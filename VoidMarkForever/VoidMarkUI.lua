local VMAPI = VoidMarkForever.API
-- VoidMark Stage 2 UI layer
-- UI Adjust 1: tighter compact header; backend/data behavior unchanged.
-- Keeps the existing VoidMark/VoidMark backend, SavedVariables, secure target rows,
-- detection logic and synchronization intact while replacing the
-- visible main-window presentation with a compact Shadow Priest themed shell.

local VM = {}
VoidMark.VoidMark = VM

VM.VERSION = "1.0 Generated Header"
VM.PURPLE = {0.56, 0.20, 0.82}
VM.PURPLE_BRIGHT = {0.76, 0.42, 1.00}
VM.BG = {0.015, 0.010, 0.025, 0.97}
VM.ROW_UNKNOWN = {0.075, 0.075, 0.095}
VM.ROW_LOW = {0.025, 0.17, 0.09}
VM.ROW_KOS = {0.38, 0.035, 0.05}
VM.ROW_STEALTH = {0.20, 0.045, 0.31}

-- Compact header geometry. The logo gets a little more vertical breathing room,
-- while the window is nudged slightly narrower once per profile.
VM.HEADER_HEIGHT = 88
VM.ROW_TOP_OFFSET = 90
VM.DEFAULT_WIDTH_SCALE = 1.00
VM.MIN_MAIN_WIDTH = 300
VM.DEFAULT_MAIN_WIDTH = 360

local function Chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffb86cff[VoidMark]|r " .. tostring(msg))
end

local function CountTable(tbl)
    local n = 0
    if tbl then
        for _ in pairs(tbl) do n = n + 1 end
    end
    return n
end

local function SafePlayerData(name)
    return VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData and VoidMarkPerCharDB.PlayerData[name] or nil
end

local function IsKOS(name)
    if not name or not VoidMarkPerCharDB then return false end
    if VoidMarkPerCharDB.KOSData and VoidMarkPerCharDB.KOSData[name] then return true end
    local data = SafePlayerData(name)
    return data and data.kos == 1 or false
end

local function IsStealth(name)
    local untilTime = VoidMark.StealthDetectedUntil and VoidMark.StealthDetectedUntil[name]
    if not untilTime then return false end
    if untilTime <= time() then
        VoidMark.StealthDetectedUntil[name] = nil
        return false
    end
    return true
end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.92, 0.92, 0.96
end

-- Inline class icon used by the compact enemy row. CLASS_ICON_TCOORDS is
-- Blizzard's class-icon lookup table; the full class name never needs to be
-- shown in the row.
local function ClassIconTag(class, size)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not coords then return "" end

    size = size or 13
    local atlasSize = 256
    local left = math.floor((coords[1] or 0) * atlasSize + 0.5)
    local right = math.floor((coords[2] or 1) * atlasSize + 0.5)
    local top = math.floor((coords[3] or 0) * atlasSize + 0.5)
    local bottom = math.floor((coords[4] or 1) * atlasSize + 0.5)

    return string.format(
        "|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t",
        size, size, atlasSize, atlasSize, left, right, top, bottom
    )
end

local function SetFont(fs, path, size, flags, fallback)
    local ok = false
    if fs and fs.SetFont and path then
        local success, result = pcall(fs.SetFont, fs, path, size, flags or "")
        ok = success and result ~= false
    end
    if not ok and fs and fallback then
        fs:SetFontObject(fallback)
    end
end

local function AgeText(ts)
    if not ts then return "Unknown" end
    local delta = math.max(0, time() - ts)
    if delta < 60 then return tostring(delta) .. "s ago" end
    if delta < 3600 then return tostring(math.floor(delta / 60)) .. "m ago" end
    if delta < 86400 then return tostring(math.floor(delta / 3600)) .. "h ago" end
    return tostring(math.floor(delta / 86400)) .. "d ago"
end

function VM:GetPriority(name)
    if IsKOS(name) then return 600 end
    if IsStealth(name) then return 300 end
    return 100
end

function VM:ManageNearby()
    local list = {}
    local seen = {}

    local function AddSet(tbl, active)
        for player, stamp in pairs(tbl or {}) do
            if not seen[player] and VoidMark.NearbyList[player] ~= nil then
                seen[player] = true
                list[#list + 1] = {
                    player = player,
                    time = VoidMark.NearbyList[player] or stamp or 0,
                    active = active and 1 or 0,
                    priority = VM:GetPriority(player),
                }
            end
        end
    end

    AddSet(VoidMark.ActiveList, true)
    AddSet(VoidMark.InactiveList, false)

    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.active ~= b.active then return a.active > b.active end
        return (a.time or 0) > (b.time or 0)
    end)

    VoidMark.CurrentList = list
end

