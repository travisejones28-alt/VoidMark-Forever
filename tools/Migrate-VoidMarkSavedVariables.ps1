param(
    [Parameter(Mandatory = $true)]
    [string]$ClientRoot
)
$ErrorActionPreference = 'Stop'
# Renaming the physical addon changes the SavedVariables filename WoW loads,
# even when the declared variable remains VoidMarkDB. Copy only into new paths.
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -match '^Wow(?:Classic|ClassicT|B|T|_).*|^Wow$'
}
if ($running) { throw 'Close World of Warcraft before migrating SavedVariables.' }
$accountRoot = Join-Path $ClientRoot 'WTF\Account'
if (-not (Test-Path -LiteralPath $accountRoot -PathType Container)) {
    throw "Account directory not found: $accountRoot"
}
$copied = 0
Get-ChildItem -LiteralPath $accountRoot -Recurse -File -Filter 'VoidMark.lua' | ForEach-Object {
    $newPath = Join-Path $_.DirectoryName 'VoidMarkForever.lua'
    if (-not (Test-Path -LiteralPath $newPath)) {
        Copy-Item -LiteralPath $_.FullName -Destination $newPath
        $copied++
        Write-Output "Migrated: $newPath"
    } else {
        Write-Output "Preserved existing: $newPath"
    }
    $backup = $_.FullName + '.bak'
    $newBackup = $newPath + '.bak'
    if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $newBackup)) {
        Copy-Item -LiteralPath $backup -Destination $newBackup
    }
}
Write-Output "Migration complete: $copied file(s) copied. Original files were retained."
