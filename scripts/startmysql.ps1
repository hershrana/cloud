<#
    startmysql - Opens an SSH tunnel to the OCI HeatWave MySQL (private subnet)
    through the app VM, exposing it locally on 127.0.0.1:3307.

    Usage:
        startmysql            # open tunnel (blocks; Ctrl+C to stop)
        startmysql -Port 3388 # use a different local port
#>
param(
    [int]$Port     = 3307,
    [string]$Key   = "$HOME\.ssh\rp-app-instances",
    [string]$JumpHost = "opc@137.23.42.212",
    [string]$MysqlHost = "rpapp.private.rpapp.oraclevcn.com",
    [int]$MysqlPort   = 3306
)

if (-not (Test-Path $Key)) {
    Write-Error "SSH key not found: $Key"
    exit 1
}

# Bail out early if the local port is already in use.
$inUse = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
if ($inUse) {
    Write-Warning "Port $Port is already listening (PID $($inUse.OwningProcess | Select-Object -First 1)). Tunnel may already be running."
    return
}

Write-Host "Opening MySQL tunnel: 127.0.0.1:$Port -> $MysqlHost`:$MysqlPort via $JumpHost" -ForegroundColor Cyan
Write-Host "Connect with:  jdbc:mysql://127.0.0.1:$Port/jira   (user admin)" -ForegroundColor DarkGray
Write-Host "Press Ctrl+C to stop the tunnel." -ForegroundColor DarkGray

ssh -i $Key -o StrictHostKeyChecking=accept-new -N -L "$($Port):$($MysqlHost):$($MysqlPort)" $JumpHost
