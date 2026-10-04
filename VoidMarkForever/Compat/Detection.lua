local VMAPI = VoidMarkForever.API
-- VoidMark Forever compatibility layer
-- Target: WoW Forever beta 1.60.1 / Interface 16001
-- Keeps the mature VoidMark backend/UI but replaces Era combat-log detection with
-- visible-unit detection and standalone Forever kill/death APIs.

VoidMarkForever = VoidMarkForever or {}
local VMF = VoidMarkForever

local _, _, _, interfaceVersion = GetBuildInfo()
VMF.IsForever = tonumber(interfaceVersion) == 16001
VMF.Interface = tonumber(interfaceVersion) or 0
VMF.GUIDToName = VMF.GUIDToName or {}
VMF.NameToGUID = VMF.NameToGUID or {}
VMF.LastSeen = VMF.LastSeen or {}
VMF.Build = "1.0.0"

if not VMF.IsForever then
    return
end

-- Match the known-working Forever VoidMark port here: only true secret values are
-- unreadable. canaccessvalue() is deliberately NOT used for detection because on
-- Forever it can reject ordinary unit-return values that VoidMark can safely inspect.
local function CanAccess(value)
    if VMF.Readable(value) == nil then return false end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok and secret then return false end
    end
    return true
end
VMF.CanAccess = CanAccess

