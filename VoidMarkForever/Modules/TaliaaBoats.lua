local VMAPI = VoidMarkForever.API
local ADDON_NAME = ...
local PREFIX = "TBOAT2"
local SYNC_MODEL_REV = 2

-- TaliaaBoats v2.2.2 - integrated VoidMark module
--
-- Fixed-cycle ferry timer engine.
-- The timer does NOT try to infer precise dock arrival from player coordinates.
-- Instead it uses the measured Classic Era ferry phase durations and calibrates
-- automatically from the major-zone transition produced by the loading screen.
--
-- Measured timing model adapted from the supplied working BigTonyTimer addon:
--
-- Auberdine/Darkshore <-> Menethil/Wetlands: 293 sec cycle
-- Theramore/Dustwallow <-> Menethil/Wetlands: 326 sec cycle
-- Ratchet/Barrens <-> Booty Bay/Stranglethorn Vale: 350.823 sec cycle

local DB
local frame
local overlay
local lastZone
local updateAccum = 0
local lastBroadcastAt = {}
local announceState = {}

local ZONE_DARKSHORE = "Darkshore"
local ZONE_WETLANDS = "Wetlands"
local ZONE_DUSTWALLOW = "Dustwallow Marsh"
local ZONE_BARRENS = "The Barrens"
local ZONE_STRANGLETHORN = "Stranglethorn Vale"

local ROUTES = {
    AUB_MEN = {
        id = "AUB_MEN",
        short = "dark",
        a = "Auberdine",
        b = "Menethil",
        zoneA = ZONE_DARKSHORE,
        zoneB = ZONE_WETLANDS,

        -- Zone transition after the ferry loading screen -> phase that begins.
        crossings = {
            [ZONE_DARKSHORE] = { [ZONE_WETLANDS] = 4 },
            [ZONE_WETLANDS]  = { [ZONE_DARKSHORE] = 1 },
        },

        -- Emergency/manual calibration while standing in the destination zone.
        calibrate = {
            [ZONE_DARKSHORE] = 1,
            [ZONE_WETLANDS] = 4,
        },

        phases = {
            { id="load_park_a", dur=44, where="approaching", endpoint="A", status="Boat arrives at Auberdine" },
            { id="parked_a",   dur=64, where="docked",      endpoint="A", status="Boat leaves Auberdine" },
            { id="leave_a",    dur=34, where="sailing",     endpoint="B", status="Sailing to Menethil" },
            { id="load_park_b",dur=41, where="approaching", endpoint="B", status="Boat arrives at Menethil" },
            { id="parked_b",   dur=61, where="docked",      endpoint="B", status="Boat leaves Menethil" },
            { id="leave_b",    dur=49, where="sailing",     endpoint="A", status="Sailing to Auberdine" },
        },
    },

    MEN_THE = {
        id = "MEN_THE",
        short = "thera",
        a = "Menethil",
        b = "Theramore",
        zoneA = ZONE_WETLANDS,
        zoneB = ZONE_DUSTWALLOW,

        crossings = {
            [ZONE_DUSTWALLOW] = { [ZONE_WETLANDS] = 4 },
            [ZONE_WETLANDS]   = { [ZONE_DUSTWALLOW] = 1 },
        },

        calibrate = {
            [ZONE_DUSTWALLOW] = 1,
            [ZONE_WETLANDS] = 4,
        },

        phases = {
            { id="load_park_b",dur=52, where="approaching", endpoint="B", status="Boat arrives at Theramore" },
            { id="parked_b",   dur=60, where="docked",      endpoint="B", status="Boat leaves Theramore" },
            { id="leave_b",    dur=52, where="sailing",     endpoint="A", status="Sailing to Menethil" },
            { id="load_park_a",dur=51, where="approaching", endpoint="A", status="Boat arrives at Menethil" },
            { id="parked_a",   dur=60, where="docked",      endpoint="A", status="Boat leaves Menethil" },
            { id="leave_a",    dur=51, where="sailing",     endpoint="B", status="Sailing to Theramore" },
        },
    },

    RAT_BB = {
        id = "RAT_BB",
        short = "booty",
        a = "Ratchet",
        b = "Booty Bay",
        zoneA = ZONE_BARRENS,
        zoneB = ZONE_STRANGLETHORN,

        crossings = {
            [ZONE_BARRENS]      = { [ZONE_STRANGLETHORN] = 4 },
            [ZONE_STRANGLETHORN]= { [ZONE_BARRENS] = 1 },
        },

        calibrate = {
            [ZONE_BARRENS] = 1,
            [ZONE_STRANGLETHORN] = 4,
        },

        -- NauticusClassic measures this route at 350.823333 sec round trip.
        -- The split below is reconstructed around its zone-transition markers so
        -- our existing loading-screen calibration model can use the same cycle.
        phases = {
            { id="load_park_a", dur=64.8553330757341, where="approaching", endpoint="A", status="Boat arrives at Ratchet" },
            { id="parked_a",    dur=60,               where="docked",      endpoint="A", status="Boat leaves Ratchet" },
            { id="leave_a",     dur=69.29,            where="sailing",     endpoint="B", status="Sailing to Booty Bay" },
            { id="load_park_b", dur=37.518,           where="approaching", endpoint="B", status="Boat arrives at Booty Bay" },
            { id="parked_b",    dur=60,               where="docked",      endpoint="B", status="Boat leaves Booty Bay" },
            { id="leave_b",     dur=59.16,            where="sailing",     endpoint="A", status="Sailing to Ratchet" },
        },
    },
}

