-- TaliaaVoidMark Gank Tracker
-- Panic main-menu toggle: 2026-10-02
local GANKTRACKER_BUILD = "2026-10-03 1.3.8 AUDIT"
-- Daily combined kill tracker + reload-safe local session + global historical repository.
-- Daily victim announcement count fix build: 2026-08-25

TaliaaGankTracker = TaliaaGankTracker or {}
local GT = TaliaaGankTracker
-- Shared with RecordKill: declare before its closures, never as late locals.
local recentOutgoingVictims = {}
local recentConfirmedPlayerKills = {}
local IsUnitCurrentlyFeigningName, MarkHunterFeign
local lastLabel, syncButton
local VOIDMARK_GANK_BUILD = "2026-09-03-stable-local-session"

GT.totalKills = GT.totalKills or 0
GT.uniqueKills = GT.uniqueKills or 0
GT.victims = GT.victims or {}

-- One-time migration for the streak feature: PARTY announcements start ON.
-- After this migration the user's PARTY button choice is respected normally.
if VoidMarkDB and not VoidMarkDB.VoidMarkStreakPartyDefaultV1 then
    VoidMarkDB.TaliaaGankPartyAnnounce = true
    VoidMarkDB.VoidMarkStreakPartyDefaultV1 = true
end

if VoidMarkDB and VoidMarkDB.TaliaaGankPartyAnnounce ~= nil then
    GT.partyAnnounce = VoidMarkDB.TaliaaGankPartyAnnounce and true or false
else
    if GT.partyAnnounce == nil then GT.partyAnnounce = true end
end
GT.seenEnemies = GT.seenEnemies or {}
GT.recentKillEvents = GT.recentKillEvents or {}
GT._pendingRevengeClaims = GT._pendingRevengeClaims or {}
GT.recentHunterPetKills = GT.recentHunterPetKills or {}

local function EnsureHunterPetStats()
    if VoidMarkDB then
        VoidMarkDB.TaliaaHunterPetKills = VoidMarkDB.TaliaaHunterPetKills or { total = 0, byName = {}, events = {} }
        VoidMarkDB.TaliaaHunterPetKills.byName = VoidMarkDB.TaliaaHunterPetKills.byName or {}
        VoidMarkDB.TaliaaHunterPetKills.events = VoidMarkDB.TaliaaHunterPetKills.events or {}
        return VoidMarkDB.TaliaaHunterPetKills
    end
    GT._hunterPetFallback = GT._hunterPetFallback or { total = 0, byName = {}, events = {} }
    GT._hunterPetFallback.events = GT._hunterPetFallback.events or {}
    return GT._hunterPetFallback
end

local function HunterPetKillTotal()
    local db = EnsureHunterPetStats()
    return tonumber(db.total) or 0
end

local function RecordHunterPetKill(petName, petGUID)
    local now = GetTime()
    local key = tostring(petGUID or petName or "?")
    local last = tonumber(GT.recentHunterPetKills[key])
    if last and now - last < 6 then return false end
    GT.recentHunterPetKills[key] = now

    local db = EnsureHunterPetStats()
    db.total = (tonumber(db.total) or 0) + 1
    local name = tostring(petName or "Unknown Pet")
    db.byName[name] = (tonumber(db.byName[name]) or 0) + 1
    db.events = db.events or {}
    local stamp = (GetServerTime and GetServerTime()) or time()
    db.events[#db.events + 1] = { t = tonumber(stamp) or time(), name = name, guid = petGUID }

    -- Today/Week only need recent timestamped events. Keep a bounded window so
    -- the pet tracker cannot grow indefinitely while lifetime stays in db.total.
    local cutoff = (tonumber(stamp) or time()) - (15 * 86400)
    while #db.events > 0 and (tonumber(db.events[1] and db.events[1].t) or 0) < cutoff do
        table.remove(db.events, 1)
    end

    GT._displayRefreshPending = true
    return true
end

local function IsPlayerGUID(guid)
    guid = tostring(guid or "")
    return guid:sub(1, 6) == "Player"
end

local function IsExplicitNonPlayerGUID(guid)
    guid = tostring(guid or "")
    return guid ~= "" and not IsPlayerGUID(guid)
end

-- Kill announcement options.
-- These are persistent VoidMark settings now, so replacing the Lua file does not
-- reset the user's preferred announcement blocks.
local ANNOUNCE_FACTORY = {
    level = true,
    class = false,
    location = false,
    victimKills = false,
    historicalKills = true,
    sessionKills = true,
    uniqueKills = false,
}

local function EnsureAnnounceSettings()
    GT.announceOptions = GT.announceOptions or {}

    if VoidMarkDB then
        VoidMarkDB.TaliaaGankAnnounceSettings = VoidMarkDB.TaliaaGankAnnounceSettings or {}
        local persistent = VoidMarkDB.TaliaaGankAnnounceSettings
        for key, defaultValue in pairs(ANNOUNCE_FACTORY) do
            if persistent[key] == nil then
                if GT.announceOptions[key] ~= nil then
                    persistent[key] = GT.announceOptions[key] and true or false
                else
                    persistent[key] = defaultValue
                end
            end
        end
        GT.announceOptions = persistent
    else
        for key, defaultValue in pairs(ANNOUNCE_FACTORY) do
            if GT.announceOptions[key] == nil then
                GT.announceOptions[key] = defaultValue
            end
        end
    end

    -- VoidMark kill announcements are intentionally fixed now:
    -- Name + level + session total + historical victim count.
    GT.announceOptions.level = true
    GT.announceOptions.class = false
    GT.announceOptions.location = false
    GT.announceOptions.victimKills = false
    GT.announceOptions.historicalKills = true
    GT.announceOptions.sessionKills = true
    GT.announceOptions.uniqueKills = false

    return GT.announceOptions
end

EnsureAnnounceSettings()

local PANIC_WINDOW_SECONDS = 30
local PANIC_LEVEL_MARGIN = 3

local SAP_SPELL_IDS = {
    [6770] = true,  -- Sap Rank 1
    [2070] = true,  -- Sap Rank 2
    [11297] = true, -- Sap Rank 3
}
local lastSapAlertAt
local recentRemoteSapAlerts = {}

local function IsSapAlertEnabled()
    if not VoidMarkDB then return true end
    if VoidMarkDB.VoidMarkSapAlert == nil then VoidMarkDB.VoidMarkSapAlert = true end
    return VoidMarkDB.VoidMarkSapAlert == true
end

local SAP_COMM_PREFIX = "VMSAP"

local function SapAlertDistribution()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function ShowSapAlert(sourceName)
    if not IsSapAlertEnabled() then return end
    local now = GetTime()
    if lastSapAlertAt and now - lastSapAlertAt < 2 then return end
    lastSapAlertAt = now

    local shortName = sourceName and VoidMarkForever.DisplayName(sourceName)
    local groupMsg = shortName and ("{rt8} SAPPED BY "..shortName.." {rt8}") or "{rt8} SAPPED {rt8}"
    local distribution = SapAlertDistribution()

    -- The Sapped player does not get VoidMark's large local warning or sound.
    -- Party/Raid chat still gets the human-readable callout.
    if distribution and SendChatMessage then
        SendChatMessage(groupMsg, distribution)
    end

    -- Separately notify other VoidMark users so their clients can produce the
    -- stronger visual/audio reaction without creating another chat message.
    if distribution and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local myName = VoidMarkForever.API.UnitName("player") or "PARTY MEMBER"
        C_ChatInfo.SendAddonMessage(SAP_COMM_PREFIX, "SAPPED|"..myName, distribution)
    end
end

local function ShowRemoteSapAlert(playerName)
    local shortName = playerName and VoidMarkForever.DisplayName(playerName) or "PARTY MEMBER"
    local msg = "SAPPED  •  "..shortName

    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or {r=1,g=0.2,b=0.2})
    elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1.0, 0.18, 0.22, 1.0)
    end

    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end
function GT:IsSapAlertEnabled()
    return IsSapAlertEnabled()
end

function GT:SetSapAlertEnabled(enabled)
    if VoidMarkDB then VoidMarkDB.VoidMarkSapAlert = enabled and true or false end
end

function GT:ToggleSapAlertEnabled()
    self:SetSapAlertEnabled(not self:IsSapAlertEnabled())
    return self:IsSapAlertEnabled()
end

local sapCommFrame = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(SAP_COMM_PREFIX)
end
VoidMarkForever.RegisterEvent(sapCommFrame,"CHAT_MSG_ADDON")
sapCommFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
    if prefix ~= SAP_COMM_PREFIX or not IsSapAlertEnabled() then return end
    if not VoidMarkForever.IsGroupSender(sender) then return end
    if channel ~= "PARTY" and channel ~= "RAID" then return end
    if type(message) ~= "string" or type(sender) ~= "string" then return end

    local kind = message:match("^([^|]+)|?(.*)$")
    if kind ~= "SAPPED" then return end

    local myName, myRealm
    if VoidMarkForever.API.UnitFullName then myName, myRealm = VoidMarkForever.API.UnitFullName("player") end
    myName = myName or VoidMarkForever.API.UnitName("player")
    myRealm = myRealm or (GetRealmName and GetRealmName())
    local fullSelf = myName and myRealm and (myName.."-"..myRealm:gsub("%s", ""))
    if sender == myName or sender == fullSelf then return end
    local now = GetTime()
    if recentRemoteSapAlerts[sender] and now-recentRemoteSapAlerts[sender] < 2 then return end
    recentRemoteSapAlerts[sender] = now
    -- The transport sender is the sapped party member; keep that identity.
    ShowRemoteSapAlert(sender)
end)

local function PanicPlayerLevel()
    local level = VoidMarkForever.API.UnitLevel and tonumber(VoidMarkForever.API.UnitLevel("player")) or nil
    if not level or level < 1 then return 60 end
    return math.min(60, level)
end

local LEVEL_BUCKET_ORDER = {"1-9", "10-20", "21-30", "31-40", "41-50", "51-59", "60"}
GT.levelKillBuckets = GT.levelKillBuckets or {
    ["1-9"] = 0,
    ["10-20"] = 0,
    ["21-30"] = 0,
    ["31-40"] = 0,
    ["41-50"] = 0,
    ["51-59"] = 0,
    ["60"] = 0,
}

local function LevelBucketKey(level)
    level = tonumber(level)
    if not level then return nil end
    if level >= 1 and level <= 9 then return "1-9" end
    if level >= 10 and level <= 20 then return "10-20" end
    if level >= 21 and level <= 30 then return "21-30" end
    if level >= 31 and level <= 40 then return "31-40" end
    if level >= 41 and level <= 50 then return "41-50" end
    if level >= 51 and level <= 59 then return "51-59" end
    if level == 60 then return "60" end
    return nil
end

-- Daily tracker -------------------------------------------------------------
-- GankRepository already stores every accepted kill persistently in VoidMarkDB with
-- a timestamp. Rebuild the visible counters from today's history so /reload,
-- relogging, and character swaps do not erase the day's hunt.
local DAILY_CLUSTER = "Forever"

local function DailyNow()
    if GetServerTime then
        local t = GetServerTime()
        if t and t > 0 then return t end
    end
    return time()
end

-- Daily hunt reset is 08:00 on the WoW realm clock. Keep a separate realm
-- midnight helper because the weekly Tuesday calculation is anchored to the
-- calendar day and then applies its own 08:00 reset hour.
local DAILY_RESET_HOUR = 8

local function RealmMidnight(now)
    now = tonumber(now) or DailyNow()

    if GetGameTime then
        local hour, minute = GetGameTime()
        hour = tonumber(hour)
        minute = tonumber(minute)
        if hour and minute then
            local second = now % 60
            return now - (hour * 3600) - (minute * 60) - second
        end
    end

    -- Fallback only if the realm clock API is unavailable. Classic Era should
    -- normally use the GetGameTime() path above.
    local hour = tonumber(date("%H", now)) or 0
    local minute = tonumber(date("%M", now)) or 0
    local second = tonumber(date("%S", now)) or 0
    return now - (hour * 3600) - (minute * 60) - second
end

-- Return the start of the CURRENT daily hunt window: 08:00 realm time.
-- Before 08:00, the active window began at 08:00 on the previous realm day.
local function DailyRealmDayStart(now)
    now = tonumber(now) or DailyNow()
    local resetStart = RealmMidnight(now) + (DAILY_RESET_HOUR * 3600)
    if now < resetStart then
        resetStart = resetStart - 86400
    end
    return resetStart
end

local function DailyDateKey()
    return tostring(DailyRealmDayStart())
end

local function BasePlayerName(name)
    local s = tostring(name or "?")
    return s
end

local function NormalizedPlayerName(name)
    if TaliaaGankRepository and TaliaaGankRepository.CanonicalPlayerName then
        return TaliaaGankRepository:CanonicalPlayerName(name)
    end
    return string.lower(BasePlayerName(name))
end


-- Weekly tracker ------------------------------------------------------------
-- Weekly means the current WoW weekly-reset window: Tuesday 08:00 server.
-- Stats are rebuilt from the merged persistent GankRepository history, so
-- synced kills from the other WoW account are included automatically.
local WEEKLY_RESET_WDAY = 3 -- Lua weekday: 1=Sun, 2=Mon, 3=Tue
local WEEKLY_RESET_HOUR = 8

local DailyHistory

local levelLookup = {
    spyFull = {},
    spyBase = {},
    repoFull = {},
    repoBase = {},
    repoGUID = {},
    lastBuild = 0,
    dirty = true,
}

local function ValidLevel(value)
    local level = tonumber(value)
    if level and level >= 1 and level <= 60 then
        return level
    end
    return nil
end

local function RebuildLevelLookup(force)
    local now = GetTime and GetTime() or 0

    -- UpdateDisplay runs every second while the Gank Tracker is visible.
    -- Do not walk the restored 3k+ VoidMark database every tick.
    if not force and not levelLookup.dirty and (now - (levelLookup.lastBuild or 0)) < 60 then
        return
    end

    local spyFull, spyBase = {}, {}
    local repoFull, repoBase, repoGUID = {}, {}, {}

    -- Build the VoidMark lookup ONCE per stats refresh. The previous version scanned
    -- the entire 3k+ PlayerData table separately for every unresolved kill event,
    -- which could trip WoW's "script ran too long" watchdog.
    local playerData = VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData
    if type(playerData) == "table" then
        for key, data in pairs(playerData) do
            if type(data) == "table" then
                local full = string.lower(tostring(key or ""))
                if full ~= "" then
                    spyFull[full] = data
                end

                local base = NormalizedPlayerName(key)
                if base ~= "" then
                    if spyBase[base] == nil then
                        spyBase[base] = data
                    elseif spyBase[base] ~= data then
                        spyBase[base] = false -- ambiguous base name
                    end
                end
            end
        end
    end

    local history = DailyHistory and DailyHistory() or nil
    if history and type(history.victims) == "table" then
        for _, victim in pairs(history.victims) do
            if type(victim) == "table" and victim.name then
                local full = string.lower(tostring(victim.name))
                if full ~= "" then
                    repoFull[full] = victim
                end

                local guid = tostring(victim.guid or "")
                if guid:sub(1, 6) == "Player" then
                    repoGUID[guid] = victim
                end

                local base = NormalizedPlayerName(victim.name)
                if base ~= "" then
                    if repoBase[base] == nil then
                        repoBase[base] = victim
                    elseif repoBase[base] ~= victim then
                        repoBase[base] = false -- ambiguous base name
                    end
                end
            end
        end
    end

    levelLookup.spyFull = spyFull
    levelLookup.spyBase = spyBase
    levelLookup.repoFull = repoFull
    levelLookup.repoBase = repoBase
    levelLookup.repoGUID = repoGUID
    levelLookup.lastBuild = now
    levelLookup.dirty = false
end

local function FindPlayerDataForName(playerName)
    local full = string.lower(tostring(playerName or ""))
    local data = levelLookup.spyFull[full]
    if data then return data end

    local base = NormalizedPlayerName(playerName)
    data = levelLookup.spyBase[base]
    if data and data ~= false then
        return data
    end

    -- A newly detected player can be added after the last cache rebuild.
    -- Exact-key lookup is O(1), so check it without walking the whole DB.
    if VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData then
        return VoidMarkPerCharDB.PlayerData[playerName]
    end

    return nil
end

local function SyncVoidMarkLifetimeRecord(playerName, playerGUID, historicalKills)
    local total = tonumber(historicalKills) or 0
    if total <= 0 then return end

    local data = FindPlayerDataForName(playerName)
    if data then
        -- PlayerData.wins is now only a presentation cache. The repository
        -- already folds in preserved legacy wins/floors, so mirroring the
        -- canonical total prevents the old VoidMark kill counter from double-counting
        -- the same real death.
        data.wins = total
        if playerGUID and tostring(playerGUID) ~= "" and not data.guid then
            data.guid = playerGUID
        end
    end

    -- Repaint VoidMark outside combat so the W/L value changes immediately.
    if VoidMark and VoidMark.RefreshCurrentList and not (InCombatLockdown and InCombatLockdown()) then
        VoidMark:RefreshCurrentList()
    end
end

local function ResolveKnownLevel(playerName, playerGUID, storedLevel)
    local level = ValidLevel(storedLevel)
    if level then return level end

    local data = FindPlayerDataForName(playerName)
    level = data and ValidLevel(data.level) or nil
    if level then return level end

    local guid = tostring(playerGUID or "")
    local victim = nil

    if guid:sub(1, 6) == "Player" then
        victim = levelLookup.repoGUID[guid]
    end

    if not victim then
        victim = levelLookup.repoFull[string.lower(tostring(playerName or ""))]
    end

    if not victim then
        local baseVictim = levelLookup.repoBase[NormalizedPlayerName(playerName)]
        if baseVictim and baseVictim ~= false then
            victim = baseVictim
        end
    end

    level = victim and ValidLevel(victim.lastLevel) or nil
    return level
end

local function ResolveEventLevel(event)
    if type(event) ~= "table" then return nil end

    local level = ValidLevel(event.level)
    if level then return level end

    level = ResolveKnownLevel(event.name, event.guid, event.level)
    if level then
        -- Repair old "?" event rows once. After this, future reports use the
        -- stored numeric value and do not need any lookup at all.
        event.level = level
    end
    return level
end

local function WeeklyResetStart(now)
    now = tonumber(now) or DailyNow()

    -- Prefer Blizzard's reset timer when this Classic build exposes it.
    -- This automatically follows the realm/region reset schedule and DST.
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, seconds = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        seconds = ok and tonumber(seconds) or nil
        if seconds and seconds >= 0 and seconds <= (8 * 86400) then
            return now + seconds - (7 * 86400)
        end
    end

    -- Fallback: calculate Tuesday 08:00 from the current realm-local day.
    local dayStart = RealmMidnight(now)

    -- Noon relative to realm midnight is safely on the same calendar date for
    -- North American realms, allowing UTC date() to supply the weekday without
    -- depending on the PC's local timezone.
    local calendar = date("!*t", dayStart + (12 * 3600))
    local wday = tonumber(calendar and calendar.wday) or WEEKLY_RESET_WDAY
    local daysSinceTuesday = (wday - WEEKLY_RESET_WDAY) % 7

    local resetStart = dayStart - (daysSinceTuesday * 86400) + (WEEKLY_RESET_HOUR * 3600)
    if now < resetStart then
        resetStart = resetStart - (7 * 86400)
    end

    return resetStart
end


-- Player death history -------------------------------------------------------
-- Keep a tiny timestamp log for K/D display.  This is intentionally separate
-- from kill history so player deaths do not affect marks, streak credit, or
-- repository sync semantics.
local function EnsurePlayerDeathHistory()
    if not VoidMarkDB then return nil end
    VoidMarkDB.TaliaaGankPlayerDeaths = VoidMarkDB.TaliaaGankPlayerDeaths or { events = {} }
    local db = VoidMarkDB.TaliaaGankPlayerDeaths
    db.events = db.events or {}
    return db
end

