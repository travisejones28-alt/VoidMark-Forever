local VMAPI = VoidMarkForever.API
local F = VoidMarkForever
-- VoidMark Damage Records
-- Lightweight highest-hit tracker. Keeps one record per ability; no hit history.
VoidMarkDamageRecords = VoidMarkDamageRecords or {}
local DR = VoidMarkDamageRecords

local function CurrentCharacter()
    local name,realm=VoidMarkForever.PlayerIdentity()
    return name,realm,name.."-"..realm
end

local function DB()
    VoidMarkDB = VoidMarkDB or {}
    VoidMarkDB.VoidMarkDamageRecords = VoidMarkDB.VoidMarkDamageRecords or {
        version = 2,
        partyAnnounce = true,
        showPopup = true,
        characters = {},
    }
    local db = VoidMarkDB.VoidMarkDamageRecords

    -- Migrate the temporary YELL-era setting once, then use only Party.
    if db.partyAnnounce == nil then
        db.partyAnnounce = true
    end
    if db.showPopup == nil then db.showPopup = true end
    db.yellAnnounce = nil
    db.characters = db.characters or {}

    -- v1 stored every character in one shared records table. Split the records
    -- we can identify by the character/realm snapshot already stored on them.
    if (tonumber(db.version) or 1) < 2 then
        local function BucketFor(record)
            local name = type(record) == "table" and tostring(record.character or "") or ""
            local realm = type(record) == "table" and tostring(record.realm or "") or ""
            if name == "" or name == "?" then
                name, realm = "__LEGACY_UNKNOWN", "__LEGACY_UNKNOWN"
            elseif realm == "" or realm == "?" then
                local _, currentRealm = CurrentCharacter()
                realm = currentRealm
            end
            local key = name .. "-" .. realm
            db.characters[key] = db.characters[key] or { records = {} }
            db.characters[key].records = db.characters[key].records or {}
            return db.characters[key]
        end

        for key, record in pairs(db.records or {}) do
            if type(record) == "table" then
                local bucket = BucketFor(record)
                local old = bucket.records[key]
                if not old or (tonumber(old.amount) or 0) < (tonumber(record.amount) or 0) then
                    bucket.records[key] = record
                end
                if not bucket.overall or (tonumber(bucket.overall.amount) or 0) < (tonumber(record.amount) or 0) then
                    bucket.overall = {}
                    for k, v in pairs(record) do bucket.overall[k] = v end
                end
            end
        end

        if type(db.overall) == "table" then
            local bucket = BucketFor(db.overall)
            if not bucket.overall or (tonumber(bucket.overall.amount) or 0) < (tonumber(db.overall.amount) or 0) then
                bucket.overall = {}
                for k, v in pairs(db.overall) do bucket.overall[k] = v end
            end
        end

        db.records = nil
        db.overall = nil
        db.version = 2
    end

    return db
end

local function CharacterDB()
    local db = DB()
    local _, _, key = CurrentCharacter()
    db.characters[key] = db.characters[key] or { records = {} }
    local cdb = db.characters[key]
    cdb.records = cdb.records or {}
    return cdb
end

local function PlayerGUID()
    return VMAPI.UnitGUID and VMAPI.UnitGUID("player") or nil
end

local function TargetType(guid)
    if type(guid) == "string" and guid:match("^Player%-") then return "Player" end
    return "Mob"
end

local function Location()
    local zone = GetZoneText and GetZoneText() or "Unknown"
    local sub = GetSubZoneText and GetSubZoneText() or ""
    return zone, sub
end

local function SpellInfoSafe(spellID, fallback)
    local name, icon, _
    if VMAPI.GetSpellInfo and spellID then
        name, _, icon = VMAPI.GetSpellInfo(spellID)
    end
    -- Modernized Classic clients may expose spell info through C_Spell instead.
    if (not name or not icon) and C_Spell and C_Spell.GetSpellInfo and spellID then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            name = name or info.name
            icon = icon or info.iconID or info.iconFileID
        end
    end
    return name or fallback or "Unknown", icon
end

local function RecordKey(kind, spellID, spellName)
    if kind == "SWING" then return "SWING" end
    if spellID then return "SPELL:" .. tostring(spellID) end
    return tostring(kind or "DAMAGE") .. ":" .. tostring(spellName or "Unknown")
end