function VM:ManageAllPlayers()
    local list = {}
    for player, data in pairs((VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData) or {}) do
        if data and data.isEnemy then
            list[#list + 1] = { player = player, time = data.time or 0 }
        end
    end
    table.sort(list, function(a, b) return (a.time or 0) > (b.time or 0) end)
    VoidMark.CurrentList = list
end

-- Extend the existing dropdown-backed list model without changing the first four
-- indices used by the old VoidMark backend. High Risk and Hunt List were retired.
if VoidMark.ListTypes and not VM.ListTypesInstalled then
    VoidMark.ListTypes[1][2] = function() VM:ManageNearby() end
    table.insert(VoidMark.ListTypes, {"All Players", function() VM:ManageAllPlayers() end})
    VM.ListTypesInstalled = true
end

local function ModeShort(mode)
    local names = {
        [1] = "Nearby",
        [2] = "Recent",
        [3] = "Ignore",
        [4] = "KOS",
        [5] = "All",
    }
    return names[mode] or "List"
end

function VM:GetModeCount(mode)
    mode = mode or (VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.CurrentList) or 1
    if mode == 1 then return VoidMark.GetNearbyListSize and VoidMark:GetNearbyListSize() or CountTable(VoidMark.NearbyList) end
    if mode == 2 then return CountTable(VoidMark.LastHourList) end
    if mode == 3 then return CountTable(VoidMarkPerCharDB and VoidMarkPerCharDB.IgnoreData) end
    if mode == 4 then return CountTable(VoidMarkPerCharDB and VoidMarkPerCharDB.KOSData) end
    if mode == 5 then
        local n = 0
        for _, data in pairs((VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData) or {}) do
            if data and data.isEnemy then n = n + 1 end
        end
        return n
    end
    return #(VoidMark.CurrentList or {})
end

function VM:UpdateModeLabel()
    local frame = VoidMark.MainWindow
    if not frame or not frame.VoidMarkModeText then return end
    local mode = VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.CurrentList or 1
    frame.VoidMarkModeText:SetText(string.format("|cffb45cff•|r %s (%d)", ModeShort(mode), VM:GetModeCount(mode)))
end

function VM:SetListMode(mode)
    if InCombatLockdown() then
        VoidMark.VoidMarkPendingMode = mode
        UIErrorsFrame:AddMessage("VoidMark: list switch queued until combat ends.", 0.75, 0.45, 1.0, 1.0)
        return
    end
    VoidMark:SetCurrentList(mode)
end

local function BuildModeMenu(self, level)
    if level ~= 1 then return end
    local entries = {
        {1, "Nearby"},
        {2, "Recent"},
        {4, "KOS List"},
        {3, "Ignore List"},
        {5, "All Players"},
    }
    for _, entry in ipairs(entries) do
        local mode, label = entry[1], entry[2]
        local info = UIDropDownMenu_CreateInfo()
        info.text = label
        info.notCheckable = true
        info.checked = false
        info.func = function() VM:SetListMode(mode) end
        UIDropDownMenu_AddButton(info, level)
    end
end

local function BuildGearMenu(self, level)
    if level ~= 1 then return end

    local function Add(text, func)
        local info = UIDropDownMenu_CreateInfo()
        info.text = text
        info.notCheckable = true
        info.func = func
        UIDropDownMenu_AddButton(info, level)
    end

    Add("Statistics", function() if VoidMarkStats then VoidMarkStats:Toggle() end end)
    Add("Settings", function() if VoidMark.ShowConfig then VoidMark:ShowConfig() end end)
    Add("Kill Effects", function()
        if VoidMarkKillEffects and VoidMarkKillEffects.ToggleOptions then
            VoidMarkKillEffects:ToggleOptions()
        end
    end)
    Add("Damage Records", function()
        if VoidMarkDamageRecords and VoidMarkDamageRecords.Toggle then
            VoidMarkDamageRecords:Toggle()
        end
    end)
    local enemyMovesEnabled = VoidMarkEnemyMoves
        and VoidMarkEnemyMoves.IsEnabled
        and VoidMarkEnemyMoves:IsEnabled()

    Add(enemyMovesEnabled and "Enemy Moves: ON" or "Enemy Moves: OFF", function()
        if VoidMarkEnemyMoves and VoidMarkEnemyMoves.ToggleEnabled then
            VoidMarkEnemyMoves:ToggleEnabled()
        end
    end)

    local panicEnabled = TaliaaGankTracker
        and TaliaaGankTracker.IsPanicEnabled
        and TaliaaGankTracker:IsPanicEnabled()

    Add(panicEnabled and "Panic: ON" or "Panic: OFF", function()
        if TaliaaGankTracker and TaliaaGankTracker.TogglePanicEnabled then
            TaliaaGankTracker:TogglePanicEnabled()
        end
    end)

    local sapAlertEnabled = TaliaaGankTracker
        and TaliaaGankTracker.IsSapAlertEnabled
        and TaliaaGankTracker:IsSapAlertEnabled()

    Add(sapAlertEnabled and "Sap Alert: ON" or "Sap Alert: OFF", function()
        if TaliaaGankTracker and TaliaaGankTracker.ToggleSapAlertEnabled then
            TaliaaGankTracker:ToggleSapAlertEnabled()
        end
    end)
    Add("Taunt", function()
        if VoidMarkTaunt and VoidMarkTaunt.Toggle then VoidMarkTaunt.Toggle() end
    end)
    Add("Boat Timers", function()
        if VoidMarkBoats and VoidMarkBoats.Toggle then VoidMarkBoats:Toggle() end
    end)
    Add("Ride or Die", function()
        if VoidMarkRideOrDie and VoidMarkRideOrDie.ToggleUI then VoidMarkRideOrDie:ToggleUI() end
    end)
    if TaliaaGankTracker and TaliaaGankTracker.Frame then
        local shown = TaliaaGankTracker.Frame:IsShown()
        Add(shown and "Hide Gank Tracker" or "Show Gank Tracker", function()
            if TaliaaGankTracker and TaliaaGankTracker.ToggleWindow then
                TaliaaGankTracker:ToggleWindow()
            elseif TaliaaGankTracker and TaliaaGankTracker.Frame then
                if TaliaaGankTracker.Frame:IsShown() then
                    TaliaaGankTracker.Frame:Hide()
                else
                    TaliaaGankTracker.Frame:Show()
                end
            end
        end)
    end
    Add("Clear Nearby", function() if not InCombatLockdown() then VoidMark:ClearList() end end)
    Add("Reset Window Positions", function() if not InCombatLockdown() then VoidMark:ResetPositions() end end)
end

function VM:OpenModeMenu(button)
    if not VM.ModeMenu then
        VM.ModeMenu = CreateFrame("Frame", "VoidMark_ModeDropDown", UIParent, "UIDropDownMenuTemplate")
        VM.ModeMenu.displayMode = "MENU"
        VM.ModeMenu.initialize = BuildModeMenu
    end
    ToggleDropDownMenu(1, nil, VM.ModeMenu, button, 0, 0)
end

function VM:OpenGearMenu(button)
    if not VM.GearMenu then
        VM.GearMenu = CreateFrame("Frame", "VoidMark_GearDropDown", UIParent, "UIDropDownMenuTemplate")
        VM.GearMenu.displayMode = "MENU"
        VM.GearMenu.initialize = BuildGearMenu
    end
    ToggleDropDownMenu(1, nil, VM.GearMenu, button, 0, 0)
end

function VM:StyleCloseButton(frame)
    local b = frame.CloseButton
    if not b or b.VoidMarkStyled then return end
    b.VoidMarkStyled = true
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -29)
    b:SetSize(15, 15)
    b:SetFrameLevel(frame:GetFrameLevel() + 25)
    -- Classic Era does not accept nil as a texture asset here.
    -- Keep the existing Button textures attached, but make them invisible.
    local normal = b:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local pushed = b:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local highlight = b:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    b.VoidMarkBG = b:CreateTexture(nil, "BACKGROUND")
    b.VoidMarkBG:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
    b.VoidMarkBG:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    b.VoidMarkBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    b.VoidMarkBG:SetVertexColor(0.045, 0.022, 0.065, 0.96)
    b.VoidMarkText = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.VoidMarkText:SetAllPoints(b)
    b.VoidMarkText:SetText("×")
    b.VoidMarkText:SetTextColor(0.92, 0.63, 1.0, 1)
    SetFont(b.VoidMarkText, "Fonts\\FRIZQT__.TTF", 12, "OUTLINE", GameFontNormal)
    b:SetScript("OnEnter", function(self)
        if self.VoidMarkBG then self.VoidMarkBG:SetVertexColor(0.16, 0.055, 0.22, 1) end
        if self.VoidMarkText then self.VoidMarkText:SetTextColor(1.0, 0.38, 0.52, 1) end
    end)
    b:SetScript("OnLeave", function(self)
        if self.VoidMarkBG then self.VoidMarkBG:SetVertexColor(0.045, 0.022, 0.065, 0.96) end
        if self.VoidMarkText then self.VoidMarkText:SetTextColor(0.92, 0.63, 1.0, 1) end
    end)
