# Stable Flutter dev run — avoids Windows Temp flutter_tools races (app.dill PathNotFoundException).
param(
    [string[]]$FlutterArgs = @("--flavor", "development", "-t", "lib/main_development.dart")
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

& "$ProjectRoot\tool\flutter_prepare.ps1" | Out-Null

$dartProcs = @(Get-Process -Name dart -ErrorAction SilentlyContinue)
if ($dartProcs.Count -gt 0) {
    Write-Host "Stopping $($dartProcs.Count) stale dart process(es)..."
    $dartProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Set-Location $ProjectRoot
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$tokenFile = Join-Path $PSScriptRoot "app_check_debug_token.local"
$extraDefines = @()
if (Test-Path $tokenFile) {
    $token = (Get-Content -Path $tokenFile -Raw).Trim()
    if ($token) {
        $extraDefines += "--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=$token"
    }
}

Write-Host "Running: flutter run $($FlutterArgs -join ' ') $($extraDefines -join ' ')"
flutter run @FlutterArgs @extraDefines
exit $LASTEXITCODE
