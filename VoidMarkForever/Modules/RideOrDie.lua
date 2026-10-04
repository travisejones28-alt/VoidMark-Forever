local VMAPI = VoidMarkForever.API
local ADDON_NAME = ...
local VERSION = "0.5.2"

local TRD = CreateFrame("Frame", "TaliaasRideOrDieFrame")
_G.TaliaasRideOrDie = TRD

local PURPLE = { 0.71, 0.42, 1.00 }
local BG = { 0.045, 0.025, 0.065, 0.96 }
local BORDER = { 0.42, 0.20, 0.58, 1.00 }
local BTN_BG = { 0.13, 0.07, 0.17, 1 }
local BTN_HOVER = { 0.21, 0.10, 0.30, 1 }
local BTN_ACTIVE = { 0.24, 0.12, 0.35, 1 }

local SLOT_IDS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local LEGACY_SCHEMA = 4
local CURRENT_SCHEMA = 5

local DEFAULT_DB = {
    schema = CURRENT_SCHEMA,
    enabled = true,
    sets = {},
    setOrder = { "PvP", "Holy", "Shadow", "Riding" },
    selectedSet = "PvP",
    defaultGroundSet = "PvP",
    ridingSetName = "Riding",
    pendingMode = nil,
    frameX = 0,
    frameY = 0,
}

local EquipByName = (C_Item and C_Item.EquipItemByName) or EquipItemByName
local StaticPopupDialogs = StaticPopupDialogs

local function CopyTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do out[k] = CopyTable(v) end
    return out
end

