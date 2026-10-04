-- VoidMark MC Marks
-- Auto raid-marks enemy players while they are under Priest Mind Control.
-- Session marks are intentionally not persisted. Position/enabled state are.

local MARK_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 } -- Skull -> Star
local ICON_NAMES = {
    [1] = "Star",
    [2] = "Circle",
    [3] = "Diamond",
    [4] = "Triangle",
    [5] = "Moon",
    [6] = "Square",
    [7] = "Cross",
    [8] = "Skull",
}

local MC_SPELLS = {
    [605] = true,
    [10911] = true,
    [10912] = true,
}

local MAX_ROWS = 8
local marks = {} -- guid -> { guid, name, icon, class, t0, mcActive }
local rows = {}
local board
local nextIconCursor = 1
local tickerElapsed = 0

local function DB()
    VoidMarkDB = VoidMarkDB or {}
    VoidMarkDB.VoidMarkMCMarks = VoidMarkDB.VoidMarkMCMarks or {}
    local db = VoidMarkDB.VoidMarkMCMarks
    if db.enabled == nil then db.enabled = true end
    return db
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffb266ffVoidMark|r: " .. tostring(msg))
end

local function StripRealm(name)
    name = tostring(name or "?")
    if VoidMarkForever and VoidMarkForever.IsForever and VoidMarkForever.DisplayName then
        return VoidMarkForever.DisplayName(name)
    end
    if Ambiguate then
        name = Ambiguate(name, "none") or name
    end
    return name:match("^([^-]+)") or name
end

local function IconTexture(index)
    return string.format("Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d", tonumber(index) or 8)
end

local function IconTag(index)
    return string.format("|T%s:14:14:0:0|t", IconTexture(index))
end

local function ClassColoredName(name, classFile)
    local clean = StripRealm(name)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not c then return clean end
    return string.format(
        "|cff%02x%02x%02x%s|r",
        math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5),
        math.floor(c.b * 255 + 0.5),
        clean
    )
end

local function AuraIsMindControl(scanner, unit)
    if type(scanner) ~= "function" then return false end

    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellID = scanner(unit, i)
        if not name then break end

        if spellID and MC_SPELLS[spellID] then
            return true
        end

        if type(name) == "string" and string.lower(name) == "mind control" then
            return true
        end
    end

    return false
end

local function HasMindControlAura(unit)
    if not unit or not UnitExists(unit) then return false end
    return AuraIsMindControl(UnitBuff, unit) or AuraIsMindControl(UnitDebuff, unit)
end

