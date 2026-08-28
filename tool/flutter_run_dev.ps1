# Stable Flutter dev run — avoids Windows Temp flutter_tools races (app.dill PathNotFoundException).
# Prefer: tool\flutter_run_dev.cmd (bypasses ExecutionPolicy).
param(
    [string]$DeviceId = "",
    [string[]]$FlutterArgs = @()
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$StableTmp = Join-Path $ProjectRoot ".tmp"
New-Item -ItemType Directory -Force -Path $StableTmp | Out-Null
$env:TMP = $StableTmp
$env:TEMP = $StableTmp

& powershell -NoProfile -ExecutionPolicy Bypass -File "$ProjectRoot\tool\flutter_prepare.ps1" | Out-Null

$dartProcs = @(Get-Process -Name dart -ErrorAction SilentlyContinue)
if ($dartProcs.Count -gt 0) {
    Write-Host "Stopping $($dartProcs.Count) stale dart process(es)..."
    $dartProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Set-Location $ProjectRoot
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($FlutterArgs.Count -eq 0) {
    $FlutterArgs = @(
        "--flavor", "development",
        "-t", "lib/main_development.dart",
        "--dart-define=USE_EMULATORS=false",
        "--dart-define=SPOTIFY_CLIENT_ID=b0a808c4c2264b0ba179c2045a8d3445"
    )
}

$tokenFile = Join-Path $PSScriptRoot "app_check_debug_token.local"
$extraDefines = @()
if (Test-Path $tokenFile) {
    $token = (Get-Content -Path $tokenFile -Raw).Trim()
    if ($token -and ($FlutterArgs -join " ") -notlike "*FIREBASE_APP_CHECK_DEBUG_TOKEN*") {
        $extraDefines += "--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=$token"
    }
}

# Prefer physical USB device when -d is omitted and multiple Android targets exist.
if ($DeviceId) {
    $FlutterArgs = @("-d", $DeviceId) + $FlutterArgs
} elseif (($FlutterArgs -join " ") -notmatch "(^|\s)-d(\s|$)") {
    $adb = Join-Path $env:LOCALAPPDATA "Android\sdk\platform-tools\adb.exe"
    if (Test-Path $adb) {
        $serials = @()
        foreach ($line in (& $adb devices)) {
            if ($line -match "^(\S+)\s+device$") { $serials += $Matches[1] }
        }
        $physical = @($serials | Where-Object { $_ -notlike "emulator-*" })
        if ($physical.Count -ge 1) {
            Write-Host "Selecting physical device $($physical[0]) (override with -DeviceId)."
            $FlutterArgs = @("-d", $physical[0]) + $FlutterArgs
        }
    }
}

Write-Host "Running: flutter run $($FlutterArgs -join ' ') $($extraDefines -join ' ')"
flutter run @FlutterArgs @extraDefines
exit $LASTEXITCODE
