-- Nameplate colors: enemy players red, NPCs blue by default; both colors
-- are picked from dropdowns in Settings > General.
-- Tapped mobs stay gray and friendly players keep the game's color.
-- Forever can hide unit facts in combat, so what a plate is (player or NPC,
-- hostile or not) is worked out when the plate appears and remembered.
local NC = {}
VoidMarkNameplateColors = NC

-- Choices for the two dropdowns in Settings > General. "game" leaves the
-- game's own color.
NC.COLORS = {
    red    = { name = "Red",    rgb = { 0.90, 0.12, 0.12 } },
    blue   = { name = "Blue",   rgb = { 0.20, 0.45, 1.00 } },
    purple = { name = "Purple", rgb = { 0.64, 0.30, 1.00 } },
    pink   = { name = "Pink",   rgb = { 1.00, 0.40, 0.75 } },
    orange = { name = "Orange", rgb = { 1.00, 0.55, 0.10 } },
    yellow = { name = "Yellow", rgb = { 1.00, 0.85, 0.10 } },
    green  = { name = "Green",  rgb = { 0.20, 0.85, 0.30 } },
    cyan   = { name = "Cyan",   rgb = { 0.15, 0.85, 0.95 } },
    white  = { name = "White",  rgb = { 0.95, 0.95, 0.95 } },
    black  = { name = "Black",  rgb = { 0.12, 0.12, 0.12 } },
    game   = { name = "Game default" },
}
NC.ORDER = { "red", "blue", "purple", "pink", "orange", "yellow", "green", "cyan", "white", "black", "game" }
NC.DEFAULT_PLAYER, NC.DEFAULT_NPC = "red", "blue"

function NC.Choices()
    local t = {}
    for _, k in ipairs(NC.ORDER) do t[k] = NC.COLORS[k].name end
    return t
end
local function profile() return VoidMark and VoidMark.db and VoidMark.db.profile end
function NC.ColorFor(kind)
    local p = profile()
    local key = kind == "enemyPlayer" and (p and p.NameplatePlayerColor or NC.DEFAULT_PLAYER)
        or (p and p.NameplateNpcColor or NC.DEFAULT_NPC)
    local c = NC.COLORS[key] or NC.COLORS[kind == "enemyPlayer" and NC.DEFAULT_PLAYER or NC.DEFAULT_NPC]
    return c.rgb
end

local kinds = {}   -- nameplate unit -> "enemyPlayer" | "npc" | "other"

