# One-time setup: redirect Windows user TMP/TEMP to project-stable folder on D: drive.
# Run once, then reload Cursor/VS Code. Reverts with -Revert.
param([switch]$Revert)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$StableTmp = Join-Path $ProjectRoot ".tmp"
$DefaultTmp = Join-Path $env:LOCALAPPDATA "Temp"

New-Item -ItemType Directory -Force -Path $StableTmp | Out-Null

if ($Revert) {
    [Environment]::SetEnvironmentVariable("TMP", $DefaultTmp, "User")
    [Environment]::SetEnvironmentVariable("TEMP", $DefaultTmp, "User")
    Write-Host "Reverted user TMP/TEMP to $DefaultTmp"
    exit 0
}

[Environment]::SetEnvironmentVariable("TMP", $StableTmp, "User")
[Environment]::SetEnvironmentVariable("TEMP", $StableTmp, "User")
$env:TMP = $StableTmp
$env:TEMP = $StableTmp

Write-Host "User TMP/TEMP set to $StableTmp"
Write-Host "Reload Cursor (Developer: Reload Window) so all Dart/Flutter processes pick up the new temp path."