local function Chat(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFB56CFFRide or Die|r |cFF70508B»|r " .. tostring(msg))
end

local function CurrentItem(slot)
    return GetInventoryItemLink("player", slot)
end

local function IsRealMount()
    return IsMounted() and not VoidMarkForever.API.UnitOnTaxi("player")
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function SetBackdrop(frame, bgColor, borderColor)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    frame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
end

local function CaptureCurrentSet()
    local set = {}
    for _, slot in ipairs(SLOT_IDS) do
        local link = CurrentItem(slot)
        if link then set[slot] = link end
    end
    return set
end

local function TableCount(t)
    local n = 0
    for _, v in pairs(t or {}) do
        if v then n = n + 1 end
    end
    return n
end

local function Trim(s)
    return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function NormalizeName(name)
    return Trim(name)
end

local function SetExists(name)
    name = NormalizeName(name)
    return name ~= "" and TRD.db and TRD.db.sets and TRD.db.sets[name] ~= nil
end

local function EnsureSetInOrder(name)
    if not name or name == "" then return end
    for _, v in ipairs(TRD.db.setOrder) do
        if v == name then return end
    end
    table.insert(TRD.db.setOrder, name)
end

local function RemoveFromOrder(name)
    for i, v in ipairs(TRD.db.setOrder) do
        if v == name then
            table.remove(TRD.db.setOrder, i)
            return
        end
    end
end

local function IsReservedName(name)
    name = NormalizeName(name)
    return name == "Riding"
end

function TRD:GetSelectedSetName()
    local selected = self.db.selectedSet
    if selected and self.db.sets[selected] then return selected end
    return self.db.defaultGroundSet or "PvP"
end

function TRD:GetGroundSetName()
    local name = self.db.defaultGroundSet
    if name and self.db.sets[name] then return name end
    for _, setName in ipairs(self.db.setOrder) do
        if setName ~= self.db.ridingSetName and self.db.sets[setName] then
            self.db.defaultGroundSet = setName
            return setName
        end
    end
    return nil
end

function TRD:GetRidingSetName()
    local name = self.db.ridingSetName or "Riding"
    if name and self.db.sets[name] then return name end
    return nil
end

function TRD:GetDesiredMode()
    if VoidMarkForever.API.UnitOnTaxi("player") then return nil end
    return IsRealMount() and "riding" or "ground"
end

function TRD:GetSetForMode(mode)
    if mode == "riding" then
        return self:GetRidingSetName()
    elseif mode == "ground" then
        return self:GetGroundSetName()
    end
    return nil
end

function TRD:EnsureMinimumSets()
    self.db.sets = self.db.sets or {}
    self.db.setOrder = self.db.setOrder or {}

    local defaults = {
        PvP = self.db.sets.PvP or {},
        Holy = self.db.sets.Holy or {},
        Shadow = self.db.sets.Shadow or {},
        Riding = self.db.sets.Riding or {},
    }

    for name, set in pairs(defaults) do
        if not self.db.sets[name] then self.db.sets[name] = set end
        EnsureSetInOrder(name)
    end

    if not self.db.selectedSet or not self.db.sets[self.db.selectedSet] then
        self.db.selectedSet = self.db.defaultGroundSet or "PvP"
    end
    if not self.db.defaultGroundSet or not self.db.sets[self.db.defaultGroundSet] or self.db.defaultGroundSet == self.db.ridingSetName then
        self.db.defaultGroundSet = "PvP"
    end
end

local function EnsureDB()
    TRD_DB = TRD_DB or {}
    for key, value in pairs(DEFAULT_DB) do
        if TRD_DB[key] == nil then
            TRD_DB[key] = CopyTable(value)
        end
    end

    if (TRD_DB.schema or 1) <= LEGACY_SCHEMA and (TRD_DB.pvpSet or TRD_DB.ridingSet) then
        TRD_DB.sets = TRD_DB.sets or {}
        TRD_DB.setOrder = TRD_DB.setOrder or { "PvP", "Holy", "Shadow", "Riding" }

        if next(TRD_DB.pvpSet or {}) then
            TRD_DB.sets.PvP = CopyTable(TRD_DB.pvpSet)
        elseif not TRD_DB.sets.PvP then
            TRD_DB.sets.PvP = {}
        end

        if next(TRD_DB.ridingSet or {}) then
            local rebuilt = {}
            local pvp = TRD_DB.pvpSet or {}
            for _, slot in ipairs(SLOT_IDS) do
                rebuilt[slot] = TRD_DB.ridingSet[slot] or pvp[slot]
            end
            TRD_DB.sets.Riding = rebuilt
        elseif not TRD_DB.sets.Riding then
            TRD_DB.sets.Riding = {}
        end

        TRD_DB.sets.Holy = TRD_DB.sets.Holy or {}
        TRD_DB.sets.Shadow = TRD_DB.sets.Shadow or {}
        TRD_DB.defaultGroundSet = TRD_DB.defaultGroundSet or "PvP"
        TRD_DB.selectedSet = TRD_DB.selectedSet or TRD_DB.defaultGroundSet
        TRD_DB.ridingSetName = "Riding"
        TRD_DB.pvpSet = nil
        TRD_DB.ridingSet = nil
        TRD_DB.schema = CURRENT_SCHEMA
    end

    TRD.db = TRD_DB
    TRD:EnsureMinimumSets()
end

function TRD:SaveSet(name)
    name = NormalizeName(name)
    if name == "" then return end
    self.db.sets[name] = CaptureCurrentSet()
    EnsureSetInOrder(name)
    self.db.selectedSet = name
    if name ~= self.db.ridingSetName and (not self.db.defaultGroundSet or self.db.defaultGroundSet == "") then
        self.db.defaultGroundSet = name
    end
    self:RefreshUI()
    Chat(name .. " set saved.")
end

function TRD:EquipSet(name, quiet)
    name = NormalizeName(name)
    local set = self.db.sets[name]
    if not set or not next(set) then
        if not quiet then Chat(name .. " set is empty.") end
        return false
    end
    if VMAPI.UnitIsDeadOrGhost("player") or VoidMarkForever.API.UnitOnTaxi("player") then return false end

    if InCombat() then
        if name == self:GetRidingSetName() then
            self.db.pendingMode = "riding"
        else
            self.db.pendingMode = "ground"
            self.db.pendingGroundSet = name
        end
        self:RefreshUI()
        return false
    end

    local changed = 0
    for _, slot in ipairs(SLOT_IDS) do
        local desired = set[slot]
        if desired and desired ~= CurrentItem(slot) then
            EquipByName(desired, slot)
            changed = changed + 1
        end
    end

    self.db.pendingMode = nil
    self.db.pendingGroundSet = nil
    self.lastEquippedSet = name
    self:RefreshUI()

    if changed > 0 and not quiet then
        Chat(name .. " equipped.")
    end
    return true
end

function TRD:ApplyMode(mode, quiet)
    if not self.db.enabled and mode ~= "ground" and mode ~= "riding" then return false end
    local targetSet = self:GetSetForMode(mode)
    if mode == "ground" and self.db.pendingGroundSet and self.db.sets[self.db.pendingGroundSet] then
        targetSet = self.db.pendingGroundSet
    end
    if not targetSet then return false end
    return self:EquipSet(targetSet, quiet)
end

function TRD:CheckMountState(force)
    if not self.db then return end
    if not self.db.enabled then
        self:RefreshUI()
        return
    end
    if VMAPI.UnitIsDeadOrGhost("player") then return end
    if VoidMarkForever.API.UnitOnTaxi("player") then
        self:RefreshUI()
        return
    end

    local mounted = IsRealMount()
    if not force and self.wasMounted == mounted then return end
    self.wasMounted = mounted

    if mounted then
        C_Timer.After(0.25, function()
            if TRD.db and TRD.db.enabled and IsRealMount() then
                TRD:ApplyMode("riding")
            end
        end)
    else
        self:ApplyMode("ground")
    end

    self:RefreshUI()
end

local function MakeButton(parent, label, width, callback)
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local b = CreateFrame("Button", nil, parent, template)
    b:SetSize(width, 24)
    SetBackdrop(b, BTN_BG, BORDER)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b.text:SetTextColor(0.92, 0.84, 1.00)

    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(BTN_HOVER[1], BTN_HOVER[2], BTN_HOVER[3], 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(BTN_BG[1], BTN_BG[2], BTN_BG[3], 1)
    end)
    b:SetScript("OnClick", callback)
    return b
end

local function MakeSetRow(parent, index)
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local row = CreateFrame("Button", nil, parent, template)
    row:SetSize(160, 30)
    SetBackdrop(row, BTN_BG, { 0.22, 0.12, 0.32, 1 })

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", 10, 0)
    row.text:SetJustifyH("LEFT")

    row.index = index
    row:SetScript("OnClick", function(self)
        local name = TRD.db.setOrder[self.index]
        if name then
            TRD.db.selectedSet = name
            TRD:RefreshUI()
        end
    end)
    return row
end

local function MakeCheckbox(parent, label)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetText(label)
    c.label:SetTextColor(0.84, 0.78, 0.90)
    return c
end

function TRD:PromptCreateSet()
    StaticPopup_Show("TRD_NEW_SET")
end

function TRD:PromptRenameSet()
    local selected = self:GetSelectedSetName()
    if not selected then return end
    if selected == self.db.ridingSetName then
        Chat("Riding stays named Riding.")
        return
    end
    self.renameSourceSet = selected
    StaticPopup_Show("TRD_RENAME_SET", selected)
end

function TRD:DeleteSelectedSet()
    local name = self:GetSelectedSetName()
    if not name then return end
    if name == self.db.ridingSetName then
        Chat("Can't delete the Riding set.")
        return
    end
    if name == self.db.defaultGroundSet then
        Chat("Pick another default set first.")
        return
    end
    self.db.sets[name] = nil
    RemoveFromOrder(name)
    self.db.selectedSet = self:GetGroundSetName() or self.db.ridingSetName
    self:RefreshUI()
    Chat(name .. " deleted.")
end

function TRD:SetSelectedAsDefault(flag)
    local name = self:GetSelectedSetName()
    if not name or name == self.db.ridingSetName then
        self.ui.defaultCheck:SetChecked(false)
        return
    end
    if flag then
        self.db.defaultGroundSet = name
        Chat(name .. " is now your default set after riding/combat.")
    else
        self.ui.defaultCheck:SetChecked(true)
        return
    end
    self:RefreshUI()
end

function TRD:CreateUI()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local f = CreateFrame("Frame", "TaliaasRideOrDieConfig", UIParent, template)
    self.ui = f
    f:SetSize(540, 390)
    f:SetPoint("CENTER", UIParent, "CENTER", self.db.frameX or 0, self.db.frameY or 0)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    SetBackdrop(f, BG, BORDER)

    f:SetScript("OnDragStart", function(frame)
        if not InCombat() then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local cx, cy = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            TRD.db.frameX = math.floor(cx - ux + 0.5)
            TRD.db.frameY = math.floor(cy - uy + 0.5)
        end
    end)

    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface/Buttons/WHITE8X8")
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    accent:SetVertexColor(PURPLE[1], PURPLE[2], PURPLE[3], 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetText("VOIDMARK  •  RIDE OR DIE")
    title:SetTextColor(PURPLE[1], PURPLE[2], PURPLE[3])

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Gear manager   v" .. VERSION)
    subtitle:SetTextColor(0.75, 0.67, 0.85)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -4)

    -- LEFT: set list -------------------------------------------------------
    local leftPanel = CreateFrame("Frame", nil, f, template)
    leftPanel:SetPoint("TOPLEFT", 14, -52)
    leftPanel:SetSize(195, 310)
    SetBackdrop(leftPanel, {0.035, 0.018, 0.052, 0.45}, {0.18, 0.09, 0.25, 1})

    local leftTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 10, -9)
    leftTitle:SetText("GEAR SETS")
    leftTitle:SetTextColor(0.88, 0.80, 0.98)

    f.rows = {}
    for i = 1, 7 do
        local row = MakeSetRow(leftPanel, i)
        row:SetSize(175, 30)
        row:SetPoint("TOPLEFT", 10, -31 - ((i - 1) * 33))
        f.rows[i] = row
    end

    local newBtn = MakeButton(leftPanel, "New", 53, function() TRD:PromptCreateSet() end)
    newBtn:SetPoint("BOTTOMLEFT", 10, 10)

    local renameBtn = MakeButton(leftPanel, "Rename", 65, function() TRD:PromptRenameSet() end)
    renameBtn:SetPoint("LEFT", newBtn, "RIGHT", 5, 0)

    local delBtn = MakeButton(leftPanel, "Delete", 53, function() TRD:DeleteSelectedSet() end)
    delBtn:SetPoint("LEFT", renameBtn, "RIGHT", 5, 0)

    -- RIGHT: selected set -------------------------------------------------
    local rightPanel = CreateFrame("Frame", nil, f, template)
    rightPanel:SetPoint("TOPLEFT", 219, -52)
    rightPanel:SetPoint("BOTTOMRIGHT", -14, 28)
    SetBackdrop(rightPanel, {0.035, 0.018, 0.052, 0.35}, {0.18, 0.09, 0.25, 1})

    local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightTitle:SetPoint("TOPLEFT", 12, -10)
    rightTitle:SetText("SELECTED SET")
    rightTitle:SetTextColor(0.88, 0.80, 0.98)

    local selected = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    selected:SetPoint("TOPLEFT", 12, -31)
    selected:SetJustifyH("LEFT")
    f.selectedLabel = selected

    local activeCaption = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeCaption:SetPoint("TOPLEFT", selected, "BOTTOMLEFT", 0, -5)
    activeCaption:SetText("Active gear:")
    activeCaption:SetTextColor(0.62, 0.55, 0.70)

    local activeLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    activeLabel:SetPoint("LEFT", activeCaption, "RIGHT", 5, 0)
    f.activeLabel = activeLabel

    local summary = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summary:SetPoint("TOPLEFT", activeCaption, "BOTTOMLEFT", 0, -10)
    summary:SetPoint("RIGHT", rightPanel, "RIGHT", -12, 0)
    summary:SetJustifyH("LEFT")
    summary:SetJustifyV("TOP")
    f.summary = summary

    local equipBtn = MakeButton(rightPanel, "Equip Selected", 118, function()
        local name = TRD:GetSelectedSetName()
        if name then TRD:EquipSet(name) end
    end)
    equipBtn:SetPoint("TOPLEFT", 12, -117)

    local saveBtn = MakeButton(rightPanel, "Save Current Gear", 132, function()
        local name = TRD:GetSelectedSetName()
        if name then TRD:SaveSet(name) end
    end)
    saveBtn:SetPoint("LEFT", equipBtn, "RIGHT", 10, 0)

    local ruleLine = rightPanel:CreateTexture(nil, "ARTWORK")
    ruleLine:SetTexture("Interface/Buttons/WHITE8X8")
    ruleLine:SetPoint("TOPLEFT", 12, -154)
    ruleLine:SetPoint("TOPRIGHT", -12, -154)
    ruleLine:SetHeight(1)
    ruleLine:SetVertexColor(0.25, 0.13, 0.34, 1)

    local rulesTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rulesTitle:SetPoint("TOPLEFT", 12, -166)
    rulesTitle:SetText("AUTOMATIC SWAP")
    rulesTitle:SetTextColor(0.88, 0.80, 0.98)

    local defaultCheck = MakeCheckbox(rightPanel, "Default after dismount / combat")
    defaultCheck:SetPoint("TOPLEFT", 10, -188)
    defaultCheck:SetScript("OnClick", function(btn)
        TRD:SetSelectedAsDefault(btn:GetChecked())
    end)
    f.defaultCheck = defaultCheck

    local autoCheck = MakeCheckbox(rightPanel, "Equip Riding while mounted")
    autoCheck:SetPoint("TOPLEFT", 10, -216)
    autoCheck:SetScript("OnClick", function(btn)
        TRD.db.enabled = btn:GetChecked() and true or false
        TRD.db.pendingMode = nil
        TRD.db.pendingGroundSet = nil
        if TRD.db.enabled then TRD:CheckMountState(true) end
        TRD:RefreshUI()
    end)
    f.autoCheck = autoCheck

    local notes = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notes:SetPoint("TOPLEFT", 12, -252)
    notes:SetPoint("RIGHT", rightPanel, "RIGHT", -12, 0)
    notes:SetJustifyH("LEFT")
    notes:SetJustifyV("TOP")
    notes:SetText("Riding is always the mounted set. Your checked default set returns when you dismount. If combat blocks a swap, the correct set is applied the instant combat ends.")
    notes:SetTextColor(0.74, 0.69, 0.82)

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 18, 9)
    status:SetPoint("BOTTOMRIGHT", -18, 9)
    status:SetJustifyH("LEFT")
    f.status = status

    f:Hide()