local function RecordPlayerDeathTimestamp()
    local db = EnsurePlayerDeathHistory()
    if not db then return end
    local now = DailyNow()
    local events = db.events

    -- PLAYER_DEAD should only fire once per death, but keep a small guard so a
    -- client quirk/reload cannot add the same death twice.
    local last = events[#events]
    if last and math.abs(now - (tonumber(last.t) or 0)) < 3 then return end

    events[#events + 1] = { t = now }

    -- K/D only needs current/nearby history.  Trim anything older than roughly
    -- two weekly windows so this list stays permanently tiny.
    local cutoff = now - (15 * 86400)
    while #events > 0 and (tonumber(events[1] and events[1].t) or 0) < cutoff do
        table.remove(events, 1)
    end
end

local function PlayerDeathsInRange(startTime, endTime)
    local db = EnsurePlayerDeathHistory()
    if not db then return 0 end
    startTime = tonumber(startTime) or 0
    endTime = tonumber(endTime) or math.huge
    local total = 0
    for _, event in ipairs(db.events or {}) do
        local t = tonumber(event and event.t) or 0
        if t >= startTime and t <= endTime then
            total = total + 1
        end
    end
    return total
end

local function PlayerDeathsToday()
    local now = DailyNow()
    return PlayerDeathsInRange(DailyRealmDayStart(now), now + 60)
end

local function PlayerDeathsWeekly()
    local now = DailyNow()
    return PlayerDeathsInRange(WeeklyResetStart(now), now + 60)
end

local function KDRatioText(kills, deaths)
    kills = tonumber(kills) or 0
    deaths = tonumber(deaths) or 0
    if deaths <= 0 then
        return kills > 0 and "INF" or "0.00"
    end
    return string.format("%.2f", kills / deaths)
end

local function HunterPetKillsInRange(startTime, endTime)
    local db = EnsureHunterPetStats()
    local events = db.events or {}
    local total = 0
    startTime = tonumber(startTime) or 0
    endTime = tonumber(endTime) or math.huge
    for _, event in ipairs(events) do
        local t = tonumber(event and event.t) or 0
        if t >= startTime and t <= endTime then
            total = total + 1
        end
    end
    return total
end

local function HunterPetKillToday()
    local now = DailyNow()
    return HunterPetKillsInRange(DailyRealmDayStart(now), now + 60)
end

local function HunterPetKillWeekly()
    local now = DailyNow()
    local weekStart = WeeklyResetStart(now)

    -- Weekly is strictly timestamp-based. Older lifetime-only pet records cannot
    -- be assigned to a week without inventing a date. Lifetime remains intact in
    -- db.total, while current Today/Week counts use only known timestamps.
    local db = EnsureHunterPetStats()
    db.legacyWeeklyCarry = nil
    db.legacyWeeklyCarryWeekStart = nil
    db.legacyWeeklyMigrationDone = true

    return HunterPetKillsInRange(weekStart, now + 60)
end

local recordStatsCache = {
    eventCount = -1,
    stats = nil,
}

-- PERFORMANCE: the tracker UI refreshes once per second. Weekly totals only
-- change when the repository event generation changes or the weekly reset
-- boundary changes, so never rescan thousands of historical rows every tick.
local weeklyStatsCache = {
    eventCount = -1,
    lastEventTime = -1,
    weekStart = nil,
    stats = nil,
}

local function ShortDate(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 then return "?" end
    return date("!%b %d", timestamp)
end

local function BuildRecordStats()
    local history = DailyHistory()
    local eventCount = history and tonumber(history.eventCount) or 0

    local now = DailyNow()
    local currentWeekStart = WeeklyResetStart(now)
    local lastEventTime = history and tonumber(history.lastEventTime) or 0
    if recordStatsCache.stats and recordStatsCache.eventCount == eventCount
        and recordStatsCache.history == history
        and recordStatsCache.lastEventTime == lastEventTime
        and recordStatsCache.weekStart == currentWeekStart then
        return recordStatsCache.stats, true
    end

    local stats = {
        total = 0,
        marks = 0,
        repeats = 0,
        bestWeek = 0,
        bestWeekStart = 0,
        bestWeekEnd = 0,
        currentWeek = 0,
    }

    if not TaliaaGankRepository or not TaliaaGankRepository.GetEventsInRange then
        return stats, false
    end

    if TaliaaGankRepository.GetStats then
        stats.total, stats.marks = TaliaaGankRepository:GetStats()
        stats.total = tonumber(stats.total) or 0
        stats.marks = tonumber(stats.marks) or 0
    end
    stats.repeats = math.max(0, stats.total - stats.marks)

    local WEEK = 7 * 86400
    local events = TaliaaGankRepository:GetEventsInRange(1, now + 60)
    local weeklyCounts = {}

    for _, event in pairs(events or {}) do
        if type(event) == "table" then
            local t = tonumber(event.t or event.time or event.timestamp) or 0
            if t > 0 then
                -- Anchor historical weeks to the current realm weekly reset.
                local index = math.floor((t - currentWeekStart) / WEEK)
                local weekStart = currentWeekStart + (index * WEEK)
                weeklyCounts[weekStart] = (weeklyCounts[weekStart] or 0) + 1
            end
        end
    end

    stats.currentWeek = tonumber(weeklyCounts[currentWeekStart]) or 0

    -- Personal best means a completed reset-to-reset week. If there is no
    -- completed week in the repository yet, fall back to the current week.
    for weekStart, count in pairs(weeklyCounts) do
        if weekStart < currentWeekStart and count > stats.bestWeek then
            stats.bestWeek = count
            stats.bestWeekStart = weekStart
            stats.bestWeekEnd = weekStart + WEEK
        end
    end

    if stats.bestWeek <= 0 then
        stats.bestWeek = stats.currentWeek
        stats.bestWeekStart = currentWeekStart
        stats.bestWeekEnd = currentWeekStart + WEEK
    end

    recordStatsCache.eventCount = eventCount
    recordStatsCache.history = history
    recordStatsCache.lastEventTime = lastEventTime
    recordStatsCache.weekStart = currentWeekStart
    recordStatsCache.stats = stats
    return stats, true
end

local function BuildWeeklyStats()
    local now = DailyNow()
    local weekStart = WeeklyResetStart(now)

    -- Sanity-check the reset calculation. A current weekly window can never
    -- begin in the future or more than roughly seven days ago.
    if weekStart > now or (now - weekStart) > (7 * 86400 + 3600) then
        local dayStart = RealmMidnight(now)
        local calendar = date("!*t", dayStart + (12 * 3600))
        local wday = tonumber(calendar and calendar.wday) or WEEKLY_RESET_WDAY
        local daysSinceTuesday = (wday - WEEKLY_RESET_WDAY) % 7
        weekStart = dayStart - (daysSinceTuesday * 86400) + (WEEKLY_RESET_HOUR * 3600)
        if now < weekStart then weekStart = weekStart - (7 * 86400) end
    end

    local history = DailyHistory and DailyHistory() or nil
    local eventCount = history and (tonumber(history.eventCount) or 0) or 0
    local lastEventTime = history and (tonumber(history.lastEventTime) or 0) or 0
    if weeklyStatsCache.stats
        and weeklyStatsCache.eventCount == eventCount
        and weeklyStatsCache.lastEventTime == lastEventTime
        and weeklyStatsCache.weekStart == weekStart then
        return weeklyStatsCache.stats, true
    end

    RebuildLevelLookup()

    local stats = {
        startTime = weekStart,
        endTime = now,
        total = 0,
        unique = 0,
        repeats = 0,
        level60 = 0,
        noobs = 0,
        unknown = 0,
        levelBuckets = {
            ["1-9"] = 0,
            ["10-20"] = 0,
            ["21-30"] = 0,
            ["31-40"] = 0,
            ["41-50"] = 0,
            ["51-59"] = 0,
            ["60"] = 0,
        },
    }

    local events = nil

    if TaliaaGankRepository and TaliaaGankRepository.GetEventsInRange then
        -- Aggregate counters do not need chronological sorting.
        events = TaliaaGankRepository:GetEventsInRange(weekStart, now + 60, true)
    else
        local history = DailyHistory()
        if history and type(history.events) == "table" then
            events = {}
            for _, event in pairs(history.events) do
                local eventTime = tonumber(event and (event.t or event.time or event.timestamp)) or 0
                if eventTime >= weekStart and eventTime <= (now + 60) then
                    events[#events + 1] = event
                end
            end
        end
    end

    if type(events) ~= "table" then
        return stats, false
    end

    local unique = {}

    for _, event in pairs(events) do
        if type(event) == "table" then
            stats.total = stats.total + 1

            local name = tostring(event.name or "?")
            local guid = tostring(event.guid or "")
            local uniqueKey
            if guid:sub(1, 6) == "Player" then
                uniqueKey = guid
            else
                uniqueKey = string.lower(name)
            end
            unique[uniqueKey] = true

            local level = ResolveEventLevel(event)
            if level == 60 then
                stats.level60 = stats.level60 + 1
            elseif level and level < 60 then
                stats.noobs = stats.noobs + 1
            else
                stats.unknown = stats.unknown + 1
            end

            local bucket = LevelBucketKey(level)
            if bucket then
                stats.levelBuckets[bucket] = (stats.levelBuckets[bucket] or 0) + 1
            end
        end
    end

    for _ in pairs(unique) do
        stats.unique = stats.unique + 1
    end

    stats.repeats = math.max(0, stats.total - stats.unique)

    local repoTotal = 0
    if TaliaaGankRepository and TaliaaGankRepository.GetStats then
        repoTotal = tonumber((select(1, TaliaaGankRepository:GetStats()))) or 0
    end
    local marker = VoidMarkDB and VoidMarkDB.TaliaaGankOfflineSync
    local fileMerged = type(marker) == "table" and tonumber(marker.merged) or 0

    stats.repositoryTotal = repoTotal
    stats.fileMerged = fileMerged
    stats.incomplete = (fileMerged > 0 and repoTotal > 0 and fileMerged > repoTotal)

    weeklyStatsCache.eventCount = eventCount
    weeklyStatsCache.lastEventTime = lastEventTime
    weeklyStatsCache.weekStart = weekStart
    weeklyStatsCache.stats = stats
    return stats, true
end

local function DailyFaction()
    if VoidMark and VoidMark.FactionName and VoidMark.FactionName ~= "" then
        return VoidMark.FactionName
    end
    return VoidMarkForever.API.UnitFactionGroup("player") or "Unknown"
end

DailyHistory = function()
    if not VoidMarkDB or not VoidMarkDB.TaliaaGankGlobal then return nil end
    local shared = VoidMarkDB.TaliaaGankGlobal[DAILY_CLUSTER]
    return shared and shared.GankHistory or nil
end

-- Reload-safe local session stats. "Session" is this character's current
-- 08:00-to-08:00 hunt window. /reload, relogging and zoning do not erase it,
-- but crossing the daily 08:00 realm reset automatically starts a new session.
local function SessionKey()
    return tostring(VoidMarkForever.API.UnitName("player") or "?") .. "-" .. tostring(GetRealmName and GetRealmName() or "?")
end

local function EnsureSessionStats()
    if not VoidMarkDB then
        GT.sessionKills = tonumber(GT.sessionKills) or 0
        GT.sessionVictims = GT.sessionVictims or {}
        return nil
    end

    VoidMarkDB.TaliaaGankSessions = VoidMarkDB.TaliaaGankSessions or {}
    local key = SessionKey()
    local dailyStart = DailyRealmDayStart(DailyNow())
    VoidMarkDB.TaliaaGankSessions[key] = VoidMarkDB.TaliaaGankSessions[key] or {
        count = 0,
        victims = {},
        -- First install seeds this character from rows in the active 08:00 daily
        -- window so an already-running hunt is not lost.
        startedAt = dailyStart,
        seededFromHistory = false,
        streak = 0,
        bestStreak = 0,
        revengeTargets = {},
        dhkCount = 0,
    }
    local session = VoidMarkDB.TaliaaGankSessions[key]

    -- Preserve the live streak across /reload. SavedVariables are only flushed to
    -- disk on logout/reload, so snapshot the current runtime streak before the
    -- reload tears the UI down. This does not reconstruct or alter kill history.
    GT._sessionKey = key

    -- Old builds let Session continue forever until a manual reset. If the saved
    -- session began before the active 08:00 window, roll it forward now. Seed it
    -- once from repository rows so kills already made after 08:00 survive relogs.
    local savedStart = tonumber(session.startedAt) or 0
    if savedStart < dailyStart then
        session.count = 0
        session.victims = {}
        session.startedAt = dailyStart
        session.seededFromHistory = false
        session.seedVersion = 4
        session.streak = 0
        session.bestStreak = 0
        session.revengeTargets = {}
        session.dhkCount = 0
    end

    session.count = tonumber(session.count) or 0
    session.victims = session.victims or {}
    session.startedAt = tonumber(session.startedAt) or dailyStart
    session.streak = tonumber(session.streak) or 0
    session.bestStreak = tonumber(session.bestStreak) or 0
    session.revengeTargets = session.revengeTargets or {}
    session.dhkCount = tonumber(session.dhkCount) or 0

    -- Session display/count is the merged account-wide 08:00 daily hunt.
    -- Keep this table only for character-local streak/revenge/DHK persistence.
    GT.sessionStartedAt = session.startedAt
    GT.currentStreak = session.streak
    GT.bestStreak = session.bestStreak
    GT.revengeTargets = session.revengeTargets
    GT.sessionDHK = session.dhkCount
    return session
end

local streakSaveFrame = CreateFrame("Frame")
VoidMarkForever.RegisterEvent(streakSaveFrame,"PLAYER_LOGOUT")
streakSaveFrame:SetScript("OnEvent", function()
    if not VoidMarkDB or not VoidMarkDB.TaliaaGankSessions then return end
    local key = GT._sessionKey or SessionKey()
    local session = VoidMarkDB.TaliaaGankSessions[key]
    if not session then return end
    session.streak = math.max(0, tonumber(GT.currentStreak) or tonumber(session.streak) or 0)
    session.bestStreak = math.max(tonumber(session.bestStreak) or 0, tonumber(GT.bestStreak) or 0, session.streak)
end)

local function SeedSessionFromHistory()
    local session = EnsureSessionStats()
    if not session then return false end

    -- Seed only once. After a session exists, its persisted local counter is the
    -- authority. Rebuilding it from the merged repository on every kill/sync can
    -- make SESS jump backward or forward because the repository intentionally
    -- deduplicates the same death seen by both WoW accounts and may retain the
    -- peer account's copy/killer name instead of this character's copy.
    if session.seededFromHistory then
        return true
    end

    local history = DailyHistory()
    if not history or type(history.events) ~= "table" then return false end

    local me = string.lower(tostring(VoidMarkForever.API.UnitName("player") or ""))
    local startAt = tonumber(session.startedAt) or DailyRealmDayStart(DailyNow())
    local count = 0
    local victims = {}

    for _, event in pairs(history.events) do
        local killer = string.lower(tostring(event and event.killer or ""))
        local t = tonumber(event and event.t) or 0
        if killer == me and t >= startAt then
            count = count + 1
            local name = tostring(event.name or "?")
            victims[name] = (victims[name] or 0) + 1
        end
    end

    session.count = count
    session.victims = victims
    session.seededFromHistory = true
    session.seedVersion = 4
    return true
end

local function AddSessionKill(playerName)
    SeedSessionFromHistory()
    local session = EnsureSessionStats()
    if session then
        session.count = (tonumber(session.count) or 0) + 1
        local name = tostring(playerName or "?")
        session.victims[name] = (tonumber(session.victims[name]) or 0) + 1
        session.streak = (tonumber(session.streak) or 0) + 1
        session.bestStreak = math.max(tonumber(session.bestStreak) or 0, session.streak)

        GT.currentStreak = session.streak
        GT.bestStreak = session.bestStreak
    else
        GT.sessionKills = (tonumber(GT.sessionKills) or 0) + 1
        GT.sessionVictims = GT.sessionVictims or {}
        GT.sessionVictims[playerName] = (tonumber(GT.sessionVictims[playerName]) or 0) + 1
        GT.currentStreak = (tonumber(GT.currentStreak) or 0) + 1
        GT.bestStreak = math.max(tonumber(GT.bestStreak) or 0, GT.currentStreak)
    end
end

local function ResetSessionStats()
    local now = DailyNow()
    if VoidMarkDB then
        VoidMarkDB.TaliaaGankSessions = VoidMarkDB.TaliaaGankSessions or {}
        VoidMarkDB.TaliaaGankSessions[SessionKey()] = {
            count = 0,
            victims = {},
            startedAt = now,
            seededFromHistory = true,
            streak = 0,
            bestStreak = 0,
            revengeTargets = {},
            dhkCount = 0,
        }
    end
    GT.sessionStartedAt = now
    GT.currentStreak = 0
    GT.bestStreak = 0
    GT.revengeTargets = {}
    GT.sessionDHK = 0
end

local function DailyResetCutoff(dayKey)
    if not VoidMarkDB or not VoidMarkDB.TaliaaGankDailyReset then return 0 end
    local factionStore = VoidMarkDB.TaliaaGankDailyReset[DailyFaction()]
    return factionStore and (tonumber(factionStore[dayKey]) or 0) or 0
end

local function SetDailyResetCutoff(dayKey, timestamp)
    if not VoidMarkDB then return end
    VoidMarkDB.TaliaaGankDailyReset = VoidMarkDB.TaliaaGankDailyReset or {}
    local faction = DailyFaction()
    VoidMarkDB.TaliaaGankDailyReset[faction] = VoidMarkDB.TaliaaGankDailyReset[faction] or {}
    VoidMarkDB.TaliaaGankDailyReset[faction][dayKey] = tonumber(timestamp) or DailyNow()
end

local function DailyLocation(event)
    local zone = tostring(event and event.zone or "Unknown")
    local subZone = tostring(event and event.subZone or "")
    if subZone ~= "" and subZone ~= zone then
        return zone .. " - " .. subZone
    end
    return zone
end

local function RefreshDailyStats()
    RebuildLevelLookup()
    local now = DailyNow()
    local dayStart = DailyRealmDayStart(now)
    local dayKey = tostring(dayStart)
    GT._dailyDateKey = dayKey

    local history = DailyHistory()
    if not history or type(history.events) ~= "table" then
        -- Never leave yesterday's in-memory totals visible when the repository
        -- is temporarily unavailable during login/reload.
        GT.totalKills = 0
        GT.uniqueKills = 0
        GT.daily60Kills = 0
        GT.dailyNoobKills = 0
        GT.dailyUnknownLevelKills = 0
        GT.victims = {}
        GT.levelKillBuckets = {}
        GT.sessionKills = 0
        GT.sessionVictims = {}
        GT.lastKillName = nil
        GT.lastKillGUID = nil
        GT.lastKillLevel = nil
        GT.lastKillLocation = nil
        GT.lastKillHistorical = 0
        return false
    end

    -- Fixed daily boundary is 08:00 realm time. Ignore the old per-account
    -- manual cutoff because it made synced accounts show different totals.
    local total = 0
    local daily60 = 0
    local dailyNoobs = 0
    local dailyUnknown = 0
    local victims = {}
    local unique = {}
    local buckets = {
        ["1-9"] = 0,
        ["10-20"] = 0,
        ["21-30"] = 0,
        ["31-40"] = 0,
        ["41-50"] = 0,
        ["51-59"] = 0,
        ["60"] = 0,
    }
    local lastEvent = nil
    local lastTime = 0

    for _, event in pairs(history.events) do
        local eventTime = tonumber(event and event.t) or 0
        -- Count only events from the active realm 08:00 daily reset through now.
        -- This follows the WoW realm clock instead of the PC timezone.
        if eventTime >= dayStart and eventTime <= (now + 60) then
            total = total + 1

            local name = tostring(event.name or "?")
            local guid = tostring(event.guid or "")
            local uniqueKey
            if guid:sub(1, 6) == "Player" then
                uniqueKey = guid
            else
                uniqueKey = string.lower(name)
            end
            unique[uniqueKey] = true

            local victim = victims[name]
            if not victim then
                victim = { kills = 0, lastZone = "Unknown", lastSubZone = "", guid = guid }
                victims[name] = victim
            end
            victim.kills = (tonumber(victim.kills) or 0) + 1
            victim.guid = guid ~= "" and guid or victim.guid
            victim.lastZone = tostring(event.zone or victim.lastZone or "Unknown")
            victim.lastSubZone = tostring(event.subZone or victim.lastSubZone or "")

            local eventLevel = ResolveEventLevel(event)
            if eventLevel == 60 then
                daily60 = daily60 + 1
            elseif eventLevel and eventLevel < 60 then
                dailyNoobs = dailyNoobs + 1
            else
                dailyUnknown = dailyUnknown + 1
            end

            local bucket = LevelBucketKey(eventLevel)
            if bucket then
                buckets[bucket] = (buckets[bucket] or 0) + 1
            end

            if eventTime >= lastTime then
                lastTime = eventTime
                lastEvent = event
            end
        end
    end

    local uniqueCount = 0
    for _ in pairs(unique) do uniqueCount = uniqueCount + 1 end

    GT.totalKills = total
    GT.uniqueKills = uniqueCount
    GT.daily60Kills = daily60
    GT.dailyNoobKills = dailyNoobs
    GT.dailyUnknownLevelKills = dailyUnknown
    GT.victims = victims
    GT.levelKillBuckets = buckets

    -- "Session" is the shared current hunt window (08:00 -> 08:00), not a
    -- character-local login/session counter. Because 'victims' is rebuilt from
    -- the merged repository, character swaps and paired-account syncs all show
    -- the same Session total and per-victim Session count.
    GT.sessionKills = total
    GT.sessionVictims = {}
    for name, victim in pairs(victims) do
        GT.sessionVictims[name] = tonumber(victim and victim.kills) or 0
    end

    if lastEvent then
        GT.lastKillName = tostring(lastEvent.name or "?")
        GT.lastKillGUID = tostring(lastEvent.guid or "")
        GT.lastKillLevel = lastEvent.level or "?"
        GT.lastKillLocation = DailyLocation(lastEvent)
        if TaliaaGankRepository and TaliaaGankRepository.GetHistoricalCount then
            GT.lastKillHistorical = TaliaaGankRepository:GetHistoricalCount(GT.lastKillName, GT.lastKillGUID) or 0
        end
    else
        GT.lastKillName = nil
        GT.lastKillGUID = nil
        GT.lastKillLevel = nil
        GT.lastKillLocation = nil
        GT.lastKillHistorical = 0
    end

    return true
end
local GetVictimKillCount
local UpdatePanicDisplay

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffb86cff[VoidMark Gank]|r " .. tostring(msg))
end

local function RefreshSessionDHK()
    local session = EnsureSessionStats()
    if session then
        session.dhkCount = tonumber(session.dhkCount) or 0
        GT.sessionDHK = session.dhkCount
    else
        GT.sessionDHK = tonumber(GT.sessionDHK) or 0
    end
    return GT.sessionDHK
end

local function IsDishonorableKillMessage(message)
    message = tostring(message or "")
    if message == "" then return false end

    -- Classic's honor combat message is e.g. "<name> dies, dishonorable kill."
    -- Use the localized Blizzard format when available; enUS text is a fallback.
    local fmt = _G and _G.COMBATLOG_DISHONORGAIN
    if type(fmt) == "string" and fmt ~= "" then
        local pattern = fmt
        pattern = pattern:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
        pattern = pattern:gsub("%%%%s", ".+")
        pattern = pattern:gsub("%%%%d", "%%d+")
        if message:match("^" .. pattern .. "$") then
            return true
        end
    end

    return string.find(string.lower(message), "dishonorable kill", 1, true) ~= nil
end

local function EnsureDHKHistory()
    if not VoidMarkDB then return nil end
    VoidMarkDB.TaliaaGankDHKHistory = VoidMarkDB.TaliaaGankDHKHistory or {
        version = 1,
        events = {},
        nextID = 0,
    }
    local history = VoidMarkDB.TaliaaGankDHKHistory
    history.events = history.events or {}
    history.nextID = tonumber(history.nextID) or 0
    return history
end

local dhkCountsCache = {
    eventCount = -1,
    dayStart = nil,
    weekStart = nil,
    today = 0,
    weekly = 0,
    lifetime = 0,
}

local function GetDHKCounts()
    local now = DailyNow()
    local dayStart = DailyRealmDayStart(now)
    local weekStart = WeeklyResetStart(now)
    local eventCount = nil

    if TaliaaGankRepository and TaliaaGankRepository.GetDHKCount then
        eventCount = tonumber(TaliaaGankRepository:GetDHKCount()) or 0
        if dhkCountsCache.eventCount == eventCount
            and dhkCountsCache.dayStart == dayStart
            and dhkCountsCache.weekStart == weekStart then
            return dhkCountsCache.today, dhkCountsCache.weekly, dhkCountsCache.lifetime
        end
    end

    local today, weekly, lifetime = 0, 0, 0
    local events = nil
    if TaliaaGankRepository and TaliaaGankRepository.GetDHKEventsInRange then
        events = TaliaaGankRepository:GetDHKEventsInRange(0, now + 60)
    else
        -- Compatibility fallback for one build that stored DHKs only in the local
        -- VoidMarkDB table. GankRepository imports this table automatically once updated.
        local history = EnsureDHKHistory()
        events = history and history.events or nil
    end

    if type(events) ~= "table" then
        return 0, 0, tonumber(GT.sessionDHK) or 0
    end

    for _, event in pairs(events) do
        if type(event) == "table" then
            local t = tonumber(event.t) or 0
            if t > 0 and t <= (now + 60) then
                lifetime = lifetime + 1
                if t >= weekStart then weekly = weekly + 1 end
                if t >= dayStart then today = today + 1 end
            end
        end
    end

    if eventCount ~= nil then
        dhkCountsCache.eventCount = eventCount
        dhkCountsCache.dayStart = dayStart
        dhkCountsCache.weekStart = weekStart
        dhkCountsCache.today = today
        dhkCountsCache.weekly = weekly
        dhkCountsCache.lifetime = lifetime
    end

    return today, weekly, lifetime
end

local UpdateDisplay

local function GetBlizzardTodayDHKs()
    if type(GetPVPSessionStats) ~= "function" then return nil end

    local ok, _, dishonorableKills = pcall(GetPVPSessionStats)
    if not ok then return nil end

    local value = tonumber(dishonorableKills)
    if not value or value < 0 or value ~= math.floor(value) then
        return nil
    end

    -- Defensive ceiling. This is a kill count, not honor points.
    if value > 10000 then return nil end
    return value
end

local function GetRepoCharacterDHKsToday()
    if not TaliaaGankRepository
        or not TaliaaGankRepository.GetDHKCountForCharacterInRange then
        return 0
    end

    local now = DailyNow()
    return tonumber(TaliaaGankRepository:GetDHKCountForCharacterInRange(
        SessionKey(),
        DailyRealmDayStart(now),
        now + 60
    )) or 0
end

local function ReconcileCurrentCharacterDHKs(silent)
    if not TaliaaGankRepository or not TaliaaGankRepository.RecordDHK then
        return 0
    end

    local expected = GetBlizzardTodayDHKs()
    if expected == nil then return 0 end

    local now = DailyNow()
    local dayStart = DailyRealmDayStart(now)
    local character = SessionKey()

    -- Clean only rows created by the two earlier experimental API-recovery builds.
    -- Real combat-message rows are never deleted here.
    if TaliaaGankRepository.RemoveBrokenSyntheticDHKsForCharacterInRange then
        TaliaaGankRepository:RemoveBrokenSyntheticDHKsForCharacterInRange(
            character, dayStart, now + 60, expected
        )
    end

    local have = GetRepoCharacterDHKsToday()
    local missing = math.max(0, expected - have)
    if missing <= 0 then return 0 end

    local added = 0
    for i = 1, missing do
        -- Give each backfilled row a distinct timestamp/message. The repository
        -- still dedupes network retransmits but will preserve multiple real DHKs.
        local stamp = now - ((missing - i) * 2)
        if stamp < dayStart then stamp = dayStart + i end

        local didAdd = select(1, TaliaaGankRepository:RecordDHK(
            "Blizzard Today DHK #" .. tostring(have + i),
            {
                character = character,
                zone = GetZoneText() or "",
                timestamp = stamp,
                source = "blizzard-session-api",
            }
        ))

        if didAdd then added = added + 1 end
    end

    if added > 0 and not silent then
        local today, weekly, lifetime = GetDHKCounts()
        Print("DHK sync repaired " .. tostring(added)
            .. " missing DHK" .. (added == 1 and "" or "s")
            .. " for " .. tostring(character)
            .. ". Account totals: Today " .. tostring(today)
            .. " • Week " .. tostring(weekly)
            .. " • Life " .. tostring(lifetime))
    end

    return added
end

local function RecordDishonorableKill(message)
    if not IsDishonorableKillMessage(message) then return false end

    local now = DailyNow()
    local key = tostring(message or ""):lower():gsub("%s+", " ")

    GT._recentDHKMessages = GT._recentDHKMessages or {}
    local last = tonumber(GT._recentDHKMessages[key]) or 0
    if key ~= "" and math.abs(now - last) <= 2 then
        return false
    end
    if key ~= "" then GT._recentDHKMessages[key] = now end

    local recorded = false
    if TaliaaGankRepository and TaliaaGankRepository.RecordDHK then
        recorded = select(1, TaliaaGankRepository:RecordDHK(message, {
            character = SessionKey(),
            zone = GetZoneText() or "",
            timestamp = now,
            source = "combat-honor-message",
        })) and true or false
    end

    if recorded then
        local session = EnsureSessionStats()
        if session then
            session.dhkCount = (tonumber(session.dhkCount) or 0) + 1
            GT.sessionDHK = session.dhkCount
        else
            GT.sessionDHK = (tonumber(GT.sessionDHK) or 0) + 1
        end

        local today, weekly, lifetime = GetDHKCounts()
        Print("|cffff3030DHK +1|r  •  Today " .. tostring(today)
            .. "  •  Week " .. tostring(weekly)
            .. "  •  Life " .. tostring(lifetime))
        if InCombatLockdown and InCombatLockdown() then
            GT._displayRefreshPending = true
        else
            UpdateDisplay()
        end
    end

    -- The Blizzard stat can update a fraction of a second after the message.
    -- Reconcile shortly afterward so even a missed/filtered chat event is repaired.
    if C_Timer and C_Timer.After then
        C_Timer.After(5.0, function()
            local fixed = ReconcileCurrentCharacterDHKs(true)
            if fixed > 0 then UpdateDisplay() end
        end)
    end

    return recorded
end

local function SetStreak(value)
    local session = EnsureSessionStats()
    value = math.max(0, tonumber(value) or 0)
    GT.currentStreak = value

    if session then
        session.streak = value
        session.bestStreak = math.max(tonumber(session.bestStreak) or 0, value)
        GT.bestStreak = session.bestStreak
    else
        GT.bestStreak = math.max(tonumber(GT.bestStreak) or 0, value)
    end
end

local function RevengeCountAndNewest()
    local session = EnsureSessionStats()
    local targets = (session and session.revengeTargets) or GT.revengeTargets or {}
    local count = 0
    local newest = nil

    for _, target in pairs(targets) do
        if type(target) == "table" then
            count = count + 1
            if not newest or (tonumber(target.lastDeath) or 0) > (tonumber(newest.lastDeath) or 0) then
                newest = target
            end
        end
    end

    return count, newest
end

local function AddRevengeTarget(name, guid)
    if not name or name == "" then return end
    local session = EnsureSessionStats()
    if not session then return end

    session.revengeTargets = session.revengeTargets or {}
    local key
    if guid and tostring(guid):sub(1, 6) == "Player" then
        key = "G:" .. tostring(guid)
    else
        key = "N:" .. NormalizedPlayerName(name)
    end

    local target = session.revengeTargets[key] or {
        name = BasePlayerName(name),
        guid = guid,
        deaths = 0,
    }

    target.name = BasePlayerName(name)
    target.guid = guid or target.guid
    target.deaths = (tonumber(target.deaths) or 0) + 1
    target.lastDeath = DailyNow()

    session.revengeTargets[key] = target
    GT.revengeTargets = session.revengeTargets

    Print("|cffff5577REVENGE MARKED|r: " .. tostring(target.name) .. " killed you.")
end

local function ClaimRevenge(name, guid)
    local session = EnsureSessionStats()
    if not session or type(session.revengeTargets) ~= "table" then return false end

    local wantName = NormalizedPlayerName(name)
    local wantGUID = tostring(guid or "")
    local foundKey, found

    for key, target in pairs(session.revengeTargets) do
        if type(target) == "table" then
            local sameGUID = wantGUID ~= "" and tostring(target.guid or "") == wantGUID
            local sameName = NormalizedPlayerName(target.name) == wantName
            if sameGUID or sameName then
                foundKey, found = key, target
                break
            end
        end
    end

    if foundKey then
        session.revengeTargets[foundKey] = nil
        GT.revengeTargets = session.revengeTargets

        local extra = ""
        if (tonumber(found.deaths) or 1) > 1 then
            extra = " (" .. tostring(found.deaths) .. " deaths owed)"
        end
        Print("|cff66ff66REVENGE CLAIMED|r: " .. BasePlayerName(name) .. extra)
        return true
    end

    return false
end

local function FlushPendingRevengeClaims()
    if not GT._pendingRevengeClaims then return end
    for key, claim in pairs(GT._pendingRevengeClaims) do
        if type(claim) == "table" then
            ClaimRevenge(claim.name, claim.guid)
        end
        GT._pendingRevengeClaims[key] = nil
    end
end

local function FormatAge(timestamp)
    timestamp = tonumber(timestamp) or 0
    if timestamp <= 0 then return nil end

    local age = math.max(0, DailyNow() - timestamp)
    if age < 60 then return tostring(age) .. "s" end
    if age < 3600 then return tostring(math.floor(age / 60)) .. "m" end
    if age < 86400 then return tostring(math.floor(age / 3600)) .. "h" end
    return tostring(math.floor(age / 86400)) .. "d"
end


local function PrintTodayStats()
    RefreshDailyStats()
    local total = tonumber(GT.totalKills) or 0
    local unique = tonumber(GT.uniqueKills) or 0
    local repeats = math.max(0, total - unique)
    local dhkToday = select(1, GetDHKCounts()) or 0

    Print(
        "TODAY " .. tostring(total) .. " kills"
        .. " • Unique " .. tostring(unique)
        .. " • Repeat " .. tostring(repeats)
        .. " • DHK " .. tostring(tonumber(dhkToday) or 0)
    )
end

local function PrintWeeklyStats()
    local stats, ok = BuildWeeklyStats()
    if not ok then
        Print("WEEK report unavailable: repository history not loaded.")
        return
    end

    local dhkWeekly = select(2, GetDHKCounts()) or 0
    Print(
        "WEEK " .. tostring(tonumber(stats.total) or 0) .. " kills"
        .. " • Unique " .. tostring(tonumber(stats.unique) or 0)
        .. " • Repeat " .. tostring(tonumber(stats.repeats) or 0)
        .. " • DHK " .. tostring(tonumber(dhkWeekly) or 0)
    )
end

local function PrintTodayAndWeeklyStats()
    PrintTodayStats()
    PrintWeeklyStats()
end

local function CleanChatMessage(message)
    if not message then return nil end
    -- Blizzard chat rejects WoW escape sequences/control characters.
    message = tostring(message)
    message = message:gsub("|", "")
    message = message:gsub("[%c]", " ")
    message = message:gsub("%s+", " ")
    return message
end

local function SafeGroupMessage(message)
    message = CleanChatMessage(message)
    if not message then return false end

    if IsInRaid() then
        SendChatMessage(message, "RAID")
        return true
    elseif IsInGroup() then
        SendChatMessage(message, "PARTY")
        return true
    else
        Print("Not in a group. " .. message)
        return false
    end
end

local function EnsureReportSettings()
    GT.reportSettings = GT.reportSettings or {}

    if VoidMarkDB then
        VoidMarkDB.TaliaaGankReportSettings = VoidMarkDB.TaliaaGankReportSettings or {}
        local persistent = VoidMarkDB.TaliaaGankReportSettings
        -- Preserve any temporary values created before VoidMarkDB was ready.
        for key, value in pairs(GT.reportSettings) do
            if persistent[key] == nil then persistent[key] = value end
        end
        GT.reportSettings = persistent
    end

    local settings = GT.reportSettings

    -- Report content.
    if settings.daily == nil then settings.daily = true end
    if settings.weekly == nil then settings.weekly = false end
    if settings.records == nil then settings.records = false end

    -- Report detail:
    --   summary = totals/unique/repeats/60s/noobs
    --   levels  = summary plus the same level-range breakdown shown in the tracker
    settings.reportStyle = tostring(settings.reportStyle or "summary")
    if settings.reportStyle ~= "summary" and settings.reportStyle ~= "levels" then
        settings.reportStyle = "summary"
    end

    -- Destination migration from the older "group" setting.
    if settings.party == nil then
        if settings.group ~= nil then
            settings.party = settings.group and true or false
        else
            settings.party = true
        end
    end
    if settings.guild == nil then settings.guild = false end
    if settings.whisper == nil then settings.whisper = false end
    if settings.say == nil then settings.say = false end

    settings.whisperTarget = tostring(settings.whisperTarget or "")
    return settings
end

local function NormalizeWhisperTarget(raw)
    local target = tostring(raw or "")
    target = target:gsub("–", "-"):gsub("—", "-")
    target = target:match("^%s*(.-)%s*$") or ""
    if target == "" then return "" end

    -- Cross-realm whispers require Name-Realm. Accept friendly input such as
    -- "Name - Realm Name" and normalize the realm portion the same way WoW does.
    local name, realm = target:match("^([^%-]+)%s*%-%s*(.+)$")
    if name and realm then
        name = name:match("^%s*(.-)%s*$") or name
        realm = realm:match("^%s*(.-)%s*$") or realm
        realm = realm:gsub("%s+", "")
        if name ~= "" and realm ~= "" then
            return name .. "-" .. realm
        end
    end

    return target
end

local function SendReportMessage(message)
    message = CleanChatMessage(message)
    if not message then return 0 end

    local settings = EnsureReportSettings()
    local selected = 0
    local sent = 0

    if settings.party then
        selected = selected + 1
        if IsInRaid and IsInRaid() then
            SendChatMessage(message, "RAID")
            sent = sent + 1
        elseif IsInGroup and IsInGroup() then
            SendChatMessage(message, "PARTY")
            sent = sent + 1
        else
            Print("Report: not in a party/raid.")
        end
    end

    if settings.guild then
        selected = selected + 1
        if IsInGuild and IsInGuild() then
            SendChatMessage(message, "GUILD")
            sent = sent + 1
        else
            Print("Report: not in a guild.")
        end
    end

    if settings.whisper then
        selected = selected + 1
        local target = NormalizeWhisperTarget(settings.whisperTarget)
        if target ~= "" then
            -- Save the normalized form so future reports use the exact cross-realm target.
            settings.whisperTarget = target
            if GT.ReportWhisperEdit and not GT.ReportWhisperEdit:HasFocus() then
                GT.ReportWhisperEdit:SetText(target)
            end
            SendChatMessage(message, "WHISPER", nil, target)
            sent = sent + 1
        else
            Print("Report: whisper is enabled but no target is set in OPT.")
        end
    end

    if settings.say then
        selected = selected + 1
        SendChatMessage(message, "SAY")
        sent = sent + 1
    end

    if selected == 0 then
        Print("No report destination selected. " .. message)
    end

    return sent
end

local function GetHuntViewMode()
    local mode = (VoidMarkDB and VoidMarkDB.TaliaaGankTrackerViewMode) or GT.huntViewMode or "today"
    if mode ~= "weekly" and mode ~= "records" then mode = "today" end
    GT.huntViewMode = mode
    return mode
end

function GT:RefreshVoidMarkCompact()
    local main = VoidMark and VoidMark.MainWindow
    if not main then return end

    local left = main.VoidMarkGTCompactTextLeft or main.VoidMarkGTCompactText
    local right = main.VoidMarkGTCompactTextRight
    if not left and not right then return end

    local kills = tonumber(GT.totalKills) or 0
    local unique = tonumber(GT.uniqueKills) or 0
    local repeats = math.max(0, kills - unique)
    local dhkToday = 0
    if GetDHKCounts then
        dhkToday = tonumber((select(1, GetDHKCounts()))) or 0
    end
    local streak = tonumber(GT.currentStreak) or 0

    local leftText = "K " .. tostring(kills)
        .. "   U " .. tostring(unique)
        .. "   R " .. tostring(repeats)
    local rightText = "DK " .. tostring(dhkToday)
        .. "   K/S " .. tostring(streak)

    if left then
        left:SetText(leftText)
    end
    if right then
        right:SetText(rightText)
    elseif left then
        left:SetText(leftText .. "   " .. rightText)
    end
end

local RestorePanicVisibility

UpdateDisplay = function()
    -- Nothing in the full tracker repaint is combat-critical. Weekly/repository
    -- totals can touch thousands of rows when their cache invalidates, so any
    -- accidental combat-time caller is collapsed into one repaint at combat end.
    if InCombatLockdown and InCombatLockdown() then
        GT._displayRefreshPending = true
        if GT.PanicFrame and GT.PanicFrame:IsShown() and UpdatePanicDisplay then
            UpdatePanicDisplay()
        end
        return
    end

    GT._displayRefreshPending = nil
    if GT._dailyDateKey ~= DailyDateKey() then
        RefreshDailyStats()
    end
    if not GT.Frame then return end

    local duplicates = math.max(0, (GT.totalKills or 0) - (GT.uniqueKills or 0))
    local recentThreats = GT:GetRecentEnemyCount(PANIC_WINDOW_SECONDS)
    local huntView = GetHuntViewMode()
    local weeklyViewStats = nil
    local recordViewStats = nil

    if huntView == "records" then
        recordViewStats = select(1, BuildRecordStats())
        local total = recordViewStats and (tonumber(recordViewStats.total) or 0) or 0
        local marks = recordViewStats and (tonumber(recordViewStats.marks) or 0) or 0
        local repeats = math.max(0, total - marks)
        local bestWeek = recordViewStats and (tonumber(recordViewStats.bestWeek) or 0) or 0

        if GT.Frame.TotalValue then
            GT.Frame.TotalValue:SetText(tostring(total))
            if GT.Frame.TotalValue.Caption then GT.Frame.TotalValue.Caption:SetText("KILLS") end
        end
        if GT.Frame.UniqueValue then
            GT.Frame.UniqueValue:SetText(tostring(marks))
            if GT.Frame.UniqueValue.Caption then GT.Frame.UniqueValue.Caption:SetText("MARKS") end
        end
        if GT.Frame.DupeValue then
            GT.Frame.DupeValue:SetText(tostring(repeats))
            if GT.Frame.DupeValue.Caption then GT.Frame.DupeValue.Caption:SetText("REPEATS") end
        end
        if GT.Frame.NearbyValue then
            GT.Frame.NearbyValue:SetText(tostring(bestWeek))
            if GT.Frame.NearbyValue.Caption then GT.Frame.NearbyValue.Caption:SetText("BEST WK") end
        end
    elseif huntView == "weekly" then
        weeklyViewStats = BuildWeeklyStats()
        if GT.Frame.TotalValue then
            GT.Frame.TotalValue:SetText(tostring((weeklyViewStats and weeklyViewStats.total) or 0))
            if GT.Frame.TotalValue.Caption then GT.Frame.TotalValue.Caption:SetText("KILLS") end
        end
        if GT.Frame.UniqueValue then
            GT.Frame.UniqueValue:SetText(tostring((weeklyViewStats and weeklyViewStats.unique) or 0))
            if GT.Frame.UniqueValue.Caption then GT.Frame.UniqueValue.Caption:SetText("UNIQUE") end
        end
        if GT.Frame.DupeValue then
            GT.Frame.DupeValue:SetText(tostring((weeklyViewStats and weeklyViewStats.repeats) or 0))
            if GT.Frame.DupeValue.Caption then GT.Frame.DupeValue.Caption:SetText("REPEATS") end
        end
        if GT.Frame.NearbyValue then
            GT.Frame.NearbyValue:SetText(tostring((weeklyViewStats and weeklyViewStats.level60) or 0))
            if GT.Frame.NearbyValue.Caption then GT.Frame.NearbyValue.Caption:SetText("60s") end
        end
    else
        if GT.Frame.TotalValue then
            GT.Frame.TotalValue:SetText(tostring(GT.totalKills or 0))
            if GT.Frame.TotalValue.Caption then GT.Frame.TotalValue.Caption:SetText("KILLS") end
        end
        if GT.Frame.UniqueValue then
            GT.Frame.UniqueValue:SetText(tostring(GT.uniqueKills or 0))
            if GT.Frame.UniqueValue.Caption then GT.Frame.UniqueValue.Caption:SetText("UNIQUE") end
        end
        if GT.Frame.DupeValue then
            GT.Frame.DupeValue:SetText(tostring(duplicates))
            if GT.Frame.DupeValue.Caption then GT.Frame.DupeValue.Caption:SetText("REPEATS") end
        end
        if GT.Frame.NearbyValue then
            GT.Frame.NearbyValue:SetText(tostring(recentThreats))
            if GT.Frame.NearbyValue.Caption then GT.Frame.NearbyValue.Caption:SetText("THR/30") end
        end
    end

    -- Hunter-pet kills are kept as a separate lifetime counter and never affect
    -- player-kill totals, marks, repeats, streaks, or level buckets.
    if GT.Frame.PetValue then
        local petCount = HunterPetKillToday()
        if huntView == "weekly" then
            petCount = HunterPetKillWeekly()
        elseif huntView == "records" then
            petCount = HunterPetKillTotal()
        end
        GT.Frame.PetValue:SetText(tostring(petCount))
        if GT.Frame.PetValue.Caption then GT.Frame.PetValue.Caption:SetText("PETS") end
    end

    if GT.Frame.Subtitle then
        if huntView == "records" then
            GT.Frame.Subtitle:SetText("CAREER RECORDS")
        elseif huntView == "weekly" then
            local label = "WEEKLY HUNT"
            if weeklyViewStats and weeklyViewStats.incomplete then
                label = "WEEKLY HUNT  •  HISTORY INCOMPLETE"
            end
            GT.Frame.Subtitle:SetText(label)
        else
            GT.Frame.Subtitle:SetText("TODAY'S HUNT")
        end
    end

    if huntView == "records" and recordViewStats then
        if lastLabel then
            lastLabel:SetText("PERSONAL RECORD")
        end
        if GT.Frame.LastName then
            GT.Frame.LastName:SetText("BEST WEEK  •  " .. tostring(recordViewStats.bestWeek or 0) .. " KILLS")
            GT.Frame.LastName:SetTextColor(0.86, 0.58, 1.00, 1)
        end
        if GT.Frame.LastMeta then
            GT.Frame.LastMeta:SetText(
                ShortDate(recordViewStats.bestWeekStart)
                .. " – " .. ShortDate((recordViewStats.bestWeekEnd or 0) - 1)
                .. "  •  Current " .. tostring(recordViewStats.currentWeek or 0)
            )
        end
        if GT.Frame.LastLocation then
            GT.Frame.LastLocation:SetText(
                "Lifetime " .. tostring(recordViewStats.total or 0)
                .. " kills  •  " .. tostring(recordViewStats.marks or 0) .. " marks"
                .. "  •  Hunter pets " .. tostring(HunterPetKillTotal())
            )
        end
    elseif GT.lastKillName then
        if lastLabel then lastLabel:SetText("LAST MARK") end
        local lastData = FindPlayerDataForName(GT.lastKillName)
        local class = lastData and lastData.class or nil
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if GT.Frame.LastName then
            GT.Frame.LastName:SetText(BasePlayerName(GT.lastKillName))
            if color then
                GT.Frame.LastName:SetTextColor(color.r, color.g, color.b, 1)
            else
                GT.Frame.LastName:SetTextColor(0.96, 0.72, 1.00, 1)
            end
        end
        if GT.Frame.LastMeta then
            local victimKills = GetVictimKillCount and GetVictimKillCount(GT.lastKillName) or 0
            GT.Frame.LastMeta:SetText(
                "L" .. tostring(GT.lastKillLevel or "?")
                .. "  •  Today " .. tostring(victimKills) .. "x"
                .. "  •  Life " .. tostring(GT.lastKillHistorical or 0) .. "x"
            )
        end
        if GT.Frame.LastLocation then
            GT.Frame.LastLocation:SetText(tostring(GT.lastKillLocation or "Unknown"))
        end
    else
        if lastLabel then lastLabel:SetText("LAST MARK") end
        if GT.Frame.LastName then
            GT.Frame.LastName:SetText("No kills today")
            GT.Frame.LastName:SetTextColor(0.65, 0.60, 0.70, 1)
        end
        if GT.Frame.LastMeta then GT.Frame.LastMeta:SetText("Waiting for a mark...") end
        if GT.Frame.LastLocation then GT.Frame.LastLocation:SetText("") end
    end

    if GT.Frame.PartyButton and GT.Frame.PartyButton.Label then
        GT.Frame.PartyButton.Label:SetText(GT.partyAnnounce and "PARTY ON" or "PARTY OFF")
        if GT.partyAnnounce then
            GT.Frame.PartyButton:SetBackdropColor(0.16, 0.06, 0.24, 1)
            GT.Frame.PartyButton:SetBackdropBorderColor(0.76, 0.42, 1.00, 1)
        else
            GT.Frame.PartyButton:SetBackdropColor(0.035, 0.025, 0.055, 1)
            GT.Frame.PartyButton:SetBackdropBorderColor(0.30, 0.14, 0.42, 1)
        end
    end

    RefreshSessionDHK()
    local dhkToday, dhkWeekly, dhkLifetime = GetDHKCounts()

    if GT.Frame.RepoText then
        if TaliaaGankRepository and TaliaaGankRepository.GetStats then
            local total = select(1, TaliaaGankRepository:GetStats()) or 0
            local weeklyStats = BuildWeeklyStats()
            local weeklyTotal = weeklyStats and (tonumber(weeklyStats.total) or 0) or 0
            local weekLabel = tostring(weeklyTotal)
            if weeklyStats and weeklyStats.incomplete then
                weekLabel = weekLabel .. "!"
            end
            GT.Frame.RepoText:SetText(
                "LIFE " .. tostring(total)
                .. "  •  WEEK " .. weekLabel
                .. "  •  SESSION " .. tostring(GT.sessionKills or 0)
            )
            if GT.Frame.CombatText then
                local todayKills = tonumber(GT.totalKills) or 0
                local todayDeaths = PlayerDeathsToday()
                local weekKills = tonumber(weeklyTotal) or 0
                local weekDeaths = PlayerDeathsWeekly()
                GT.Frame.CombatText:SetText(
                    "K/D TODAY " .. tostring(todayKills) .. "-" .. tostring(todayDeaths)
                    .. " (" .. KDRatioText(todayKills, todayDeaths) .. ")"
                    .. "  •  WEEK " .. tostring(weekKills) .. "-" .. tostring(weekDeaths)
                    .. " (" .. KDRatioText(weekKills, weekDeaths) .. ")"
                )
            end
        else
            GT.Frame.RepoText:SetText("LIFE repository offline")
            if GT.Frame.CombatText then
                local todayKills = tonumber(GT.totalKills) or 0
                local todayDeaths = PlayerDeathsToday()
                GT.Frame.CombatText:SetText(
                    "K/D TODAY " .. tostring(todayKills) .. "-" .. tostring(todayDeaths)
                    .. " (" .. KDRatioText(todayKills, todayDeaths) .. ")"
                )
            end
        end
    end

    if GT.Frame.RevengeText then
        local revengeCount, newest = RevengeCountAndNewest()
        if revengeCount > 0 and newest then
            GT.Frame.RevengeText:SetText("REVENGE " .. tostring(revengeCount) .. "  •  " .. tostring(newest.name or "?"))
            GT.Frame.RevengeText:SetTextColor(1.00, 0.32, 0.45, 1)
        else
            GT.Frame.RevengeText:SetText("REVENGE none")
            GT.Frame.RevengeText:SetTextColor(0.50, 0.44, 0.56, 1)
        end
    end

    if GT.Frame.SyncText then
        GT.Frame.SyncText:SetText("")
        GT.Frame.SyncText:Hide()
    end

    if GT.Frame.CompactText then
        local compactTotal, compactUnique, compactRepeats
        if huntView == "records" and recordViewStats then
            GT.Frame.CompactText:SetText(
                "LIFE " .. tostring(recordViewStats.total or 0)
                .. "   BEST " .. tostring(recordViewStats.bestWeek or 0)
            )
            compactTotal = nil
        elseif huntView == "weekly" and weeklyViewStats then
            compactTotal = tonumber(weeklyViewStats.total) or 0
            compactUnique = tonumber(weeklyViewStats.unique) or 0
            compactRepeats = tonumber(weeklyViewStats.repeats) or 0
        else
            compactTotal = tonumber(GT.totalKills) or 0
            compactUnique = tonumber(GT.uniqueKills) or 0
            compactRepeats = math.max(0, compactTotal - compactUnique)
        end
        if compactTotal ~= nil then
            GT.Frame.CompactText:SetText(
                "K " .. tostring(compactTotal)
                .. "   U " .. tostring(compactUnique)
                .. "   R " .. tostring(compactRepeats)
            )
        end
    end

    if GT.Frame.LevelBucketValues then
        local sourceBuckets = GT.levelKillBuckets or {}
        if huntView == "weekly" and weeklyViewStats and weeklyViewStats.levelBuckets then
            sourceBuckets = weeklyViewStats.levelBuckets
        end

        -- UpdateDisplay is defined before the local frame variable is created.
        -- Always use GT.Frame here; referencing "frame" can be nil when history
        -- refreshes asynchronously from the repository.
        local showBuckets = huntView ~= "records"
            and GT.Frame
            and GT.Frame.GetHeight
            and GT.Frame:GetHeight() > 40
        for _, key in ipairs(LEVEL_BUCKET_ORDER) do
            local fs = GT.Frame.LevelBucketValues[key]
            if fs then
                fs:SetText(tostring(sourceBuckets[key] or 0))
                if fs.Holder then
                    if showBuckets then fs.Holder:Show() else fs.Holder:Hide() end
                end
            end
        end
    end

    if GT.Frame.TodayViewButton and GT.Frame.WeeklyViewButton and GT.Frame.RecordsViewButton then
        local buttons = {
            {GT.Frame.TodayViewButton, huntView == "today"},
            {GT.Frame.WeeklyViewButton, huntView == "weekly"},
            {GT.Frame.RecordsViewButton, huntView == "records"},
        }
        for _, item in ipairs(buttons) do
            local button, active = item[1], item[2]
            button:SetBackdropColor(active and 0.16 or 0.035, active and 0.06 or 0.025, active and 0.24 or 0.055, 1)
            button:SetBackdropBorderColor(active and 0.76 or 0.30, active and 0.42 or 0.14, active and 1.00 or 0.42, 1)
        end
    end

    GT:RefreshVoidMarkCompact()

    RestorePanicVisibility()
    if UpdatePanicDisplay and GT.PanicFrame and GT.PanicFrame:IsShown() then
        UpdatePanicDisplay(recentThreats)
    end
end

-- Defined after UpdateDisplay on purpose. This avoids the Lua local
-- forward-reference bug that caused the WEEK/TODAY buttons to call nil.
local function SetHuntViewMode(mode)
    if mode ~= "weekly" and mode ~= "records" then mode = "today" end
    GT.huntViewMode = mode
    if VoidMarkDB then VoidMarkDB.TaliaaGankTrackerViewMode = mode end
    UpdateDisplay()
end

local function CurrentLocation()
    local zone = GetZoneText() or "Unknown"
    local subZone = GetSubZoneText() or ""

    if subZone ~= "" and subZone ~= zone then
        return zone .. " - " .. subZone
    end

    return zone
end

UpdatePanicDisplay = function(forcedCount)
    if GT.RefreshPanicArt then
        GT:RefreshPanicArt(false, forcedCount)
        return
    end

    local pf = GT.PanicFrame
    local button = pf and pf.Button
    local label = button and button.Label
    if not label then return end

    local count = forcedCount
    if count == nil then
        count = GT:GetRecentEnemyCount(PANIC_WINDOW_SECONDS)
    end
    count = tonumber(count) or 0

    local style = "banner"
    style = "banner"
    if style == "banner" then
        label:SetText("PANIC   " .. tostring(count) .. " THREAT" .. (count == 1 and "" or "S"))
    elseif style == "ring" then
        label:SetText("PANIC  " .. tostring(count))
    else
        label:SetText("PANIC\n" .. tostring(count))
    end

    local br, bg, bb, lr, lg, lb, ar, ag, ab
    if count >= 6 then
        br,bg,bb = 1.00,0.16,0.12
        lr,lg,lb = 1.00,0.94,0.92
        ar,ag,ab = 1.00,0.12,0.08
        button:SetBackdropColor(0.58, 0.010, 0.025, 0.99)
    elseif count >= 3 then
        br,bg,bb = 0.95,0.12,0.18
        lr,lg,lb = 1.00,0.82,0.82
        ar,ag,ab = 0.95,0.10,0.18
        button:SetBackdropColor(0.46, 0.020, 0.045, 0.99)
    elseif count >= 1 then
        br,bg,bb = 0.78,0.16,0.32
        lr,lg,lb = 1.00,0.58,0.68
        ar,ag,ab = 0.78,0.16,0.32
        button:SetBackdropColor(0.28, 0.025, 0.070, 0.98)
    else
        br,bg,bb = 0.48,0.20,0.68
        lr,lg,lb = 0.82,0.60,0.96
        ar,ag,ab = 0.56,0.20,0.82
        button:SetBackdropColor(0.075, 0.025, 0.11, 0.97)
    end

    button:SetBackdropBorderColor(br,bg,bb,1)
    label:SetTextColor(lr,lg,lb,1)
    if button.Accent then button.Accent:SetVertexColor(ar,ag,ab,1) end
    if button.StyleDiamond then button.StyleDiamond:SetVertexColor(ar*0.34,ag*0.34,ab*0.34,0.96) end
    if button.StyleRing then button.StyleRing:SetVertexColor(br,bg,bb,1) end
    if button.StyleRingGlow then button.StyleRingGlow:SetVertexColor(ar,ag,ab,1) end
    if button.BannerLeft then button.BannerLeft:SetVertexColor(ar*0.55,ag*0.55,ab*0.55,1) end
    if button.BannerRight then button.BannerRight:SetVertexColor(ar*0.55,ag*0.55,ab*0.55,1) end
    if button.VoidGlow then button.VoidGlow:SetVertexColor(ar,ag,ab,1) end
end
function GT:NoteEnemySeen(playerName, timestamp, source)
    if not playerName or playerName == "" then
        return
    end

    -- Only count enemies detected by this client.
    -- Ignore detections received from another VoidMark user. Some local detection
    -- paths omit a source entirely, so nil remains a valid local observation.
    if source and VoidMark and VoidMark.CharacterName and source ~= VoidMark.CharacterName then
        return
    end

    local seenData = FindPlayerDataForName(playerName)
    local level = seenData and tonumber(seenData.level) or nil

    self.seenEnemies[playerName] = {
        seenAt = timestamp or time(),
        level = level,
    }
    if UpdatePanicDisplay then UpdatePanicDisplay() end
end

function GT:GetPanicThreats(seconds)
    local window = tonumber(seconds) or PANIC_WINDOW_SECONDS
    local cutoff = time() - window
    local playerLevel = PanicPlayerLevel()
    local minimumRelevantLevel = math.max(1, playerLevel - PANIC_LEVEL_MARGIN)
    local threats = {}

    for playerName, data in pairs(self.seenEnemies or {}) do
        local seenAt
        local level

        if type(data) == "table" then
            seenAt = tonumber(data.seenAt)
            level = tonumber(data.level)

            if not level then
                local seenData = FindPlayerDataForName(playerName)
                level = seenData and tonumber(seenData.level) or nil
                data.level = level
            end
        else
            seenAt = tonumber(data)
            local seenData = FindPlayerDataForName(playerName)
            level = seenData and tonumber(seenData.level) or nil
        end

        if seenAt and seenAt >= cutoff then
            -- Classic reports a player 10+ levels above you as a skull/??.
            -- Some detection paths expose no level at all. Keep those as an
            -- explicit unknown (?) rather than falsely labeling them skull/??.
            local skull = level ~= nil and level < 0
            local unknown = level == nil or level == 0
            if skull or unknown or level >= minimumRelevantLevel then
                threats[#threats + 1] = {
                    name = playerName,
                    level = (skull or unknown) and nil or level,
                    skull = skull,
                    unknown = unknown,
                }
            end
        else
            self.seenEnemies[playerName] = nil
        end
    end

    table.sort(threats, function(a, b)
        if a.skull ~= b.skull then return a.skull end
        if a.skull then return tostring(a.name or "") < tostring(b.name or "") end
        if a.unknown ~= b.unknown then return not a.unknown end
        local aLevel = tonumber(a.level) or 0
        local bLevel = tonumber(b.level) or 0
        if aLevel ~= bLevel then return aLevel > bLevel end
        return tostring(a.name or "") < tostring(b.name or "")
    end)

    return threats
end

function GT:GetRecentEnemyCount(seconds)
    return #self:GetPanicThreats(seconds)
end

local function FormatLevelBreakdownLines(buckets, unknown)
    buckets = buckets or {}

    local low = (tonumber(buckets["1-9"]) or 0)
        + (tonumber(buckets["10-20"]) or 0)
        + (tonumber(buckets["21-30"]) or 0)
    local mid = (tonumber(buckets["31-40"]) or 0)
        + (tonumber(buckets["41-50"]) or 0)
        + (tonumber(buckets["51-59"]) or 0)
    local maxLevel = tonumber(buckets["60"]) or 0

    local line = string.format(
        "LVL [1-30] {star}%d  •  [31-59] {star}%d  •  [60] {skull}%d{skull}",
        low, mid, maxLevel
    )

    unknown = tonumber(unknown) or 0
    if unknown > 0 then
        line = line .. "  •  Unknown " .. tostring(unknown)
    end

    return { line }
end

local function BuildRecordReportLines()
    local stats, ok = BuildRecordStats()
    if not ok then return nil end

    return {
        "VOIDMARK RECORDS — " .. tostring(stats.total or 0) .. " lifetime kills"
            .. "  •  " .. tostring(stats.marks or 0) .. " unique marks"
            .. "  •  Hunter pets " .. tostring(HunterPetKillTotal()),
        "BEST WEEK — " .. tostring(stats.bestWeek or 0) .. " kills"
            .. "  •  " .. ShortDate(stats.bestWeekStart)
            .. " – " .. ShortDate((stats.bestWeekEnd or 0) - 1)
            .. "  •  Current " .. tostring(stats.currentWeek or 0),
    }
end

local function BuildDailyReportLines()
    RefreshDailyStats()
    local total = tonumber(GT.totalKills) or 0
    local unique = tonumber(GT.uniqueKills) or 0
    local repeats = math.max(0, total - unique)
    local unknown = tonumber(GT.dailyUnknownLevelKills) or 0
    local dhkToday = select(1, GetDHKCounts()) or 0

    local lines = {
        string.format(
            "TODAY {star}%d kills  •  Unique %d  •  Repeat %d  •  DHK %d  •  Hunter pets %d",
            total, unique, repeats, tonumber(dhkToday) or 0, HunterPetKillToday()
        ),
    }

    lines[#lines + 1] = "KILL STREAK " .. tostring(GT.currentStreak or 0)
        .. "  •  Best this session " .. tostring(GT.bestStreak or 0)

    local settings = EnsureReportSettings()
    if settings.reportStyle == "levels" then
        local levelLines = FormatLevelBreakdownLines(GT.levelKillBuckets, unknown)
        for _, levelLine in ipairs(levelLines) do
            lines[#lines + 1] = levelLine
        end
    end

    return lines
end

local function BuildWeeklyReportLines()
    local stats, ok = BuildWeeklyStats()
    if not ok then
        return { "WEEK report unavailable: repository history not loaded." }
    end

    local dhkWeekly = select(2, GetDHKCounts()) or 0
    local lines = {
        string.format(
            "WEEK {star}%d kills  •  Unique %d  •  Repeat %d  •  DHK %d  •  Hunter pets %d",
            tonumber(stats.total) or 0,
            tonumber(stats.unique) or 0,
            tonumber(stats.repeats) or 0,
            tonumber(dhkWeekly) or 0,
            HunterPetKillWeekly()
        ),
    }

    local settings = EnsureReportSettings()
    if settings.reportStyle == "levels" then
        local levelLines = FormatLevelBreakdownLines(stats.levelBuckets, stats.unknown)
        for _, levelLine in ipairs(levelLines) do
            lines[#lines + 1] = levelLine
        end
    end

    return lines
end

local function QueueReportLines(lines, startingDelay)
    if type(lines) ~= "table" then return 0 end

    local delay = tonumber(startingDelay) or 0
    local queued = 0

    for _, line in ipairs(lines) do
        local message = tostring(line or "")
        if message ~= "" then
            local thisDelay = delay
            C_Timer.After(thisDelay, function()
                SendReportMessage(message)
            end)
            delay = delay + 0.35
            queued = queued + 1
        end
    end

    return queued, delay
end

function GT:ReportToParty()
    local settings = EnsureReportSettings()
    local groups = {}

    if settings.daily then
        groups[#groups + 1] = BuildDailyReportLines()
    end

    if settings.weekly then
        local weekly = BuildWeeklyReportLines()
        if weekly then
            groups[#groups + 1] = weekly
        else
            Print("Weekly report unavailable: repository history is not loaded.")
        end
    end

    if settings.records then
        local records = BuildRecordReportLines()
        if records then
            groups[#groups + 1] = records
        else
            Print("Records report unavailable: repository history is not loaded.")
        end
    end

    if #groups == 0 then
        Print("No report content selected. Open OPT and choose Daily and/or Weekly.")
        return
    end

    local delay = 0
    local lineCount = 0
    for _, lines in ipairs(groups) do
        local queued, nextDelay = QueueReportLines(lines, delay)
        lineCount = lineCount + (queued or 0)
        delay = (nextDelay or delay) + 0.20
    end

    if lineCount > 0 then
        Print("Report queued: " .. tostring(lineCount) .. " readable line" .. (lineCount == 1 and "." or "s."))
    end
end

-- The main REPORT button follows the hunt selector directly:
-- TODAY reports Today's Hunt; WEEK reports Weekly Hunt.
function GT:ReportCurrentHunt()
    local mode = GetHuntViewMode()
    local lines

    if mode == "records" then
        lines = BuildRecordReportLines()
        if not lines then
            Print("Records report unavailable: repository history is not loaded.")
            return
        end
    elseif mode == "weekly" then
        local stats = BuildWeeklyStats()
        if stats and stats.incomplete then
            Print("Weekly repository is incomplete on this client: loaded "
                .. tostring(stats.repositoryTotal or 0)
                .. " of " .. tostring(stats.fileMerged or 0)
                .. " events from the last offline merge. Recover/merge history before reporting weekly.")
            return
        end

        lines = BuildWeeklyReportLines()
        if not lines then
            Print("Weekly report unavailable: repository history is not loaded.")
            return
        end
    else
        lines = BuildDailyReportLines()
    end

    local count = QueueReportLines(lines, 0)
    if (tonumber(count) or 0) > 0 then
        local reportName = mode == "weekly" and "Weekly"
            or mode == "records" and "Records"
            or "Today's"
        Print(reportName
            .. " report queued: " .. tostring(count)
            .. " readable line" .. (count == 1 and "." or "s."))
    end
end

local function PanicLocation()
    local subZone = GetSubZoneText and (GetSubZoneText() or "") or ""
    if subZone ~= "" then return subZone end
    local zone = GetZoneText and (GetZoneText() or "") or ""
    if zone ~= "" then return zone end
    return "Unknown"
end

local function PanicCoordinates()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
        return "??,??"
    end

    local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or not mapID then return "??,??" end

    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not okPos or not pos or not pos.GetXY then return "??,??" end

    local okXY, x, y = pcall(pos.GetXY, pos)
    if not okXY or not x or not y or (x == 0 and y == 0) then
        return "??,??"
    end

    return string.format("%02d,%02d", math.floor((x * 100) + 0.5), math.floor((y * 100) + 0.5))
end

local function PanicThreatLevelList(threats)
    local levels = {}
    for _, threat in ipairs(threats or {}) do
        if threat.skull then
            levels[#levels + 1] = "??"
        elseif threat.unknown then
            levels[#levels + 1] = "?"
        else
            levels[#levels + 1] = tostring(tonumber(threat.level) or "?")
        end
    end
    return table.concat(levels, ", ")
end

function GT:Panic()
    local threats = self:GetPanicThreats(PANIC_WINDOW_SECONDS)
    local location = PanicLocation()
    local coords = PanicCoordinates()
    local count = #threats
    local message

    if count > 0 then
        message = string.format(
            "PANIC {skull} %d THREAT%s [%s] {skull} %s (%s)",
            count,
            count == 1 and "" or "S",
            PanicThreatLevelList(threats),
            location,
            coords
        )
    else
        message = string.format("PANIC {skull} NEED HELP {skull} %s (%s)", location, coords)
    end

    SafeGroupMessage(message)
end

GetVictimKillCount = function(playerName)
    local v = GT.victims and GT.victims[playerName]
    if type(v) == "table" then
        return tonumber(v.kills) or 0
    elseif type(v) == "number" then
        return v
    end

    -- Recovery-only alias lookup for accented/special-character spellings. Use
    -- it only when exactly one displayed victim matches the canonical name.
    local want = NormalizedPlayerName(playerName)
    local found, matches = 0, 0
    for name, victim in pairs(GT.victims or {}) do
        if NormalizedPlayerName(name) == want then
            matches = matches + 1
            if type(victim) == "table" then
                found = tonumber(victim.kills) or 0
            elseif type(victim) == "number" then
                found = victim
            end
        end
    end
    if matches == 1 then return found end
    return 0
end

local function GetPlayerDetails(playerName, playerGUID)
    local data = FindPlayerDataForName(playerName)
    local level = ResolveKnownLevel(playerName, playerGUID, data and data.level or nil) or "?"
    local class = data and data.class or nil
    return level, class
end


local function SameVictimIdentity(eventName, eventGUID, playerName, playerGUID)
    local haveGUID = tostring(eventGUID or "")
    local wantGUID = tostring(playerGUID or "")

    -- If both sides have a real player GUID, the GUID is authoritative.
    -- Do not merge two different players just because the visible name matches.
    if haveGUID:sub(1, 6) == "Player" and wantGUID:sub(1, 6) == "Player" then
        return haveGUID == wantGUID
    end

    -- Older/recovered rows sometimes have no GUID. In that case, fall back to
    -- the normalized player name so those kills still count.
    return NormalizedPlayerName(eventName) == NormalizedPlayerName(playerName)
end

local function CountHistoricalVictimKillsFromHistory(playerName, playerGUID)
    local history = DailyHistory()
    if not history or type(history.events) ~= "table" then
        return 0
    end

    local count = 0
    for _, event in pairs(history.events) do
        if type(event) == "table"
            and SameVictimIdentity(event.name, event.guid, playerName, playerGUID) then
            count = count + 1
        end
    end
    return count
end

local function GetTodayVictimKillCount(playerName, playerGUID)
    local history = DailyHistory()
    if not history then
        return GetVictimKillCount(playerName)
    end

    local now = DailyNow()
    local dayStart = DailyRealmDayStart(now)
    local victim = nil
    local guid = tostring(playerGUID or "")

    -- Repository victim.events is the deduped canonical per-victim event index.
    -- Do not count raw history.events here: older/synced duplicate rows can remain
    -- in that ledger temporarily even though victim.kills correctly represents one
    -- physical death.
    if IsPlayerGUID(guid) and type(history.victims) == "table" then
        victim = history.victims["G:" .. guid]
    end

    if not victim and type(history.victims) == "table" then
        for _, candidate in pairs(history.victims) do
            if type(candidate) == "table"
                and SameVictimIdentity(candidate.name, candidate.guid, playerName, playerGUID) then
                victim = candidate
                break
            end
        end
    end

    if type(victim) ~= "table" or type(victim.events) ~= "table" then
        return 0
    end

    local count = 0
    for _, stamp in pairs(victim.events) do
        local eventTime = tonumber(stamp) or 0
        if eventTime >= dayStart and eventTime <= (now + 60) then
            count = count + 1
        end
    end
    return count
end

local function FindTodayVictim(playerName, playerGUID)
    GT.victims = GT.victims or {}

    local exact = GT.victims[playerName]
    if exact then return playerName, exact end

    local wantGUID = tostring(playerGUID or "")
    if IsPlayerGUID(wantGUID) then
        for name, victim in pairs(GT.victims) do
            if type(victim) == "table" and tostring(victim.guid or "") == wantGUID then
                return name, victim
            end
        end
    end

    -- Special-character/realm aliases are a recovery fallback only. Today's list
    -- is small, so this is cheap and avoids creating a second row for the same mark.
    local wantName = NormalizedPlayerName(playerName)
    local foundName, foundVictim, matches = nil, nil, 0
    for name, victim in pairs(GT.victims) do
        if NormalizedPlayerName(name) == wantName then
            matches = matches + 1
            foundName, foundVictim = name, victim
            if matches > 1 then break end
        end
    end
    if matches == 1 then return foundName, foundVictim end
    return playerName, nil
end

local function GetCurrentTodayCount(playerName, playerGUID)
    local _, victim = FindTodayVictim(playerName, playerGUID)
    return victim and (tonumber(victim.kills) or 0) or 0
end

local function ApplyLocalKillToDailyStats(playerName, playerGUID, playerLevel, zone, subZone, location, historicalKills)
    -- Normally initialized/rebuilt at login and on remote sync. Only do a full
    -- rebuild here if the realm 08:00 daily boundary actually rolled over.
    if GT._dailyDateKey ~= DailyDateKey() then
        RefreshDailyStats()
    end

    local victimKey, victim = FindTodayVictim(playerName, playerGUID)
    local isNew = victim == nil
    if isNew then
        victim = {
            kills = 0,
            guid = tostring(playerGUID or ""),
            lastZone = zone,
            lastSubZone = subZone,
        }
        GT.victims[victimKey] = victim
        GT.uniqueKills = (tonumber(GT.uniqueKills) or 0) + 1
    end

    victim.kills = (tonumber(victim.kills) or 0) + 1
    victim.guid = tostring(playerGUID or victim.guid or "")
    victim.lastZone = zone
    victim.lastSubZone = subZone

    GT.totalKills = (tonumber(GT.totalKills) or 0) + 1
    GT.sessionKills = GT.totalKills
    GT.sessionVictims = GT.sessionVictims or {}
    GT.sessionVictims[victimKey] = victim.kills

    local numericLevel = tonumber(playerLevel)
    if numericLevel == 60 then
        GT.daily60Kills = (tonumber(GT.daily60Kills) or 0) + 1
    elseif numericLevel and numericLevel < 60 then
        GT.dailyNoobKills = (tonumber(GT.dailyNoobKills) or 0) + 1
    else
        GT.dailyUnknownLevelKills = (tonumber(GT.dailyUnknownLevelKills) or 0) + 1
    end

    local bucket = LevelBucketKey(playerLevel)
    if bucket then
        GT.levelKillBuckets = GT.levelKillBuckets or {}
        GT.levelKillBuckets[bucket] = (tonumber(GT.levelKillBuckets[bucket]) or 0) + 1
    end

    GT.lastKillName = playerName
    GT.lastKillGUID = playerGUID
    GT.lastKillLevel = playerLevel
    GT.lastKillLocation = location
    GT.lastKillHistorical = tonumber(historicalKills) or 0

    return victim.kills
end

local STREAK_FLAVOR = {
    [5] = {
        "KILLING SPREE", "HE'S WARMING UP", "SOMEONE CHECK ON THEM",
        "BAD DAY TO BE ALLIANCE", "MINOR GRAVEYARD CONGESTION REPORTED",
        "LOCAL PALADINS ADVISED TO TRAVEL IN GROUPS", "THE FIRST COMPLAINT HAS BEEN FILED",
        "THIS SEEMED FUNNIER FIVE KILLS AGO",
    },
    [10] = {
        "BODIES ARE PILING UP", "THIS IS GETTING PERSONAL", "THE GRAVEYARD IS GETTING BUSY",
        "LOCAL RESPONSE TIME INCREASING", "CORPSE RUN TRAFFIC NOW MODERATE",
        "ZONE CHAT HAS BEGUN ASKING QUESTIONS", "THEY HAVE FORMED A COMMITTEE",
        "TEN DIFFERENT PEOPLE HAVE MADE THE SAME MISTAKE",
    },
    [15] = {
        "ABSOLUTE MENACE", "THIS HAS BECOME A PUBLIC SAFETY ISSUE", "SOMEONE CALL MANAGEMENT",
        "THE ZONE HAS FILED A COMPLAINT", "GRAVEYARD PARKING IS NOW FULL",
        "AN INCIDENT COMMAND POST HAS BEEN ESTABLISHED", "THE SITUATION HAS DEVELOPED ITS OWN PAPERWORK",
        "LOCAL AUTHORITIES RECOMMEND LOGGING AN ALT",
    },
    [20] = {
        "LOCAL DISASTER", "EVACUATION MAY BE APPROPRIATE", "THIS IS NOW A REGIONAL PROBLEM",
        "RESPAWN SERVICES OVERWHELMED", "THE GRAVEYARD HAS SWITCHED TO TRIAGE",
        "THIS NOW REQUIRES A POWERPOINT", "A SECOND GRAVEYARD HAS BEEN REQUESTED",
        "THE CORONER HAS STOPPED ASKING FOR NAMES",
    },
    [25] = {
        "PUBLIC ENEMY", "WANTED IN MULTIPLE ZONES", "THE CORPSE RUN ECONOMY IS BOOMING",
        "GRAVEYARD STAFF REQUESTING OVERTIME", "THE FLIGHT MASTER IS CONSIDERING EVACUATION",
        "LOCAL INNS ARE OFFERING WITNESS PROTECTION", "THE ALLIANCE HAS OPENED A HELP DESK",
        "THIS INCIDENT NOW HAS A CASE NUMBER",
    },
    [30] = {
        "SEND REINFORCEMENTS", "THE NATIONAL GUARD HAS BEEN NOTIFIED", "THIS WAS NOT IN THE RAID PLAN",
        "RESPAWN BUDGET EXCEEDED", "THE GRAVEYARD HAS DECLARED A STATE OF EMERGENCY",
        "THE WAR ROOM IS JUST PEOPLE POINTING AT THE MAP", "THEY HAVE BEGUN BLAMING LAG",
        "AN EMERGENCY MEETING HAS ACCOMPLISHED NOTHING",
    },
    [35] = {
        "THIS IS GETTING RIDICULOUS", "WE ARE RUNNING OUT OF GRAVESTONES", "ZONE CHAT IS IN SHAMBLES",
        "THIS FEELS ADMINISTRATIVE NOW", "THE INCIDENT REPORT HAS BECOME A NOVEL",
        "GRAVEYARD STAFF HAVE UNIONIZED", "THE MAP LEGEND NOW INCLUDES TALIAA",
        "SOMEONE HAS DEFINITELY OPENED A TICKET",
    },
    [40] = {
        "OUT OF CONTROL", "STILL NOT DEAD", "THIS HAS ESCALATED BEYOND REASON",
        "GRAVEYARD QUEUE EXCEEDS CAPACITY", "WHO APPROVED THIS", "THE MAP IS NOW A CRIME SCENE",
        "PLEASE STOP FEEDING HIM", "SITUATION NORMAL: EVERYONE IS DEAD",
        "THE GRAVEYARD IS ACCEPTING RESERVATIONS", "THE ALLIANCE HAS REQUESTED A SERVER RESTART",
        "THE WAR EFFORT HAS BEEN RECLASSIFIED AS A LOST AND FOUND",
        "THE INCIDENT COMMANDER HAS LEFT THE GROUP",
    },
}
local STREAK_FALLBACK = {
    "STILL NOT DEAD",
    "THIS HAS ESCALATED BEYOND REASON",
    "GRAVEYARD QUEUE EXCEEDS CAPACITY",
    "WHO APPROVED THIS",
    "THE MAP IS NOW A CRIME SCENE",
    "PLEASE STOP FEEDING HIM",
    "SITUATION NORMAL: EVERYONE IS DEAD",
    "THE GRAVEYARD IS ACCEPTING RESERVATIONS",
    "THE ALLIANCE HAS REQUESTED A SERVER RESTART",
    "THE WAR ROOM HAS STOPPED RETURNING CALLS",
    "LOCAL AUTHORITIES HAVE CHANGED THEIR NAMES",
    "THE CORPSE RUN NOW HAS A COMMUTER LANE",
    "THE GRAVEYARD HAS A WAITING ROOM",
    "THIS IS NO LONGER PVP. THIS IS URBAN PLANNING",
    "THE RESPAWN TIMER HAS RETAINED LEGAL COUNSEL",
    "THE MAP IS REQUESTING PAID TIME OFF",
    "A TASK FORCE HAS BEEN FORMED TO STUDY THE TASK FORCE",
    "THE ALLIANCE HAS BEGUN EVACUATING LOW LEVELS",
    "GRAVEYARD CAPACITY IS NOW A STRATEGIC RESOURCE",
    "THE INCIDENT REPORT JUST RAN OUT OF PAPER",
    "THIS KILL STREAK NOW HAS ITS OWN ZIP CODE",
    "THE LOCAL ECONOMY IS 80 PERCENT REPAIR BILLS",
    "THE SPIRIT HEALER HAS ACTIVATED SURGE PRICING",
    "THE ZONE HAS ENTERED THE FIND OUT PHASE",
    "THEY ARE NOW RESPAWNING OUT OF HABIT",
    "THE GRAVEYARD SHIFT CHANGE HAS BEEN CANCELLED",
    "THE NEXT REINFORCEMENT IS JUST ANOTHER CORPSE",
    "SOMEONE CHECK IF THIS IS STILL WITHIN THE TERMS OF SERVICE",
    "THE ALLIANCE IS CURRENTLY ACCEPTING APPLICATIONS FOR SURVIVORS",
    "AT THIS POINT THE GRAVEYARD IS THE MAIN CITY",
}

local function PickStreakFlavor(pool)
    if type(pool) ~= "table" or #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

local function StreakFlavor(streak)
    streak = tonumber(streak) or 0
    if streak < 5 or streak % 5 ~= 0 then return nil end

    -- Five kills unlocks the nonsense pool. From then on every 5-kill
    -- milestone can draw from every line instead of being tier-locked.
    local pool = {}
    for _, milestonePool in pairs(STREAK_FLAVOR) do
        for _, line in ipairs(milestonePool) do
            pool[#pool + 1] = line
        end
    end
    for _, line in ipairs(STREAK_FALLBACK) do
        pool[#pool + 1] = line
    end
    return PickStreakFlavor(pool)
end

local function BuildStreakEndMessage(streak)
    streak = tonumber(streak) or 0
    if streak < 5 then return nil end
    local me = tostring(VoidMarkForever.API.UnitName("player") or "Player")
    if streak >= 30 then
        return string.format("%s's %d-kill streak finally ended. Reinforcements worked.", me, streak)
    elseif streak >= 20 then
        return string.format("%s's %d-kill streak ended. The zone can breathe again.", me, streak)
    elseif streak >= 10 then
        return string.format("%s's %d-kill streak ended.", me, streak)
    end
    return string.format("%s's %d-kill streak ended.", me, streak)
end

local function BuildKillAnnouncement(playerName, playerGUID, playerLevel, playerClass, location, historicalKills, todayVictimKills)
    local displayName = tostring(playerName or "?")
    displayName = displayName:match("^[^-]+") or displayName

    -- "Session" is this victim's merged account-wide count in the current
    -- 08:00-to-08:00 hunt window. GetTodayVictimKillCount() is built from the
    -- shared repository, so kills from every character/account are included
    -- after sync instead of being stuck in a character-local session table.
    local sessionVictimKills = tonumber(todayVictimKills) or 0
    if sessionVictimKills < 1 then
        sessionVictimKills = 1
    end

    local message = string.format(
        "%s L%s | Today %dx | Historical %dx",
        displayName,
        tostring(playerLevel or "?"),
        sessionVictimKills,
        tonumber(historicalKills) or 0
    )

    return message
end

local function BuildStreakMilestoneMessage()
    local streak = tonumber(GT.currentStreak) or 0
    local flavor = StreakFlavor(streak)
    if not flavor then return nil end
    return string.format("KILL STREAK %d - %s", streak, flavor)
end


-- Lightweight kill-path profiler. Silent during play; inspect with /tgank perf.
GT._killPerf = GT._killPerf or { samples = {}, maxSamples = 20 }

local function PerfNowMS()
    if debugprofilestop then
        return debugprofilestop()
    end
    return (GetTime and GetTime() or 0) * 1000
end

local function PerfPushSample(sample)
    local p = GT._killPerf
    p.samples[#p.samples + 1] = sample
    while #p.samples > (p.maxSamples or 20) do
        table.remove(p.samples, 1)
    end
end

local function PerfMark(sample, label, lastMS)
    local nowMS = PerfNowMS()
    sample.steps[#sample.steps + 1] = {
        label = label,
        ms = math.max(0, nowMS - (lastMS or sample.startedMS or nowMS)),
    }
    return nowMS
end

local function PrintKillPerf()
    local p = GT._killPerf
    local samples = p and p.samples or nil
    if not samples or #samples == 0 then
        Print("PERF: no kill samples recorded yet.")
        return
    end

    local latest = samples[#samples]
    Print(string.format("PERF latest: %s | total %.2f ms",
        BasePlayerName(latest.name or "?"),
        tonumber(latest.totalMS) or 0))

    for _, step in ipairs(latest.steps or {}) do
        Print(string.format("  %s: %.2f ms", tostring(step.label), tonumber(step.ms) or 0))
    end

    local worst = latest
    for _, s in ipairs(samples) do
        if (tonumber(s.totalMS) or 0) > (tonumber(worst.totalMS) or 0) then
            worst = s
        end
    end
    if worst ~= latest then
        Print(string.format("PERF worst of last %d: %s | %.2f ms",
            #samples,
            BasePlayerName(worst.name or "?"),
            tonumber(worst.totalMS) or 0))
        for _, step in ipairs(worst.steps or {}) do
            Print(string.format("  WORST %s: %.2f ms", tostring(step.label), tonumber(step.ms) or 0))
        end
    else
        Print(string.format("PERF worst of last %d: latest sample.", #samples))
    end
end

local function IgnoreBattlegroundStats()
    if VoidMark and VoidMark.ShouldIgnoreBattlegroundStats then
        return VoidMark:ShouldIgnoreBattlegroundStats()
    end
    local profile = VoidMark and VoidMark.db and VoidMark.db.profile
    if not (profile and profile.IgnoreBattlegroundStats) then return false end
    local inInstance, instanceType = VoidMarkForever.API.IsInInstance()
    return inInstance == true and instanceType == "pvp"
end

function GT:ShouldIgnoreBattlegroundStats()
    return IgnoreBattlegroundStats()
end

function GT:RecordKill(playerName, playerGUID, shouldAnnounce)
    if not playerName or playerName == "" then return end
    if IgnoreBattlegroundStats() then return end

    -- Authoritative kill credit overrides stale Feign state for this death.
    local confirmedAt = 0
    if playerGUID and recentConfirmedPlayerKills then
        confirmedAt = tonumber(recentConfirmedPlayerKills[playerGUID]) or 0
    end
    local confirmedRealDeath = confirmedAt > 0 and (GetTime() - confirmedAt) <= 2.0

    -- Final central Feign gate. Every kill source (VoidMark, PARTY_KILL, UNIT_DIED,
    -- assist fallback) eventually passes through RecordKill(), so also ask the
    -- live unit state here. This covers Classic clients that do not expose a
    -- usable Feign flag/spell event before kill credit is emitted.
    if not confirmedRealDeath and IsUnitCurrentlyFeigningName and IsUnitCurrentlyFeigningName(playerName) then
        MarkHunterFeign(playerGUID, playerName)
        if playerGUID then recentOutgoingVictims[playerGUID] = nil end
        return
    end

    -- Feign Death can generate UNIT_DIED-like traffic in Classic. Suppress it
    -- centrally so VoidMark.lua, PARTY_KILL/UNIT_DIED fallbacks, and other callers
    -- cannot accidentally turn a feign into a real gank. Authoritative PARTY_KILL
    -- credit overrides stale Feign state from the same death.
    if not confirmedRealDeath and GT:IsRecentFeign(playerName, playerGUID) then
        return
    end

    local perf = {
        name = playerName,
        startedMS = PerfNowMS(),
        steps = {},
    }
    local perfLastMS = perf.startedMS

    -- Never count pets, guardians, NPCs, totems or vehicles as ganks. Some
    -- player-controlled pets can satisfy Blizzard's "hostile players" combat-log
    -- filter, so GUID type is the final authority.
    if IsExplicitNonPlayerGUID(playerGUID) then
        return
    end

    -- PARTY_KILL, UNIT_DIED, VoidMark.lua and this file's combat fallback can all
    -- report the same death. Match the repository's six-second same-death guard.
    local now = GetTime()
    local dedupeKey
    if IsPlayerGUID(playerGUID) then
        dedupeKey = "G:" .. tostring(playerGUID)
    else
        dedupeKey = "N:" .. NormalizedPlayerName(playerName)
    end
    local lastEvent = self.recentKillEvents[dedupeKey]
    if lastEvent and now - lastEvent < 6 then
        return
    end
    self.recentKillEvents[dedupeKey] = now

    local zone = GetZoneText() or "Unknown"
    local subZone = GetSubZoneText() or ""
    local location = CurrentLocation()
    perfLastMS = PerfMark(perf, "preflight/location", perfLastMS)
    local playerLevel, playerClass = GetPlayerDetails(playerName, playerGUID)
    perfLastMS = PerfMark(perf, "player details", perfLastMS)
    local historicalKills = 0
    local repositoryAdded = nil
    local todayCountBeforeRepository = GetCurrentTodayCount(playerName, playerGUID)

    if TaliaaGankRepository and TaliaaGankRepository.RecordKill then
        historicalKills, repositoryAdded = TaliaaGankRepository:RecordKill(playerName, playerGUID, {
            zone = zone,
            subZone = subZone,
            level = playerLevel,
            class = playerClass,
            killer = VoidMarkForever.API.UnitName("player") or "?",
        })
        historicalKills = tonumber(historicalKills) or 0
    end
    perfLastMS = PerfMark(perf, "repository write", perfLastMS)

    -- Keep VoidMark's visible W/L cache in lockstep with the canonical lifetime
    -- repository value returned for this kill. This fixes rows that could remain
    -- at 0-0 while the kill announcement correctly reported Historical 2x, etc.
    SyncVoidMarkLifetimeRecord(playerName, playerGUID, historicalKills)
    perfLastMS = PerfMark(perf, "VoidMark W/L sync", perfLastMS)

    -- The local six-second gate above is authoritative for streak/effect credit on
    -- this client. The repository may return false simply because VoidMark.lua or the
    -- paired account stored the same death first. Returning here used to make a
    -- legitimate local kill advance Today/Historical while leaving KILL STREAK at 0.
    AddSessionKill(playerName)
    perfLastMS = PerfMark(perf, "session/streak", perfLastMS)

    -- Kill Effects follows accepted kills. Hunters get a short grace period
    -- because Classic can emit UNIT_DIED for Feign after an earlier kill-credit
    -- path. This prevents fake deaths from firing Fatality/multikill audio.
    if VoidMarkKillEffects and VoidMarkKillEffects.OnKill then
        if GT:IsKnownHunter(playerName, playerGUID) and C_Timer and C_Timer.After then
            local effectName, effectGUID, effectStreak = playerName, playerGUID, GT.currentStreak
            local confirmedAt = effectGUID and tonumber(recentConfirmedPlayerKills[effectGUID]) or 0
            if confirmedAt > 0 and (GetTime() - confirmedAt) <= 2.0 then
                -- PARTY_KILL is the authoritative real-Hunter-death signal.
                VoidMarkKillEffects:OnKill(effectName, effectGUID, effectStreak)
            else
                -- Unconfirmed Hunter death paths can be Feign. Wait long enough
                -- for UNIT_DIED/Feign classification before allowing any kill audio.
                C_Timer.After(2.25, function()
                    if not GT:IsRecentFeign(effectName, effectGUID) then
                        VoidMarkKillEffects:OnKill(effectName, effectGUID, effectStreak)
                    end
                end)
            end
        else
            VoidMarkKillEffects:OnKill(playerName, playerGUID, GT.currentStreak)
        end
    end
    perfLastMS = PerfMark(perf, "Kill Effects", perfLastMS)
    -- Feign warning / kill-effect validation refresh marker.

    local todayVictimKills = GetTodayVictimKillCount(playerName, playerGUID)

    -- Lifetime can never be lower than today's count. During two-client sync the
    -- victim index can trail the event ledger by a frame, so clamp the visible
    -- announcement to the logically valid minimum while normal repair catches up.
    historicalKills = math.max(tonumber(historicalKills) or 0, tonumber(todayVictimKills) or 0)

    GT.lastKillName = playerName
    GT.lastKillGUID = playerGUID
    GT.lastKillLevel = playerLevel
    GT.lastKillLocation = location
    GT.lastKillHistorical = historicalKills

    -- Rebuild the rest of today's cached counters after combat instead of trying
    -- to locally increment them on every client that saw the same group death.
    GT._historyRefreshPending = true
    perfLastMS = PerfMark(perf, "today/history counters", perfLastMS)

    levelLookup.dirty = true

    -- v8.9: do not call chat/network APIs from inside the combat-log death
    -- callback. Queue the already-built message for a few hundredths of a second
    -- later so the death frame can return to the client immediately.
    if self.partyAnnounce and shouldAnnounce ~= false then
        local killMessage = BuildKillAnnouncement(
            playerName, playerGUID, playerLevel, playerClass, location, historicalKills, todayVictimKills
        )
        local streakMessage = BuildStreakMilestoneMessage()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() SafeGroupMessage(killMessage) end)
            if streakMessage then
                C_Timer.After(0.15, function() SafeGroupMessage(streakMessage) end)
            end
        else
            SafeGroupMessage(killMessage)
            if streakMessage then
                SafeGroupMessage(streakMessage)
            end
        end
    end
    perfLastMS = PerfMark(perf, "announcement queue", perfLastMS)

    -- Never do revenge-table walks or a GankTracker repaint in the death
    -- callback, even if the killing blow happens to drop combat immediately.
    local revengeKey = IsPlayerGUID(playerGUID) and ("G:" .. tostring(playerGUID))
        or ("N:" .. NormalizedPlayerName(playerName))
    self._pendingRevengeClaims[revengeKey] = { name = playerName, guid = playerGUID }
    self._displayRefreshPending = true

    -- If combat is already over, service the deferred UI on a later frame.
    -- Multiple near-simultaneous kills coalesce behind one timer.
    if not (InCombatLockdown and InCombatLockdown()) and not self._killDeferredTimerArmed then
        self._killDeferredTimerArmed = true
        C_Timer.After(0.10, function()
            GT._killDeferredTimerArmed = nil
            if InCombatLockdown and InCombatLockdown() then return end
            FlushPendingRevengeClaims()
            if GT._historyRefreshPending then
                GT._historyRefreshPending=nil
                RefreshDailyStats()
                SeedSessionFromHistory()
            end
            GT._displayRefreshPending = nil
            UpdateDisplay()
        end)
    end

    perfLastMS = PerfMark(perf, "deferred UI scheduling", perfLastMS)
    perf.totalMS = math.max(0, PerfNowMS() - perf.startedMS)
    PerfPushSample(perf)
end

function GT:OnHistoryUpdated(playerName, playerGUID, historicalKills)
    recordStatsCache.stats = nil
    weeklyStatsCache.stats = nil
    SyncVoidMarkLifetimeRecord(playerName, playerGUID, historicalKills)
    -- Repository updates here are remote/sync updates; local GT:RecordKill uses
    -- the incremental path above. Never rescan thousands of rows in combat.
    levelLookup.dirty = true

    if InCombatLockdown and InCombatLockdown() then
        self._historyRefreshPending = true
        return
    end

    local rebuilt = RefreshDailyStats()
    SeedSessionFromHistory() -- one-time migration seed only

    if not rebuilt and self.lastKillName and playerName then
        local sameName = NormalizedPlayerName(self.lastKillName) == NormalizedPlayerName(playerName)
        local sameGUID = self.lastKillGUID and playerGUID and tostring(self.lastKillGUID) == tostring(playerGUID)
        if sameName or sameGUID then
            self.lastKillHistorical = tonumber(historicalKills) or self.lastKillHistorical or 0
        end
    end

    UpdateDisplay()
end

function GT:OnHistoricalRepair(playerName, playerGUID, historicalKills)
    SyncVoidMarkLifetimeRecord(playerName, playerGUID, historicalKills)
    -- Lightweight post-combat identity repair. Daily/session counters were already
    -- updated when the kill happened; only the displayed lifetime value may need
    -- to rise after an accent/legacy alias is reconciled.
    if self.lastKillName and playerName then
        local sameName = NormalizedPlayerName(self.lastKillName) == NormalizedPlayerName(playerName)
        local sameGUID = self.lastKillGUID and playerGUID
            and tostring(self.lastKillGUID) == tostring(playerGUID)
        if sameName or sameGUID then
            self.lastKillHistorical = math.max(
                tonumber(self.lastKillHistorical) or 0,
                tonumber(historicalKills) or 0
            )
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        self._displayRefreshPending = true
    else
        UpdateDisplay()
    end
end

function GT:OnDHKHistoryUpdated()
    -- Remote DHK sync can arrive while fighting. Defer even the UI/count rebuild
    -- until combat ends; the authoritative rows are already safely stored.
    if InCombatLockdown and InCombatLockdown() then
        self._dhkRefreshPending = true
        return
    end
    UpdateDisplay()
end

function GT:Reset()
    -- Today/Session is a fixed account-wide 08:00 -> 08:00 window. A local
    -- manual cutoff would make paired accounts disagree, so Reset now clears
    -- only character-local streak/revenge/DHK session state.
    ResetSessionStats()
    self.recentKillEvents = {}
    RefreshDailyStats()
    UpdateDisplay()
    Print("Local streak/revenge session reset. Shared Today/Session still uses the fixed 08:00 realm reset.")
end

RefreshDailyStats()
EnsureSessionStats()
SeedSessionFromHistory()

local VM_PURPLE = {0.56, 0.20, 0.82}
local VM_PURPLE_BRIGHT = {0.76, 0.42, 1.00}
local VM_BG = {0.015, 0.010, 0.025, 0.97}
local VM_PANEL = {0.035, 0.025, 0.055, 0.98}
local VM_BORDER = {0.31, 0.11, 0.46, 1.00}

local function ApplyVoidMarkFrame(frame, bg)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local c = bg or VM_BG
    frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
    frame:SetBackdropBorderColor(VM_BORDER[1], VM_BORDER[2], VM_BORDER[3], VM_BORDER[4])
end

local function MakeFlatButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    ApplyVoidMarkFrame(b, VM_PANEL)
    b:SetBackdropBorderColor(0.30, 0.14, 0.42, 1)
    b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Label:SetPoint("CENTER")
    b.Label:SetText(text)
    b.Label:SetTextColor(0.88, 0.78, 0.94, 1)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.11, 0.045, 0.16, 1)
        self:SetBackdropBorderColor(VM_PURPLE_BRIGHT[1], VM_PURPLE_BRIGHT[2], VM_PURPLE_BRIGHT[3], 1)
        self.Label:SetTextColor(1, 1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(VM_PANEL[1], VM_PANEL[2], VM_PANEL[3], VM_PANEL[4])
        self:SetBackdropBorderColor(0.30, 0.14, 0.42, 1)
        self.Label:SetTextColor(0.88, 0.78, 0.94, 1)
        if self == GT.Frame.PartyButton then UpdateDisplay() end
    end)
    return b
end

local function MakeStat(parent, x, label)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(46, 38)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -62)

    local value = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOP", holder, "TOP", 0, 0)
    value:SetText("0")
    value:SetTextColor(0.92, 0.72, 1.00, 1)

    local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("TOP", value, "BOTTOM", 0, -1)
    caption:SetText(label)
    caption:SetTextColor(0.55, 0.48, 0.62, 1)

    value.Caption = caption
    value.Holder = holder
    return value
end

local function MakeLevelStat(parent, x, label)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(34, 28)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -106)

    local value = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    value:SetPoint("TOP", holder, "TOP", 0, 0)
    value:SetText("0")
    value:SetTextColor(0.88, 0.68, 1.00, 1)

    local caption = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("TOP", value, "BOTTOM", 0, -1)
    caption:SetText(label)
    caption:SetTextColor(0.52, 0.45, 0.59, 1)

    value.Caption = caption
    value.Holder = holder
    return value
end

-- Main Gank Tracker ---------------------------------------------------------
local frame = CreateFrame("Frame", "TaliaaVoidMarkGankTrackerFrame", UIParent, "BackdropTemplate")
GT.Frame = frame

frame:SetSize(250, 292)
frame:SetPoint("CENTER", UIParent, "CENTER", 320, 120)
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
ApplyVoidMarkFrame(frame, VM_BG)

-- Start hidden every login/reload. The tracker continues collecting data in the
-- background and the VoidMark GT button (or /tgank show) opens it on demand.
frame:Hide()

local function GankUIState()
    if not VoidMarkDB then return nil end
    VoidMarkDB.TaliaaGankUI = VoidMarkDB.TaliaaGankUI or {}
    return VoidMarkDB.TaliaaGankUI
end

local function SaveGankPosition()
    -- The compact tracker is docked to VoidMark and should never overwrite the
    -- user's free-floating expanded position.
    if GT.IsMinimized and GT:IsMinimized() then return end
    local state = GankUIState()
    if not state then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    state.point = point or "CENTER"
    state.relativePoint = relativePoint or state.point
    state.x = x or 0
    state.y = y or 0
end


local function RestoreGankPosition()
    local state = GankUIState()
    if state and state.x ~= nil and state.y ~= nil then
        frame:ClearAllPoints()
        frame:SetPoint(state.point or "CENTER", UIParent, state.relativePoint or state.point or "CENTER", state.x, state.y)
    end
end

RestoreGankPosition()

frame:SetScript("OnDragStart", function(self)
    if GT.IsMinimized and GT:IsMinimized() then return end
    self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveGankPosition()
end)

local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
header:SetHeight(56)
header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
header:SetBackdropColor(0.045, 0.018, 0.065, 0.98)

local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", header, "TOPLEFT", 9, -5)
title:SetText("VOIDMARK  •  GANK TRACKER")
title:SetTextColor(VM_PURPLE_BRIGHT[1], VM_PURPLE_BRIGHT[2], VM_PURPLE_BRIGHT[3], 1)

local subtitle = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.Subtitle = subtitle
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -1)
subtitle:SetText("TODAY'S HUNT")
subtitle:SetTextColor(0.56, 0.48, 0.63, 1)

-- Hunt view selector: switches the stat panel between today's counters and
-- the current weekly-reset window. This only changes the display; it does not
-- reset or alter any repository data.
frame.TodayViewButton = MakeFlatButton(header, "TODAY", 55, 17)
frame.TodayViewButton:SetPoint("TOPLEFT", header, "TOPLEFT", 45, -35)
frame.TodayViewButton:SetScript("OnClick", function() SetHuntViewMode("today") end)

frame.WeeklyViewButton = MakeFlatButton(header, "WEEK", 55, 17)
frame.WeeklyViewButton:SetPoint("LEFT", frame.TodayViewButton, "RIGHT", 4, 0)
frame.WeeklyViewButton:SetScript("OnClick", function() SetHuntViewMode("weekly") end)

frame.RecordsViewButton = MakeFlatButton(header, "RECORDS", 61, 17)
frame.RecordsViewButton:SetPoint("LEFT", frame.WeeklyViewButton, "RIGHT", 4, 0)
frame.RecordsViewButton:SetScript("OnClick", function() SetHuntViewMode("records") end)

frame.CloseButton = CreateFrame("Button", nil, header)
frame.CloseButton:SetSize(18, 18)
frame.CloseButton:SetPoint("TOPRIGHT", header, "TOPRIGHT", -4, -4)
frame.CloseButton.Text = frame.CloseButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.CloseButton.Text:SetPoint("CENTER")
frame.CloseButton.Text:SetText("X")
frame.CloseButton.Text:SetTextColor(1.0, 0.28, 0.38, 1)
frame.CloseButton:SetScript("OnEnter", function(self)
    self.Text:SetTextColor(1.0, 0.65, 0.72, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Hide Gank Tracker", 1, 0.82, 0)
    GameTooltip:AddLine("Tracking continues while hidden.", 1, 1, 1)
    GameTooltip:Show()
end)
frame.CloseButton:SetScript("OnLeave", function(self)
    self.Text:SetTextColor(1.0, 0.28, 0.38, 1)
    GameTooltip:Hide()
end)
frame.CloseButton:SetScript("OnClick", function()
    if GT.SetMinimized then GT:SetMinimized(true) else frame:Hide() end
end)

frame.MinimizeButton = CreateFrame("Button", nil, header)
frame.MinimizeButton:SetSize(18, 18)
frame.MinimizeButton:SetPoint("RIGHT", frame.CloseButton, "LEFT", -2, 0)
frame.MinimizeButton.Text = frame.MinimizeButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.MinimizeButton.Text:SetPoint("CENTER")
frame.MinimizeButton.Text:SetText("−")
frame.MinimizeButton.Text:SetTextColor(0.78, 0.52, 1.00, 1)
frame.MinimizeButton:SetScript("OnEnter", function(self)
    self.Text:SetTextColor(1, 1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Minimize Gank Tracker", 0.78, 0.45, 1.0)
    GameTooltip:AddLine("Tracking continues while hidden.", 0.85, 0.85, 0.85)
    GameTooltip:Show()
end)
frame.MinimizeButton:SetScript("OnLeave", function(self)
    self.Text:SetTextColor(0.78, 0.52, 1.00, 1)
    GameTooltip:Hide()
end)

frame.CompactText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.CompactText:SetPoint("LEFT", header, "LEFT", 88, 0)
frame.CompactText:SetPoint("RIGHT", frame.MinimizeButton, "LEFT", -6, 0)
frame.CompactText:SetJustifyH("LEFT")
frame.CompactText:SetTextColor(0.82, 0.72, 0.90, 1)
frame.CompactText:Hide()

frame.TotalValue = MakeStat(frame, 3, "KILLS")
frame.UniqueValue = MakeStat(frame, 52, "UNIQUE")
frame.DupeValue = MakeStat(frame, 101, "REPEATS")
frame.NearbyValue = MakeStat(frame, 150, "60/30")
frame.PetValue = MakeStat(frame, 199, "PETS")

frame.LevelBucketValues = {}
frame.LevelBucketValues["1-9"] = MakeLevelStat(frame, 2, "1-9")
frame.LevelBucketValues["10-20"] = MakeLevelStat(frame, 36, "10-20")
frame.LevelBucketValues["21-30"] = MakeLevelStat(frame, 71, "21-30")
frame.LevelBucketValues["31-40"] = MakeLevelStat(frame, 106, "31-40")
frame.LevelBucketValues["41-50"] = MakeLevelStat(frame, 141, "41-50")
frame.LevelBucketValues["51-59"] = MakeLevelStat(frame, 176, "51-59")
frame.LevelBucketValues["60"] = MakeLevelStat(frame, 211, "60")

local divider = frame:CreateTexture(nil, "ARTWORK")
divider:SetColorTexture(0.30, 0.12, 0.42, 0.65)
divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -140)
divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -140)
divider:SetHeight(1)

lastLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lastLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -148)
lastLabel:SetText("LAST MARK")
lastLabel:SetTextColor(0.56, 0.48, 0.63, 1)

frame.LastName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.LastName:SetPoint("TOPLEFT", lastLabel, "BOTTOMLEFT", 0, -2)
frame.LastName:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
frame.LastName:SetJustifyH("LEFT")

frame.LastMeta = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
frame.LastMeta:SetPoint("TOPLEFT", frame.LastName, "BOTTOMLEFT", 0, -2)
frame.LastMeta:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
frame.LastMeta:SetJustifyH("LEFT")
frame.LastMeta:SetTextColor(0.82, 0.78, 0.86, 1)

frame.LastLocation = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.LastLocation:SetPoint("TOPLEFT", frame.LastMeta, "BOTTOMLEFT", 0, -2)
frame.LastLocation:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
frame.LastLocation:SetJustifyH("LEFT")
frame.LastLocation:SetTextColor(0.60, 0.50, 0.68, 1)

frame.RevengeText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.RevengeText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 73)
frame.RevengeText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
frame.RevengeText:SetJustifyH("LEFT")
frame.RevengeText:SetTextColor(0.50, 0.44, 0.56, 1)

frame.RepoText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.RepoText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 59)
frame.RepoText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
frame.RepoText:SetJustifyH("LEFT")
frame.RepoText:SetTextColor(0.54, 0.45, 0.62, 1)

frame.CombatText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.CombatText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 45)
frame.CombatText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
frame.CombatText:SetJustifyH("LEFT")
frame.CombatText:SetTextColor(0.54, 0.45, 0.62, 1)

frame.SyncText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.SyncText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 31)
frame.SyncText:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
frame.SyncText:SetJustifyH("LEFT")
frame.SyncText:SetTextColor(0.50, 0.68, 0.58, 1)

frame.PartyButton = MakeFlatButton(frame, "PARTY OFF", 72, 21)
frame.PartyButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 6)
frame.PartyButton:SetScript("OnClick", function()
    GT.partyAnnounce = not GT.partyAnnounce
    if VoidMarkDB then VoidMarkDB.TaliaaGankPartyAnnounce = GT.partyAnnounce end
    UpdateDisplay()
    Print("Party announcements: " .. (GT.partyAnnounce and "ON" or "OFF"))
end)

frame.ReportButton = MakeFlatButton(frame, "REPORT", 55, 21)
frame.ReportButton:SetPoint("LEFT", frame.PartyButton, "RIGHT", 4, 0)
frame.ReportButton:SetScript("OnClick", function() GT:ReportCurrentHunt() end)

frame.ResetButton = MakeFlatButton(frame, "RESET", 50, 21)
frame.ResetButton:SetPoint("LEFT", frame.ReportButton, "RIGHT", 4, 0)
frame.ResetButton:SetScript("OnClick", function() GT:Reset() end)

frame.OptionsButton = MakeFlatButton(frame, "OPT", 41, 21)
frame.OptionsButton:SetPoint("LEFT", frame.ResetButton, "RIGHT", 4, 0)

local expandedWidgets = {
    subtitle,
    frame.TodayViewButton,
    frame.WeeklyViewButton,
    frame.RecordsViewButton,
    frame.TotalValue and frame.TotalValue.Holder,
    frame.UniqueValue and frame.UniqueValue.Holder,
    frame.DupeValue and frame.DupeValue.Holder,
    frame.NearbyValue and frame.NearbyValue.Holder,
    frame.PetValue and frame.PetValue.Holder,
    frame.LevelBucketValues["1-9"] and frame.LevelBucketValues["1-9"].Holder,
    frame.LevelBucketValues["10-20"] and frame.LevelBucketValues["10-20"].Holder,
    frame.LevelBucketValues["21-30"] and frame.LevelBucketValues["21-30"].Holder,
    frame.LevelBucketValues["31-40"] and frame.LevelBucketValues["31-40"].Holder,
    frame.LevelBucketValues["41-50"] and frame.LevelBucketValues["41-50"].Holder,
    frame.LevelBucketValues["51-59"] and frame.LevelBucketValues["51-59"].Holder,
    frame.LevelBucketValues["60"] and frame.LevelBucketValues["60"].Holder,
    divider, lastLabel,
    frame.LastName, frame.LastMeta, frame.LastLocation,
    frame.RevengeText, frame.RepoText, frame.CombatText, frame.SyncText,
    frame.PartyButton, frame.ReportButton, frame.ResetButton, frame.OptionsButton,
}

function GT:SetMinimized(minimized)
    minimized = minimized and true or false
    local state = GankUIState()

    -- Preserve the expanded/free-floating position before marking the tracker
    -- minimized; SaveGankPosition intentionally ignores minimized state.
    if minimized and frame:IsShown() then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        if state and (relativeTo == UIParent or relativeTo == nil) then
            state.point = point or state.point or "CENTER"
            state.relativePoint = relativePoint or state.relativePoint or state.point
            state.x = x or state.x or 0
            state.y = y or state.y or 0
        end
    end
    if state then state.minimized = minimized end

    -- "Minimized" now means the full tracker is hidden. The compact K/U/R/DK
    -- summary is rendered directly inside the VoidMark header, so there is no
    -- second frame to dock or drag.
    if minimized then
        frame.CompactText:Hide()
        frame:SetSize(250, 292)
        frame:Hide()
    else
        frame:SetSize(250, 292)
        RestoreGankPosition()
        for _, widget in ipairs(expandedWidgets) do
            if widget then widget:Show() end
        end
        header:SetHeight(56)
        title:SetText("VOIDMARK  •  GANK TRACKER")
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 9, -5)
        frame.CompactText:Hide()
        frame.MinimizeButton.Text:SetText("−")
        frame:Show()
    end

    GT:RefreshVoidMarkCompact()
    UpdateDisplay()
end

function GT:IsMinimized()
    local state = GankUIState()
    return state and state.minimized and true or false
end

function GT:ToggleWindow()
    if frame:IsShown() then
        SaveGankPosition()
        frame.CompactText:Hide()
        frame:SetSize(250, 292)
        frame:Hide()
        local state = GankUIState()
        if state then state.minimized = true end
    else
        local state = GankUIState()
        if state then state.minimized = false end
        frame:SetSize(250, 292)
        RestoreGankPosition()
        for _, widget in ipairs(expandedWidgets) do
            if widget then widget:Show() end
        end
        header:SetHeight(56)
        title:SetText("VOIDMARK  •  GANK TRACKER")
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 9, -5)
        frame.CompactText:Hide()
        frame.MinimizeButton.Text:SetText("−")
        frame:Show()
        UpdateDisplay()
    end
    GT:RefreshVoidMarkCompact()
end

frame.MinimizeButton:SetScript("OnClick", function()
    GT:SetMinimized(true)
end)

-- Always start with the full tracker hidden; the inline VoidMark summary is the
-- compact/minimized presentation.
local initialUIState = GankUIState()
if initialUIState then initialUIState.minimized = true end
frame.CompactText:Hide()
frame:SetSize(250, 292)
frame:Hide()
C_Timer.After(0, function()
    frame:Hide()
    GT:RefreshVoidMarkCompact()
end)

-- Options -------------------------------------------------------------------
local optionsFrame = CreateFrame("Frame", "TaliaaVoidMarkGankOptionsFrame", UIParent, "BackdropTemplate")
GT.OptionsFrame = optionsFrame
optionsFrame:SetSize(350, 355)
optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 535, 120)
optionsFrame:SetFrameStrata("DIALOG")
optionsFrame:SetClampedToScreen(true)
optionsFrame:SetMovable(true)
optionsFrame:EnableMouse(true)
optionsFrame:RegisterForDrag("LeftButton")
optionsFrame:Hide()
ApplyVoidMarkFrame(optionsFrame, VM_BG)
optionsFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
optionsFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

local optHeader = CreateFrame("Frame", nil, optionsFrame, "BackdropTemplate")
optHeader:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 1, -1)
optHeader:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -1, -1)
optHeader:SetHeight(32)
optHeader:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
optHeader:SetBackdropColor(0.045, 0.018, 0.065, 0.98)

local optionsTitle = optHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
optionsTitle:SetPoint("LEFT", optHeader, "LEFT", 10, 0)
optionsTitle:SetText("VOIDMARK  •  GANK OPTIONS")
optionsTitle:SetTextColor(VM_PURPLE_BRIGHT[1], VM_PURPLE_BRIGHT[2], VM_PURPLE_BRIGHT[3], 1)

local optClose = CreateFrame("Button", nil, optHeader)
optClose:SetSize(18, 18)
optClose:SetPoint("RIGHT", optHeader, "RIGHT", -4, 0)
optClose.Text = optClose:CreateFontString(nil, "OVERLAY", "GameFontNormal")
optClose.Text:SetPoint("CENTER")
optClose.Text:SetText("X")
optClose.Text:SetTextColor(1.0, 0.28, 0.38, 1)
optClose:SetScript("OnClick", function() optionsFrame:Hide() end)

local function SectionTitle(textValue, y)
    local fs = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, y)
    fs:SetText(textValue)
    fs:SetTextColor(VM_PURPLE_BRIGHT[1], VM_PURPLE_BRIGHT[2], VM_PURPLE_BRIGHT[3], 1)
    return fs
end

local function HelpText(textValue, y)
    local fs = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, y)
    fs:SetWidth(318)
    fs:SetJustifyH("LEFT")
    fs:SetText(textValue)
    fs:SetTextColor(0.56, 0.49, 0.62, 1)
    return fs
end

local simpleButtons = {}
local RefreshPanicStyle

local function SetSimpleButtonState(button, active)
    if not button then return end
    button._voidMarkActive = active and true or false
    if button._voidMarkActive then
        button:SetBackdropColor(0.16, 0.055, 0.24, 1)
        button:SetBackdropBorderColor(0.76, 0.42, 1.00, 1)
        button.Label:SetTextColor(1.00, 0.90, 1.00, 1)
    else
        button:SetBackdropColor(VM_PANEL[1], VM_PANEL[2], VM_PANEL[3], VM_PANEL[4])
        button:SetBackdropBorderColor(0.30, 0.14, 0.42, 1)
        button.Label:SetTextColor(0.72, 0.64, 0.80, 1)
    end
end

local function MakeSimpleToggle(key, label, x, y, width)
    local b = MakeFlatButton(optionsFrame, label, width, 22)
    b:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", x, y)
    simpleButtons[key] = b
    return b
end

local function MakeVoidMarkCheckbox(key, label, x, y)
    local cb = CreateFrame("CheckButton", nil, optionsFrame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", x, y)

    local text = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    text:SetTextColor(0.82, 0.72, 0.90, 1)

    cb.Label = text
    simpleButtons[key] = cb
    return cb
end

local fixedKillLine = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
fixedKillLine:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -48)
fixedKillLine:SetText("Kill line:  Name  •  Level  •  Today  •  Historical")
fixedKillLine:SetTextColor(0.66, 0.58, 0.72, 1)

-- --------------------------------------------------------------------------
-- REPORT
-- --------------------------------------------------------------------------
SectionTitle("REPORT", -78)
HelpText("REPORT sends the tab you are looking at: TODAY, WEEK, or RECORDS.", -96)

MakeVoidMarkCheckbox("levelBreakdown", "LEVEL BREAKDOWN", 16, -123)

local sendLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sendLabel:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -190)
sendLabel:SetText("Send report to")
sendLabel:SetTextColor(0.56, 0.49, 0.62, 1)

