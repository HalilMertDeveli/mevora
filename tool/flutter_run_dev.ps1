# Stable Flutter dev run — avoids Windows Temp flutter_tools races (app.dill PathNotFoundException).
param(
    [string[]]$FlutterArgs = @("--flavor", "development", "-t", "lib/main_development.dart")
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$StableTmp = Join-Path $ProjectRoot ".tmp"
$LogPath = "D:\debug-80971b.log"

function Write-DebugLog {
    param([string]$HypothesisId, [string]$Location, [string]$Message, [hashtable]$Data, [string]$RunId = "terminal-run")
    $entry = @{
        sessionId    = "80971b"
        runId        = $RunId
        hypothesisId = $HypothesisId
        location     = $Location
        message      = $Message
        data         = $Data
        timestamp    = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Compress
    Add-Content -Path $LogPath -Value $entry -Encoding utf8
}

# #region agent log
& "$ProjectRoot\tool\flutter_prepare.ps1" | Out-Null

$dartProcs = @(Get-Process -Name dart -ErrorAction SilentlyContinue)
Write-DebugLog -HypothesisId "A" -Location "tool/flutter_run_dev.ps1:entry" -Message "pre_run_state" -Data @{
    dartProcessCount = $dartProcs.Count
    stableTmp        = $StableTmp
    envTmp           = $env:TMP
}

if ($dartProcs.Count -gt 0) {
    Write-Host "Stopping $($dartProcs.Count) stale dart process(es)..."
    $dartProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
# #endregion

Set-Location $ProjectRoot
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Running: flutter run $($FlutterArgs -join ' ')"
flutter run @FlutterArgs
$exitCode = $LASTEXITCODE

# #region agent log
$appDill = Get-ChildItem $StableTmp -Recurse -Filter "app.dill" -ErrorAction SilentlyContinue | Select-Object -First 1
Write-DebugLog -HypothesisId "C" -Location "tool/flutter_run_dev.ps1:exit" -Message "flutter_run_finished" -Data @{
    exitCode    = $exitCode
    appDillPath = $appDill.FullName
    appDillOnD  = ($null -ne $appDill -and $appDill.FullName -like "D:\Mevora\.tmp*")
}
# #endregion

exit $exitCode
