# Copies integration_test screenshots into docs/images for README relative paths.
$src = Join-Path $PSScriptRoot "..\..\screenshots"
$dest = Join-Path $PSScriptRoot "..\..\docs\images"
New-Item -ItemType Directory -Force -Path $dest | Out-Null

if (-not (Test-Path $src)) {
  Write-Error "No screenshots folder at $src"
  exit 1
}

Get-ChildItem $src -Filter "*.png" | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $dest $_.Name) -Force
  Write-Host "Copied $($_.Name)"
}

Get-ChildItem $dest -Filter "mevora-*.png" | Select-Object Name, Length
