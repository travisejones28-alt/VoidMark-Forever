-- VoidMark Gank Tracker
local GANKTRACKER_BUILD = "2026-09-15 HISTORICAL-IDENTITY-2-PERF89-DEATHFRAME"
-- Daily combined kill tracker + reload-safe local session + global historical repository.
-- Daily victim announcement count fix build: 2026-08-25

TaliaaGankTracker = TaliaaGankTracker or {}
local GT = TaliaaGankTracker
local VOIDMARK_GANK_BUILD = "2026-09-03-stable-local-session"

GT.totalKills = GT.totalKills or 0
GT.uniqueKills = GT.uniqueKills or 0
GT.victims = GT.victims or {}
if VoidMarkDB and VoidMarkDB.TaliaaGankPartyAnnounce ~= nil then
    GT.partyAnnounce = VoidMarkDB.TaliaaGankPartyAnnounce and true or false
else
    GT.partyAnnounce = GT.partyAnnounce or false
end
GT.seenEnemies = GT.seenEnemies or {}
GT.recentKillEvents = GT.recentKillEvents or {}
GT._pendingRevengeClaims = GT._pendingRevengeClaims or {}

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

local PANIC_LEVEL = 60
local PANIC_WINDOW_SECONDS = 30

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
    if VoidMarkForever and VoidMarkForever.IsForever then
        return s
    end
    return s:match("^([^-]+)") or s
end

local function DisplayPlayerName(name)
    if VoidMarkForever and VoidMarkForever.DisplayName then
        return VoidMarkForever.DisplayName(name)
    end
    return BasePlayerName(name)
end

local function CurrentPlayerIdentity()
    if VoidMark and VoidMark.PlayerName then
        local ok, full = pcall(VoidMark.PlayerName, VoidMark, "player")
        if ok and type(full) == "string" and full ~= "" then return full end
    end
    return tostring(UnitName("player") or "")
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
    voidmarkFull = {},
    voidmarkBase = {},
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

    local voidmarkFull, voidmarkBase = {}, {}
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
                    voidmarkFull[full] = data
                end

                local base = NormalizedPlayerName(key)
                if base ~= "" then
                    if voidmarkBase[base] == nil then
                        voidmarkBase[base] = data
                    elseif voidmarkBase[base] ~= data then
                        voidmarkBase[base] = false -- ambiguous base name
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

    levelLookup.voidmarkFull = voidmarkFull
    levelLookup.voidmarkBase = voidmarkBase
    levelLookup.repoFull = repoFull
    levelLookup.repoBase = repoBase
    levelLookup.repoGUID = repoGUID
    levelLookup.lastBuild = now
    levelLookup.dirty = false
end

local function FindPlayerDataForName(playerName)
    local full = string.lower(tostring(playerName or ""))
    local data = levelLookup.voidmarkFull[full]
    if data then return data end

    local base = NormalizedPlayerName(playerName)
    data = levelLookup.voidmarkBase[base]
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

local recordStatsCache = {
    eventCount = -1,
    stats = nil,
}