MakeVoidMarkCheckbox("party", "PARTY/RAID", 16, -208)
MakeVoidMarkCheckbox("guild", "GUILD", 112, -208)
MakeVoidMarkCheckbox("whisper", "WHISPER", 184, -208)
MakeVoidMarkCheckbox("say", "SAY", 278, -208)

local whisperLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
whisperLabel:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -244)
whisperLabel:SetText("Whisper target")
whisperLabel:SetTextColor(0.56, 0.49, 0.62, 1)

local whisperEdit = CreateFrame("EditBox", nil, optionsFrame, "InputBoxTemplate")
GT.ReportWhisperEdit = whisperEdit
whisperEdit:SetSize(210, 22)
whisperEdit:SetPoint("LEFT", whisperLabel, "RIGHT", 10, 0)
whisperEdit:SetAutoFocus(false)
whisperEdit:SetMaxLetters(64)
whisperEdit:SetScript("OnEnterPressed", function(self)
    local settings = EnsureReportSettings()
    settings.whisperTarget = NormalizeWhisperTarget(self:GetText())
    self:SetText(settings.whisperTarget)
    self:ClearFocus()
end)
whisperEdit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)
whisperEdit:SetScript("OnEditFocusLost", function(self)
    local settings = EnsureReportSettings()
    settings.whisperTarget = NormalizeWhisperTarget(self:GetText())
    self:SetText(settings.whisperTarget)
end)

