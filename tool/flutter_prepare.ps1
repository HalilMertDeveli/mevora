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

exit 0