end

function TRD:RefreshUI()
    if not self.ui or not self.db then return end

    local selected = self:GetSelectedSetName()
    local ridingName = self:GetRidingSetName() or self.db.ridingSetName or "Riding"
    local defaultGround = self:GetGroundSetName() or "None"
    local activeName
    if IsRealMount() then
        activeName = ridingName
    else
        activeName = self.lastEquippedSet or defaultGround
    end

    for i, row in ipairs(self.ui.rows) do
        local name = self.db.setOrder[i]
        if name and self.db.sets[name] then
            row:Show()
            local suffix = ""
            if name == ridingName then
                suffix = "  |cFFB56CFF• MOUNT|r"
            elseif name == defaultGround then
                suffix = "  |cFF63E6A6• DEFAULT|r"
            end
            row.text:SetText(name .. suffix)
            if name == selected then
                row:SetBackdropColor(BTN_ACTIVE[1], BTN_ACTIVE[2], BTN_ACTIVE[3], 1)
                row:SetBackdropBorderColor(PURPLE[1], PURPLE[2], PURPLE[3], 1)
                row.text:SetTextColor(1.0, 0.95, 1.0)
            else
                row:SetBackdropColor(BTN_BG[1], BTN_BG[2], BTN_BG[3], 1)
                row:SetBackdropBorderColor(0.22, 0.12, 0.32, 1)
                row.text:SetTextColor(0.88, 0.84, 0.96)
            end
        else
            row:Hide()
        end
    end

    self.ui.selectedLabel:SetText(selected or "No set")
    self.ui.activeLabel:SetText("|cFFB56CFF" .. (activeName or "Unknown") .. "|r")

    if selected then
        local count = TableCount(self.db.sets[selected])
        local desc
        if selected == ridingName then
            desc = "Mounted gear set. This equips whenever you mount."
        elseif selected == defaultGround then
            desc = "Default grounded set. This returns after riding, dismounting, or combat reconciliation."
        else
            desc = "Saved manual gear set. Check Default below if you want this to return after riding."
        end
        self.ui.summary:SetText("|cFFFFD86B" .. count .. " saved slots|r\n" .. desc)
    else
        self.ui.summary:SetText("")
    end

    local canBeDefault = selected and selected ~= ridingName
    local isDefault = canBeDefault and selected == defaultGround
    self.ui.defaultCheck:SetChecked(isDefault and true or false)
    self.ui.defaultCheck:SetEnabled(canBeDefault and true or false)
    if canBeDefault then
        self.ui.defaultCheck.label:SetTextColor(0.84, 0.78, 0.90)
    else
        self.ui.defaultCheck.label:SetTextColor(0.45, 0.45, 0.45)
    end

    self.ui.autoCheck:SetChecked(self.db.enabled)

    local status
    if not self.db.enabled then
        status = "|cFFFF7878Auto swap disabled|r"
    elseif VoidMarkForever.API.UnitOnTaxi("player") then
        status = "|cFF9D8AAATaxi:|r swaps paused"
    elseif self.db.pendingMode then
        local pendingName = self.db.pendingMode == "riding" and (self:GetRidingSetName() or "Riding") or (self.db.pendingGroundSet or self:GetGroundSetName() or "Ground")
        status = "|cFFFFC266Combat:|r " .. pendingName .. " queued — applies immediately when combat ends"
    elseif IsRealMount() then
        status = "|cFFB56CFFMounted:|r Riding active   |cFF6E5A7F•|r   Dismount → " .. (defaultGround or "None")
    else
        status = "|cFF63E6A6Grounded:|r " .. (defaultGround or "None") .. " active"
    end
    self.ui.status:SetText(status)
