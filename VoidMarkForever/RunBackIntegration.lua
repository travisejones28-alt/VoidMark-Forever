local VMAPI = VoidMarkForever.API
-- VoidMark + Taliaa RunBack integration.
-- Keeps normal VoidMark detection behavior for living enemies, pins a dead
-- enemy through the corpse-run floor, then releases the pin 60 seconds after
-- RETURN POSSIBLE.  The far-right W/L record remains untouched.
local _, RB = ...

VoidMark.RunBackPinned = VoidMark.RunBackPinned or {}
RB.byVoidMarkName = RB.byVoidMarkName or {}

local function BaseName(name)
    return tostring(name or "")
end

local function Lower(s) return string.lower(tostring(s or "")) end
local function KnownGUID(info)
    local guid=type(info)=="table" and info.guid
    return type(guid)=="string" and guid:sub(1,7)=="Player-" and guid or nil
end

local function ResolveVoidMarkName(raw,guid)
    if not raw or raw=="" then return nil end
    local data=VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData or {}
    local exactGUID=KnownGUID(data[raw])
    if guid and exactGUID==guid then return raw end
    if raw:find("-",1,true) and (data[raw] or (VoidMark.NearbyList and VoidMark.NearbyList[raw])) and (not exactGUID or exactGUID==guid) then return raw end
    local keys={}
    for key in pairs(data) do keys[key]=true end
    for key in pairs(VoidMark.NearbyList or {}) do keys[key]=true end
    local exact,base,baseCount=nil,nil,0
    for key in pairs(keys) do
        local info=data[key]
        local known=KnownGUID(info)
        if guid and known==guid then return key end
        local compatible=not known or known==guid
        if compatible and Lower(key)==Lower(raw) then exact=key end
        if compatible and Lower(BaseName(key))==Lower(BaseName(raw)) then base=key; baseCount=baseCount+1 end
    end
    if exact then return exact end
    -- An explicit realm is part of identity. Never strip it to attach a timer
    -- to another realm. Unqualified names may match only one known identity.
    if not raw:find("-",1,true) and baseCount==1 then return base end
    return raw
end

local function MapRecord(r)
    if not r or not r.name then return end
    local key=ResolveVoidMarkName(r.name,r.guid)
    r.voidMarkName=key
    VoidMark.RunBackPinned[key]=r.guid
    RB.byVoidMarkName[Lower(key)]=r.guid
    return key
end

function VoidMark:GetRunBackRecord(name)
    if not name or not RB.active then return nil end
    local data=VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData
    local info=data and data[name]
    local guid=KnownGUID(info)
    if guid then return RB.active[guid] end
    local full=Lower(name)
    local qualified=name:find("-",1,true)~=nil
    local found
    for _,r in pairs(RB.active) do
        local key=r.voidMarkName or r.name
        local matches=qualified and (Lower(key)==full or Lower(r.name)==full)
            or (not qualified and (Lower(BaseName(key))==full or Lower(BaseName(r.name))==full))
        if matches then
            if found and found.guid~=r.guid then return nil end
            found=r
        end
    end
    return found
end

function VoidMark:IsRunBackPinned(name)
    return self:GetRunBackRecord(name)~=nil
end

local function Clock(seconds)
    local t=math.max(0,math.floor(seconds or 0))
    return string.format("%d:%02d",math.floor(t/60),t%60)
end

function VoidMark:GetRunBackDisplay(name)
    local r=self:GetRunBackRecord(name)
    if not r or not RB:Finite(r.readyAt) then return nil end
    local now=RB:Now()
    local delta=r.readyAt-now
    if delta>0 then
        -- Yellow countdown until the earliest possible return floor.
        return {time=Clock(delta), ready=false, record=r}
    end
    -- Once return is possible, keep the exact same compact timer format but
    -- count upward in red.  No POS/REZ/ALIVE label is shown.
    return {time="+"..Clock(-delta), ready=true, record=r}
end

