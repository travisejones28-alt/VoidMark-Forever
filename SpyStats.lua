-- VOIDMARK STATISTICS BUILD: permanent history + custom VoidMark skin.
SpyStats = Spy:NewModule("SpyStats", "AceTimer-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Spy", true)

local Spy = Spy
local Data = SpyData

local GUI = {}
local units = {
    recent = {},
    display = {},
}

local PAGE_SIZE = 30
local XML_ROW_COUNT = 34
local TAB_PLAYER = 1
local VIEW_PLAYER_HISTORY = 1
local COLOR_NORMAL = {1, 1, 1}
local COLOR_SAME_FACTION = {0, 1, 0}
local COLOR_KOS = {1, 0, 0}

local VM_PURPLE_BRIGHT = {0.82, 0.50, 1.00}
local VM_BG = {0.010, 0.008, 0.016, 0.97}
local VM_ROW_A = {0.018, 0.016, 0.026, 0.96}
local VM_ROW_B = {0.030, 0.026, 0.042, 0.96}

local function StatsFilterStore()
    if not SpyDB then return nil end
    SpyDB.VoidMarkStatsFilters = SpyDB.VoidMarkStatsFilters or {}
    return SpyDB.VoidMarkStatsFilters
end

local function StyleVoidMarkStatistics()
    local f = SpyStatsFrame
    if not f or f.VoidMarkStyled then return end
    f.VoidMarkStyled = true

    f:SetSize(1100, 610)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(VM_BG[1], VM_BG[2], VM_BG[3], VM_BG[4])
    f.VoidMarkBackground = bg

    local headerBG = f:CreateTexture(nil, "BORDER")
    headerBG:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    headerBG:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    headerBG:SetHeight(42)
    headerBG:SetColorTexture(0.028, 0.012, 0.042, 0.99)

    local footerBG = f:CreateTexture(nil, "BORDER")
    footerBG:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    footerBG:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    footerBG:SetHeight(42)
    footerBG:SetColorTexture(0.020, 0.012, 0.030, 0.99)

    local top = f:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    top:SetColorTexture(0.43, 0.12, 0.64, 0.95)

    local bottom = f:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(1)
    bottom:SetColorTexture(0.43, 0.12, 0.64, 0.95)

    local left = f:CreateTexture(nil, "BORDER")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(1)
    left:SetColorTexture(0.43, 0.12, 0.64, 0.95)

    local right = f:CreateTexture(nil, "BORDER")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(1)
    right:SetColorTexture(0.43, 0.12, 0.64, 0.95)

    if SpyStatsFrame_Header then SpyStatsFrame_Header:Hide() end
    if SpyStatsFrame_Title then
        SpyStatsFrame_Title:SetText("VOIDMARK  •  STATISTICS")
        SpyStatsFrame_Title:ClearAllPoints()
        SpyStatsFrame_Title:SetPoint("TOP", f, "TOP", 0, -13)
        SpyStatsFrame_Title:SetTextColor(VM_PURPLE_BRIGHT[1], VM_PURPLE_BRIGHT[2], VM_PURPLE_BRIGHT[3], 1)
    end

    if SpyStatsFrameTopCloseButton then
        local normal = SpyStatsFrameTopCloseButton:GetNormalTexture()
        local pushed = SpyStatsFrameTopCloseButton:GetPushedTexture()
        local highlight = SpyStatsFrameTopCloseButton:GetHighlightTexture()
        if normal then normal:SetAlpha(0) end
        if pushed then pushed:SetAlpha(0) end
        if highlight then highlight:SetAlpha(0) end
        if not SpyStatsFrameTopCloseButton.VoidMarkText then
            local x = SpyStatsFrameTopCloseButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            x:SetPoint("CENTER")
            x:SetText("X")
            x:SetTextColor(1.0, 0.28, 0.40, 1)
            SpyStatsFrameTopCloseButton.VoidMarkText = x
        end
    end

    if SpyStatsTabFrame then
        SpyStatsTabFrame:ClearAllPoints()
        SpyStatsTabFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48)
        SpyStatsTabFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 48)
    end

    local content = SpyStatsTabFrameTabContentFrame and SpyStatsTabFrameTabContentFrame.ContentFrame
    if content and content.SetBackdrop then
        content:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        content:SetBackdropColor(0.008, 0.008, 0.012, 0.92)
        content:SetBackdropBorderColor(0.22, 0.08, 0.32, 1)
    end

    if SpyStatsFrameFilterText then
        SpyStatsFrameFilterText:SetText("FILTER")
        SpyStatsFrameFilterText:ClearAllPoints()
        SpyStatsFrameFilterText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 16)
        SpyStatsFrameFilterText:SetTextColor(VM_PURPLE_BRIGHT[1], VM_PURPLE_BRIGHT[2], VM_PURPLE_BRIGHT[3], 1)
    end
    if SpyStatsFrameShowOnlyText then SpyStatsFrameShowOnlyText:Hide() end

    if SpyStatsFilterBox then
        SpyStatsFilterBox:ClearAllPoints()
        SpyStatsFilterBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 67, 9)
        SpyStatsFilterBox:SetSize(190, 25)
        if SpyStatsFilterBox.FilterBox and SpyStatsFilterBox.FilterBox.SetBackdrop then
            SpyStatsFilterBox.FilterBox:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
            })
            SpyStatsFilterBox.FilterBox:SetBackdropColor(0.018, 0.014, 0.024, 1)
            SpyStatsFilterBox.FilterBox:SetBackdropBorderColor(0.36, 0.12, 0.52, 1)
        end
    end

    local filterPositions = {
        {SpyStatsKosCheckbox, SpyStatsKosCheckboxText, 270},
        {SpyStatsRealmCheckbox, SpyStatsRealmCheckboxText, 356},
        {SpyStatsWinsLosesCheckbox, SpyStatsWinsLosesCheckboxText, 458},
        {SpyStatsReasonCheckbox, SpyStatsReasonCheckboxText, 580},
    }
    for _, item in ipairs(filterPositions) do
        local cb, label, x = item[1], item[2], item[3]
        if cb then
            cb:ClearAllPoints()
            cb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 8)
            local checked = cb:GetCheckedTexture()
            local normal = cb:GetNormalTexture()
            local highlight = cb:GetHighlightTexture()
            if checked then checked:SetVertexColor(0.76, 0.38, 1.00, 1) end
            if normal then normal:SetVertexColor(0.40, 0.22, 0.52, 1) end
            if highlight then highlight:SetVertexColor(0.72, 0.38, 0.96, 0.32) end
        end
        if label then label:SetTextColor(0.86, 0.80, 0.91, 1) end
    end

    if SpyStatsRefreshButton then
        SpyStatsRefreshButton:ClearAllPoints()
        SpyStatsRefreshButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 9)
        SpyStatsRefreshButton:SetSize(92, 24)
        local normal = SpyStatsRefreshButton:GetNormalTexture()
        local pushed = SpyStatsRefreshButton:GetPushedTexture()
        local highlight = SpyStatsRefreshButton:GetHighlightTexture()
        if normal then normal:SetAlpha(0) end
        if pushed then pushed:SetAlpha(0) end
        if highlight then highlight:SetAlpha(0) end
        local fs = SpyStatsRefreshButton:GetFontString()
        if fs then fs:SetTextColor(0.92, 0.80, 1.00, 1) end
        if not SpyStatsRefreshButton.VoidMarkBG then
            local b = SpyStatsRefreshButton:CreateTexture(nil, "BACKGROUND")
            b:SetAllPoints()
            b:SetColorTexture(0.12, 0.035, 0.18, 1)
            SpyStatsRefreshButton.VoidMarkBG = b
        end
    end

    if SpyStatsHonorKillsText then
        SpyStatsHonorKillsText:ClearAllPoints()
        SpyStatsHonorKillsText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 705, 16)
        SpyStatsHonorKillsText:SetTextColor(0.78, 0.67, 0.84, 1)
    end
    if SpyStatsPvPDeathsText then SpyStatsPvPDeathsText:Hide() end

    if SpyStatsPlayersNameSort then SpyStatsPlayersNameSort:SetWidth(135) end
    if SpyStatsPlayersGuildSort then SpyStatsPlayersGuildSort:SetWidth(130) end
    if SpyStatsPlayersReasonSort then SpyStatsPlayersReasonSort:SetWidth(220) end
    if SpyStatsZoneSort then SpyStatsZoneSort:SetWidth(220) end

    for row = 1, PAGE_SIZE do
        local fields = GUI.ListFrameFields[VIEW_PLAYER_HISTORY][row]
        if fields then
            local name = fields["Name"]
            local guild = fields["Guild"]
            local reason = fields["Reason"]
            local zone = fields["Zone"]
            if name then name:SetWidth(135) end
            if guild then guild:SetWidth(130) end
            if reason then reason:SetWidth(220) end
            if zone then zone:SetWidth(220) end
        end
    end

    local sortButtons = {
        SpyStatsPlayersNameSort, SpyStatsPlayersLevelSort, SpyStatsPlayersRankSort,
        SpyStatsPlayersClassSort, SpyStatsPlayersGuildSort, SpyStatsPlayersWinsSort,
        SpyStatsPlayersLosesSort, SpyStatsPlayersReasonSort, SpyStatsZoneSort,
        SpyStatsTimeSort, SpyStatsListSort,
    }
    for _, b in ipairs(sortButtons) do
        if b then
            local fs = b:GetFontString()
            if fs then fs:SetTextColor(0.78, 0.48, 1.0, 1) end
        end
    end
