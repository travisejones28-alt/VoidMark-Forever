[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$ClientRoot = 'C:\Program Files (x86)\World of Warcraft\_forever_')
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'VoidMarkForever')).Path
if (!(Test-Path -LiteralPath (Join-Path $source 'VoidMarkForever.toc'))) { throw 'Current addon source is missing.' }
$addons = (Resolve-Path -LiteralPath (Join-Path $ClientRoot 'Interface\AddOns')).Path
$legacy = Join-Path $addons 'VoidMark'
$current = Join-Path $addons 'VoidMarkForever'
$oldLink = Get-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue
if ($oldLink -and ($oldLink.LinkType -ne 'Junction' -or
    [IO.Path]::GetFullPath([string]$oldLink.Target).TrimEnd('\') -ne $PSScriptRoot.TrimEnd('\'))) {
    throw "Existing $legacy is not this repository's legacy junction. Move that addon out of AddOns manually first; no files were changed."
}
$newLink = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
if ($newLink -and ($newLink.LinkType -ne 'Junction' -or
    [IO.Path]::GetFullPath([string]$newLink.Target).TrimEnd('\') -ne $source.TrimEnd('\'))) {
    throw "Existing $current points elsewhere. No files were changed."
}
if ($PSCmdlet.ShouldProcess($ClientRoot, 'Preserve saved data and install the current VoidMark Forever junction')) {
    # This helper refuses migration while WoW is running and never overwrites saves.
    & (Join-Path $PSScriptRoot 'tools\Migrate-VoidMarkSavedVariables.ps1') -ClientRoot $ClientRoot
    if (!$newLink) { New-Item -ItemType Junction -Path $current -Target $source | Out-Null }
    if ($oldLink) {
        # Revalidate immediately before unlinking. Delete is nonrecursive: only
        # the verified junction is removed, never the repository it points to.
        $verify = Get-Item -LiteralPath $legacy -Force
        if ($verify.LinkType -ne 'Junction' -or
            [IO.Path]::GetFullPath([string]$verify.Target).TrimEnd('\') -ne $PSScriptRoot.TrimEnd('\')) {
            throw 'Legacy junction changed during installation; left it in place.'
        }
        [IO.Directory]::Delete($legacy)
    }
    Write-Host 'VoidMark Forever installed. Enable VoidMark in the addon list. Future GitHub pulls update this installation.'
}