local function AbilityLabel(record)
    if not record then return "Unknown" end
    if record.kind == "SWING" then return "Melee" end
    return tostring(record.spellName or "Unknown")
end

local function IconTag(record)
    local icon = record and tonumber(record.icon)
    if not icon then return "" end
    return "|T" .. tostring(icon) .. ":16:16:0:0|t "
end

-- Forever names are "First Surname"; FullName stores them as "First-Surname".
local function ShortTarget(name)
    name = tostring(name or "Unknown")
    return (name:gsub("%-", " ", 1))
end

local function SelfNotice(record)
    local prefix = record.critical and "NEW HIGH CRIT!" or "NEW HIGH HIT!"
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffb86cff[VoidMark]|r |cffffd34e" .. prefix .. "|r "
        .. IconTag(record) .. AbilityLabel(record)
        .. " |cffffffff" .. tostring(record.amount) .. "|r"
        .. " vs |cffffffff" .. ShortTarget(record.targetName) .. "|r"
    )
end

local banner
local function ShowBanner(record)
    if not UIParent then return end
    if not banner then
        banner = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        banner:SetSize(440, 72)
        banner:SetPoint("TOP", UIParent, "TOP", 0, -170)
        banner:SetFrameStrata("DIALOG")
        banner:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
        })
        banner:SetBackdropColor(0.04, 0.02, 0.07, 0.94)
        banner:SetBackdropBorderColor(0.66, 0.28, 0.90, 1)
        banner.Icon = banner:CreateTexture(nil, "ARTWORK")
        banner.Icon:SetSize(42, 42)
        banner.Icon:SetPoint("LEFT", banner, "LEFT", 14, 0)
        banner.Title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        banner.Title:SetPoint("TOPLEFT", banner.Icon, "TOPRIGHT", 12, -1)
        banner.Value = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        banner.Value:SetPoint("TOPLEFT", banner.Title, "BOTTOMLEFT", 0, -7)
        banner:Hide()
    end

    banner.Icon:SetTexture(record.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    banner.Title:SetText(record.critical and "NEW HIGH CRIT" or "NEW HIGH HIT")
    banner.Value:SetText(AbilityLabel(record) .. "  •  " .. tostring(record.amount)
        .. "  →  " .. ShortTarget(record.targetName))
    banner:Show()

    local token = (banner._token or 0) + 1
    banner._token = token
    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, function()
            if banner and banner._token == token then banner:Hide() end
        end)
    end
end

local function SaveRecord(kind, spellID, spellName, amount, critical, destGUID, destName)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end

    local db = DB()
    local cdb = CharacterDB()
    local key = RecordKey(kind, spellID, spellName)
    local old = cdb.records[key]
    if old and (tonumber(old.amount) or 0) >= amount then return end

    local zone, sub = Location()
    local resolvedName, icon = SpellInfoSafe(spellID, spellName)
    if kind == "SWING" then
        resolvedName = "Melee"
        icon = "Interface\\Icons\\INV_Sword_04"
    end

    local record = {
        key = key,
        kind = kind,
        spellID = tonumber(spellID),
        spellName = resolvedName,
        icon = icon,
        amount = amount,
        critical = critical and true or false,
        targetName = tostring(destName or "Unknown"),
        targetGUID = tostring(destGUID or ""),
        targetType = TargetType(destGUID),
        time = GetServerTime and GetServerTime() or time(),
        zone = zone,
        subZone = sub,
        character = ShortTarget((CurrentCharacter())),
        realm = tostring(GetRealmName and GetRealmName() or "?"),
    }
    cdb.records[key] = record
    local isOverallRecord = not cdb.overall or (tonumber(cdb.overall.amount) or 0) < amount
    if isOverallRecord then
        -- Store a snapshot, not an alias to a per-ability table.
        cdb.overall = {}
        for k, v in pairs(record) do cdb.overall[k] = v end
    end

    -- Party is automatic only when the player is in a normal party.
    -- Solo and raid always use the private VoidMark notification.
    local inRaid = IsInRaid and IsInRaid() or false
    local inParty = IsInGroup and IsInGroup() or false
    if db.partyAnnounce and inParty and not inRaid and SendChatMessage then
        local prefix = record.critical and "NEW HIGH CRIT!" or "NEW HIGH HIT!"
        SendChatMessage(prefix .. " " .. AbilityLabel(record) .. " - "
            .. tostring(record.amount) .. " vs " .. ShortTarget(record.targetName), "PARTY")
    else
        SelfNotice(record)
    end
    if db.showPopup then ShowBanner(record) end
    if DR.Refresh then DR:Refresh() end