-- --------------------------------------------------------------------------
-- ACCOUNT SYNC
-- --------------------------------------------------------------------------
SectionTitle("ACCOUNT SYNC", -283)

local repoStatus = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
repoStatus:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -302)
repoStatus:SetWidth(318)
repoStatus:SetJustifyH("LEFT")
repoStatus:SetTextColor(0.58, 0.51, 0.64, 1)
GT.RepoStatusText = repoStatus

local function UpdateRepoStatus()
    if not GT.RepoStatusText then return end

    if TaliaaGankRepository and TaliaaGankRepository.GetStats then
        local total, victims = TaliaaGankRepository:GetStats()
        local paired, peerID, peerName = TaliaaGankRepository:GetPeerStatus()
        local peer = paired and tostring(peerName or peerID or "paired") or "not paired"
        local syncStatus = TaliaaGankRepository.GetSyncStatus
            and TaliaaGankRepository:GetSyncStatus() or nil

        local suffix = ""
        if syncStatus and syncStatus.syncing then
            local started = tonumber(syncStatus.syncStartedAt) or 0
            local elapsed = 0
            if started > 0 then
                elapsed = math.max(0, DailyNow() - started)
            end
            local queued = tonumber(syncStatus.queueRemaining) or 0
            suffix = "  •  SYNCING " .. tostring(elapsed) .. "s"
            if queued > 0 then
                suffix = suffix .. " (" .. tostring(queued) .. " queued)"
            end
        elseif syncStatus and (tonumber(syncStatus.lastSyncVerified) or 0) > 0 then
            suffix = "  •  SYNCED ✓"
        end

        GT.RepoStatusText:SetText(
            tostring(total or 0) .. " kills / "
            .. tostring(victims or 0) .. " marks  •  " .. peer .. suffix
        )

        if syncButton and syncButton.Label then
            if syncStatus and syncStatus.syncing then
                syncButton.Label:SetText("SYNCING...")
                syncButton:Disable()
            else
                syncButton.Label:SetText("SYNC NOW")
                syncButton:Enable()
            end
        end
    else
        GT.RepoStatusText:SetText("Repository module not loaded")
    end