local function readable(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return readable(v)
end

function NC.Enabled()
    local p = VoidMark and VoidMark.db and VoidMark.db.profile
    return not p or p.NameplateColors ~= false
end

function NC.Kind(unit)
    local guid = safe(UnitGUID, unit)
    local isPlayer
    if type(guid) == "string" then
        if guid:find("^Player%-") then isPlayer = true
        elseif guid:find("^Creature%-") or guid:find("^Vehicle%-") or guid:find("^Pet%-") then isPlayer = false end
    end
    if isPlayer == nil then isPlayer = safe(UnitIsPlayer, unit) end
    if isPlayer == nil then return nil end
    if not isPlayer then return "npc" end
    local hostile = VoidMarkForever and VoidMarkForever.IsHostileUnit and VoidMarkForever.IsHostileUnit(unit)
    if hostile == nil then hostile = safe(UnitIsEnemy, "player", unit) end
    return hostile and "enemyPlayer" or "other"
end

local function plateFor(unit)
    return C_NamePlate and C_NamePlate.GetNamePlateForUnit and safe(C_NamePlate.GetNamePlateForUnit, unit)
end

function NC.Paint(frame)
    if not frame or not NC.Enabled() then return end
    local unit = frame.unit or frame.displayedUnit
    if type(unit) ~= "string" or not unit:find("^nameplate") then return end
    local kind = kinds[unit]
    if not kind then kind = NC.Kind(unit); kinds[unit] = kind end
    local c
    if kind == "enemyPlayer" then c = NC.ColorFor("enemyPlayer")
    elseif kind == "npc" and not safe(UnitIsTapDenied, unit) then c = NC.ColorFor("npc") end
    if not c then return end
    local bar = frame.healthBar
    if bar and bar.SetStatusBarColor then bar:SetStatusBarColor(c[1], c[2], c[3]) end
    -- Far-away plates show only a name, colored by the game (red for
    -- hostile). Color that name too; full plates keep their white name.
    local name = frame.name
    if name and name.SetTextColor and NC.NameColored(frame) then
        name:SetTextColor(c[1], c[2], c[3])
        if name.SetVertexColor then name:SetVertexColor(c[1], c[2], c[3]) end
    end
end

-- Is the game coloring this plate's name (name-only / far away)?
function NC.NameColored(frame)
    local o = frame.optionTable
    if o and (o.colorNameBySelection or o.colorNameWithExtendedColors) then return true end
    local bar = frame.healthBar
    if bar and bar.IsShown and not bar:IsShown() then return true end
    if bar and bar.GetAlpha and (bar:GetAlpha() or 1) < 0.05 then return true end
    return false
end

-- Turning it off: let the game repaint its own colors (it skips repainting
-- when it thinks the color hasn't changed, so clear what it remembers).
function NC.RefreshAll()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, plate in ipairs(safe(C_NamePlate.GetNamePlates) or {}) do
        local f = plate.UnitFrame
        if f then
            if f.healthBar then f.healthBar.r, f.healthBar.g, f.healthBar.b = nil, nil, nil end
            if CompactUnitFrame_UpdateHealthColor then pcall(CompactUnitFrame_UpdateHealthColor, f) end
            if CompactUnitFrame_UpdateName then pcall(CompactUnitFrame_UpdateName, f) end
            NC.Paint(f)
        end
    end
end

if hooksecurefunc then
    for _, fn in ipairs({ "CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateName", "CompactUnitFrame_UpdateNameColor" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, NC.Paint) end
    end
end

if CreateFrame then
    local f = CreateFrame("Frame")
    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_REMOVED" then kinds[unit] = nil; return end
        kinds[unit] = NC.Kind(unit)
        local plate = plateFor(unit)
        if plate and plate.UnitFrame then NC.Paint(plate.UnitFrame) end
    end)
    NC.frame = f
end

-- Small window (VoidMark gear menu > Nameplate Colors): on/off and the two
-- color dropdowns. Same settings as Settings > General.
local function hex(rgb)
    if not rgb then return "ffffffff" end
    return string.format("ff%02x%02x%02x", rgb[1] * 255, rgb[2] * 255, rgb[3] * 255)
end
local function setKey(field, key)
    local p = profile(); if not p then return end
    p[field] = key
    NC.RefreshAll()
    if NC.window and NC.window:IsShown() then NC.UpdateWindow() end
end
local function colorDropdown(parent, field, default, y, label)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", 16, y); l:SetText(label)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", 120, y + 6)
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, 120) end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dd, function(_, level)
            for _, k in ipairs(NC.ORDER) do
                local c = NC.COLORS[k]
                local info = UIDropDownMenu_CreateInfo()
                info.text = c.rgb and ("|c" .. hex(c.rgb) .. c.name .. "|r") or c.name
                info.value = k
                local p = profile()
                info.checked = ((p and p[field]) or default) == k
                info.func = function() setKey(field, k); CloseDropDownMenus() end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end
    dd.field, dd.default = field, default
    return dd
end
-- Far-away mobs show the game's own floating name (not a nameplate), which
-- addons can't recolor. Two game settings help: show nameplates farther out,
-- or hide those floating NPC names.
NC.DISTANCES = { 20, 30, 41 }
local function cvar(name) local ok, v = pcall(GetCVar, name); if ok then return v end end
local function setCVar(name, v) if SetCVar then pcall(SetCVar, name, v) end end
function NC.Distance() return tonumber(cvar("nameplateMaxDistance")) end
function NC.SetDistance(yards)
    setCVar("nameplateMaxDistance", tostring(yards))
    return NC.Distance()
end
function NC.FloatingNamesHidden() return cvar("UnitNameNPC") == "0" end
function NC.SetFloatingNamesHidden(hide)
    local v = hide and "0" or "1"
    for _, n in ipairs({ "UnitNameNPC", "UnitNameHostleNPC", "UnitNameEnemyNPC" }) do setCVar(n, v) end
end

