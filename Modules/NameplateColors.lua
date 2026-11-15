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
    local bar = frame.healthBar
    if not bar or not bar.SetStatusBarColor then return end
    local kind = kinds[unit]
    if not kind then kind = NC.Kind(unit); kinds[unit] = kind end
    local c
    if kind == "enemyPlayer" then c = NC.ColorFor("enemyPlayer")
    elseif kind == "npc" and not safe(UnitIsTapDenied, unit) then c = NC.ColorFor("npc") end
    if c then bar:SetStatusBarColor(c[1], c[2], c[3]) end
end

-- Turning it off: let the game repaint its own colors (it skips repainting
-- when it thinks the color hasn't changed, so clear what it remembers).
function NC.RefreshAll()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, plate in ipairs(safe(C_NamePlate.GetNamePlates) or {}) do
        local f = plate.UnitFrame
        if f and f.healthBar then
            f.healthBar.r, f.healthBar.g, f.healthBar.b = nil, nil, nil
            if CompactUnitFrame_UpdateHealthColor then pcall(CompactUnitFrame_UpdateHealthColor, f) end
            NC.Paint(f)
        end
    end
end

if hooksecurefunc and type(CompactUnitFrame_UpdateHealthColor) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateHealthColor", NC.Paint)
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
