# Clean rebuild + install Mevora development debug on connected Android device(s).
# Ensures physical phones get the same flavor, Firebase project, and dart-defines as the emulator.
param(
    [string]$DeviceId = "",
    [switch]$UninstallFirst,
    [switch]$GrantPermissions,
    [switch]$AllAndroid
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$StableTmp = Join-Path $ProjectRoot ".tmp"
New-Item -ItemType Directory -Force -Path $StableTmp | Out-Null
$env:TMP = $StableTmp
$env:TEMP = $StableTmp

$tokenFile = Join-Path $PSScriptRoot "app_check_debug_token.local"
$appCheckToken = ""
if (Test-Path $tokenFile) {
    $appCheckToken = (Get-Content -Path $tokenFile -Raw).Trim()
}

$defines = @(
    "--dart-define=USE_EMULATORS=false",
    "--dart-define=SPOTIFY_CLIENT_ID=b0a808c4c2264b0ba179c2045a8d3445"
)
if ($appCheckToken) {
    $defines += "--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=$appCheckToken"
}

Write-Host "Building development debug APK with live Firebase (mevora-d6ed0)..."
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter build apk --debug --flavor development -t lib/main_development.dart @defines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apk = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-development-debug.apk"
if (-not (Test-Path $apk)) {
    Write-Error "APK missing: $apk"
    exit 1
}

$adb = Join-Path $env:LOCALAPPDATA "Android\sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = "adb"
}

$devices = @()
$raw = & $adb devices
foreach ($line in $raw) {
    if ($line -match "^(\S+)\s+device$") {
        $devices += $Matches[1]
    }
}

if ($DeviceId) {
    $targets = @($DeviceId)
} elseif ($AllAndroid) {
    $targets = $devices
} else {
    # Prefer a physical device when multiple are connected.
    $physical = $devices | Where-Object { $_ -notlike "emulator-*" }
    if ($physical.Count -ge 1) {
        $targets = @($physical[0])
    } elseif ($devices.Count -ge 1) {
        $targets = @($devices[0])
    } else {
        Write-Error "No Android devices connected."
        exit 1
    }
}

$runtimePerms = @(
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.CAMERA",
    "android.permission.RECORD_AUDIO",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.READ_MEDIA_IMAGES"
)

foreach ($serial in $targets) {
    Write-Host "=== Target $serial ==="
    if ($UninstallFirst) {
        Write-Host "Uninstalling com.mevora.app..."
        & $adb -s $serial uninstall com.mevora.app 2>$null | Out-Null
        & $adb -s $serial uninstall com.mevora.app.dev 2>$null | Out-Null
    }
    Write-Host "Installing $apk ..."
    & $adb -s $serial install -r $apk
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if ($GrantPermissions) {
        foreach ($perm in $runtimePerms) {
            & $adb -s $serial shell pm grant com.mevora.app $perm 2>$null | Out-Null
        }
        Write-Host "Runtime permissions granted (QA)."
    }

    $info = & $adb -s $serial shell dumpsys package com.mevora.app
    $version = ($info | Select-String -Pattern "versionName=" | Select-Object -First 1).ToString().Trim()
    Write-Host "Installed: $version"
}

Write-Host "Done. Launch Mevora Dev and verify Firebase project mevora-d6ed0."
exit 0