end

function VM:ReanchorMainRows()
    local f = VoidMark.MainWindow
    if not f or not f.Rows then return end
    local rowHeight = VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.MainWindow and VoidMark.db.profile.MainWindow.RowHeight or 16
    local rowSpacing = VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.MainWindow and VoidMark.db.profile.MainWindow.RowSpacing or 0
    for i, row in pairs(f.Rows) do
        if type(i) == "number" and i >= 1 and row then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -VM.ROW_TOP_OFFSET - (rowHeight + rowSpacing) * (i - 1))
        end
    end
end

function VM:ApplyOneTimeCompactWidth()
    local f = VoidMark.MainWindow
    local profile = VoidMark.db and VoidMark.db.profile
    if not f or not profile or not profile.MainWindow or InCombatLockdown() then return end
    if profile.VoidMarkGeneratedHeaderV1 then return end

    profile.VoidMarkGeneratedHeaderV1 = true
    local currentWidth = f:GetWidth() or profile.MainWindow.Position.w or VM.DEFAULT_MAIN_WIDTH
    local newWidth = currentWidth
    if currentWidth > VM.DEFAULT_MAIN_WIDTH then
        newWidth = VM.DEFAULT_MAIN_WIDTH
    end

    if newWidth ~= currentWidth then
        local x = f:GetLeft()
        local y = profile.InvertVoidMark and f:GetBottom() or f:GetTop()
        VoidMark:RestoreMainWindowPosition(x, y, newWidth, f:GetHeight())
        VoidMark:SaveMainWindowPosition()
    end
end