-- PERFORMANCE: the tracker UI refreshes once per second. Weekly totals only
-- change when the repository event generation changes or the weekly reset
-- boundary changes, so never rescan thousands of historical rows every tick.
local weeklyStatsCache = {
    eventCount = -1,
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

    if recordStatsCache.stats and recordStatsCache.eventCount == eventCount then
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

    local now = DailyNow()
    local currentWeekStart = WeeklyResetStart(now)
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
    if weeklyStatsCache.stats
        and weeklyStatsCache.eventCount == eventCount
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
    weeklyStatsCache.weekStart = weekStart
    weeklyStatsCache.stats = stats
    return stats, true
end

local function DailyFaction()
    if VoidMark and VoidMark.FactionName and VoidMark.FactionName ~= "" then
        return VoidMark.FactionName
    end
    return UnitFactionGroup("player") or "Unknown"
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
    return tostring(UnitName("player") or "?") .. "-" .. tostring(GetRealmName and GetRealmName() or "?")
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

    local me = string.lower(CurrentPlayerIdentity())
    local startAt = tonumber(session.startedAt) or DailyRealmDayStart(DailyNow())
    local count = 0
    local victims = {}

    for _, event in pairs(history.events) do
        local killer = string.lower(tostring(event and event.killer or ""))
        if not (VoidMarkForever and VoidMarkForever.IsForever) then
            killer = killer:match("^([^-]+)") or killer
        end
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
        C_Timer.After(1.0, function()
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
    local recent60 = GT:GetRecentEnemyCount(PANIC_WINDOW_SECONDS)
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
            GT.Frame.NearbyValue:SetText(tostring(recent60))
            if GT.Frame.NearbyValue.Caption then GT.Frame.NearbyValue.Caption:SetText("60s / 30s") end
        end
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
                .. "  •  SESS " .. tostring(GT.sessionKills or 0)
            )
            if GT.Frame.CombatText then
                GT.Frame.CombatText:SetText(
                    "STREAK " .. tostring(GT.currentStreak or 0) .. "/" .. tostring(GT.bestStreak or 0)
                    .. "  •  DHK T" .. tostring(dhkToday)
                    .. " W" .. tostring(dhkWeekly)
                    .. " L" .. tostring(dhkLifetime)
                )
            end
        else
            GT.Frame.RepoText:SetText("LIFE repository offline")
            if GT.Frame.CombatText then
                GT.Frame.CombatText:SetText(
                    "STREAK " .. tostring(GT.currentStreak or 0) .. "/" .. tostring(GT.bestStreak or 0)
                    .. "  •  DHK T" .. tostring(dhkToday)
                    .. " W" .. tostring(dhkWeekly)
                    .. " L" .. tostring(dhkLifetime)
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
        local parts = {}

        if TaliaaGankRepository and TaliaaGankRepository.GetSyncStatus then
            local status = TaliaaGankRepository:GetSyncStatus()
            if status.paired then
                local live = "LIVE ● " .. BasePlayerName(status.peerName or status.peerID or "peer")
                local lastRx = (tonumber(status.lastReceive) or 0) > 0 and status.lastReceive or status.lastPeerSeen
                local age = FormatAge(lastRx)
                if age then live = live .. " " .. age end
                parts[#parts + 1] = live
            elseif status.pairing then
                parts[#parts + 1] = "LIVE ◐ pairing"
            else
                parts[#parts + 1] = "LIVE ○ offline"
            end
        else
            parts[#parts + 1] = "LIVE ?"
        end

        local marker = VoidMarkDB and VoidMarkDB.TaliaaGankOfflineSync
        if type(marker) == "table" and tonumber(marker.t) then
            local fileAge = FormatAge(marker.t)
            local fileText = "FILE " .. tostring(fileAge or "?")
            local merged = tonumber(marker.merged)
            if merged then
                fileText = fileText .. " " .. tostring(merged)
                local loaded = 0
                if TaliaaGankRepository and TaliaaGankRepository.GetStats then
                    loaded = tonumber((select(1, TaliaaGankRepository:GetStats()))) or 0
                end
                if loaded > 0 and merged > loaded then
                    fileText = fileText .. " > LIFE " .. tostring(loaded)
                end
            end
            parts[#parts + 1] = fileText
        else
            parts[#parts + 1] = "FILE --"
        end

        GT.Frame.SyncText:SetText(table.concat(parts, "  •  "))
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

    if UpdatePanicDisplay then
        UpdatePanicDisplay(recent60)
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
    local pf = GT.PanicFrame
    local button = pf and pf.Button
    local label = button and button.Label
    if not label then return end

    local recent60 = forcedCount
    if recent60 == nil then
        recent60 = GT:GetRecentEnemyCount(PANIC_WINDOW_SECONDS)
    end

    label:SetText("PANIC  •  " .. tostring(recent60 or 0))
    if recent60 and recent60 >= 3 then
        button:SetBackdropColor(0.50, 0.025, 0.045, 0.98)
        label:SetTextColor(1.0, 0.92, 0.92, 1)
    elseif recent60 and recent60 >= 1 then
        button:SetBackdropColor(0.34, 0.025, 0.070, 0.98)
        label:SetTextColor(1.0, 0.58, 0.68, 1)
    else
        button:SetBackdropColor(0.16, 0.020, 0.040, 0.96)
        label:SetTextColor(0.78, 0.46, 0.56, 1)
    end
end

function GT:NoteEnemySeen(playerName, timestamp, source)
    if not playerName or playerName == "" then
        return
    end

    -- Only count enemies detected by this client.
    -- Ignore detections received from another VoidMark user.
    if source and source ~= VoidMark.CharacterName then
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

function GT:GetRecentEnemyCount(seconds)
    local window = seconds or 30
    local cutoff = time() - window
    local count = 0

    for playerName, data in pairs(self.seenEnemies) do
        local seenAt
        local level

        if type(data) == "table" then
            seenAt = data.seenAt
            level = tonumber(data.level)

            if not level then
                local seenData = FindPlayerDataForName(playerName)
                level = seenData and tonumber(seenData.level) or nil
                data.level = level
            end
        else
            seenAt = data
            local seenData = FindPlayerDataForName(playerName)
            level = seenData and tonumber(seenData.level) or nil
        end

        if seenAt and seenAt >= cutoff then
            if level and level == PANIC_LEVEL then
                count = count + 1
            end
        else
            self.seenEnemies[playerName] = nil
        end
    end

    return count
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
            .. "  •  " .. tostring(stats.marks or 0) .. " unique marks",
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
            "TODAY {star}%d kills  •  Unique %d  •  Repeat %d  •  DHK %d",
            total, unique, repeats, tonumber(dhkToday) or 0
        ),
    }

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
            "WEEK {star}%d kills  •  Unique %d  •  Repeat %d  •  DHK %d",
            tonumber(stats.total) or 0,
            tonumber(stats.unique) or 0,
            tonumber(stats.repeats) or 0,
            tonumber(dhkWeekly) or 0
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
    local subZone = GetSubZoneText() or ""
    if subZone ~= "" then return subZone end
    return GetZoneText() or "Unknown"
end

function GT:Panic()
    local nearby = self:GetRecentEnemyCount(PANIC_WINDOW_SECONDS)
    local location = PanicLocation()
    local message

    if nearby and nearby > 0 then
        message = string.format("HELP! %s - %dx 60 nearby!", location, nearby)
    else
        message = string.format("HELP! %s!", location)
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
    if not history or type(history.events) ~= "table" then
        return GetVictimKillCount(playerName)
    end

    local now = DailyNow()
    local dayStart = DailyRealmDayStart(now)
    local count = 0

    for _, event in pairs(history.events) do
        if type(event) == "table" then
            local eventTime = tonumber(event.t) or 0
            if eventTime >= dayStart and eventTime <= (now + 60)
                and SameVictimIdentity(event.name, event.guid, playerName, playerGUID) then
                count = count + 1
            end
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

local function BuildKillAnnouncement(playerName, playerGUID, playerLevel, playerClass, location, historicalKills, todayVictimKills)
    local displayName = DisplayPlayerName(playerName or "?")

    -- "Session" is this victim's merged account-wide count in the current
    -- 08:00-to-08:00 hunt window. GetTodayVictimKillCount() is built from the
    -- shared repository, so kills from every character/account are included
    -- after sync instead of being stuck in a character-local session table.
    local sessionVictimKills = tonumber(todayVictimKills) or 0
    if sessionVictimKills < 1 then
        sessionVictimKills = 1
    end

    return string.format(
        "%s L%s | Session %dx | Historical %dx",
        displayName,
        tostring(playerLevel or "?"),
        sessionVictimKills,
        tonumber(historicalKills) or 0
    )
end

function GT:RecordKill(playerName, playerGUID)
    if not playerName or playerName == "" then return end

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
    local lastEvent = self.recentKillEvents[dedupeKey] or 0
    if now - lastEvent < 6 then
        return
    end
    self.recentKillEvents[dedupeKey] = now

    local zone = GetZoneText() or "Unknown"
    local subZone = GetSubZoneText() or ""
    local location = CurrentLocation()
    local playerLevel, playerClass = GetPlayerDetails(playerName, playerGUID)
    local historicalKills = 0
    local repositoryAdded = nil

    if TaliaaGankRepository and TaliaaGankRepository.RecordKill then
        historicalKills, repositoryAdded = TaliaaGankRepository:RecordKill(playerName, playerGUID, {
            zone = zone,
            subZone = subZone,
            level = playerLevel,
            class = playerClass,
            killer = UnitName("player") or "?",
        })
        historicalKills = tonumber(historicalKills) or 0
    end

    -- New repository builds return false when the second account/another callback
    -- already recorded this same death. Do not double-increment the local UI.
    if repositoryAdded == false then
        return
    end

    -- Session streak bookkeeping is only advanced after the repository accepts
    -- the death (or when running without the repository for compatibility).
    AddSessionKill(playerName)

    -- PERFORMANCE: update today's in-memory counters directly. The old path
    -- walked the entire 2k+ event repository multiple times at the instant of a
    -- kill, which is exactly when combat responsiveness matters most.
    local todayVictimKills = ApplyLocalKillToDailyStats(
        playerName, playerGUID, playerLevel, zone, subZone, location, historicalKills
    )

    levelLookup.dirty = true

    -- v8.9: do not call chat/network APIs from inside the combat-log death
    -- callback. Queue the already-built message for a few hundredths of a second
    -- later so the death frame can return to the client immediately.
    if self.partyAnnounce then
        local killMessage = BuildKillAnnouncement(
            playerName, playerGUID, playerLevel, playerClass, location, historicalKills, todayVictimKills
        )
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function() SafeGroupMessage(killMessage) end)
        else
            SafeGroupMessage(killMessage)
        end
    end

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
            GT._displayRefreshPending = nil
            UpdateDisplay()
        end)
    end
end

function GT:OnHistoryUpdated(playerName, playerGUID, historicalKills)
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
    holder:SetSize(54, 38)
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
local frame = CreateFrame("Frame", "VoidMarkGankTrackerFrame", UIParent, "BackdropTemplate")
GT.Frame = frame

frame:SetSize(250, 292)
frame:SetPoint("CENTER", UIParent, "CENTER", 320, 120)
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
ApplyVoidMarkFrame(frame, VM_BG)

local function GankUIState()
    if not VoidMarkDB then return nil end
    VoidMarkDB.TaliaaGankUI = VoidMarkDB.TaliaaGankUI or {}
    return VoidMarkDB.TaliaaGankUI
end

local function SaveGankPosition()
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
frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)

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
    GameTooltip:AddLine("Tracking continues in compact mode.", 0.85, 0.85, 0.85)
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

frame.TotalValue = MakeStat(frame, 10, "KILLS")
frame.UniqueValue = MakeStat(frame, 69, "UNIQUE")
frame.DupeValue = MakeStat(frame, 128, "REPEATS")
frame.NearbyValue = MakeStat(frame, 187, "60s / 30s")

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

local lastLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
    if state then state.minimized = minimized end

    for _, widget in ipairs(expandedWidgets) do
        if widget then
            if minimized then widget:Hide() else widget:Show() end
        end
    end

    if minimized then
        frame:SetSize(310, 32)
        header:SetHeight(30)
        title:SetText("VOIDMARK")
        title:ClearAllPoints()
        title:SetPoint("LEFT", header, "LEFT", 9, 0)

        frame.CompactText:ClearAllPoints()
        frame.CompactText:SetPoint("LEFT", header, "LEFT", 92, 0)
        frame.CompactText:SetPoint("RIGHT", frame.MinimizeButton, "LEFT", -8, 0)
        frame.CompactText:SetJustifyH("LEFT")
        frame.CompactText:Show()
        frame.MinimizeButton.Text:SetText("+")
    else
        frame:SetSize(250, 292)
        header:SetHeight(56)
        title:SetText("VOIDMARK  •  GANK TRACKER")
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 9, -5)
        frame.CompactText:Hide()
        frame.MinimizeButton.Text:SetText("−")
    end

    UpdateDisplay()
end

function GT:IsMinimized()
    local state = GankUIState()
    return state and state.minimized and true or false
end

function GT:ToggleWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        UpdateDisplay()
    end
end

frame.MinimizeButton:SetScript("OnClick", function()
    GT:SetMinimized(not GT:IsMinimized())
end)

local initialUIState = GankUIState()
if initialUIState and initialUIState.minimized then
    C_Timer.After(0, function() GT:SetMinimized(true) end)
end

-- Options -------------------------------------------------------------------
local optionsFrame = CreateFrame("Frame", "VoidMarkGankOptionsFrame", UIParent, "BackdropTemplate")
GT.OptionsFrame = optionsFrame
optionsFrame:SetSize(350, 325)
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
fixedKillLine:SetText("Kill line:  Name  •  Level  •  Session  •  Historical")
fixedKillLine:SetTextColor(0.66, 0.58, 0.72, 1)

-- --------------------------------------------------------------------------
-- REPORT
-- --------------------------------------------------------------------------
SectionTitle("REPORT", -78)
HelpText("REPORT sends the tab you are looking at: TODAY, WEEK, or RECORDS.", -96)

MakeVoidMarkCheckbox("levelBreakdown", "LEVEL BREAKDOWN", 16, -123)

local sendLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sendLabel:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -160)
sendLabel:SetText("Send report to")
sendLabel:SetTextColor(0.56, 0.49, 0.62, 1)

MakeVoidMarkCheckbox("party", "PARTY/RAID", 16, -178)
MakeVoidMarkCheckbox("guild", "GUILD", 112, -178)
MakeVoidMarkCheckbox("whisper", "WHISPER", 184, -178)
MakeVoidMarkCheckbox("say", "SAY", 278, -178)

local whisperLabel = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
whisperLabel:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -214)
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
SectionTitle("ACCOUNT SYNC", -253)

