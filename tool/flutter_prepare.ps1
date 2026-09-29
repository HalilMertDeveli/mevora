# Pre-launch prep: ensure stable temp dir exists for Flutter tooling.
$ErrorActionPreference = "SilentlyContinue"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$StableTmp = Join-Path $ProjectRoot ".tmp"

New-Item -ItemType Directory -Force -Path $StableTmp | Out-Null
$env:TMP = $StableTmp
$env:TEMP = $StableTmp

$userTmp = [Environment]::GetEnvironmentVariable("TMP", "User")
$userTemp = [Environment]::GetEnvironmentVariable("TEMP", "User")
$cFree = (Get-PSDrive C -ErrorAction SilentlyContinue).Free

if ($userTmp -ne $StableTmp -or $userTemp -ne $StableTmp) {
    Write-Warning "User TMP/TEMP still point to C: ($userTmp). Run: .\tool\flutter_env_setup.ps1"
}

if ($cFree -lt 3GB) {
    Write-Warning "C: drive low on space ($([math]::Round($cFree/1GB,2)) GB free). Flutter may fail."
}

# Inject registered App Check debug token (gitignored local file).
$tokenFile = Join-Path $PSScriptRoot "app_check_debug_token.local"
if (Test-Path $tokenFile) {
    $token = (Get-Content -Path $tokenFile -Raw).Trim()
    if ($token) {
        $env:FIREBASE_APP_CHECK_DEBUG_TOKEN = $token
        $define = "--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=$token"
        if (-not $env:FLUTTER_TOOL_ARGS) {
            $env:FLUTTER_TOOL_ARGS = $define
        } elseif ($env:FLUTTER_TOOL_ARGS -notlike "*FIREBASE_APP_CHECK_DEBUG_TOKEN*") {
            $env:FLUTTER_TOOL_ARGS = "$($env:FLUTTER_TOOL_ARGS) $define"
        }
    }
}

# Android 16 put local network access behind a runtime permission, and runtime
# permissions start denied. Without it the app sandbox cannot reach the
# Firebase Emulator Suite on 10.0.2.2 at all -- adb shell still can, so it
# looks like firebase_auth/network-request-failed or "check your internet
# connection" rather than a missing permission. Granting it here keeps the
# emulator launch configuration working straight from F5.
#
# Debug builds only: the permission is declared in the debug source set.
$adb = Join-Path $env:LOCALAPPDATA "Android\sdk\platform-tools\adb.exe"
if (Test-Path $adb) {
    $serials = & $adb devices |
        Select-String -Pattern "^(emulator-\d+)\s+device$" |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
    foreach ($serial in $serials) {
        $installed = & $adb -s $serial shell pm list packages com.mevora.app
        if ($installed) {
            & $adb -s $serial shell pm grant com.mevora.app android.permission.ACCESS_LOCAL_NETWORK 2>&1 | Out-Null
        } else {
            # This task runs before flutter installs the APK, so a fresh AVD
            # has nothing to grant yet. MainActivity asks for the permission
            # itself on first launch; accept the dialog to reach 10.0.2.2.
            Write-Warning ("com.mevora.app is not installed on $serial yet, so ACCESS_LOCAL_NETWORK " +
                "cannot be granted before this launch. The app will ask for it on first launch " +
                "(allow the nearby devices dialog); or run: " +
                "adb -s $serial shell pm grant com.mevora.app android.permission.ACCESS_LOCAL_NETWORK " +
                "and restart the app.")
        }
    }
}

exit 0