end

GUI.ListFrameLines = {
    [VIEW_PLAYER_HISTORY] = {},
}
GUI.ListFrameFields = {
    [VIEW_PLAYER_HISTORY] = {},
}

local SORT = {
    ["SpyStatsPlayersNameSort"] = "name",
    ["SpyStatsPlayersLevelSort"] = "level",
    ["SpyStatsPlayersRankSort"] = "rank",
    ["SpyStatsPlayersClassSort"] = "class",
    ["SpyStatsPlayersGuildSort"] = "guild",
    ["SpyStatsPlayersWinsSort"] = "wins",
    ["SpyStatsPlayersLosesSort"] = "loses",	
    ["SpyStatsTimeSort"] = "time",	
}

function SpyStats:OnInitialize()
    -- create lookup tables for all GUI list lines and buttons
    local views = {
        [VIEW_PLAYER_HISTORY] = "SpyStatsPlayerHistoryFrameListFrame",
    }

    for view, frame in pairs(views) do
        GUI.ListFrameLines[view] = {}
        setmetatable(GUI.ListFrameLines[view], {
            __index = function(t, k)
                local b = _G[views[view].."Line"..k]
                if b then
                    rawset(t, k, b)
                    return b
                end
            end,
        })

        for line = 1, PAGE_SIZE do
            GUI.ListFrameFields[view][line] = {}
            setmetatable(GUI.ListFrameFields[view][line], {
                __index = function(t, k)
                    local f = _G[views[view].."Line"..line..k]
                    if f then
                        rawset(t, k, f)
                        return f
                    end
                end,
            })
        end
    end

    -- set initial view
    self.sortBy = "time"	
    self.view = VIEW_PLAYER_HISTORY

    -- localization
    SpyStatsKosCheckboxText:SetText(L["KOS"])
    SpyStatsRealmCheckboxText:SetText(L["Realm"])
    SpyStatsWinsLosesCheckboxText:SetText(L["Won/Lost"])
    SpyStatsReasonCheckboxText:SetText(L["Reason"])
    
    StyleVoidMarkStatistics()

    for row = 1, XML_ROW_COUNT do
        local line = _G["SpyStatsPlayerHistoryFrameListFrameLine" .. row]
        if line then
            if row <= PAGE_SIZE then
                if not line.VoidMarkRowBG then
                    local rowBG = line:CreateTexture(nil, "BACKGROUND")
                    rowBG:SetAllPoints()
                    rowBG:SetColorTexture(0.02, 0.018, 0.028, 0.95)
                    line.VoidMarkRowBG = rowBG

                    local hl = line:GetHighlightTexture()
                    if hl then
                        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
                        hl:SetVertexColor(0.56, 0.20, 0.84, 0.24)
                    end
                end
            else
                -- The original Spy XML physically contains 34 rows. VoidMark has a
                -- dedicated footer now, so the extra four rows must never draw over it.
                line:Hide()
            end
        end
    end

    table.insert(UISpecialFrames, "SpyStatsFrame")