local ROUTE_ORDER = { ROUTES.AUB_MEN, ROUTES.MEN_THE, ROUTES.RAT_BB }

for _, route in ipairs(ROUTE_ORDER) do
    local total = 0
    for _, p in ipairs(route.phases) do
        total = total + p.dur
    end
    route.cycle = total
end

local function Now()
    if GetServerTime then return GetServerTime() end
    return time()
end

local function ZoneName()
    if GetRealZoneText then
        local z = GetRealZoneText()
        if z and z ~= "" then return z end
    end
    if GetZoneText then return GetZoneText() or "" end
    return ""
end

local function Fmt(sec)
    sec = tonumber(sec)
    if not sec then return "--" end
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local function Clock(ts)
    ts = tonumber(ts)
    if not ts then return "--" end
    if date then return date("%I:%M:%S %p", ts):gsub("^0", "") end
    return tostring(ts)
end

local function ApplyDefaults()
    TaliaaBoatsDB = TaliaaBoatsDB or {}
    DB = TaliaaBoatsDB

    if DB.enabled == nil then DB.enabled = true end
    if DB.shown == nil then DB.shown = true end
    if DB.overlayShown == nil then DB.overlayShown = true end
    if DB.overlayDarkness == nil then DB.overlayDarkness = 45 end
    DB.overlayDarkness = math.max(0, math.min(100, tonumber(DB.overlayDarkness) or 45))
    if DB.reportToParty == nil then DB.reportToParty = false end
    if DB.announceArrivals == nil then DB.announceArrivals = false end
    if DB.announceDepartures == nil then DB.announceDepartures = false end
    if DB.countdownFinal == nil then DB.countdownFinal = false end
    if DB.countdownFiveSecond == nil then DB.countdownFiveSecond = false end

    DB.overlayPoint = DB.overlayPoint or "TOP"
    DB.overlayX = tonumber(DB.overlayX) or 0
    DB.overlayY = tonumber(DB.overlayY) or -160

    DB.point = DB.point or "CENTER"
    DB.x = tonumber(DB.x) or 0
    DB.y = tonumber(DB.y) or 100
    DB.routes = type(DB.routes) == "table" and DB.routes or {}

    for _, route in ipairs(ROUTE_ORDER) do
        DB.routes[route.id] = type(DB.routes[route.id]) == "table" and DB.routes[route.id] or {}
    end

    -- v2.2.2: invalidate anchors created by the broken "sync only once" build.
    -- The measured phase tables are defined from a loading-screen zone crossing,
    -- so each crossing is an authoritative calibration point. UI/preferences stay intact.
    if tonumber(DB.syncModelRevision) ~= SYNC_MODEL_REV then
        for _, route in ipairs(ROUTE_ORDER) do
            local rdb = DB.routes[route.id]
            rdb.anchor = nil
            rdb.phaseIndex = nil
            rdb.syncedAt = nil
            rdb.source = nil
        end
        DB.syncModelRevision = SYNC_MODEL_REV
    end
end

local function RouteDB(route)
    DB.routes[route.id] = DB.routes[route.id] or {}
    return DB.routes[route.id]
end

local function Phase(route)
    local rdb = RouteDB(route)
    local anchor = tonumber(rdb.anchor)
    local idx = tonumber(rdb.phaseIndex)
    if not anchor or not idx or not route.phases[idx] then return nil end

    local elapsed = (Now() - anchor) % route.cycle
    local into = elapsed

    for _ = 1, #route.phases + 1 do
        local p = route.phases[idx]
        if into < p.dur then
            return {
                phaseIndex = idx,
                id = p.id,
                where = p.where,
                endpoint = p.endpoint,
                status = p.status,
                eta = p.dur - into,
                elapsed = into,
                progress = p.dur > 0 and into / p.dur or 0,
            }
        end
        into = into - p.dur
        idx = idx + 1
        if idx > #route.phases then idx = 1 end
    end

    return nil
end

local function NextLandingEta(route, endpoint)
    local ph = Phase(route)
    if not ph then return nil end

    local idx = ph.phaseIndex
    local current = route.phases[idx]

    if current.where == "approaching" and current.endpoint == endpoint then
        return ph.eta
    end

    local total = ph.eta
    local i = idx + 1
    if i > #route.phases then i = 1 end

    for _ = 1, #route.phases do
        local q = route.phases[i]
        if q.where == "approaching" and q.endpoint == endpoint then
            return total + q.dur
        end
        total = total + q.dur
        i = i + 1
        if i > #route.phases then i = 1 end
    end

    return nil
