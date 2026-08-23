# Pre-launch prep: ensure stable temp dir exists; log state (no destructive cleanup).
$ErrorActionPreference = "SilentlyContinue"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$StableTmp = Join-Path $ProjectRoot ".tmp"
$LogPath = "D:\debug-80971b.log"

function Write-DebugLog {
    param([string]$HypothesisId, [string]$Location, [string]$Message, [hashtable]$Data, [string]$RunId = "prepare")
    $entry = @{
        sessionId    = "80971b"
        runId        = $RunId
        hypothesisId = $HypothesisId
        location     = $Location
        message      = $Message
        data         = $Data
        timestamp    = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Compress
    Add-Content -Path $LogPath -Value $entry -Encoding utf8
}

# #region agent log
New-Item -ItemType Directory -Force -Path $StableTmp | Out-Null
$env:TMP = $StableTmp
$env:TEMP = $StableTmp

$userTmp = [Environment]::GetEnvironmentVariable("TMP", "User")
$userTemp = [Environment]::GetEnvironmentVariable("TEMP", "User")
$cFree = (Get-PSDrive C -ErrorAction SilentlyContinue).Free

Write-DebugLog -HypothesisId "G" -Location "tool/flutter_prepare.ps1" -Message "pre_launch_prepare" -Data @{
    stableTmp              = $StableTmp
    userTmp                = $userTmp
    userTemp               = $userTemp
    processTmp             = $env:TMP
    cDriveFreeGB           = [math]::Round($cFree / 1GB, 2)
    dartProcessCount       = @(Get-Process dart -ErrorAction SilentlyContinue).Count
    systemFlutterToolsDirs = @(Get-ChildItem "$env:LOCALAPPDATA\Temp\flutter_tools*" -Directory -ErrorAction SilentlyContinue).Count
    stableFlutterToolsDirs = @(Get-ChildItem "$StableTmp\flutter_tools*" -Directory -ErrorAction SilentlyContinue).Count
}
# #endregion

if ($userTmp -ne $StableTmp -or $userTemp -ne $StableTmp) {
    Write-Warning "User TMP/TEMP still point to C: ($userTmp). Run: .\tool\flutter_env_setup.ps1"
}

if ($cFree -lt 3GB) {
    Write-Warning "C: drive low on space ($([math]::Round($cFree/1GB,2)) GB free). Flutter may fail."
}

exit 0