end

local pairButton = MakeFlatButton(optionsFrame, "PAIR", 70, 21)
pairButton:SetPoint("BOTTOMLEFT", optionsFrame, "BOTTOMLEFT", 12, 10)
pairButton:SetScript("OnClick", function()
    if TaliaaGankRepository and TaliaaGankRepository.StartPairing then
        TaliaaGankRepository:StartPairing()
        C_Timer.After(1, UpdateRepoStatus)
        C_Timer.After(7, UpdateRepoStatus)
    end
end)

syncButton = MakeFlatButton(optionsFrame, "SYNC NOW", 86, 21)
syncButton:SetPoint("LEFT", pairButton, "RIGHT", 6, 0)
syncButton:SetScript("OnClick", function()
    if TaliaaGankRepository and TaliaaGankRepository.SyncNow then
        TaliaaGankRepository:SyncNow(false)
        UpdateRepoStatus()
    end
end)

local closeOptions = MakeFlatButton(optionsFrame, "CLOSE", 60, 21)
closeOptions:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -10, 10)
closeOptions:SetScript("OnClick", function() optionsFrame:Hide() end)

local function RefreshSimpleOptions()
    EnsureAnnounceSettings()
    local report = EnsureReportSettings()

    if simpleButtons.levelBreakdown and simpleButtons.levelBreakdown.SetChecked then
        simpleButtons.levelBreakdown:SetChecked(report.reportStyle == "levels")
    end
    for _, key in ipairs({"party", "guild", "whisper", "say"}) do
        local cb = simpleButtons[key]
        if cb and cb.SetChecked then
            cb:SetChecked(report[key] and true or false)
        end
    end

    if GT.ReportWhisperEdit and not GT.ReportWhisperEdit:HasFocus() then
        GT.ReportWhisperEdit:SetText(tostring(report.whisperTarget or ""))
    end

    UpdateRepoStatus()