end

local function EndpointName(route, endpoint)
    return endpoint == "A" and route.a or route.b
end

local function SendGroupText(text)
    if not IsInGroup or not IsInGroup() then return false end
    text = tostring(text or ""):gsub("|", "||")
    local channel = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    SendChatMessage(text, channel)
    return true
end

local function ReportParty(route)
    if not DB.reportToParty then return end

    local etaA = NextLandingEta(route, "A")
    local etaB = NextLandingEta(route, "B")
    local text = string.format(
        "Boat sync: %s <-> %s - %s %s - %s %s",
        route.a, route.b,
        route.a, etaA and Fmt(etaA) or "?",
        route.b, etaB and Fmt(etaB) or "?"
    )

    SendGroupText(text)
end

local function RouteRelevantHere(route, endpoint)
    local z = ZoneName()
    if endpoint == "A" then return z == route.zoneA end
    if endpoint == "B" then return z == route.zoneB end
    return z == route.zoneA or z == route.zoneB
end

local function ShouldFireCountdown(sec)
    sec = math.max(0, math.floor((tonumber(sec) or 0) + 0.5))
    if DB.countdownFinal and (sec == 10 or sec == 5 or sec == 4 or sec == 3 or sec == 2 or sec == 1) then
        return true
    end
    if DB.countdownFiveSecond and (sec == 30 or sec == 25 or sec == 20 or sec == 15 or sec == 10 or sec == 5) then
        return true
    end
    return false
end

local function UpdateAnnouncements(route)
    if not DB or not (DB.announceArrivals or DB.announceDepartures or DB.countdownFinal or DB.countdownFiveSecond) then
        return
    end

    local ph = Phase(route)
    if not ph then return end

    local st = announceState[route.id]
    if not st then
        st = { phaseIndex = ph.phaseIndex, countdownKey = nil }
        announceState[route.id] = st
        return
    end

    -- Announce completed transitions once. Initial state after login/reload is silent.
    if st.phaseIndex ~= ph.phaseIndex then
        local prev = route.phases[st.phaseIndex]
        local current = route.phases[ph.phaseIndex]

        if current and current.where == "docked" and DB.announceArrivals and RouteRelevantHere(route, current.endpoint) then
            SendGroupText(string.format("Boat arrived at %s.", EndpointName(route, current.endpoint)))
        elseif prev and prev.where == "docked" and current and current.where == "sailing" and DB.announceDepartures and RouteRelevantHere(route, prev.endpoint) then
            SendGroupText(string.format("Boat departed %s for %s.", EndpointName(route, prev.endpoint), EndpointName(route, current.endpoint)))
        end

        st.phaseIndex = ph.phaseIndex
        st.countdownKey = nil
    end

    -- Departure countdowns only run while the boat is physically docked at the
    -- endpoint matching the player's current major zone.
    if ph.where == "docked" and RouteRelevantHere(route, ph.endpoint) then
        local sec = math.max(0, math.floor((ph.eta or 0) + 0.5))
        if ShouldFireCountdown(sec) then
            local key = tostring(ph.phaseIndex) .. ":" .. tostring(sec)
            if st.countdownKey ~= key then
                st.countdownKey = key
                SendGroupText(string.format("Boat leaves %s in %d.", EndpointName(route, ph.endpoint), sec))
            end
        end
    else
        st.countdownKey = nil
    end
end

local function RegisterPrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end
end

local function SendAddon(channel, msg)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)
    elseif SendAddonMessage then
        SendAddonMessage(PREFIX, msg, channel)
    end
end

local function BroadcastSync(route)
    local rdb = RouteDB(route)
    local anchor = tonumber(rdb.anchor)
    local phaseIndex = tonumber(rdb.phaseIndex)
    if not anchor or not phaseIndex then return end

    local nowLocal = GetTime and GetTime() or 0
    if nowLocal - (lastBroadcastAt[route.id] or 0) < 1.5 then return end
    lastBroadcastAt[route.id] = nowLocal

    local msg = string.format("S|%s|%d|%d|%d", route.id, anchor, phaseIndex, Now())

    if IsInRaid and IsInRaid() then
        pcall(SendAddon, "RAID", msg)
    elseif IsInGroup and IsInGroup() then
        pcall(SendAddon, "PARTY", msg)
    end

    if IsInGuild and IsInGuild() then
        pcall(SendAddon, "GUILD", msg)
    end

    -- Optional integration hook for a future Battle.net receiver.
    if TaliaaBoats_ForwardExternalSync then
        pcall(TaliaaBoats_ForwardExternalSync, route.id, anchor, phaseIndex)
    end
