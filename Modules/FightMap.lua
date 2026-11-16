-- VoidMark Forever: the fight map.
-- Every fight against an enemy player (your kill, a group kill, a loss) is kept with
-- where it happened and shown on the world map as a skull: green your kill, blue a
-- group kill, red a loss. A dropdown on the map picks the period (or off).
-- The skull sits where you stood: the client doesn't give other players' positions,
-- and in a fight you're a few yards apart.

VoidMarkFightMap = VoidMarkFightMap or {}
local FM = VoidMarkFightMap

FM.LIMIT = 500
FM.PERIODS = { day = 86400, week = 7 * 86400, month = 30 * 86400, all = math.huge }
FM.ORDER = { "off", "day", "week", "month", "all" }
FM.LABELS = { off = "Off", day = "Last day", week = "Last week", month = "Last month", all = "All" }
FM.COLORS = { W = { 0.25, 1, 0.25 }, G = { 0.35, 0.7, 1 }, L = { 1, 0.25, 0.25 } }
FM.WORDS = { W = "Your kill", G = "Group kill", L = "Loss" }
local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

local function readable(v)
    if VoidMarkForever and VoidMarkForever.Readable then return VoidMarkForever.Readable(v) end
    return v
end
local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return readable(a), readable(b)
end

function FM:Store()
    if type(VoidMarkPerCharDB) ~= "table" then return nil end
    VoidMarkPerCharDB.Fights = VoidMarkPerCharDB.Fights or {}
    return VoidMarkPerCharDB.Fights
end

function FM:Period()
    local p = VoidMark and VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.FightMapPeriod
    return FM.LABELS[p] and p or "week"
end
function FM:SetPeriod(p)
    if not FM.LABELS[p] then return end
    if VoidMark and VoidMark.db and VoidMark.db.profile then VoidMark.db.profile.FightMapPeriod = p end
    FM:Refresh()
end

-- On/off for the whole fight map (skulls and the map dropdown). Fights are still
-- recorded while it's off, so turning it back on shows the full history.
function FM:IsEnabled()
    local prof = VoidMark and VoidMark.db and VoidMark.db.profile
    return not (prof and prof.FightMapEnabled == false)
end
function FM:SetEnabled(on)
    local prof = VoidMark and VoidMark.db and VoidMark.db.profile
    if prof then prof.FightMapEnabled = on and true or false end
    if FM.dropdown then
        if FM:IsEnabled() then FM.dropdown:Show() else FM.dropdown:Hide() end
    end
    FM:Refresh()
end
function FM:ToggleEnabled() FM:SetEnabled(not FM:IsEnabled()) end

-- Our map and position, or nil in an instance or when the client hides them.
function FM:Position()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return nil end
    local map = safe(C_Map.GetBestMapForUnit, "player")
    if type(map) ~= "number" then return nil end
    local pos = safe(C_Map.GetPlayerMapPosition, map, "player")
    if type(pos) ~= "table" and type(pos) ~= "userdata" then return nil end
    local x, y
    if pos.GetXY then x, y = safe(pos.GetXY, pos) else x, y = readable(pos.x), readable(pos.y) end
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return map, x, y
end

-- kind: "W" your kill, "G" a group kill, "L" a loss.
function FM:Add(kind, name)
    if not FM.COLORS[kind] or type(name) ~= "string" then return end
    local store = FM:Store()
    if not store then return end
    local map, x, y = FM:Position()
    if not map then return end
    local zone = GetZoneText and safe(GetZoneText) or nil
    store[#store + 1] = { t = time(), m = map, x = x, y = y, k = kind, n = name, z = type(zone) == "string" and zone or nil }
    while #store > FM.LIMIT do table.remove(store, 1) end
    FM:Refresh()
end

-- Fights to show on a map for the chosen period.
function FM:Visible(mapID, now)
    local out = {}
    local period = FM:Period()
    if not FM:IsEnabled() or period == "off" or type(mapID) ~= "number" then return out end
    local since = (now or time()) - FM.PERIODS[period]
    for _, f in ipairs(FM:Store() or {}) do
        if f.m == mapID and (f.t or 0) >= since then out[#out + 1] = f end
    end
    return out
end

-- World map pins ----------------------------------------------------------------
FM.pins = FM.pins or {}
local function pin(i, parent)
    local p = FM.pins[i]
    if not p then
        p = CreateFrame("Frame", nil, parent)
        p:SetFrameStrata("HIGH")
        p.icon = p:CreateTexture(nil, "OVERLAY")
        p.icon:SetAllPoints(p)
        p.icon:SetTexture(SKULL)
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self)
            local f = self.fight
            if not f or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local c = FM.COLORS[f.k]
            local shown = VoidMarkForever and VoidMarkForever.DisplayName and VoidMarkForever.DisplayName(f.n) or f.n
            GameTooltip:AddLine(FM.WORDS[f.k] .. ": " .. tostring(shown), c[1], c[2], c[3])
            GameTooltip:AddLine(date("%b %d %H:%M", f.t) .. (f.z and ("  " .. f.z) or ""), 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        FM.pins[i] = p
    end
    if p:GetParent() ~= parent then p:SetParent(parent) end
    return p
end

function FM:Refresh()
    for _, p in ipairs(FM.pins) do p:Hide() end
    local wm = WorldMapFrame
    if not wm or not wm.IsShown or not wm:IsShown() then return end
    local canvas = wm.ScrollContainer and wm.ScrollContainer.Child
    local mapID = wm.GetMapID and wm:GetMapID()
    if not canvas or type(mapID) ~= "number" then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if not w or w <= 0 then return end
    local size = math.max(10, w * 0.014)
    for i, f in ipairs(FM:Visible(mapID)) do
        local p = pin(i, canvas)
        p.fight = f
        p:SetSize(size, size)
        p:ClearAllPoints()
        p:SetPoint("CENTER", canvas, "TOPLEFT", f.x * w, -f.y * h)
        local c = FM.COLORS[f.k]
        p.icon:SetVertexColor(c[1], c[2], c[3])
        p:Show()
    end
end

-- Period dropdown on the map.
function FM:SetupMap()
    local wm = WorldMapFrame
    if FM.hooked or not wm then return end
    FM.hooked = true
    if wm.HookScript then wm:HookScript("OnShow", function() FM:Refresh() end) end
    if hooksecurefunc and wm.OnMapChanged then hooksecurefunc(wm, "OnMapChanged", function() FM:Refresh() end) end
    local parent = wm.ScrollContainer or wm
    local dd = CreateFrame("Frame", "VoidMarkFightMapPeriod", parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 6, -2)
    dd:SetFrameStrata("HIGH")
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, 120) end
    local function label() return "VoidMark fights: " .. FM.LABELS[FM:Period()] end
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(dd, function(_, level)
            for _, key in ipairs(FM.ORDER) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = FM.LABELS[key]
                info.checked = FM:Period() == key
                info.func = function()
                    FM:SetPeriod(key)
                    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dd, label()) end
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end
    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dd, label()) end
    FM.dropdown = dd
    if not FM:IsEnabled() then dd:Hide() end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function()
    if WorldMapFrame then pcall(FM.SetupMap, FM) end
end)
