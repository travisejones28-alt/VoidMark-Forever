local VMAPI = VoidMarkForever.API
-- VoidMark native minimap button
-- Lightweight, dependency-free launcher. Position and visibility are account-wide.
local addonName = ...
VoidMarkMinimap = VoidMarkMinimap or {}
local MM = VoidMarkMinimap

local RADIUS = 80
local EDGE_PAD = 2

local function IsSquareMinimap()
    -- Prefer the standard shape hint when a minimap addon exposes it.
    if type(GetMinimapShape) == "function" then
        local ok, shape = pcall(GetMinimapShape)
        if ok and type(shape) == "string" then
            shape = shape:upper()
            if shape:find("SQUARE", 1, true) then return true end
            if shape == "ROUND" then return false end
        end
    end

    -- ElvUI uses a square minimap but does not consistently expose a
    -- GetMinimapShape result on every Classic build.
    if type(_G.ElvUI) == "table" then return true end

    return false
end

local function SquareOffset(angle)
    local dx, dy = math.cos(angle), math.sin(angle)
    local halfW = ((Minimap and Minimap:GetWidth()) or (RADIUS * 2)) * 0.5 + EDGE_PAD
    local halfH = ((Minimap and Minimap:GetHeight()) or (RADIUS * 2)) * 0.5 + EDGE_PAD

    local ax, ay = math.abs(dx), math.abs(dy)
    local tx = ax > 0.0001 and (halfW / ax) or math.huge
    local ty = ay > 0.0001 and (halfH / ay) or math.huge
    local t = math.min(tx, ty)

    return dx * t, dy * t
end

local function DB()
    VoidMarkDB = VoidMarkDB or {}
    VoidMarkDB.VoidMarkMinimap = type(VoidMarkDB.VoidMarkMinimap) == "table" and VoidMarkDB.VoidMarkMinimap or {}
    local db = VoidMarkDB.VoidMarkMinimap
    if db.show == nil then db.show = true end
    if type(db.angle) ~= "number" then db.angle = 225 end
    return db
end

local function Atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

function MM:UpdatePosition()
    if not self.button or not Minimap then return end
    local angle = math.rad(DB().angle or 225)
    local x, y

    if IsSquareMinimap() then
        x, y = SquareOffset(angle)
    else
        x, y = math.cos(angle) * RADIUS, math.sin(angle) * RADIUS
    end

    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function MM:SetShown(show)
    local db = DB()
    db.show = show and true or false
    if self.button then
        if db.show then self.button:Show() else self.button:Hide() end
    end
end

function MM:ToggleMain()
    if not VoidMark or not VoidMark.MainWindow then return end
    if InCombatLockdown and InCombatLockdown() then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("VoidMark: window toggle unavailable during combat.", 0.75, 0.45, 1.0, 1.0)
        end
        return
    end
    if VoidMark.MainWindow:IsShown() then VoidMark.MainWindow:Hide() else VoidMark.MainWindow:Show() end
end

function MM:OpenSettings(button)
    local vm = VoidMark and VoidMark.VoidMark
    if vm and vm.OpenGearMenu then
        vm:OpenGearMenu(button)
    elseif VoidMark and VoidMark.ShowConfig then
        VoidMark:ShowConfig()
    end
end

function MM:Create()
    if self.button or not Minimap then return end

    local b = CreateFrame("Button", "VoidMarkMinimapButton", Minimap, "BackdropTemplate")
    self.button = b
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    b:SetClampedToScreen(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    -- True circular minimap button: no square backdrop or tooltip border.
    b:SetBackdrop(nil)

    b.ring = b:CreateTexture(nil, "BACKGROUND")
    b.ring:SetPoint("CENTER")
    b.ring:SetSize(38, 38)
    b.ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.ring:SetVertexColor(0.58, 0.20, 0.86, 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(28, 28)
    b.icon:SetTexture("Interface\\AddOns\\VoidMarkForever\\Media\\Panic\\panic_circle.tga")
    b.icon:SetTexCoord(0, 1, 0, 1)
    b.icon:SetVertexColor(1, 1, 1, 1)

    b.highlight = b:CreateTexture(nil, "HIGHLIGHT")
    b.highlight:SetPoint("CENTER")
    b.highlight:SetSize(38, 38)
    b.highlight:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    b.highlight:SetBlendMode("ADD")
    b.highlight:SetAlpha(0.35)

    b:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then MM:OpenSettings(self) else MM:ToggleMain() end
    end)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local scale = UIParent:GetEffectiveScale()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            if not mx or not my or not cx or not cy or not scale or scale == 0 then return end
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(Atan2(cy - my, cx - mx))
            DB().angle = angle
            MM:UpdatePosition()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    b:SetScript("OnEnter", function(self)
        if self.ring then self.ring:SetVertexColor(0.78, 0.38, 1.0, 1) end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("VoidMark", 0.78, 0.45, 1.0)
        GameTooltip:AddLine("Left-click: Show / hide VoidMark", 0.88, 0.88, 0.92)
        GameTooltip:AddLine("Right-click: Settings / tools", 0.88, 0.88, 0.92)
        GameTooltip:AddLine("Drag: Move around minimap", 0.62, 0.56, 0.68)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if self.ring then self.ring:SetVertexColor(0.58, 0.20, 0.86, 1) end
        GameTooltip:Hide()
    end)

    self:UpdatePosition()
    if DB().show then b:Show() else b:Hide() end
end

-- Add the visibility switch to VoidMark's existing General options without
-- adding another settings window or library.
if VoidMark and VoidMark.options and VoidMark.options.args and VoidMark.options.args.General and VoidMark.options.args.General.args then
    VoidMark.options.args.General.args.VoidMarkMinimapButton = {
        name = "Show Minimap Button",
        desc = "Show the VoidMark launcher beside the minimap.",
        type = "toggle",
        order = 10,
        width = "full",
        get = function() return DB().show end,
        set = function(_, value) MM:SetShown(value) end,
    }
end

-- SavedVariables are restored before ADDON_LOADED fires for this addon.
-- Waiting here avoids creating or modifying VoidMarkDB during file execution.
local loader = CreateFrame("Frame")
VoidMarkForever.RegisterEvent(loader,"ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loaded)
    if loaded ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    MM:Create()
end)