end

-- Sources -------------------------------------------------------------------
-- 1) Combat log, when the client exposes readable events (Classic-style).
-- 2) Forever fallback: the combat log is secret on Forever, so watch damage the
--    current TARGET takes (UNIT_COMBAT) and credit it to the player only when it
--    lines up with the player's own cast, channel or melee swing. DoT ticks and
--    pet damage can't be attributed this way and are not recorded.
DR.source = "none"          -- "combatlog" | "target" | "none"
DR.hidden = false           -- client returned secret damage values
DR.debug = false
local lastCLEU = 0
local lastCast, channel     -- {id,name,icon,at,used}
local CAST_WINDOW = 1.3     -- seconds from cast success to first hit (travel time)

local function Debug(msg)
    if DR.debug then DEFAULT_CHAT_FRAME:AddMessage("|cffb86cff[VoidMark dmg]|r " .. tostring(msg)) end
end

local function Grouped()
    return (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or false
end

local function AutoAttacking()
    local fn = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
    return F.Safe(fn, 6603) and true or false
end

local function CastInfo(spellID)
    spellID = tonumber(F.Readable(spellID))
    if not spellID or spellID == 6603 then return nil end
    local name, icon = SpellInfoSafe(spellID, nil)
    return { id = spellID, name = name, icon = icon, at = GetTime(), used = false }
end

local function OnTargetDamage(unit, action, flag, amount)
    if unit ~= "target" then return end
    -- If the readable combat log is working, it already recorded this hit.
    if GetTime() - lastCLEU < 5 then return end
    action, flag, amount = F.Readable(action), F.Readable(flag), F.Readable(amount)
    if action == nil or amount == nil then
        if not DR.hidden then DR.hidden = true; Debug("damage values are hidden by the client"); if DR.Refresh then DR:Refresh() end end
        return
    end
    if action ~= "WOUND" then return end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return end
    if not F.Safe(UnitCanAttack, "player", "target") then return end
    local guid = F.Safe(UnitGUID, "target")
    local name = F.FullName("target") or "Unknown"
    local crit = flag == "CRITICAL"
    local now = GetTime()
    local solo = not Grouped()

    if channel and (solo or not channel.used) then
        -- Channel ticks (e.g. Mind Flay). In a group only the first tick counts,
        -- so other players' hits during a long channel can't be credited.
        channel.used = true
        Debug(("%s tick %d"):format(channel.name, amount))
        DR.source = "target"
        SaveRecord("SPELL", channel.id, channel.name, amount, crit, guid, name)
    elseif lastCast and not lastCast.used and now - lastCast.at <= CAST_WINDOW then
        lastCast.used = true      -- one hit per cast
        Debug(("%s hit %d"):format(lastCast.name, amount))
        DR.source = "target"
        SaveRecord("SPELL", lastCast.id, lastCast.name, amount, crit, guid, name)
    elseif solo and AutoAttacking() then
        Debug(("melee %d"):format(amount))
        DR.source = "target"
        SaveRecord("SWING", nil, "Melee", amount, crit, guid, name)
    else
        Debug(("skipped %d (not clearly yours)"):format(amount))
    end
end

local eventFrame = CreateFrame("Frame")
VoidMarkForever.RegisterEvent(eventFrame,"PLAYER_LOGIN")
VoidMarkForever.RegisterEvent(eventFrame,"COMBAT_LOG_EVENT_UNFILTERED")
for _, ev in ipairs({"UNIT_COMBAT","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_STOP","PLAYER_TARGET_CHANGED"}) do
    VoidMarkForever.RegisterEvent(eventFrame, ev)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        DB()
        return
    end
    if event == "UNIT_COMBAT" then return OnTargetDamage(...) end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" then local c = CastInfo(spellID); if c then lastCast = c end end
        return
    end
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, _, spellID = ...
        if unit == "player" then channel = CastInfo(spellID) end
        return
    end
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if (...) == "player" then channel = nil end
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then lastCast = nil; return end
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" or not VMAPI.CombatLogGetCurrentEventInfo then return end

    local info = { VMAPI.CombatLogGetCurrentEventInfo() }
    local subevent = info[2]
    local sourceGUID = info[4]
    if sourceGUID ~= PlayerGUID() then return end

    if subevent == "SWING_DAMAGE" then
        -- SWING_DAMAGE: amount=12, critical=18.
        lastCLEU = GetTime(); DR.source = "combatlog"
        SaveRecord("SWING", nil, "Melee", info[12], info[18], info[8], info[9])
    elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
        or subevent == "RANGE_DAMAGE" then
        -- SPELL/RANGE damage: spellId=12, spellName=13, amount=15, critical=21.
        lastCLEU = GetTime(); DR.source = "combatlog"
        SaveRecord("SPELL", info[12], info[13], info[15], info[21], info[8], info[9])
    end
end)