end

function TRD:ResetPosition()
    if not self.ui then return end
    self.db.frameX, self.db.frameY = 0, 0
    self.ui:ClearAllPoints()
    self.ui:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function GetPopupEditBox(popup)
    return popup and (popup.EditBox or popup.editBox)
end

local function AcceptPopupFromEditBox(editBox)
    local popup = editBox and editBox:GetParent()
    if not popup then return end
    if StaticPopup_OnClick then
        StaticPopup_OnClick(popup, 1)
    else
        editBox:ClearFocus()
    end
end

StaticPopupDialogs.TRD_NEW_SET = {
    text = "New gear set name",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 24,
    whileDead = true,
    hideOnEscape = true,
    timeout = 0,
    preferredIndex = 3,
    OnShow = function(self)
        local box = GetPopupEditBox(self)
        if not box then return end
        box:SetText("")
        box:SetFocus()
    end,
    OnAccept = function(self)
        local box = GetPopupEditBox(self)
        if not box then return end
        local name = NormalizeName(box:GetText())
        if name == "" then return end
        if SetExists(name) then
            Chat("That set already exists.")
            return
        end
        TRD.db.sets[name] = {}
        EnsureSetInOrder(name)
        TRD.db.selectedSet = name
        TRD:RefreshUI()
        Chat(name .. " created. Equip your gear and hit Save Current.")
    end,
    EditBoxOnEnterPressed = AcceptPopupFromEditBox,
}

