# Stable Flutter dev run — avoids Windows Temp flutter_tools races (app.dill PathNotFoundException).
# Prefer: tool\flutter_run_dev.cmd (bypasses ExecutionPolicy).
param(
    [string]$DeviceId = "",
    # Collected as remaining arguments so each token survives the trip through
    # flutter_run_dev.cmd. That wrapper calls `powershell -File`, which has no
    # array support: `-FlutterArgs "--flavor","development"` arrives as the
    # single string `--flavor,development`, and flutter then goes looking for a
    # target file by that name. Collecting the tail keeps tokens separate, and
    # `-FlutterArgs a,b,c` still works when calling the .ps1 from PowerShell.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs = @()
)

# One comma-joined argument is the .cmd symptom described above. Split it back
# apart rather than failing on something the caller cannot see from their
# command line.
if ($FlutterArgs.Count -eq 1 -and $FlutterArgs[0] -match ",") {
    $FlutterArgs = @($FlutterArgs[0].Split(",") | Where-Object { $_ -ne "" })
}

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

$defaultArgs = @(
    "--flavor", "development",
    "-t", "lib/main_development.dart",
    "--dart-define=USE_EMULATORS=false",
    "--dart-define=SPOTIFY_CLIENT_ID=a937aa81f01645f78c5ba8c174c800d1"
)

if ($FlutterArgs.Count -eq 0) {
    $FlutterArgs = $defaultArgs
} elseif (-not ($FlutterArgs -match "^(--flavor|-t|--target)$")) {
    # Only extra --dart-defines were passed. Adding one should not silently
    # drop the flavor and entrypoint — a flavourless build picks a different
    # google-services.json, which is a confusing way to fail. Naming a flavor
    # or target still takes over completely.
    $FlutterArgs = $defaultArgs + $FlutterArgs
}

$tokenFile = Join-Path $PSScriptRoot "app_check_debug_token.local"
$extraDefines = @()
$tokenSupplied = ($FlutterArgs -join " ") -like "*FIREBASE_APP_CHECK_DEBUG_TOKEN*"
$token = ""
if (Test-Path $tokenFile) {
    $token = (Get-Content -Path $tokenFile -Raw).Trim()
    if ($token -and -not $tokenSupplied) {
        $extraDefines += "--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=$token"
    }
}

# Say so loudly. The token file is gitignored and per-machine, so a fresh
# worktree simply does not have it. Without a registered token App Check hands
# out an unrecognised one, every callable that enforces App Check answers 403,
# and the app looks broken for no visible reason — which is a miserable thing
# to debug from the UI.
if (-not $tokenSupplied -and -not $token) {
    Write-Host ""
    Write-Host "WARNING: no App Check debug token." -ForegroundColor Yellow
    Write-Host "  Expected: $tokenFile (gitignored, per-machine)" -ForegroundColor Yellow
    Write-Host "  Callables that enforce App Check will return 403 and the app will look broken." -ForegroundColor Yellow
    Write-Host "  Copy the token from Firebase Console > App Check > Apps > Manage debug tokens." -ForegroundColor Yellow
    Write-Host ""
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
