-- VoidMark Gank Repository
-- Persistent historical gank storage + two-account Battle.net synchronization.
-- v8.9 PERFORMANCE: death-frame network/history work deferred until combat ends.
-- v7.3: live-sync telemetry + merged-event range API for weekly reporting.
-- History is stored inside VoidMarkDB.TaliaaGankGlobal["Forever"].GankHistory and synced across accounts.

TaliaaGankRepository = TaliaaGankRepository or {}
local Repo = TaliaaGankRepository

local PREFIX = "TGANK2"
local SEP = "\031"
local CLUSTER = "Forever"
local VOIDMARK_REPO_BUILD = "2026-09-19-forever-beta-v0.1"
local HISTORY_VERSION = 8
local DEDUPE_SECONDS = 6
local SEND_INTERVAL = 0.08
local AUTO_PAIR_RETRY = 20
local AUTO_SYNC_RETRY = 8
local DIRECT_PAIR_MAX_ID = 100
local DIRECT_PAIR_STEP_DELAY = 0.08

local frame = CreateFrame("Frame")
local sendQueue = {}
local sendHead = 1
local sendTail = 0
local sendElapsed = 0
local syncSendNotBefore = 0

-- Fast differential sync state. Manual sync exchanges compact inventories of
-- known event IDs first, then sends only rows the other account is missing.
local ID_LIST_SEP = "\030"
local INVENTORY_CHUNK_BYTES = 150
local incomingInventories = {}

local pairing = false
local pairNonce = nil
local pairingSilent = false
local localSessionToken = nil

-- Expensive legacy/accent recovery is never allowed to run on the combat kill
-- path. Victims that need a deep identity repair are queued and reconciled
-- incrementally once combat has ended.
local deferredHistoricalQueue = {}
local deferredHistoricalHead = 1
local deferredHistoricalTail = 0
local deferredHistoricalKeys = {}
local deferredHistoricalElapsed = 0
local deferredHistoricalNotBefore = 0
local repositoryWasInCombat = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Taliaa Gank Repo]|r " .. tostring(msg))
end

local function Now()
    if GetServerTime then
        local t = GetServerTime()
        if t and t > 0 then return t end
    end
    return time()
end

-- WoW character names can contain accented Latin letters. Lua 5.1's
-- string.lower() is byte/ASCII oriented on Classic Era, so two visually identical
-- names can arrive through different APIs with case/diacritic variants and fail
-- an ordinary table lookup. Keep an accent-preserving fold for exact aliases and
-- a conservative ASCII fold for recovery-only matching.
local UTF8_LOWER = {
    ["À"]="à", ["Á"]="á", ["Â"]="â", ["Ã"]="ã", ["Ä"]="ä", ["Å"]="å",
    ["Æ"]="æ", ["Ç"]="ç", ["È"]="è", ["É"]="é", ["Ê"]="ê", ["Ë"]="ë",
    ["Ì"]="ì", ["Í"]="í", ["Î"]="î", ["Ï"]="ï", ["Ð"]="ð", ["Ñ"]="ñ",
    ["Ò"]="ò", ["Ó"]="ó", ["Ô"]="ô", ["Õ"]="õ", ["Ö"]="ö", ["Ø"]="ø",
    ["Ù"]="ù", ["Ú"]="ú", ["Û"]="û", ["Ü"]="ü", ["Ý"]="ý", ["Þ"]="þ",
    ["Œ"]="œ", ["Š"]="š", ["Ž"]="ž", ["Ÿ"]="ÿ",
}

local UTF8_ASCII = {
    ["à"]="a", ["á"]="a", ["â"]="a", ["ã"]="a", ["ä"]="a", ["å"]="a",
    ["æ"]="ae", ["ç"]="c", ["è"]="e", ["é"]="e", ["ê"]="e", ["ë"]="e",
    ["ì"]="i", ["í"]="i", ["î"]="i", ["ï"]="i", ["ð"]="d", ["ñ"]="n",
    ["ò"]="o", ["ó"]="o", ["ô"]="o", ["õ"]="o", ["ö"]="o", ["ø"]="o",
    ["ù"]="u", ["ú"]="u", ["û"]="u", ["ü"]="u", ["ý"]="y", ["ÿ"]="y",
    ["þ"]="th", ["ß"]="ss", ["œ"]="oe", ["š"]="s", ["ž"]="z",
}

local function UTF8CaseFold(value)
    local s = tostring(value or "")
    for upper, lower in pairs(UTF8_LOWER) do
        s = s:gsub(upper, lower)
    end
    return string.lower(s)
end

local function BasePlayerNameText(name)
    local s = tostring(name or "")
    if VoidMarkForever and VoidMarkForever.IsForever then
        -- On Forever the suffix is the mandatory secondary name, not a realm.
        return s
    end
    return s:match("^([^-]+)") or s
end

local function ExactPlayerNameKey(name)
    return UTF8CaseFold(tostring(name or ""))
end

local function CanonicalPlayerNameKey(name)
    local s = UTF8CaseFold(BasePlayerNameText(name))
    for accented, ascii in pairs(UTF8_ASCII) do
        s = s:gsub(accented, ascii)
    end
    return s
end

local function NormalizePlayerName(name)
    return CanonicalPlayerNameKey(name)
end

local function CleanField(value)
    local s = tostring(value or "")
    s = s:gsub(SEP, " ")
    s = s:gsub("|", "/")
    s = s:gsub("[%c]", " ")
    return s
end