end

simpleButtons.levelBreakdown:SetScript("OnClick", function(self)
    local report = EnsureReportSettings()
    report.reportStyle = self:GetChecked() and "levels" or "summary"
    RefreshSimpleOptions()
end)

function GT:IsPanicEnabled()
    return VoidMarkDB and VoidMarkDB.VoidMarkShowPanicButton == true
end

function GT:SetPanicEnabled(enabled)
    enabled = enabled and true or false
    if VoidMarkDB then
        VoidMarkDB.VoidMarkShowPanicButton = enabled
    end

    if enabled then
        -- One-minute grace so the user can position/test Panic with no nearby enemy.
        GT._panicVisibleUntil = GetTime() + 60
    else
        GT._panicVisibleUntil = nil
    end

    if RestorePanicVisibility then
        RestorePanicVisibility()
    elseif GT.PanicFrame then
        if enabled then GT.PanicFrame:Show() else GT.PanicFrame:Hide() end
    end

    RefreshSimpleOptions()
end

function GT:TogglePanicEnabled()
    self:SetPanicEnabled(not self:IsPanicEnabled())
    return self:IsPanicEnabled()
end

for _, key in ipairs({"party", "guild", "whisper", "say"}) do
    simpleButtons[key]:SetScript("OnClick", function(self)
        local report = EnsureReportSettings()
        report[key] = self:GetChecked() and true or false
        RefreshSimpleOptions()
    end)
end

optionsFrame:SetScript("OnShow", function()
    optionsFrame._syncStatusElapsed = 0
    RefreshSimpleOptions()
end)

optionsFrame:SetScript("OnUpdate", function(self, elapsed)
    self._syncStatusElapsed = (tonumber(self._syncStatusElapsed) or 0) + (tonumber(elapsed) or 0)
    if self._syncStatusElapsed >= 0.5 then
        self._syncStatusElapsed = 0
        UpdateRepoStatus()
    end
end)

frame.OptionsButton:SetScript("OnClick", function()
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
    end
end)

-- Panic ---------------------------------------------------------------------
local panicFrame = CreateFrame("Frame", "TaliaaVoidMarkPanicFrame", UIParent, "BackdropTemplate")
GT.PanicFrame = panicFrame
panicFrame:SetSize(118, 34)
panicFrame:SetFrameStrata("DIALOG")
panicFrame:SetClampedToScreen(true)
panicFrame:SetMovable(true)
panicFrame:EnableMouse(true)
ApplyVoidMarkFrame(panicFrame, VM_BG)
panicFrame:SetBackdropBorderColor(0.52, 0.08, 0.16, 1)

local function PanicPositionStore()
    local profile = VoidMark and VoidMark.db and VoidMark.db.profile
    if not profile then return nil end
    profile.VoidMarkPanicPosition = profile.VoidMarkPanicPosition or {}
    return profile.VoidMarkPanicPosition
end

local function SavePanicPosition()
    local store = PanicPositionStore()
    if not store then return end
    local point, _, relativePoint, x, y = panicFrame:GetPoint(1)
    store.point = point or "CENTER"
    store.relativePoint = relativePoint or store.point
    store.x = x or 0
    store.y = y or 0
end

local function RestorePanicPosition()
    local store = PanicPositionStore()
    panicFrame:ClearAllPoints()
    if store and store.x ~= nil and store.y ~= nil then
        panicFrame:SetPoint(store.point or "CENTER", UIParent, store.relativePoint or store.point or "CENTER", store.x, store.y)
    else
        panicFrame:SetPoint("CENTER", UIParent, "CENTER", 320, 25)
    end
end
RestorePanicPosition()

RestorePanicVisibility = function()
    if not GT.PanicFrame then return end

    local enabled = VoidMarkDB and VoidMarkDB.VoidMarkShowPanicButton == true
    if not enabled then
        GT._panicVisibleUntil = nil
        if GT.PanicFrame:IsShown() then GT.PanicFrame:Hide() end
        return
    end

    local now = GetTime()
    local graceActive = GT._panicVisibleUntil and now < GT._panicVisibleUntil

    local nearbyCount = 0
    if VoidMark and VoidMark.GetNearbyListSize then
        nearbyCount = tonumber(VoidMark:GetNearbyListSize()) or 0
    elseif VoidMark and type(VoidMark.NearbyList) == "table" then
        for _ in pairs(VoidMark.NearbyList) do nearbyCount = nearbyCount + 1 end
    end

    local shouldShow = graceActive or nearbyCount > 0
    if shouldShow then
        if not GT.PanicFrame:IsShown() then GT.PanicFrame:Show() end
    else
        if GT.PanicFrame:IsShown() then GT.PanicFrame:Hide() end
    end