end

function SpyStats:OnDisable()
    self:Hide()
end

function SpyStats:Show()
    StyleVoidMarkStatistics()
    for row = PAGE_SIZE + 1, XML_ROW_COUNT do
        local line = _G["SpyStatsPlayerHistoryFrameListFrameLine" .. row]
        if line then line:Hide() end
    end
    local store = StatsFilterStore() or {}
    SpyStatsFilterBox:SetText(tostring(store.text or ""))
    SpyStatsKosCheckbox:SetChecked(store.kos and true or false)
    SpyStatsRealmCheckbox:SetChecked(store.realm and true or false)
    SpyStatsWinsLosesCheckbox:SetChecked(store.pvp and true or false)
    SpyStatsReasonCheckbox:SetChecked(store.reason and true or false)

    SpyStatsFrame:Show()
    self:Recalulate()
    self:ScheduleRepeatingTimer("Refresh", 1)
end

function SpyStats:Hide()
    self:CancelAllTimers()
    SpyStatsFrame:Hide()
    self:Cleanup()
end

function SpyStats:Toggle()
    if SpyStatsFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function SpyStats:IsShown()
    return SpyStatsFrame:IsShown()
end 

function SpyStats:UpdateView()
    local tab = PanelTemplates_GetSelectedTab(SpyStatsTabFrame)

    if tab == TAB_PLAYER then
		self.view = VIEW_PLAYER_HISTORY

        -- VoidMark owns the footer filter layout; do not restore Spy's old anchors.

        if (self.sortBy == "name") or (self.sortBy == "level") or (self.sortBy == "rank") or (self.sortBy == "class") then
            self.sortBy = "time"
        end 
    end 
    self:Refresh()
