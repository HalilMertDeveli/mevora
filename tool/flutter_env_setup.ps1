# One-time setup: redirect Windows user TMP/TEMP to project-stable folder on D: drive.
# Run once, then reload Cursor/VS Code. Reverts with -Revert.
param([switch]$Revert)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$StableTmp = Join-Path $ProjectRoot ".tmp"
$LogPath = "D:\debug-80971b.log"
$DefaultTmp = Join-Path $env:LOCALAPPDATA "Temp"

New-Item -ItemType Directory -Force -Path $StableTmp | Out-Null

function Write-DebugLog {
    param([string]$Message, [hashtable]$Data)
    $entry = @{
        sessionId    = "80971b"
        runId        = "env-setup"
        hypothesisId = "G"
        location     = "tool/flutter_env_setup.ps1"
        message      = $Message
        data         = $Data
        timestamp    = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Compress
    Add-Content -Path $LogPath -Value $entry -Encoding utf8
}

if ($Revert) {
    [Environment]::SetEnvironmentVariable("TMP", $DefaultTmp, "User")
    [Environment]::SetEnvironmentVariable("TEMP", $DefaultTmp, "User")
    Write-Host "Reverted user TMP/TEMP to $DefaultTmp"
    Write-DebugLog -Message "env_reverted" -Data @{ tmp = $DefaultTmp }
    exit 0
}

[Environment]::SetEnvironmentVariable("TMP", $StableTmp, "User")
[Environment]::SetEnvironmentVariable("TEMP", $StableTmp, "User")
$env:TMP = $StableTmp
$env:TEMP = $StableTmp

Write-Host "User TMP/TEMP set to $StableTmp"
Write-Host "Reload Cursor (Developer: Reload Window) so all Dart/Flutter processes pick up the new temp path."
Write-DebugLog -Message "env_configured" -Data @{
    userTmp  = [Environment]::GetEnvironmentVariable("TMP", "User")
    userTemp = [Environment]::GetEnvironmentVariable("TEMP", "User")
    stableTmp = $StableTmp
}
