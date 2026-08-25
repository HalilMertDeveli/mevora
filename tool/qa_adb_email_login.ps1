# ADB email login driver for Mevora multi-emulator QA.
param(
  [Parameter(Mandatory=$true)][string]$Serial,
  [Parameter(Mandatory=$true)][string]$Email,
  [Parameter(Mandatory=$true)][string]$Password,
  [Parameter(Mandatory=$true)][string]$ShotPrefix
)

$ErrorActionPreference = 'Continue'
$adb = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
$out = 'D:\Mevora\build\qa-parity\multi-emu'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Shot([string]$name) {
  & $adb -s $Serial shell screencap -p "/sdcard/$name.png"
  & $adb -s $Serial pull "/sdcard/$name.png" "$out\$name.png" 2>$null | Out-Null
  Write-Host "SHOT $name=$((Get-Item "$out\$name.png").Length)"
}

function DumpUi {
  & $adb -s $Serial shell uiautomator dump /sdcard/ui.xml 2>$null | Out-Null
  & $adb -s $Serial pull /sdcard/ui.xml "$out\$ShotPrefix-ui.xml" 2>$null | Out-Null
  return [IO.File]::ReadAllText("$out\$ShotPrefix-ui.xml")
}

function TapDesc([string]$pattern) {
  $xml = DumpUi
  $m = [regex]::Match($xml, "content-desc=`"([^`"]*$([regex]::Escape($pattern))[^`"]*)`"[^>]*bounds=`"\[(\d+),(\d+)\]\[(\d+),(\d+)\]`"")
  if (-not $m.Success) {
    $m = [regex]::Match($xml, "text=`"([^`"]*$([regex]::Escape($pattern))[^`"]*)`"[^>]*bounds=`"\[(\d+),(\d+)\]\[(\d+),(\d+)\]`"")
  }
  if (-not $m.Success) { Write-Host "MISS $pattern"; return $false }
  $cx = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value)/2)
  $cy = [int](([int]$m.Groups[3].Value + [int]$m.Groups[5].Value)/2)
  Write-Host "HIT $($m.Groups[1].Value) @ $cx,$cy"
  & $adb -s $Serial shell input tap $cx $cy
  Start-Sleep 2
  return $true
}

$size = (& $adb -s $Serial shell wm size) -replace '.*Physical size:\s*',''
$w,$h = $size.Split('x') | ForEach-Object { [int]$_ }
Write-Host "SIZE ${w}x${h} on $Serial"

& $adb -s $Serial shell am force-stop com.mevora.app
& $adb -s $Serial shell am start -n com.mevora.app/.MainActivity
Start-Sleep 10
Shot "$ShotPrefix-01-welcome"

# Email button ~ 5th in stack. Prefer semantics, else coordinate.
if (-not (TapDesc 'email')) {
  if (-not (TapDesc 'e-posta')) {
    # medium_phone / pixel approx: email near bottom third
    $ex = [int]($w * 0.5)
    $ey = [int]($h * 0.72)
    Write-Host "COORD email $ex,$ey"
    & $adb -s $Serial shell input tap $ex $ey
    Start-Sleep 2
  }
}
Shot "$ShotPrefix-02-email-form"

# Focus first field and type email (escape @ as %40 for adb input text)
& $adb -s $Serial shell input tap ([int]($w*0.5)) ([int]($h*0.42))
Start-Sleep 1
& $adb -s $Serial shell input keyevent 123
& $adb -s $Serial shell input keyevent KEYCODE_MOVE_END
# clear field: select all delete
& $adb -s $Serial shell input keyevent 113 # CTRL? may not work — tap and type
$emailEsc = $Email.Replace('@','%40')
& $adb -s $Serial shell input text $emailEsc
Start-Sleep 1
& $adb -s $Serial shell input keyevent 61 # TAB
Start-Sleep 1
$passEsc = $Password.Replace('!','\!')
# adb input text: escape special chars
$passEsc = ($Password -replace '([\\ &<>|])','\$1')
# Use %s for spaces; ! often ok
& $adb -s $Serial shell input text ($Password -replace ' ','%s')
Start-Sleep 1
Shot "$ShotPrefix-03-filled"

if (-not (TapDesc 'Sign in')) {
  if (-not (TapDesc 'Giriş')) {
    if (-not (TapDesc 'Sign')) {
      & $adb -s $Serial shell input tap ([int]($w*0.5)) ([int]($h*0.62))
      Start-Sleep 2
    }
  }
}
Start-Sleep 8
Shot "$ShotPrefix-04-after-login"
DumpUi | Out-Null
Write-Host "DONE $Serial"
