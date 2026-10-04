param(
    [string]$AccountRoot = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Cluster = "Forever"
$DedupeSeconds = 6

function Write-Info([string]$Text) {
    Write-Host "[VoidMark Sync] $Text" -ForegroundColor Cyan
}
function Write-Warn([string]$Text) {
    Write-Host "[VoidMark Sync] $Text" -ForegroundColor Yellow
}
function Write-Bad([string]$Text) {
    Write-Host "[VoidMark Sync] $Text" -ForegroundColor Red
}

function Find-AccountRoot {
    param([string]$Requested)

    if ($Requested) {
        $p = [Environment]::ExpandEnvironmentVariables($Requested.Trim('"'))
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
        throw "Account root not found: $p"
    }

    # Preferred path when this helper lives in:
    # ...\_classic_beta_\Interface\AddOns\VoidMark\
    try {
        $addonDir = $PSScriptRoot
        if ($addonDir) {
            # VoidMark -> AddOns -> Interface -> _classic_beta_
            $classicEraRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $addonDir))
            $relativeAccountRoot = Join-Path $classicEraRoot "WTF\Account"
            if (Test-Path -LiteralPath $relativeAccountRoot) {
                return (Resolve-Path -LiteralPath $relativeAccountRoot).Path
            }
        }
    } catch {}

    $candidates = New-Object System.Collections.Generic.List[string]
    $drives = @("C:","D:","E:","F:","G:")

    foreach ($d in $drives) {
        $candidates.Add("$d\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account")
        $candidates.Add("$d\Program Files\World of Warcraft\_classic_beta_\WTF\Account")
        $candidates.Add("$d\World of Warcraft\_classic_beta_\WTF\Account")
        $candidates.Add("$d\Games\World of Warcraft\_classic_beta_\WTF\Account")
    }

    try {
        $regPaths = @(
            "HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
            "HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft"
        )
        foreach ($rp in $regPaths) {
            if (Test-Path $rp) {
                $item = Get-ItemProperty $rp
                foreach ($prop in @("InstallPath","GamePath")) {
                    $base = $item.$prop
                    if ($base) {
                        $base = $base.TrimEnd("\")
                        $candidates.Add((Join-Path $base "_classic_beta_\WTF\Account"))
                        if ($base -like "*_classic_beta_*") {
                            $candidates.Add((Join-Path $base "WTF\Account"))
                        }
                    }
                }
            }
        }
    } catch {}

    foreach ($p in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $p) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }

    Write-Warn "Could not auto-detect the Classic Era WTF\Account folder."
    $typed = Read-Host 'Paste the path to ...\World of Warcraft\_classic_beta_\WTF\Account'
    if (-not $typed) { throw "No Account folder supplied." }
    $typed = [Environment]::ExpandEnvironmentVariables($typed.Trim('"'))
    if (-not (Test-Path -LiteralPath $typed)) { throw "Account root not found: $typed" }
    return (Resolve-Path -LiteralPath $typed).Path
}

function Find-MatchingBrace {
    param(
        [string]$Text,
        [int]$OpenIndex
    )
    if ($OpenIndex -lt 0 -or $OpenIndex -ge $Text.Length -or $Text[$OpenIndex] -ne '{') {
        return -1
    }

    $depth = 0
    $inString = $false
    $escaped = $false

    for ($i = $OpenIndex; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]

        if ($inString) {
            if ($escaped) {
                $escaped = $false
                continue
            }
            if ($ch -eq '\') {
                $escaped = $true
                continue
            }
            if ($ch -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            continue
        }

        if ($ch -eq '{') {
            $depth++
        } elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
    }
    return -1
}

function Find-KeyTable {
    param(
        [string]$Text,
        [string]$Key,
        [int]$StartIndex,
        [int]$EndIndex
    )

    $pattern = '\["' + [regex]::Escape($Key) + '"\]\s*=\s*\{'
    $rx = New-Object System.Text.RegularExpressions.Regex($pattern)
    $m = $rx.Match($Text, $StartIndex)
    if (-not $m.Success -or $m.Index -ge $EndIndex) { return $null }

    $open = $Text.IndexOf('{', $m.Index)
    if ($open -lt 0 -or $open -ge $EndIndex) { return $null }
    $close = Find-MatchingBrace -Text $Text -OpenIndex $open
    if ($close -lt 0 -or $close -gt $EndIndex) { return $null }

    return [pscustomobject]@{
        MatchIndex = $m.Index
        Open = $open
        Close = $close
    }
}

