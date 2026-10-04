$ErrorActionPreference = "Continue"

$Here = $PSScriptRoot
$Startup = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $Startup "VoidMark Automatic Kill Sync.lnk"

if (Test-Path -LiteralPath $ShortcutPath) {
    Remove-Item -LiteralPath $ShortcutPath -Force
}

# Stop only PowerShell instances actually running this watcher file.
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
        $_.CommandLine -like "*VoidMark_AutoSyncWatcher.ps1*"
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
} catch {}

Remove-Item -LiteralPath (Join-Path $Here "VoidMark_AutoSyncWatcher.pid") -Force -ErrorAction SilentlyContinue

Write-Host "[VoidMark Sync] Automatic watcher disabled." -ForegroundColor Green
