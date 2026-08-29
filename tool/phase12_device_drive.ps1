# Phase 12 — Physical device WYM drive helper (development = mevora-d6ed0)
param(
  [ValidateSet('success', 'empty', 'offline', 'locale-tr', 'locale-en')]
  [string]$Mode = 'success',
  [string]$DeviceId = 'R68T305S3VM'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$adb = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
$token = (Get-Content (Join-Path $root 'tool\app_check_debug_token.local') -Raw).Trim()
$fixturePath = Join-Path $root 'integration_test\fixtures\why_you_matched_device_qa.local.json'
if (-not (Test-Path $fixturePath)) {
  throw "Missing fixture $fixturePath — run whyYouMatchedPhase11DeviceFixture.cjs"
}
$fixture = Get-Content $fixturePath -Raw | ConvertFrom-Json

$driveMode = $Mode
if ($Mode -eq 'locale-tr' -or $Mode -eq 'locale-en') {
  $driveMode = 'success'
}

function Set-DeviceLocale([string]$LocaleTag) {
  & $adb -s $DeviceId shell "settings put system system_locales $LocaleTag"
  & $adb -s $DeviceId shell "am force-stop com.mevora.app"
  Start-Sleep -Seconds 2
}

function Set-DeviceNetwork([bool]$Online) {
  if ($Online) {
    & $adb -s $DeviceId shell "svc wifi enable"
    & $adb -s $DeviceId shell "svc data enable"
  } else {
    & $adb -s $DeviceId shell "svc wifi disable"
    & $adb -s $DeviceId shell "svc data disable"
  }
  Start-Sleep -Seconds 3
}

$outLog = Join-Path $root "tool\phase12_device_$Mode.txt"

if ($Mode -eq 'locale-tr') { Set-DeviceLocale 'tr-TR' }
if ($Mode -eq 'locale-en') { Set-DeviceLocale 'en-US' }

if ($Mode -eq 'offline') {
  # Start online for login, then cut network after auth (handled by background job timing).
  Set-DeviceNetwork $true
}

$defines = @(
  "--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=$token",
  "--dart-define=WYM_DEVICE_EMAIL_A=$($fixture.emailA)",
  "--dart-define=WYM_DEVICE_PASSWORD=$($fixture.password)",
  "--dart-define=WYM_DEVICE_NAME_B=$($fixture.displayNameB)",
  "--dart-define=WYM_DEVICE_NAME_EMPTY=WYM_EMPTY_B",
  "--dart-define=WYM_DEVICE_PROJECT=mevora-d6ed0",
  "--dart-define=WYM_DEVICE_MODE=$driveMode"
)

$args = @(
  'drive',
  '--driver=test_driver/integration_test.dart',
  '--target=integration_test/matching/why_you_matched_device_phase12_e2e_test.dart',
  '-d', $DeviceId,
  '-t', 'lib/main_development.dart'
) + $defines

Write-Host "PHASE12_DRIVE mode=$Mode driveMode=$driveMode device=$DeviceId"
Write-Host "LOG=$outLog"

if ($Mode -eq 'offline') {
  # After ~45s (bootstrap+login), disable network; restore after another 40s for retry.
  Start-Job -ScriptBlock {
    param($Adb, $Id)
    Start-Sleep -Seconds 45
    & $Adb -s $Id shell "svc wifi disable"
    & $Adb -s $Id shell "svc data disable"
    Start-Sleep -Seconds 50
    & $Adb -s $Id shell "svc wifi enable"
    & $Adb -s $Id shell "svc data enable"
  } -ArgumentList $adb, $DeviceId | Out-Null
}

& flutter @args *> $outLog
$code = $LASTEXITCODE

# Always restore network/locale-ish connectivity.
Set-DeviceNetwork $true

Write-Host "EXIT=$code"
exit $code