function VM:ApplyMainSkin()
    local f = VoidMark.MainWindow
    if not f then return end

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    f:SetBackdropColor(VM.BG[1], VM.BG[2], VM.BG[3], VM.BG[4])
    f:SetBackdropBorderColor(VM.PURPLE[1], VM.PURPLE[2], VM.PURPLE[3], 0.94)

    if f.Background then
        f.Background:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.Background:SetVertexColor(0.015, 0.010, 0.022, 0.96)
        f.Background:SetAlpha(1)
    end

    if f.TitleBar then
        f.TitleBar:ClearAllPoints()
        f.TitleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        f.TitleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        f.TitleBar:SetHeight(VM.HEADER_HEIGHT)
        f.TitleBar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        f.TitleBar:SetBackdropColor(0.025, 0.012, 0.038, 1)
        f.TitleBar:SetBackdropBorderColor(0.37, 0.10, 0.55, 0.95)
    end

    if f.Title then f.Title:Hide() end
    if f.RightButton then f.RightButton:Hide() end
    if f.LeftButton then f.LeftButton:Hide() end
    if f.ClearButton then f.ClearButton:Hide() end
    if f.StatsButton then f.StatsButton:Hide() end
    if f.CountButton then f.CountButton:Hide() end
    if f.CountFrame then f.CountFrame:Hide() end

    VM:StyleCloseButton(f)

    -- The secure target rows make the main frame protected in combat. Guard every
    -- ordinary movement/resize entry point so Stage 2 cannot reproduce the
    -- RestrictedExecution error from the earlier combat-drag experiment.
    f:SetScript("OnMouseDown", function(self, button)
        if InCombatLockdown() then return end
        if (((not self.isLocked) or (self.isLocked == 0)) and button == "LeftButton") then
            VoidMark:SetWindowTop(self)
            self:StartMoving()
            self.isMoving = true
        end
    end)
    f:SetScript("OnMouseUp", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            VoidMark:SaveMainWindowPosition()
        end
    end)

    if f.TitleClick then
        f.TitleClick:ClearAllPoints()
        f.TitleClick:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        f.TitleClick:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -92, -(VM.HEADER_HEIGHT + 1))
        f.TitleClick:SetFrameLevel(f:GetFrameLevel() + 8)
    end

    local grips = {f.DragBottomRight, f.DragBottomLeft, f.DragTopRight, f.DragTopLeft}
    for _, grip in ipairs(grips) do
        if grip and not grip.VoidMarkCombatGuard then
            grip.VoidMarkCombatGuard = true
            local oldDown = grip:GetScript("OnMouseDown")
            grip:SetScript("OnMouseDown", function(self, button)
                if InCombatLockdown() then return end
                if oldDown then oldDown(self, button) end
            end)
        end
    end

    -- Single generated VoidMark header image. All branding is baked into the art
    -- so compact scaling cannot cause separate text/logo layers to collide.
    if f.VoidMarkIcon then f.VoidMarkIcon:Hide() end
    if f.VoidMarkTitle then f.VoidMarkTitle:Hide() end
    if f.VoidMarkSignature then f.VoidMarkSignature:Hide() end
    if f.VoidMarkTagline then f.VoidMarkTagline:Hide() end
    if f.VoidMarkLogo then f.VoidMarkLogo:Hide() end
    if f.VoidMarkHeaderTagline then f.VoidMarkHeaderTagline:Hide() end
    if f.VoidMarkHeaderLine then f.VoidMarkHeaderLine:Hide() end

    if not f.VoidMarkGeneratedHeader then
        f.VoidMarkGeneratedHeader = f:CreateTexture(nil, "ARTWORK")
        f.VoidMarkGeneratedHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
        f.VoidMarkGeneratedHeader:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
        f.VoidMarkGeneratedHeader:SetHeight(82)
        f.VoidMarkGeneratedHeader:SetTexture("Interface\\AddOns\\VoidMarkForever\\Textures\\VoidMarkGeneratedHeader.tga")
        f.VoidMarkGeneratedHeader:SetTexCoord(0, 1, 0, 1)
    end

    if not f.VoidMarkGearButton then
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        f.VoidMarkGearButton = b
        b:SetSize(15, 15)
        b:SetPoint("TOPRIGHT", f.CloseButton, "TOPLEFT", -4, 0)
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 6,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        })
        b:SetBackdropColor(0.045, 0.022, 0.065, 0.96)
        b:SetBackdropBorderColor(0.28, 0.08, 0.40, 0.95)
        b.Icon = b:CreateTexture(nil, "ARTWORK")
        b.Icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
        b.Icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        b.Icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        b.Icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        b.Icon:SetVertexColor(0.78, 0.63, 0.92, 1)
        b:SetFrameLevel(f:GetFrameLevel() + 25)
        b:SetScript("OnClick", function(self) VM:OpenGearMenu(self) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("VoidMark", 0.78, 0.45, 1.0)
            GameTooltip:AddLine("Settings / Statistics", 0.85, 0.85, 0.85)
            if TaliaaGankRepository and TaliaaGankRepository.GetPeerStatus then
                local connected, _, peer = TaliaaGankRepository:GetPeerStatus()
                if connected then
                    GameTooltip:AddLine("Sync: Paired" .. (peer and (" • " .. tostring(peer)) or ""), 0.35, 1.0, 0.55)
                else
                    GameTooltip:AddLine("Sync: Not paired", 0.75, 0.75, 0.75)
                end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.28, 0.08, 0.40, 0.95)
            GameTooltip:Hide()
        end)
        b:HookScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.62, 0.24, 0.88, 1)
        end)
    end

    if not f.VoidMarkGTButton then
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        f.VoidMarkGTButton = b
        b:SetSize(24, 15)
        if f.VoidMarkGearButton then
            b:SetPoint("RIGHT", f.VoidMarkGearButton, "LEFT", -4, 0)
        else
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -46, -6)
        end
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 6,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        })
        b:SetBackdropColor(0.045, 0.022, 0.065, 0.96)
        b:SetBackdropBorderColor(0.34, 0.10, 0.50, 0.95)
        b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.Text:SetAllPoints()
        b.Text:SetText("GT")
        b.Text:SetTextColor(0.82, 0.62, 1.0, 1)
        b:SetFrameLevel(f:GetFrameLevel() + 25)
        b:SetScript("OnClick", function()
            if TaliaaGankTracker and TaliaaGankTracker.ToggleWindow then
                TaliaaGankTracker:ToggleWindow()
            elseif TaliaaGankTracker and TaliaaGankTracker.Frame then
                local gt = TaliaaGankTracker.Frame
                if gt:IsShown() then gt:Hide() else gt:Show() end
            end
        end)
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.68, 0.30, 1.0, 1)
            self.Text:SetTextColor(1, 1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Gank Tracker", 0.78, 0.45, 1.0)
            GameTooltip:AddLine("Show / hide GT", 0.85, 0.85, 0.85)
            if TaliaaGankTracker and TaliaaGankTracker.IsMinimized and TaliaaGankTracker:IsMinimized() then
                GameTooltip:AddLine("Compact mode", 0.65, 0.55, 0.72)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.34, 0.10, 0.50, 0.95)
            self.Text:SetTextColor(0.82, 0.62, 1.0, 1)
            GameTooltip:Hide()
        end)
    end

    -- Draw compact GT stats in two blocks so the center logo/signature remains
    -- clear: K/U/R on the far left, DK/K-S on the far right.
    if not f.VoidMarkGTCompactFrame then
        local cf = CreateFrame("Frame", nil, f)
        f.VoidMarkGTCompactFrame = cf
        cf:SetSize(430, 14)
        cf:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -67)
        cf:SetFrameLevel(f:GetFrameLevel() + 40)
        cf:EnableMouse(false)

        local left = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.VoidMarkGTCompactTextLeft = left
        left:SetPoint("LEFT", cf, "LEFT", 0, 0)
        left:SetPoint("TOP", cf, "TOP", 0, 0)
        left:SetPoint("BOTTOM", cf, "BOTTOM", 0, 0)
        left:SetWidth(150)
        left:SetJustifyH("LEFT")
        left:SetJustifyV("MIDDLE")
        left:SetText("K 0   U 0   R 0")
        left:SetTextColor(0.88, 0.78, 0.96, 1)
        SetFont(left, "Fonts\\FRIZQT__.TTF", 10, "OUTLINE", GameFontHighlightSmall)

        local right = cf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.VoidMarkGTCompactTextRight = right
        -- Anchor directly to the main VoidMark frame so DK/K-S stays tucked
        -- inside the lower-right edge instead of inheriting the compact frame width.
        right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -67)
        right:SetWidth(112)
        right:SetHeight(14)
        right:SetJustifyH("RIGHT")
        right:SetJustifyV("MIDDLE")
        right:SetText("DK 0   K/S 0")
        right:SetTextColor(0.88, 0.78, 0.96, 1)
        SetFont(right, "Fonts\\FRIZQT__.TTF", 10, "OUTLINE", GameFontHighlightSmall)

        -- Backward-compatible alias so older code paths do not error.
        f.VoidMarkGTCompactText = left

        if TaliaaGankTracker and TaliaaGankTracker.RefreshVoidMarkCompact then
            TaliaaGankTracker:RefreshVoidMarkCompact()
        end
    end

    if not f.VoidMarkModeButton then
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        f.VoidMarkModeButton = b
        b:SetSize(82, 15)
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        b:SetBackdropColor(0.01, 0.005, 0.02, 0.72)
        b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.VoidMarkModeText = b.Text
        b.Text:SetAllPoints(b)
        b.Text:SetJustifyH("RIGHT")
        b.Text:SetTextColor(0.88, 0.80, 0.94, 1)
        SetFont(b.Text, "Fonts\\FRIZQT__.TTF", 9, "", GameFontHighlightSmall)
        b:SetFrameLevel(f:GetFrameLevel() + 25)
        b:SetScript("OnClick", function(self) VM:OpenModeMenu(self) end)
        b:SetScript("OnEnter", function(self)
            self.Text:SetTextColor(1.0, 0.88, 1.0, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Select List", 0.78, 0.45, 1.0)
            GameTooltip:AddLine("Nearby • Recent • KOS • Ignore • All", 0.85, 0.85, 0.85)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self.Text:SetTextColor(0.88, 0.80, 0.94, 1)
            GameTooltip:Hide()
        end)
    end

    for _, row in pairs(f.Rows or {}) do
        if not row.VoidMarkHover then
            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints(row)
            hover:SetTexture("Interface\\Buttons\\WHITE8X8")
            hover:SetVertexColor(0.58, 0.28, 0.82, 0.16)
            row.VoidMarkHover = hover
        end
    end

    if VoidMark.CombatSightingsFrame then
        local c = VoidMark.CombatSightingsFrame
        c:SetBackdropColor(0.025, 0.012, 0.038, 0.97)
        c:SetBackdropBorderColor(0.55, 0.18, 0.85, 0.95)
        if c.Title then
            c.Title:SetText("COMBAT SIGHTINGS")
            c.Title:SetTextColor(0.78, 0.45, 1.0, 1)
        end
    end

    VM:ReanchorMainRows()
    VM:ApplyOneTimeCompactWidth()
    VM:UpdateModeLabel()
end

function VM:StyleRow(num, name, desc, opacity)
    local frame = VoidMark.MainWindow
    local row = frame and frame.Rows and frame.Rows[num]
    if not row or not name then return end

    local data = SafePlayerData(name)
    local class = data and data.class

    -- Feed row hover into Enemy Moves. Keep the existing row scripts intact:
    -- hovering only previews a player when we currently have live cooldowns
    -- recorded for them, and leaving restores the pinned/current enemy.
    row.VoidMarkEnemyMovesName = name
    row.VoidMarkEnemyMovesGUID = data and data.guid
    if not row.VoidMarkEnemyMovesHoverHooked then
        row.VoidMarkEnemyMovesHoverHooked = true
        row:HookScript("OnEnter", function(self)
            if VoidMarkEnemyMoves and VoidMarkEnemyMoves.HoverPlayer then
                VoidMarkEnemyMoves:HoverPlayer(self.VoidMarkEnemyMovesName,self.VoidMarkEnemyMovesGUID)
            end
        end)
        row:HookScript("OnLeave", function()
            if VoidMarkEnemyMoves and VoidMarkEnemyMoves.ClearHover then
                VoidMarkEnemyMoves:ClearHover()
            end
        end)
    end
    local r, g, b = ClassColor(class)
    local isKOS = IsKOS(name)
    local isStealth = IsStealth(name)

    local marker = ""
    if isKOS then
        marker = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:13:13:0:0|t "
    elseif isStealth then
        marker = "|TInterface\\Icons\\Ability_Stealth:13:13:0:0|t "
    end

    local displayName = VoidMarkForever.DisplayName(name)
    row.LeftText:SetText(marker .. displayName)
    row.LeftText:SetTextColor(r, g, b, opacity or 1)

    local status = isKOS and "|cffff4d5dKOS|r" or ""

    -- Integrated corpse run timer.
    local runBack = VoidMark.GetRunBackDisplay and VoidMark:GetRunBackDisplay(name) or nil
    local runBackTime = ""
    local runBackColor = "|cffffd84d"
    if runBack then
        if runBack.ready then
            runBackColor = "|cffff5b65"
        end
        runBackTime = runBack.time or ""
    end

    local levelText = (data and data.level) and tostring(data.level) or ""
    local classIcon = ClassIconTag(class, 16)
    if classIcon == "" and class then
        classIcon = tostring(class)
    end

    local kills = tonumber(data and data.wins) or 0
    local deaths = tonumber(data and data.loses) or 0
    if TaliaaGankRepository and TaliaaGankRepository.GetHistoricalStats then
        local repoKills, repoDeaths = TaliaaGankRepository:GetHistoricalStats(name, data and data.guid)
        kills = math.max(kills, tonumber(repoKills) or 0)
        deaths = math.max(deaths, tonumber(repoDeaths) or 0)
    end
    local record = string.format("|cffb9a3c9%d-%d|r", kills, deaths)

    local function MatchRightFont(fs)
        if not fs then return end
        local font, size, flags = row.RightText:GetFont()
        if font and size then fs:SetFont(font, size, flags or "") end
    end

    if not row.VoidMarkRecordText then
        row.VoidMarkRecordText = row.StatusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.VoidMarkRecordText:SetJustifyH("RIGHT")
        MatchRightFont(row.VoidMarkRecordText)
    end
    row.VoidMarkRecordText:ClearAllPoints()
    row.VoidMarkRecordText:SetPoint("RIGHT", row.StatusBar, "RIGHT", -2, 0)
    row.VoidMarkRecordText:SetWidth(31)
    row.VoidMarkRecordText:SetText(record)
    row.VoidMarkRecordText:SetTextColor(0.73, 0.64, 0.79, opacity or 1)

    if not row.VoidMarkClassText then
        row.VoidMarkClassText = row.StatusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.VoidMarkClassText:SetJustifyH("CENTER")
        MatchRightFont(row.VoidMarkClassText)
    end
    row.VoidMarkClassText:ClearAllPoints()
    row.VoidMarkClassText:SetPoint("RIGHT", row.VoidMarkRecordText, "LEFT", -3, 0)
    row.VoidMarkClassText:SetWidth(20)
    row.VoidMarkClassText:SetText(classIcon)
    row.VoidMarkClassText:SetTextColor(0.90, 0.90, 0.94, opacity or 1)

    row.RightText:ClearAllPoints()
    row.RightText:SetPoint("RIGHT", row.VoidMarkClassText, "LEFT", -3, 0)
    row.RightText:SetWidth(24)
    row.RightText:SetJustifyH("RIGHT")
    row.RightText:SetText(levelText)
    row.RightText:SetTextColor(0.90, 0.90, 0.94, opacity or 1)

    if not row.VoidMarkThreatText then
        row.VoidMarkThreatText = row.StatusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.VoidMarkThreatText:SetJustifyH("RIGHT")
        MatchRightFont(row.VoidMarkThreatText)
    end
    row.VoidMarkThreatText:ClearAllPoints()
    row.VoidMarkThreatText:SetPoint("RIGHT", row.RightText, "LEFT", -3, 0)
    row.VoidMarkThreatText:SetWidth(42)
    row.VoidMarkThreatText:SetText(status)
    row.VoidMarkThreatText:SetTextColor(0.90, 0.90, 0.94, opacity or 1)

    if not row.VoidMarkRunBackTime then
        row.VoidMarkRunBackTime = row.StatusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.VoidMarkRunBackTime:SetJustifyH("RIGHT")
        row.VoidMarkRunBackTime:SetWordWrap(false)
        MatchRightFont(row.VoidMarkRunBackTime)
    end
    row.VoidMarkRunBackTime:ClearAllPoints()
    row.VoidMarkRunBackTime:SetPoint("RIGHT", row.VoidMarkThreatText, "LEFT", -4, 0)
    row.VoidMarkRunBackTime:SetWidth(48)
    row.VoidMarkRunBackTime:SetText(runBackColor .. runBackTime .. "|r")
    row.VoidMarkRunBackTime:SetTextColor(1, 1, 1, opacity or 1)

    if row.VoidMarkRunBackLabel then
        row.VoidMarkRunBackLabel:SetText("")
        row.VoidMarkRunBackLabel:Hide()
    end
    if row.VoidMarkRunBackText then
        row.VoidMarkRunBackText:SetText("")
        row.VoidMarkRunBackText:Hide()
    end

    local cr, cg, cb = VM.ROW_UNKNOWN[1], VM.ROW_UNKNOWN[2], VM.ROW_UNKNOWN[3]
    if runBack then
        cr, cg, cb = 0.24, 0.025, 0.035
    elseif isKOS then
        cr, cg, cb = VM.ROW_KOS[1], VM.ROW_KOS[2], VM.ROW_KOS[3]
    elseif isStealth then
        cr, cg, cb = VM.ROW_STEALTH[1], VM.ROW_STEALTH[2], VM.ROW_STEALTH[3]
    end

    local alpha = opacity or 1
    if VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.CurrentList == 1 then
        local seenAt = VoidMark.NearbyList and VoidMark.NearbyList[name]
        local age = seenAt and (time() - seenAt) or 0
        if age > 45 then
            alpha = math.min(alpha, 0.55)
        elseif age > 15 then
            alpha = math.min(alpha, 0.78)
        end
    end

    row.StatusBar:SetStatusBarColor(cr, cg, cb, alpha)

    local rightColumnsWidth = 46 + 4 + 42 + 3 + 24 + 3 + 20 + 3 + 31 + 4
    row.LeftText:SetWidth(math.max(40, row:GetWidth() - rightColumnsWidth - 4))
end

local function CreateDetailLabel(parent, y, label)
    local left = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    left:SetWidth(84)
    left:SetJustifyH("LEFT")
    left:SetText(label)
    left:SetTextColor(0.58, 0.48, 0.65, 1)

    local right = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right:SetPoint("TOPLEFT", parent, "TOPLEFT", 98, y)
    right:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
    right:SetJustifyH("LEFT")
    right:SetTextColor(0.90, 0.90, 0.94, 1)
    return right
end

function VM:CreateDetailsFrame()
    if VM.DetailsFrame then return VM.DetailsFrame end

    local f = CreateFrame("Frame", "VoidMark_DetailsFrame", UIParent, "BackdropTemplate")
    VM.DetailsFrame = f
    f:SetSize(292, 224)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    f:SetBackdropColor(0.012, 0.008, 0.020, 0.98)
    f:SetBackdropBorderColor(0.55, 0.18, 0.82, 0.96)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    f.Header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.Header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    f.Header:SetText("VoidMark • Player Intel")
    f.Header:SetTextColor(0.78, 0.45, 1.0, 1)
    SetFont(f.Header, "Fonts\\MORPHEUS.ttf", 12, "OUTLINE", GameFontNormal)

    f.Close = CreateFrame("Button", nil, f)
    f.Close:SetSize(16, 16)
    f.Close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    f.Close.Text = f.Close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.Close.Text:SetAllPoints(f.Close)
    f.Close.Text:SetText("×")
    f.Close.Text:SetTextColor(1.0, 0.24, 0.32, 1)
    f.Close:SetScript("OnClick", function() f:Hide() end)

    f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
    f.Name:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.Name:SetJustifyH("LEFT")
    SetFont(f.Name, "Fonts\\FRIZQT__.TTF", 12, "OUTLINE", GameFontNormal)

    f.LevelClass = CreateDetailLabel(f, -50, "Identity")
    f.Threat = CreateDetailLabel(f, -67, "Threat")
    f.Record = CreateDetailLabel(f, -84, "Fight Record")
    f.Lifetime = CreateDetailLabel(f, -101, "Lifetime")
    f.Ganks = f.Lifetime
    f.Damage = CreateDetailLabel(f, -118, "Damage")
    f.LastSeen = CreateDetailLabel(f, -135, "Last Seen")
    f.Location = CreateDetailLabel(f, -152, "Location")
    f.Note = CreateDetailLabel(f, -169, "Note")

    f.TargetButton = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.TargetButton:SetSize(72, 20)
    f.TargetButton:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    f.TargetButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6 })
    f.TargetButton:SetBackdropColor(0.07, 0.04, 0.10, 1)
    f.TargetButton:SetBackdropBorderColor(0.42, 0.16, 0.62, 1)
    f.TargetButton.Text = f.TargetButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.TargetButton.Text:SetAllPoints(f.TargetButton)
    f.TargetButton.Text:SetText("Target")
    f.TargetButton:SetScript("OnClick", function()
        local name = f.playerName
        if not name then return end
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage("VoidMark: use the Nearby row to target during combat.", 0.75, 0.45, 1.0, 1.0)
            return
        end
        if TargetByName then TargetByName(VoidMarkForever.TargetName(name), true) end
    end)

    f.NoteButton = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.NoteButton:SetSize(86, 20)
    f.NoteButton:SetPoint("LEFT", f.TargetButton, "RIGHT", 8, 0)
    f.NoteButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6 })
    f.NoteButton:SetBackdropColor(0.07, 0.04, 0.10, 1)
    f.NoteButton:SetBackdropBorderColor(0.42, 0.16, 0.62, 1)
    f.NoteButton.Text = f.NoteButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.NoteButton.Text:SetAllPoints(f.NoteButton)
    f.NoteButton.Text:SetText("Add Note")
    f.NoteButton:SetScript("OnClick", function()
        if f.playerName then StaticPopup_Show("VOIDMARK_ADD_NOTE", nil, nil, f.playerName) end
    end)

    f:Hide()
    return f