local function IsUnitInMyGroup(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsUnit(unit, "player") then return true end

    if UnitInParty and UnitInParty(unit) then return true end
    if UnitInRaid and UnitInRaid(unit) then return true end

    local guid = UnitGUID(unit)
    if not guid then return false end

    if IsInRaid and IsInRaid() then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, n do
            if UnitGUID("raid" .. i) == guid then return true end
        end
    else
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers()
            or (GetNumPartyMembers and GetNumPartyMembers())
            or 0
        for i = 1, n do
            if UnitGUID("party" .. i) == guid then return true end
        end
    end

    return false
end

local function IsMindControlledEnemyPlayer(unit)
    if not unit or not UnitExists(unit) then return false end
    if not UnitIsPlayer(unit) then return false end
    if UnitIsUnit(unit, "player") then return false end
    if IsUnitInMyGroup(unit) then return false end
    return HasMindControlAura(unit)
end

local function BuildSearchUnits()
    local units = { "target", "mouseover", "focus" }

    if IsInRaid and IsInRaid() then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, n do
            units[#units + 1] = "raid" .. i
            units[#units + 1] = "raid" .. i .. "target"
        end
    else
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers()
            or (GetNumPartyMembers and GetNumPartyMembers())
            or 0
        for i = 1, n do
            units[#units + 1] = "party" .. i
            units[#units + 1] = "party" .. i .. "target"
        end
    end

    for i = 1, 40 do
        units[#units + 1] = "nameplate" .. i
    end

    return units
end

local function FindUnitByGUID(guid)
    if not guid then return nil end

    for _, unit in ipairs(BuildSearchUnits()) do
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit
        end
    end

    return nil
end

local function IconUsedByTrackedMark(icon, exceptGUID)
    for guid, mark in pairs(marks) do
        if guid ~= exceptGUID and mark.icon == icon then
            return true
        end
    end
    return false
end

local function IconVisibleOnAnotherUnit(icon, exceptGUID)
    if not GetRaidTargetIndex then return false end

    for _, unit in ipairs(BuildSearchUnits()) do
        if UnitExists(unit)
            and GetRaidTargetIndex(unit) == icon
            and UnitGUID(unit) ~= exceptGUID then
            return true
        end
    end

    return false
end

local function IconIsFree(icon, exceptGUID)
    return not IconUsedByTrackedMark(icon, exceptGUID)
        and not IconVisibleOnAnotherUnit(icon, exceptGUID)
end

local function ClearMarkIcon(mark)
    if not mark or not mark.icon then return end

    local unit = FindUnitByGUID(mark.guid)
    if unit and GetRaidTargetIndex and GetRaidTargetIndex(unit) == mark.icon and SetRaidTarget then
        pcall(SetRaidTarget, unit, 0)
    end
end

local RefreshBoard

local function RemoveMark(guid, silent)
    local mark = marks[guid]
    if not mark then return end

    ClearMarkIcon(mark)
    marks[guid] = nil

    if not silent then
        Print("cleared MC mark " .. IconTag(mark.icon) .. " " .. StripRealm(mark.name))
    end

    if RefreshBoard then RefreshBoard() end
end

local function OldestReclaimableMark()
    local inactive
    local active

    for _, mark in pairs(marks) do
        if not mark.mcActive then
            if not inactive or (mark.t0 or 0) < (inactive.t0 or 0) then
                inactive = mark
            end
        elseif not active or (mark.t0 or 0) < (active.t0 or 0) then
            active = mark
        end
    end

    return inactive or active
end

local function NextFreeIcon()
    for _ = 1, #MARK_ORDER do
        local icon = MARK_ORDER[nextIconCursor]
        nextIconCursor = nextIconCursor + 1
        if nextIconCursor > #MARK_ORDER then nextIconCursor = 1 end

        if IconIsFree(icon) then
            return icon
        end
    end

    -- If all eight VoidMark marks are occupied, reclaim the oldest mark,
    -- preferring an old "was MC" entry over an active MC.
    local reclaim = OldestReclaimableMark()
    if reclaim then
        local icon = reclaim.icon
        RemoveMark(reclaim.guid, true)
        return icon
    end

    -- Do not steal unrelated raid icons from the group.
    return nil
end

local function SaveBoardPosition()
    if not board then return end
    local point, _, relativePoint, x, y = board:GetPoint(1)
    local db = DB()
    db.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function RestoreBoardPosition()
    if not board then return end

    local pos = DB().position
    board:ClearAllPoints()

    if pos and pos.point then
        board:SetPoint(
            pos.point,
            UIParent,
            pos.relativePoint or pos.point,
            tonumber(pos.x) or 0,
            tonumber(pos.y) or 0
        )
    else
        board:SetPoint("RIGHT", UIParent, "RIGHT", -40, 200)
    end
end

local function EnsureBoard()
    if board then return board end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", "VoidMarkMCMarksBoard", UIParent, template)
    frame:SetSize(270, 30)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveBoardPosition()
    end)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        frame:SetBackdropColor(0.015, 0.008, 0.025, 0.94)
        frame:SetBackdropBorderColor(0.52, 0.18, 0.78, 0.96)
    end

    local headerBG = frame:CreateTexture(nil, "BACKGROUND")
    headerBG:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    headerBG:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    headerBG:SetHeight(25)
    headerBG:SetColorTexture(0.075, 0.018, 0.115, 0.98)

    frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7)
    frame.Title:SetText("|cffd28cffVOIDMARK|r  |cff9860bf•|r  |cffc77dffMC MARKS|r")

    frame.Count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.Count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -25, -7)

    frame.Close = CreateFrame("Button", nil, frame)
    frame.Close:SetSize(18, 18)
    frame.Close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    frame.Close.Text = frame.Close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.Close.Text:SetPoint("CENTER")
    frame.Close.Text:SetText("X")
    frame.Close.Text:SetTextColor(1.0, 0.28, 0.42, 1)
    frame.Close:SetScript("OnClick", function()
        frame:Hide()
        DB().hidden = true
    end)

    board = frame
    RestoreBoardPosition()
    frame:Hide()
    return frame
end

local function SortedMarks()
    local list = {}
    for _, mark in pairs(marks) do
        list[#list + 1] = mark
    end

    table.sort(list, function(a, b)
        if a.mcActive ~= b.mcActive then
            return a.mcActive and true or false
        end
        return (a.t0 or 0) < (b.t0 or 0)
    end)

    return list
end

RefreshBoard = function()
    local frame = EnsureBoard()

    if not DB().enabled then
        frame:Hide()
        return
    end

    local list = SortedMarks()
    local count = #list

    if count == 0 or DB().hidden then
        frame:Hide()
        return
    end

    frame.Count:SetText(tostring(count))
    frame:Show()

    for i = 1, MAX_ROWS do
        local row = rows[i]

        if not row then
            row = CreateFrame("Frame", nil, frame)
            row:SetHeight(18)

            row.BG = row:CreateTexture(nil, "BACKGROUND")
            row.BG:SetAllPoints()

            row.Icon = row:CreateTexture(nil, "OVERLAY")
            row.Icon:SetSize(14, 14)
            row.Icon:SetPoint("LEFT", row, "LEFT", 6, 0)

            row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 5, 0)
            row.Name:SetWidth(145)
            row.Name:SetJustifyH("LEFT")
            row.Name:SetWordWrap(false)

            row.Status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Status:SetPoint("LEFT", row.Name, "RIGHT", 4, 0)
            row.Status:SetWidth(65)
            row.Status:SetJustifyH("LEFT")

            row.Clear = CreateFrame("Button", nil, row)
            row.Clear:SetSize(18, 18)
            row.Clear:SetPoint("RIGHT", row, "RIGHT", -3, 0)
            row.Clear.Text = row.Clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Clear.Text:SetPoint("CENTER")
            row.Clear.Text:SetText("X")
            row.Clear.Text:SetTextColor(1.0, 0.30, 0.40, 1)
            row.Clear:SetScript("OnClick", function(self)
                local parent = self:GetParent()
                if parent and parent.guid then
                    RemoveMark(parent.guid)
                end
            end)

            rows[i] = row
        end

        local mark = list[i]
        if mark then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -25 - ((i - 1) * 18))
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -25 - ((i - 1) * 18))

            if i % 2 == 0 then
                row.BG:SetColorTexture(0.035, 0.022, 0.050, 0.92)
            else
                row.BG:SetColorTexture(0.020, 0.014, 0.030, 0.92)
            end

            row.guid = mark.guid
            row.Icon:SetTexture(IconTexture(mark.icon))
            row.Name:SetText(ClassColoredName(mark.name, mark.class))

            if mark.mcActive then
                row.Status:SetText("|cff66ff88MC|r")
            else
                row.Status:SetText("|cff777777was MC|r")
            end

            row:Show()
        else
            row.guid = nil
            row:Hide()
        end
    end

    frame:SetHeight(26 + (math.min(count, MAX_ROWS) * 18) + 4)
end

local function TryMarkUnit(unit, reason)
    if not DB().enabled then return false end
    if not unit or not UnitExists(unit) then return false end

    if not IsMindControlledEnemyPlayer(unit) then
        if reason == "manual" then
            Print("target is not an enemy player under Priest Mind Control.")
        end
        return false
    end

    local guid = UnitGUID(unit)
    local name = UnitName(unit)
    if not guid or not name then return false end

    DB().hidden = false

    local existing = marks[guid]
    if existing then
        existing.mcActive = true
        existing.name = name
        local _, classFile = UnitClass(unit)
        existing.class = classFile or existing.class

        if existing.icon and SetRaidTarget then
            pcall(SetRaidTarget, unit, existing.icon)
        end

        RefreshBoard()
        return true
    end

    local icon = NextFreeIcon()
    if not icon then
        Print("no free raid icon available for " .. StripRealm(name) .. ".")
        return false
    end

    local ok = false
    if SetRaidTarget then
        ok = pcall(SetRaidTarget, unit, icon)
    end
    local _, classFile = UnitClass(unit)

    marks[guid] = {
        guid = guid,
        name = name,
        icon = icon,
        class = classFile,
        t0 = GetTime(),
        mcActive = true,
        markCallOK = ok and true or false,
    }

    RefreshBoard()

    Print(
        "MC marked " .. IconTag(icon)
        .. " |cffffff00" .. StripRealm(name) .. "|r"
        .. " with " .. IconTag(icon)
        .. " |cffaaaaaa(" .. (ICON_NAMES[icon] or tostring(icon)) .. ")|r"
    )

    return true
end

local function ScanMarks()
    if not DB().enabled then
        if board then board:Hide() end
        return
    end

    if UnitExists("target") and IsMindControlledEnemyPlayer("target") then
        TryMarkUnit("target", "auto")
    end

    for guid, mark in pairs(marks) do
        local unit = FindUnitByGUID(guid)

        if unit then
            mark.mcActive = IsMindControlledEnemyPlayer(unit)
            mark.name = UnitName(unit) or mark.name
            local _, classFile = UnitClass(unit)
            mark.class = classFile or mark.class

            if mark.mcActive and mark.icon then
                if SetRaidTarget and (not GetRaidTargetIndex or GetRaidTargetIndex(unit) ~= mark.icon) then
                    pcall(SetRaidTarget, unit, mark.icon)
                end
            end
        else
            mark.mcActive = false
        end
    end

    RefreshBoard()
end

local function ClearAll()
    local guids = {}
    for guid in pairs(marks) do
        guids[#guids + 1] = guid
    end

    for _, guid in ipairs(guids) do
        RemoveMark(guid, true)
    end

    DB().hidden = false
    RefreshBoard()
    Print("all MC marks cleared.")
end

-- Expose a tiny public surface so a future VoidMark button can toggle this without
-- coupling the main UI file to implementation details.
VoidMarkMCMarks = VoidMarkMCMarks or {}

function VoidMarkMCMarks:SetEnabled(enabled)
    DB().enabled = enabled and true or false
    if not DB().enabled then
        if board then board:Hide() end
    else
        DB().hidden = false
        ScanMarks()
    end
end

function VoidMarkMCMarks:IsEnabled()
    return DB().enabled and true or false
end

function VoidMarkMCMarks:Show()
    DB().hidden = false
    RefreshBoard()
end

function VoidMarkMCMarks:Clear()
    ClearAll()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UNIT_FLAGS")
events:RegisterEvent("GROUP_ROSTER_UPDATE")

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        EnsureBoard()
        C_Timer.After(1, ScanMarks)
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        ScanMarks()
        return
    end

    if event == "UNIT_AURA" or event == "UNIT_FLAGS" then
        if unit == "target" then
            ScanMarks()
            return
        end

        local guid = unit and UnitGUID(unit)
        if guid and marks[guid] then
            ScanMarks()
        end
        return
    end

    RefreshBoard()
end)

events:SetScript("OnUpdate", function(_, elapsed)
    tickerElapsed = tickerElapsed + (tonumber(elapsed) or 0)
    if tickerElapsed < 0.4 then return end
    tickerElapsed = 0

    if not DB().enabled then return end

    if next(marks)
        or (UnitExists("target") and HasMindControlAura("target")) then
        ScanMarks()
    end
end)

SLASH_VOIDMARKMC1 = "/vmc"
SLASH_VOIDMARKMC2 = "/mcmark"

SlashCmdList["VOIDMARKMC"] = function(msg)
    msg = string.lower(strtrim(msg or ""))

    if msg == "on" then
        VoidMarkMCMarks:SetEnabled(true)
        Print("MC auto marking: ON")
    elseif msg == "off" then
        VoidMarkMCMarks:SetEnabled(false)
        Print("MC auto marking: OFF")
    elseif msg == "clear" then
        ClearAll()
    elseif msg == "show" then
        VoidMarkMCMarks:Show()
    elseif msg == "" or msg == "mark" then
        TryMarkUnit("target", "manual")
    else
        Print("/vmc mark | on | off | show | clear")
        Print("Auto-marks your targeted enemy player while Priest Mind Control is active.")
    end
end
