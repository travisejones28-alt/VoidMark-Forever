-- Nameplate colors: enemy players red, NPCs blue (Settings > General).
-- Tapped mobs stay gray and friendly players keep the game's color.
-- Forever can hide unit facts in combat, so what a plate is (player or NPC,
-- hostile or not) is worked out when the plate appears and remembered.
local NC = {}
VoidMarkNameplateColors = NC

NC.PLAYER = { 0.90, 0.12, 0.12 }
NC.NPC = { 0.20, 0.45, 1.00 }

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
    if kind == "enemyPlayer" then c = NC.PLAYER
    elseif kind == "npc" and not safe(UnitIsTapDenied, unit) then c = NC.NPC end
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