local repoStatus = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
repoStatus:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 16, -272)
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

local syncButton = MakeFlatButton(optionsFrame, "SYNC NOW", 86, 21)
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
local panicFrame = CreateFrame("Frame", "VoidMarkPanicFrame", UIParent, "BackdropTemplate")
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
panicFrame.Button.Label = panicFrame.Button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panicFrame.Button.Label:SetPoint("CENTER")
panicFrame.Button.Label:SetText("PANIC  •  0")
panicFrame.Button:SetScript("OnDragStart", StartPanicDrag)
panicFrame.Button:SetScript("OnDragStop", StopPanicDrag)
panicFrame.Button:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.43, 0.035, 0.08, 1)
    self.Label:SetTextColor(1, 1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("VoidMark Panic", 0.88, 0.56, 1.0)
    GameTooltip:AddLine("Click: send a short HELP call with your location and nearby level-60 count.", 0.88, 0.88, 0.92, true)
    GameTooltip:AddLine("Drag: move this button.", 0.68, 0.62, 0.72)
    GameTooltip:Show()
end)
panicFrame.Button:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    if UpdatePanicDisplay then UpdatePanicDisplay() end
end)
panicFrame.Button:SetScript("OnClick", function()
    if GT._panicDragging then return end
    GT:Panic()
end)

