<#
.SYNOPSIS
    Makes sure the local Firebase Emulator Suite is running the current
    functions code and holds the QA users and the curated humor catalogue.

.DESCRIPTION
    preLaunchTask (via "Flutter: Prepare Run (full emulator suite)") of the
    VS Code configuration "Mevora (development - full emulator suite)", so F5
    gives a working, seeded local backend with no manual commands:

      1. Rebuilds functions/lib when any functions/src file is newer than it,
         running npm ci first when functions/node_modules is missing.
      2. Reuses an emulator suite that is already running, or starts one from
         this workspace in a separate minimized window so it outlives this
         task, and waits until the hub reports auth, firestore, functions and
         storage and the functions have loaded.
      3. Seeds the QA users (only missing ones: existing users, their matches
         and chats are left alone) and the curated humor catalogue
         (idempotent: never resets anyone's calibration progress).
      4. Prints one status line.

    It never targets the cloud. Nothing is deployed, and every seed write goes
    through FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST on 127.0.0.1,
    without which the seed scripts refuse to run.

    Windows PowerShell 5.1 compatible. Exits non-zero with a message on any
    failure, which makes VS Code stop before launching the app.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tool/ensure_emulators.ps1
#>
[CmdletBinding()]
param(
    # Emulator config, relative to the workspace root. Ports are read from it.
    [string]$Config = "firebase.qa.json",
    # Project the suite runs as. Must match the app (lib/firebase_options.dart).
    [string]$ProjectId = "mevora-d6ed0",
    # Upper bound for a cold start: Java Firestore emulator plus functions load.
    [int]$TimeoutSeconds = 180
)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$FunctionsDir = Join-Path $ProjectRoot "functions"
$TmpDir = Join-Path $ProjectRoot ".tmp"
$ExitMarker = Join-Path $TmpDir "emulators.exited"
$Required = @("auth", "firestore", "functions", "storage")

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "ensure_emulators: FAILED - $Message" -ForegroundColor Red
    exit 1
}

function Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# --------------------------------------------------------------------------
# Preconditions
# --------------------------------------------------------------------------

if ($ProjectId -notmatch '^[a-z0-9][a-z0-9-]{2,62}$' -or $ProjectId -match 'prod') {
    Fail "refusing project id '$ProjectId': the emulator suite is for development projects only"
}
$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $node) {
    Fail "node is not on PATH - install Node.js 20+ (the Firebase CLI and the seed scripts need it)"
}
$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue

$configPath = Join-Path $ProjectRoot $Config
if (-not (Test-Path $configPath)) {
    Fail "emulator config not found: $configPath"
}
try {
    $cfg = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Fail "cannot parse ${Config}: $($_.Exception.Message)"
}

function PortOf([string]$Name, [int]$Default) {
    $entry = $cfg.emulators.$Name
    if ($entry -and $entry.port) {
        return [int]$entry.port
    }
    return $Default
}

$Ports = [ordered]@{
    hub       = PortOf "hub" 4400
    firestore = PortOf "firestore" 8080
    auth      = PortOf "auth" 9099
    functions = PortOf "functions" 5001
    storage   = PortOf "storage" 9199
}

# --------------------------------------------------------------------------
# 1. Current functions code
# --------------------------------------------------------------------------

Step "Functions build"
if (-not (Test-Path (Join-Path $FunctionsDir "node_modules"))) {
    if (-not $npm) {
        Fail "npm is not on PATH and functions/node_modules is missing"
    }
    Write-Host "functions/node_modules is missing - running npm ci"
    & $npm.Source --prefix $FunctionsDir ci
    if ($LASTEXITCODE -ne 0) {
        Fail "npm ci in functions/ failed (exit code $LASTEXITCODE)"
    }
}