end

RestorePanicVisibility()

local function StartPanicDrag()
    GT._panicDragging = true
    panicFrame:StartMoving()
end
local function StopPanicDrag()
    panicFrame:StopMovingOrSizing()
    SavePanicPosition()
    C_Timer.After(0, function() GT._panicDragging = false end)
end

panicFrame:RegisterForDrag("LeftButton")
panicFrame:SetScript("OnDragStart", StartPanicDrag)
panicFrame:SetScript("OnDragStop", StopPanicDrag)

panicFrame.Button = CreateFrame("Button", nil, panicFrame, "BackdropTemplate")
panicFrame.Button:SetPoint("TOPLEFT", panicFrame, "TOPLEFT", 3, -3)
panicFrame.Button:SetPoint("BOTTOMRIGHT", panicFrame, "BOTTOMRIGHT", -3, 3)
panicFrame.Button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
panicFrame.Button:RegisterForClicks("LeftButtonUp")
panicFrame.Button:RegisterForDrag("LeftButton")
panicFrame.Button.Icon = panicFrame.Button:CreateTexture(nil, "ARTWORK")
panicFrame.Button.Icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
panicFrame.Button.Icon:SetSize(24, 24)
panicFrame.Button.Icon:SetPoint("TOP", panicFrame.Button, "TOP", 0, -5)

-- Style artwork is built once and then shown/hidden by RefreshPanicStyle().
-- This keeps the Panic control as one draggable/clickable frame while making
-- each dropdown choice a genuinely different composition instead of a resized
-- rectangle.
panicFrame.Button.StyleDiamond = panicFrame.Button:CreateTexture(nil, "BACKGROUND", nil, -1)
panicFrame.Button.StyleDiamond:SetTexture("Interface\\Buttons\\WHITE8X8")
panicFrame.Button.StyleDiamond:SetSize(47, 47)
panicFrame.Button.StyleDiamond:SetPoint("CENTER")
if panicFrame.Button.StyleDiamond.SetRotation then
    panicFrame.Button.StyleDiamond:SetRotation(math.rad(45))
end

panicFrame.Button.StyleRing = panicFrame.Button:CreateTexture(nil, "BACKGROUND", nil, -1)
panicFrame.Button.StyleRing:SetTexture("Interface\\Buttons\\UI-Quickslot2")
panicFrame.Button.StyleRing:SetSize(66, 66)
panicFrame.Button.StyleRing:SetPoint("CENTER")

panicFrame.Button.StyleRingGlow = panicFrame.Button:CreateTexture(nil, "BACKGROUND", nil, -2)
panicFrame.Button.StyleRingGlow:SetTexture("Interface\\Buttons\\UI-Quickslot2")
panicFrame.Button.StyleRingGlow:SetSize(76, 76)
panicFrame.Button.StyleRingGlow:SetPoint("CENTER")
panicFrame.Button.StyleRingGlow:SetBlendMode("ADD")
panicFrame.Button.StyleRingGlow:SetAlpha(0.32)

panicFrame.Button.BannerLeft = panicFrame.Button:CreateTexture(nil, "BACKGROUND", nil, -1)
panicFrame.Button.BannerLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
panicFrame.Button.BannerLeft:SetSize(18, 18)
if panicFrame.Button.BannerLeft.SetRotation then panicFrame.Button.BannerLeft:SetRotation(math.rad(45)) end

panicFrame.Button.BannerRight = panicFrame.Button:CreateTexture(nil, "BACKGROUND", nil, -1)
panicFrame.Button.BannerRight:SetTexture("Interface\\Buttons\\WHITE8X8")
panicFrame.Button.BannerRight:SetSize(18, 18)
if panicFrame.Button.BannerRight.SetRotation then panicFrame.Button.BannerRight:SetRotation(math.rad(45)) end

panicFrame.Button.VoidGlow = panicFrame.Button:CreateTexture(nil, "BACKGROUND", nil, -2)
panicFrame.Button.VoidGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
panicFrame.Button.VoidGlow:SetPoint("CENTER")
panicFrame.Button.VoidGlow:SetBlendMode("ADD")
panicFrame.Button.VoidGlow:SetAlpha(0.18)

panicFrame.Button.Accent = panicFrame.Button:CreateTexture(nil, "BORDER")
panicFrame.Button.Accent:SetTexture("Interface\\Buttons\\WHITE8X8")
panicFrame.Button.Accent:SetPoint("BOTTOMLEFT", panicFrame.Button, "BOTTOMLEFT", 2, 2)
panicFrame.Button.Accent:SetPoint("BOTTOMRIGHT", panicFrame.Button, "BOTTOMRIGHT", -2, 2)
panicFrame.Button.Accent:SetHeight(2)

panicFrame.Button.Label = panicFrame.Button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panicFrame.Button.Label:SetPoint("CENTER")
panicFrame.Button.Label:SetText("PANIC  •  0")
panicFrame.Button:SetScript("OnDragStart", StartPanicDrag)
panicFrame.Button:SetScript("OnDragStop", StopPanicDrag)
panicFrame.Button:SetScript("OnEnter", function(self)
    -- Keep the custom Panic artwork fully transparent on hover.
    self:SetBackdropColor(0, 0, 0, 0)
    self:SetBackdropBorderColor(0, 0, 0, 0)
    self.Label:SetTextColor(1, 1, 1, 1)
end)
panicFrame.Button:SetScript("OnLeave", function(self)
    if UpdatePanicDisplay then UpdatePanicDisplay() end
end)
panicFrame.Button:SetScript("OnClick", function()
    if GT._panicDragging then return end
    GT:Panic()
end)

local function GetPanicStyle()
    if VoidMarkDB then VoidMarkDB.VoidMarkPanicStyle = "banner" end
    return "banner"
end

RefreshPanicStyle = function()
    if GT.RefreshPanicArt then
        GT:RefreshPanicArt(true)
        return
    end

    local style = GetPanicStyle()

    local button = panicFrame.Button
    button:ClearAllPoints()
    button.Label:ClearAllPoints()
    button.Icon:ClearAllPoints()
    button.Icon:Show()
    button.Accent:Hide()
    button.StyleDiamond:Hide()
    button.StyleRing:Hide()
    button.StyleRingGlow:Hide()
    button.BannerLeft:Hide()
    button.BannerRight:Hide()
    button.VoidGlow:Hide()

    -- Reset to a transparent button; each style opts into only the visual
    -- pieces it actually uses.
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    button:SetBackdropColor(0.035, 0.010, 0.050, 0.96)
    button:SetBackdropBorderColor(0.48, 0.20, 0.68, 1)

    if style == "banner" then
        -- Wide emergency banner: skull badge, single-line copy, pointed ends.
        panicFrame:SetSize(190, 46)
        button:SetPoint("TOPLEFT", panicFrame, "TOPLEFT", 7, -6)
        button:SetPoint("BOTTOMRIGHT", panicFrame, "BOTTOMRIGHT", -7, 6)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 9,
            insets = {left=2,right=2,top=2,bottom=2},
        })
        button.Icon:SetSize(28, 28)
        button.Icon:SetPoint("LEFT", button, "LEFT", 9, 0)
        button.Label:SetPoint("LEFT", button.Icon, "RIGHT", 8, 0)
        button.Label:SetFontObject("GameFontNormal")
        button.Accent:Show()
        button.BannerLeft:ClearAllPoints()
        button.BannerLeft:SetPoint("CENTER", button, "LEFT", 1, 0)
        button.BannerLeft:Show()
        button.BannerRight:ClearAllPoints()
        button.BannerRight:SetPoint("CENTER", button, "RIGHT", -1, 0)
        button.BannerRight:Show()

    elseif style == "diamond" then
        -- Compact rotated diamond plate with the skull centered above the count.
        panicFrame:SetSize(86, 86)
        button:SetPoint("CENTER", panicFrame, "CENTER", 0, 0)
        button:SetSize(70, 70)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left=3,right=3,top=3,bottom=3},
        })
        button:SetBackdropColor(0,0,0,0)
        button:SetBackdropBorderColor(0,0,0,0)
        button.StyleDiamond:Show()
        button.Icon:SetSize(26, 26)
        button.Icon:SetPoint("CENTER", button, "CENTER", 0, 8)
        button.Label:SetPoint("CENTER", button, "CENTER", 0, -17)
        button.Label:SetFontObject("GameFontNormalSmall")

    elseif style == "ring" then
        -- True circular alert badge using Blizzard's quickslot ring artwork.
        panicFrame:SetSize(84, 84)
        button:SetPoint("CENTER", panicFrame, "CENTER", 0, 0)
        button:SetSize(72, 72)
        button:SetBackdropColor(0,0,0,0)
        button:SetBackdropBorderColor(0,0,0,0)
        button.StyleRingGlow:Show()
        button.StyleRing:Show()
        button.Icon:SetSize(27, 27)
        button.Icon:SetPoint("CENTER", button, "CENTER", 0, 8)
        button.Label:SetPoint("CENTER", button, "CENTER", 0, -17)
        button.Label:SetFontObject("GameFontNormalSmall")

    else
        -- Void Skull: tall occult plate, oversized skull and purple void glow.
        panicFrame:SetSize(94, 104)
        button:SetPoint("TOPLEFT", panicFrame, "TOPLEFT", 5, -5)
        button:SetPoint("BOTTOMRIGHT", panicFrame, "BOTTOMRIGHT", -5, 5)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 11,
            insets = {left=3,right=3,top=3,bottom=3},
        })
        button.VoidGlow:ClearAllPoints()
        button.VoidGlow:SetPoint("CENTER", button, "CENTER", 0, -1)
        button.VoidGlow:SetSize(68, 78)
        button.VoidGlow:Show()
        button.Icon:SetSize(39, 39)
        button.Icon:SetPoint("TOP", button, "TOP", 0, -8)
        button.Label:SetPoint("BOTTOM", button, "BOTTOM", 0, 11)
        button.Label:SetFontObject("GameFontNormal")
        button.Accent:Show()
        button.Accent:SetHeight(3)
    end

    ApplyVoidMarkFrame(panicFrame, VM_BG)
    panicFrame:SetBackdropBorderColor(0.52, 0.08, 0.16, 1)
    if UpdatePanicDisplay then UpdatePanicDisplay() end
end
RefreshPanicStyle()

-- Session DHK / streak / revenge monitor ------------------------------------
local combatMonitor = CreateFrame("Frame")
VoidMarkForever.RegisterEvent(combatMonitor,"PLAYER_LOGIN")
VoidMarkForever.RegisterEvent(combatMonitor,"PLAYER_ENTERING_WORLD")
VoidMarkForever.RegisterEvent(combatMonitor,"PLAYER_REGEN_ENABLED")
VoidMarkForever.RegisterEvent(combatMonitor,"CHAT_MSG_COMBAT_HONOR_GAIN")
VoidMarkForever.RegisterEvent(combatMonitor,"CHAT_MSG_COMBAT_MISC_INFO")
VoidMarkForever.RegisterEvent(combatMonitor,"COMBAT_TEXT_UPDATE")
VoidMarkForever.RegisterEvent(combatMonitor,"PLAYER_DEAD")
VoidMarkForever.RegisterEvent(combatMonitor,"COMBAT_LOG_EVENT_UNFILTERED")

-- GetPVPSessionStats() is the authoritative current-character DK total in
-- Classic Era. Poll lightly so VoidMark self-heals even when a chat event is
-- filtered, changed, or never delivered to this addon.
local dhkPollElapsed = 0
combatMonitor:SetScript("OnUpdate", function(_, elapsed)
    dhkPollElapsed = dhkPollElapsed + (tonumber(elapsed) or 0)
    if dhkPollElapsed < 2 then return end
    dhkPollElapsed = 0

    -- Honor/DHK reconciliation is not combat-critical. Keep it entirely off the
    -- combat hot path and reconcile once PLAYER_REGEN_ENABLED fires instead.
    if InCombatLockdown and InCombatLockdown() then return end

    local fixed = ReconcileCurrentCharacterDHKs(true)
    if fixed > 0 then UpdateDisplay() end
end)

local lastHostilePlayer = nil
local recentOutgoingHunterPets = {}
local hunterPetGUIDCache = {}
local combatPlayerGUID = VoidMarkForever.API.UnitGUID("player")

local function IsHostilePlayerControlledPetFlags(flags)
    local band = bit and bit.band
    if not band or not flags then return false end
    local typePet = COMBATLOG_OBJECT_TYPE_PET or 0x00001000
    local controlPlayer = COMBATLOG_OBJECT_CONTROL_PLAYER or 0x00000100
    local hostile = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
    return band(flags, typePet) ~= 0
        and band(flags, controlPlayer) ~= 0
        and band(flags, hostile) ~= 0
end

local function FindVisibleUnitByGUID(guid)
    if not guid then return nil end
    local quick = { "target", "mouseover" }
    for _, unit in ipairs(quick) do
        if VoidMarkForever.API.UnitExists(unit) and VoidMarkForever.API.UnitGUID(unit) == guid then return unit end
    end
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if VoidMarkForever.API.UnitExists(unit) and VoidMarkForever.API.UnitGUID(unit) == guid then return unit end
    end
    return nil
end

local function ConfirmHunterPet(guid, flags)
    if not guid or not IsHostilePlayerControlledPetFlags(flags) then return false end
    if hunterPetGUIDCache[guid] ~= nil then return hunterPetGUIDCache[guid] end

    local unit = FindVisibleUnitByGUID(guid)
    if not unit then return false end

    -- Classic hunter pets are player-controlled Beasts. Restricting the tracker
    -- to Beast pets prevents Warlock demons and other controlled summons from
    -- inflating the Hunter-pet counter.
    local creatureType = VoidMarkForever.API.UnitCreatureType and VoidMarkForever.API.UnitCreatureType(unit) or nil
    local isHunterPet = creatureType == "Beast"
    hunterPetGUIDCache[guid] = isHunterPet and true or false
    return isHunterPet
end

local FEIGN_DEATH_SPELL_ID = 5384
local FEIGN_SUPPRESS_SECONDS = 8.0
local recentFeign = {}
local recentFeignByName = {}

local function NormalizeFeignName(name)
    if not name then return nil end
    local base = VoidMarkForever.DisplayName(name)
    return string.lower(base)
end

IsUnitCurrentlyFeigningName = function(name)
    if not name or not VoidMarkForever.API.UnitIsFeignDeath then return false end
    local function check(unit)
        if not VoidMarkForever.API.UnitExists or not VoidMarkForever.API.UnitExists(unit) then return false end
        local unitName = VoidMarkForever.FullName(unit)
        if not unitName then return false end
        local base = VoidMarkForever.DisplayName(unitName)
        local wanted = VoidMarkForever.DisplayName(name)
        if string.lower(base) ~= string.lower(wanted) then return false end
        local ok, result = pcall(VoidMarkForever.API.UnitIsFeignDeath, unit)
        return ok and result == true
    end
    if check("target") or check("mouseover") then return true end
    for i = 1, 40 do
        if check("nameplate"..i) then return true end
    end
    return false
end

function GT:IsUnitCurrentlyFeigningName(name)
    return IsUnitCurrentlyFeigningName(name)
end

local IsKnownHunter
function GT:ShouldSuppressHunterUnitDied(name, guid)
    if not IsKnownHunter(name, guid) then return false end

    -- PARTY_KILL is authoritative when our group receives credit, but a real
    -- Hunter can also die nearby to somebody outside our group. UNIT_DIED alone
    -- is therefore not proof of Feign Death.
    local confirmedAt = guid and tonumber(recentConfirmedPlayerKills[guid]) or 0
    if confirmedAt > 0 and (GetTime() - confirmedAt) <= 2.0 then return false end

    if self.IsRecentFeign and self:IsRecentFeign(name, guid) then return true end
    return IsUnitCurrentlyFeigningName(name) == true
end

IsKnownHunter = function(name, guid)
    local data = FindPlayerDataForName and FindPlayerDataForName(name) or nil
    local class = data and (data.class or data.Class) or nil
    if not class and VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData then
        local raw = VoidMarkPerCharDB.PlayerData[name]
        class = raw and (raw.class or raw.Class) or nil
    end
    if not class and guid and VoidMarkForever.API.GetPlayerInfoByGUID then
        local _, classFile = VoidMarkForever.API.GetPlayerInfoByGUID(guid)
        class = classFile
    end
    return tostring(class or ""):upper() == "HUNTER"
end
function GT:IsKnownHunter(name, guid)
    return IsKnownHunter(name, guid)
end

MarkHunterFeign = function(guid, name)
    -- If a kill sound raced ahead of Classic's Feign classification, stop it
    -- immediately when Feign is confirmed.
    if VoidMarkKillEffects and VoidMarkKillEffects.StopActiveSound then
        VoidMarkKillEffects:StopActiveSound()
    end

    local now = GetTime()
    if guid then
        recentFeign[guid] = now
        recentOutgoingVictims[guid] = nil
    end
    local key = NormalizeFeignName(name)
    if key then recentFeignByName[key] = now end

    -- One notice per actual Feign activation. SPELL_CAST_SUCCESS and
    -- AURA_APPLIED can both report the same Feign, so suppress duplicates.
    GT._lastFeignNotice = GT._lastFeignNotice or {}
    local noticeKey = guid or key or tostring(name or "Hunter")
    local last = tonumber(GT._lastFeignNotice[noticeKey]) or 0
    if now - last <= 1.0 then return end
    GT._lastFeignNotice[noticeKey] = now

    local short = VoidMarkForever.DisplayName(name or "Hunter")
    local message = short .. " FEIGN"
    -- Normal party only: raid/solo stays private, avoiding unexpected raid spam.
    if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) and SendChatMessage then
        SendChatMessage(message, "PARTY")
    else
        Print(message)
    end

    -- Brief on-screen confirmation so the Feign is obvious even when chat is busy.
    if UIParent and not GT._feignPopup then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(360, 70)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(100)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.text:SetPoint("CENTER")
        f.text:SetFont(STANDARD_TEXT_FONT, 32, "OUTLINE")
        f:Hide()
        GT._feignPopup = f
    end
    local popup = GT._feignPopup
    if popup then
        popup.text:SetText("|cffff2020" .. short .. " FEIGN|r")
        popup:Show()
        if C_Timer and C_Timer.After then
            local token = (popup._token or 0) + 1
            popup._token = token
            C_Timer.After(3.0, function()
                if popup and popup._token == token then popup:Hide() end
            end)
        else
            popup:Hide()
        end
    end
end

local function ClearHunterFeign(guid, name)
    if guid then recentFeign[guid] = nil end
    local key = NormalizeFeignName(name)
    if key then recentFeignByName[key] = nil end
    local popup = GT._feignPopup
    if popup then
        popup._token = (popup._token or 0) + 1
        popup:Hide()
    end
end

local function ConfirmHunterRealDeath(guid, name)
    if not guid then return end
    recentConfirmedPlayerKills[guid] = GetTime()
    -- A genuine kill can race with UNIT_DIED-based Feign detection, especially
    -- when the Hunter dies at range to a DoT. Real kill credit wins: remove any
    -- stale Feign state/popup so the following UNIT_DIED cannot show FEIGN.
    ClearHunterFeign(guid, name)
end

function GT:ConfirmHunterRealDeath(playerGUID, playerName)
    if not IsKnownHunter(playerName, playerGUID) then return false end
    ConfirmHunterRealDeath(playerGUID, playerName)
    GT._pendingHunterDeaths = GT._pendingHunterDeaths or {}
    GT._pendingHunterDeaths[playerGUID] = nil
    return true
end

function GT:HandleHunterUnitDied(playerGUID, playerName)
    if not playerGUID or not IsKnownHunter(playerName, playerGUID) then return false end

    local confirmedAt = tonumber(recentConfirmedPlayerKills[playerGUID]) or 0
    if confirmedAt > 0 and (GetTime() - confirmedAt) <= 2.0 then
        -- PARTY_KILL already proved this was a genuine death.
        ClearHunterFeign(playerGUID, playerName)
        return true
    end

    -- A nearby player outside our party can genuinely kill a Hunter and we will
    -- see UNIT_DIED without receiving PARTY_KILL. Never infer Feign from that
    -- absence alone. Require positive Feign evidence: a recent 5384 event, the
    -- client live-unit state, or the unconscious flag handled by the caller.
    if (GT.IsRecentFeign and GT:IsRecentFeign(playerName, playerGUID))
        or IsUnitCurrentlyFeigningName(playerName) then
        MarkHunterFeign(playerGUID, playerName)
        return true
    end

    return false
end

function GT:HandleHunterFeign(playerGUID, playerName)
    MarkHunterFeign(playerGUID, playerName)
end

function GT:IsRecentFeign(playerName, playerGUID)
    local now = GetTime()
    if playerGUID then
        local t = tonumber(recentFeign[playerGUID])
        if t and now - t <= FEIGN_SUPPRESS_SECONDS then return true end
        if t and now - t > 10 then recentFeign[playerGUID] = nil end
    end
    local key = NormalizeFeignName(playerName)
    if key then
        local t = tonumber(recentFeignByName[key])
        if t and now - t <= FEIGN_SUPPRESS_SECONDS then return true end
        if t and now - t > 10 then recentFeignByName[key] = nil end
    end
    return false
end

local function IsMyGroupCombatSource(flags)
    -- Count damage from this character OR any current party/raid member (and
    -- their player-controlled pets) toward the 30-second grouped kill window.
    -- This closes the gap where a nearby party member got the kill but this
    -- character never personally damaged the victim and PARTY_KILL was absent.
    local band = bit and bit.band
    if not band or not flags then return false end

    local mine = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001
    local party = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002
    local raid = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004
    local controlled = COMBATLOG_OBJECT_CONTROL_PLAYER or 0x00000100
    local affiliations = mine + party + raid

    return band(flags, affiliations) ~= 0 and band(flags, controlled) ~= 0
end

local function IsHostilePlayerFlags(flags, guid)
    -- This function sits on the combat-log hot path. Avoid pcall() and filter
    -- helper overhead on every damage tick; Classic exposes the same information
    -- directly in the source/destination flags.
    if guid and guid ~= "" and not IsPlayerGUID(guid) then
        return false
    end

    local band = bit and bit.band
    if band and flags then
        local typePlayer = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
        local hostile = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
        return band(flags, typePlayer) ~= 0 and band(flags, hostile) ~= 0
    end

    -- Very old/fallback clients only. This should not be reached in Classic Era.
    if CombatLog_Object_IsA and COMBATLOG_FILTER_HOSTILE_PLAYERS then
        return CombatLog_Object_IsA(flags, COMBATLOG_FILTER_HOSTILE_PLAYERS) and true or false
    end
    return false
end

