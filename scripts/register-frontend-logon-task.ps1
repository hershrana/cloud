<#
    register-frontend-logon-task - Creates (or updates) a Windows Scheduled Task
    that opens the rp_app frontend in the default browser whenever the current
    Windows user logs in.

    Usage:
        # Register with defaults (opens both jira URLs at logon for current user)
        .\register-frontend-logon-task.ps1

        # Open different URLs / name the task differently
        .\register-frontend-logon-task.ps1 -Urls "https://137.23.42.212/todo/" -TaskName "OpenTodoApp"

        # Remove the task
        .\register-frontend-logon-task.ps1 -Unregister

    Notes:
        - No admin rights needed: the task runs as the interactive user only.
        - Re-running re-creates the task (idempotent).
        - URLs open in the Windows default browser (Chrome, as currently set).
#>
[CmdletBinding()]
param(
    [string[]]$Urls    = @("https://137.23.42.212/todo/", "https://137.23.42.212/jira/populate"),
    [string]$TaskName  = "OpenRpAppFrontend",
    [int]$DelaySeconds = 10,
    [switch]$Unregister
)

$ErrorActionPreference = "Stop"

# --- Handle removal -------------------------------------------------------
if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task '$TaskName'." -ForegroundColor Yellow
    } else {
        Write-Host "No scheduled task named '$TaskName' found." -ForegroundColor DarkGray
    }
    return
}

# --- Build the task -------------------------------------------------------
# Launch each URL via cmd's `start` so it opens in the user's DEFAULT browser.
$startCmds = ($Urls | ForEach-Object { "start `"`" `"$_`"" }) -join " & "
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $startCmds"

# Trigger: at logon of the current user only.
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Small delay so the network/desktop is ready before the browser opens.
if ($DelaySeconds -gt 0) {
    $trigger.Delay = "PT${DelaySeconds}S"
}

# Run in the interactive user's context, no elevation.
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

# Sensible settings: don't stop on battery, allow start when idle, etc.
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

# --- Register (overwrite if it already exists) ---------------------------
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Opens the rp_app frontend ($($Urls -join ', ')) in the default browser at user logon." `
    -Force | Out-Null

Write-Host "Registered scheduled task '$TaskName'." -ForegroundColor Green
Write-Host "  URLs:    $($Urls -join ', ')"
Write-Host "  Trigger: At logon of $env:USERNAME (delay ${DelaySeconds}s)"
Write-Host ""
Write-Host "Verify with:  Get-ScheduledTask -TaskName '$TaskName' | Format-List" -ForegroundColor DarkGray
Write-Host "Test now:     Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor DarkGray