end

local function Calibrate(route, phaseIndex, source)
    phaseIndex = tonumber(phaseIndex)
    if not route or not phaseIndex or not route.phases[phaseIndex] then return false end

    local rdb = RouteDB(route)
    rdb.anchor = Now()
    rdb.phaseIndex = phaseIndex
    rdb.syncedAt = Now()
    rdb.source = source or "local"
    announceState[route.id] = { phaseIndex = phaseIndex, countdownKey = nil }

    BroadcastSync(route)
    ReportParty(route)

    if frame and frame.UpdateNow then frame:UpdateNow() end
    return true
end

local function ApplyRemoteSync(routeId, anchor, phaseIndex, sentAt, sender)
    local route = ROUTES[routeId]
    if not route then return end

    anchor = tonumber(anchor)
    phaseIndex = tonumber(phaseIndex)
    sentAt = tonumber(sentAt) or anchor
    if not anchor or not phaseIndex or not route.phases[phaseIndex] then return end

    local rdb = RouteDB(route)
    local existing = tonumber(rdb.syncedAt) or 0
    if sentAt < existing then return end

    rdb.anchor = anchor
    rdb.phaseIndex = phaseIndex
    rdb.syncedAt = sentAt
    rdb.source = sender and ("remote:" .. tostring(sender)) or "remote"
    announceState[route.id] = { phaseIndex = phaseIndex, countdownKey = nil }

    if frame and frame.UpdateNow then frame:UpdateNow() end
end

-- Public entry point for a future Horde/Battle.net receiver.
function TaliaaBoats_ApplyExternalSync(routeId, anchor, phaseIndex, source)
    ApplyRemoteSync(routeId, anchor, phaseIndex, anchor, source or "BNet")
end

local function OnAddonMessage(prefix, message, _, sender)
    if prefix ~= PREFIX or type(message) ~= "string" then return end

    local kind, routeId, anchor, phaseIndex, sentAt = strsplit("|", message)
    if kind ~= "S" then return end

    local me = VMAPI.UnitName and VMAPI.UnitName("player")
    if sender and me and Ambiguate then
        if Ambiguate(sender, "none") == Ambiguate(me, "none") then return end
    elseif sender == me then
        return
    end

    ApplyRemoteSync(routeId, anchor, phaseIndex, sentAt, sender)
end

local function HandleZoneChange()
    local z = ZoneName()
    local prev = lastZone

    if not prev then
        lastZone = z
        return
    end

    if z == prev then return end
    lastZone = z

    for _, route in ipairs(ROUTE_ORDER) do
        local map = route.crossings[prev]
        local phaseIndex = map and map[z]
        if phaseIndex then
            -- The phase durations are measured FROM the loading-screen zone crossing.
            -- Re-anchor on EVERY valid crossing. This is how the working BigTonyTimer
            -- keeps the fixed cycle aligned and it also self-corrects any accumulated
            -- drift or stale SavedVariables.
            Calibrate(route, phaseIndex, "zone:" .. prev .. ">" .. z)
            print(string.format(
                "|cff44ddffTaliaaBoats|r synced %s <-> %s from %s -> %s.",
                route.a, route.b, prev, z
            ))
        end
    end
end

local function MakeCheck(parent, label, x, y, key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)

    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)

    cb:SetChecked(DB[key] and true or false)
    cb:SetScript("OnClick", function(self)
        DB[key] = self:GetChecked() and true or false
    end)

    return cb
end



local function ApplyOverlayBackground()
    if not overlay or not DB then return end

    local pct = math.max(0, math.min(100, tonumber(DB.overlayDarkness) or 45))
    local p = pct / 100

    -- 0% = no box at all, just white text.
    -- 100% = dark gray, nearly opaque.
    local alpha = p * 0.90
    local gray = 0.52 - (0.30 * p)

    if overlay.SetBackdropColor then
        overlay:SetBackdropColor(gray, gray, gray, alpha)
        overlay:SetBackdropBorderColor(0.85, 0.85, 0.85, p * 0.65)
    elseif overlay.bg then
        overlay.bg:SetColorTexture(gray, gray, gray, alpha)
    end
end