StaticPopupDialogs.TRD_RENAME_SET = {
    text = "Rename set: %s",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 24,
    whileDead = true,
    hideOnEscape = true,
    timeout = 0,
    preferredIndex = 3,
    OnShow = function(self)
        local box = GetPopupEditBox(self)
        if not box then return end
        local oldName = TRD.renameSourceSet or TRD:GetSelectedSetName() or ""
        box:SetText(oldName)
        box:HighlightText()
        box:SetFocus()
    end,
    OnAccept = function(self)
        local box = GetPopupEditBox(self)
        if not box then return end
        local oldName = TRD.renameSourceSet or TRD:GetSelectedSetName()
        local newName = NormalizeName(box:GetText())
        TRD.renameSourceSet = nil
        if not oldName or oldName == "" or newName == "" or oldName == newName then return end
        if oldName == TRD.db.ridingSetName then
            Chat("Riding stays named Riding.")
            return
        end
        if SetExists(newName) then
            Chat("That set already exists.")
            return
        end
        if not TRD.db.sets[oldName] then
            Chat("Could not find the original set to rename.")
            return
        end
        TRD.db.sets[newName] = TRD.db.sets[oldName]
        TRD.db.sets[oldName] = nil
        for i, name in ipairs(TRD.db.setOrder) do
            if name == oldName then
                TRD.db.setOrder[i] = newName
                break
            end
        end
        if TRD.db.selectedSet == oldName then TRD.db.selectedSet = newName end
        if TRD.db.defaultGroundSet == oldName then TRD.db.defaultGroundSet = newName end
        TRD:RefreshUI()
        Chat(oldName .. " renamed to " .. newName .. ".")
    end,
    OnCancel = function()
        TRD.renameSourceSet = nil
    end,
    EditBoxOnEnterPressed = AcceptPopupFromEditBox,
}