function Find-GlobalEventsRegion {
    param([string]$Text)

    $rootEnd = $Text.Length - 1
    $global = Find-KeyTable -Text $Text -Key "TaliaaGankGlobal" -StartIndex 0 -EndIndex $rootEnd
    if (-not $global) { return $null }

    $cluster = Find-KeyTable -Text $Text -Key $Cluster -StartIndex ($global.Open + 1) -EndIndex $global.Close
    if (-not $cluster) { return $null }

    $history = Find-KeyTable -Text $Text -Key "GankHistory" -StartIndex ($cluster.Open + 1) -EndIndex $cluster.Close
    if (-not $history) { return $null }

    return Find-KeyTable -Text $Text -Key "events" -StartIndex ($history.Open + 1) -EndIndex $history.Close
}

function Find-GlobalHistoryRegion {
    param([string]$Text)

    $rootEnd = $Text.Length - 1
    $global = Find-KeyTable -Text $Text -Key "TaliaaGankGlobal" -StartIndex 0 -EndIndex $rootEnd
    if (-not $global) { return $null }

    $cluster = Find-KeyTable -Text $Text -Key $Cluster -StartIndex ($global.Open + 1) -EndIndex $global.Close
    if (-not $cluster) { return $null }

    return Find-KeyTable -Text $Text -Key "GankHistory" -StartIndex ($cluster.Open + 1) -EndIndex $cluster.Close
}

function Find-GlobalLegacyFloorsRegion {
    param([string]$Text)

    $history = Find-GlobalHistoryRegion -Text $Text
    if (-not $history) { return $null }
    return Find-KeyTable -Text $Text -Key "legacyFloors" -StartIndex ($history.Open + 1) -EndIndex $history.Close
}

function Find-GlobalDHKEventsRegion {
    param([string]$Text)

    $rootEnd = $Text.Length - 1
    $global = Find-KeyTable -Text $Text -Key "TaliaaGankGlobal" -StartIndex 0 -EndIndex $rootEnd
    if (-not $global) { return $null }

    $cluster = Find-KeyTable -Text $Text -Key $Cluster -StartIndex ($global.Open + 1) -EndIndex $global.Close
    if (-not $cluster) { return $null }

    $history = Find-KeyTable -Text $Text -Key "DHKHistory" -StartIndex ($cluster.Open + 1) -EndIndex $cluster.Close
    if (-not $history) { return $null }

    return Find-KeyTable -Text $Text -Key "events" -StartIndex ($history.Open + 1) -EndIndex $history.Close
}

