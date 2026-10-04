local VMAPI = VoidMarkForever.API
local addon, A = ...
A.version, A.schema, A.timingRevision = "1.3.9-voidmark", 1, 2
A.active, A.units, A.seen, A.involved = {}, {}, {}, {}
A.metrics = { deaths=0, ignored=0, jobs=0, slices=0 }
A.defaults = { alpha=0.9, scale=1, locked=false, hidden=true, rows=8, retention=900, linger=60, assist=30, debug=false, routes=false }
function A:Print(s) DEFAULT_CHAT_FRAME:AddMessage("|cffb45cffVoidMark RunBack:|r " .. tostring(s)) end
function A:Safe(fn, ...) return VoidMarkForever.Safe(fn, ...) end
function A:Finite(n) n=VoidMarkForever.Readable(n); return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge end
function A:Distance(a,b)
    if not a or not b or a.map~=b.map or not self:Finite(a.x) or not self:Finite(b.x) or not self:Finite(a.y) or not self:Finite(b.y) then return nil end
    return ((a.x-b.x)^2+(a.y-b.y)^2)^0.5
end
function A:Now() return GetTime() end
function A:Epoch() return GetServerTime and GetServerTime() or time() end
function A:InitDB()
    if type(TaliaaRunBackDB)~="table" then TaliaaRunBackDB={} end
    if type(TaliaaRunBackCharDB)~="table" then TaliaaRunBackCharDB={} end
    local db, ch=TaliaaRunBackDB,TaliaaRunBackCharDB
    if (db.schema or 0)>self.schema or (ch.schema or 0)>self.schema then
        self.disabled=true; self:Print("Saved data is from a newer version; disabled to preserve it."); return
    end
    -- Schema zero -> one: new namespaces only, no destructive replacement.
    db.schema=self.schema; ch.schema=self.schema
    db.settings=type(db.settings)=="table" and db.settings or {}
    db.diagnostics=type(db.diagnostics)=="table" and db.diagnostics or {}
    db.calibration=type(db.calibration)=="table" and db.calibration or {}
    db.calibration.routes=type(db.calibration.routes)=="table" and db.calibration.routes or {}
    ch.timers=type(ch.timers)=="table" and ch.timers or {}
    self.db,self.char=db,ch
    for k,v in pairs(self.defaults) do
        if type(db.settings[k])~=type(v) or (type(v)=="number" and not self:Finite(db.settings[k])) then db.settings[k]=v end
    end
    db.settings.alpha=math.max(.15,math.min(1,db.settings.alpha))
    db.settings.scale=math.max(.6,math.min(2,db.settings.scale))
    db.settings.rows=math.max(1,math.min(20,math.floor(db.settings.rows)))
    db.settings.retention=math.max(60,math.min(86400,db.settings.retention))
    db.settings.assist=math.max(0,math.min(60,db.settings.assist))
end
function A:IsOutdoor()
    local inside=self:Safe(VMAPI.IsInInstance)
    if inside then return false end
    local _,_,_,map=self:Safe(VMAPI.UnitPosition,"player")
    if map~=nil then return map==0 or map==1 end
    local ui=self:Safe(C_Map and C_Map.GetBestMapForUnit,"player")
    return ui and self.Data.maps[ui]~=nil
end
function A:Save()
    if not self.char then return end
    local saved={}
    for guid,r in pairs(self.active) do
        local c={}; for k,v in pairs(r) do if k~="routeJob" then c[k]=v end end
        -- Preserve both pre-ready countdown time and post-ready linger time.
        -- `remaining` stays for backwards compatibility with older builds.
        c.readyRemaining=r.readyAt-self:Now()
        c.remaining=math.max(0,c.readyRemaining)
        c.routeRemaining=r.routeAt and (r.routeAt-self:Now()) or nil
        c.savedAt=self:Epoch(); c.readyAt=nil; c.routeAt=nil
        c.deathObservedAt=nil; c.rezObservedAt=nil; c.routeRequested=nil
        saved[guid]=c
    end
    self.char.timers=saved
end
A.events=CreateFrame("Frame")
VoidMarkForever.RegisterEvent(A.events,"ADDON_LOADED")
A.events:SetScript("OnEvent",function(_,event,...)
    if event=="ADDON_LOADED" then
        if (...)~=addon then return end
        A:InitDB(); if A.disabled then return end
        A:BuildAreaIndex(); A:RestoreTimers(); A:InstallCommands()
        for _,e in ipairs({"PLAYER_LOGIN","PLAYER_LOGOUT","PLAYER_ENTERING_WORLD","ZONE_CHANGED","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED_INDOORS","COMBAT_LOG_EVENT_UNFILTERED","PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","GROUP_ROSTER_UPDATE","PLAYER_DEAD","PLAYER_UNGHOST","PLAYER_ALIVE","CORPSE_IN_RANGE","SPELLS_CHANGED"}) do VoidMarkForever.RegisterEvent(A.events,e) end
        A.events:UnregisterEvent("ADDON_LOADED")
    elseif A.disabled or not A.db then return
    elseif event=="COMBAT_LOG_EVENT_UNFILTERED" then A:CombatEvent(VMAPI.CombatLogGetCurrentEventInfo())
    elseif event=="PLAYER_LOGOUT" then A:Save()
    elseif event=="PLAYER_TARGET_CHANGED" then A:Observe("target")
    elseif event=="UPDATE_MOUSEOVER_UNIT" then A:Observe("mouseover")
    elseif event=="NAME_PLATE_UNIT_ADDED" then A:Observe((...))
    elseif event=="NAME_PLATE_UNIT_REMOVED" then A:ForgetUnit((...))
    elseif event=="GROUP_ROSTER_UPDATE" then A:RefreshGroup()
    elseif event=="SPELLS_CHANGED" then A.rangeSpells=nil
    elseif event=="PLAYER_DEAD" or event=="PLAYER_UNGHOST" or event=="PLAYER_ALIVE" or event=="CORPSE_IN_RANGE" then
        if A.CalibrationEvent then A:CalibrationEvent(event) end
    else
        A.context=A:PlayerContext(); A:RefreshGroup()
        A:RefreshLiveGraveyards(A.context and A.context.uiMap)
        if event=="PLAYER_LOGIN" then
            local version,_,_,interface=GetBuildInfo()
            if interface~=16001 then A:Print("Client interface: "..tostring(interface)..".") end
        end
    end
end)
