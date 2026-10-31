-- Forever event adapter: native kill credit, readable spell/aura observations,
-- friends and self-Sap. Feature modules keep their existing recording/UI paths.
local F=VoidMarkForever
local A=F.Namespace
local frame=CreateFrame("Frame")
local identities,auras,friends={}, {}, {}
local lossAt=0
local function IsPlayer(guid) return type(guid)=="string" and guid:sub(1,7)=="Player-" end
local function GroupSource(guid)
    if type(guid)~="string" then return false end
    A:RefreshGroup()
    return A.group and A.group[guid] or false
end
local function CacheUnit(unit)
    if type(unit)~="string" then return end
    local guid=F.Safe(UnitGUID,unit)
    if type(guid)~="string" then return end
    local name=F.FullName(unit)
    local isPlayer=F.Safe(UnitIsPlayer,unit)
    local hostile=F.Safe(UnitCanAttack,"player",unit)
    local _,class=F.Safe(UnitClass,unit)
    local creature=F.Safe(UnitCreatureType,unit)
    if name and (isPlayer or hostile) then
        identities[guid]={name=name,class=class,hostile=hostile,player=isPlayer,creature=creature,unit=unit,at=GetTime()}
        if isPlayer then
            F.GUIDToName[guid]=name; F.NameToGUID[name]=guid
            A:Observe(unit)
        end
    end
end
function F.HandlePartyKill(attackerGUID,targetGUID,unconscious)
    attackerGUID=F.Readable(attackerGUID); targetGUID=F.Readable(targetGUID)
    unconscious=F.Readable(unconscious)
    if type(targetGUID)~="string" or not GroupSource(attackerGUID) then return end
    if unconscious==true or unconscious==1 then return end
    local identity=identities[targetGUID]
    local name=(IsPlayer(targetGUID) and F.ResolvePlayerNameByGUID(targetGUID)) or (identity and identity.name)
    if not name then return end
    local gt=TaliaaGankTracker
    if not gt then return end
    local mine=attackerGUID==F.Safe(UnitGUID,"player")
        or attackerGUID==F.Safe(UnitGUID,"pet")
    if not IsPlayer(targetGUID) then
        -- A pet must be positively observed as a hostile player-controlled
        -- Hunter pet; arbitrary NPC Beast kills cannot inflate pet statistics.
        if mine and identity and identity.hunterPet and identity.hostile and gt.RecordHunterPetKill then
            gt:RecordHunterPetKill(name,targetGUID)
        end
        return
    end
    local known=VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData and VoidMarkPerCharDB.PlayerData[name]
    if (known and known.isEnemy==false) or (identity and identity.hostile==false) then return end
    -- PARTY_KILL is the known-good Forever death credit; visible corpse/health
    -- changes never award kills, especially when a Hunter feigns.
    local key="G:"..targetGUID
    local last=gt.recentKillEvents[key]
    if last and GetTime()-last<6 then return end
    gt:ConfirmHunterRealDeath(targetGUID,name)
    gt:RecordKill(name,targetGUID,mine)
    if gt.recentKillEvents[key]==last then return end
    -- Reuse the complete RunBack death-time capture and physics engine.
    -- Synthetic flags describe the verified group/player identities, not a
    -- synthesized combat-log death or damage attribution.
    if A.db then A:CombatEvent(GetTime(),"PARTY_KILL",false,attackerGUID,nil,0x101,nil,targetGUID,name,0x540,nil) end
end
function F.RecordLoss(name,guid)
    if not IsPlayer(guid) or type(name)~="string" then return end
    if lossAt>0 and GetTime()-lossAt<6 then return end
    lossAt=GetTime()
    local data=VoidMarkPerCharDB and VoidMarkPerCharDB.PlayerData
    if not data then return end
    if not data[name] then VoidMark:AddPlayerData(name,nil,nil,nil,nil,nil,true,false,nil) end
    local record=data[name]
    if not record then return end
    record.guid=guid; record.loses=(tonumber(record.loses) or 0)+1
    if VoidMarkStats then VoidMarkStats.newevents=true end
    if VoidMark.RefreshCurrentList then VoidMark:RefreshCurrentList() end