local function SplitPayload(payload)
    local out = {}
    local start = 1
    payload = tostring(payload or "")
    while true do
        local p = payload:find(SEP, start, true)
        if not p then
            out[#out + 1] = payload:sub(start)
            break
        end
        out[#out + 1] = payload:sub(start, p - 1)
        start = p + 1
    end
    return out
end

-- Classic Era has used more than one BN_CHAT_MSG_ADDON argument layout.
-- Do not assume sender gameAccountID is always argument #4; find the first
-- numeric value after prefix/payload, matching the relay code that is known
-- to work on this client branch.
local function ExtractBNetSenderID(...)
    local args = {...}

    for i = 3, #args do
        if type(args[i]) == "number" then
            return args[i]
        end
    end

    for i = 3, #args do
        local v = args[i]
        if type(v) == "string" and v:match("^%d+$") then
            return tonumber(v)
        end
    end

    return nil
end

local function IsPlayerGUID(guid)
    guid = tostring(guid or "")
    return guid:sub(1, 6) == "Player"
end

local function IsExplicitNonPlayerGUID(guid)
    guid = tostring(guid or "")
    return guid ~= "" and not IsPlayerGUID(guid)
end


local function InCombatNow()
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function CurrentFaction()
    if VoidMark and VoidMark.FactionName and VoidMark.FactionName ~= "" then
        return VoidMark.FactionName
    end
    return UnitFactionGroup("player") or "Unknown"
end

local function HashString(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 2147483647
    end
    return h
end

local function EnsureLocalSessionToken()
    if localSessionToken and localSessionToken ~= "" then
        return localSessionToken
    end

    local seed = table.concat({
        tostring(UnitGUID("player") or ""),
        tostring(UnitName("player") or ""),
        tostring(Now()),
        tostring(GetTime and GetTime() or 0),
        tostring(math.random(100000, 999999)),
    }, ":")

    localSessionToken = "s" .. string.format("%x", HashString(seed))
    return localSessionToken
end

local function EnsureSyncDB()
    if not VoidMarkDB then return nil end
    VoidMarkDB.TaliaaGankSync = VoidMarkDB.TaliaaGankSync or {}
    local db = VoidMarkDB.TaliaaGankSync
    db.version = 3
    if db.enabled == nil then db.enabled = true end
    if db.autoPair == nil then db.autoPair = true end
    if db.autoSync == nil then db.autoSync = true end
    db.nextSeq = tonumber(db.nextSeq) or 0
    db.nextDHKSeq = tonumber(db.nextDHKSeq) or 0

    -- Event IDs must be unique even if SavedVariables were copied between WoW
    -- accounts.  Older builds stored one random nodeID in VoidMarkDB; cloning that DB
    -- could make Rogue and Priest generate colliding event IDs.  Tie the node to
    -- the current character GUID instead.  Switching characters intentionally
    -- changes the node while preserving the shared repository.
    local ownerGUID = tostring(UnitGUID("player") or "")
    if ownerGUID ~= "" and (db.nodeOwnerGUID ~= ownerGUID or not db.nodeID or db.nodeID == "") then
        local seed = ownerGUID .. ":" .. tostring(UnitName("player") or "") .. ":" .. tostring(GetRealmName and GetRealmName() or "")
        db.nodeID = "c" .. string.format("%x", HashString(seed))
        db.nodeOwnerGUID = ownerGUID
    elseif not db.nodeID or db.nodeID == "" then
        local seed = tostring(UnitName("player") or "") .. ":" .. tostring(Now())
        db.nodeID = "c" .. string.format("%x", HashString(seed))
    end

    return db
end

local function EnsureHistory()
    if not VoidMarkDB then return nil end

    -- Gank history is deliberately account-wide and faction-neutral.  VoidMark's
    -- player/KOS database can stay faction-separated, but the user wants one
    -- combined kill ledger across Priest/Rogue and both WoW accounts.
    VoidMarkDB.TaliaaGankGlobal = VoidMarkDB.TaliaaGankGlobal or {}
    VoidMarkDB.TaliaaGankGlobal[CLUSTER] = VoidMarkDB.TaliaaGankGlobal[CLUSTER] or {}

    local shared = VoidMarkDB.TaliaaGankGlobal[CLUSTER]
    shared.GankHistory = shared.GankHistory or {}
    local history = shared.GankHistory
    history.version = HISTORY_VERSION
    history.events = history.events or {}
    history.victims = history.victims or {}
    history.seenIDs = history.seenIDs or {}
    history.eventCount = tonumber(history.eventCount) or 0
    -- Per-victim legacy metadata preserves kills that predate the timestamped
    -- repository. v8 stores the missing historical amount as legacyGap so it can
    -- be synchronized safely between WoW accounts regardless of how many event
    -- rows each account had when the old total was discovered. Older floor/
    -- repoAtCapture entries are migrated lazily.
    history.legacyFloors = history.legacyFloors or {}

    return history
end

local function EnsureDHKHistory()
    if not VoidMarkDB then return nil end

    -- Same storage scope as GankHistory: shared by all characters on this WoW
    -- account and synchronized to the paired second WoW account.
    VoidMarkDB.TaliaaGankGlobal = VoidMarkDB.TaliaaGankGlobal or {}
    VoidMarkDB.TaliaaGankGlobal[CLUSTER] = VoidMarkDB.TaliaaGankGlobal[CLUSTER] or {}

    local shared = VoidMarkDB.TaliaaGankGlobal[CLUSTER]
    shared.DHKHistory = shared.DHKHistory or {}
    local history = shared.DHKHistory
    history.version = 1
    history.events = history.events or {}
    history.seenIDs = history.seenIDs or {}
    history.eventCount = tonumber(history.eventCount) or 0
    return history
end

local function NormalizeDHKMessage(message)
    local s = tostring(message or ""):lower()
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("%s+", " ")
    return s
end

local function NormalizeDHKCharacter(character)
    return string.lower(tostring(character or ""))
end

local function IsSameDHK(history, event)
    local eventTime = tonumber(event and event.t) or 0
    local eventMessage = NormalizeDHKMessage(event and event.message)
    local eventCharacter = NormalizeDHKCharacter(event and event.character)

    if eventTime <= 0 or eventMessage == "" then return false end

    -- IMPORTANT: a civilian kill can award a DHK to more than one of the user's
    -- logged-in characters at the same instant. Those are TWO account-wide DHKs,
    -- not duplicate network packets. Only collapse the same message/time when it
    -- belongs to the SAME character.
    for _, old in pairs(history.events or {}) do
        if type(old) == "table" then
            local oldTime = tonumber(old.t) or 0
            local oldCharacter = NormalizeDHKCharacter(old.character)

            if oldCharacter == eventCharacter
                and math.abs(oldTime - eventTime) <= 1
                and NormalizeDHKMessage(old.message) == eventMessage then
                return true
            end
        end
    end

    return false
end

local function AddDHKEvent(event, suppressNotify)
    local history = EnsureDHKHistory()
    if not history or type(event) ~= "table" or not event.id then
        return false, 0, "no database"
    end

    local eventID = tostring(event.id)
    if history.events[eventID] or history.seenIDs[eventID] then
        return false, tonumber(history.eventCount) or 0, "known id"
    end

    if IsSameDHK(history, event) then
        history.seenIDs[eventID] = true
        return false, tonumber(history.eventCount) or 0, "same dhk"
    end

    event.id = eventID
    event.t = tonumber(event.t) or Now()
    event.message = tostring(event.message or "")
    event.character = tostring(event.character or "")
    event.zone = tostring(event.zone or "")
    event.faction = tostring(event.faction or CurrentFaction())
    event.source = tostring(event.source or "")

    history.events[eventID] = event
    history.seenIDs[eventID] = true
    history.eventCount = (tonumber(history.eventCount) or 0) + 1

    if not suppressNotify and TaliaaGankTracker and TaliaaGankTracker.OnDHKHistoryUpdated then
        TaliaaGankTracker:OnDHKHistoryUpdated()
    end

    return true, history.eventCount
end

local function ImportLegacyDHKHistory()
    if not VoidMarkDB or type(VoidMarkDB.TaliaaGankDHKHistory) ~= "table" then
        return 0
    end

    local legacy = VoidMarkDB.TaliaaGankDHKHistory
    if type(legacy.events) ~= "table" then return 0 end

    local imported = 0
    for legacyID, event in pairs(legacy.events) do
        if type(event) == "table" then
            local raw = table.concat({
                tostring(event.t or 0),
                tostring(event.character or ""),
                tostring(event.message or ""),
                tostring(legacyID or ""),
            }, "|")

            local copy = {
                id = "LDHK-" .. string.format("%x", HashString(raw)) .. "-" .. tostring(tonumber(event.t) or 0),
                t = tonumber(event.t) or 0,
                character = tostring(event.character or ""),
                message = tostring(event.message or ""),
                zone = tostring(event.zone or ""),
                faction = tostring(event.faction or ""),
            }

            local added = AddDHKEvent(copy, true)
            if added then imported = imported + 1 end
        end
    end

    return imported
end

local function RepairDHKHistory()
    local history = EnsureDHKHistory()
    if not history then return 0 end

    local seen = {}
    local count = 0
    for id, event in pairs(history.events or {}) do
        if type(event) == "table" then
            local eventID = tostring(event.id or id)
            event.id = eventID
            seen[eventID] = true
            count = count + 1
        end
    end

    history.seenIDs = seen
    history.eventCount = count
    return count
end

local function IsBrokenSyntheticDHK(event)
    if type(event) ~= "table" then return false end
    local source = string.lower(tostring(event.source or ""))
    local message = string.lower(tostring(event.message or ""))

    if source == "api" then return true end
    if source == "blizzard-session-api" then return false end

    -- Previous experimental builds used these messages without a reliable source.
    if message:match("^blizzard dhk #%d+$") then return true end
    if message:match("^blizzard today dhk #%d+$") then
        return source ~= "blizzard-session-api"
    end

    return false
end

local function NormalizeCharacterKey(character)
    return string.lower(tostring(character or ""))
end

local function RemoveBrokenSyntheticDHKsForCharacterInRange(character, startTime, endTime, authoritativeCount)
    local history = EnsureDHKHistory()
    if not history then return 0 end

    local want = NormalizeCharacterKey(character)
    local first = tonumber(startTime) or 0
    local last = tonumber(endTime) or (Now() + 60)
    local expected = tonumber(authoritativeCount) or 0

    local current = 0
    local broken = {}
    for id, event in pairs(history.events or {}) do
        if type(event) == "table"
            and NormalizeCharacterKey(event.character) == want then
            local t = tonumber(event.t) or 0
            if t >= first and t <= last then
                current = current + 1
                if IsBrokenSyntheticDHK(event) then
                    broken[#broken + 1] = { id = id, t = t }
                end
            end
        end
    end

    local excess = math.max(0, current - expected)
    if excess <= 0 or #broken == 0 then return 0 end

    table.sort(broken, function(a, b) return a.t > b.t end)
    local removed = 0

    for i = 1, math.min(excess, #broken) do
        history.events[broken[i].id] = nil
        removed = removed + 1
    end

    if removed > 0 then RepairDHKHistory() end
    return removed
end

local function PurgeExplicitNonPlayerHistory()
    local history = EnsureHistory()
    if not history then return 0, 0 end

    local removedEvents = 0
    local removedVictims = 0

    -- Remove timestamped kills that are explicitly pets/NPCs/etc. Empty GUIDs are
    -- retained because some old legitimate player history was recovered without GUIDs.
    for id, event in pairs(history.events or {}) do
        if type(event) == "table" and IsExplicitNonPlayerGUID(event.guid) then
            history.events[id] = nil
            removedEvents = removedEvents + 1
        end
    end

    for key, victim in pairs(history.victims or {}) do
        if type(victim) == "table" and IsExplicitNonPlayerGUID(victim.guid) then
            history.victims[key] = nil
            removedVictims = removedVictims + 1
        end
    end

    return removedEvents, removedVictims
end

local function RecoveryEventSignature(event)
    if type(event) ~= "table" then return "" end
    return table.concat({
        tostring(event.t or 0),
        tostring(event.name or ""),
        tostring(event.guid or ""),
        tostring(event.zone or ""),
        tostring(event.subZone or ""),
        tostring(event.level or ""),
        tostring(event.class or ""),
        tostring(event.killer or ""),
        tostring(event.faction or ""),
    }, "|")
end

local function RecoveryCollisionID(eventID, event)
    local raw = tostring(eventID or "") .. "|" .. RecoveryEventSignature(event)
    return "R" .. string.format("%x", HashString(raw)) .. "-" .. tostring(tonumber(event and event.t) or 0)
end

local function ImportRecoveryLedger()
    if not VoidMarkDB or type(VoidMarkDB.TaliaaGankRecoveryLedger) ~= "table" then
        return 0, 0, 0
    end

    local ledger = VoidMarkDB.TaliaaGankRecoveryLedger
    local history = EnsureHistory()
    if not history or type(ledger.events) ~= "table" then
        return 0, tonumber(ledger.count) or 0, tonumber(ledger.unresolved) or 0
    end

    local imported = 0
    for id, event in pairs(ledger.events) do
        if type(event) == "table" then
            local eventID = tostring(event.id or id or "")
            if eventID ~= "" then
                local existing = history.events[eventID]

                -- If the ID is unused, import normally.
                if existing == nil then
                    local copy = {}
                    for k, v in pairs(event) do copy[k] = v end
                    copy.id = eventID
                    history.events[eventID] = copy
                    imported = imported + 1

                -- If the same ID already represents the same kill, it is already
                -- present and should not be duplicated.
                elseif RecoveryEventSignature(existing) == RecoveryEventSignature(event) then
                    -- already represented

                -- If the same ID represents a DIFFERENT kill, preserve both by
                -- assigning the recovery row a stable collision-safe ID.
                else
                    local newID = RecoveryCollisionID(eventID, event)
                    local n = 1
                    while history.events[newID] ~= nil
                        and RecoveryEventSignature(history.events[newID]) ~= RecoveryEventSignature(event) do
                        n = n + 1
                        newID = RecoveryCollisionID(eventID .. "-" .. tostring(n), event)
                    end

                    if history.events[newID] == nil then
                        local copy = {}
                        for k, v in pairs(event) do copy[k] = v end
                        copy.id = newID
                        copy.recoveryOriginalID = eventID
                        history.events[newID] = copy
                        imported = imported + 1
                    end
                end
            end
        end
    end

    ledger.lastImportedAt = Now()
    ledger.lastImportedCount = imported
    return imported, tonumber(ledger.count) or 0, tonumber(ledger.unresolved) or 0
end

function Repo:GetRecoveryLedgerStats()
    local ledger = VoidMarkDB and VoidMarkDB.TaliaaGankRecoveryLedger
    if type(ledger) ~= "table" then return 0, 0, 0 end
    return tonumber(ledger.count) or 0,
           tonumber(ledger.unresolved) or 0,
           tonumber(ledger.generatedAt) or 0
end

local function LegacyFactionHistories()
    local out = {}
    if not VoidMarkDB or not VoidMarkDB.TaliaaShared then return out end
    local cluster = VoidMarkDB.TaliaaShared[CLUSTER]
    if type(cluster) ~= "table" then return out end

    for faction, shared in pairs(cluster) do
        if type(shared) == "table" and type(shared.GankHistory) == "table" then
            out[#out + 1] = { faction = tostring(faction), history = shared.GankHistory }
        end
    end
    return out
end

-- Build a stable import ID from the actual kill data instead of trusting the
-- old repository event ID.  This matters when two WoW accounts were created
-- from the same SavedVariables file and therefore reused the same old nodeID.
local function LegacyImportID(event, fallbackID, faction)
    local raw = table.concat({
        tostring(event and event.t or 0),
        tostring(event and event.name or "?"),
        tostring(event and event.guid or ""),
        tostring(event and event.killer or ""),
        tostring(event and event.zone or ""),
        tostring(event and event.subZone or ""),
        tostring(faction or ""),
        tostring(fallbackID or ""),
    }, "|")
    return "L" .. string.format("%x", HashString(raw)) .. "-" .. tostring(tonumber(event and event.t) or 0)
end

-- Copy old faction-scoped repository rows into the new global ledger.  Imported
-- IDs are canonicalized so colliding legacy IDs from different accounts do not
-- silently erase one character's kills. RepairLegacyHistory() then removes true
-- same-death duplicates by victim + timestamp.
local function ImportLegacyFactionEvents()
    local dst = EnsureHistory()
    if not dst then return 0 end
    local imported = 0

    for _, source in ipairs(LegacyFactionHistories()) do
        local src = source.history
        if src ~= dst then
            for id, event in pairs(src.events or {}) do
                if type(event) == "table" then
                    local oldID = tostring(event.id or id or "")
                    local eventID = LegacyImportID(event, oldID, source.faction)
                    if dst.events[eventID] == nil then
                        local copy = {}
                        for k, v in pairs(event) do copy[k] = v end
                        copy.id = eventID
                        copy.legacyID = oldID
                        if not copy.faction or copy.faction == "" then copy.faction = source.faction end
                        dst.events[eventID] = copy
                        imported = imported + 1
                    end
                end
            end

            -- Some early builds retained timestamps only under victim.events.
            for _, victim in pairs(src.victims or {}) do
                if type(victim) == "table" and type(victim.events) == "table" then
                    for eventID, stamp in pairs(victim.events) do
                        local oldID = tostring(eventID or "")
                        local synthetic = {
                            t = tonumber(stamp) or tonumber(victim.lastKill) or 0,
                            name = tostring(victim.name or "?"),
                            guid = tostring(victim.guid or ""),
                            zone = tostring(victim.lastZone or "Unknown"),
                            subZone = tostring(victim.lastSubZone or ""),
                            level = victim.lastLevel or "?",
                            class = victim.lastClass or "",
                            killer = tostring(victim.lastKiller or ""),
                            faction = source.faction,
                        }
                        local canonicalID = LegacyImportID(synthetic, oldID, source.faction)
                        if dst.events[canonicalID] == nil then
                            synthetic.id = canonicalID
                            synthetic.legacyID = oldID
                            dst.events[canonicalID] = synthetic
                            imported = imported + 1
                        end
                    end
                end
            end
        end
    end

    return imported
end

local QueueLegacyFloorToPeer

local function VictimKey(name, guid)
    guid = tostring(guid or "")
    if guid:sub(1, 6) == "Player" then
        return "G:" .. guid
    end
    return "N:" .. ExactPlayerNameKey(tostring(name or "?"))
end

local function FindVictimByName(history, name)
    if not history or not name then return nil end

    local wantFull = ExactPlayerNameKey(name)
    local wantBase = ExactPlayerNameKey(BasePlayerNameText(name))
    local wantCanonical = CanonicalPlayerNameKey(name)
    local exactBaseVictim, exactBaseKey, exactBaseMatches = nil, nil, 0
    local canonicalVictim, canonicalKey, canonicalMatches = nil, nil, 0

    for key, victim in pairs(history.victims or {}) do
        if victim and victim.name then
            local haveFull = ExactPlayerNameKey(victim.name)
            if haveFull == wantFull then
                return victim, key
            end

            if ExactPlayerNameKey(BasePlayerNameText(victim.name)) == wantBase then
                exactBaseMatches = exactBaseMatches + 1
                exactBaseVictim, exactBaseKey = victim, key
            end

            if wantCanonical ~= "" and CanonicalPlayerNameKey(victim.name) == wantCanonical then
                canonicalMatches = canonicalMatches + 1
                canonicalVictim, canonicalKey = victim, key
            end
        end
    end

    if exactBaseMatches == 1 then
        return exactBaseVictim, exactBaseKey
    end

    -- Accent-fold recovery is intentionally last and only accepted when unique.
    -- That fixes names such as Izihørdekids/Izihòrdekids without ever combining
    -- two different historical players just because their accents fold alike.
    if canonicalMatches == 1 then
        return canonicalVictim, canonicalKey
    end
end

local function FindVoidMarkPlayerData(name, guid)
    local playerData = VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData
    if type(playerData) ~= "table" then return nil, nil, nil end

    local rawName = tostring(name or "")
    local baseName = BasePlayerNameText(rawName)

    if type(playerData[rawName]) == "table" then
        return playerData[rawName], rawName, "exact"
    end
    if baseName ~= rawName and type(playerData[baseName]) == "table" then
        return playerData[baseName], baseName, "base"
    end

    local guidText = tostring(guid or "")
    local wantFull = ExactPlayerNameKey(rawName)
    local wantBase = ExactPlayerNameKey(baseName)
    local wantCanonical = CanonicalPlayerNameKey(rawName)
    local exactData, exactKey, exactMatches = nil, nil, 0
    local canonicalData, canonicalKey, canonicalMatches = nil, nil, 0

    for key, data in pairs(playerData) do
        if type(data) == "table" then
            if IsPlayerGUID(guidText) and tostring(data.guid or data.GUID or "") == guidText then
                return data, key, "guid"
            end

            local keyFull = ExactPlayerNameKey(key)
            local keyBase = ExactPlayerNameKey(BasePlayerNameText(key))
            if keyFull == wantFull or keyBase == wantBase then
                exactMatches = exactMatches + 1
                exactData, exactKey = data, key
            elseif wantCanonical ~= "" and CanonicalPlayerNameKey(key) == wantCanonical then
                canonicalMatches = canonicalMatches + 1
                canonicalData, canonicalKey = data, key
            end
        end
    end

    if exactMatches == 1 then
        return exactData, exactKey, "folded"
    end
    if canonicalMatches == 1 then
        return canonicalData, canonicalKey, "accent"
    end
    return nil, nil, canonicalMatches > 1 and "ambiguous" or "none"
end

-- Return the repository event count for one victim without losing older
-- name-only rows. GUID rows are authoritative; one unique legacy name alias may
-- also be included because older imports sometimes lacked a GUID.
local function IndexedVictimEventCount(history, name, guid)
    if not history then return 0 end

    local count = 0
    local counted = {}
    local guidText = tostring(guid or "")

    if IsPlayerGUID(guidText) then
        local victim = history.victims and history.victims[VictimKey(name, guidText)]
        if type(victim) == "table" then
            count = count + (tonumber(victim.kills) or 0)
            counted[victim] = true
        end

        local byName = FindVictimByName(history, name)
        if type(byName) == "table" and not counted[byName]
            and not IsPlayerGUID(byName.guid) then
            count = count + (tonumber(byName.kills) or 0)
            counted[byName] = true
        end
    else
        local victim = history.victims and history.victims[VictimKey(name, "")]
        if type(victim) == "table" then
            count = count + (tonumber(victim.kills) or 0)
            counted[victim] = true
        end

        local byName = FindVictimByName(history, name)
        if type(byName) == "table" and not counted[byName] then
            count = count + (tonumber(byName.kills) or 0)
        end
    end

    return count
end

local function VoidMarkLifetimeWins(name, guid)
    local data, matchedKey, method = FindVoidMarkPlayerData(name, guid)
    return type(data) == "table" and (tonumber(data.wins) or 0) or 0,
           matchedKey, method
end

-- Read-only VoidMark identity index for the combat hot path. Built outside combat and
-- stores references to VoidMark player tables, so a player's .wins value stays fresh
-- without rebuilding the index after every kill.
local voidmarkFastIndex = { exact = {}, canonical = {}, guid = {}, ready = false }

local function RebuildVoidMarkFastIndex()
    if InCombatNow() then return false end
    local playerData = VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData
    if type(playerData) ~= "table" then return false end

    local exact, canonical, byGUID = {}, {}, {}
    for key, data in pairs(playerData) do
        if type(data) == "table" then
            local exactKey = ExactPlayerNameKey(key)
            if exactKey ~= "" then
                if exact[exactKey] == nil then exact[exactKey] = data
                elseif exact[exactKey] ~= data then exact[exactKey] = false end
            end

            local canonicalKey = CanonicalPlayerNameKey(key)
            if canonicalKey ~= "" then
                if canonical[canonicalKey] == nil then canonical[canonicalKey] = data
                elseif canonical[canonicalKey] ~= data then canonical[canonicalKey] = false end
            end

            local g = tostring(data.guid or data.GUID or "")
            if IsPlayerGUID(g) then byGUID[g] = data end
        end
    end

    voidmarkFastIndex.exact = exact
    voidmarkFastIndex.canonical = canonical
    voidmarkFastIndex.guid = byGUID
    voidmarkFastIndex.ready = true
    return true
end

local function FastVoidMarkLifetimeWins(name, guid)
    local playerData = VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData
    local rawName = tostring(name or "")
    local baseName = BasePlayerNameText(rawName)

    -- Newly seen players can appear after the index build; direct keys remain O(1).
    if type(playerData) == "table" then
        local data = playerData[rawName]
        if type(data) ~= "table" and baseName ~= rawName then data = playerData[baseName] end
        if type(data) == "table" then return tonumber(data.wins) or 0 end
    end

    if voidmarkFastIndex.ready then
        local g = tostring(guid or "")
        local data = IsPlayerGUID(g) and voidmarkFastIndex.guid[g] or nil
        if type(data) ~= "table" then
            data = voidmarkFastIndex.exact[ExactPlayerNameKey(rawName)]
        end
        if type(data) ~= "table" then
            local canonical = voidmarkFastIndex.canonical[CanonicalPlayerNameKey(rawName)]
            if canonical and canonical ~= false then data = canonical end
        end
        if type(data) == "table" then return tonumber(data.wins) or 0 end
    end

    return 0
end

local function LegacyUnresolvedExtra(history, name, guid)
    if not history or type(history.legacyUnresolved) ~= "table" then return 0 end

    local best = 0
    local rawName = tostring(name or "")
    local baseName = BasePlayerNameText(rawName)
    local guidText = tostring(guid or "")

    local function Consider(key)
        if key and key ~= "" then
            best = math.max(best, tonumber(history.legacyUnresolved[key]) or 0)
        end
    end

    Consider(guidText)
    Consider(rawName)
    Consider(baseName)

    local wantExact = ExactPlayerNameKey(rawName)
    local wantBase = ExactPlayerNameKey(baseName)
    local wantCanonical = CanonicalPlayerNameKey(rawName)
    local canonicalValue, canonicalMatches = 0, 0

    for key, value in pairs(history.legacyUnresolved) do
        if not IsPlayerGUID(key) then
            local exact = ExactPlayerNameKey(key)
            local exactBase = ExactPlayerNameKey(BasePlayerNameText(key))
            if exact == wantExact or exactBase == wantBase then
                best = math.max(best, tonumber(value) or 0)
            elseif wantCanonical ~= "" and CanonicalPlayerNameKey(key) == wantCanonical then
                canonicalMatches = canonicalMatches + 1
                canonicalValue = math.max(canonicalValue, tonumber(value) or 0)
            end
        end
    end

    if canonicalMatches == 1 then
        best = math.max(best, canonicalValue)
    end
    return best
end

local function LegacyGapFromEntry(entry)
    if type(entry) ~= "table" then return 0 end
    local gap = tonumber(entry.legacyGap)
    if gap then return math.max(0, gap) end

    -- v7 stored an absolute floor plus the repository size at capture. Convert
    -- that into the portable missing-kill amount used by v8.
    local floor = tonumber(entry.floor) or 0
    local repoAtCapture = tonumber(entry.repoAtCapture) or 0
    gap = math.max(0, floor - repoAtCapture)
    entry.legacyGap = gap
    entry.version = 2
    return gap
end

-- Combat-safe historical lookup. This deliberately uses ONLY direct table
-- lookups: no pairs() walks over PlayerData, victims, unresolved history or
-- legacy floors. Deep accent/alias recovery is queued for after combat.
local function FastHistoricalCount(history, name, guid)
    if not history then return 0, 0, 0, 0, nil end

    local rawName = tostring(name or "")
    local baseName = BasePlayerNameText(rawName)
    local guidText = tostring(guid or "")
    local eventCount = 0
    local counted = {}

    local victim = history.victims and history.victims[VictimKey(rawName, guidText)]
    if type(victim) == "table" then
        eventCount = eventCount + (tonumber(victim.kills) or 0)
        counted[victim] = true
    end

    -- Old imports can have a name-only victim row even after a GUID becomes
    -- available. Exact accent-preserving lookup is still O(1).
    local nameVictim = history.victims and history.victims["N:" .. ExactPlayerNameKey(rawName)]
    if type(nameVictim) == "table" and not counted[nameVictim] then
        eventCount = eventCount + (tonumber(nameVictim.kills) or 0)
        counted[nameVictim] = true
    end
    if baseName ~= rawName then
        local baseVictim = history.victims and history.victims["N:" .. ExactPlayerNameKey(baseName)]
        if type(baseVictim) == "table" and not counted[baseVictim] then
            eventCount = eventCount + (tonumber(baseVictim.kills) or 0)
            counted[baseVictim] = true
        end
    end

    local voidmarkWins = FastVoidMarkLifetimeWins(rawName, guidText)

    local unresolved = 0
    local old = history.legacyUnresolved
    if type(old) == "table" then
        if guidText ~= "" then unresolved = math.max(unresolved, tonumber(old[guidText]) or 0) end
        if rawName ~= "" then unresolved = math.max(unresolved, tonumber(old[rawName]) or 0) end
        if baseName ~= "" then unresolved = math.max(unresolved, tonumber(old[baseName]) or 0) end
    end

    history.legacyFloors = history.legacyFloors or {}
    local floorKey = VictimKey(rawName, guidText)
    local entryKey = floorKey
    local entry = history.legacyFloors[floorKey]
    if type(entry) ~= "table" then
        entryKey = "N:" .. ExactPlayerNameKey(rawName)
        entry = history.legacyFloors[entryKey]
    end
    if type(entry) ~= "table" and baseName ~= rawName then
        entryKey = "N:" .. ExactPlayerNameKey(baseName)
        entry = history.legacyFloors[entryKey]
    end

    local knownGap = LegacyGapFromEntry(entry)

    -- v8.9: this function is now strictly read-only on the combat hot path.
    -- Do not migrate keys, mutate legacy floors or queue BNet metadata here.
    -- The deep deferred recovery pass persists any newly observed VoidMark/legacy gap
    -- once combat is over. The max() below still returns the correct visible
    -- historical total immediately, even before that floor is persisted.
    local total = math.max(eventCount + knownGap, eventCount, voidmarkWins, eventCount + unresolved)
    return total, eventCount, voidmarkWins, unresolved, entry
end

local function QueueDeferredHistoricalRecovery(name, guid, notifyTracker)
    local rawName = tostring(name or "")
    local guidText = tostring(guid or "")
    if rawName == "" and guidText == "" then return end

    local key = IsPlayerGUID(guidText) and ("G:" .. guidText) or ("N:" .. ExactPlayerNameKey(rawName))
    local existing = deferredHistoricalKeys[key]
    if existing then
        if notifyTracker then existing.notifyTracker = true end
        if rawName ~= "" then existing.name = rawName end
        if guidText ~= "" then existing.guid = guidText end
        return
    end

    local item = { name = rawName, guid = guidText, notifyTracker = notifyTracker and true or false, key = key }
    deferredHistoricalTail = deferredHistoricalTail + 1
    deferredHistoricalQueue[deferredHistoricalTail] = item
    deferredHistoricalKeys[key] = item
end

local function FindLegacyFloor(history, name, guid)
    if not history or type(history.legacyFloors) ~= "table" then return nil, nil end

    local key = VictimKey(name, guid)
    if type(history.legacyFloors[key]) == "table" then
        return history.legacyFloors[key], key
    end

    local guidText = tostring(guid or "")
    local wantExact = ExactPlayerNameKey(name)
    local wantBase = ExactPlayerNameKey(BasePlayerNameText(name))
    local wantCanonical = CanonicalPlayerNameKey(name)
    local exactEntry, exactKey, exactMatches = nil, nil, 0
    local canonicalEntry, canonicalKey, canonicalMatches = nil, nil, 0

    for oldKey, entry in pairs(history.legacyFloors) do
        if type(entry) == "table" then
            if IsPlayerGUID(guidText) and tostring(entry.guid or "") == guidText then
                return entry, oldKey
            end

            local entryName = tostring(entry.name or "")
            if entryName ~= "" then
                local full = ExactPlayerNameKey(entryName)
                local base = ExactPlayerNameKey(BasePlayerNameText(entryName))
                if full == wantExact or base == wantBase then
                    exactMatches = exactMatches + 1
                    exactEntry, exactKey = entry, oldKey
                elseif wantCanonical ~= "" and CanonicalPlayerNameKey(entryName) == wantCanonical then
                    canonicalMatches = canonicalMatches + 1
                    canonicalEntry, canonicalKey = entry, oldKey
                end
            end
        end
    end

    if exactMatches == 1 then return exactEntry, exactKey end
    if canonicalMatches == 1 then return canonicalEntry, canonicalKey end
    return nil, nil
end

local function MergeLegacyGap(history, name, guid, incomingGap, suppressSync)
    if not history then return nil, false end
    history.legacyFloors = history.legacyFloors or {}

    local gap = math.max(0, tonumber(incomingGap) or 0)
    if gap <= 0 then return nil, false end

    local wantedKey = VictimKey(name, guid)
    local entry, oldKey = FindLegacyFloor(history, name, guid)

    -- Once the real GUID is known, move a unique older name-only floor to the
    -- GUID key. This permanently resolves later spelling/accent differences.
    if entry and IsPlayerGUID(guid) and oldKey ~= wantedKey then
        history.legacyFloors[oldKey] = nil
        history.legacyFloors[wantedKey] = entry
        oldKey = wantedKey
    end

    if not entry then
        entry = {
            legacyGap = gap,
            name = tostring(name or "?"),
            guid = tostring(guid or ""),
            capturedAt = Now(),
            version = 2,
        }
        history.legacyFloors[wantedKey] = entry
    end

    local oldGap = LegacyGapFromEntry(entry)
    local changed = gap > oldGap
    if changed then entry.legacyGap = gap end
    if name and name ~= "" then entry.name = tostring(name) end
    if IsPlayerGUID(guid) then entry.guid = tostring(guid) end
    entry.version = 2

    -- Keep the old fields populated for readable diagnostics/backward safety,
    -- but calculations use legacyGap from this build onward.
    local eventCount = IndexedVictimEventCount(history, name, guid)
    entry.repoAtCapture = eventCount
    entry.floor = eventCount + LegacyGapFromEntry(entry)
    if changed then entry.capturedAt = Now() end

    if changed and not suppressSync and QueueLegacyFloorToPeer then
        QueueLegacyFloorToPeer(entry)
    end
    return entry, changed
end

local function CompactLegacyFloors(history)
    if not history or type(history.legacyFloors) ~= "table" then return 0 end
    local floors = history.legacyFloors
    local removed = 0

    -- First collapse all entries carrying the same real player GUID.
    local guidOwner = {}
    local snapshot = {}
    for key, entry in pairs(floors) do
        snapshot[#snapshot + 1] = { key = key, entry = entry }
    end

    for _, item in ipairs(snapshot) do
        local key, entry = item.key, item.entry
        if floors[key] == entry and type(entry) == "table" then
            local guid = tostring(entry.guid or "")
            if IsPlayerGUID(guid) then
                local desiredKey = "G:" .. guid
                local owner = guidOwner[guid] or floors[desiredKey]
                if owner and owner ~= entry then
                    if LegacyGapFromEntry(entry) > LegacyGapFromEntry(owner) then
                        owner.legacyGap = LegacyGapFromEntry(entry)
                        owner.name = entry.name or owner.name
                        owner.capturedAt = math.max(tonumber(owner.capturedAt) or 0, tonumber(entry.capturedAt) or 0)
                    end
                    floors[key] = nil
                    removed = removed + 1
                else
                    if key ~= desiredKey then
                        floors[key] = nil
                        floors[desiredKey] = entry
                        removed = removed + 1
                    end
                    guidOwner[guid] = entry
                end
            end
        end
    end

    -- Then attach a name-only floor to a GUID floor only when that GUID match is
    -- unique. Exact accent-preserving name wins; ASCII accent folding is fallback.
    local guidEntries = {}
    for key, entry in pairs(floors) do
        if type(entry) == "table" and IsPlayerGUID(entry.guid) then
            guidEntries[#guidEntries + 1] = { key = key, entry = entry }
        end
    end

    snapshot = {}
    for key, entry in pairs(floors) do
        if type(entry) == "table" and not IsPlayerGUID(entry.guid) then
            snapshot[#snapshot + 1] = { key = key, entry = entry }
        end
    end

    for _, item in ipairs(snapshot) do
        local key, entry = item.key, item.entry
        if floors[key] == entry then
            local exactWant = ExactPlayerNameKey(BasePlayerNameText(entry.name))
            local canonicalWant = CanonicalPlayerNameKey(entry.name)
            local exactMatch, exactCount = nil, 0
            local canonicalMatch, canonicalCount = nil, 0

            for _, candidate in ipairs(guidEntries) do
                local c = candidate.entry
                if ExactPlayerNameKey(BasePlayerNameText(c.name)) == exactWant then
                    exactCount = exactCount + 1
                    exactMatch = c
                elseif canonicalWant ~= "" and CanonicalPlayerNameKey(c.name) == canonicalWant then
                    canonicalCount = canonicalCount + 1
                    canonicalMatch = c
                end
            end

            local target = exactCount == 1 and exactMatch
                or (exactCount == 0 and canonicalCount == 1 and canonicalMatch)
            if target then
                if LegacyGapFromEntry(entry) > LegacyGapFromEntry(target) then
                    target.legacyGap = LegacyGapFromEntry(entry)
                end
                floors[key] = nil
                removed = removed + 1
            end
        end
    end

    return removed
end

-- Historical = timestamped repository rows + the old kills that were never
-- represented by rows. The portable legacyGap is the critical piece: it avoids
-- double-counting overlap and remains correct after cross-account/file merges.
local function HistoricalCountWithFloor(history, name, guid, allowCreate, suppressSync)
    if not history then return 0, 0, 0, 0, nil, nil, nil end

    history.legacyFloors = history.legacyFloors or {}

    local eventCount = IndexedVictimEventCount(history, name, guid)
    local voidmarkWins, voidmarkKey, voidmarkMethod = VoidMarkLifetimeWins(name, guid)
    local unresolved = LegacyUnresolvedExtra(history, name, guid)
    local observedGap = math.max(0, voidmarkWins - eventCount, unresolved)

    local entry = FindLegacyFloor(history, name, guid)
    local knownGap = LegacyGapFromEntry(entry)

    -- Bind a previously name-only floor to the real GUID as soon as we have it,
    -- even when the numerical gap did not change.
    if entry and knownGap > 0 and IsPlayerGUID(guid) then
        entry = select(1, MergeLegacyGap(history, name, guid, knownGap, true))
        knownGap = LegacyGapFromEntry(entry)
    end

    if allowCreate and observedGap > knownGap then
        entry = select(1, MergeLegacyGap(history, name, guid, observedGap, suppressSync))
        knownGap = LegacyGapFromEntry(entry)
    end

    local total = math.max(eventCount + knownGap, eventCount, voidmarkWins, eventCount + unresolved)
    return total, eventCount, voidmarkWins, unresolved, entry, voidmarkKey, voidmarkMethod
end

local function ProcessOneDeferredHistoricalRecovery()
    if InCombatNow() or deferredHistoricalHead > deferredHistoricalTail then return false end

    local item = deferredHistoricalQueue[deferredHistoricalHead]
    deferredHistoricalQueue[deferredHistoricalHead] = nil
    deferredHistoricalHead = deferredHistoricalHead + 1
    if item and item.key then deferredHistoricalKeys[item.key] = nil end

    if deferredHistoricalHead > deferredHistoricalTail then
        wipe(deferredHistoricalQueue)
        deferredHistoricalHead = 1
        deferredHistoricalTail = 0
    end

    if not item then return false end
    local history = EnsureHistory()
    if not history then return false end

    local total = HistoricalCountWithFloor(history, item.name, item.guid, true)
    if item.notifyTracker and TaliaaGankTracker then
        if TaliaaGankTracker.OnHistoricalRepair then
            TaliaaGankTracker:OnHistoricalRepair(item.name, item.guid, tonumber(total) or 0)
        elseif TaliaaGankTracker.OnHistoryUpdated then
            TaliaaGankTracker:OnHistoryUpdated(item.name, item.guid, tonumber(total) or 0)
        end
    end
    return true
end

local function EnsureVictim(history, event)
    local key = VictimKey(event.name, event.guid)
    local victim = history.victims[key]

    -- If an older name-key record exists and we now know the GUID, migrate it.
    -- Combat path: only use exact O(1) aliases. Deep accent/name scans are
    -- deferred until combat ends so a first kill can never hitch the client.
    if not victim and event.guid and tostring(event.guid):sub(1, 6) == "Player" then
        local oldKey = "N:" .. ExactPlayerNameKey(event.name)
        local oldVictim = history.victims[oldKey]
        if not oldVictim and not InCombatNow() then
            oldVictim, oldKey = FindVictimByName(history, event.name)
        end
        if oldVictim and oldKey and oldKey ~= key then
            history.victims[oldKey] = nil
            history.victims[key] = oldVictim
            victim = oldVictim
        end
    end

    if not victim then
        victim = {
            name = event.name,
            guid = event.guid,
            kills = 0,
            events = {},
        }
        history.victims[key] = victim
    end

    victim.events = victim.events or {}
    victim.kills = tonumber(victim.kills) or 0
    if event.name and event.name ~= "" then victim.name = event.name end
    if event.guid and event.guid ~= "" then victim.guid = event.guid end

    return victim, key
end

local function IsSameDeath(victim, timestamp)
    local t = tonumber(timestamp) or 0
    if t <= 0 then return false end

    -- Live kills are chronological, so lastKill is enough to catch the usual
    -- UNIT_DIED/PARTY_KILL duplicate without walking every old kill for a victim.
    local lastKill = tonumber(victim and victim.lastKill) or 0
    if lastKill > 0 and math.abs(lastKill - t) <= DEDUPE_SECONDS then
        return true
    end

    -- Historical/import rows can arrive out of order. Preserve the exhaustive
    -- check outside combat only; it is never worth stalling an active fight.
    if InCombatNow() then return false end
    for _, oldTime in pairs(victim.events or {}) do
        oldTime = tonumber(oldTime) or 0
        if oldTime > 0 and math.abs(oldTime - t) <= DEDUPE_SECONDS then
            return true
        end
    end

    return false
end

-- Reload-safe legacy repair/import. Older repository builds may already contain
-- local kills in GankHistory. Rebuild indexes from those records and recover any
-- event rows that still exist only under victim.events. This is idempotent.
local function RepairLegacyHistory()
    local history = EnsureHistory()
    if not history then return 0, 0 end

    local recovered = 0
    local oldVictims = history.victims or {}
    history.legacyUnresolved = history.legacyUnresolved or {}

    -- Recover event rows from the per-victim event map when possible.
    for _, victim in pairs(oldVictims) do
        if type(victim) == "table" and type(victim.events) == "table" then
            local eventSlots = 0
            for eventID, stamp in pairs(victim.events) do
                eventSlots = eventSlots + 1
                eventID = tostring(eventID or "")
                if eventID ~= "" and history.events[eventID] == nil then
                    history.events[eventID] = {
                        id = eventID,
                        t = tonumber(stamp) or tonumber(victim.lastKill) or 0,
                        name = tostring(victim.name or "?"),
                        guid = tostring(victim.guid or ""),
                        zone = tostring(victim.lastZone or "Unknown"),
                        subZone = tostring(victim.lastSubZone or ""),
                        level = victim.lastLevel or "?",
                        class = victim.lastClass or "",
                        killer = tostring(victim.lastKiller or ""),
                        faction = CurrentFaction(),
                    }
                    recovered = recovered + 1
                end
            end
            local claimed = tonumber(victim.kills) or 0
            if claimed > eventSlots then
                local unresolvedKey = tostring(victim.guid or victim.name or "?")
                history.legacyUnresolved[unresolvedKey] = math.max(
                    tonumber(history.legacyUnresolved[unresolvedKey]) or 0,
                    claimed - eventSlots
                )
            end
        elseif type(victim) == "table" and (tonumber(victim.kills) or 0) > 0 then
            local unresolvedKey = tostring(victim.guid or victim.name or "?")
            history.legacyUnresolved[unresolvedKey] = math.max(
                tonumber(history.legacyUnresolved[unresolvedKey]) or 0,
                tonumber(victim.kills) or 0
            )
        end
    end

    -- Rebuild all derived indexes from the authoritative event rows.
    history.victims = {}
    history.seenIDs = {}
    history.eventCount = 0
    history.lastEventTime = 0

    local events = {}
    for id, event in pairs(history.events) do
        if type(event) == "table" then
            event.id = tostring(event.id or id)
            event.t = tonumber(event.t) or 0
            event.name = tostring(event.name or "?")
            event.guid = tostring(event.guid or "")
            event.faction = tostring(event.faction or CurrentFaction())
            events[#events + 1] = event
        end
    end
    table.sort(events, function(a, b)
        local at, bt = tonumber(a.t) or 0, tonumber(b.t) or 0
        if at == bt then return tostring(a.id) < tostring(b.id) end
        return at < bt
    end)

    for _, event in ipairs(events) do
        local eventID = tostring(event.id)
        local key = VictimKey(event.name, event.guid)
        local victim = history.victims[key]
        if not victim then
            victim = { name = event.name, guid = event.guid, kills = 0, events = {} }
            history.victims[key] = victim
        end
        victim.events = victim.events or {}

        -- Same-death protection also applies while rebuilding mixed histories.
        if not IsSameDeath(victim, event.t) then
            history.seenIDs[eventID] = true
            victim.events[eventID] = tonumber(event.t) or 0
            victim.kills = (tonumber(victim.kills) or 0) + 1
            local eventTime = tonumber(event.t) or 0
            if not victim.firstKill or eventTime < victim.firstKill then victim.firstKill = eventTime end
            if not victim.lastKill or eventTime >= victim.lastKill then
                victim.lastKill = eventTime
                victim.lastZone = event.zone
                victim.lastSubZone = event.subZone
                victim.lastLevel = event.level
                victim.lastClass = event.class
                victim.lastKiller = event.killer
            end
            history.eventCount = history.eventCount + 1
            history.lastEventTime = math.max(tonumber(history.lastEventTime) or 0, eventTime)
        else
            -- Drop duplicate event rows so the daily tracker (which counts
            -- history.events directly) cannot double-count after /reload.
            history.events[eventID] = nil
            history.seenIDs[eventID] = true
        end
    end

    -- Promote every old unresolved legacy amount into a portable floor record.
    -- legacyUnresolved already represents kills missing from event rows, so its
    -- value is directly usable as legacyGap. This lets offline/BNet sync carry
    -- those old kills even before the player is encountered again.
    for unresolvedKey, extra in pairs(history.legacyUnresolved or {}) do
        extra = math.max(0, tonumber(extra) or 0)
        if extra > 0 then
            local unresolvedGUID = IsPlayerGUID(unresolvedKey) and tostring(unresolvedKey) or ""
            local unresolvedName = IsPlayerGUID(unresolvedKey) and "?" or tostring(unresolvedKey or "?")
            if unresolvedGUID ~= "" then
                local victim = history.victims and history.victims["G:" .. unresolvedGUID]
                if type(victim) == "table" and victim.name then
                    unresolvedName = tostring(victim.name)
                end
            end
            MergeLegacyGap(history, unresolvedName, unresolvedGUID, extra, true)
        end
    end

    -- Migrate v7 absolute floors to the portable v8 legacy-gap format and
    -- collapse old name aliases onto their unique GUID identity where safe.
    for _, entry in pairs(history.legacyFloors or {}) do
        if type(entry) == "table" then
            LegacyGapFromEntry(entry)
        end
    end
    CompactLegacyFloors(history)

    history.version = HISTORY_VERSION
    local sync = EnsureSyncDB()
    if sync then sync.historyRepairVersion = HISTORY_VERSION end
    return history.eventCount, recovered
end

local function NotifyHistoryUpdated(event, count)
    if TaliaaGankTracker and TaliaaGankTracker.OnHistoryUpdated then
        TaliaaGankTracker:OnHistoryUpdated(event.name, event.guid, count)
    end
end

local function AddEvent(event, suppressNotify, skipHistoricalRecovery)
    local history = EnsureHistory()
    if not history or not event or not event.id then return false, 0, "no database" end

    if IsExplicitNonPlayerGUID(event.guid) then
        return false, 0, "non-player"
    end

    local eventID = tostring(event.id)
    if history.events[eventID] or history.seenIDs[eventID] then
        local victim = history.victims[VictimKey(event.name, event.guid)]
        if not victim then victim = FindVictimByName(history, event.name) end
        return false, victim and (tonumber(victim.kills) or 0) or 0, "known id"
    end

    local victim, key = EnsureVictim(history, event)

    -- Two logged-in accounts can see the same death. Treat the same victim
    -- dying within a few seconds as one historical gank, even if each account
    -- generated its own local event ID.
    if IsSameDeath(victim, event.t) then
        history.seenIDs[eventID] = true
        return false, tonumber(victim.kills) or 0, "same death"
    end

    history.events[eventID] = event
    history.seenIDs[eventID] = true
    victim.events[eventID] = tonumber(event.t) or Now()
    victim.kills = (tonumber(victim.kills) or 0) + 1

    local eventTime = tonumber(event.t) or Now()
    if not victim.firstKill or eventTime < victim.firstKill then victim.firstKill = eventTime end
    if not victim.lastKill or eventTime >= victim.lastKill then
        victim.lastKill = eventTime
        victim.lastZone = event.zone
        victim.lastSubZone = event.subZone
        victim.lastLevel = event.level
        victim.lastClass = event.class
        victim.lastKiller = event.killer
    end

    history.eventCount = (tonumber(history.eventCount) or 0) + 1
    history.lastEventTime = math.max(tonumber(history.lastEventTime) or 0, eventTime)

    local historicalCount
    if skipHistoricalRecovery or InCombatNow() then
        historicalCount = select(1, FastHistoricalCount(history, event.name, event.guid))
        QueueDeferredHistoricalRecovery(event.name, event.guid, not suppressNotify)
    else
        historicalCount = HistoricalCountWithFloor(
            history, event.name, event.guid, true, suppressNotify and true or false
        )
    end
    if not suppressNotify then
        NotifyHistoryUpdated(event, historicalCount)
    end
    return true, tonumber(historicalCount) or victim.kills, key
end

local function EncodeEvent(event)
    return table.concat({
        "E",
        CleanField(EnsureLocalSessionToken()),
        CleanField(event.id),
        tostring(tonumber(event.t) or 0),
        CleanField(event.name),
        CleanField(event.guid),
        CleanField(event.zone),
        CleanField(event.subZone),
        CleanField(event.level),
        CleanField(event.class),
        CleanField(event.killer),
        CleanField(event.faction),
    }, SEP)
end

local function DecodeEvent(parts)
    if not parts or parts[1] ~= "E" then return nil end
    if not parts[3] or parts[3] == "" then return nil end

    return {
        id = parts[3],
        t = tonumber(parts[4]) or 0,
        name = parts[5] or "?",
        guid = parts[6] or "",
        zone = parts[7] or "",
        subZone = parts[8] or "",
        level = tonumber(parts[9]) or parts[9] or "?",
        class = parts[10] or "",
        killer = parts[11] or "",
        faction = parts[12] or "",
    }
end

local function EncodeDHKEvent(event)
    return table.concat({
        "H",
        CleanField(EnsureLocalSessionToken()),
        CleanField(event.id),
        tostring(tonumber(event.t) or 0),
        CleanField(event.character),
        CleanField(event.message),
        CleanField(event.zone),
        CleanField(event.faction),
        CleanField(event.source),
    }, SEP)
end

local function DecodeDHKEvent(parts)
    if not parts or parts[1] ~= "H" then return nil end
    if not parts[3] or parts[3] == "" then return nil end

    return {
        id = parts[3],
        t = tonumber(parts[4]) or 0,
        character = parts[5] or "",
        message = parts[6] or "",
        zone = parts[7] or "",
        faction = parts[8] or "",
        source = parts[9] or "",
    }
end

local function EncodeLegacyFloor(entry)
    return table.concat({
        "F",
        CleanField(EnsureLocalSessionToken()),
        CleanField(entry and entry.name or "?"),
        CleanField(entry and entry.guid or ""),
        tostring(LegacyGapFromEntry(entry)),
    }, SEP)
end

local function DecodeLegacyFloor(parts)
    if not parts or parts[1] ~= "F" then return nil end
    local gap = tonumber(parts[5]) or 0
    if gap <= 0 then return nil end
    return {
        name = parts[3] or "?",
        guid = parts[4] or "",
        legacyGap = gap,
    }
end

local function SendBN(gameAccountID, payload)
    local id = tonumber(gameAccountID)
    if not id or not payload or payload == "" then return false end

    if BNSendGameData then
        local ok = pcall(BNSendGameData, id, PREFIX, payload)
        return ok
    elseif C_BattleNet and C_BattleNet.SendGameData then
        local ok = pcall(C_BattleNet.SendGameData, id, PREFIX, payload)
        return ok
    end

    return false
end

local function QueuePayload(gameAccountID, payload)
    local id = tonumber(gameAccountID)
    if not id or not payload then return end
    sendTail = sendTail + 1
    sendQueue[sendTail] = { id = id, payload = payload }
end

local function QueueEventToPeer(event)
    local sync = EnsureSyncDB()
    if not sync or sync.enabled == false or not sync.peerGameAccountID then return end
    QueuePayload(sync.peerGameAccountID, EncodeEvent(event))
end

local function QueueDHKEventToPeer(event)
    local sync = EnsureSyncDB()
    if not sync or sync.enabled == false or not sync.peerGameAccountID then return end
    QueuePayload(sync.peerGameAccountID, EncodeDHKEvent(event))
end

QueueLegacyFloorToPeer = function(entry)
    local sync = EnsureSyncDB()
    if not sync or sync.enabled == false or not sync.peerGameAccountID then return end
    if not entry or LegacyGapFromEntry(entry) <= 0 then return end
    QueuePayload(sync.peerGameAccountID, EncodeLegacyFloor(entry))
end

local function QueueAllLegacyFloors(gameAccountID)
    local history = EnsureHistory()
    if not history or type(history.legacyFloors) ~= "table" then return 0 end
    CompactLegacyFloors(history)

    local sent = 0
    for _, entry in pairs(history.legacyFloors) do
        if type(entry) == "table" and LegacyGapFromEntry(entry) > 0 then
            QueuePayload(gameAccountID, EncodeLegacyFloor(entry))
            sent = sent + 1
        end
    end
    return sent
end

local function QueueAllEvents(gameAccountID)
    local history = EnsureHistory()
    if not history then return 0 end

    local events = {}
    for _, event in pairs(history.events) do
        if event and event.id then events[#events + 1] = event end
    end
    table.sort(events, function(a, b)
        local at = tonumber(a.t) or 0
        local bt = tonumber(b.t) or 0
        if at == bt then return tostring(a.id) < tostring(b.id) end
        return at < bt
    end)

    for _, event in ipairs(events) do
        QueuePayload(gameAccountID, EncodeEvent(event))
    end

    local dhkHistory = EnsureDHKHistory()
    local dhkEvents = {}
    if dhkHistory and type(dhkHistory.events) == "table" then
        for _, event in pairs(dhkHistory.events) do
            if type(event) == "table" and event.id then
                dhkEvents[#dhkEvents + 1] = event
            end
        end
        table.sort(dhkEvents, function(a, b)
            local at = tonumber(a.t) or 0
            local bt = tonumber(b.t) or 0
            if at == bt then return tostring(a.id) < tostring(b.id) end
            return at < bt
        end)

        for _, event in ipairs(dhkEvents) do
            QueuePayload(gameAccountID, EncodeDHKEvent(event))
        end
    end

    local floorCount = QueueAllLegacyFloors(gameAccountID)

    QueuePayload(gameAccountID, table.concat({
        "D",
        CleanField(EnsureLocalSessionToken()),
        tostring(#events),
        tostring(#dhkEvents),
        tostring(floorCount),
    }, SEP))
    return #events, #dhkEvents, floorCount
end

local function CollectKnownIDs(history)
    local ids, known = {}, {}
    if history then
        for id in pairs(history.events or {}) do
            id = tostring(id or "")
            if id ~= "" and not known[id] then
                known[id] = true
                ids[#ids + 1] = id
            end
        end
        for id, seen in pairs(history.seenIDs or {}) do
            if seen then
                id = tostring(id or "")
                if id ~= "" and not known[id] then
                    known[id] = true
                    ids[#ids + 1] = id
                end
            end
        end
    end
    table.sort(ids)
    return ids
end

local function QueueInventoryIDChunks(gameAccountID, tx, kind, ids)
    local chunk, bytes = {}, 0

    local function Flush()
        if #chunk == 0 then return end
        QueuePayload(gameAccountID, table.concat({
            "I",
            CleanField(EnsureLocalSessionToken()),
            CleanField(tx),
            kind,
            table.concat(chunk, ID_LIST_SEP),
        }, SEP))
        wipe(chunk)
        bytes = 0
    end

    for _, rawID in ipairs(ids or {}) do
        local id = tostring(rawID or ""):gsub(ID_LIST_SEP, "")
        if id ~= "" then
            local addBytes = #id + (#chunk > 0 and 1 or 0)
            if #chunk > 0 and (bytes + addBytes) > INVENTORY_CHUNK_BYTES then
                Flush()
            end
            chunk[#chunk + 1] = id
            bytes = bytes + addBytes
        end
    end
    Flush()
end

local function QueueInventory(gameAccountID, tx, requestReply)
    local killIDs = CollectKnownIDs(EnsureHistory())
    local dhkIDs = CollectKnownIDs(EnsureDHKHistory())

    QueueInventoryIDChunks(gameAccountID, tx, "K", killIDs)
    QueueInventoryIDChunks(gameAccountID, tx, "H", dhkIDs)

    QueuePayload(gameAccountID, table.concat({
        "J",
        CleanField(EnsureLocalSessionToken()),
        CleanField(tx),
        requestReply and "1" or "0",
        tostring(#killIDs),
        tostring(#dhkIDs),
    }, SEP))
    return #killIDs, #dhkIDs
end

local function RememberInventoryChunk(parts)
    local tx = tostring(parts and parts[3] or "")
    local kind = tostring(parts and parts[4] or "")
    local data = tostring(parts and parts[5] or "")
    if tx == "" or (kind ~= "K" and kind ~= "H") then return end

    local slot = incomingInventories[tx]
    if not slot then
        slot = { kills = {}, dhks = {}, startedAt = Now() }
        incomingInventories[tx] = slot
    end

    local target = (kind == "K") and slot.kills or slot.dhks
    local start = 1
    while start <= #data do
        local p = data:find(ID_LIST_SEP, start, true)
        local id
        if p then
            id = data:sub(start, p - 1)
            start = p + 1
        else
            id = data:sub(start)
            start = #data + 1
        end
        if id and id ~= "" then target[id] = true end
    end

    local now = Now()
    for key, oldSlot in pairs(incomingInventories) do
        if oldSlot and (now - (tonumber(oldSlot.startedAt) or now)) > 120 then
            incomingInventories[key] = nil
        end
    end
end

local function QueueMissingEvents(gameAccountID, remoteKills, remoteDHKs, tx, finalLeg)
    remoteKills = remoteKills or {}
    remoteDHKs = remoteDHKs or {}
    tx = tostring(tx or "")

    local sentKills, sentDHKs = 0, 0
    local history = EnsureHistory()
    if history and type(history.events) == "table" then
        local events = {}
        for id, event in pairs(history.events) do
            id = tostring(id or (event and event.id) or "")
            if event and id ~= "" and not remoteKills[id] then
                events[#events + 1] = event
            end
        end
        table.sort(events, function(a, b)
            local at, bt = tonumber(a.t) or 0, tonumber(b.t) or 0
            if at == bt then return tostring(a.id) < tostring(b.id) end
            return at < bt
        end)
        for _, event in ipairs(events) do
            QueuePayload(gameAccountID, EncodeEvent(event))
            sentKills = sentKills + 1
        end
    end

    local dhkHistory = EnsureDHKHistory()
    if dhkHistory and type(dhkHistory.events) == "table" then
        local events = {}
        for id, event in pairs(dhkHistory.events) do
            id = tostring(id or (event and event.id) or "")
            if event and id ~= "" and not remoteDHKs[id] then
                events[#events + 1] = event
            end
        end
        table.sort(events, function(a, b)
            local at, bt = tonumber(a.t) or 0, tonumber(b.t) or 0
            if at == bt then return tostring(a.id) < tostring(b.id) end
            return at < bt
        end)
        for _, event in ipairs(events) do
            QueuePayload(gameAccountID, EncodeDHKEvent(event))
            sentDHKs = sentDHKs + 1
        end
    end

    -- Floors are small metadata, not event rows. Send every known floor on each
    -- sync leg before D so the receiver applies them while bulk mode is active.
    local sentFloors = QueueAllLegacyFloors(gameAccountID)

    QueuePayload(gameAccountID, table.concat({
        "D",
        CleanField(EnsureLocalSessionToken()),
        CleanField(tx),
        finalLeg and "1" or "0",
        tostring(sentKills),
        tostring(sentDHKs),
        tostring(sentFloors),
    }, SEP))

    return sentKills, sentDHKs, sentFloors
end

local function NextLocalDHKEventID(sync, history)
    local node = tostring(sync and sync.nodeID or "")
    if node == "" then return nil end

    local seq = tonumber(sync.nextDHKSeq) or 0
    local tries = 0
    repeat
        seq = seq + 1
        tries = tries + 1
        local eventID = "DHK-" .. node .. "-" .. tostring(seq)
        if not history.events[eventID] and not history.seenIDs[eventID] then
            sync.nextDHKSeq = seq
            return eventID
        end
    until tries >= 100000

    return nil
end

function Repo:RecordDHK(message, details)
    local sync = EnsureSyncDB()
    local history = EnsureDHKHistory()
    if not sync or not history then return false, 0 end

    local eventID = NextLocalDHKEventID(sync, history)
    if not eventID then return false, tonumber(history.eventCount) or 0 end

    details = details or {}
    local event = {
        id = eventID,
        t = tonumber(details.timestamp) or Now(),
        character = tostring(details.character or UnitName("player") or "?"),
        message = tostring(message or ""),
        zone = tostring(details.zone or GetZoneText() or ""),
        faction = tostring(details.faction or CurrentFaction()),
        source = tostring(details.source or ""),
    }

    local added, count = AddDHKEvent(event)
    if added then
        QueueDHKEventToPeer(event)
    end

    return added, tonumber(count) or 0
end

function Repo:GetDHKEventsInRange(startTime, endTime)
    local history = EnsureDHKHistory()
    local out = {}
    if not history or type(history.events) ~= "table" then return out end

    local first = tonumber(startTime) or 0
    local last = tonumber(endTime) or (Now() + 60)

    for _, event in pairs(history.events) do
        if type(event) == "table" then
            local t = tonumber(event.t) or 0
            if t >= first and t <= last then
                out[#out + 1] = event
            end
        end
    end

    table.sort(out, function(a, b)
        local at = tonumber(a and a.t) or 0
        local bt = tonumber(b and b.t) or 0
        if at == bt then return tostring(a and a.id or "") < tostring(b and b.id or "") end
        return at < bt
    end)

    return out
end

function Repo:GetDHKCount()
    local history = EnsureDHKHistory()
    return history and (tonumber(history.eventCount) or 0) or 0
end

function Repo:RemoveBrokenSyntheticDHKsForCharacterInRange(character, startTime, endTime, authoritativeCount)
    return RemoveBrokenSyntheticDHKsForCharacterInRange(
        character, startTime, endTime, authoritativeCount
    )
end

function Repo:GetDHKCountForCharacterInRange(character, startTime, endTime)
    local history = EnsureDHKHistory()
    if not history or type(history.events) ~= "table" then return 0 end

    local wantCharacter = NormalizeDHKCharacter(character)
    local first = tonumber(startTime) or 0
    local last = tonumber(endTime) or (Now() + 60)
    local count = 0

    for _, event in pairs(history.events) do
        if type(event) == "table"
            and NormalizeDHKCharacter(event.character) == wantCharacter then
            local t = tonumber(event.t) or 0
            if t >= first and t <= last then
                count = count + 1
            end
        end
    end

    return count
end

function Repo:GetHistoricalCount(playerName, playerGUID)
    local history = EnsureHistory()
    if not history then return 0 end

    if InCombatNow() then
        local total = select(1, FastHistoricalCount(history, playerName, playerGUID))
        QueueDeferredHistoricalRecovery(playerName, playerGUID, false)
        return tonumber(total) or 0
    end

    local total = HistoricalCountWithFloor(history, playerName, playerGUID, true)
    return tonumber(total) or 0
end

function Repo:CanonicalPlayerName(playerName)
    return CanonicalPlayerNameKey(playerName)
end

-- Diagnostic helper for future recovery/debug work. Returns:
-- total, event rows, VoidMark wins, unresolved extras, legacy gap, diagnostic floor,
-- repo-at-capture, matched VoidMark key, and the identity-match method.
function Repo:GetHistoricalBreakdown(playerName, playerGUID)
    local history = EnsureHistory()
    if not history then return 0, 0, 0, 0, 0, 0, 0, nil, nil end

    local total, events, voidmarkWins, unresolved, entry, voidmarkKey, voidmarkMethod =
        HistoricalCountWithFloor(history, playerName, playerGUID, true)

    local gap = LegacyGapFromEntry(entry)
    return tonumber(total) or 0,
           tonumber(events) or 0,
           tonumber(voidmarkWins) or 0,
           tonumber(unresolved) or 0,
           tonumber(gap) or 0,
           entry and (tonumber(entry.floor) or 0) or 0,
           entry and (tonumber(entry.repoAtCapture) or 0) or 0,
           voidmarkKey, voidmarkMethod
end

-- PERFORMANCE-CRITICAL compatibility helper used by VoidMark's compact rows
-- and tooltips.  These callers can refresh repeatedly while combat-log activity
-- is high, so this path MUST stay O(1) and must never walk the full VoidMark database,
-- victim table, unresolved table, or legacy-floor table.
--
-- Full recovery/identity matching still lives in GetHistoricalCount() and runs
-- when a kill is recorded or when the explicit diagnostic command is used.  The
-- compact UI already combines this repository value with playerData.wins, so an
-- unresolved old alias can safely wait for that slower recovery path without
-- hitching combat.
function Repo:GetHistoricalStats(playerName, playerGUID)
    local history = EnsureHistory()
    if not history then return 0, 0 end

    local name = tostring(playerName or "")
    local guid = tostring(playerGUID or "")
    local key = VictimKey(name, guid)

    -- Direct authoritative victim row. Once a real GUID is known this is the
    -- normal path and requires a single table lookup.
    local victim = history.victims and history.victims[key]
    local eventCount = type(victim) == "table" and (tonumber(victim.kills) or 0) or 0

    -- For a name-only identity, the exact normalized name key is also direct.
    -- Do not perform accent/realm alias scans here; those are intentionally kept
    -- out of the combat/UI hot path.
    if eventCount <= 0 and not IsPlayerGUID(guid) and name ~= "" then
        victim = history.victims and history.victims["N:" .. ExactPlayerNameKey(name)]
        eventCount = type(victim) == "table" and (tonumber(victim.kills) or 0) or 0
    end

    local floor = history.legacyFloors and history.legacyFloors[key]
    local gap = type(floor) == "table" and LegacyGapFromEntry(floor) or 0

    -- If the GUID floor has not been bound yet, allow one exact name-key lookup.
    -- This is still O(1) and preserves older name-only floors without scanning.
    if gap <= 0 and name ~= "" then
        local nameFloor = history.legacyFloors and history.legacyFloors["N:" .. ExactPlayerNameKey(name)]
        if type(nameFloor) == "table" then
            gap = LegacyGapFromEntry(nameFloor)
        end
    end

    return math.max(0, eventCount + gap), 0
end

function Repo:GetRawEventCount()
    local history = EnsureHistory()
    if not history or type(history.events) ~= "table" then return 0 end

    local raw = 0
    for _, event in pairs(history.events) do
        if type(event) == "table" then raw = raw + 1 end
    end
    return raw
end

local repoStatsCache = {
    history = nil,
    eventCount = -1,
    victimCount = 0,
}

function Repo:GetStats()
    local history = EnsureHistory()
    if not history then return 0, 0 end

    -- PERFORMANCE: RepairLegacyHistory/AddEvent keep history.eventCount
    -- authoritative.  The old implementation re-walked every event and every
    -- victim on *each* UI refresh; GankTracker asks for these totals several
    -- times per second while visible, which produced periodic combat hitches on
    -- a 2k+ kill repository.  Recount victims only when the event generation
    -- changes. Explicit /tgank repo diagnostics still have GetRawEventCount().
    local count = tonumber(history.eventCount) or 0
    if repoStatsCache.history == history
        and repoStatsCache.eventCount == count then
        return count, tonumber(repoStatsCache.victimCount) or 0
    end

    local victims = 0
    for _ in pairs(history.victims or {}) do victims = victims + 1 end

    repoStatsCache.history = history
    repoStatsCache.eventCount = count
    repoStatsCache.victimCount = victims
    return count, victims
end

function Repo:GetLegacyFloorStats()
    local history = EnsureHistory()
    if not history or type(history.legacyFloors) ~= "table" then return 0, 0 end
    CompactLegacyFloors(history)

    local count, totalGap = 0, 0
    for _, entry in pairs(history.legacyFloors) do
        if type(entry) == "table" then
            local gap = LegacyGapFromEntry(entry)
            if gap > 0 then
                count = count + 1
                totalGap = totalGap + gap
            end
        end
    end
    return count, totalGap
end

function Repo:GetPeerStatus()
    local sync = EnsureSyncDB()
    if not sync then return false, nil, nil end
    return sync.peerGameAccountID ~= nil, sync.peerGameAccountID, sync.peerName
end

-- Lightweight status for the tracker UI. Timestamps are server Unix time.
function Repo:GetSyncStatus()
    local sync = EnsureSyncDB()
    if not sync then
        return {
            paired = false,
            pairing = pairing and true or false,
            autoPair = false,
        }
    end

    return {
        paired = sync.peerGameAccountID ~= nil,
        pairing = pairing and true or false,
        autoPair = sync.autoPair ~= false,
        peerID = sync.peerGameAccountID,
        peerName = sync.peerName,
        lastReceive = tonumber(sync.lastReceive) or 0,
        lastPeerSeen = tonumber(sync.lastPeerSeen) or 0,
        lastSyncComplete = tonumber(sync.lastSyncComplete) or 0,
        syncing = sync.syncing and true or false,
        syncStartedAt = tonumber(sync.syncStartedAt) or 0,
        lastSyncVerified = tonumber(sync.lastSyncVerified) or 0,
        lastSyncVerifiedTotal = tonumber(sync.lastSyncVerifiedTotal) or 0,
        lastSyncVerifiedVictims = tonumber(sync.lastSyncVerifiedVictims) or 0,
        verifyRetries = tonumber(sync.verifyRetries) or 0,
        queueRemaining = math.max(0, (tonumber(sendTail) or 0) - (tonumber(sendHead) or 1) + 1),
    }
end

-- Return authoritative merged events from the repository for reports/statistics.
function Repo:GetEventsInRange(startTime, endTime, unsorted)
    local history = EnsureHistory()
    local out = {}
    if not history or type(history.events) ~= "table" then return out end

    local first = tonumber(startTime) or 0
    local last = tonumber(endTime) or (Now() + 60)

    for _, event in pairs(history.events) do
        if type(event) == "table" then
            local eventTime = tonumber(event.t or event.time or event.timestamp) or 0
            if eventTime >= first and eventTime <= last then
                out[#out + 1] = event
            end
        end
    end

    -- Reporting screens that need chronological output keep the default sort.
    -- Aggregate weekly counters do not care about order and can skip an
    -- O(n log n) sort by passing true as the third argument.
    if not unsorted then
        table.sort(out, function(a, b)
            local at = tonumber(a and (a.t or a.time or a.timestamp)) or 0
            local bt = tonumber(b and (b.t or b.time or b.timestamp)) or 0
            if at == bt then return tostring(a and a.id or "") < tostring(b and b.id or "") end
            return at < bt
        end)
    end

    return out
end

local function NextLocalEventID(sync, history)
    -- File/recovery merges can restore old event rows without restoring the
    -- matching nextSeq value. Skip every occupied ID so a fresh kill can never
    -- silently collide with an older "<node>-<seq>" event.
    local node = tostring(sync and sync.nodeID or "")
    if node == "" then return nil end

    local seq = tonumber(sync.nextSeq) or 0
    local tries = 0

    repeat
        seq = seq + 1
        tries = tries + 1
        local eventID = node .. "-" .. tostring(seq)

        if not history.events[eventID] and not history.seenIDs[eventID] then
            sync.nextSeq = seq
            return eventID
        end
    until tries >= 100000

    return nil
end

function Repo:RecordKill(playerName, playerGUID, details)
    if not playerName or playerName == "" then return 0 end
    if IsExplicitNonPlayerGUID(playerGUID) then return 0 end

    local sync = EnsureSyncDB()
    local history = EnsureHistory()
    if not sync or not history then return 0 end

    -- KILL HOT PATH: never do the deep accent/legacy scans while fighting.
    -- Capture the pre-kill total from direct indexes only, then the accepted
    -- event simply advances that total by one. Deep recovery is queued for
    -- after combat and can raise the floor if an old alias was not direct.
    local preHistorical
    if InCombatNow() then
        preHistorical = select(1, FastHistoricalCount(history, playerName, playerGUID))
        -- AddEvent() queues exactly one deferred identity repair after the event
        -- is accepted. Avoid touching the deferred queue twice on the death frame.
    else
        preHistorical = HistoricalCountWithFloor(history, playerName, playerGUID, true)
    end
    preHistorical = tonumber(preHistorical) or 0

    local eventID = NextLocalEventID(sync, history)
    if not eventID then
        Print("ERROR: could not allocate a unique kill-event ID.")
        return preHistorical
    end

    details = details or {}
    local event = {
        id = eventID,
        t = Now(),
        name = tostring(playerName),
        guid = tostring(playerGUID or ""),
        zone = tostring(details.zone or GetZoneText() or "Unknown"),
        subZone = tostring(details.subZone or GetSubZoneText() or ""),
        level = details.level or "?",
        class = details.class or "",
        killer = tostring(details.killer or UnitName("player") or "?"),
        faction = CurrentFaction(),
    }

    -- Local GT:RecordKill owns the immediate session/chat update. Skip historical
    -- recovery inside AddEvent as well so one kill cannot accidentally trigger a
    -- second full identity walk.
    local added = AddEvent(event, true, true)
    if added then
        QueueEventToPeer(event)
    end

    return preHistorical + (added and 1 or 0), added and true or false
end

local function OwnGameAccountID()
    local guid = UnitGUID("player")
    if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID and guid then
        local vals = {C_BattleNet.GetGameAccountInfoByGUID(guid)}
        for _, v in ipairs(vals) do
            if type(v) == "table" then
                local id = v.gameAccountID or v.gameAccountId or v.id
                if id then return tonumber(id) end
            elseif type(v) == "number" then
                return tonumber(v)
            end
        end
    end
    return nil
end

function Repo:SyncNow(silent, force)
    local sync = EnsureSyncDB()
    if not sync or sync.enabled == false then
        if not silent then Print("Account sync is disabled.") end
        return false
    end

    local peerID = tonumber(sync.peerGameAccountID)
    if not peerID or not sync.peerSessionToken or sync.peerSessionToken == "" then
        if not silent then Print("No external peer account connected. Use /tgank pair while both WoW accounts are online.") end
        return false
    end

    if sync.syncing and not force then
        if not silent then
            Print("Sync is already in progress. Wait for SYNC COMPLETE.")
        end
        return false
    end

    local now = Now()
    if silent and not force and (now - (tonumber(sync.lastSyncAttempt) or 0)) < 20 then
        return true
    end

    local tx = tostring(sync.nodeID or "node")
        .. "-" .. tostring(now)
        .. "-" .. tostring(math.random(1000, 9999))

    sync.bulkReceivePending = true
    sync.syncing = true
    sync.syncStartedAt = now
    sync.activeSyncTx = tx
    if not force then
        sync.verifyRetries = 0
    end

    local killIDs, dhkIDs = QueueInventory(peerID, tx, true)
    sync.lastSyncAttempt = now

    if not silent then
        Print("Fast sync started: comparing "
            .. tostring(killIDs) .. " kill IDs + "
            .. tostring(dhkIDs) .. " DHK IDs with peer.")
    end
    return true
end

-- Debug/fallback only. Normal Sync no longer sends the whole 2k+ repository.
function Repo:FullSyncNow(silent)
    local sync = EnsureSyncDB()
    local peerID = sync and tonumber(sync.peerGameAccountID) or nil
    if not sync or sync.enabled == false or not peerID
        or not sync.peerSessionToken or sync.peerSessionToken == "" then
        if not silent then Print("No external peer account connected.") end
        return false
    end

    sync.bulkReceivePending = true
    local kills, dhks = QueueAllEvents(peerID)
    sync.lastSyncAttempt = Now()
    if not silent then
        Print("FULL sync queued: " .. tostring(kills) .. " kills + "
            .. tostring(dhks) .. " DHKs -> peer.")
    end
    return true
end

-- Return currently-online WoW game accounts from Battle.net friends.
-- We keep the BattleTag alongside the gameAccountID so the same external
-- Battle.net account can be rediscovered even when it changes characters.
local function DiscoverOnlineWoWGameAccounts(preferredBattleTag)
    local out = {}
    local seen = {}
    local wowClient = BNET_CLIENT_WOW or "WoW"
    local ownID = OwnGameAccountID()
    local preferred = tostring(preferredBattleTag or ""):lower()

    local function Add(id, characterName, battleTag)
        id = tonumber(id)
        if not id or id <= 0 or (ownID and id == ownID) or seen[id] then return end

        local tag = tostring(battleTag or "")
        if preferred ~= "" and tag ~= "" and tag:lower() ~= preferred then
            return
        end

        seen[id] = true
        out[#out + 1] = {
            id = id,
            characterName = tostring(characterName or ""),
            battleTag = tag,
        }
    end

    if not BNGetNumFriends then return out end

    for i = 1, (BNGetNumFriends() or 0) do
        local modernInfo = nil
        local modernTag = ""

        if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
            modernInfo = C_BattleNet.GetFriendAccountInfo(i)
            modernTag = modernInfo and tostring(modernInfo.battleTag or "") or ""

            local ga = modernInfo and modernInfo.gameAccountInfo
            if ga and ga.isOnline and ga.gameAccountID
                and (ga.clientProgram == "WoW" or ga.clientProgram == wowClient) then
                Add(ga.gameAccountID, ga.characterName, modernTag)
            end

            if C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
                for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
                    local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
                    if g and g.isOnline and g.gameAccountID
                        and (g.clientProgram == "WoW" or g.clientProgram == wowClient) then
                        Add(g.gameAccountID, g.characterName, modernTag)
                    end
                end
            end
        end

        -- Classic Era legacy API fallback.
        if BNGetFriendInfo then
            local _, _, battleTag, _, _, gameAccountID, client, isOnline = BNGetFriendInfo(i)
            local legacyTag = tostring(battleTag or modernTag or "")

            if isOnline and gameAccountID
                and (client == "WoW" or client == wowClient) then
                Add(gameAccountID, "", legacyTag)
            end

            if BNGetNumFriendGameAccounts and BNGetFriendGameAccountInfo then
                for j = 1, (BNGetNumFriendGameAccounts(i) or 0) do
                    local _, characterName, clientProg, _, _, _, _, _, _, _, _, _, _, _, gaOnline, gaID =
                        BNGetFriendGameAccountInfo(i, j)
                    if gaOnline and gaID and (clientProg == "WoW" or clientProg == wowClient) then
                        Add(gaID, characterName, legacyTag)
                    end
                end
            end
        end
    end

    return out
end

local function ResolvePeerGameAccountID(reportedID, expectedCharacter)
    local expected = NormalizePlayerName(expectedCharacter)
    local sync = EnsureSyncDB()
    local preferredTag = sync and sync.peerBattleTag or nil

    -- First trust the event-reported ID only when the API confirms it belongs
    -- to the character named inside the repository handshake.
    local reported = tonumber(reportedID)
    if reported and C_BattleNet and C_BattleNet.GetGameAccountInfoByID then
        local info = C_BattleNet.GetGameAccountInfoByID(reported)
        if info and info.gameAccountID and info.isOnline then
            local have = NormalizePlayerName(info.characterName)
            if expected == "" or have == expected then
                local ownID = OwnGameAccountID()
                if not ownID or tonumber(info.gameAccountID) ~= tonumber(ownID) then
                    return tonumber(info.gameAccountID), tostring(info.characterName or expectedCharacter or ""), preferredTag
                end
            end
        end
    end

    -- If Classic's BN_CHAT_MSG_ADDON layout reports an unexpected numeric ID,
    -- resolve the real gameAccountID by the remote character name from the
    -- payload. This is what prevents Taliaa from pairing to Taliaa and Aloha
    -- from pairing to Aloha.
    local candidates = DiscoverOnlineWoWGameAccounts(preferredTag)
    if #candidates == 0 and preferredTag and preferredTag ~= "" then
        candidates = DiscoverOnlineWoWGameAccounts(nil)
    end

    for _, candidate in ipairs(candidates) do
        if expected ~= "" and NormalizePlayerName(candidate.characterName) == expected then
            return candidate.id, candidate.characterName, candidate.battleTag
        end
    end

    -- Last chance: if exactly one external WoW friend is online, it is the peer.
    if #candidates == 1 then
        local c = candidates[1]
        return c.id, c.characterName ~= "" and c.characterName or expectedCharacter, c.battleTag
    end

    return nil, nil, nil
end

local function FinishPair(peerID, peerName, peerNode, peerSessionToken, payloadPeerID)
    local sync = EnsureSyncDB()
    if not sync then return end
    if NormalizePlayerName(peerName) == NormalizePlayerName(UnitName("player")) then return end

    if not peerSessionToken or peerSessionToken == "" then return end
    if tostring(peerSessionToken) == tostring(EnsureLocalSessionToken()) then return end

    -- On this Classic Era client, the two WoW licenses can be reachable by
    -- current-session gameAccountID even when they do not appear as Battle.net
    -- friends.  The old working repository paired IDs such as 3 and 4 directly.
    -- Trust the live BN_CHAT_MSG_ADDON sender ID after the nonce/session-token
    -- handshake proves it is a different loaded repository.
    local id = tonumber(payloadPeerID) or tonumber(peerID)
    local ownID = OwnGameAccountID()
    if ownID and id == ownID then return end

    local resolvedName, battleTag
    if not id then
        id, resolvedName, battleTag = ResolvePeerGameAccountID(peerID, peerName)
    else
        local resolvedID
        resolvedID, resolvedName, battleTag = ResolvePeerGameAccountID(peerID, peerName)
        if resolvedID then id = resolvedID end
    end
    if not id then return end

    pairing = false
    sync.peerGameAccountID = id
    -- Remember the last working current-session ID as a fast probe hint.
    -- It is never trusted as permanent; every login still renegotiates.
    sync.lastKnownPeerGameAccountID = id
    sync.peerName = (resolvedName and resolvedName ~= "") and resolvedName or peerName or sync.peerName
    sync.peerBattleTag = (battleTag and battleTag ~= "") and battleTag or sync.peerBattleTag
    sync.peerSessionToken = tostring(peerSessionToken)
    sync.lastPeerSeen = Now()

    Print("Paired to external account via " .. tostring(sync.peerName or "other character")
        .. " (BNet game ID " .. tostring(id) .. ").")
    C_Timer.After(1.5, function() Repo:SyncNow(true) end)
end

local function SendPairProbe(id)
    if not pairing or not pairNonce then return end
    local payload = table.concat({
        "P",
        pairNonce,
        CleanField(UnitName("player") or "?"),
        CleanField((EnsureSyncDB() or {}).nodeID or ""),
        CleanField(EnsureLocalSessionToken()),
        tostring(OwnGameAccountID() or ""),
    }, SEP)
    SendBN(id, payload)
end

function Repo:StartPairing(silent)
    if pairing then
        if not silent then Print("Pairing is already running.") end
        return false
    end

    local sync = EnsureSyncDB()
    pairNonce = tostring(Now()) .. "-" .. tostring(math.random(10000, 99999))
    pairing = true
    pairingSilent = silent and true or false
    if not silent then Print("Searching for Aloha's external WoW account.") end

    -- Probe any visible Battle.net-friend game accounts first.
    local candidates = DiscoverOnlineWoWGameAccounts(sync and sync.peerBattleTag or nil)
    if #candidates == 0 and sync and sync.peerBattleTag and sync.peerBattleTag ~= "" then
        candidates = DiscoverOnlineWoWGameAccounts(nil)
    end

    local sent = {}
    local ownID = OwnGameAccountID()
    local function Probe(id)
        id = tonumber(id)
        if not id or id <= 0 or sent[id] or (ownID and id == ownID) then return end
        sent[id] = true
        SendPairProbe(id)
    end

    -- Fast path: probe the last ID that successfully paired before doing the
    -- wider scan. If Blizzard reassigned it, the session-token/name checks
    -- reject it and discovery continues normally.
    if sync and sync.lastKnownPeerGameAccountID then
        Probe(sync.lastKnownPeerGameAccountID)
    end

    for _, candidate in ipairs(candidates) do
        Probe(candidate.id)
    end

    -- Critical Classic-Era fallback: gameAccountIDs are temporary and have now
    -- been observed moving from low values (3/4) to values such as 57. They are
    -- not always enumerable through the Battle.net friends API, so scan a wider
    -- bounded range. Session-token/name checks prevent self-pairing.
    local nextID = 1
    local function DirectPairStep()
        if not pairing then return end
        while nextID <= DIRECT_PAIR_MAX_ID do
            local id = nextID
            nextID = nextID + 1
            if not sent[id] and (not ownID or id ~= ownID) then
                Probe(id)
                C_Timer.After(DIRECT_PAIR_STEP_DELAY, DirectPairStep)
                return
            end
        end
    end
    DirectPairStep()

    -- 100 IDs at 0.08 seconds is about 8 seconds. Leave extra margin for
    -- BNet throttling and delayed addon-message delivery.
    C_Timer.After(14, function()
        if pairing then
            pairing = false
            if not pairingSilent then
                Print("Pair probe timed out after scanning BNet IDs 1-" .. tostring(DIRECT_PAIR_MAX_ID) .. ". Keep Aloha and Taliaa/Ganktastic online, then /tgank pair again.")
            end
        end
    end)
    return true
end

function Repo:GetBuild()
    return VOIDMARK_REPO_BUILD
end

function Repo:RebuildIndexes()
    local importedRecovery = select(1, ImportRecoveryLedger()) or 0
    local importedLegacy = ImportLegacyFactionEvents() or 0
    local removedEvents = select(1, PurgeExplicitNonPlayerHistory()) or 0
    local total, recovered = RepairLegacyHistory()
    return tonumber(total) or 0,
           (tonumber(recovered) or 0) + (tonumber(importedRecovery) or 0)
           + (tonumber(importedLegacy) or 0) + tonumber(removedEvents)
end

function Repo:Unpair()
    local sync = EnsureSyncDB()
    if not sync then return end
    sync.peerGameAccountID = nil
    sync.peerName = nil
    sync.peerBattleTag = nil
    sync.peerSessionToken = nil
    wipe(sendQueue)
    sendHead = 1
    sendTail = 0
    Print("Gank repository account pairing cleared.")
end

function Repo:PrintStatus(playerName)
    local total, victims = self:GetStats()
    local paired, peerID, peerName = self:GetPeerStatus()

    if playerName and playerName ~= "" then
        local count = self:GetHistoricalCount(playerName, nil)
        Print(tostring(playerName) .. ": " .. tostring(count) .. " historical ganks.")
        return
    end

    Print("Repository: " .. tostring(total) .. " historical kills | " .. tostring(victims) .. " victims.")

    local history = EnsureHistory()
    local byKiller = {}
    for _, event in pairs(history and history.events or {}) do
        local killer = tostring(event and event.killer or "")
        if killer == "" then killer = "Unknown" end
        byKiller[killer] = (byKiller[killer] or 0) + 1
    end
    local parts = {}
    for killer, count in pairs(byKiller) do
        parts[#parts + 1] = tostring(killer) .. " " .. tostring(count)
    end
    table.sort(parts)
    if #parts > 0 then Print("By character: " .. table.concat(parts, " | ")) end

    if paired then
        Print("Peer account: connected via " .. tostring(peerName or "paired character") .. " (current-session ID " .. tostring(peerID) .. ").")
    else
        Print("Peer account: not connected. Auto-pair is " .. ((EnsureSyncDB().autoPair ~= false) and "ON" or "OFF") .. ".")
    end
end

local function ReplyPair(senderID, nonce, senderName, senderNode, senderSessionToken, payloadSenderID)
    local sync = EnsureSyncDB()
    if not sync or not nonce or nonce == "" then return end
    if NormalizePlayerName(senderName) == NormalizePlayerName(UnitName("player")) then return end
    if not senderSessionToken or senderSessionToken == "" then return end
    if tostring(senderSessionToken) == tostring(EnsureLocalSessionToken()) then return end

    -- Accept the live sender ID directly after validating that the probe came
    -- from a different character/session token.  This supports a second WoW
    -- license that is reachable through BNet game data but not listed as a
    -- Battle.net friend.
    local id = tonumber(payloadSenderID) or tonumber(senderID)
    local ownID = OwnGameAccountID()
    if ownID and id == ownID then return end

    local resolvedName, battleTag
    if id then
        local resolvedID
        resolvedID, resolvedName, battleTag = ResolvePeerGameAccountID(senderID, senderName)
        if resolvedID then id = resolvedID end
    else
        id, resolvedName, battleTag = ResolvePeerGameAccountID(senderID, senderName)
    end
    if not id then return end

    -- The external account initiating the scan becomes this account's peer.
    sync.peerGameAccountID = id
    sync.lastKnownPeerGameAccountID = id
    sync.peerName = (resolvedName and resolvedName ~= "") and resolvedName or senderName or sync.peerName or "paired account"
    sync.peerBattleTag = (battleTag and battleTag ~= "") and battleTag or sync.peerBattleTag
    sync.peerSessionToken = tostring(senderSessionToken)
    sync.lastPeerSeen = Now()

    -- Pair ACK is sent immediately so it cannot sit behind a large history sync queue.
    SendBN(id, table.concat({
        "A",
        nonce,
        CleanField(UnitName("player") or "?"),
        CleanField(sync.nodeID or ""),
        CleanField(EnsureLocalSessionToken()),
        tostring(OwnGameAccountID() or ""),
    }, SEP))
    C_Timer.After(1.5, function() Repo:SyncNow(true) end)
end

local function HandlePayload(payload, senderID)
    local parts = SplitPayload(payload)
    local kind = parts[1]
    local sync = EnsureSyncDB()
    if not sync then return end

    if kind == "P" then
        ReplyPair(senderID, parts[2], parts[3], parts[4], parts[5], parts[6])
        return
    end

    if kind == "A" then
        if pairing and parts[2] == pairNonce then
            FinishPair(senderID, parts[3], parts[4], parts[5], parts[6])
        end
        return
    end

    -- TGANK2 authenticates the live peer with a per-login session token.
    -- This avoids relying on the ambiguous numeric position returned by some
    -- Classic Era BN_CHAT_MSG_ADDON builds after pairing is complete.
    local peerToken = tostring(sync.peerSessionToken or "")
    local messageToken = tostring(parts[2] or "")
    if peerToken == "" or messageToken == "" or messageToken ~= peerToken then
        return
    end

    sync.lastPeerSeen = Now()
    sync.lastReceive = sync.lastPeerSeen

    if kind == "I" then
        RememberInventoryChunk(parts)
        return
    end

    if kind == "J" then
        local tx = tostring(parts[3] or "")
        local requestReply = tostring(parts[4] or "0") == "1"
        local slot = incomingInventories[tx] or { kills = {}, dhks = {} }
        incomingInventories[tx] = nil

        if requestReply then
            sync.syncing = true
            sync.syncStartedAt = Now()
            sync.activeSyncTx = tx
        end

        -- requestReply=true is the first leg: send what the initiator is missing.
        -- requestReply=false is the return/final leg: once its D packet is received,
        -- the peer can ACK that BOTH directions are finished.
        QueueMissingEvents(
            sync.peerGameAccountID,
            slot.kills,
            slot.dhks,
            tx,
            not requestReply
        )

        if requestReply then
            sync.bulkReceivePending = true
            QueueInventory(sync.peerGameAccountID, tx .. "-r", false)
        end
        return
    end

    if kind == "Q" then
        QueueAllEvents(sync.peerGameAccountID)
        return
    end

    if kind == "F" then
        local floor = DecodeLegacyFloor(parts)
        if not floor then return end
        local history = EnsureHistory()
        local _, changed = MergeLegacyGap(
            history, floor.name, floor.guid, floor.legacyGap, true
        )
        if changed then
            sync.lastReceive = Now()
            if not sync.bulkReceivePending and TaliaaGankTracker
                and TaliaaGankTracker.OnHistoryUpdated then
                TaliaaGankTracker:OnHistoryUpdated(floor.name, floor.guid, 0)
            end
        end
        return
    end

    if kind == "E" then
        local event = DecodeEvent(parts)
        if not event then return end

        local added = AddEvent(event, sync.bulkReceivePending and true or false)
        if added then sync.lastReceive = Now() end
        return
    end

    if kind == "H" then
        local event = DecodeDHKEvent(parts)
        if not event then return end

        local added = AddDHKEvent(event, sync.bulkReceivePending and true or false)
        if added then sync.lastReceive = Now() end
        return
    end

    if kind == "D" then
        sync.lastSyncComplete = Now()
        local wasBulk = sync.bulkReceivePending
        sync.bulkReceivePending = nil

        local tx = tostring(parts[3] or "")
        local finalLeg = tostring(parts[4] or "0") == "1"

        if wasBulk and TaliaaGankTracker then
            if TaliaaGankTracker.OnHistoryUpdated then
                TaliaaGankTracker:OnHistoryUpdated(nil, nil, 0)
            end
            if TaliaaGankTracker.OnDHKHistoryUpdated then
                TaliaaGankTracker:OnDHKHistoryUpdated()
            end
        end

        if finalLeg then
            -- We just received the LAST missing rows from the initiating account.
            -- Send a completion ACK containing our final repository totals.
            local total, victims = Repo:GetStats()
            local floorCount, floorGap = Repo:GetLegacyFloorStats()
            sync.syncing = false
            sync.lastSyncVerified = Now()
            sync.lastSyncVerifiedTotal = tonumber(total) or 0
            sync.lastSyncVerifiedVictims = tonumber(victims) or 0
            sync.lastSyncVerifiedFloors = tonumber(floorCount) or 0
            sync.lastSyncVerifiedLegacyGap = tonumber(floorGap) or 0

            QueuePayload(sync.peerGameAccountID, table.concat({
                "C",
                CleanField(EnsureLocalSessionToken()),
                CleanField(tx),
                tostring(tonumber(total) or 0),
                tostring(tonumber(victims) or 0),
                tostring(tonumber(floorCount) or 0),
                tostring(tonumber(floorGap) or 0),
            }, SEP))

            Print("SYNC COMPLETE: "
                .. tostring(tonumber(total) or 0) .. " kills / "
                .. tostring(tonumber(victims) or 0) .. " marks / "
                .. tostring(tonumber(floorCount) or 0) .. " historical floors.")
        end
        return
    end

    if kind == "C" then
        -- End-to-end ACK from the peer after it received the final return leg.
        local peerTotal = tonumber(parts[4]) or 0
        local peerVictims = tonumber(parts[5]) or 0
        local peerFloors = tonumber(parts[6]) or 0
        local peerGap = tonumber(parts[7]) or 0
        local myTotal, myVictims = Repo:GetStats()
        local myFloors, myGap = Repo:GetLegacyFloorStats()
        myTotal = tonumber(myTotal) or 0
        myVictims = tonumber(myVictims) or 0
        myFloors = tonumber(myFloors) or 0
        myGap = tonumber(myGap) or 0

        if myTotal == peerTotal and myVictims == peerVictims
            and myFloors == peerFloors and myGap == peerGap then
            sync.syncing = false
            sync.lastSyncVerified = Now()
            sync.lastSyncVerifiedTotal = myTotal
            sync.lastSyncVerifiedVictims = myVictims
            sync.lastSyncVerifiedFloors = myFloors
            sync.lastSyncVerifiedLegacyGap = myGap
            sync.verifyRetries = 0

            Print("SYNC COMPLETE: both accounts match at "
                .. tostring(myTotal) .. " kills / "
                .. tostring(myVictims) .. " marks / "
                .. tostring(myFloors) .. " historical floors.")
        else
            local tries = tonumber(sync.verifyRetries) or 0
            if tries < 3 then
                tries = tries + 1
                sync.verifyRetries = tries
                Print("Sync pass finished but history still differs (kills "
                    .. tostring(myTotal) .. "/" .. tostring(peerTotal)
                    .. ", floors " .. tostring(myFloors) .. "/" .. tostring(peerFloors)
                    .. ", gap " .. tostring(myGap) .. "/" .. tostring(peerGap)
                    .. "). Verifying again " .. tostring(tries) .. "/3...")
                C_Timer.After(1.0, function()
                    Repo:SyncNow(true, true)
                end)
            else
                sync.syncing = false
                Print("SYNC WARNING: 3 verification passes finished but history still differs (kills "
                    .. tostring(myTotal) .. "/" .. tostring(peerTotal)
                    .. ", floors " .. tostring(myFloors) .. "/" .. tostring(peerFloors)
                    .. ", gap " .. tostring(myGap) .. "/" .. tostring(peerGap) .. ").")
            end
        end
        return
    end
end

local function AutoConnectAndSync()
    local sync = EnsureSyncDB()
    if not sync or sync.enabled == false then return end

    if sync.peerGameAccountID then
        if sync.autoSync ~= false then
            local now = Now()
            if (now - (tonumber(sync.lastSyncAttempt) or 0)) >= 20 then
                Repo:SyncNow(true)
            end
        end
    elseif sync.autoPair ~= false and not pairing then
        Repo:StartPairing(true)
        C_Timer.After(AUTO_PAIR_RETRY, function()
            local s = EnsureSyncDB()
            if s and not s.peerGameAccountID and s.autoPair ~= false and not pairing then
                Repo:StartPairing(true)
            end
        end)
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("BN_CHAT_MSG_ADDON")
frame:RegisterEvent("BN_FRIEND_INFO_CHANGED")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        local loginSync = EnsureSyncDB()
        EnsureHistory()
        EnsureDHKHistory()
        RepairDHKHistory()

        -- TGANK2 always renegotiates the live gameAccountID/session token on
        -- login or /reload. Keep peerBattleTag/peerName as rediscovery hints,
        -- but never trust a stale ID from the old self-pairing builds.
        EnsureLocalSessionToken()
        if loginSync then
            loginSync.peerGameAccountID = nil
            loginSync.peerSessionToken = nil
        end

        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(PREFIX)
        end

        -- Import the external recovery ledger first, then legacy faction histories,
        -- then rebuild indexes from the authoritative event rows.
        local importedRecovery, recoveryCount, recoveryUnresolved = ImportRecoveryLedger()
        local importedLegacy = ImportLegacyFactionEvents()
        local importedLegacyDHK = ImportLegacyDHKHistory()
        local removedNonPlayerEvents, removedNonPlayerVictims = PurgeExplicitNonPlayerHistory()
        local total, recovered = RepairLegacyHistory()
        local imported = (tonumber(importedRecovery) or 0) + (tonumber(importedLegacy) or 0)

        if (tonumber(importedLegacyDHK) or 0) > 0 then
            Print("Imported " .. tostring(importedLegacyDHK)
                .. " legacy DHK event" .. (importedLegacyDHK == 1 and "." or "s."))
        end

        if (tonumber(removedNonPlayerEvents) or 0) > 0 or (tonumber(removedNonPlayerVictims) or 0) > 0 then
            Print("Removed " .. tostring(tonumber(removedNonPlayerEvents) or 0)
                .. " pet/NPC kill events from Gank History.")
        end

        if imported > 0 or recovered > 0 then
            Print("Imported/repaired " .. tostring(imported + recovered)
                .. " kill events (" .. tostring(total) .. " local total).")
        end
        if (tonumber(recoveryCount) or 0) > 0 then
            Print("Recovery ledger: " .. tostring(recoveryCount)
                .. " timestamped events"
                .. ((tonumber(recoveryUnresolved) or 0) > 0
                    and (" + " .. tostring(recoveryUnresolved) .. " legacy kills without timestamps")
                    or "")
                .. ".")
        end
        if TaliaaGankTracker and TaliaaGankTracker.OnHistoryUpdated then
            TaliaaGankTracker:OnHistoryUpdated(nil, nil, 0)
        end

        -- Build the special-character/GUID VoidMark lookup once, outside combat. Keep
        -- retrying quietly if the player logs/reloads directly into combat.
        local function BuildVoidMarkIndexWhenSafe()
            if not RebuildVoidMarkFastIndex() then
                C_Timer.After(2.0, BuildVoidMarkIndexWhenSafe)
            end
        end
        C_Timer.After(1.0, BuildVoidMarkIndexWhenSafe)

        -- BNet game-account IDs are temporary for the current Battle.net session,
        -- so refresh the peer every login/reload instead of trusting an old ID.
        C_Timer.After(2, function()
            local s = EnsureSyncDB()
            if s and s.enabled ~= false and s.autoPair ~= false then Repo:StartPairing(true) end
        end)
        C_Timer.After(8, AutoConnectAndSync)
        return
    end

    if event == "BN_CHAT_MSG_ADDON" then
        local args = {...}
        local prefix = args[1]
        local payload = args[2]
        local senderID = ExtractBNetSenderID(...)

        if prefix == PREFIX and payload then
            HandlePayload(payload, senderID)
        end
        return
    end

    if event == "BN_FRIEND_INFO_CHANGED" then
        local sync = EnsureSyncDB()
        if sync then
            local now = Now()
            if now - (tonumber(sync.lastFriendAutoSync) or 0) >= 30 then
                sync.lastFriendAutoSync = now
                C_Timer.After(1, AutoConnectAndSync)
            end
        end
    end
end)

frame:SetScript("OnUpdate", function(_, elapsed)
    local inCombat = InCombatNow()
    local now = GetTime and GetTime() or 0

    if repositoryWasInCombat and not inCombat then
        -- Give the client breathing room after combat. Historical repair waits a
        -- full second; live BNet kill sync can begin after half a second.
        deferredHistoricalNotBefore = now + 1.00
        syncSendNotBefore = now + 0.50
    end
    repositoryWasInCombat = inCombat

    -- v8.9: Never call Battle.net SendGameData while the player is in combat.
    -- A local kill is already safely written to SavedVariables immediately; the
    -- peer receives queued rows after combat instead of stealing time on/near the
    -- death frame.
    if not inCombat and now >= (tonumber(syncSendNotBefore) or 0) then
        if sendHead <= sendTail then
            sendElapsed = sendElapsed + elapsed
            if sendElapsed >= SEND_INTERVAL then
                sendElapsed = 0
                local item = sendQueue[sendHead]
                sendQueue[sendHead] = nil
                sendHead = sendHead + 1
                if item then SendBN(item.id, item.payload) end
            end
        elseif sendTail ~= 0 then
            wipe(sendQueue)
            sendHead = 1
            sendTail = 0
            sendElapsed = 0
        end
    end

    -- Deep historical/accent recovery is intentionally post-combat. Give the
    -- client a short grace period after combat drops, then process at most one
    -- victim every 0.10s so recovery can never land on the kill frame itself.
    if deferredHistoricalHead <= deferredHistoricalTail
        and not inCombat
        and now >= (tonumber(deferredHistoricalNotBefore) or 0) then
        deferredHistoricalElapsed = deferredHistoricalElapsed + elapsed
        if deferredHistoricalElapsed >= 0.10 then
            deferredHistoricalElapsed = 0
            ProcessOneDeferredHistoricalRecovery()
        end
    else
        deferredHistoricalElapsed = 0
    end
end)