-- Session DHK / streak / revenge monitor ------------------------------------
local combatMonitor = CreateFrame("Frame")
combatMonitor:RegisterEvent("PLAYER_LOGIN")
combatMonitor:RegisterEvent("PLAYER_ENTERING_WORLD")
combatMonitor:RegisterEvent("PLAYER_REGEN_ENABLED")
combatMonitor:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")
combatMonitor:RegisterEvent("CHAT_MSG_COMBAT_MISC_INFO")
combatMonitor:RegisterEvent("COMBAT_TEXT_UPDATE")
combatMonitor:RegisterEvent("PLAYER_DEAD")
do
    local _, _, _, interfaceVersion = GetBuildInfo()
    if tonumber(interfaceVersion) == 16001 then
        combatMonitor:RegisterEvent("PARTY_KILL")
    else
        combatMonitor:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

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
local recentOutgoingVictims = {}
local combatPlayerGUID = UnitGUID("player")

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
        combatPlayerGUID = UnitGUID("player") or combatPlayerGUID
        if event == "PLAYER_ENTERING_WORLD" then return end
        RefreshSessionDHK()
        C_Timer.After(2, function()
            ReconcileCurrentCharacterDHKs(false)
            UpdateDisplay()
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

    if event == "PARTY_KILL" then
        local attackerGUID, targetGUID = ...
        if not IsPlayerGUID(targetGUID) then return end

        local targetName = nil
        if VoidMarkForever and VoidMarkForever.ResolvePlayerNameByGUID then
            targetName = VoidMarkForever.ResolvePlayerNameByGUID(targetGUID)
        end
        if not targetName and GetPlayerInfoByGUID then
            local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, targetGUID)
            if ok and name and (not canaccessvalue or canaccessvalue(name)) then
                targetName = name
                if realm and realm ~= "" and (not canaccessvalue or canaccessvalue(realm)) then
                    targetName = name .. "-" .. realm
                end
            end
        end
        if not targetName then return end

        local known = VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData and VoidMarkPerCharDB.PlayerData[targetName]
        if not known and not (VoidMarkForever and VoidMarkForever.IsForever) then
            local base = tostring(targetName):match("^[^-]+")
            known = base and VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData and VoidMarkPerCharDB.PlayerData[base]
        end
        if known and known.isEnemy == false then return end

        GT:RecordKill(targetName, targetGUID)
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags =
            CombatLogGetCurrentEventInfo()

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

        local playerGUID = combatPlayerGUID or UnitGUID("player")
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

        -- Independent gank fallback. VoidMark.lua normally calls GT:RecordKill(), but
        -- retain recent outgoing player damage here so a missed/broken VoidMark callback
        -- cannot leave Gank Tracker at zero while VoidMark W/L continues updating.
        -- Reuse per-victim records to avoid combat-time table churn/GC spikes.
        if sourceGUID == playerGUID
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

        -- Strongest signal when available: our party received kill credit.
        if subEvent == "PARTY_KILL"
            and destGUID and destName
            and IsPlayerGUID(destGUID)
            and IsHostilePlayerFlags(destFlags, destGUID) then

            GT:RecordKill(destName, destGUID)
            recentOutgoingVictims[destGUID] = nil
            return
        end

        -- Catch DoT/assist deaths where PARTY_KILL is absent but we recently
        -- damaged that hostile player.
        if subEvent == "UNIT_DIED" and destGUID and destName and IsPlayerGUID(destGUID) then
            local tracked = recentOutgoingVictims[destGUID]
            if tracked and (GetTime() - (tonumber(tracked.t) or 0)) <= 30 then
                GT:RecordKill(destName, destGUID)
            end
            recentOutgoingVictims[destGUID] = nil
        end

        return
    end

    if event == "PLAYER_DEAD" then
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