function NC.UpdateWindow()
    local w = NC.window; if not w then return end
    if w.hideNames then w.hideNames:SetChecked(NC.FloatingNamesHidden()) end
    if w.distance and UIDropDownMenu_SetText then
        local d = NC.Distance()
        UIDropDownMenu_SetText(w.distance, d and (math.floor(d + 0.5) .. " yards") or "Game default")
    end
    local p = profile()
    w.enable:SetChecked(NC.Enabled())
    for _, dd in ipairs({ w.player, w.npc }) do
        local key = (p and p[dd.field]) or dd.default
        local c = NC.COLORS[key] or NC.COLORS[dd.default]
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dd, c.rgb and ("|c" .. hex(c.rgb) .. c.name .. "|r") or c.name) end
        if UIDropDownMenu_EnableDropDown and UIDropDownMenu_DisableDropDown then
            if NC.Enabled() then UIDropDownMenu_EnableDropDown(dd) else UIDropDownMenu_DisableDropDown(dd) end
        end
    end
end
function NC.ToggleWindow()
    if not NC.window then
        local w = CreateFrame("Frame", "VoidMarkNameplateColorsFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        w:SetSize(300, 230); w:SetPoint("CENTER"); w:SetFrameStrata("DIALOG")
        w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", w.StartMoving); w:SetScript("OnDragStop", w.StopMovingOrSizing)
        if w.SetBackdrop then
            w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
            w:SetBackdropColor(0.07, 0.05, 0.12, 0.95); w:SetBackdropBorderColor(0.6, 0.4, 0.9, 1)
        end
        local t = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        t:SetPoint("TOPLEFT", 14, -12); t:SetText("Nameplate Colors")
        local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local enable = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        enable:SetPoint("TOPLEFT", 12, -36); enable:SetSize(24, 24)
        local el = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        el:SetPoint("LEFT", enable, "RIGHT", 4, 0); el:SetText("Color nameplates")
        enable:SetScript("OnClick", function(b)
            local p = profile(); if p then p.NameplateColors = b:GetChecked() and true or false end
            NC.RefreshAll(); NC.UpdateWindow()
        end)
        w.enable = enable
        w.player = colorDropdown(w, "NameplatePlayerColor", NC.DEFAULT_PLAYER, -74, "Enemy players")
        w.npc = colorDropdown(w, "NameplateNpcColor", NC.DEFAULT_NPC, -108, "NPCs")
        local dl = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dl:SetPoint("TOPLEFT", 16, -142); dl:SetText("Nameplate range")
        local dd = CreateFrame("Frame", nil, w, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", 120, -136)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, 120) end
        if UIDropDownMenu_Initialize then
            UIDropDownMenu_Initialize(dd, function(_, level)
                for _, y in ipairs(NC.DISTANCES) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = y .. " yards" .. (y == 20 and " (game default)" or "")
                    info.checked = math.floor((NC.Distance() or 0) + 0.5) == y
                    info.func = function()
                        local got = NC.SetDistance(y); CloseDropDownMenus(); NC.UpdateWindow()
                        if got and got < y and DEFAULT_CHAT_FRAME then
                            DEFAULT_CHAT_FRAME:AddMessage("|cffb45cffVoidMark:|r the game caps nameplate range at " .. math.floor(got + 0.5) .. " yards.")
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
        end
        w.distance = dd
        local hide = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
        hide:SetPoint("TOPLEFT", 12, -176); hide:SetSize(24, 24)
        local hl = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        hl:SetPoint("LEFT", hide, "RIGHT", 4, 0); hl:SetWidth(250); hl:SetJustifyH("LEFT")
        hl:SetText("Hide far-away NPC names (the red text with no nameplate - the game won't let addons recolor it)")
        hl:SetWordWrap(true)
        hide:SetScript("OnClick", function(b) NC.SetFloatingNamesHidden(b:GetChecked() and true or false); NC.UpdateWindow() end)
        w.hideNames = hide
        if UISpecialFrames then table.insert(UISpecialFrames, "VoidMarkNameplateColorsFrame") end
        w:Hide()
        NC.window = w
    end
    if NC.window:IsShown() then NC.window:Hide() else NC.UpdateWindow(); NC.window:Show() end
end
