-- VoidMark Forever: your own note and a tag on an enemy player.
-- Note: free text ("camps the Crossroads flight master"), shown in the row tooltip
-- and on the Kill On Sight alert. Tag: Spare (could have ganked you and didn't) or
-- Rival (a fair fight, not Kill On Sight), shown as a marker on the row.
-- Set from the right-click menu on a row. Shared by all your characters.

VoidMarkPlayerNotes = VoidMarkPlayerNotes or {}
local PN = VoidMarkPlayerNotes

PN.MAX = 200
PN.TAGS = {
    spare = { label = "Spare", color = "|cff55dd55", icon = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:13:13:0:0|t " },
    rival = { label = "Rival", color = "|cffff9933", icon = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:13:13:0:0|t " },
}

function PN:Store()
    if type(VoidMarkDB) ~= "table" then return nil end
    VoidMarkDB.PlayerNotes = VoidMarkDB.PlayerNotes or {}
    return VoidMarkDB.PlayerNotes
end
local function entry(name, create)
    local store = PN:Store()
    if not store or type(name) ~= "string" or name == "" then return nil end
    if create and type(store[name]) ~= "table" then store[name] = {} end
    return store[name]
end
local function tidy(name)
    local store = PN:Store()
    local e = store and store[name]
    if type(e) == "table" and not e.note and not e.tag then store[name] = nil end
end
local function refresh()
    if VoidMark and VoidMark.RefreshCurrentList then pcall(VoidMark.RefreshCurrentList, VoidMark) end
end

function PN:Note(name)
    local e = entry(name)
    return e and type(e.note) == "string" and e.note ~= "" and e.note or nil
end
function PN:SetNote(name, text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("|", "/")
    if #text > PN.MAX then text = text:sub(1, PN.MAX) end
    local e = entry(name, text ~= "")
    if not e then return end
    e.note = text ~= "" and text or nil
    tidy(name); refresh()
end
function PN:Tag(name)
    local e = entry(name)
    return e and PN.TAGS[e.tag] and e.tag or nil
end
function PN:SetTag(name, tag)
    if tag ~= nil and not PN.TAGS[tag] then return end
    local e = entry(name, tag ~= nil)
    if not e then return end
    e.tag = tag
    tidy(name); refresh()
end
function PN:Marker(name)
    local t = PN.TAGS[PN:Tag(name)]
    return t and t.icon or ""
end
-- Tooltip lines for a player.
function PN:AddTooltip(tooltip, name)
    if not tooltip then return end
    local t = PN.TAGS[PN:Tag(name)]
    local note = PN:Note(name)
    if t then tooltip:AddLine(t.color .. "Tag: " .. t.label .. "|r") end
    if note then tooltip:AddLine("Note: " .. note, 1, 0.9, 0.55, true) end
end

-- Edit-a-note popup (opened from the row menu).
if StaticPopupDialogs then
    StaticPopupDialogs["VOIDMARK_PLAYER_NOTE"] = {
        text = "Your note on %s",
        button1 = SAVE or "Save",
        button2 = CANCEL or "Cancel",
        button3 = "Clear",
        hasEditBox = true,
        maxLetters = PN.MAX,
        editBoxWidth = 260,
        OnShow = function(self, data)
            local eb = self.editBox or self.EditBox
            if eb then eb:SetText(PN:Note(data) or ""); eb:HighlightText() end
        end,
        OnAccept = function(self, data)
            local eb = self.editBox or self.EditBox
            PN:SetNote(data, eb and eb:GetText() or "")
        end,
        OnAlt = function(_, data) PN:SetNote(data, "") end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            PN:SetNote(parent.data, self:GetText()); parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end
function PN:EditNote(name)
    if type(name) ~= "string" or not StaticPopup_Show then return end
    local shown = VoidMarkForever and VoidMarkForever.DisplayName and VoidMarkForever.DisplayName(name) or name
    StaticPopup_Show("VOIDMARK_PLAYER_NOTE", shown, nil, name)
end

-- Menu entries for the row right-click menu (level 1 and the Tag submenu).
function PN:AddMenu(level, player)
    if level == 1 then
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = PN:Note(player) and "Edit note..." or "Add note..."
        info.func = function() if CloseDropDownMenus then CloseDropDownMenus() end; PN:EditNote(player) end
        UIDropDownMenu_AddButton(info, level)
        info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.hasArrow = true
        local t = PN.TAGS[PN:Tag(player)]
        info.text = "Tag" .. (t and (": " .. t.color .. t.label .. "|r") or "")
        info.value = { Key = "VoidMarkTag" }
        UIDropDownMenu_AddButton(info, level)
    elseif level == 2 then
        for _, key in ipairs({ "spare", "rival" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = PN.TAGS[key].icon .. PN.TAGS[key].label
            info.checked = PN:Tag(player) == key
            info.func = function() PN:SetTag(player, key); if CloseDropDownMenus then CloseDropDownMenus() end end
            UIDropDownMenu_AddButton(info, level)
        end
        local info = UIDropDownMenu_CreateInfo()
        info.text = "No tag"
        info.checked = PN:Tag(player) == nil
        info.func = function() PN:SetTag(player, nil); if CloseDropDownMenus then CloseDropDownMenus() end end
        UIDropDownMenu_AddButton(info, level)
    end
end

-- The Kill On Sight alert shows your note under the location.
if hooksecurefunc and VoidMark then
    hooksecurefunc(VoidMark, "ShowAlert", function(_, kind, player)
        if kind ~= "kos" then return end
        local note = PN:Note(player)
        local w = VoidMark.AlertWindow
        if note and w and w.Location and w.Location.GetText then
            w.Location:SetText((w.Location:GetText() or "") .. "\n|cffffe08c" .. note .. "|r")
        end
    end)
end