end

StaticPopupDialogs["VOIDMARK_ADD_NOTE"] = {
    text = "VoidMark note",
    button1 = ACCEPT,
    button2 = CANCEL,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    hasEditBox = true,
    editBoxWidth = 260,
    OnShow = function(self)
        local name = self.data
        local data = name and SafePlayerData(name)
        local edit = self.GetEditBox and self:GetEditBox() or self.editBox
        if edit then
            edit:SetText((data and data.voidMarkNote) or "")
            edit:SetFocus()
            edit:HighlightText()
        end
    end,
    OnAccept = function(self)
        local name = self.data
        local data = name and SafePlayerData(name)
        local edit = self.GetEditBox and self:GetEditBox() or self.editBox
        if data and edit then
            local note = strtrim(edit:GetText() or "")
            data.voidMarkNote = note ~= "" and note or nil
            if VM.DetailsFrame and VM.DetailsFrame.playerName == name then
                VoidMark:ShowVoidMarkDetails(name)
            end
        end
    end,
}

function VoidMark:ShowVoidMarkDetails(name)
    if not name or name == "" then return end
    local data = SafePlayerData(name)
    if not data then return end

    local f = VM:CreateDetailsFrame()
    f.playerName = name

    local r, g, b = ClassColor(data.class)
    f.Name:SetText(name)
    f.Name:SetTextColor(r, g, b, 1)

    local identity = "L" .. tostring(data.level or "?") .. " " .. tostring(data.class and (RAID_CLASS_COLORS[data.class] and data.class or data.class) or "Unknown")
    f.LevelClass:SetText(identity)

    if f.Threat then f.Threat:Hide() end
    if f.Record then f.Record:Hide() end
    if f.Damage then f.Damage:Hide() end

    -- Lifetime is the old VoidMark/gank history. Keep it separate from the newer
    -- fight-based threat record so archived kills do not appear to vanish.
    local kills = tonumber(data.wins) or 0
    local deaths = tonumber(data.loses) or 0
    if TaliaaGankRepository and TaliaaGankRepository.GetHistoricalStats then
        local repoKills, repoDeaths = TaliaaGankRepository:GetHistoricalStats(name, data.guid)
        kills = math.max(kills, tonumber(repoKills) or 0)
        deaths = math.max(deaths, tonumber(repoDeaths) or 0)
    end
    f.Lifetime:SetText(string.format("%d kills / %d deaths", kills, deaths))
    f.LastSeen:SetText(AgeText(data.time))
    f.Location:SetText(VoidMark.GetPlayerLocation and VoidMark:GetPlayerLocation(data) or tostring(data.zone or "Unknown"))
    f.Note:SetText(data.voidMarkNote or "—")

    f:ClearAllPoints()
    local left = VoidMark.MainWindow and VoidMark.MainWindow:GetLeft() or 0
    if left and left > 250 then
        f:SetPoint("TOPRIGHT", VoidMark.MainWindow, "TOPLEFT", -8, 0)
    else
        f:SetPoint("TOPLEFT", VoidMark.MainWindow, "TOPRIGHT", 8, 0)
    end
    f:Show()
