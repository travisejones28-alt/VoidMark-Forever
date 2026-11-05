param([Parameter(Mandatory=$true)][string]$WorkRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path $WorkRoot ([guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'repo'
$client=Join-Path $fixture '_forever_'
$addons=Join-Path $client 'Interface\AddOns'
$saves=Join-Path $client 'WTF\Account\TEST\SavedVariables'
New-Item -ItemType Directory -Force $source,$addons,$saves,(Join-Path $source 'tools'),(Join-Path $source 'Modules') | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'INSTALL_FOREVER_LIVE.ps1') -Destination $source
Copy-Item -LiteralPath (Join-Path $repo 'tools\Migrate-VoidMarkSavedVariables.ps1') -Destination (Join-Path $source 'tools')
Set-Content (Join-Path $source 'VoidMarkForever.toc') '## Interface: 16001'
Set-Content (Join-Path $source 'VoidMark.lua') '-- mock'
Set-Content (Join-Path $source 'Modules\MinimapButton.lua') '-- mock'
Set-Content (Join-Path $saves 'VoidMark.lua') 'VoidMarkDB = { retained = 123 }'
New-Item -ItemType Junction -Path (Join-Path $addons 'VoidMark') -Target $source | Out-Null
# Synthetic fixture only: no real client data is used by this test.
function Get-Process { @() }
& (Join-Path $source 'INSTALL_FOREVER_LIVE.ps1') -ClientRoot $client
if (Test-Path (Join-Path $addons 'VoidMark')) { throw 'Legacy link remains' }
if (!(Test-Path (Join-Path $addons 'VoidMarkForever\VoidMarkForever.toc'))) { throw 'Flat addon TOC missing' }
if (!(Test-Path (Join-Path $source 'VoidMarkForever.toc'))) { throw 'Source was deleted' }
$newSave=Join-Path $saves 'VoidMarkForever.lua'
if ((Get-Content $newSave -Raw) -notmatch 'retained = 123') { throw 'Save not migrated' }
Set-Content $newSave 'VoidMarkDB = { retained = 456 }'
& (Join-Path $source 'INSTALL_FOREVER_LIVE.ps1') -ClientRoot $client
if ((Get-Content $newSave -Raw) -notmatch 'retained = 456') { throw 'Existing save overwritten' }
if (!(Test-Path (Join-Path $saves 'VoidMark.lua'))) { throw 'Original save removed' }
Write-Output 'PASS: junction installation, repeat installation, saved-data migration and existing-save preservation'