end
local function ObserveSpell(unit,id,event)
    id=F.Readable(id)
    if type(id)~="number" then return end
    CacheUnit(unit)
    local guid=F.Safe(UnitGUID,unit)
    local identity=guid and identities[guid]
    if id==5384 and identity and identity.player and identity.hostile then
        TaliaaGankTracker:HandleHunterFeign(guid,identity.name)
    end
    if identity and identity.player and identity.hostile and VoidMarkEnemyMoves then
        VoidMarkEnemyMoves:ObserveSpell(guid,identity.name,identity.class,id,event)
    end
end
local function ReadAuras(unit)
    local guid=F.Safe(UnitGUID,unit)
    if type(guid)~="string" then return end
    CacheUnit(unit)
    local current={}
    local sap
    for _,filter in ipairs({"HELPFUL","HARMFUL"}) do
        for index=1,40 do
            local name,_,_,_,duration,expiry,source,_,_,id=F.API.UnitAura(unit,index,filter)
            if not name then break end
            if type(id)=="number" then
                current[id]={expiration=expiry,source=source,duration=duration}
                if unit=="player" and (id==6770 or id==2070 or id==11297) then sap=source or "unknown" end
            end
        end
    end
    local prior=auras[guid] or {}
    for id,info in pairs(current) do
        if not prior[id] then ObserveSpell(unit,id,"SPELL_AURA_APPLIED")
        elseif type(info.expiration)=="number" and info.expiration~=prior[id].expiration then ObserveSpell(unit,id,"SPELL_AURA_REFRESH") end
    end
    for id in pairs(prior) do if not current[id] then ObserveSpell(unit,id,"SPELL_AURA_REMOVED") end end
    auras[guid]=current
    if sap and not F.Sapped then
        F.Sapped=true
        if TaliaaGankTracker.HandleSapAlert then TaliaaGankTracker:HandleSapAlert(F.FullName(sap)) end
    elseif unit=="player" and not sap then F.Sapped=false end
end
local function FriendSnapshot(announce)
    if not C_FriendList or not C_FriendList.GetNumFriends or not C_FriendList.GetFriendInfoByIndex then return end
    local count=F.Safe(C_FriendList.GetNumFriends) or 0
    local nextFriends={}
    for i=1,count do
        local info=F.Safe(C_FriendList.GetFriendInfoByIndex,i)
        if type(info)=="table" then
            local name=F.Readable(info.name); local online=F.Readable(info.connected)
            if type(name)=="string" and type(online)=="boolean" then
                nextFriends[name]=online
                if announce and friends[name]~=nil and friends[name]~=online and VoidMarkDB and VoidMarkDB.VoidMarkFriendAlerts then
                    local text=F.DisplayName(name)..(online and " logged in." or " logged out.")
                    F.AddInternalAlert(text)

                end
            end
        end
    end
    friends=nextFriends
end
function F.StartEvents()
    if F.eventsStarted then return end
    F.eventsStarted=true
    for _,event in ipairs({"NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","UNIT_AURA","UNIT_SPELLCAST_SUCCEEDED","FRIENDLIST_UPDATE","GROUP_ROSTER_UPDATE","PLAYER_ENTERING_WORLD"}) do F.RegisterEvent(frame,event) end
    FriendSnapshot(false)
end
function F.StopEvents()
    frame:UnregisterAllEvents(); F.eventsStarted=false
