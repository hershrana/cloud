<#
    Deploy-App - Builds an app locally and ships it to the OCI boxes over SSH,
    doing what a GitHub Actions deploy workflow would do but on this machine
    (no runner minutes, no artifact storage quota).

    The script itself is generic. What to build lives in scripts\deploy\<app>.psd1;
    where to send it lives in scripts\deploy\tenants\<tenant>.psd1. Splitting the
    two is what lets one app deploy to several OCI tenants: the app config names
    a box by role ('app', 'nginx'), and the tenant supplies that role's address,
    SSH key and user.

    Usage:
        .\Deploy-App.ps1 jira -Tenant purvi     # build, then deploy every target
        .\Deploy-App.ps1 jira -Tenant purvi -DryRun    # print commands, run none
        .\Deploy-App.ps1 jira -Tenant purvi -SkipBuild # reuse the last build
        .\Deploy-App.ps1 jira -Tenant purvi -Target backend
        .\Deploy-App.ps1 -ListTenants           # show configured tenants
        .\Deploy-App.ps1 -Config D:\other.psd1 -Tenant purvi

    The tenant may be left off when the app config sets DefaultTenant, or when
    $env:OCI_TENANT is set. An explicit -Tenant always wins.

    Requirements:
        - ssh.exe / scp.exe  (Windows OpenSSH client, built in on Win10+)
        - tar.exe            (bsdtar, built in on Win10+; only for SourceDir targets)
        - whatever the app's own build needs (JDK, Node, ...)

    See scripts\deploy\jira.psd1 for a commented example config.
#>
[CmdletBinding()]
param(
    # App name; resolves to scripts\deploy\<App>.psd1. Ignored when -Config is given.
    [Parameter(Position = 0)]
    [string]$App,

    # Explicit path to a config file, for configs kept outside scripts\deploy.
    [string]$Config,

    # Which OCI tenant to deploy to; resolves to scripts\deploy\tenants\<Tenant>.psd1.
    # Falls back to the app config's DefaultTenant, then to $env:OCI_TENANT.
    [string]$Tenant,

    # Print the configured tenants and exit.
    [switch]$ListTenants,

    # Deploy only the named target(s) from the config's Deploy list.
    [string[]]$Target,

    # Reuse whatever is already in the build output directories.
    [switch]$SkipBuild,

    # Print every build and remote command without executing any of them.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- helpers ---

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# Runs a native command and aborts on a non-zero exit code. PowerShell does not
# throw on native failures the way it does on cmdlet errors, so every external
# call has to be checked by hand or a failed build silently "succeeds".
function Invoke-Native {
    param(
        [string]$Command,
        [string]$What
    )
    Write-Host "    $Command" -ForegroundColor DarkGray
    if ($DryRun) { return }

    Invoke-Expression $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed (exit $LASTEXITCODE): $Command"
    }
}

# Quotes a string for the bash running on the far side of ssh, not for PowerShell.
function ConvertTo-RemoteArg {
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

# A .psd1 holds literal data only, so it cannot look anything up itself. The
# "env:NAME" form lets a config name an environment variable instead of the
# value -- which is what keeps box addresses and key paths out of this repo,
# since hershrana/cloud is public.
function Resolve-ConfigValue {
    param(
        [string]$Value,
        [string]$Field
    )
    if ($Value -notmatch '^env:(.+)$') { return $Value }

    $varName = $Matches[1]
    $resolved = [Environment]::GetEnvironmentVariable($varName)
    if (-not $resolved) {
        throw "$Field is 'env:$varName' but `$env:$varName is not set. Set it first (see scripts\deploy\README.md)."
    }
    return $resolved
}

# Expands {{token}} placeholders from the tenant's Vars, so one app config can
# describe boxes whose service accounts or paths differ between tenants.
function Expand-Vars {
    param(
        [string]$Value,
        [hashtable]$Vars,
        [string]$Field
    )
    if (-not $Value) { return $Value }

    # Checked up front rather than inside a MatchEvaluator, because an exception
    # thrown from the callback reaches the caller wrapped in regex plumbing and
    # buries the actual message.
    foreach ($m in [regex]::Matches($Value, '\{\{(\w+)\}\}')) {
        $key = $m.Groups[1].Value
        if (-not $Vars.ContainsKey($key)) {
            $known = @($Vars.Keys) -join ', '
            throw "$Field uses {{$key}}, which the tenant does not define. It has: $known"
        }
    }

    return [regex]::Replace($Value, '\{\{(\w+)\}\}', { param($m) [string]$Vars[$m.Groups[1].Value] })
}

$tenantDir = Join-Path $PSScriptRoot 'deploy\tenants'

function Get-TenantNames {
    return @(Get-ChildItem -Path $tenantDir -Filter '*.psd1' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.BaseName })
}

# ----------------------------------------------------------- list tenants ---