local function CreateOverlay()
    if overlay then return end

    overlay = CreateFrame("Frame", "TaliaaBoatsOverlay", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    overlay:SetSize(360, 30 + (#ROUTE_ORDER * 44))
    overlay:SetPoint(DB.overlayPoint, UIParent, DB.overlayPoint, DB.overlayX, DB.overlayY)
    overlay:SetMovable(true)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetClampedToScreen(true)
    overlay:SetFrameStrata("HIGH")

    overlay:SetScript("OnDragStart", overlay.StartMoving)
    overlay:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        DB.overlayPoint = p or "TOP"
        DB.overlayX = x or 0
        DB.overlayY = y or 0
    end)

    if overlay.SetBackdrop then
        overlay:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
    else
        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        overlay.bg = bg
    end

    ApplyOverlayBackground()

    local title = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetTextColor(1, 1, 1, 1)
    title:SetText("VOIDMARK BOATS")
    overlay.title = title

    local hint = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", -9, -9)
    hint:SetTextColor(1, 1, 1, 0.65)
    hint:SetText("drag")
    overlay.hint = hint

    overlay.lines = {}
    local y = -30

    for _, route in ipairs(ROUTE_ORDER) do
        local routeTitle = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        routeTitle:SetPoint("TOPLEFT", 10, y)
        routeTitle:SetTextColor(1, 1, 1, 1)
        routeTitle:SetWidth(340)
        routeTitle:SetJustifyH("LEFT")

        local routeTimes = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        routeTimes:SetPoint("TOPLEFT", 10, y - 18)
        routeTimes:SetTextColor(1, 1, 1, 1)
        routeTimes:SetWidth(340)
        routeTimes:SetJustifyH("LEFT")

        overlay.lines[route.id] = {
            title = routeTitle,
            times = routeTimes,
        }

        y = y - 44
    end

    function overlay:UpdateNow()
        for _, route in ipairs(ROUTE_ORDER) do
            local ui = self.lines[route.id]
            local ph = Phase(route)

            if ph then
                ui.title:SetText(string.format(
                    "%s <-> %s   •   %s in %s",
                    route.a,
                    route.b,
                    ph.status,
                    Fmt(ph.eta)
                ))

                local etaA = NextLandingEta(route, "A")
                local etaB = NextLandingEta(route, "B")

                ui.times:SetText(string.format(
                    "%s %s     %s %s",
                    route.a,
                    etaA and Fmt(etaA) or "--",
                    route.b,
                    etaB and Fmt(etaB) or "--"
                ))
            else
                ui.title:SetText(string.format("%s <-> %s", route.a, route.b))
                ui.times:SetText("UNSYNCED")
            end
        end
    end

    if DB.overlayShown then
        overlay:Show()
    else
        overlay:Hide()
    end
    overlay:UpdateNow()
end

local function CreateUI()
    if frame then return end

    frame = CreateFrame("Frame", "TaliaaBoatsWindow", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    local extraRoutes = math.max(0, #ROUTE_ORDER - 2)
    local lineY = -250 - (extraRoutes * 96)
    local checkY = -264 - (extraRoutes * 96)
    local announceY = checkY - 30
    local countdownY = checkY - 58
    local opacityLabelY = checkY - 98
    local opacitySliderY = checkY - 93
    frame:SetSize(650, 462 + (extraRoutes * 96))
    frame:SetPoint(DB.point, UIParent, DB.point, DB.x, DB.y)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        DB.point, DB.relativePoint, DB.x, DB.y = p, rp, x, y
    end)

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = { left=3, right=3, top=3, bottom=3 },
        })
        frame:SetBackdropColor(0.02, 0.03, 0.04, 0.88)
        frame:SetBackdropBorderColor(0.4, 0.7, 0.9, 0.9)
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cffb45cffVOIDMARK|r  •  |cffffcc00BOAT TIMERS|r")

    local info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    info:SetPoint("TOP", title, "BOTTOM", 0, -4)
    info:SetText("Fixed ferry cycle • automatically syncs on one loading-screen crossing")

    frame.routeUI = {}

    local y = -60
    for _, route in ipairs(ROUTE_ORDER) do
        local block = {}

        block.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        block.title:SetPoint("TOPLEFT", 22, y)
        block.title:SetText(string.format("|cffffcc00%s <-> %s|r", route.a, route.b))

        block.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        block.status:SetPoint("TOPLEFT", 230, y)
        block.status:SetWidth(390)
        block.status:SetJustifyH("LEFT")

        block.aName = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        block.aName:SetPoint("TOPLEFT", 42, y - 26)
        block.aName:SetText(route.a)

        block.aEta = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        block.aEta:SetPoint("TOPLEFT", 230, y - 26)
        block.aEta:SetWidth(75)
        block.aEta:SetJustifyH("RIGHT")

        block.aClock = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        block.aClock:SetPoint("TOPLEFT", 330, y - 26)

        block.bName = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        block.bName:SetPoint("TOPLEFT", 42, y - 48)
        block.bName:SetText(route.b)

        block.bEta = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        block.bEta:SetPoint("TOPLEFT", 230, y - 48)
        block.bEta:SetWidth(75)
        block.bEta:SetJustifyH("RIGHT")

        block.bClock = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        block.bClock:SetPoint("TOPLEFT", 330, y - 48)

        block.sync = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        block.sync:SetPoint("TOPLEFT", 495, y - 26)
        block.sync:SetWidth(135)
        block.sync:SetJustifyH("RIGHT")

        frame.routeUI[route.id] = block
        y = y - 96
    end

    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.18)
    line:SetPoint("TOPLEFT", 18, lineY)
    line:SetPoint("TOPRIGHT", -18, lineY)
    line:SetHeight(1)

    MakeCheck(frame, "Report new boat syncs to group", 24, checkY, "reportToParty")

    local overlayCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    overlayCheck:SetSize(24, 24)
    overlayCheck:SetPoint("TOPLEFT", 290, checkY)
    local overlayLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    overlayLabel:SetPoint("LEFT", overlayCheck, "RIGHT", 2, 0)
    overlayLabel:SetText("Show compact overlay")
    overlayCheck:SetChecked(DB.overlayShown and true or false)
    overlayCheck:SetScript("OnClick", function(self)
        DB.overlayShown = self:GetChecked() and true or false
        if overlay then
            if DB.overlayShown then
                overlay:Show()
                overlay:UpdateNow()
            else
                overlay:Hide()
            end
        end
    end)

    MakeCheck(frame, "Announce arrivals", 24, announceY, "announceArrivals")
    MakeCheck(frame, "Announce departures", 290, announceY, "announceDepartures")
    MakeCheck(frame, "Departure countdown: 10, 5, 4, 3, 2, 1", 24, countdownY, "countdownFinal")
    MakeCheck(frame, "Add 30/25/20/15 sec countdowns", 360, countdownY, "countdownFiveSecond")

    local opacityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    opacityLabel:SetPoint("TOPLEFT", 28, opacityLabelY)
    opacityLabel:SetText("Overlay background")

    local opacityValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    opacityValue:SetPoint("LEFT", opacityLabel, "RIGHT", 8, 0)

    local opacity = CreateFrame(
        "Slider",
        "TaliaaBoatsOverlayOpacitySlider",
        frame,
        "OptionsSliderTemplate"
    )
    opacity:SetPoint("TOPLEFT", 175, opacitySliderY)
    opacity:SetSize(300, 16)
    opacity:SetMinMaxValues(0, 100)
    opacity:SetValueStep(5)
    if opacity.SetObeyStepOnDrag then opacity:SetObeyStepOnDrag(true) end
    opacity:SetValue(DB.overlayDarkness or 45)

    local low = _G[opacity:GetName() .. "Low"]
    local high = _G[opacity:GetName() .. "High"]
    local text = _G[opacity:GetName() .. "Text"]
    if low then low:SetText("Text only") end
    if high then high:SetText("Darker") end
    if text then text:SetText("") end

    local function RefreshOpacityLabel(value)
        value = math.floor((tonumber(value) or 0) + 0.5)
        if value <= 0 then
            opacityValue:SetText("|cffffffff0%  (text only)|r")
        else
            opacityValue:SetText(string.format("|cffffffff%d%%|r", value))
        end
    end

    RefreshOpacityLabel(DB.overlayDarkness)
    opacity:SetScript("OnValueChanged", function(self, value)
        value = math.floor((value or 0) / 5 + 0.5) * 5
        DB.overlayDarkness = math.max(0, math.min(100, value))
        RefreshOpacityLabel(DB.overlayDarkness)
        ApplyOverlayBackground()
    end)

    local test = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    test:SetSize(100, 24)
    test:SetPoint("BOTTOMLEFT", 22, 16)
    test:SetText("Status")
    test:SetScript("OnClick", function()
        SlashCmdList["TALIAABOATS"]("status")
    end)

    local hide = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    hide:SetSize(75, 24)
    hide:SetPoint("BOTTOMRIGHT", -22, 16)
    hide:SetText("Hide")
    hide:SetScript("OnClick", function()
        DB.shown = false
        frame:Hide()
    end)

    function frame:UpdateNow()
        for _, route in ipairs(ROUTE_ORDER) do
            local block = self.routeUI[route.id]
            local ph = Phase(route)
            local rdb = RouteDB(route)

            if not ph then
                block.status:SetText("|cffaaaaaaUNSYNCED — ride this ferry through one loading screen|r")
                block.aEta:SetText("|cff888888--|r")
                block.bEta:SetText("|cff888888--|r")
                block.aClock:SetText("")
                block.bClock:SetText("")
                block.sync:SetText("not synced")
            else
                block.status:SetText(string.format("|cff44ff88%s in %s|r", ph.status, Fmt(ph.eta)))

                local etaA = NextLandingEta(route, "A")
                local etaB = NextLandingEta(route, "B")

                block.aEta:SetText("|cffffcc00" .. Fmt(etaA) .. "|r")
                block.bEta:SetText("|cffffcc00" .. Fmt(etaB) .. "|r")
                block.aClock:SetText(etaA and Clock(Now() + etaA) or "")
                block.bClock:SetText(etaB and Clock(Now() + etaB) or "")

                local age = rdb.syncedAt and math.max(0, Now() - rdb.syncedAt) or nil
                if age then
                    block.sync:SetText(string.format("sync %s ago", Fmt(age)))
                else
                    block.sync:SetText("synced")
                end
            end
        end
    end

    if DB.shown then frame:Show() else frame:Hide() end
    frame:UpdateNow()

    if overlay and overlay.UpdateNow then
        overlay:UpdateNow()
    end