end
frame:SetScript("OnEvent",function(_,event,unit,castGUID,id)
    if event=="UNIT_SPELLCAST_SUCCEEDED" then ObserveSpell(unit,id,"SPELL_CAST_SUCCESS")
    elseif event=="UNIT_AURA" then ReadAuras(unit)
    elseif event=="NAME_PLATE_UNIT_ADDED" then CacheUnit(unit); ReadAuras(unit)
    elseif event=="NAME_PLATE_UNIT_REMOVED" then
        for guid,info in pairs(identities) do if info.unit==unit then info.unit=nil end end
    elseif event=="PLAYER_TARGET_CHANGED" then CacheUnit("target"); ReadAuras("target"); ReadAuras("player")
    elseif event=="UPDATE_MOUSEOVER_UNIT" then CacheUnit("mouseover"); ReadAuras("mouseover")
    elseif event=="FRIENDLIST_UPDATE" then FriendSnapshot(true)
    elseif event=="GROUP_ROSTER_UPDATE" then A:RefreshGroup()
    elseif event=="PLAYER_ENTERING_WORLD" then CacheUnit("target"); ReadAuras("player"); FriendSnapshot(false); F.ProbeCombatLog() end
    if (event=="PLAYER_TARGET_CHANGED" or unit=="target") and F.Safe(UnitIsPlayer,"target")==true then
        -- Only the target's actual pet token proves ownership and type.
        local _,class=F.Safe(UnitClass,"target")
        if class=="HUNTER" then
            CacheUnit("targetpet")
            local pet=F.Safe(UnitGUID,"targetpet")
            if pet and identities[pet] then identities[pet].hunterPet=true end
        end
    end
end)
local cleanup=C_Timer.NewTicker(30,function()
    local now=GetTime()
    for guid,info in pairs(identities) do
        if now-info.at>300 then identities[guid]=nil; auras[guid]=nil end
    end
    for guid,at in pairs(F.LastSeen or {}) do
        if now-at>600 then
            local name=F.GUIDToName[guid]
            F.GUIDToName[guid]=nil; F.LastSeen[guid]=nil
            if name and F.NameToGUID[name]==guid then F.NameToGUID[name]=nil end
        end
    end
end)
if VoidMark.options and VoidMark.options.args.General then
    VoidMark.options.args.General.args.VoidMarkFriendAlerts={
        type="toggle",name="Friend login/logout alerts",order=99,
        desc="Show standard friend login/logout changes in VoidMark's internal alerts.",
        get=function() return VoidMarkDB and VoidMarkDB.VoidMarkFriendAlerts==true end,
        set=function(_,value) VoidMarkDB.VoidMarkFriendAlerts=value and true or false end,
    }
end

function F.AddInternalAlert(text)
    if not VoidMarkDB then return end
    VoidMarkDB.VoidMarkInternalAlerts=VoidMarkDB.VoidMarkInternalAlerts or {}
    local history=VoidMarkDB.VoidMarkInternalAlerts
    history[#history+1]={t=time(),text=text}
    if #history>200 then table.remove(history,1) end
    local parent=VoidMark.MainWindow
    if not parent then return end
    if not F.AlertFrame then
        local bar=CreateFrame("Frame",nil,parent,"BackdropTemplate")
        bar:SetPoint("TOPLEFT",parent,"BOTTOMLEFT",0,-2)
        bar:SetPoint("TOPRIGHT",parent,"BOTTOMRIGHT",0,-2)
        bar:SetHeight(22)
        bar:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        bar:SetBackdropColor(.04,.01,.08,.95)
        bar.Text=bar:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        bar.Text:SetPoint("LEFT",6,0); bar.Text:SetPoint("RIGHT",-6,0)
        F.AlertFrame=bar
    end
    F.AlertFrame.Text:SetText(text); F.AlertFrame:Show()
    F.lastAlert=GetTime()
    local at=F.lastAlert
    C_Timer.After(8,function() if F.lastAlert==at then F.AlertFrame:Hide() end end)
end
function F.ShowAlertHistory()
    local history=VoidMarkDB and VoidMarkDB.VoidMarkInternalAlerts or {}
    if not F.HistoryFrame then
        local f=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
        f:SetSize(460,380);f:SetPoint("CENTER");f:SetClampedToScreen(true)
        f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
        f:SetBackdropColor(.02,.01,.04,.98)
        local close=CreateFrame("Button",nil,f,"UIPanelCloseButton");close:SetPoint("TOPRIGHT");close:SetScript("OnClick",function() f:Hide() end)
        f.Text=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        f.Text:SetPoint("TOPLEFT",12,-12);f.Text:SetPoint("BOTTOMRIGHT",-12,12);f.Text:SetJustifyH("LEFT");f.Text:SetJustifyV("TOP")
        F.HistoryFrame=f
    end
    local lines={"|cffb366ffVoidMark Alerts|r"}
    for i=#history,math.max(1,#history-19),-1 do
        local entry=history[i]
        lines[#lines+1]=date("%m/%d %H:%M",entry.t).."  "..entry.text
    end
    F.HistoryFrame.Text:SetText(table.concat(lines,"\n"));F.HistoryFrame:Show()
end
VoidMark.options.args.General.args.VoidMarkAlertHistory={type="execute",name="Internal alert history",order=100,func=F.ShowAlertHistory}