end

-- Correct the old context-menu lookup to always use the real row name, then add
-- Hunt/Details actions without changing the existing KOS/Ignore actions.
local OriginalBarDropDown = VoidMark_CreateBarDropdown
function VoidMark_CreateBarDropdown(self, level)
    OriginalBarDropDown(self, level)
    if level ~= 1 then return end
    local row = self and self.relativeTo
    local player = row and (row.Name or VoidMark.ButtonName[row.id])
    if not player or player == "" then return end

    local info = UIDropDownMenu_CreateInfo()
    info.notCheckable = true
    info.text = "Details"
    info.func = function()
        VoidMark:ShowVoidMarkDetails(player)
        CloseDropDownMenus(1)
    end
    UIDropDownMenu_AddButton(info, level)
end

-- Preserve normal secure click-targeting, but Shift+Click now opens the compact
-- intel panel instead of toggling KOS. KOS remains available on right-click.
local function EnsureVoidMarkContextMenu()
    if VM.ContextMenu then return VM.ContextMenu end

    local menu = CreateFrame("Frame", "VoidMarkContextMenu", UIParent, "BackdropTemplate")
    VM.ContextMenu = menu
    menu:SetSize(178, 105)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0.025, 0.015, 0.045, 0.98)
    menu:SetBackdropBorderColor(0.55, 0.25, 0.80, 1)
    menu:EnableMouse(true)
    menu:Hide()

    menu.Title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.Title:SetPoint("TOPLEFT", 9, -8)
    menu.Title:SetPoint("TOPRIGHT", -9, -8)
    menu.Title:SetJustifyH("LEFT")
    menu.Title:SetTextColor(0.82, 0.62, 1.0, 1)

    local function MakeButton(index)
        local b = CreateFrame("Button", nil, menu)
        b:SetHeight(21)
        b:SetPoint("TOPLEFT", 6, -26 - ((index - 1) * 23))
        b:SetPoint("TOPRIGHT", -6, -26 - ((index - 1) * 23))
        b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.Text:SetPoint("LEFT", 5, 0)
        b.Text:SetPoint("RIGHT", -5, 0)
        b.Text:SetJustifyH("LEFT")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(0.45, 0.18, 0.65, 0.35)
        return b
    end

    menu.Buttons = {}
    for i = 1, 3 do menu.Buttons[i] = MakeButton(i) end

    menu:SetScript("OnShow", function(self)
        self:SetFrameLevel(1000)
    end)

    return menu
