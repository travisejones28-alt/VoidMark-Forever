-- Keep alert state outside GankTracker's nearly full Lua 5.1 main chunk.
local F = VoidMarkForever
local GT = TaliaaGankTracker
local DISTRACT_SPELL_ID = 1725
local lastAlertAt

function GT:IsDistractAlertEnabled()
    if not VoidMarkDB then return true end
    if VoidMarkDB.VoidMarkDistractAlert == nil then
        VoidMarkDB.VoidMarkDistractAlert = true
    end
    return VoidMarkDB.VoidMarkDistractAlert == true
end

function GT:SetDistractAlertEnabled(enabled)
    VoidMarkDB = VoidMarkDB or {}
    VoidMarkDB.VoidMarkDistractAlert = enabled and true or false
end

function GT:ToggleDistractAlertEnabled()
    self:SetDistractAlertEnabled(not self:IsDistractAlertEnabled())
    return self:IsDistractAlertEnabled()
end

function GT:ShowDistractAlert(sourceName)
    if not self:IsDistractAlertEnabled() then return false end
    local now = GetTime()
    if lastAlertAt and now - lastAlertAt < 3 then return false end
    lastAlertAt = now
    sourceName = F.Readable(sourceName)
    local name = type(sourceName) == "string" and F.DisplayName(sourceName) or "UNKNOWN ROGUE"
    local msg = "DISTRACT USED  -  " .. name
    -- A ground-targeted cast does not establish who was affected.
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg,
            ChatTypeInfo and ChatTypeInfo.RAID_WARNING or {r=1,g=0.2,b=0.2})
    elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(msg, 1, 0.25, 0.15, 1)
    end
    if PlaySound then
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
    return true
end

function GT:ObserveDistractCast(spellID, sourceGUID, sourceName, hostile)
    spellID = F.Readable(spellID)
    sourceGUID = F.Readable(sourceGUID)
    hostile = F.Readable(hostile)
    if spellID ~= DISTRACT_SPELL_ID or hostile ~= true
        or type(sourceGUID) ~= "string" or not sourceGUID:match("^Player%-") then
        return false
    end
    return self:ShowDistractAlert(sourceName)
end

-- Use the optional readable combat log; native visible-unit casts are also
-- routed here by Compat/Events.lua when this client restricts the combat log.
local frame = CreateFrame("Frame")
F.RegisterEvent(frame, "COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", function()
    local _, event, _, guid, name, flags, _, _, _, _, _, spellID = F.CombatInfo()
    if event ~= "SPELL_CAST_SUCCESS" then return end
    local hostile = type(flags) == "number" and COMBATLOG_OBJECT_REACTION_HOSTILE
        and bit and bit.band(flags, COMBATLOG_OBJECT_REACTION_HOSTILE) ~= 0
    GT:ObserveDistractCast(spellID, guid, name, hostile == true)
end)