combatMonitor:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        combatPlayerGUID = VoidMarkForever.API.UnitGUID("player") or combatPlayerGUID
        C_Timer.After(0, function()
            RestorePanicVisibility()
            if UpdatePanicDisplay and GT.PanicFrame and GT.PanicFrame:IsShown() then
                UpdatePanicDisplay()
            end
        end)
        if event == "PLAYER_ENTERING_WORLD" then return end
        RefreshSessionDHK()
        C_Timer.After(2, function()
            ReconcileCurrentCharacterDHKs(false)
            UpdateDisplay()
            RestorePanicVisibility()
        end)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- Full UI/history refreshes are intentionally suppressed during combat.
        -- Collapse all deferred sync work into one rebuild the instant combat ends.
        FlushPendingRevengeClaims()
        GT._killDeferredTimerArmed = nil
        if GT._historyRefreshPending then
            GT._historyRefreshPending = nil
            RefreshDailyStats()
            SeedSessionFromHistory()
        end
        GT._dhkRefreshPending = nil
        ReconcileCurrentCharacterDHKs(true)
        UpdateDisplay()
        RestorePanicVisibility()
        return
    end

    if event == "CHAT_MSG_COMBAT_HONOR_GAIN"
        or event == "CHAT_MSG_COMBAT_MISC_INFO" then
        local message = ...
        RecordDishonorableKill(message)
        return
    end

    if event == "COMBAT_TEXT_UPDATE" then
        local combatTextType = ...
        if combatTextType == "HONOR_GAINED" then
            -- The floating-combat-text payload is not consistently descriptive
            -- enough to identify a DHK, so use it only as an immediate trigger to
            -- query Blizzard's authoritative DK count.
            C_Timer.After(0.2, function()
                if InCombatLockdown and InCombatLockdown() then
                    GT._dhkRefreshPending = true
                    return
                end
                local fixed = ReconcileCurrentCharacterDHKs(true)
                if fixed > 0 then UpdateDisplay() end
            end)
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, payload1, payload2, payload3, payload4, payload5 =
            VoidMarkForever.API.CombatLogGetCurrentEventInfo()

        -- Personal Rogue safety alert: only fire when Sap actually lands on us.
        -- This runs before the normal CLEU fast-return because aura events are
        -- otherwise intentionally ignored by GankTracker's hot path.
        if (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH")
            and SAP_SPELL_IDS[tonumber(payload1)]
            and destGUID == (combatPlayerGUID or VoidMarkForever.API.UnitGUID("player")) then
            ShowSapAlert(sourceName)
        end

        -- End the warning as soon as Classic exposes Feign ending. Also treat
        -- a subsequent action by that same Hunter as proof they broke Feign
        -- (for example standing up to cast/drop a trap) rather than waiting the
        -- full five-second visual timeout.
        if subEvent == "SPELL_AURA_REMOVED" and tonumber(payload1) == FEIGN_DEATH_SPELL_ID then
            ClearHunterFeign(destGUID or sourceGUID, destName or sourceName)
        elseif sourceGUID and recentFeign[sourceGUID]
            and subEvent ~= "UNIT_DIED" and subEvent ~= "PARTY_KILL"
            and not ((subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_AURA_APPLIED")
                and tonumber(payload1) == FEIGN_DEATH_SPELL_ID) then
            ClearHunterFeign(sourceGUID, sourceName)
        end

        -- Feign Death may have no destination on SPELL_CAST_SUCCESS, so use the
        -- source hunter there and the destination on AURA_APPLIED. This must run
        -- before the normal CLEU fast-return below.
        if (subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_AURA_APPLIED")
            and tonumber(payload1) == FEIGN_DEATH_SPELL_ID then
            local feignGUID = destGUID or sourceGUID
            local feignName = destName or sourceName
            MarkHunterFeign(feignGUID, feignName)
            if feignGUID then recentOutgoingVictims[feignGUID] = nil end
            return
        end

        local isDamageEvent = (subEvent == "SWING_DAMAGE"
            or subEvent == "RANGE_DAMAGE"
            or subEvent == "SPELL_DAMAGE"
            or subEvent == "SPELL_PERIODIC_DAMAGE"
            or subEvent == "DAMAGE_SHIELD"
            or subEvent == "DAMAGE_SPLIT"
            or subEvent == "SPELL_INSTAKILL")

        -- Most CLEU traffic is irrelevant to GankTracker. Return before GUID,
        -- flag and table work for heals, energize, aura spam, casts, misses, etc.
        if not isDamageEvent and subEvent ~= "PARTY_KILL" and subEvent ~= "UNIT_DIED" then
            return
        end

        local playerGUID = combatPlayerGUID or VoidMarkForever.API.UnitGUID("player")
        combatPlayerGUID = playerGUID

        -- Existing revenge tracking: hostile player damaged us. Reuse the same
        -- table rather than allocating a fresh one on every swing/DoT tick; the
        -- old behavior generated unnecessary garbage during sustained combat.
        if destGUID and destGUID == playerGUID
            and sourceGUID and sourceName
            and IsHostilePlayerFlags(sourceFlags, sourceGUID)
            and isDamageEvent then

            lastHostilePlayer = lastHostilePlayer or {}
            lastHostilePlayer.name = sourceName
            lastHostilePlayer.guid = sourceGUID
            lastHostilePlayer.t = GetTime()
        end

        -- Hunter-pet tracker. Keep this completely separate from player ganks.
        -- We only track hostile, player-controlled Beast pets that this character
        -- actually damaged, so Warlock demons/guardians/NPCs are excluded.
        if sourceGUID == playerGUID
            and destGUID and destName
            and isDamageEvent
            and IsHostilePlayerControlledPetFlags(destFlags) then

            local confirmed = ConfirmHunterPet(destGUID, destFlags)
            if confirmed then
                local pet = recentOutgoingHunterPets[destGUID]
                if not pet then
                    pet = {}
                    recentOutgoingHunterPets[destGUID] = pet
                end
                pet.name = destName
                pet.guid = destGUID
                pet.t = GetTime()
            end
        end

        -- Independent grouped-kill fallback. VoidMark.lua normally calls GT:RecordKill(),
        -- and PARTY_KILL is preferred when Blizzard sends it. Also retain recent
        -- damage from this character or a nearby party/raid member (including their
        -- player-controlled pets) so UNIT_DIED can award the grouped kill within
        -- the existing 30-second window even when PARTY_KILL is absent.
        -- Reuse per-victim records to avoid combat-time table churn/GC spikes.
        if IsMyGroupCombatSource(sourceFlags)
            and destGUID and destName
            and IsHostilePlayerFlags(destFlags, destGUID)
            and isDamageEvent then

            local tracked = recentOutgoingVictims[destGUID]
            if not tracked then
                tracked = {}
                recentOutgoingVictims[destGUID] = tracked
            end
            tracked.name = destName
            tracked.guid = destGUID
            tracked.t = GetTime()
        end

        -- Feign Death is represented by the combat-log "unconsciousOnDeath"
        -- flag on PARTY_KILL/UNIT_DIED. It can arrive before either normal kill
        -- path, so suppress it here before any RecordKill() call.
        if subEvent == "PARTY_KILL"
            and destGUID and destName and IsPlayerGUID(destGUID)
            and (payload5 == 1 or payload5 == true or payload5 == "1") then
            MarkHunterFeign(destGUID, destName)
            recentOutgoingVictims[destGUID] = nil
            return
        end

        if subEvent == "UNIT_DIED"
            and destGUID and destName and IsPlayerGUID(destGUID)
            and IsKnownHunter(destName, destGUID) then
            -- UNIT_DIED alone is ambiguous: real deaths caused by players outside
            -- our group also arrive without PARTY_KILL. Only stop here when we
            -- have positive Feign evidence. Otherwise let the normal death/assist
            -- fallback below evaluate the event.
            if GT:HandleHunterUnitDied(destGUID, destName) then
                recentOutgoingVictims[destGUID] = nil
                return
            end
        end

        if subEvent == "UNIT_DIED"
            and destGUID and destName and IsPlayerGUID(destGUID)
            and (payload2 == 1 or payload2 == true or payload2 == "1") then
            MarkHunterFeign(destGUID, destName)
            recentOutgoingVictims[destGUID] = nil
            return
        end

        -- Hunter pet kill credit. PARTY_KILL is authoritative when this character
        -- is the killer. Never route pet deaths through RecordKill().
        if subEvent == "PARTY_KILL"
            and sourceGUID == playerGUID
            and destGUID and destName
            and not IsPlayerGUID(destGUID)
            and IsHostilePlayerControlledPetFlags(destFlags) then

            local trackedPet = recentOutgoingHunterPets[destGUID]
            if (trackedPet and (GetTime() - (tonumber(trackedPet.t) or 0)) <= 30)
                or ConfirmHunterPet(destGUID, destFlags) then
                if RecordHunterPetKill(destName, destGUID) then
                    UpdateDisplay()
                end
            end
            recentOutgoingHunterPets[destGUID] = nil
            return
        end

        -- Strongest signal when available: our party received kill credit.
        if subEvent == "PARTY_KILL"
            and destGUID and destName
            and IsPlayerGUID(destGUID)
            and IsHostilePlayerFlags(destFlags, destGUID) then

            -- On this Classic Era client, a real Hunter death produces PARTY_KILL
            -- immediately before UNIT_DIED, while Feign produces UNIT_DIED alone.
            -- Remember the authoritative real-kill signal so the following
            -- UNIT_DIED is not mistaken for Feign.
            ConfirmHunterRealDeath(destGUID, destName)
            GT:RecordKill(destName, destGUID, sourceGUID == playerGUID)
            recentOutgoingVictims[destGUID] = nil
            return
        end

        -- Classic reports Hunter Feign Death as UNIT_DIED traffic, but the death
        -- payload includes the unconscious/Feign flag. This is the authoritative
        -- signal for hostile Hunters: no SPELL_AURA_APPLIED is guaranteed for an
        -- enemy Feign, so trying to detect it only from the spell event misses it.
        -- payload1 is the recap id; payload2 is the unconscious-on-death flag.
        if subEvent == "SPELL_INSTAKILL" and destGUID and destName and IsPlayerGUID(destGUID)
            and (payload5 == true or payload5 == 1 or payload5 == "1") then
            MarkHunterFeign(destGUID, destName)
            recentOutgoingVictims[destGUID] = nil
            return
        end

        if subEvent == "UNIT_DIED" and destGUID and destName and IsPlayerGUID(destGUID)
            and (payload2 == true or payload2 == 1 or payload2 == "1") then
            MarkHunterFeign(destGUID, destName)
            recentOutgoingVictims[destGUID] = nil
            return
        end

        -- Hunter-pet DoT/fallback death when PARTY_KILL is absent.
        if subEvent == "UNIT_DIED" and destGUID and destName and not IsPlayerGUID(destGUID) then
            local pet = recentOutgoingHunterPets[destGUID]
            if pet and (GetTime() - (tonumber(pet.t) or 0)) <= 30 then
                if RecordHunterPetKill(destName, destGUID) then
                    UpdateDisplay()
                end
            end
            recentOutgoingHunterPets[destGUID] = nil
        end

        -- Catch DoT/group-assist deaths where PARTY_KILL is absent but this
        -- character or a party/raid member damaged that hostile player recently.
        if subEvent == "UNIT_DIED" and destGUID and destName and IsPlayerGUID(destGUID) then
            local tracked = recentOutgoingVictims[destGUID]
            if not GT:IsRecentFeign(destName, destGUID) and not IsUnitCurrentlyFeigningName(destName)
                and tracked and (GetTime() - (tonumber(tracked.t) or 0)) <= 30 then
                GT:RecordKill(destName, destGUID)
            end
            recentOutgoingVictims[destGUID] = nil
        end

        return
    end

    if event == "PLAYER_DEAD" then
        if IgnoreBattlegroundStats() then
            return
        end
        RecordPlayerDeathTimestamp()
        local endedStreak = tonumber(GT.currentStreak) or 0
        if GT.partyAnnounce and endedStreak >= 5 then
            local endedMessage = BuildStreakEndMessage(endedStreak)
            if endedMessage then
                C_Timer.After(0.05, function() SafeGroupMessage(endedMessage) end)
            end
        end

        if VoidMarkKillEffects and VoidMarkKillEffects.OnPlayerDeath then
            VoidMarkKillEffects:OnPlayerDeath()
        end
        SetStreak(0)

        if lastHostilePlayer and (GetTime() - (tonumber(lastHostilePlayer.t) or 0)) <= 20 then
            AddRevengeTarget(lastHostilePlayer.name, lastHostilePlayer.guid)
        end

        lastHostilePlayer = nil
        if InCombatLockdown and InCombatLockdown() then
            GT._displayRefreshPending = true
        else
            UpdateDisplay()
        end
    end
end)

UpdateDisplay()

local lastTransientCleanup = 0
local function PruneTransientCombatState(now)
    if now-lastTransientCleanup < 30 then return end
    lastTransientCleanup = now
    local function PruneTimes(tbl, age)
        for key, stamp in pairs(tbl) do
            if now-stamp > age then tbl[key]=nil end
        end
    end
    PruneTimes(GT.recentKillEvents, 30)
    PruneTimes(GT.recentHunterPetKills, 30)
    PruneTimes(recentConfirmedPlayerKills, 30)
    PruneTimes(recentFeign, 30)
    PruneTimes(recentFeignByName, 30)
    PruneTimes(recentRemoteSapAlerts, 30)
    for guid, victim in pairs(recentOutgoingVictims) do
        if now-(victim.t or 0) > 30 then recentOutgoingVictims[guid]=nil end
    end
    for guid, pet in pairs(recentOutgoingHunterPets) do
        if now-(pet.t or 0) > 30 then recentOutgoingHunterPets[guid]=nil end
    end
    for guid in pairs(hunterPetGUIDCache) do
        if not recentOutgoingHunterPets[guid] then hunterPetGUIDCache[guid]=nil end
    end
end

local refreshTicker = C_Timer.NewTicker(1, function()
    -- Run cache maintenance outside combat, even with all windows closed.
    if not (InCombatLockdown and InCombatLockdown()) then
        PruneTransientCombatState(GetTime())
    end
    if RestorePanicVisibility then
        RestorePanicVisibility()
    end

    if GT.Frame and GT.Frame:IsShown() then
        -- Keep the combat log hot path as quiet as possible. Kill/DHK callbacks
        -- already push immediate updates, and PLAYER_REGEN_ENABLED repaints once
        -- combat ends. During combat only the tiny panic count needs a heartbeat.
        if InCombatLockdown and InCombatLockdown() then
            if GT.PanicFrame and GT.PanicFrame:IsShown() and UpdatePanicDisplay then
                UpdatePanicDisplay()
            end
            return
        end
        UpdateDisplay()
    elseif GT.PanicFrame and GT.PanicFrame:IsShown() and UpdatePanicDisplay then
        UpdatePanicDisplay()
    end
end)

SLASH_TALIAAGANK1 = "/tgank"
SlashCmdList["TALIAAGANK"] = function(msg)
    local raw = tostring(msg or "")
    local cmd, rest = raw:match("^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")
    rest = rest or ""

    if cmd == "build" or cmd == "version" then
        Print("GankTracker build: " .. GANKTRACKER_BUILD)
        Print("Level report format: [1-30] {star} N • [31-59] {star} N • [60] {star} N")
    elseif cmd == "reset" then
        GT:Reset()
    elseif cmd == "sessionreset" or cmd == "sessreset" then
        ResetSessionStats()
        GT.recentKillEvents = {}
        UpdateDisplay()
        Print("Local streak/revenge session reset. Shared 08:00 Session/Today and lifetime history were not changed.")
    elseif cmd == "party" then
        GT.partyAnnounce = not GT.partyAnnounce
        UpdateDisplay()
        Print("Party announcements: " .. (GT.partyAnnounce and "ON" or "OFF"))
    elseif cmd == "report" then
        GT:ReportCurrentHunt()
    elseif cmd == "reportboth" then
        GT:ReportToParty()
    elseif cmd == "stats" or cmd == "stat" then
        PrintTodayAndWeeklyStats()
    elseif cmd == "today" or cmd == "daily" then
        PrintTodayStats()
    elseif cmd == "week" or cmd == "weekly" then
        PrintWeeklyStats()
    elseif cmd == "records" or cmd == "record" or cmd == "best" then
        local stats, ok = BuildRecordStats()
        if not ok then
            Print("RECORDS: repository history is not loaded.")
        else
            Print("RECORDS: " .. tostring(stats.total or 0) .. " lifetime kills"
                .. " | " .. tostring(stats.marks or 0) .. " unique marks"
                .. " | best week " .. tostring(stats.bestWeek or 0)
                .. " (" .. ShortDate(stats.bestWeekStart)
                .. " - " .. ShortDate((stats.bestWeekEnd or 0) - 1) .. ")"
                .. " | current week " .. tostring(stats.currentWeek or 0))
        end
    elseif cmd == "pets" or cmd == "petkills" then
        Print("Hunter pet kills: Today " .. tostring(HunterPetKillToday())
            .. " | Week " .. tostring(HunterPetKillWeekly())
            .. " | Lifetime " .. tostring(HunterPetKillTotal()))
    elseif cmd == "revenge" then
        local count, newest = RevengeCountAndNewest()
        if count == 0 then
            Print("Revenge list: empty.")
        else
            Print("Revenge marks: " .. tostring(count) .. (newest and (" | newest: " .. tostring(newest.name)) or ""))
        end
    elseif cmd == "streak" then
        Print("Streak: " .. tostring(GT.currentStreak or 0) .. " | Best session: " .. tostring(GT.bestStreak or 0))
    elseif cmd == "dhk" then
        ReconcileCurrentCharacterDHKs(true)

        local today, weekly, lifetime = GetDHKCounts()
        local blizzard = GetBlizzardTodayDHKs()
        local repoCharacter = GetRepoCharacterDHKsToday()
        local paired = TaliaaGankRepository and TaliaaGankRepository.GetPeerStatus
            and select(1, TaliaaGankRepository:GetPeerStatus())

        Print("DHKs: Account Today " .. tostring(today)
            .. " | Week " .. tostring(weekly)
            .. " | Life " .. tostring(lifetime)
            .. " | " .. tostring(SessionKey())
            .. " Blizzard " .. tostring(blizzard or "?")
            .. " / Repo " .. tostring(repoCharacter)
            .. " | Sync " .. (paired and "paired" or "not paired"))
    elseif cmd == "unknown" then
        levelLookup.dirty = true
        RebuildLevelLookup(true)
        RefreshDailyStats()
        local now = DailyNow()
        local dayStart = DailyRealmDayStart(now)
        local history = DailyHistory()
        local found = 0
        if history and type(history.events) == "table" then
            for _, event in pairs(history.events) do
                local eventTime = tonumber(event and event.t) or 0
                if eventTime >= dayStart and eventTime <= (now + 60) then
                    if not ResolveEventLevel(event) then
                        found = found + 1
                        Print("Unknown level: " .. BasePlayerName(event.name or "?")
                            .. " | GUID " .. tostring(event.guid or "")
                            .. " | " .. tostring(event.zone or "Unknown"))
                    end
                end
            end
        end
        if found == 0 then
            Print("No unresolved level rows today.")
        else
            Print("Unresolved level rows today: " .. tostring(found) .. ".")
        end
        RefreshDailyStats()
        UpdateDisplay()
    elseif cmd == "weekdebug" then
        local stats, ok = BuildWeeklyStats()
        Print("Weekly source: " .. (ok and "merged repository" or "unavailable")
            .. " | start " .. tostring(stats and stats.startTime or 0)
            .. " | total " .. tostring(stats and stats.total or 0)
            .. " | today " .. tostring(GT.totalKills or 0))
    elseif cmd == "panictest" then
        local count = tonumber(rest) or 4
        count = math.max(0, math.min(20, math.floor(count)))
        if GT.PanicFrame then
            GT.PanicFrame:Show()
            if UpdatePanicDisplay then UpdatePanicDisplay(count) end
            Print("Panic preview: " .. tostring(count) .. " threats. No chat sent and no history changed.")
        end
    elseif cmd == "panicstyle" then
        Print("Panic style is fixed to Banner.")
    elseif cmd == "panic" then
        GT:Panic()
    elseif cmd == "options" or cmd == "opt" then
        if GT.OptionsFrame:IsShown() then
            GT.OptionsFrame:Hide()
        else
            GT.OptionsFrame:Show()
        end
    elseif cmd == "pair" then
        if TaliaaGankRepository and TaliaaGankRepository.StartPairing then
            TaliaaGankRepository:StartPairing()
        end
    elseif cmd == "unpair" then
        if TaliaaGankRepository and TaliaaGankRepository.Unpair then
            TaliaaGankRepository:Unpair()
        end
    elseif cmd == "sync" then
        if TaliaaGankRepository and TaliaaGankRepository.SyncNow then
            TaliaaGankRepository:SyncNow(false)
        end
    elseif cmd == "fullsync" then
        if TaliaaGankRepository and TaliaaGankRepository.FullSyncNow then
            TaliaaGankRepository:FullSyncNow(false)
        else
            Print("Full sync is unavailable in this GankRepository.lua.")
        end
    elseif cmd == "repo" or cmd == "history" then
        if not TaliaaGankRepository then
            Print("Repository object is not loaded.")
        elseif rest == "rebuild" then
            if TaliaaGankRepository.RebuildIndexes then
                local total, recovered = TaliaaGankRepository:RebuildIndexes()
                Print("Repository rebuilt: " .. tostring(total or 0)
                    .. " event rows | recovered " .. tostring(recovered or 0) .. ".")
                RefreshDailyStats()
                UpdateDisplay()
            else
                Print("Repository rebuild function is unavailable in this GankRepository.lua.")
            end
        elseif rest ~= "" and TaliaaGankRepository.GetHistoricalCount then
            local lookupName = rest
            local lookupGUID = nil
            if string.lower(rest) == "target" then
                lookupName = VoidMarkForever.API.UnitName("target")
                lookupGUID = VoidMarkForever.API.UnitGUID("target")
                if not lookupName then
                    Print("No target selected.")
                    return
                end
            end

            local total = TaliaaGankRepository:GetHistoricalCount(lookupName, lookupGUID) or 0
            Print(BasePlayerName(lookupName) .. ": " .. tostring(total) .. " historical ganks.")

            if TaliaaGankRepository.GetHistoricalBreakdown then
                local repairedTotal, eventRows, spyWins, unresolved, legacyGap, floor, repoAtCapture, spyKey, spyMethod =
                    TaliaaGankRepository:GetHistoricalBreakdown(lookupName, lookupGUID)
                Print("History source: total " .. tostring(repairedTotal or 0)
                    .. " | repo " .. tostring(eventRows or 0)
                    .. " | legacy gap " .. tostring(legacyGap or 0)
                    .. " | VoidMark wins " .. tostring(spyWins or 0)
                    .. " | legacy extra " .. tostring(unresolved or 0)
                    .. " | floor " .. tostring(floor or 0)
                    .. " @ repo " .. tostring(repoAtCapture or 0) .. ".")
                if spyKey or spyMethod then
                    Print("VoidMark identity: " .. tostring(spyKey or "no match")
                        .. " (" .. tostring(spyMethod or "none") .. ").")
                end
            end
        else
            local indexed, victims = 0, 0
            if TaliaaGankRepository.GetStats then
                indexed, victims = TaliaaGankRepository:GetStats()
            end
            local raw = indexed
            if TaliaaGankRepository.GetRawEventCount then
                raw = TaliaaGankRepository:GetRawEventCount()
            end

            local weekly = BuildWeeklyStats()
            local marker = VoidMarkDB and VoidMarkDB.TaliaaGankOfflineSync
            local fileMerged = type(marker) == "table" and tonumber(marker.merged) or 0
            local recoveryCount, recoveryUnresolved = 0, 0
            if TaliaaGankRepository.GetRecoveryLedgerStats then
                recoveryCount, recoveryUnresolved = TaliaaGankRepository:GetRecoveryLedgerStats()
            end

            Print("Repository: RAW " .. tostring(raw or 0)
                .. " | LIFE " .. tostring(indexed or 0)
                .. " | victims " .. tostring(victims or 0)
                .. " | WEEK " .. tostring(weekly and weekly.total or 0)
                .. " | TODAY " .. tostring(GT.totalKills or 0)
                .. " | FILE " .. tostring(fileMerged or 0)
                .. " | REC " .. tostring(recoveryCount or 0) .. ".")

            if (tonumber(recoveryUnresolved) or 0) > 0 then
                Print("Legacy unresolved: " .. tostring(recoveryUnresolved)
                    .. " kills exist only as aggregate counts and have no usable timestamps.")
            end

            if TaliaaGankRepository.GetBuild then
                Print("Repository build: " .. tostring(TaliaaGankRepository:GetBuild()))
            end

            if TaliaaGankRepository.GetSyncStatus then
                local status = TaliaaGankRepository:GetSyncStatus()
                if status and status.paired then
                    Print("Peer: connected via " .. BasePlayerName(status.peerName or status.peerID or "peer") .. ".")
                elseif status and status.pairing then
                    Print("Peer: pairing.")
                else
                    Print("Peer: offline/not connected.")
                end
            end

            if (tonumber(recoveryCount) or 0) > raw then
                Print("WARNING: recovery ledger has " .. tostring(recoveryCount)
                    .. " events, but repository loaded only " .. tostring(raw)
                    .. ". Run /tgank repo rebuild once.")
            elseif fileMerged > 0 and raw < fileMerged then
                Print("WARNING: offline merge marker says " .. tostring(fileMerged)
                    .. " events, but repository loaded only " .. tostring(raw)
                    .. ". Build the recovery ledger with the v5 BAT.")
            end
        end
    elseif cmd == "perf" then
        PrintKillPerf()
    elseif cmd == "show" then
        frame:Show()
        panicFrame:Show()
    elseif cmd == "hide" then
        frame:Hide()
        panicFrame:Hide()
    else
        PrintTodayAndWeeklyStats()
        local lifetime = 0
        if TaliaaGankRepository and TaliaaGankRepository.GetStats then
            lifetime = select(1, TaliaaGankRepository:GetStats()) or 0
        end
        Print("Today: " .. GT.totalKills
            .. " | Session: " .. tostring(GT.sessionKills or 0)
            .. " | Lifetime: " .. tostring(lifetime)
            .. " | Unique today: " .. GT.uniqueKills
            .. " | Repeats today: " .. (GT.totalKills - GT.uniqueKills)
            .. " | Hunter pets today: " .. tostring(HunterPetKillToday())
            .. " | Party: " .. (GT.partyAnnounce and "ON" or "OFF"))
        if TaliaaGankRepository and TaliaaGankRepository.PrintStatus then
            TaliaaGankRepository:PrintStatus()
        end
        Print("Commands: /tgank build | stats | today | weekly | records | pets | unknown | report | revenge | streak | dhk | options | reset | sessionreset | party | panic | pair | sync | fullsync | repo [name|target|rebuild] | reportdebug | perf | show | hide")
    end
end

-- Client adapters enter the same feature writers as combat-log consumers.
function GT:RecordHunterPetKill(name,guid) return RecordHunterPetKill(name,guid) end
function GT:HandleSapAlert(name) return ShowSapAlert(name) end