function TRD:ToggleUI()
    if not self.ui then self:CreateUI() end
    if self.ui:IsShown() then self.ui:Hide() else self.ui:Show(); self:RefreshUI() end
end
_G.VoidMarkRideOrDie = TRD

SLASH_TALIAASRIDEORDIE1 = "/trd"
SLASH_TALIAASRIDEORDIE2 = "/rideordie"
SLASH_TALIAASRIDEORDIE3 = "/taliaagear"
SlashCmdList.TALIAASRIDEORDIE = function(msg)
    msg = Trim(msg)
    local lower = string.lower(msg)
    local arg = msg:match("^set%s+(.+)$")
    local saveArg = msg:match("^save%s+(.+)$")

    if lower == "riding" or lower == "ride" then
        TRD:EquipSet(TRD:GetRidingSetName() or "Riding")
    elseif lower == "pvp" then
        if TRD.db.sets.PvP then TRD:EquipSet("PvP") end
    elseif lower == "save pvp" then
        TRD:SaveSet("PvP")
    elseif lower == "save riding" or lower == "save ride" then
        TRD:SaveSet(TRD.db.ridingSetName or "Riding")
    elseif lower == "status" then
        Chat("Default after riding: " .. (TRD:GetGroundSetName() or "None") .. ". Riding set: " .. (TRD:GetRidingSetName() or "None") .. ".")
    elseif lower == "auto on" then
        TRD.db.enabled = true
        TRD:CheckMountState(true)
        TRD:RefreshUI()
    elseif lower == "auto off" then
        TRD.db.enabled = false
        TRD.db.pendingMode = nil
        TRD.db.pendingGroundSet = nil
        TRD:RefreshUI()
    elseif lower == "resetpos" then
        TRD:ResetPosition()
    elseif saveArg and saveArg ~= "" and SetExists(NormalizeName(saveArg)) then
        TRD:SaveSet(NormalizeName(saveArg))
    elseif arg and arg ~= "" and SetExists(NormalizeName(arg)) then
        TRD:EquipSet(NormalizeName(arg))
    elseif lower == "help" then
        Chat("/trd opens UI. /trd set NAME equips. /trd save NAME saves current gear. /trd auto on/off")
    else
        TRD:ToggleUI()
    end