end

local function PrintStatus()
    print("|cff44ddffTaliaaBoats|r v2 fixed-cycle status:")
    print(string.format("  Report syncs to group: %s", DB.reportToParty and "ON" or "OFF"))
    print(string.format("  Arrival announcements: %s", DB.announceArrivals and "ON" or "OFF"))
    print(string.format("  Departure announcements: %s", DB.announceDepartures and "ON" or "OFF"))
    print(string.format("  Final departure countdown: %s", DB.countdownFinal and "ON" or "OFF"))
    print(string.format("  Extended 5-sec countdown: %s", DB.countdownFiveSecond and "ON" or "OFF"))

    for _, route in ipairs(ROUTE_ORDER) do
        local ph = Phase(route)
        if ph then
            print(string.format(
                "  %s <-> %s: %s in %s | %s %s | %s %s",
                route.a, route.b,
                ph.status, Fmt(ph.eta),
                route.a, Fmt(NextLandingEta(route, "A")),
                route.b, Fmt(NextLandingEta(route, "B"))
            ))
        else
            print(string.format("  %s <-> %s: UNSYNCED", route.a, route.b))
        end
    end
end

SLASH_TALIAABOATS1 = "/tb"
SLASH_TALIAABOATS2 = "/tboats"
SlashCmdList["TALIAABOATS"] = function(msg)
    msg = strtrim(strlower(msg or ""))

    if msg == "" or msg == "show" then
        DB.shown = true
        if frame then frame:Show(); frame:UpdateNow() end
        return
    end

    if msg == "hide" then
        DB.shown = false
        if frame then frame:Hide() end
        return
    end

    if msg == "status" or msg == "test" then
        PrintStatus()
        return
    end

    if msg == "overlay" or msg == "overlay on" then
        DB.overlayShown = true
        if overlay then
            overlay:Show()
            overlay:UpdateNow()
        end
        print("|cff44ddffTaliaaBoats|r compact overlay: ON")
        return
    end

    if msg == "overlay off" then
        DB.overlayShown = false
        if overlay then overlay:Hide() end
        print("|cff44ddffTaliaaBoats|r compact overlay: OFF")
        return
    end

    local opacityValue = msg:match("^opacity%s+(%d+)$")
    if opacityValue then
        opacityValue = math.max(0, math.min(100, tonumber(opacityValue) or 45))
        DB.overlayDarkness = opacityValue
        ApplyOverlayBackground()
        print(string.format(
            "|cff44ddffTaliaaBoats|r overlay background: %d%%%s",
            opacityValue,
            opacityValue == 0 and " (text only)" or ""
        ))
        return
    end

    if msg == "report on" then
        DB.reportToParty = true
        print("|cff44ddffTaliaaBoats|r report new syncs to group: ON")
        return
    end

    if msg == "report off" then
        DB.reportToParty = false
        print("|cff44ddffTaliaaBoats|r report new syncs to group: OFF")
        return
    end

    if msg == "arrivals on" then DB.announceArrivals = true; print("|cff44ddffTaliaaBoats|r arrival announcements: ON"); return end
    if msg == "arrivals off" then DB.announceArrivals = false; print("|cff44ddffTaliaaBoats|r arrival announcements: OFF"); return end
    if msg == "departures on" then DB.announceDepartures = true; print("|cff44ddffTaliaaBoats|r departure announcements: ON"); return end
    if msg == "departures off" then DB.announceDepartures = false; print("|cff44ddffTaliaaBoats|r departure announcements: OFF"); return end
    if msg == "countdown on" then DB.countdownFinal = true; print("|cff44ddffTaliaaBoats|r final departure countdown: ON"); return end
    if msg == "countdown off" then DB.countdownFinal = false; print("|cff44ddffTaliaaBoats|r final departure countdown: OFF"); return end
    if msg == "countdown5 on" then DB.countdownFiveSecond = true; print("|cff44ddffTaliaaBoats|r extended 5-sec countdown: ON"); return end
    if msg == "countdown5 off" then DB.countdownFiveSecond = false; print("|cff44ddffTaliaaBoats|r extended 5-sec countdown: OFF"); return end

    if msg == "sync dark" or msg == "sync aub" or msg == "sync auberdine" then
        local z = ZoneName()
        local idx = ROUTES.AUB_MEN.calibrate[z]
        if not idx then
            print("|cff44ddffTaliaaBoats|r: for manual Darkshore sync, be in Darkshore or Wetlands.")
            return
        end
        Calibrate(ROUTES.AUB_MEN, idx, "manual:" .. z)
        print("|cff44ddffTaliaaBoats|r Darkshore/Menethil manually synced.")
        return
    end

    if msg == "sync thera" or msg == "sync theramore" then
        local z = ZoneName()
        local idx = ROUTES.MEN_THE.calibrate[z]
        if not idx then
            print("|cff44ddffTaliaaBoats|r: for manual Theramore sync, be in Wetlands or Dustwallow Marsh.")
            return
        end
        Calibrate(ROUTES.MEN_THE, idx, "manual:" .. z)
        print("|cff44ddffTaliaaBoats|r Menethil/Theramore manually synced.")
        return
    end

    if msg == "sync booty" or msg == "sync bb" or msg == "sync ratchet" then
        local z = ZoneName()
        local idx = ROUTES.RAT_BB.calibrate[z]
        if not idx then
            print("|cff44ddffTaliaaBoats|r: for manual Booty Bay sync, be in The Barrens or Stranglethorn Vale.")
            return
        end
        Calibrate(ROUTES.RAT_BB, idx, "manual:" .. z)
        print("|cff44ddffTaliaaBoats|r Ratchet/Booty Bay manually synced.")
        return
    end

    if msg == "clear" or msg == "reset" then
        for _, route in ipairs(ROUTE_ORDER) do
            local rdb = RouteDB(route)
            rdb.anchor = nil
            rdb.phaseIndex = nil
            rdb.syncedAt = nil
            rdb.source = nil
        end
        announceState = {}
        if frame then frame:UpdateNow() end
        print("|cff44ddffTaliaaBoats|r boat syncs cleared.")
        return
    end

    print("|cff44ddffTaliaaBoats|r commands:")
    print("  /tb                 show window")
    print("  /tb status          print timers")
    print("  /tb overlay on|off  compact overlay")
    print("  /tb opacity 0-100   overlay background darkness")
    print("  /tb report on|off   report new syncs to group")
    print("  /tb arrivals on|off arrival announcements")
    print("  /tb departures on|off departure announcements")
    print("  /tb countdown on|off 10,5,4,3,2,1 departure countdown")
    print("  /tb countdown5 on|off add 30,25,20,15 sec countdowns")
    print("  /tb sync dark       emergency Darkshore/Menethil sync")
    print("  /tb sync thera      emergency Menethil/Theramore sync")
    print("  /tb sync booty      emergency Ratchet/Booty Bay sync")
    print("  /tb clear           clear cycle anchors")