end

function SpyStats:OnNewEvent(unit)
    self.newevents = true
end

function SpyStats:SetSortColumn(name)
    name = SORT[name]
    if name then
        self.sortBy = name
        self:Recalulate()
    end
end

function SpyStats:Recalulate()
    if not self:IsShown() or not self:IsEnabled() then
		return
	end

    self.newevents = false
    SpyStatsRefreshButton:UnlockHighlight()

    local tab = PanelTemplates_GetSelectedTab(SpyStatsTabFrame)

    local i = 1
    local totalWins = 0
    local totalLoses = 0

    if tab == TAB_PLAYER then
        for _, unit in SpyData:GetPlayers(self.sortBy) do
            units.recent[i] = unit
            totalWins = totalWins + (tonumber(unit.wins) or 0)
            totalLoses = totalLoses + (tonumber(unit.loses) or 0)
            i = i + 1
        end
    end

    self.VoidMarkSummary = {
        marks = i - 1,
        wins = totalWins,
        loses = totalLoses,
    }

    for j = i, #units.recent do
		units.recent[j] = nil
	end

    self:Filter()
end

function SpyStats:Filter()
    if not self:IsShown() or not self:IsEnabled() then
		return
	end

    local tab = PanelTemplates_GetSelectedTab(SpyStatsTabFrame)

    local filter = SpyStatsFilterBox:GetText() or ""
    local filterkos = SpyStatsKosCheckbox:GetChecked()
    local filterrealm = SpyStatsRealmCheckbox:GetChecked()
    local filterpvp = SpyStatsWinsLosesCheckbox:GetChecked()
    local filterreason = SpyStatsReasonCheckbox:GetChecked()

    local store = StatsFilterStore()
    if store then
        store.text = filter
        store.kos = filterkos and true or false
        store.realm = filterrealm and true or false
        store.pvp = filterpvp and true or false
        store.reason = filterreason and true or false
    end

    local i = 1
    for _, unit in ipairs(units.recent) do
        local session = SpyData:GetUnitSession(unit)

        if (filter == "" or (unit.name and unit.name:sub(1, string.len(filter)):lower() == filter:lower()) or (unit.guild and unit.guild:sub(1, string.len(filter)):lower() == filter:lower())) and (not filterkos or unit.kos) and (not filterrealm or unit.name and not unit.name:find "-") and (not filterpvp or ((unit.wins and unit.wins > 0) or (unit.loses and unit.loses > 0))) and (not filterreason or unit.reason) then
			units.display[i] = unit
			i = i + 1
        end
    end

    for j = i, #units.display do
		units.display[j] = nil
	end

    self:Refresh()
end

