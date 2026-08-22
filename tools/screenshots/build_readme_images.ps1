# Builds PNG assets for README from real Mevora UI (adb emulator captures + login hero asset).
param(
  [string]$Adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe",
  [string]$Device = "emulator-5554"
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$dest = Join-Path $root "docs\images"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Add-Type -AssemblyName System.Drawing

function Convert-ToPng($source, $target) {
  if (-not (Test-Path $source)) {
    Write-Warning "Missing source: $source"
    return
  }
  $img = [System.Drawing.Image]::FromFile($source)
  try {
    $targetPath = Join-Path $dest $target
    $img.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "PNG $target <= $source"
  } finally {
    $img.Dispose()
  }
}

function Capture-Adb($name) {
  $targetPath = Join-Path $dest $name
  cmd /c "`"$Adb`" -s $Device exec-out screencap -p > `"$targetPath`""
  $len = (Get-Item $targetPath).Length
  if ($len -lt 1024) {
    throw "Capture too small: $name ($len bytes)"
  }
  Write-Host "ADB $name ($len bytes)"
}

function Tap($x, $y) {
  & $Adb -s $Device shell input tap $x $y | Out-Null
  Start-Sleep -Seconds 2
}

function PressBack {
  & $Adb -s $Device shell input keyevent 4 | Out-Null
  Start-Sleep -Seconds 1
}

# Sync legacy JPG docs used elsewhere in the repo.
Copy-Item (Join-Path $root "assets\images\login_background.jpg") (Join-Path $dest "login-hero.jpg") -Force
1..6 | ForEach-Object {
  $n = "{0:D2}" -f $_
  Copy-Item (Join-Path $root "assets\images\portraits\mock-$n.jpg") (Join-Path $dest "portrait-$n.jpg") -Force
}

Convert-ToPng (Join-Path $root "assets\images\login_background.jpg") "mevora-hero.png"

if (-not (Test-Path $Adb)) {
  Write-Warning "adb not found - only static PNG conversions were written."
  exit 0
}

& $Adb -s $Device shell settings put global animator_duration_scale 0 | Out-Null
& $Adb -s $Device shell settings put global transition_animation_scale 0 | Out-Null
& $Adb -s $Device shell settings put global window_animation_scale 0 | Out-Null

# Ensure app is on login (cold start).
& $Adb -s $Device shell am force-stop com.mevora.app.dev | Out-Null
& $Adb -s $Device shell monkey -p com.mevora.app.dev -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 6

Capture-Adb "mevora-login.png"

Tap 540 2100
Capture-Adb "mevora-register.png"
PressBack

Tap 540 1450
Capture-Adb "mevora-login-email.png"
PressBack

Tap 540 1680
Capture-Adb "mevora-phone.png"
PressBack

# Discovery card sample portraits shipped with the app (used on Discover cards).
Convert-ToPng (Join-Path $root "assets\images\portraits\mock-08.jpg") "mevora-discover-sample.png"
Convert-ToPng (Join-Path $root "assets\images\portraits\mock-02.jpg") "mevora-profile-sample.png"

Get-ChildItem $dest -Filter "mevora-*.png" | Sort-Object Name | Format-Table Name, Length -AutoSize