end

function VoidMark:ShowVoidMarkContextMenu(row, name)
    if not name or name == "" then return end
    local menu = EnsureVoidMarkContextMenu()
    menu.PlayerName = name

    local displayName = (VoidMarkForever and VoidMarkForever.DisplayName and VoidMarkForever.DisplayName(name)) or name
    menu.Title:SetText(displayName)

    local isKOS = VoidMarkPerCharDB and VoidMarkPerCharDB.KOSData and VoidMarkPerCharDB.KOSData[name]
    local isIgnored = VoidMarkPerCharDB and VoidMarkPerCharDB.IgnoreData and VoidMarkPerCharDB.IgnoreData[name]

    local b1, b2, b3 = unpack(menu.Buttons)
    b1.Text:SetText(isKOS and "Remove from KOS" or "Add to KOS")
    b1:SetScript("OnClick", function()
        VoidMark:ToggleKOSPlayer(not isKOS, name)
        menu:Hide()
    end)

    b2.Text:SetText(isIgnored and "Remove from Ignore" or "Add to Ignore")
    b2:SetScript("OnClick", function()
        VoidMark:ToggleIgnorePlayer(not isIgnored, name)
        menu:Hide()
    end)

    b3.Text:SetText("Details")
    b3:SetScript("OnClick", function()
        menu:Hide()
        VoidMark:ShowVoidMarkDetails(name)
    end)

    menu:ClearAllPoints()
    if row and row.GetRight and row:GetRight() and row:GetRight() < (GetScreenWidth() * 0.72) then
        menu:SetPoint("TOPLEFT", row, "TOPRIGHT", 5, 2)
    elseif row then
        menu:SetPoint("TOPRIGHT", row, "TOPLEFT", -5, 2)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
    menu:Show()
