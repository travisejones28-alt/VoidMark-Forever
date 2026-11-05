[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$ClientRoot = 'C:\Program Files (x86)\World of Warcraft\_forever_')
$ErrorActionPreference = 'Stop'

# This repository keeps build tooling at its root. The actual installed addon
# is the nested VoidMarkForever directory, not the repository root.
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'VoidMarkForever')).Path
if (!(Test-Path -LiteralPath (Join-Path $source 'VoidMarkForever.toc'))) {
    throw 'Missing VoidMarkForever\VoidMarkForever.toc. Pull the latest GitHub repository first.'
}
if (!(Test-Path -LiteralPath (Join-Path $source 'Modules\MinimapButton.lua'))) {
    throw 'Missing minimap module in canonical addon source.'
}
$addons = (Resolve-Path -LiteralPath (Join-Path $ClientRoot 'Interface\AddOns')).Path
$legacy = Join-Path $addons 'VoidMark'
$current = Join-Path $addons 'VoidMarkForever'

function SameTarget($link, [string]$expected) {
    if (!$link -or $link.LinkType -ne 'Junction') { return $false }
    try {
        return [IO.Path]::GetFullPath([string]$link.Target).TrimEnd('\') -ieq
            [IO.Path]::GetFullPath($expected).TrimEnd('\')
    } catch { return $false }
}

$old = Get-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue
$new = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue

if ($new -and !(SameTarget $new $source)) {
    throw "Existing $current does not link to the canonical addon folder. No files changed."
}
if ($old -and $old.LinkType -and !(SameTarget $old $PSScriptRoot)) {
    throw "Existing $legacy links elsewhere. No files changed; inspect it before reinstalling."
}

# A regular legacy folder might contain local changes. Keep it intact by moving
# it outside AddOns instead of deleting or replacing any files.
$backup = $null
if ($old -and !$old.LinkType) {
    $backup = Join-Path (Split-Path -Parent $addons) ('VoidMark-legacy-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if (Test-Path -LiteralPath $backup) { throw "Backup already exists: $backup" }
}

if ($PSCmdlet.ShouldProcess($ClientRoot, 'Install canonical VoidMark Forever addon without overwriting saves')) {
    # Migration helper refuses to run while WoW is open, and preserves existing data.
    & (Join-Path $PSScriptRoot 'tools\Migrate-VoidMarkSavedVariables.ps1') -ClientRoot $ClientRoot

    # Do not leave the old root addon active alongside the actual Forever addon.
    if ($old) {
        if ($old.LinkType -eq 'Junction') {
            $check = Get-Item -LiteralPath $legacy -Force
            if (!(SameTarget $check $PSScriptRoot)) { throw 'Legacy junction changed; no link removed.' }
            [IO.Directory]::Delete($legacy) # unlink only; do not recurse into repo
        } else {
            Move-Item -LiteralPath $legacy -Destination $backup
            Write-Host "Preserved old addon folder at: $backup"
        }
    }

    if (!$new) { New-Item -ItemType Junction -Path $current -Target $source | Out-Null }
    $installed = Get-Item -LiteralPath $current -Force
    if (!(SameTarget $installed $source)) { throw 'Could not verify installed addon junction.' }
    Write-Host "VoidMark Forever installed from: $source"
    Write-Host "Live AddOns path: $current"
    Write-Host 'The minimap launcher will load after restarting WoW. GitHub pulls update the linked addon.'
}