-- Fired exactly once when a pinned dead player is positively seen alive again.
-- Treat that as a fresh local detection for timestamps and play the same sound
-- family VoidMark normally uses: KOS alert for KOS, guild-KOS where applicable,
-- race alert when configured, otherwise the standard nearby ping.
function VoidMark:OnRunBackRezConfirmed(r, unit)
    if not r then return end
    local name=r.voidMarkName or ResolveVoidMarkName(r.name,r.guid)
    if not name then return end

    local now=time()
    VoidMark.NearbyList=VoidMark.NearbyList or {}
    VoidMark.ActiveList=VoidMark.ActiveList or {}
    VoidMark.InactiveList=VoidMark.InactiveList or {}
    VoidMark.LastHourList=VoidMark.LastHourList or {}
    VoidMark.NearbyList[name]=now
    VoidMark.ActiveList[name]=now
    VoidMark.InactiveList[name]=nil
    VoidMark.LastHourList[name]=now

    if r._voidMarkRezSoundPlayed then return end
    r._voidMarkRezSoundPlayed=true

    if not (VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.EnableSound) then return end
    local profile=VoidMark.db.profile
    local playerData=VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData and VoidMarkPerCharDB.PlayerData[name]
    local isKOS=VoidMarkPerCharDB and VoidMarkPerCharDB.KOSData and VoidMarkPerCharDB.KOSData[name]

    if isKOS and profile.WarnOnKOS then
        PlaySoundFile("Interface\\AddOns\\VoidMarkForever\\Sounds\\detected-kos.mp3",profile.SoundChannel)
        return
    end
    if profile.WarnOnKOSGuild and playerData and playerData.guild and VoidMark.KOSGuild and VoidMark.KOSGuild[playerData.guild] then
        PlaySoundFile("Interface\\AddOns\\VoidMarkForever\\Sounds\\detected-kosguild.mp3",profile.SoundChannel)
        return
    end
    if profile.OnlySoundKoS then return end
    if playerData and profile.WarnOnRace and playerData.race==profile.SelectWarnRace then
        PlaySoundFile("Interface\\AddOns\\VoidMarkForever\\Sounds\\detected-race.mp3",profile.SoundChannel)
    else
        PlaySoundFile("Interface\\AddOns\\VoidMarkForever\\Sounds\\detected-nearby.mp3",profile.SoundChannel)
    end
end

function RB:OnVoidMarkRezConfirmed(r,unit)
    VoidMark:OnRunBackRezConfirmed(r,unit)
    if not InCombatLockdown() and VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.CurrentList==1 then
        VoidMark:RefreshCurrentList()
        if VoidMark.UpdateActiveCount then VoidMark:UpdateActiveCount() end
    end
end

function RB:OnVoidMarkTimerCreated(r, restored)
    local name=MapRecord(r)
    if not name then return end
    local now=time()
    VoidMark.NearbyList=VoidMark.NearbyList or {}
    VoidMark.ActiveList=VoidMark.ActiveList or {}
    VoidMark.InactiveList=VoidMark.InactiveList or {}
    VoidMark.LastHourList=VoidMark.LastHourList or {}

    -- If VoidMark already knew this enemy, preserve its real detection stamp.
    -- Otherwise add the combat-log victim so the pinned timer has a row.
    if not VoidMark.NearbyList[name] then VoidMark.NearbyList[name]=now end
    if not VoidMark.ActiveList[name] and not VoidMark.InactiveList[name] then VoidMark.InactiveList[name]=VoidMark.NearbyList[name] or now end
    VoidMark.LastHourList[name]=math.max(tonumber(VoidMark.LastHourList[name]) or 0,now)

    if not InCombatLockdown() and VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.CurrentList==1 then
        VoidMark:RefreshCurrentList()
        if VoidMark.UpdateActiveCount then VoidMark:UpdateActiveCount() end
    end
end

function RB:OnVoidMarkTimerRemoved(r, reason)
    if not r then return end
    local name=r.voidMarkName or ResolveVoidMarkName(r.name,r.guid)
    if not name then return end
    if VoidMark.RunBackPinned[name]==r.guid then VoidMark.RunBackPinned[name]=nil end
    if RB.byVoidMarkName[Lower(name)]==r.guid then RB.byVoidMarkName[Lower(name)]=nil end

    -- Another GUID may still own this exact row after a replacement.
    local owner=VoidMark:GetRunBackRecord(name)
    if owner and owner.guid~=r.guid then return end

    -- If the enemy has actually been detected again recently, hand the row back
    -- to normal VoidMark expiration. Otherwise remove the dead pinned row now.
    local now=time()
    local activeAt=VoidMark.ActiveList and tonumber(VoidMark.ActiveList[name])
    local recent=activeAt and (now-activeAt)<=((VoidMark.ActiveTimeout or 10)+1)
    if not recent then
        if VoidMark.ActiveList then VoidMark.ActiveList[name]=nil end
        if VoidMark.InactiveList then VoidMark.InactiveList[name]=nil end
        if VoidMark.NearbyList then VoidMark.NearbyList[name]=nil end
    end
    if not InCombatLockdown() and VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.CurrentList==1 then
        VoidMark:RefreshCurrentList()
        if VoidMark.UpdateActiveCount then VoidMark:UpdateActiveCount() end
    end
end

-- Timers.lua calls RenderRows every second.  In the integrated build that tick
-- simply repaints the already-existing VoidMark rows; no second run-back window.
function RB:RenderRows()
    local frame=VoidMark.MainWindow
    if not frame or not frame:IsShown() then return end
    for i=1,(VoidMark.ListAmountDisplayed or 0) do
        local name=VoidMark.ButtonName and VoidMark.ButtonName[i]
        local vm=VoidMark.VoidMark
        if name and vm and vm.StyleRow then
            local opacity=1
            if VoidMark.db and VoidMark.db.profile and VoidMark.db.profile.CurrentList==1 and VoidMark.InactiveList and VoidMark.InactiveList[name] then opacity=.5 end
            vm:StyleRow(i,name,nil,opacity)
        end
    end
end

-- Expose the engine for debugging without making the standalone frame necessary.
_G.VoidMarkRunBack = RB