end

TRD:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= ADDON_NAME then return end
        EnsureDB()
        self:CreateUI()
        VoidMarkForever.RegisterEvent(self,"PLAYER_ENTERING_WORLD")
        VoidMarkForever.RegisterEvent(self,"PLAYER_MOUNT_DISPLAY_CHANGED")
        VoidMarkForever.RegisterEvent(self,"UNIT_AURA")
        VoidMarkForever.RegisterEvent(self,"PLAYER_REGEN_DISABLED")
        VoidMarkForever.RegisterEvent(self,"PLAYER_REGEN_ENABLED")
        VoidMarkForever.RegisterEvent(self,"PLAYER_DEAD")
        VoidMarkForever.RegisterEvent(self,"PLAYER_ALIVE")
        self:UnregisterEvent("ADDON_LOADED")
        self.wasMounted = IsRealMount()

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            if not TRD.db then return end
            TRD.wasMounted = IsRealMount()
            TRD:RefreshUI()
        end)

    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        self:CheckMountState(false)

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then self:CheckMountState(false) end

    elseif event == "PLAYER_REGEN_DISABLED" then
        if self.db.enabled then
            local desired = self:GetDesiredMode()
            self.db.pendingMode = desired
            if desired == "ground" then
                self.db.pendingGroundSet = self:GetGroundSetName()
            end
        end
        self:RefreshUI()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if self.db.enabled then
            local desired = self:GetDesiredMode()
            if desired == "ground" and not self.db.pendingGroundSet then
                self.db.pendingGroundSet = self:GetGroundSetName()
            end
            self.db.pendingMode = desired
            if desired then
                self:ApplyMode(desired)
            end
        end
        self:RefreshUI()

    elseif event == "PLAYER_DEAD" then
        self.wasDead = true

    elseif event == "PLAYER_ALIVE" then
        if self.wasDead then
            self.wasDead = false
            self:CheckMountState(true)
        end
    end
end)

VoidMarkForever.RegisterEvent(TRD,"ADDON_LOADED")