SLASH_VOIDMARKDAMAGE1 = "/vmdmg"
SlashCmdList.VOIDMARKDAMAGE = function(msg)
    msg = tostring(msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "debug" then
        DR.debug = not DR.debug
        DEFAULT_CHAT_FRAME:AddMessage("|cffb86cff[VoidMark]|r Damage debug " .. (DR.debug and "ON - hit a target to see what is recorded." or "OFF"))
    else
        DR:Toggle()
    end
end

local frame
local selectedKey = "__OVERALL"

local function SortedRecords()
    local out = {}
    for key, record in pairs(CharacterDB().records) do
        if type(record) == "table" then
            out[#out + 1] = { key = key, record = record }
        end
    end
    table.sort(out, function(a, b)
        return (tonumber(a.record.amount) or 0) > (tonumber(b.record.amount) or 0)
    end)
    return out
end

local function SelectedRecord()
    local cdb = CharacterDB()
    if selectedKey == "__OVERALL" then return cdb.overall end
    return cdb.records[selectedKey]
end

function DR:Refresh()
    if not frame then return end
    local db = DB()
    local cdb = CharacterDB()
    local charName = CurrentCharacter()
    local r = SelectedRecord()
    frame.PartyButton.Text:SetText(db.partyAnnounce and "PARTY ANNOUNCE: ON" or "PARTY ANNOUNCE: OFF")
    frame.PopupButton.Text:SetText(db.showPopup and "POPUP: ON" or "POPUP: OFF")
    if frame.CharacterLabel then
        frame.CharacterLabel:SetText("CHARACTER: " .. ShortTarget(charName))
    end
    if frame.Source then
        if DR.source == "combatlog" then
            frame.Source:SetText("|cff8f8f8fTracking: combat log|r")
        elseif DR.hidden and DR.source ~= "target" then
            frame.Source:SetText("|cffff7777This client hides damage numbers from addons - records can't update.|r")
        else
            frame.Source:SetText("|cff8f8f8fTracking: hits on your target (casts, channels, melee). DoTs/pets not counted.|r")
        end
    end
    -- A previously selected spell can disappear after changing characters or
    -- after manual SavedVariables editing. Fall back cleanly.
    if selectedKey ~= "__OVERALL" and not cdb.records[selectedKey] then
        selectedKey = "__OVERALL"
        if frame.Dropdown then
            UIDropDownMenu_SetSelectedValue(frame.Dropdown, selectedKey)
            UIDropDownMenu_SetText(frame.Dropdown, "Highest Damage Ever")
        end
        r = cdb.overall
    end
    if not r then
        frame.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        frame.Ability:SetText("No damage records yet")
        frame.Amount:SetText("—")
        frame.Meta:SetText("Hit something you have targeted to create a record.")
        frame.Location:SetText("")
        return
    end
    frame.Icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.Ability:SetText(AbilityLabel(r))
    frame.Amount:SetText(tostring(r.amount) .. (r.critical and "  CRIT" or "  HIT"))
    local when = tonumber(r.time) and date("%b %d, %Y  %I:%M %p", tonumber(r.time)) or "?"
    frame.Meta:SetText(ShortTarget(r.targetName) .. "  •  " .. tostring(r.targetType or "?") .. "  •  " .. when)
    local loc = tostring(r.zone or "Unknown")
    if r.subZone and r.subZone ~= "" and r.subZone ~= r.zone then loc = loc .. " - " .. r.subZone end
    frame.Location:SetText(loc .. "  •  " .. tostring(r.character or "?"))
end

local function BuildUI()
    if frame then return end
    frame = CreateFrame("Frame", "VoidMarkDamageRecordsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(470, 255)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
    })
    frame:SetBackdropColor(0.035, 0.02, 0.055, 0.98)
    frame:SetBackdropBorderColor(0.48, 0.20, 0.68, 1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -13)
    title:SetText("VOIDMARK — DAMAGE RECORDS")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)

    frame.CharacterLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.CharacterLabel:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, -11)
    frame.CharacterLabel:SetJustifyH("RIGHT")

    frame.Dropdown = CreateFrame("Frame", "VoidMarkDamageRecordsDropdown", frame, "UIDropDownMenuTemplate")
    frame.Dropdown:SetPoint("TOPLEFT", 2, -40)
    UIDropDownMenu_SetWidth(frame.Dropdown, 260)
    UIDropDownMenu_Initialize(frame.Dropdown, function(_, level)
        if level ~= 1 then return end
        local function Add(label, key, icon)
            local info = UIDropDownMenu_CreateInfo()
            info.text = label
            info.value = key
            info.icon = icon
            info.checked = selectedKey == key
            info.func = function()
                selectedKey = key
                UIDropDownMenu_SetSelectedValue(frame.Dropdown, key)
                UIDropDownMenu_SetText(frame.Dropdown, label)
                DR:Refresh()
            end
            UIDropDownMenu_AddButton(info, level)
        end
        Add("Highest Damage Ever", "__OVERALL")
        for _, item in ipairs(SortedRecords()) do
            Add(AbilityLabel(item.record) .. "  —  " .. tostring(item.record.amount), item.key, item.record.icon)
        end
    end)
    UIDropDownMenu_SetSelectedValue(frame.Dropdown, selectedKey)
    UIDropDownMenu_SetText(frame.Dropdown, "Highest Damage Ever")

    frame.Icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetSize(44, 44)
    frame.Icon:SetPoint("TOPLEFT", 20, -92)

    frame.Ability = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.Ability:SetPoint("TOPLEFT", frame.Icon, "TOPRIGHT", 12, -1)

    frame.Amount = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.Amount:SetPoint("TOPLEFT", frame.Ability, "BOTTOMLEFT", 0, -5)

    frame.Meta = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.Meta:SetPoint("TOPLEFT", 20, -148)
    frame.Meta:SetPoint("RIGHT", -20, 0)
    frame.Meta:SetJustifyH("LEFT")

    frame.Location = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.Location:SetPoint("TOPLEFT", frame.Meta, "BOTTOMLEFT", 0, -7)
    frame.Location:SetPoint("RIGHT", -20, 0)
    frame.Location:SetJustifyH("LEFT")

    frame.Source = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.Source:SetPoint("BOTTOMLEFT", 20, 44)
    frame.Source:SetPoint("RIGHT", -20, 0)
    frame.Source:SetJustifyH("LEFT")

    frame.PartyButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.PartyButton:SetSize(180, 24)
    frame.PartyButton:SetPoint("BOTTOMLEFT", 18, 13)
    frame.PartyButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
    })
    frame.PartyButton:SetBackdropColor(0.08, 0.035, 0.12, 1)
    frame.PartyButton:SetBackdropBorderColor(0.48, 0.20, 0.68, 1)
    frame.PartyButton.Text = frame.PartyButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.PartyButton.Text:SetAllPoints()
    frame.PartyButton:SetScript("OnClick", function()
        local db = DB()
        db.partyAnnounce = not db.partyAnnounce
        DR:Refresh()
    end)



    frame.PopupButton = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.PopupButton:SetSize(180, 24)
    frame.PopupButton:SetPoint("BOTTOMRIGHT", -18, 13)
    frame.PopupButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
    })
    frame.PopupButton:SetBackdropColor(0.08, 0.035, 0.12, 1)
    frame.PopupButton:SetBackdropBorderColor(0.48, 0.20, 0.68, 1)
    frame.PopupButton.Text = frame.PopupButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.PopupButton.Text:SetAllPoints()
    frame.PopupButton:SetScript("OnClick", function()
        local db = DB()
        db.showPopup = not db.showPopup
        if not db.showPopup and banner then banner:Hide() end
        DR:Refresh()
    end)

    frame:Hide()
    DR:Refresh()
end


function DR:Toggle()
    BuildUI()
    if frame:IsShown() then
        frame:Hide()
    else
        DR:Refresh()
        frame:Show()
    end
end