local refreshTicker = C_Timer.NewTicker(1, function()
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
                lookupName = UnitName("target")
                lookupGUID = UnitGUID("target")
                if not lookupName then
                    Print("No target selected.")
                    return
                end
            end

            local total = TaliaaGankRepository:GetHistoricalCount(lookupName, lookupGUID) or 0
            Print(BasePlayerName(lookupName) .. ": " .. tostring(total) .. " historical ganks.")

            if TaliaaGankRepository.GetHistoricalBreakdown then
                local repairedTotal, eventRows, voidmarkWins, unresolved, legacyGap, floor, repoAtCapture, voidmarkKey, voidmarkMethod =
                    TaliaaGankRepository:GetHistoricalBreakdown(lookupName, lookupGUID)
                Print("History source: total " .. tostring(repairedTotal or 0)
                    .. " | repo " .. tostring(eventRows or 0)
                    .. " | legacy gap " .. tostring(legacyGap or 0)
                    .. " | VoidMark wins " .. tostring(voidmarkWins or 0)
                    .. " | legacy extra " .. tostring(unresolved or 0)
                    .. " | floor " .. tostring(floor or 0)
                    .. " @ repo " .. tostring(repoAtCapture or 0) .. ".")
                if voidmarkKey or voidmarkMethod then
                    Print("VoidMark identity: " .. tostring(voidmarkKey or "no match")
                        .. " (" .. tostring(voidmarkMethod or "none") .. ").")
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
            .. " | Party: " .. (GT.partyAnnounce and "ON" or "OFF"))
        if TaliaaGankRepository and TaliaaGankRepository.PrintStatus then
            TaliaaGankRepository:PrintStatus()
        end
        Print("Commands: /tgank build | stats | today | weekly | records | unknown | report | revenge | streak | dhk | options | reset | sessionreset | party | panic | pair | sync | fullsync | repo [name|target|rebuild] | reportdebug | show | hide")
    end
end