function Get-LuaStringField {
    param([string]$TableText, [string]$Field)
    $pattern = '\["' + [regex]::Escape($Field) + '"\]\s*=\s*"((?:\\.|[^"])*)"'
    $m = [regex]::Match($TableText, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ""
}

function Get-LuaNumberField {
    param([string]$TableText, [string]$Field)
    $pattern = '\["' + [regex]::Escape($Field) + '"\]\s*=\s*(-?\d+(?:\.\d+)?)'
    $m = [regex]::Match($TableText, $pattern)
    if ($m.Success) {
        $v = 0.0
        if ([double]::TryParse($m.Groups[1].Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
            return $v
        }
    }
    return 0.0
}

function Escape-LuaString([string]$Value) {
    if ($null -eq $Value) { return "" }
    return $Value.Replace('\','\\').Replace('"','\"').Replace("`r",'\r').Replace("`n",'\n')
}

function Get-ShortHash([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0,16)
    } finally {
        $sha.Dispose()
    }
}

function Set-EventIdInTable {
    param([string]$TableText, [string]$NewId)

    $escaped = Escape-LuaString $NewId
    $pattern = '(\["id"\]\s*=\s*")((?:\\.|[^"])*)(")'
    $m = [regex]::Match($TableText, $pattern)

    if ($m.Success) {
        # Do NOT use a .NET regex replacement string here. Event IDs can contain
        # characters that have special meaning to replacement syntax (especially $).
        # Replace only the captured ID text by string index instead.
        $g = $m.Groups[2]
        return $TableText.Substring(0, $g.Index) + $escaped + $TableText.Substring($g.Index + $g.Length)
    }

    $brace = $TableText.IndexOf('{')
    if ($brace -ge 0) {
        return $TableText.Substring(0,$brace+1) + "`r`n[`"id`"] = `"$escaped`"," + $TableText.Substring($brace+1)
    }
    return $TableText
}

function Get-EventEntriesFromEventsRegion {
    param(
        [string]$Text,
        $Region,
        [string]$SourceFile
    )

    $results = New-Object System.Collections.Generic.List[object]
    $i = $Region.Open + 1
    $end = $Region.Close
    $entryRx = New-Object System.Text.RegularExpressions.Regex('\["((?:\\.|[^"])*)"\]\s*=\s*\{')

    while ($i -lt $end) {
        $m = $entryRx.Match($Text, $i)
        if (-not $m.Success -or $m.Index -ge $end) { break }

        $tableOpen = $Text.IndexOf('{', $m.Index)
        if ($tableOpen -lt 0 -or $tableOpen -ge $end) { break }

        $tableClose = Find-MatchingBrace -Text $Text -OpenIndex $tableOpen
        if ($tableClose -lt 0 -or $tableClose -gt $end) { break }

        $id = $m.Groups[1].Value
        $tableRaw = $Text.Substring($tableOpen, $tableClose - $tableOpen + 1)
        $eventId = Get-LuaStringField -TableText $tableRaw -Field "id"
        if ($eventId) { $id = $eventId }

        $t = Get-LuaNumberField -TableText $tableRaw -Field "t"
        $name = Get-LuaStringField -TableText $tableRaw -Field "name"
        $guid = Get-LuaStringField -TableText $tableRaw -Field "guid"

        if ($guid -and $guid.StartsWith("Player")) {
            $victimKey = "G:" + $guid
        } else {
            $victimKey = "N:" + $name.ToLowerInvariant()
        }

        $results.Add([pscustomobject]@{
            Id = $id
            Time = $t
            Name = $name
            Guid = $guid
            VictimKey = $victimKey
            TableRaw = $tableRaw
            Source = $SourceFile
        })

        $i = $tableClose + 1
    }

    return $results
}

function Get-AllHistoryEvents {
    param(
        [string]$Text,
        [string]$SourceFile
    )

    $all = New-Object System.Collections.Generic.List[object]
    $historyRx = New-Object System.Text.RegularExpressions.Regex('\["GankHistory"\]\s*=\s*\{')
    $pos = 0

    while ($pos -lt $Text.Length) {
        $m = $historyRx.Match($Text, $pos)
        if (-not $m.Success) { break }

        $histOpen = $Text.IndexOf('{', $m.Index)
        if ($histOpen -lt 0) { break }
        $histClose = Find-MatchingBrace -Text $Text -OpenIndex $histOpen
        if ($histClose -lt 0) { break }

        $events = Find-KeyTable -Text $Text -Key "events" -StartIndex ($histOpen + 1) -EndIndex $histClose
        if ($events) {
            foreach ($e in (Get-EventEntriesFromEventsRegion -Text $Text -Region $events -SourceFile $SourceFile)) {
                $all.Add($e)
            }
        }

        $pos = $histClose + 1
    }

    return $all
}

function Get-LegacyFloorEntriesFromRegion {
    param(
        [string]$Text,
        $Region,
        [string]$SourceFile
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $Region) { return $results }

    $i = $Region.Open + 1
    $end = $Region.Close
    $entryRx = New-Object System.Text.RegularExpressions.Regex('\["((?:\\.|[^"])*)"\]\s*=\s*\{')

    while ($i -lt $end) {
        $m = $entryRx.Match($Text, $i)
        if (-not $m.Success -or $m.Index -ge $end) { break }

        $tableOpen = $Text.IndexOf('{', $m.Index)
        if ($tableOpen -lt 0 -or $tableOpen -ge $end) { break }
        $tableClose = Find-MatchingBrace -Text $Text -OpenIndex $tableOpen
        if ($tableClose -lt 0 -or $tableClose -gt $end) { break }

        $key = $m.Groups[1].Value
        $tableRaw = $Text.Substring($tableOpen, $tableClose - $tableOpen + 1)
        $name = Get-LuaStringField -TableText $tableRaw -Field "name"
        $guid = Get-LuaStringField -TableText $tableRaw -Field "guid"
        $gap = Get-LuaNumberField -TableText $tableRaw -Field "legacyGap"
        $floor = Get-LuaNumberField -TableText $tableRaw -Field "floor"
        $repoAtCapture = Get-LuaNumberField -TableText $tableRaw -Field "repoAtCapture"
        $capturedAt = Get-LuaNumberField -TableText $tableRaw -Field "capturedAt"

        if ($gap -le 0 -and $floor -gt $repoAtCapture) {
            $gap = $floor - $repoAtCapture
        }

        if ($gap -gt 0) {
            if ($guid -and $guid.StartsWith("Player")) {
                $identity = "G:" + $guid
            } else {
                $identityName = if ($name) { $name } else { $key }
                $identity = "N:" + $identityName.ToLowerInvariant()
            }

            $results.Add([pscustomobject]@{
                Key = $key
                Identity = $identity
                Name = $name
                Guid = $guid
                Gap = [double]$gap
                Floor = [double]$floor
                RepoAtCapture = [double]$repoAtCapture
                CapturedAt = [double]$capturedAt
                Source = $SourceFile
            })
        }

        $i = $tableClose + 1
    }

    return $results
}

function Get-AllLegacyFloors {
    param(
        [string]$Text,
        [string]$SourceFile
    )

    $all = New-Object System.Collections.Generic.List[object]
    $historyRx = New-Object System.Text.RegularExpressions.Regex('\["GankHistory"\]\s*=\s*\{')
    $pos = 0

    while ($pos -lt $Text.Length) {
        $m = $historyRx.Match($Text, $pos)
        if (-not $m.Success) { break }

        $histOpen = $Text.IndexOf('{', $m.Index)
        if ($histOpen -lt 0) { break }
        $histClose = Find-MatchingBrace -Text $Text -OpenIndex $histOpen
        if ($histClose -lt 0) { break }

        $floors = Find-KeyTable -Text $Text -Key "legacyFloors" -StartIndex ($histOpen + 1) -EndIndex $histClose
        if ($floors) {
            foreach ($f in (Get-LegacyFloorEntriesFromRegion -Text $Text -Region $floors -SourceFile $SourceFile)) {
                $all.Add($f)
            }
        }

        $pos = $histClose + 1
    }

    return $all
}

function Get-DHKEventEntriesFromEventsRegion {
    param(
        [string]$Text,
        $Region,
        [string]$SourceFile
    )

    $results = New-Object System.Collections.Generic.List[object]
    if (-not $Region) { return $results }

    $i = $Region.Open + 1
    $end = $Region.Close
    $entryRx = New-Object System.Text.RegularExpressions.Regex('\["((?:\\.|[^"])*)"\]\s*=\s*\{')

    while ($i -lt $end) {
        $m = $entryRx.Match($Text, $i)
        if (-not $m.Success -or $m.Index -ge $end) { break }

        $tableOpen = $Text.IndexOf('{', $m.Index)
        if ($tableOpen -lt 0 -or $tableOpen -ge $end) { break }

        $tableClose = Find-MatchingBrace -Text $Text -OpenIndex $tableOpen
        if ($tableClose -lt 0 -or $tableClose -gt $end) { break }

        $id = $m.Groups[1].Value
        $tableRaw = $Text.Substring($tableOpen, $tableClose - $tableOpen + 1)
        $eventId = Get-LuaStringField -TableText $tableRaw -Field "id"
        if ($eventId) { $id = $eventId }

        $t = Get-LuaNumberField -TableText $tableRaw -Field "t"
        $character = Get-LuaStringField -TableText $tableRaw -Field "character"
        $message = Get-LuaStringField -TableText $tableRaw -Field "message"

        $results.Add([pscustomobject]@{
            Id = $id
            Time = $t
            Character = $character
            Message = $message
            TableRaw = $tableRaw
            Source = $SourceFile
        })

        $i = $tableClose + 1
    }

    return $results
}

function Merge-DHKEvents {
    param([object[]]$CandidateFiles)

    $byId = @{}
    $collisions = 0

    foreach ($cf in $CandidateFiles) {
        foreach ($e in @($cf.DHKEvents)) {
            if (-not $e.Id) {
                $e.Id = "XDHK-" + (Get-ShortHash ($e.TableRaw + "|" + $e.Source)) + "-" + [int64]$e.Time
            }

            if (-not $byId.ContainsKey($e.Id)) {
                $byId[$e.Id] = $e
                continue
            }

            $existing = $byId[$e.Id]
            if ($existing.TableRaw -eq $e.TableRaw) { continue }

            $collisions++
            $newId = "XDHK-" + (Get-ShortHash ($e.Id + "|" + $e.TableRaw + "|" + $e.Source)) + "-" + [int64]$e.Time
            $e.Id = $newId
            if (-not $byId.ContainsKey($newId)) {
                $byId[$newId] = $e
            }
        }
    }

    $ordered = @($byId.Values | Sort-Object @{Expression={[double]$_.Time}}, @{Expression={$_.Id}})

    # Only remove true retransmits: same character + same message + essentially
    # same server second. Different characters can legitimately receive separate
    # DHKs from the same civilian death and must remain separate.
    $kept = New-Object System.Collections.Generic.List[object]
    $lastBySignature = @{}
    $dropped = 0

    foreach ($e in $ordered) {
        $signature = ("{0}|{1}" -f ([string]$e.Character).ToLowerInvariant(), ([string]$e.Message).ToLowerInvariant())
        $drop = $false

        if ($e.Time -gt 0 -and $signature -ne "|") {
            if ($lastBySignature.ContainsKey($signature)) {
                $last = [double]$lastBySignature[$signature]
                if ([math]::Abs(([double]$e.Time) - $last) -le 1) {
                    $drop = $true
                }
            }
        }

        if ($drop) {
            $dropped++
            continue
        }

        $kept.Add($e)
        if ($e.Time -gt 0 -and $signature -ne "|") {
            $lastBySignature[$signature] = [double]$e.Time
        }
    }

    [object[]]$result = @()
    foreach ($item in $kept) { $result += $item }

    return [pscustomobject]@{
        Events = $result
        Dropped = $dropped
        Collisions = $collisions
    }
}

function Set-OfflineSyncMarker {
    param(
        [string]$Text,
        [int64]$Timestamp,
        [int]$MergedCount
    )

    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $marker = 'VoidMarkDB["TaliaaGankOfflineSync"] = {["t"] = ' + $Timestamp + ', ["merged"] = ' + $MergedCount + '}'
    $pattern = '(?m)^VoidMarkDB\["TaliaaGankOfflineSync"\]\s*=\s*\{\["t"\]\s*=\s*\d+\s*,\s*\["merged"\]\s*=\s*\d+\s*\}\s*$'
    $m = [regex]::Match($Text, $pattern)

    if ($m.Success) {
        return $Text.Substring(0, $m.Index) + $marker + $Text.Substring($m.Index + $m.Length)
    }

    if (-not $Text.EndsWith($newline)) {
        $Text += $newline
    }
    return $Text + $marker + $newline
}

function Test-LuaSavedVariablesText {
    param([string]$Text)

    $inString = $false
    $escape = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]

        if ($inString) {
            if ($escape) {
                $escape = $false
                continue
            }
            if ($ch -eq '\') {
                $escape = $true
                continue
            }
            if ($ch -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            continue
        }

        if ($ch -eq '$') {
            $line = 1
            for ($j = 0; $j -lt $i; $j++) {
                if ($Text[$j] -eq "`n") { $line++ }
            }
            throw "Refusing to write invalid Lua: bare `$ found outside a quoted string near line $line."
        }
    }

    if ($inString) {
        throw "Refusing to write invalid Lua: unterminated quoted string detected."
    }

    return $true
}

function Replace-EventsRegion {
    param(
        [string]$Text,
        $Region,
        [object[]]$Events
    )

    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object System.Collections.Generic.List[string]

    foreach ($e in $Events) {
        $idEsc = Escape-LuaString $e.Id
        $table = Set-EventIdInTable -TableText $e.TableRaw -NewId $e.Id
        $lines.Add('["' + $idEsc + '"] = ' + $table + ',')
    }

    $body = $newline
    if ($lines.Count -gt 0) {
        $body += ($lines -join $newline) + $newline
    }

    return $Text.Substring(0, $Region.Open + 1) + $body + $Text.Substring($Region.Close)
}


function Replace-GlobalLegacyFloors {
    param(
        [string]$Text,
        [object[]]$Floors
    )

    $history = Find-GlobalHistoryRegion -Text $Text
    if (-not $history) { return $Text }

    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object System.Collections.Generic.List[string]

    foreach ($f in $Floors) {
        $guid = [string]$f.Guid
        $name = [string]$f.Name
        $key = [string]$f.Key
        if ($guid -and $guid.StartsWith("Player")) {
            $key = "G:" + $guid
        } elseif (-not $key) {
            $key = "N:" + $name.ToLowerInvariant()
        }

        $gap = [int64][math]::Max(0, [double]$f.Gap)
        if ($gap -le 0) { continue }

        $repo = [int64][math]::Max(0, [double]$f.RepoAtCapture)
        $floor = [int64]($repo + $gap)
        $captured = [int64][math]::Max(0, [double]$f.CapturedAt)

        $keyEsc = Escape-LuaString $key
        $nameEsc = Escape-LuaString $name
        $guidEsc = Escape-LuaString $guid
        $line = '["' + $keyEsc + '"] = {' +
            '["legacyGap"] = ' + $gap + ', ' +
            '["name"] = "' + $nameEsc + '", ' +
            '["guid"] = "' + $guidEsc + '", ' +
            '["floor"] = ' + $floor + ', ' +
            '["repoAtCapture"] = ' + $repo + ', ' +
            '["capturedAt"] = ' + $captured + ', ' +
            '["version"] = 2},'
        $lines.Add($line)
    }

    $body = $newline
    if ($lines.Count -gt 0) {
        $body += ($lines -join $newline) + $newline
    }

    $region = Find-GlobalLegacyFloorsRegion -Text $Text
    if ($region) {
        return $Text.Substring(0, $region.Open + 1) + $body + $Text.Substring($region.Close)
    }

    # Older accounts may not have a legacyFloors table yet. Add one inside the
    # current global GankHistory table instead of requiring that account to log in.
    $history = Find-GlobalHistoryRegion -Text $Text
    if (-not $history) { return $Text }
    $tableText = $newline + '["legacyFloors"] = {' + $body + '},' + $newline
    return $Text.Substring(0, $history.Close) + $tableText + $Text.Substring($history.Close)
}

try {
    # Writing SavedVariables while WoW is open is unsafe because WoW can overwrite
    # the merged file on logout/reload.
    $wow = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "WowClassic*" -or $_.ProcessName -eq "Wow"
    }
    if ($wow) {
        Write-Bad "World of Warcraft is currently running."
        Write-Bad "Close all WoW clients, run this sync, then launch the account you want to play."
        Write-Bad "This prevents WoW from overwriting the merged SavedVariables."
        exit 2
    }

    $AccountRoot = Find-AccountRoot -Requested $AccountRoot
    Write-Info "Scanning: $AccountRoot"

    $candidateFiles = New-Object System.Collections.Generic.List[object]

    foreach ($acct in (Get-ChildItem -LiteralPath $AccountRoot -Directory -ErrorAction Stop)) {
        $sv = Join-Path $acct.FullName "SavedVariables"
        if (-not (Test-Path -LiteralPath $sv)) { continue }

        foreach ($file in (Get-ChildItem -LiteralPath $sv -Filter "*.lua" -File -ErrorAction SilentlyContinue)) {
            $text = [IO.File]::ReadAllText($file.FullName)
            if ($text -notmatch 'GankHistory' -or ($text -notmatch 'TaliaaGankGlobal' -and $text -notmatch 'TaliaaShared')) {
                continue
            }

            $events = @(Get-AllHistoryEvents -Text $text -SourceFile $file.FullName)
            $target = Find-GlobalEventsRegion -Text $text
            $floors = @(Get-AllLegacyFloors -Text $text -SourceFile $file.FullName)

            $dhkTarget = Find-GlobalDHKEventsRegion -Text $text
            $dhkEvents = @()
            if ($dhkTarget) {
                $dhkEvents = @(Get-DHKEventEntriesFromEventsRegion -Text $text -Region $dhkTarget -SourceFile $file.FullName)
            }

            if ($events.Count -gt 0 -or $target -or $floors.Count -gt 0 -or $dhkEvents.Count -gt 0 -or $dhkTarget) {
                $candidateFiles.Add([pscustomobject]@{
                    Account = $acct.Name
                    File = $file
                    Text = $text
                    Events = $events
                    Target = $target
                    Floors = $floors
                    DHKEvents = $dhkEvents
                    DHKTarget = $dhkTarget
                })
                Write-Info ("Found {0}: {1} kill rows + {2} legacy floors + {3} DHK rows in {4}" -f $acct.Name, $events.Count, $floors.Count, $dhkEvents.Count, $file.Name)
            }
        }
    }

    if ($candidateFiles.Count -eq 0) {
        throw "No VoidMark gank SavedVariables were found under $AccountRoot"
    }

    # Merge by event ID first. If two different rows somehow reused one ID,
    # assign a stable external-sync ID to the second row instead of losing it.
    $byId = @{}
    $collisionCount = 0

    foreach ($cf in $candidateFiles) {
        foreach ($e in $cf.Events) {
            if (-not $e.Id) {
                $e.Id = "X" + (Get-ShortHash ($e.TableRaw + "|" + $e.Source)) + "-" + [int64]$e.Time
            }

            if (-not $byId.ContainsKey($e.Id)) {
                $byId[$e.Id] = $e
                continue
            }

            $existing = $byId[$e.Id]
            if ($existing.TableRaw -eq $e.TableRaw) { continue }

            $collisionCount++
            $newId = "X" + (Get-ShortHash ($e.Id + "|" + $e.TableRaw + "|" + $e.Source)) + "-" + [int64]$e.Time
            $e.Id = $newId
            if (-not $byId.ContainsKey($newId)) {
                $byId[$newId] = $e
            }
        }
    }

    $ordered = @($byId.Values | Sort-Object @{Expression={[double]$_.Time}}, @{Expression={$_.Id}})

    # Same-death dedupe: the repository itself uses the same 6-second rule.
    $kept = New-Object System.Collections.Generic.List[object]
    $lastByVictim = @{}
    $sameDeathDropped = 0

    foreach ($e in $ordered) {
        $drop = $false
        if ($e.Time -gt 0 -and $e.VictimKey -and $e.VictimKey -ne "N:") {
            if ($lastByVictim.ContainsKey($e.VictimKey)) {
                $last = [double]$lastByVictim[$e.VictimKey]
                if ([math]::Abs(([double]$e.Time) - $last) -le $DedupeSeconds) {
                    $drop = $true
                }
            }
        }

        if ($drop) {
            $sameDeathDropped++
            continue
        }

        $kept.Add($e)
        if ($e.Time -gt 0 -and $e.VictimKey) {
            $lastByVictim[$e.VictimKey] = [double]$e.Time
        }
    }

    Write-Info ("Merged total: {0} kills | same-death duplicates removed: {1} | ID collisions repaired: {2}" -f $kept.Count, $sameDeathDropped, $collisionCount)

    # Windows PowerShell 5.1 can throw "Argument types do not match" when a
    # generic List[object] is splatted/coerced with @($kept). Materialize it
    # explicitly as a normal PowerShell object array before the write phase.
    [object[]]$mergedEvents = @()
    foreach ($item in $kept) {
        $mergedEvents += $item
    }

    # Merge historical pre-repository gaps. These are NOT kill rows; they are the
    # missing lifetime amount that lets a 55-kill old VoidMark record continue at 56,
    # 57, etc. Max-only merging is safe because each gap describes the same
    # historical overlap, not additional independent kills.
    $floorByIdentity = @{}
    foreach ($cf in $candidateFiles) {
        foreach ($f in @($cf.Floors)) {
            if (-not $f.Identity -or [double]$f.Gap -le 0) { continue }

            if (-not $floorByIdentity.ContainsKey($f.Identity)) {
                $floorByIdentity[$f.Identity] = $f
                continue
            }

            $existing = $floorByIdentity[$f.Identity]
            if ([double]$f.Gap -gt [double]$existing.Gap -or
                (([double]$f.Gap -eq [double]$existing.Gap) -and ([double]$f.CapturedAt -gt [double]$existing.CapturedAt))) {
                $floorByIdentity[$f.Identity] = $f
            }
        }
    }

    # If one exact visible name has both a name-only floor and exactly one GUID
    # floor, promote the larger gap to the GUID identity. This avoids leaving two
    # aliases behind after one account learned the target's GUID.
    $guidFloorsByName = @{}
    foreach ($f in @($floorByIdentity.Values)) {
        if ($f.Guid -and $f.Guid.StartsWith("Player") -and $f.Name) {
            $n = $f.Name.ToLowerInvariant()
            if (-not $guidFloorsByName.ContainsKey($n)) {
                $guidFloorsByName[$n] = @($f)
            } else {
                $guidFloorsByName[$n] += $f
            }
        }
    }

    foreach ($identity in @($floorByIdentity.Keys)) {
        if (-not $identity.StartsWith("N:")) { continue }
        $f = $floorByIdentity[$identity]
        if (-not $f.Name) { continue }
        $n = $f.Name.ToLowerInvariant()
        $matches = @($guidFloorsByName[$n])
        if ($matches.Count -eq 1) {
            $g = $matches[0]
            if ([double]$f.Gap -gt [double]$g.Gap) {
                $g.Gap = [double]$f.Gap
            }
            $floorByIdentity.Remove($identity)
        }
    }

    [object[]]$mergedFloors = @($floorByIdentity.Values | Sort-Object Identity)
    Write-Info ("Merged historical floors: {0}" -f $mergedFloors.Count)

    $dhkMerge = Merge-DHKEvents -CandidateFiles $candidateFiles
    [object[]]$mergedDHKEvents = @($dhkMerge.Events)
    Write-Info ("Merged DHKs: {0} | retransmits removed: {1} | ID collisions repaired: {2}" -f $mergedDHKEvents.Count, $dhkMerge.Dropped, $dhkMerge.Collisions)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $written = 0

    foreach ($cf in $candidateFiles) {
        if (-not $cf.Target) {
            Write-Warn ("{0}\{1} supplied history but has no current TaliaaGankGlobal target. It was read but not rewritten." -f $cf.Account, $cf.File.Name)
            continue
        }

        $newText = $cf.Text

        if ($cf.Target) {
            $newText = Replace-EventsRegion -Text $newText -Region $cf.Target -Events $mergedEvents
        }

        # Merge the historical legacy gaps too. Event-only sync was the reason an
        # old 50+ kill record could look like a first kill on the other account.
        $newText = Replace-GlobalLegacyFloors -Text $newText -Floors $mergedFloors

        # Re-locate the DHK table after the kill-table replacement because string
        # offsets can move when the merged kill history changes size.
        $currentDHKTarget = Find-GlobalDHKEventsRegion -Text $newText
        if ($currentDHKTarget) {
            $newText = Replace-EventsRegion -Text $newText -Region $currentDHKTarget -Events $mergedDHKEvents
        } elseif ($mergedDHKEvents.Count -gt 0) {
            Write-Warn ("{0}\{1} has no DHKHistory target yet; launch that account once with the updated addon, then close WoW and sync again." -f $cf.Account, $cf.File.Name)
        }

        # Expose the most recent successful file merge to the addon next login.
        $unixNow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $newText = Set-OfflineSyncMarker -Text $newText -Timestamp $unixNow -MergedCount $mergedEvents.Count

        if ($DryRun) {
            Write-Info ("DRY RUN: would update {0}\{1}" -f $cf.Account, $cf.File.Name)
            continue
        }

        # Validate the complete output before touching the live SavedVariables file.
        [void](Test-LuaSavedVariablesText -Text $newText)

        $backup = $cf.File.FullName + ".pre-VoidMarkSync-" + $timestamp + ".bak"
        [IO.File]::Copy($cf.File.FullName, $backup, $false)

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $temp = $cf.File.FullName + ".VoidMarkSync.tmp"
        [IO.File]::WriteAllText($temp, $newText, $utf8NoBom)

        # Validate the bytes we actually wrote before replacing the live file.
        $tempText = [IO.File]::ReadAllText($temp)
        [void](Test-LuaSavedVariablesText -Text $tempText)

        [IO.File]::Copy($temp, $cf.File.FullName, $true)
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        $written++

        Write-Info ("Updated {0}\{1}  (validated; backup created)" -f $cf.Account, $cf.File.Name)
    }

    if ($DryRun) {
        Write-Info "Dry run complete. No files were changed."
    } else {
        Write-Host ""
        Write-Info "DONE. Updated $written account SavedVariables file(s)."
        Write-Info "Launch any account normally. GankRepository will rebuild indexes and load the merged historical floors on login."
        Write-Info "The accounts do NOT need to be online together; kills, historical floors, and DHKs are all merged offline."
    }
}
catch {
    Write-Bad $_.Exception.Message
    if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
        Write-Bad ("Script line: " + $_.InvocationInfo.ScriptLineNumber)
    }
    if ($_.ScriptStackTrace) {
        Write-Bad ("Stack: " + $_.ScriptStackTrace)
    }
    exit 1
}
