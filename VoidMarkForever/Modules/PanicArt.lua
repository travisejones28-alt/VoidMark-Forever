local VMAPI = VoidMarkForever.API
-- Final Circle/Banner art repush: 2026-10-02
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ROOT = "Interface\\AddOns\\VoidMarkForever\\Media\\Panic\\"

local STYLE_SPEC = {
    ring = {
        texture = ROOT .. "panic_circle.tga",
        frameW = 132, frameH = 132,
        artW = 132, artH = 132,
        text = "stack",
        textX = 0, textY = 0,
        textW = 80,
        fontSize = 15,
    },
    banner = {
        texture = ROOT .. "panic_banner.tga",
        frameW = 300, frameH = 150,
        artW = 300, artH = 150,
        text = "banner",
        textX = 58, textY = 0,
        textW = 172,
        fontSize = 14,
    },
}

local TICK = 0.15
local elapsedSinceUpdate = 0
local lastStyle, lastCount, lastText = nil, nil, nil

local function GetTracker()
    return TaliaaGankTracker
end

local function CurrentStyle()
    local style = (VoidMarkDB and VoidMarkDB.VoidMarkPanicStyle) or "ring"
    if style ~= "banner" then style = "ring" end
    if VoidMarkDB then VoidMarkDB.VoidMarkPanicStyle = style end
    return style
end

local function ThreatCount(forcedCount)
    if forcedCount ~= nil then return tonumber(forcedCount) or 0 end
    local GT = GetTracker()
    if GT and GT.GetRecentEnemyCount then
        local ok, count = pcall(GT.GetRecentEnemyCount, GT, 30)
        if ok then return tonumber(count) or 0 end
    end
    return 0
end

local function ThreatColor(count)
    if count >= 6 then
        return 1.00, 0.94, 0.92
    elseif count >= 3 then
        return 1.00, 0.82, 0.82
    elseif count >= 1 then
        return 1.00, 0.58, 0.68
    else
        return 0.82, 0.60, 0.96
    end
end

local function GetObjects()
    local GT = GetTracker()
    local pf = GT and GT.PanicFrame
    local b = pf and pf.Button
    local label = b and b.Label
    if not label then return nil end
    return GT, pf, b, label
end

local function EnsureArt(button)
    if button.PanicArt then return end
    button.PanicArt = button:CreateTexture(nil, "ARTWORK", nil, -4)
    button.PanicPulse = button:CreateTexture(nil, "ARTWORK", nil, -3)
    button.PanicPulse:SetBlendMode("ADD")
    button.PanicPulse:SetAlpha(0)
end

local function ApplyVisualReset(pf, button)
    pf:SetBackdropColor(0, 0, 0, 0)
    pf:SetBackdropBorderColor(0, 0, 0, 0)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    button:SetBackdropColor(0, 0, 0, 0)
    button:SetBackdropBorderColor(0, 0, 0, 0)

    if button.Icon then button.Icon:Hide(); button.Icon:SetAlpha(0) end
    if button.Accent then button.Accent:Hide(); button.Accent:SetAlpha(0) end
    if button.StyleDiamond then button.StyleDiamond:Hide(); button.StyleDiamond:SetAlpha(0) end
    if button.StyleRing then button.StyleRing:Hide(); button.StyleRing:SetAlpha(0) end
    if button.StyleRingGlow then button.StyleRingGlow:Hide(); button.StyleRingGlow:SetAlpha(0) end
    if button.BannerLeft then button.BannerLeft:Hide(); button.BannerLeft:SetAlpha(0) end
    if button.BannerRight then button.BannerRight:Hide(); button.BannerRight:SetAlpha(0) end
    if button.VoidGlow then button.VoidGlow:Hide(); button.VoidGlow:SetAlpha(0) end
end

local function ApplyStyle(force)
    local _, pf, button, label = GetObjects()
    if not label then return end
    EnsureArt(button)

    local style = CurrentStyle()
    local spec = STYLE_SPEC[style]

    pf:SetSize(spec.frameW, spec.frameH)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, 0)
    button:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 0, 0)
    ApplyVisualReset(pf, button)

    if force or lastStyle ~= style then
        lastStyle = style

        button.PanicArt:SetTexture(spec.texture)
        button.PanicArt:ClearAllPoints()
        button.PanicArt:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.PanicArt:SetSize(spec.artW, spec.artH)

        button.PanicPulse:SetTexture(spec.texture)
        button.PanicPulse:ClearAllPoints()
        button.PanicPulse:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.PanicPulse:SetSize(spec.artW, spec.artH)

        label:ClearAllPoints()
        label:SetPoint("CENTER", button, "CENTER", spec.textX, spec.textY)
        label:SetWidth(spec.textW)
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(true)
        if label.SetNonSpaceWrap then label:SetNonSpaceWrap(false) end
        label:SetFont(FONT, spec.fontSize, "OUTLINE")
        label:SetShadowOffset(1, -1)
        label:SetShadowColor(0, 0, 0, 1)
    end
end

local function UpdateDisplay(force, forcedCount)
    local _, pf, button, label = GetObjects()
    if not label then return end

    ApplyStyle(force)
    ApplyVisualReset(pf, button)

    local style = lastStyle or CurrentStyle()
    local spec = STYLE_SPEC[style]
    local count = ThreatCount(forcedCount)

    local text
    if spec.text == "banner" then
        text = string.format("PANIC  %d THREAT%s", count, count == 1 and "" or "S")
    else
        text = string.format("PANIC\n%d", count)
    end

    if force or count ~= lastCount or text ~= lastText then
        label:SetText(text)
        lastCount = count
        lastText = text
    end

    local r, g, b = ThreatColor(count)
    label:SetTextColor(r, g, b, 1)
    button.PanicArt:SetVertexColor(1, 1, 1, 1)
    button.PanicPulse:SetVertexColor(r, g, b, 1)

    local alpha = 0.08
    if count >= 6 then
        alpha = 0.30
    elseif count >= 3 then
        alpha = 0.22
    elseif count >= 1 then
        alpha = 0.14
    end
    button.PanicPulse:SetAlpha(alpha)
end

local function AttachRefreshHook()
    local GT = GetTracker()
    if not GT or GT.RefreshPanicArt then return end
    function GT:RefreshPanicArt(forceRefresh, forcedCount)
        UpdateDisplay(forceRefresh and true or false, forcedCount)
    end
end

local driver = CreateFrame("Frame")
VoidMarkForever.RegisterEvent(driver,"PLAYER_LOGIN")
VoidMarkForever.RegisterEvent(driver,"PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function()
    AttachRefreshHook()
    C_Timer.After(0.5, function()
        AttachRefreshHook()
        UpdateDisplay(true)
    end)
end)
driver:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceUpdate = elapsedSinceUpdate + elapsed
    if elapsedSinceUpdate < TICK then return end
    elapsedSinceUpdate = 0

    AttachRefreshHook()

    local _, pf = GetObjects()
    if not pf or not pf:IsShown() then return end
    UpdateDisplay(false)
end)
