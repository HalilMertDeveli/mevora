# FAZ 7.2 — Emulator AdMob E2E host runner (adb dismiss helper).
param(
  [string]$DeviceId = "emulator-5554",
  [string]$Flavor = "staging"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$env:Path = "$env:LOCALAPPDATA\Android\Sdk\platform-tools;C:\Users\clt\src\flutter\bin;$env:Path"

$devices = & flutter devices 2>&1 | Out-String
if ($devices -notmatch [regex]::Escape($DeviceId)) {
  throw "Android emulator $DeviceId not found.`n$devices"
}
if ($devices -match "R68T305S3VM") {
  Write-Host "FAZ72_NOTE physical device present but NOT USED"
}

Write-Host "FAZ72_DEVICE=$DeviceId"
Write-Host "FAZ72_PHYSICAL=NOT_USED"

adb -s $DeviceId shell wm density 420 | Out-Null
adb -s $DeviceId shell wm size 1080x2400 | Out-Null

$apk = Join-Path $root "build\app\outputs\flutter-apk\app-$Flavor-debug.apk"
if (-not (Test-Path $apk)) {
  & flutter build apk --debug --flavor $Flavor
  if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
}
& adb -s $DeviceId install -r $apk

$logPath = Join-Path $root "tool\faz72_emulator_e2e.txt"
"" | Set-Content -Path $logPath

function Dismiss-AdMob([string]$Serial) {
  adb -s $Serial shell input tap 1000 160 | Out-Null
  Start-Sleep -Milliseconds 350
  adb -s $Serial shell input tap 1020 200 | Out-Null
  Start-Sleep -Milliseconds 350
  adb -s $Serial shell input tap 960 120 | Out-Null
  Start-Sleep -Milliseconds 350
  adb -s $Serial shell input keyevent 4 | Out-Null
}

$flutterCmd = "flutter test integration_test/humor/humor_admob_monetization_e2e_test.dart -d $DeviceId --flavor $Flavor --dart-define=HUMOR_LAB_ENABLED=true --dart-define=ADMOB_USE_TEST_ADS=true"
$proc = Start-Process -FilePath "powershell" -ArgumentList @(
  "-NoProfile", "-Command",
  "$flutterCmd 2>&1 | Tee-Object -FilePath '$logPath'"
) -PassThru -WindowStyle Hidden

$dismissed = 0
$seenMarkers = New-Object 'System.Collections.Generic.HashSet[string]'
$deadline = (Get-Date).AddMinutes(12)

while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
  if (Test-Path $logPath) {
    $lines = Get-Content -Path $logPath -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
      if ($line -match "FAZ72_NEED_DISMISS cycle=(\d+)") {
        $marker = $Matches[0]
        if ($seenMarkers.Add($marker)) {
          Start-Sleep -Seconds 3
          Dismiss-AdMob $DeviceId
          Start-Sleep -Seconds 1
          Dismiss-AdMob $DeviceId
          $dismissed++
          $msg = "FAZ72_HOST_DISMISS count=$dismissed for $marker"
          Add-Content -Path $logPath -Value $msg
          Write-Host $msg
        }
      }
    }
  }
  Start-Sleep -Milliseconds 500
}

if (-not $proc.HasExited) {
  Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  throw "FAZ72 emulator E2E timed out"
}

Wait-Process -Id $proc.Id -ErrorAction SilentlyContinue
$exit = $proc.ExitCode
if ($null -eq $exit) { $exit = 1 }

Write-Host "FAZ72_HOST_DISMISS_TOTAL=$dismissed"
Write-Host "FAZ72_EXIT=$exit"
Get-Content $logPath | Select-String -Pattern "FAZ72_|All tests|Some tests|\[E\]" | ForEach-Object { $_.Line }
exit $exit
