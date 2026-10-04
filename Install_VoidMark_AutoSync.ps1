$ErrorActionPreference = "Stop"

$Here = $PSScriptRoot
$Watcher = Join-Path $Here "VoidMark_AutoSyncWatcher.ps1"
$HiddenLauncher = Join-Path $Here "VoidMark_AutoSyncHidden.vbs"
$PidFile = Join-Path $Here "VoidMark_AutoSyncWatcher.pid"
$Startup = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $Startup "VoidMark Automatic Kill Sync.lnk"

if (-not (Test-Path -LiteralPath $Watcher)) {
    throw "Missing watcher file: $Watcher"
}
if (-not (Test-Path -LiteralPath $HiddenLauncher)) {
    throw "Missing hidden launcher file: $HiddenLauncher"
}

# Stop the currently running watcher only when the PID file really belongs to
# VoidMark_AutoSyncWatcher.ps1. This replaces an older visible Windows Terminal
# hosted watcher immediately instead of waiting until the next Windows login.
if (Test-Path -LiteralPath $PidFile) {
    try {
        $oldPid = [int]((Get-Content -LiteralPath $PidFile -Raw).Trim())
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid" -ErrorAction SilentlyContinue
        if ($proc -and $proc.CommandLine -and $proc.CommandLine -match [regex]::Escape("VoidMark_AutoSyncWatcher.ps1")) {
            Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 350
        }
    } catch {}
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

# Windows 11 can route powershell.exe through Windows Terminal. In that mode,
# -WindowStyle Hidden can still leave a visible terminal tab. Launch through
# wscript.exe instead; the VBScript starts PowerShell with window style 0.
$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"
$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $wscript
$shortcut.Arguments = '"' + $HiddenLauncher + '"'
$shortcut.WorkingDirectory = $Here
$shortcut.Description = "VoidMark automatic offline kill-history sync (hidden)"
$shortcut.Save()

# Start the watcher now with no terminal window. Its mutex still prevents
# accidental duplicate watcher instances.
Start-Process -FilePath $wscript -ArgumentList @('"' + $HiddenLauncher + '"') -WorkingDirectory $Here -WindowStyle Hidden

Write-Host ""
Write-Host "[VoidMark Sync] AUTOMATIC SYNC INSTALLED (HIDDEN)." -ForegroundColor Green
Write-Host "[VoidMark Sync] The old visible watcher was replaced if it was running."
Write-Host "[VoidMark Sync] Future Windows logins will start it through wscript.exe."
Write-Host ""
Write-Host "Behavior:" -ForegroundColor Cyan
Write-Host "  - You can run 1, 2, or 3 WoW clients normally."
Write-Host "  - Nothing is edited while ANY WoW client is open."
Write-Host "  - When the LAST WoW client closes, it waits 5 seconds."
Write-Host "  - It then merges kill history across every detected Classic Era account."
Write-Host "  - The next account you launch already has the merged history."
Write-Host ""
Write-Host "The long-running watcher is now completely hidden."
Write-Host "Log file:"
Write-Host "  $Here\VoidMark_AutoSync.log"