end

-- VoidMark module API.
_G.VoidMarkBoats = _G.VoidMarkBoats or {}
function VoidMarkBoats:Toggle()
    if not DB then ApplyDefaults() end
    CreateOverlay()
    CreateUI()
    if frame:IsShown() then frame:Hide() else frame:Show(); frame:UpdateNow() end
end
function VoidMarkBoats:Show()
    if not DB then ApplyDefaults() end
    CreateOverlay()
    CreateUI()
    frame:Show()
    frame:UpdateNow()
end
function VoidMarkBoats:ToggleOverlay()
    if not DB then ApplyDefaults() end
    CreateOverlay()
    DB.overlayShown = not DB.overlayShown
    if DB.overlayShown then overlay:Show(); overlay:UpdateNow() else overlay:Hide() end
end

local events = CreateFrame("Frame")
VoidMarkForever.RegisterEvent(events,"ADDON_LOADED")
VoidMarkForever.RegisterEvent(events,"PLAYER_LOGIN")
VoidMarkForever.RegisterEvent(events,"PLAYER_ENTERING_WORLD")
VoidMarkForever.RegisterEvent(events,"ZONE_CHANGED_NEW_AREA")
VoidMarkForever.RegisterEvent(events,"ZONE_CHANGED")
VoidMarkForever.RegisterEvent(events,"CHAT_MSG_ADDON")

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= ADDON_NAME then return end
        ApplyDefaults()
        RegisterPrefix()
        return
    end

    if not DB then
        ApplyDefaults()
    end

    if event == "PLAYER_LOGIN" then
        CreateOverlay()
        CreateUI()
        lastZone = ZoneName()

        if C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                if frame then frame:UpdateNow() end
            end)
        end

        return
    end

    if event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Do NOT clear anchors on login/reload. Server-time cycle anchors remain valid.
        HandleZoneChange()
        if frame then frame:UpdateNow() end
        return
    end

    if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        HandleZoneChange()
        if frame then frame:UpdateNow() end
        return
    end
end)

events:SetScript("OnUpdate", function(_, elapsed)
    if not DB or not DB.enabled then return end
    updateAccum = updateAccum + elapsed
    if updateAccum < 0.25 then return end
    updateAccum = 0

    -- Polling also protects against a missed zone event.
    HandleZoneChange()

    for _, route in ipairs(ROUTE_ORDER) do
        UpdateAnnouncements(route)
    end

    if frame and frame:IsShown() then
        frame:UpdateNow()
    end

    if overlay and overlay:IsShown() and overlay.UpdateNow then
        overlay:UpdateNow()
    end
end)