if ($ListTenants) {
    $names = Get-TenantNames
    if (-not $names) {
        Write-Host "No tenants configured in $tenantDir" -ForegroundColor Yellow
        return
    }
    Write-Host "Tenants in $tenantDir" -ForegroundColor Cyan
    foreach ($n in $names) {
        $t = Import-PowerShellDataFile -Path (Join-Path $tenantDir "$n.psd1")
        $roles = @($t.Hosts.Keys) -join ', '
        Write-Host ("  {0,-12} roles: {1}" -f $n, $roles)
    }
    return
}

# ------------------------------------------------------------ load config ---

if (-not $Config) {
    if (-not $App) {
        $available = Get-ChildItem -Path (Join-Path $PSScriptRoot 'deploy') -Filter '*.psd1' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.BaseName }
        if ($available) {
            throw "Specify an app. Available: $($available -join ', ')"
        }
        throw "Specify an app (-App) or a config file (-Config)."
    }
    $Config = Join-Path $PSScriptRoot "deploy\$App.psd1"
}

if (-not (Test-Path $Config)) {
    throw "Config not found: $Config"
}

$cfg = Import-PowerShellDataFile -Path $Config
Write-Host "Config: $Config" -ForegroundColor DarkGray

$repoPath = Resolve-ConfigValue -Value $cfg.RepoPath -Field 'RepoPath'
if (-not (Test-Path $repoPath)) {
    throw "RepoPath does not exist: $repoPath  (clone it first, or fix the config)"
}
$repoPath = (Resolve-Path $repoPath).Path

# ----------------------------------------------------------- load tenant ---

# Explicit flag beats the app's default, which beats the ambient env var. The
# env var is last so that setting it for convenience can never silently
# redirect a deploy that named its tenant.
$tenantName = $Tenant
if (-not $tenantName) { $tenantName = $cfg.DefaultTenant }
if (-not $tenantName) { $tenantName = $env:OCI_TENANT }
if (-not $tenantName) {
    $names = Get-TenantNames
    throw "No tenant selected. Pass -Tenant, or set DefaultTenant in the config, or set `$env:OCI_TENANT. Available: $($names -join ', ')"
}

$tenantFile = Join-Path $tenantDir "$tenantName.psd1"
if (-not (Test-Path $tenantFile)) {
    $names = Get-TenantNames
    throw "Unknown tenant '$tenantName'. Available: $($names -join ', ')"
}
$tenantCfg = Import-PowerShellDataFile -Path $tenantFile

$tenantVars = @{}
if ($tenantCfg.Vars) { $tenantVars = $tenantCfg.Vars }

# The tenant owns the credentials, because the key is a property of the account
# the boxes live in, not of the app being shipped. An app config may still set
# SshKey as a fallback for a tenant that does not.
$sshKeyRaw = $tenantCfg.SshKey
if (-not $sshKeyRaw) { $sshKeyRaw = $cfg.SshKey }
if (-not $sshKeyRaw) { throw "Tenant '$tenantName' defines no SshKey, and neither does the app config." }

# ~ is a PowerShell-ism that ssh.exe on Windows does not expand itself.
$sshKey = Resolve-ConfigValue -Value $sshKeyRaw -Field "Tenant '$tenantName' SshKey"
$sshKey = $sshKey -replace '^~', $HOME
if (-not (Test-Path $sshKey)) {
    throw "SSH key not found: $sshKey  (tenant '$tenantName')"
}

$sshUser = $tenantCfg.User
if (-not $sshUser) { $sshUser = $cfg.User }
if (-not $sshUser) { $sshUser = 'opc' }

# accept-new trusts a host the first time and pins it after, which keeps an
# unattended run from hanging on an interactive prompt without going as far as
# disabling host-key checking altogether.
$sshOpts = @('-i', $sshKey, '-o', 'StrictHostKeyChecking=accept-new')
$sshOptsText = $sshOpts -join ' '

Write-Host "App:    $($cfg.Name)" -ForegroundColor DarkGray
Write-Host "Tenant: $tenantName" -ForegroundColor Yellow
Write-Host "Repo:   $repoPath" -ForegroundColor DarkGray
Write-Host "Key:    $sshKey" -ForegroundColor DarkGray
if ($DryRun) {
    Write-Host "DRY RUN - nothing will be built, copied or restarted." -ForegroundColor Yellow
}

# ------------------------------------------------------------------ build ---

if ($SkipBuild) {
    Write-Step "Build skipped (-SkipBuild); reusing existing output"
}
elseif ($cfg.Build) {
    foreach ($step in $cfg.Build) {
        Write-Step "Build: $($step.Name)"

        $workDir = $repoPath
        if ($step.WorkingDirectory) {
            $workDir = Join-Path $repoPath $step.WorkingDirectory
        }
        if (-not (Test-Path $workDir)) {
            throw "Build '$($step.Name)': working directory not found: $workDir"
        }

        Push-Location $workDir
        try {
            foreach ($cmd in @($step.Command)) {
                Invoke-Native -Command $cmd -What "Build '$($step.Name)'"
            }
        }
        finally {
            Pop-Location
        }
    }
}