function VoidMark:IsSecret(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and secret == true
    end
    return false
end

function VoidMark:Readable(value)
    return VMF.Readable(value)
end

function VoidMark:GetZonePVPInfo()
    if C_PvP and C_PvP.GetZonePVPInfo then
        return VoidMark:Readable(C_PvP.GetZonePVPInfo())
    end
    if VMAPI.GetZonePVPInfo then
        return VoidMark:Readable(VMAPI.GetZonePVPInfo())
    end
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if not ok then return nil end
    return VMF.Readable(a), VMF.Readable(b), VMF.Readable(c), VMF.Readable(d), VMF.Readable(e), VMF.Readable(f), VMF.Readable(g)
end

local function SafeString(value)
    value = VoidMark:Readable(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

local function NormalizeName(name)
    name = SafeString(name)
    if not name then return nil end
    return name:gsub(" %- ", "-")
end

local function CacheIdentity(unit, name)
    local guid = VoidMark:Readable(SafeCall(VMAPI.UnitGUID, unit))
    if type(guid) ~= "string" or guid == "" then return end
    VMF.GUIDToName[guid] = name
    VMF.NameToGUID[name] = guid
    VMF.LastSeen[guid] = GetTime()
end

function VMF.ResolvePlayerNameByGUID(guid)
    guid = VoidMark:Readable(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local cached = VMF.GUIDToName[guid]
    if cached then return cached end

    if VMAPI.GetPlayerInfoByGUID then
        local _, _, _, _, _, name, realm = SafeCall(VMAPI.GetPlayerInfoByGUID, guid)
        name = SafeString(name)
        realm = SafeString(realm)
        if name then
            local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
            VMF.GUIDToName[guid] = full
            VMF.NameToGUID[full] = guid
            return full
        end
    end
    return nil
end

local function KnownPlayerData(name)
    if not name or not VoidMarkPerCharDB or not VoidMarkPerCharDB.PlayerData then return nil end
    -- Forever identities are the full Main-Secondary pair. Never fall back to
    -- first-name-only lookup: multiple players can legitimately share it.
    return VoidMarkPerCharDB.PlayerData[name]
end

-- Forever exposes the secondary name in the same second VMAPI.UnitName return slot
-- historically used for realm names. Internally VoidMark keeps Main-Secondary
-- because it is compact and unique; player-facing UI/slash targeting uses
-- "Main Secondary".
function VMF.DisplayName(name)
    local s = tostring(name or "")
    if s == "" then return s end
    local first, second = s:match("^([^-]+)%-(.+)$")
    if first and second and second ~= "" then
        return first .. " " .. second
    end
    return s
end

function VMF.TargetName(name)
    return VMF.DisplayName(name)
end

function VMF.SamePlayer(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

function VMF.FindVisibleUnit(name)
    if not name or not VoidMark or not VoidMark.PlayerName then return nil end
    local preferred = { "target", "mouseover", "focus" }
    for _, unit in ipairs(preferred) do
        local ok, unitName = pcall(VoidMark.PlayerName, VoidMark, unit)
        if ok and unitName == name then return unit end
    end
    for unit in pairs(VoidMark.NamePlateUnits or {}) do
        local ok, unitName = pcall(VoidMark.PlayerName, VoidMark, unit)
        if ok and unitName == name then return unit end
    end
    return nil
end

-- Same name reader used by the known-working VoidMark Forever port. VMAPI.UnitName() is used
-- instead of GetUnitName(); realm is appended only when the client actually supplies it.
function VoidMark:PlayerName(unit)
    if not VoidMark:Readable(SafeCall(VMAPI.UnitExists, unit)) or not VoidMark:Readable(SafeCall(VMAPI.UnitIsPlayer, unit)) then
        return nil
    end
    local name, realm = SafeCall(VMAPI.UnitName, unit)
    name = VoidMark:Readable(name)
    realm = VoidMark:Readable(realm)
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then
        return nil
    end
    if type(realm) == "string" and realm ~= "" then
        name = name .. "-" .. realm
    end
    return NormalizeName(name)
end

function VoidMark:EnemyPlayerName(unit)
    local name = VoidMark:PlayerName(unit)
    if name and VoidMark:Readable(SafeCall(VMAPI.UnitIsEnemy, "player", unit)) then
        return name
    end
    return nil
end

local function PlayerLevel(unit, playerData)
    local level = tonumber(VoidMark:Readable(SafeCall(VMAPI.UnitLevel, unit)))
    local guess = false
    if level == VoidMark.Skull then
        local playerLevel = tonumber(VoidMark:Readable(SafeCall(VMAPI.UnitLevel, "player"))) or 1
        if playerData and tonumber(playerData.level) then
            if tonumber(playerData.level) > (playerLevel + 10) and tonumber(playerData.level) < (VoidMark.MaximumPlayerLevel or 60) then
                guess = true
                level = nil
            elseif playerLevel < ((VoidMark.MaximumPlayerLevel or 60) - 9) then
                guess = true
                level = playerLevel + 10
            end
        else
            guess = true
            level = playerLevel + 10
        end
    end
    return level, guess
end

VMF.Stats = VMF.Stats or { scans = 0, detections = 0 }
VoidMark.NamePlateUnits = VoidMark.NamePlateUnits or {}

-- Detection core intentionally mirrors VoidMark (Forever): read an actual unit token,
-- update the player record, then feed the normal Nearby/Active list path.
function VoidMark:ScanUnit(unit)
    if type(unit) ~= "string" or unit == "" then return nil end

    local name = VoidMark:PlayerName(unit)
    if not name or (VoidMarkPerCharDB and VoidMarkPerCharDB.IgnoreData and VoidMarkPerCharDB.IgnoreData[name]) then
        return nil
    end

    VMF.Stats.scans = (VMF.Stats.scans or 0) + 1
    CacheIdentity(unit,name)
    VMF.LastDetection=VMF.LastDetection or {}
    local seen=VMF.LastDetection[name]
    if seen and GetTime()-seen<10 then return name end
    VMF.LastDetection[name]=GetTime()
    local playerData = KnownPlayerData(name)
    local isEnemy = VoidMark:Readable(SafeCall(VMAPI.UnitIsEnemy, "player", unit))

    if isEnemy then
        local learnt = true
        if playerData and playerData.isGuess == false then learnt = false end

        local _, class = SafeCall(VMAPI.UnitClass, unit)
        class = VoidMark:Readable(class)
        if type(class) ~= "string" then class = nil end

        local race = VoidMark:Readable(SafeCall(VMAPI.UnitRace, unit))
        if type(race) ~= "string" then race = nil end

        local level, guess = PlayerLevel(unit, playerData)

        local guild = VoidMark:Readable(SafeCall(VMAPI.GetGuildInfo, unit))
        if type(guild) ~= "string" then guild = nil end

        local faction = VoidMark:Readable(SafeCall(VMAPI.UnitFactionGroup, unit))
        if type(faction) ~= "string" then faction = nil end

        CacheIdentity(unit, name)
        VoidMark:UpdatePlayerData(name, class, level, race, guild, faction, true, guess, nil)
        if VoidMark.EnabledInZone then
            VoidMark:AddDetected(name, time(), learnt)
            VMF.Stats.detections = (VMF.Stats.detections or 0) + 1
        end
        return name
    elseif isEnemy == false and playerData then
        VoidMark:RemovePlayerData(name)
    end
    return nil
end

VMF.ScanUnit = function(unit)
    return VoidMark:ScanUnit(unit)
end

-- Keep the actual nameplate tokens supplied by Blizzard, exactly as the working
-- Forever port does. This is more reliable than guessing nameplate1..nameplate40.
function VoidMark:NamePlateEvent(event, unit)
    if type(unit) ~= "string" then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        VoidMark.NamePlateUnits[unit] = true
        VoidMark:ScanUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        VoidMark.NamePlateUnits[unit] = nil
    end
end

function VoidMark:ScanVisibleUnits()
    if not VoidMark.EnabledInZone then return end

    for unit in pairs(VoidMark.NamePlateUnits) do
        if VoidMark:Readable(SafeCall(VMAPI.UnitExists, unit)) then
            VoidMark:ScanUnit(unit)
        else
            VoidMark.NamePlateUnits[unit] = nil
        end
    end

    -- Target/focus are always worth rescanning. Mouseover is also included as an
    -- extra VoidMark convenience; UPDATE_MOUSEOVER_UNIT still fires immediately.
    VoidMark:ScanUnit("target")
    VoidMark:ScanUnit("focus")
    VoidMark:ScanUnit("mouseover")
end

VMF.ScanVisibleUnits = function()
    return VoidMark:ScanVisibleUnits()
end

function VoidMark:StartUnitScan()
    if not VoidMark.UnitScanTimer then
        VoidMark.UnitScanTimer = VoidMark:ScheduleRepeatingTimer("ScanVisibleUnits", 1.0)
    end
end

function VoidMark:StopUnitScan()
    if VoidMark.UnitScanTimer then
        VoidMark:CancelTimer(VoidMark.UnitScanTimer)
        VoidMark.UnitScanTimer = nil
    end
end

function VoidMark:PlayerTargetEvent()
    VoidMark:ScanUnit("target")
end

function VoidMark:PlayerMouseoverEvent()
    VoidMark:ScanUnit("mouseover")
end

function VoidMark:PlayerFocusEvent()
    VoidMark:ScanUnit("focus")
end

function VoidMark:ForeverVisibleScan()
    VoidMark:ScanVisibleUnits()
end

local stealthByID = {
    [1784] = "Stealth",
    [5215] = "Prowl",
    [1856] = "Vanish",
    [1857] = "Vanish",
}

local function HandleForeverSpellcast(unit, spellID)
    -- Forever can supply spellID/castGUID as secret values. A secret value may not
    -- be compared, concatenated, converted into a normal lookup key, or used to
    -- index a Lua table. Detect the caster first, then discard an unreadable ID.
    if type(unit) ~= "string" or unit == "" then return end

    local name = VMF.ScanUnit(unit)
    if not name then return end

    spellID = VoidMark:Readable(spellID)
    if type(spellID) ~= "number" then return end

    local kind = stealthByID[spellID]
    if not kind then return end

    if kind == "Prowl" then
        if VoidMark.PromoteStealthPlayer then VoidMark:PromoteStealthPlayer(name, time(), "Prowl") end
        if VoidMark.AlertProwlPlayer then VoidMark:AlertProwlPlayer(name) end
    else
        if VoidMark.PromoteStealthPlayer then VoidMark:PromoteStealthPlayer(name, time(), kind) end
        if VoidMark.AlertStealthPlayer then VoidMark:AlertStealthPlayer(name) end
    end
end

function VoidMark:ForeverSpellcastEvent(event, unit, castGUID, spellID)
    local ok, err = pcall(HandleForeverSpellcast, unit, spellID)
    if not ok then
        VMF.LastSpellcastError = tostring(err)
    end
end

function VoidMark:ForeverPartyKillEvent(event, attackerGUID, targetGUID, unconscious)
    return VoidMarkForever.HandlePartyKill(attackerGUID,targetGUID,unconscious)
end

local function FlattenRecapEvents(value, out, depth)
    if depth > 3 or type(value) ~= "table" then return end
    if VMF.Readable(value.sourceGUID) or VMF.Readable(value.sourceName) then
        out[#out + 1] = value
        return
    end
    for _, child in pairs(value) do
        if type(child) == "table" then
            FlattenRecapEvents(child, out, depth + 1)
        end
    end
end

function VMF.ReadDeathRecapKiller()
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return nil, nil end
    local events = SafeCall(C_DeathRecap.GetRecapEvents)
    if type(events) ~= "table" then return nil, nil end

    local flat = {}
    FlattenRecapEvents(events, flat, 0)
    local bestName, bestGUID, bestTime = nil, nil, -math.huge
    for _, info in ipairs(flat) do
        local guid = VMF.Readable(info.sourceGUID)
        local name = VMF.Readable(info.sourceName)
        if CanAccess(guid) and CanAccess(name) and type(guid) == "string" and guid:sub(1, 6) == "Player" and type(name) == "string" then
            local ts = tonumber(VMF.Readable(info.timestamp)) or 0
            if ts >= bestTime then
                bestTime = ts
                bestGUID = guid
                bestName = NormalizeName(name)
            end
        end
    end
    return bestName, bestGUID
end

function VoidMark:PlayerDeadEvent(...)
    C_Timer.After(0.15,function()
        local name,guid=VMF.ReadDeathRecapKiller()
        if name and guid and VMF.RecordLoss then VMF.RecordLoss(name,guid) end
    end)
end

-- Forever port: do not register COMBAT_LOG_EVENT_UNFILTERED. The currently known
-- working VoidMark port for 1.60.1 uses nameplates/target/focus/mouseover + PARTY_KILL.
function VoidMark:OnEnable(first)
    -- Match the working Forever VoidMark registration set.
    if VoidMark.timeid then VoidMark:CancelTimer(VoidMark.timeid) end
    VoidMark.timeid = VoidMark:ScheduleRepeatingTimer("ManageExpirations", 10, true)

    VoidMarkForever.RegisterEvent(VoidMark,"ZONE_CHANGED", "ZoneChangedEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"ZONE_CHANGED_INDOORS", "ZoneChangedEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"ZONE_CHANGED_NEW_AREA", "ZoneChangedNewAreaEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"PLAYER_ENTERING_WORLD", "PlayerEnteringWorldEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"UNIT_FACTION", "ZoneChangedEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"PLAYER_TARGET_CHANGED", "PlayerTargetEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"PLAYER_FOCUS_CHANGED", "PlayerFocusEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"UPDATE_MOUSEOVER_UNIT", "PlayerMouseoverEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"UNIT_PET", "UnitPets")
    VoidMarkForever.RegisterEvent(VoidMark,"PLAYER_REGEN_ENABLED", "LeftCombatEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"PLAYER_DEAD", "PlayerDeadEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"CHAT_MSG_CHANNEL_NOTICE", "ChannelNoticeEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"NAME_PLATE_UNIT_ADDED", "NamePlateEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"NAME_PLATE_UNIT_REMOVED", "NamePlateEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"UNIT_SPELLCAST_SUCCEEDED", "ForeverSpellcastEvent")
    VoidMarkForever.RegisterEvent(VoidMark,"PARTY_KILL", "ForeverPartyKillEvent")

    if VoidMark.RegisterComm and VoidMark.Signature then
        pcall(VoidMark.RegisterComm, VoidMark, VoidMark.Signature, "CommReceived")
    end

    if VMF.StartEvents then VMF.StartEvents() end
    VoidMark:StartUnitScan()
    VoidMark.IsEnabled = true

    C_Timer.After(0.5, function()
        -- Force the same zone-state initialization before the first manual target/nameplate test.
        if VoidMark.ZoneChanged then pcall(VoidMark.ZoneChanged, VoidMark) end
        VoidMark:ScanVisibleUnits()
    end)

    C_Timer.After(1.0, function()
        local showEnemies = GetCVar and GetCVar("nameplateShowEnemies")
        if tostring(showEnemies) ~= "1" and not VMF.NameplateWarningShown then
            VMF.NameplateWarningShown = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff9933ff[VoidMark]|r Enemy nameplates are OFF. Turn them on (V) for full Forever detection.")
        end
    end)
end

function VoidMark:OnDisable()
    if not VoidMark.IsEnabled then return end
    if VoidMark.timeid then VoidMark:CancelTimer(VoidMark.timeid); VoidMark.timeid = nil end
    if VMF.StopEvents then VMF.StopEvents() end
    VoidMark:StopUnitScan()

    local events = {
        "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
        "PLAYER_ENTERING_WORLD", "UNIT_FACTION", "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_PET",
        "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "CHAT_MSG_CHANNEL_NOTICE",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
        "UNIT_SPELLCAST_SUCCEEDED", "PARTY_KILL",
    }
    for _, eventName in ipairs(events) do
        pcall(VoidMark.UnregisterEvent, VoidMark, eventName)
    end
    if VoidMark.UnregisterComm and VoidMark.Signature then pcall(VoidMark.UnregisterComm, VoidMark, VoidMark.Signature) end
    wipe(VoidMark.NamePlateUnits)
    VoidMark.IsEnabled = false
end

-- Forever's API can return a protected PvP-flag value; use the same readable guard
-- as the working port so a zone-state check cannot disable detection by accident.
function VoidMark:ZoneChanged()
    VoidMark.InInstance = false
    local pvpType = VoidMark:GetZonePVPInfo()
    local zone = VoidMark:Readable(SafeCall(GetZoneText)) or ""
    local subZone = VoidMark:Readable(SafeCall(GetSubZoneText)) or ""
    local InFilteredZone = VoidMark:InFilteredZone(zone, subZone)

    if pvpType == "sanctuary" and not VoidMark.db.profile.EnabledInSanctuaries then
        VoidMark.EnabledInZone = false
    else
        VoidMark.EnabledInZone = true
        if zone == "" or InFilteredZone then
            VoidMark.EnabledInZone = false
        else
            local inInstance, instanceType = SafeCall(VMAPI.IsInInstance)
            if inInstance then
                VoidMark.InInstance = true
                if instanceType == "party" or instanceType == "raid"
                    or (not VoidMark.db.profile.EnabledInBattlegrounds and instanceType == "pvp")
                    or (not VoidMark.db.profile.EnabledInArenas and instanceType == "arena") then
                    VoidMark.EnabledInZone = false
                end
            elseif pvpType == "combat" then
                if not VoidMark.db.profile.EnabledInWintergrasp then VoidMark.EnabledInZone = false end
            elseif VoidMark:Readable(SafeCall(VMAPI.UnitIsPVP, "player")) == false and VoidMark.db.profile.DisableWhenPVPUnflagged then
                VoidMark.EnabledInZone = false
            end
        end
    end

    if VoidMark.EnabledInZone then
        if not VoidMark.db.profile.HideVoidMark then
            if not InCombatLockdown() then VoidMark.MainWindow:Show() end
            VoidMark:RefreshCurrentList()
        end
    else
        if not InCombatLockdown() then VoidMark.MainWindow:Hide() end
    end
    VoidMark:UpdateMainWindow()
end

-- Additional Forever guards mirrored from the known-working VoidMark Forever port.
function VoidMark:ChannelNoticeEvent(_, chStatus, _, _, Channel)
    chStatus = VoidMark:Readable(chStatus)
    Channel = VoidMark:Readable(Channel)
    if type(Channel) ~= "string" or not chStatus then return end
    if chStatus ~= "SUSPENDED" then
        VoidMark.ChnlTime = time()
        local _, zone = string.match(Channel, "(.+) %- (.+)")
        if zone and VoidMark:InFilteredZone(zone) then
            VoidMark.EnabledInZone = false
        end
    end
end

function VoidMark:UnitPets(event, unit)
    if unit ~= "player" then return end
    local petUnit = "pet"
    if not VMAPI.UnitExists(petUnit) then return end
    local petGUID = VoidMark:Readable(VMAPI.UnitGUID(petUnit))
    if type(petGUID) ~= "string" or petGUID == "" then return end
    VoidMark.PetGUID[petGUID] = time()
end

-- Small diagnostic command for beta testing without replacing the normal /vm command tree.
SLASH_VOIDMARKFOREVERDEBUG1 = "/vmf"
SlashCmdList.VOIDMARKFOREVERDEBUG = function()
    VMF.ProbeCombatLog()
    local _, version, build, toc = GetBuildInfo()
    local n = 0
    for _ in pairs(VMF.GUIDToName) do n = n + 1 end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff9933ff[VoidMark]|r client=%s version=%s build=%s interface=%s cachedPlayers=%d trackedPlates=%d scans=%d detections=%d enabledInZone=%s nameplates=%s",
        tostring(VMF.IsForever), tostring(version), tostring(build), tostring(toc), n,
        (function() local c=0 for _ in pairs(VoidMark.NamePlateUnits or {}) do c=c+1 end return c end)(),
        tonumber(VMF.Stats and VMF.Stats.scans) or 0,
        tonumber(VMF.Stats and VMF.Stats.detections) or 0,
        tostring(VoidMark.EnabledInZone),
        tostring(GetCVar and GetCVar("nameplateShowEnemies") or "?")
    ))
end

-- Map information is useful metadata, not a prerequisite for detecting a player.
-- The old Era function returned detected=false when C_Map had no usable player
-- position; on Forever that can make a valid nameplate detection disappear.
function VoidMark:UpdatePlayerData(name, class, level, race, guild, faction, isEnemy, isGuess, rank)
    if not name or not CanAccess(name) or type(name) ~= "string" then return false end
    if not VoidMarkPerCharDB or not VoidMarkPerCharDB.PlayerData then return false end

    local playerData = VoidMarkPerCharDB.PlayerData[name]
    if not playerData then
        playerData = VoidMark:AddPlayerData(name, class, level, race, guild, faction, isEnemy, isGuess, rank)
    else
        playerData.name = name
        if class ~= nil and CanAccess(class) then playerData.class = class end
        if type(level) == "number" then playerData.level = level end
        if race ~= nil and CanAccess(race) then playerData.race = race end
        if guild ~= nil and CanAccess(guild) then playerData.guild = guild end
        if faction ~= nil and CanAccess(faction) then playerData.faction = faction end
        if isEnemy ~= nil and CanAccess(isEnemy) then playerData.isEnemy = isEnemy end
        if isGuess ~= nil and CanAccess(isGuess) then playerData.isGuess = isGuess end
        if rank ~= nil and CanAccess(rank) then playerData.rank = rank end
    end

    if not playerData then return false end
    local guid=VoidMark:Readable(SafeCall(VMAPI.UnitGUID,VMF.FindVisibleUnit(name)))
    if type(guid)=="string" then playerData.guid=guid end
    if TaliaaGankRepository and TaliaaGankRepository.GetHistoricalStats then
        playerData.wins=math.max(tonumber(playerData.wins) or 0,tonumber((TaliaaGankRepository:GetHistoricalStats(name,guid))) or 0)
    end
    playerData.time = time()

    if not VoidMark.ActiveList[name] then
        local zone = SafeString(SafeCall(GetZoneText)) or SafeString(SafeCall(GetInstanceInfo)) or "Unknown"
        local subZone = SafeString(SafeCall(GetSubZoneText)) or ""
        playerData.zone = zone
        playerData.subZone = subZone

        if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
            local mapID = SafeCall(C_Map.GetBestMapForUnit, "player")
            if CanAccess(mapID) and type(mapID) == "number" then
                playerData.mapID = mapID
                local pos = SafeCall(C_Map.GetPlayerMapPosition, mapID, "player")
                if pos and type(pos.GetXY) == "function" then
                    local ok, mapX, mapY = pcall(pos.GetXY, pos)
                    if ok and CanAccess(mapX) and CanAccess(mapY) then
                        mapX, mapY = tonumber(mapX), tonumber(mapY)
                        if mapX and mapY and mapX ~= 0 and mapY ~= 0 then
                            playerData.mapX = math.floor(mapX * 100) / 100
                            playerData.mapY = math.floor(mapY * 100) / 100
                        end
                    end
                end
            end
        end
    end

    return true
end
