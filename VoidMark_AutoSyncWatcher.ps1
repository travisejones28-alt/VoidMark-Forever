param(
    [int]$PollSeconds = 5,
    [int]$CloseSettleSeconds = 5
)

$ErrorActionPreference = "Continue"

$Here = $PSScriptRoot
$SyncScript = Join-Path $Here "VoidMark_KillFileSync.ps1"
$LogFile = Join-Path $Here "VoidMark_AutoSync.log"
$PidFile = Join-Path $Here "VoidMark_AutoSyncWatcher.pid"

function Log([string]$Message) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        Add-Content -LiteralPath $LogFile -Value "[$stamp] $Message" -Encoding UTF8
    } catch {}
}

function Get-WoWProcesses {
    @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "WowClassic*" -or
        $_.ProcessName -eq "Wow" -or
        $_.ProcessName -like "WowClassicEra*"
    })
}

function Run-VoidMarkSync([string]$Reason) {
    if (-not (Test-Path -LiteralPath $SyncScript)) {
        Log "ERROR: Missing sync script: $SyncScript"
        return
    }

    if ((Get-WoWProcesses).Count -gt 0) {
        Log "Deferred sync ($Reason): WoW is active again."
        return
    }

    Log "Starting offline kill merge ($Reason)."

    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SyncScript 2>&1
        $code = $LASTEXITCODE

        foreach ($line in @($output)) {
            if ($null -ne $line -and "$line".Trim() -ne "") {
                Log ("SYNC: " + "$line")
            }
        }

        if ($code -eq 0) {
            Log "Offline kill merge complete."
        } else {
            Log "Offline kill merge exited with code $code."
        }
    }
    catch {
        Log ("ERROR running merge: " + $_.Exception.Message)
    }
}

# Only one watcher per Windows user.
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Local\VoidMarkKillSyncWatcher", [ref]$createdNew)
if (-not $createdNew) {
    Log "Watcher is already running. Duplicate instance exiting."
    exit 0
}

try {
    Set-Content -LiteralPath $PidFile -Value $PID -Encoding ASCII
} catch {}

Log "Watcher started. PID=$PID Poll=${PollSeconds}s Settle=${CloseSettleSeconds}s."

try {
    $hadWoW = ((Get-WoWProcesses).Count -gt 0)

    # Safe catch-up when Windows starts the watcher and WoW is not running.
    if (-not $hadWoW) {
        Start-Sleep -Seconds 2
        Run-VoidMarkSync "watcher startup"
    } else {
        Log "WoW already running. Waiting for every WoW client to close."
    }

    while ($true) {
        Start-Sleep -Seconds ([Math]::Max(2, $PollSeconds))
        $running = ((Get-WoWProcesses).Count -gt 0)

        if ($running) {
            if (-not $hadWoW) {
                Log "WoW detected. Merge will run after the last client closes."
            }
            $hadWoW = $true
            continue
        }

        if ($hadWoW) {
            Log "Last WoW client closed. Waiting ${CloseSettleSeconds}s for SavedVariables to finish writing."
            Start-Sleep -Seconds ([Math]::Max(2, $CloseSettleSeconds))

            if ((Get-WoWProcesses).Count -eq 0) {
                Run-VoidMarkSync "last WoW client closed"
                $hadWoW = $false
            } else {
                Log "WoW restarted during settle period. Merge postponed."
                $hadWoW = $true
            }
        }
    }
}
finally {
    try { Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue } catch {}
    try {
        if ($mutex) {
            $mutex.ReleaseMutex() | Out-Null
            $mutex.Dispose()
        }
    } catch {}
    Log "Watcher stopped."
}
