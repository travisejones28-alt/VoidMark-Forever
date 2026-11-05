[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$ClientRoot = 'C:\Program Files (x86)\World of Warcraft\_forever_')
$ErrorActionPreference = 'Stop'

# The repository root IS the addon. There is no nested VoidMarkForever folder.
$source = $PSScriptRoot
foreach ($required in @('VoidMarkForever.toc', 'Modules\MinimapButton.lua', 'VoidMark.lua')) {
    if (!(Test-Path -LiteralPath (Join-Path $source $required))) {
        throw "Missing $required in repository root. Pull the latest GitHub update first."
    }
}
$addons = (Resolve-Path -LiteralPath (Join-Path $ClientRoot 'Interface\AddOns')).Path
$legacy = Join-Path $addons 'VoidMark'
$current = Join-Path $addons 'VoidMarkForever'
$obsoleteSource = Join-Path $source 'VoidMarkForever'

function IsJunctionTo($item, [string]$target) {
    if (!$item -or $item.LinkType -ne 'Junction') { return $false }
    $actual = [IO.Path]::GetFullPath([string]$item.Target).TrimEnd('\')
    $expected = [IO.Path]::GetFullPath($target).TrimEnd('\')
    return $actual -ieq $expected
}
function BackupName([string]$name) {
    $candidate = Join-Path (Split-Path -Parent $addons) ($name + '-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if (Test-Path -LiteralPath $candidate) { throw "Backup path already exists: $candidate" }
    return $candidate
}

$old = Get-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue
$new = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue

# Refuse to alter links belonging to unrelated repositories.
if ($old -and $old.LinkType -and !(IsJunctionTo $old $source)) {
    throw "Unexpected legacy link: $legacy. No changes made."
}
if ($new -and $new.LinkType -and
    !(IsJunctionTo $new $source) -and !(IsJunctionTo $new $obsoleteSource)) {
    throw "Unexpected addon link: $current. No changes made."
}

if ($PSCmdlet.ShouldProcess($ClientRoot, 'Install flat VoidMark Forever source as canonical addon')) {
    # Existing SavedVariables are preserved; migration refuses to run while WoW is open.
    & (Join-Path $source 'tools\Migrate-VoidMarkSavedVariables.ps1') -ClientRoot $ClientRoot

    if ($old) {
        if ($old.LinkType -eq 'Junction') {
            [IO.Directory]::Delete($legacy)
        } else {
            $backup = BackupName 'VoidMark-legacy'
            Move-Item -LiteralPath $legacy -Destination $backup
            Write-Host "Preserved legacy addon at $backup"
        }
    }
    if ($new -and !(IsJunctionTo $new $source)) {
        if ($new.LinkType -eq 'Junction') {
            [IO.Directory]::Delete($current) # Only unlink, never delete source.
        } else {
            $backup = BackupName 'VoidMarkForever-previous'
            Move-Item -LiteralPath $current -Destination $backup
            Write-Host "Preserved previous addon at $backup"
        }
    }
    if (!(Test-Path -LiteralPath $current)) {
        New-Item -ItemType Junction -Path $current -Target $source | Out-Null
    }
    $installed = Get-Item -LiteralPath $current -Force
    if (!(IsJunctionTo $installed $source)) { throw 'Could not verify installed addon link.' }
    Write-Host "SUCCESS: $current -> $source"
    Write-Host 'Start WoW Forever. GitHub Desktop pulls now update the installed addon directly.'
}