# ----------------------------------------------------------------- deploy ---

$targets = @($cfg.Deploy)
if ($Target) {
    $targets = @($targets | Where-Object { $Target -contains $_.Name })
    if (-not $targets) {
        $names = @($cfg.Deploy) | ForEach-Object { $_.Name }
        throw "No deploy target matched. Config has: $($names -join ', ')"
    }
}

# Uploads land in the remote /tmp and are moved into place by the remote
# command, because the deploy user cannot write to /opt or /var/www directly
# and scp cannot run under sudo.
foreach ($t in $targets) {
    # A target names a box by role ('app', 'nginx') and the tenant resolves it.
    # HostName stays supported as an escape hatch for a one-off box that no
    # tenant lists.
    if ($t.Role) {
        if (-not $tenantCfg.Hosts -or -not $tenantCfg.Hosts.ContainsKey($t.Role)) {
            $known = @($tenantCfg.Hosts.Keys) -join ', '
            throw "Deploy '$($t.Name)' wants role '$($t.Role)', which tenant '$tenantName' does not define. It has: $known"
        }
        $hostName = Resolve-ConfigValue -Value $tenantCfg.Hosts[$t.Role] `
                                        -Field "Tenant '$tenantName' host '$($t.Role)'"
    }
    elseif ($t.HostName) {
        $hostName = Resolve-ConfigValue -Value $t.HostName -Field "Deploy '$($t.Name)'.HostName"
    }
    else {
        throw "Deploy '$($t.Name)' sets neither Role nor HostName."
    }

    Write-Step "Deploy: $($t.Name)  ->  $tenantName/$($t.Role) ($hostName)"

    $user = $t.User
    if (-not $user) { $user = $sshUser }
    $dest = "$user@$hostName"

    $localFile = $null
    $tempArchive = $null

    if ($t.SourceDir) {
        # A directory target (a frontend bundle) is tarred first; scp -r would
        # work but would copy thousands of small files one round trip each.
        $srcDir = Join-Path $repoPath $t.SourceDir
        if (-not (Test-Path $srcDir)) {
            if (-not $DryRun) {
                throw "Deploy '$($t.Name)': source directory not found: $srcDir  (did the build run?)"
            }
            Write-Host "    ($srcDir does not exist yet)" -ForegroundColor Yellow
        }
        $tempArchive = Join-Path ([System.IO.Path]::GetTempPath()) "deploy-$($cfg.Name)-$tenantName-$($t.Name).tgz"
        Write-Host "    packing $srcDir" -ForegroundColor DarkGray
        if (-not $DryRun) {
            tar -C $srcDir -czf $tempArchive .
            if ($LASTEXITCODE -ne 0) {
                throw "Deploy '$($t.Name)': tar failed (exit $LASTEXITCODE)"
            }
        }
        $localFile = $tempArchive
    }
    else {
        # A file target (a jar) is usually a glob, since the version is in the
        # filename. Newest wins if the output dir was never cleaned.
        $found = @(Get-ChildItem -Path (Join-Path $repoPath $t.Source) -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if (-not $found) {
            if (-not $DryRun) {
                throw "Deploy '$($t.Name)': nothing matched $($t.Source)  (did the build run?)"
            }
            Write-Host "    (nothing matches $($t.Source) yet)" -ForegroundColor Yellow
            $localFile = Join-Path $repoPath $t.Source
        }
        else {
            if ($found.Count -gt 1) {
                Write-Host "    $($found.Count) matches; using newest: $($found[0].Name)" -ForegroundColor Yellow
            }
            $localFile = $found[0].FullName
        }
    }

    # Both sides are expanded before anything is uploaded, so an unresolved
    # {{var}} fails while the box is still untouched rather than after a file
    # has already landed in /tmp.
    $staging = Expand-Vars -Value $t.Staging -Vars $tenantVars -Field "Deploy '$($t.Name)'.Staging"
    $remoteParts = @($t.Remote) | ForEach-Object {
        Expand-Vars -Value $_ -Vars $tenantVars -Field "Deploy '$($t.Name)'.Remote"
    }
    $remoteCmd = ConvertTo-RemoteArg ($remoteParts -join ' && ')

    Invoke-Native -Command "scp $sshOptsText `"$localFile`" `"${dest}:$staging`"" `
                  -What "Deploy '$($t.Name)': upload"
    Invoke-Native -Command "ssh $sshOptsText $dest $remoteCmd" `
                  -What "Deploy '$($t.Name)': remote command"

    if ($tempArchive -and (Test-Path $tempArchive)) {
        Remove-Item $tempArchive -Force
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