end

-- Preserve secure left-click targeting. Shift+Click opens details. Right-click
-- uses the VoidMark-native menu above instead of Blizzard UIDropDownMenu.
local OriginalButtonClicked = VoidMark.ButtonClicked
function VoidMark:ButtonClicked(row, button)
    local name = row and (VoidMark.ButtonName[row.id] or row.Name)
    if button == "LeftButton" and IsShiftKeyDown() and name then
        VoidMark:ShowVoidMarkDetails(name)
        return
    elseif button == "RightButton" and name then
        VoidMark:ShowVoidMarkContextMenu(row, name)
        return
    end
    -- The current list handler is a colon method: keep its addon, row and
    -- button arguments aligned so control-click still toggles Ignore.
    return OriginalButtonClicked(self, row, button)
end

local OriginalSetBar = VoidMark.SetBar
function VoidMark:SetBar(num, name, desc, value, colorgroup, colorclass, tooltipData, opacity)
    OriginalSetBar(self, num, name, desc, value, colorgroup, colorclass, tooltipData, opacity)
    VM:StyleRow(num, name, desc, opacity)
end

local OriginalSetupMainWindowButtons = VoidMark.SetupMainWindowButtons
function VoidMark:SetupMainWindowButtons(...)
    local result = OriginalSetupMainWindowButtons(self, ...)
    local f = VoidMark.MainWindow
    if f then
        if f.RightButton then f.RightButton:Hide() end
        if f.LeftButton then f.LeftButton:Hide() end
        if f.ClearButton then f.ClearButton:Hide() end
        if f.StatsButton then f.StatsButton:Hide() end
        if f.CountButton then f.CountButton:Hide() end
        if f.CountFrame then f.CountFrame:Hide() end
    end
    return result
end

local OriginalCreateMainWindow = VoidMark.CreateMainWindow
function VoidMark:CreateMainWindow(...)
    local result = OriginalCreateMainWindow(self, ...)
    VM:ApplyMainSkin()
    return result
end

local OriginalSetCurrentList = VoidMark.SetCurrentList
function VoidMark:SetCurrentList(mode)
    local result = OriginalSetCurrentList(self, mode)
    VM:UpdateModeLabel()
    return result
end

local OriginalUpdateActiveCount = VoidMark.UpdateActiveCount
function VoidMark:UpdateActiveCount(...)
    local result = OriginalUpdateActiveCount(self, ...)
    VM:UpdateModeLabel()
    return result
end

local OriginalAutomaticallyResize = VoidMark.AutomaticallyResize
function VoidMark:AutomaticallyResize(...)
    local result = OriginalAutomaticallyResize(self, ...)
    if not InCombatLockdown() and VoidMark.MainWindow and VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.MainWindow then
        local detected = VoidMark.ListAmountDisplayed or 0
        if detected > (VoidMark.db.profile.ResizeVoidMarkLimit or detected) then detected = VoidMark.db.profile.ResizeVoidMarkLimit end
        local rowHeight = VoidMark.db.profile.MainWindow.RowHeight or 16
        local rowSpacing = VoidMark.db.profile.MainWindow.RowSpacing or 0
        local height = (VM.ROW_TOP_OFFSET + 1) + (detected * (rowHeight + rowSpacing))
        local x = VoidMark.MainWindow:GetLeft()
        local y = VoidMark.db.profile.InvertVoidMark and VoidMark.MainWindow:GetBottom() or VoidMark.MainWindow:GetTop()
        VoidMark:RestoreMainWindowPosition(x, y, VoidMark.MainWindow:GetWidth(), height)
        VM:ReanchorMainRows()
    end
    return result
end

local OriginalManageBarsDisplayed = VoidMark.ManageBarsDisplayed
function VoidMark:ManageBarsDisplayed(...)
    local result = OriginalManageBarsDisplayed(self, ...)
    if VoidMark.MainWindow and VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.MainWindow then
        local detected = VoidMark.ListAmountDisplayed or 0
        local rowHeight = VoidMark.db.profile.MainWindow.RowHeight or 16
        local rowSpacing = VoidMark.db.profile.MainWindow.RowSpacing or 0
        local bars = math.floor((VoidMark.MainWindow:GetHeight() - VM.ROW_TOP_OFFSET) / (rowHeight + rowSpacing))
        if bars > detected then bars = detected end
        if bars > (VoidMark.db.profile.ResizeVoidMarkLimit or bars) then bars = VoidMark.db.profile.ResizeVoidMarkLimit end
        VoidMark.MainWindow.CurRows = math.max(0, bars)
        if not InCombatLockdown() then
            for i, row in pairs(VoidMark.MainWindow.Rows or {}) do
                if type(i) == "number" and i >= 1 then
                    if i <= VoidMark.MainWindow.CurRows then row:Show() else row:Hide() end
                end
            end
            VM:ReanchorMainRows()
        end
    end
    return result
end

local OriginalResizeMainWindow = VoidMark.ResizeMainWindow
function VoidMark:ResizeMainWindow(...)
    local result = OriginalResizeMainWindow(self, ...)
    VM:ReanchorMainRows()
    VM:UpdateModeLabel()
    return result
end

local OriginalShowTooltip = VoidMark.ShowTooltip
function VoidMark:ShowTooltip(row, show, id)
    local result = OriginalShowTooltip(self, row, show, id)
    if show and GameTooltip and GameTooltip:IsShown() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift+Click: Details", 0.72, 0.46, 0.92)
        GameTooltip:AddLine("Right-click: Actions", 0.55, 0.55, 0.60)
        GameTooltip:Show()
    end
    return result
end

-- Apply a queued mode change after combat, when secure row assignments can be
-- safely rebuilt.
local eventFrame = CreateFrame("Frame")
VoidMarkForever.RegisterEvent(eventFrame,"PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function()
    if VoidMark.VoidMarkPendingMode then
        local mode = VoidMark.VoidMarkPendingMode
        VoidMark.VoidMarkPendingMode = nil
        C_Timer.After(0, function()
            if VoidMark and VoidMark.SetCurrentList then VoidMark:SetCurrentList(mode) end
        end)
    end
    VM:UpdateModeLabel()
end)

-- Visible branding only. Keep the backend addon name/signature as VoidMark so saved
-- data and addon-message compatibility remain intact.
if VoidMark.options then VoidMark.options.name = "VoidMark" end