function SpyStats:Refresh()
    if self.refreshing then
		return
	end
    self.refreshing = true

    local tab = PanelTemplates_GetSelectedTab(SpyStatsTabFrame)
	local view = SpyStats.view

    -- set offest location to current scroll position
    local Scroll = SpyStatsTabFrameTabContentFrameScrollFrame
    FauxScrollFrame_Update(Scroll, #units.display, PAGE_SIZE, 15)
    local offset = FauxScrollFrame_GetOffset(Scroll)
    Scroll:Show()

    local now = time()

    -- loop through all frame lines
    for row = 1, PAGE_SIZE do
        local line = GUI.ListFrameLines[view][row]

        -- use offset to locate where to start displaying records
        local i = row + offset

        if i <= #units.display then
            local unit = units.display[i]
            local session = SpyData:GetUnitSession(unit)

            line.unit = unit

            local age = now - unit.time

            local r, g, b
            if unit.kos and (age < 60) then
                r, g, b = unpack(COLOR_KOS)
            elseif unit.faction and unit.faction == Spy.FactionName then
                r, g, b = unpack(COLOR_SAME_FACTION)
			else
                r, g, b = unpack(COLOR_NORMAL)
            end

            if line.VoidMarkRowBG then
                local base = (row % 2 == 0) and VM_ROW_B or VM_ROW_A
                if unit.kos then
                    line.VoidMarkRowBG:SetColorTexture(0.16, 0.025, 0.075, 0.94)
                elseif (tonumber(unit.wins) or 0) > 0 then
                    line.VoidMarkRowBG:SetColorTexture(base[1] + 0.012, base[2], base[3] + 0.018, base[4])
                else
                    line.VoidMarkRowBG:SetColorTexture(base[1], base[2], base[3], base[4])
                end
            end

            if tab == TAB_PLAYER then
                local name = GUI.ListFrameFields[view][row]["Name"]
                name:SetText(unit.name)
                name:SetTextColor(r, g, b)

                local level = GUI.ListFrameFields[view][row]["Level"]
                level:SetText(unit.level)
                level:SetTextColor(r, g, b)

                local rank = GUI.ListFrameFields[view][row]["Rank"]
                local rankValue = tonumber(unit.rank)
                if not rankValue or rankValue <= 0 then
                    rankValue = 0
                    unit.rank = 0
                end
                rank:SetText(rankValue)
                rank:SetTextColor(r, g, b)

                local class = GUI.ListFrameFields[view][row]["Class"]
				local classtext = unit.class
				if classtext then
					classtext = (L[classtext])
				else
					classtext = "?"
				end	
                class:SetText(classtext)
                local classColor = unit.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[unit.class]
                if classColor then
                    class:SetTextColor(classColor.r, classColor.g, classColor.b)
                else
                    class:SetTextColor(r, g, b)
                end

                local guild = GUI.ListFrameFields[view][row]["Guild"]
                guild:SetText(unit.guild or "?")
                guild:SetTextColor(r, g, b)

                local wins = GUI.ListFrameFields[view][row]["Wins"]
                wins:SetText(unit.wins or 0)
                if (tonumber(unit.wins) or 0) > 0 then
                    wins:SetTextColor(0.36, 1.00, 0.55)
                else
                    wins:SetTextColor(0.56, 0.52, 0.60)
                end

                local loses = GUI.ListFrameFields[view][row]["Loses"]
                loses:SetText(unit.loses or 0)
                if (tonumber(unit.loses) or 0) > 0 then
                    loses:SetTextColor(1.00, 0.34, 0.42)
                else
                    loses:SetTextColor(0.56, 0.52, 0.60)
                end

				local reason = GUI.ListFrameFields[view][row]["Reason"]
				local reasonText = ""
				if unit.reason then
					for reason in pairs(unit.reason) do
						if reasonText ~= "" then
							reasonText = reasonText..", "
						end
						if reason == L["KOSReasonOther"] then
							reasonText = reasonText..unit.reason[reason]
						else
							reasonText = reasonText..reason
						end
					end
				end
                reason:SetText(reasonText or "")
                reason:SetTextColor(r, g, b)
					
				local zone = GUI.ListFrameFields[view][row]["Zone"]  
				local location = unit.zone
					if location and unit.subZone and unit.subZone ~= "" and unit.subZone ~= location then
						location = unit.subZone..", "..location
					end
				zone:SetText(location or "?")
                zone:SetTextColor(r, g, b)

				local time = GUI.ListFrameFields[view][row]["Time"]
                time:SetText((unit.time and unit.time > 0) and Spy:FormatTime(unit.time) or "?")				
                time:SetTextColor(r, g, b)

                local tList = GUI.ListFrameFields[view][row]["List"]
                local f = ""
				for key, value in pairs(SpyPerCharDB.KOSData) do
					-- find units that match
					local KoSname = key
					if unit.name == KoSname then
						f = f .. "x"
					end
				end		
                tList:SetText(f)
                tList:SetTextColor(r, g, b)
            end
            line:Show()
        else
            line:Hide()
        end
    end

    if SpyStatsHonorKillsText then
        local summary = self.VoidMarkSummary or {}
        local wins = tonumber(summary.wins) or 0
        local loses = tonumber(summary.loses) or 0
        local fights = wins + loses
        local rate = fights > 0 and math.floor((wins / fights) * 100 + 0.5) or 0
        SpyStatsHonorKillsText:SetText(
            "MARKS " .. tostring(summary.marks or #units.recent)
            .. "  •  |cff55ff88W " .. tostring(wins) .. "|r"
            .. "  •  |cffff5566L " .. tostring(loses) .. "|r"
            .. "  •  " .. tostring(rate) .. "%"
        )
    end

    self.refreshing = false
end

function SpyStats:OnRefreshButtonUpdate(frame, elapsed)
    if not self.newevents then
		return
	end

    local timer = frame.timer + elapsed

    if (timer < .5) then
        frame.timer = timer
        return
    end

    while (timer >= .5) do
        timer = timer - .5
    end
    frame.timer = timer

    if (frame.state) then
        frame:UnlockHighlight()
        frame.state = nil
    else
        frame:LockHighlight()
        frame.state = true
    end    
end

-- remove all references to units
function SpyStats:Cleanup()
    for _, lines in pairs(GUI.ListFrameLines) do
        for _, line in pairs(lines) do
            line.unit = nil
        end
    end

    for i in ipairs(units.recent) do units.recent[i] = nil end
    for i in ipairs(units.display) do units.display[i] = nil end
end

function CreateStatsDropdown(node)
    local info = {}
    local unit = node.unit
    local session = SpyData:GetUnitSession(unit)
    if UIDROPDOWNMENU_MENU_LEVEL == 1 then
        info = UIDropDownMenu_CreateInfo()
        info.isTitle = true
        info.text = unit.name
		info.notCheckable = true
        UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)

		if not unit.kos then
			info.isTitle = nil
			info.notCheckable = true
			info.hasArrow = false
			info.disabled = nil
			info.text = L["AddToKOSList"]
			info.func = function()
				Spy:ToggleKOSPlayer(true, unit.name)
			end
			info.value = nil
			UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
			
		else
			info = UIDropDownMenu_CreateInfo()
			info.notCheckable = true
			info.text = L["KOSReasonDropDownMenu"]
			info.value = unit
			info.func = function()
				Spy:SetKOSReason(unit.name, L["KOSReasonOther"], other)
			end
			info.checked = false
			UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
			
			info.isTitle = nil
			info.notCheckable = true
			info.hasArrow = false
			info.disabled = nil
			info.text = L["RemoveFromKOSList"]
			info.func = function()
				Spy:ToggleKOSPlayer(false, unit.name)
			end
			info.value = nil
			UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)

			info.isTitle = nil
			info.notCheckable = true
			info.hasArrow = false
			info.disabled = nil
			info.text = L["KOSReasonClear"]
			info.func = function()
				Spy:SetKOSReason(unit.name, nil)
			end
			info.value = nil
			UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
		end	

        elseif UIDROPDOWNMENU_MENU_LEVEL == 2 then
    end 
end

function Spy:ShowStatsDropDown(node, button)
    if button ~= "RightButton" then
		return
	end
    GameTooltip:Hide()
	StatsDropDownMenu.unit = node.unit
    local cursor = GetCursorPosition() / UIParent:GetEffectiveScale()
    local center = node:GetLeft() + (node:GetWidth() / 2)
    UIDropDownMenu_Initialize(StatsDropDownMenu, CreateStatsDropdown, "MENU")
    UIDropDownMenu_SetAnchor(StatsDropDownMenu, cursor - center, 0, "TOPRIGHT", node, "TOP")
    CloseDropDownMenus(1)
    ToggleDropDownMenu(1, nil, StatsDropDownMenu)    
end