$sources = @(Get-ChildItem -Path (Join-Path $FunctionsDir "src") -Recurse -File -ErrorAction SilentlyContinue)
$tsconfig = Join-Path $FunctionsDir "tsconfig.json"
if (Test-Path $tsconfig) {
    $sources += Get-Item -Path $tsconfig
}
$newestSource = $sources | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$newestCompiled = $null
if (Test-Path (Join-Path $FunctionsDir "lib\index.js")) {
    $newestCompiled = Get-ChildItem -Path (Join-Path $FunctionsDir "lib") -Recurse -File -Filter "*.js" |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

$BuildState = "up to date"
$stale = $false
if (-not $newestCompiled) {
    Write-Host "functions/lib is missing - building"
    $stale = $true
} elseif ($newestSource -and $newestSource.LastWriteTimeUtc -gt $newestCompiled.LastWriteTimeUtc) {
    Write-Host "functions/src changed since the last build ($($newestSource.Name)) - rebuilding"
    $stale = $true
}
if ($stale) {
    if (-not $npm) {
        Fail "npm is not on PATH, so functions/lib cannot be rebuilt"
    }
    & $npm.Source --prefix $FunctionsDir run build
    if ($LASTEXITCODE -ne 0) {
        Fail "functions build failed (npm --prefix functions run build, exit code $LASTEXITCODE) - fix the errors above"
    }
    $BuildState = "rebuilt"
} else {
    Write-Host "functions/lib is up to date"
}

# --------------------------------------------------------------------------
# 2. A running suite: reuse it, or start one that outlives this task
# --------------------------------------------------------------------------

function Test-Port([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(500)) {
            return $false
        }
        $client.EndConnect($pending)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Get-Json([string]$Url) {
    try {
        return Invoke-RestMethod -Uri $Url -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
    } catch {
        return $null
    }
}

# What the hub and the functions emulator report right now. The functions
# emulator registers its triggers one by one after the hub lists it, so the
# suite only counts as ready once the trigger count has stopped growing.
function Get-SuiteState([int]$PreviousTriggers = -1) {
    $state = @{ Missing = @(); Triggers = 0; Directory = $null; Project = $null; Ready = $false }
    $hub = Get-Json "http://127.0.0.1:$($Ports.hub)/emulators"
    if (-not $hub) {
        $state.Missing = @("hub") + $Required
        return $state
    }
    $listed = @($hub.PSObject.Properties | ForEach-Object { $_.Name })
    $state.Missing = @($Required | Where-Object { $listed -notcontains $_ })
    if ($state.Missing.Count -gt 0) {
        return $state
    }
    $report = Get-Json "http://127.0.0.1:$($Ports.functions)/backends"
    if ($report -and $report.backends) {
        foreach ($backend in @($report.backends)) {
            if (-not $state.Directory) {
                $state.Directory = $backend.directory
            }
            if (-not $backend.functionTriggers) {
                continue
            }
            foreach ($trigger in @($backend.functionTriggers)) {
                $state.Triggers += 1
                $source = $null
                if ($trigger.labels) {
                    $source = $trigger.labels.EVENTARC_CLOUD_EVENT_SOURCE
                }
                if (-not $state.Project -and $source -and $source -match '/projects/([^/]+)/') {
                    $state.Project = $Matches[1]
                }
            }
        }
    }
    if ($state.Triggers -eq 0 -or $state.Triggers -ne $PreviousTriggers) {
        $state.Missing = @("functions (loading, $($state.Triggers) so far)")
        return $state
    }
    $state.Ready = (Test-Port $Ports.firestore) -and (Test-Port $Ports.auth)
    return $state
}

function Resolve-FirebaseCli {
    $globalCli = Get-Command firebase.cmd -ErrorAction SilentlyContinue
    if ($globalCli) {
        return "`"$($globalCli.Source)`""
    }
    # `npx firebase` would resolve the unrelated `firebase` SDK package; the
    # CLI is firebase-tools (pinned to the major CI uses).
    $npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
    if ($npx) {
        return "`"$($npx.Source)`" --yes firebase-tools@15"
    }
    return $null
}

function Start-Suite {
    $cli = Resolve-FirebaseCli
    if (-not $cli) {
        Fail "Firebase CLI not found - install it: npm install -g firebase-tools"
    }
    New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
    Remove-Item -Path $ExitMarker -Force -ErrorAction SilentlyContinue
    # A tiny launcher keeps the window open after a crash, so the reason stays
    # readable, and leaves a marker so this script can fail fast instead of
    # waiting out the whole timeout.
    $launcher = Join-Path $TmpDir "start_emulators.cmd"
    $lines = @(
        "@echo off",
        "title Mevora Firebase Emulator Suite ($ProjectId)",
        "cd /d `"$ProjectRoot`"",
        "echo Mevora Firebase Emulator Suite. Press Ctrl+C here to stop it.",
        "call $cli emulators:start --config `"$Config`" --project $ProjectId --only auth,firestore,functions,storage",
        "> `"$ExitMarker`" echo %ERRORLEVEL%",
        "echo.",
        "echo The emulator suite has stopped. Press any key to close this window.",
        "pause >nul"
    )
    Set-Content -Path $launcher -Value $lines -Encoding ASCII
    Write-Host "Starting: firebase emulators:start --config $Config --project $ProjectId --only auth,firestore,functions,storage"
    Write-Host "(minimized window 'Mevora Firebase Emulator Suite'; it keeps running after this task)"
    Start-Process -FilePath "cmd.exe" -ArgumentList @("/d", "/c", "`"$launcher`"") `
        -WorkingDirectory $ProjectRoot -WindowStyle Minimized | Out-Null
}

Step "Emulator suite ($Config, project $ProjectId)"
$up = @($Ports.Keys | Where-Object { Test-Port $Ports[$_] })
$down = @($Ports.Keys | Where-Object { $up -notcontains $_ })
$Mode = "reused"
$started = $false
if ($down.Count -eq 0) {
    Write-Host "All emulator ports answer - reusing the running suite"
} elseif ($up -contains "hub") {
    Write-Host "An emulator hub is up but not yet: $($down -join ', ') - waiting for that suite"
} elseif ($up.Count -gt 0) {
    $held = ($up | ForEach-Object { "$_ $($Ports[$_])" }) -join ", "
    Fail ("port(s) in use but no emulator hub answers on $($Ports.hub): $held. " +
        "Free them (Get-NetTCPConnection -LocalPort <port> shows the owner) and press F5 again.")
} else {
    Start-Suite
    $started = $true
    $Mode = "started"
}

$waitStart = Get-Date
$deadline = $waitStart.AddSeconds($TimeoutSeconds)
$lastNote = $waitStart
$state = Get-SuiteState
while (-not $state.Ready) {
    if ($started -and (Test-Path $ExitMarker)) {
        $code = (Get-Content -Path $ExitMarker -Raw).Trim()
        Fail ("the emulator suite exited while starting (exit code $code). Its window " +
            "'Mevora Firebase Emulator Suite' shows why - typically Java missing, a port " +
            "in use, or the Firebase CLI not logged in.")
    }
    if ((Get-Date) -gt $deadline) {
        Fail ("the emulator suite was not ready after $TimeoutSeconds s (missing: " +
            "$($state.Missing -join ', ')). If it was started without all of " +
            "$($Required -join ', '), stop it (Ctrl+C in its window) and press F5 again.")
    }
    if (((Get-Date) - $lastNote).TotalSeconds -ge 10) {
        $waited = [int]((Get-Date) - $waitStart).TotalSeconds
        Write-Host "  waiting for: $($state.Missing -join ', ') (${waited}s)"
        $lastNote = Get-Date
    }
    Start-Sleep -Seconds 2
    $state = Get-SuiteState $state.Triggers
}

if ($state.Project -and $state.Project -ne $ProjectId) {
    Fail ("the running emulator suite serves project '$($state.Project)', but the app " +
        "talks to '$ProjectId'. Stop that suite (Ctrl+C in its window) and press F5 again.")
}
if ($state.Directory) {
    $served = [IO.Path]::GetFullPath($state.Directory).TrimEnd('\')
    $ours = [IO.Path]::GetFullPath($FunctionsDir).TrimEnd('\')
    if ($served -ne $ours) {
        Write-Warning ("The running suite serves functions from $served, not from this " +
            "workspace ($ours), so callables run that code. To serve this workspace, stop " +
            "it (Ctrl+C in its window) and press F5 again.")
    }
}
Write-Host "Suite ready: $($Required -join ', ') up, $($state.Triggers) functions loaded"

# --------------------------------------------------------------------------
# 3. Seed data (emulator only, idempotent)
# --------------------------------------------------------------------------

Step "Seeding QA users and the humor catalogue into the emulator"
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:$($Ports.firestore)"
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:$($Ports.auth)"
$env:QA_PROJECT_ID = $ProjectId

& $node.Source (Join-Path $PSScriptRoot "seedEmulatorQaUsers.cjs") --if-missing
if ($LASTEXITCODE -ne 0) {
    Fail "QA user seed failed (exit code $LASTEXITCODE) - see its output above"
}
& $node.Source (Join-Path $PSScriptRoot "seedEmulatorHumorCatalog.cjs") --project $ProjectId
if ($LASTEXITCODE -ne 0) {
    Fail "humor catalogue seed failed (exit code $LASTEXITCODE) - see its output above"
}

# The Flutter: Prepare Run task grants ACCESS_LOCAL_NETWORK, but only to an app
# that is already installed, and its terminal closes on exit. Repeat the hint
# here, where it stays visible, for a fresh AVD.
$adb = Join-Path $env:LOCALAPPDATA "Android\sdk\platform-tools\adb.exe"
if (Test-Path $adb) {
    $serials = & $adb devices |
        Select-String -Pattern "^(emulator-\d+)\s+device$" |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
    foreach ($serial in $serials) {
        $installed = & $adb -s $serial shell pm list packages com.mevora.app
        if (-not $installed) {
            Write-Warning ("com.mevora.app is not installed on $serial yet: this first launch " +
                "cannot reach the emulators until ACCESS_LOCAL_NETWORK is granted. After it " +
                "installs, run: adb -s $serial shell pm grant com.mevora.app " +
                "android.permission.ACCESS_LOCAL_NETWORK and restart the app (the next F5 " +
                "grants it automatically).")
        }
    }
}

# --------------------------------------------------------------------------
# 4. Status
# --------------------------------------------------------------------------

$ui = ""
if (-not ($cfg.emulators.ui -and $cfg.emulators.ui.enabled -eq $false)) {
    $ui = " | UI http://127.0.0.1:$(PortOf 'ui' 4000)"
}
Write-Host ""
Write-Host ("ensure_emulators: READY | suite $Mode | project $ProjectId | functions lib " +
    "$BuildState, $($state.Triggers) loaded | QA users + humor catalogue seeded$ui") -ForegroundColor Green
exit 0
