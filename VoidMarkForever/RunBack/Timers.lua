local VMAPI = VoidMarkForever.API
local _, A = ...

function A:CreateTimer(death)
    if not self.db or not self:IsOutdoor() then return end
    local p=death.position
    local ctx=death.context or {}
    local resolution=self:ResolveGraveyard(p,ctx.area,death.faction,death.exactArea)
    local calc=self:FloorFor(p,resolution,death.race,death.faction)
    if death.latency and death.latency>0 then
        calc.adjustment=calc.adjustment..string.format("; warn %.3f s earlier for measured world RTT",death.latency)
    end

    local predicted=resolution.predicted
    local warning=calc.floorGY and self.Data.graveyards[calc.floorGY] or nil
    local r={
        guid=death.guid,name=death.name or "Unknown",level=death.level,class=death.class,race=death.race,faction=death.faction or "Unknown",
        diedAt=death.epoch or self:Epoch(),readyAt=(death.at or self:Now())+calc.seconds,
        deathObservedAt=death.observedAt or self:Now(),timingRevision=self.timingRevision,
        position=p,uiMap=ctx.uiMap,area=ctx.area,zone=ctx.zone,subzone=ctx.subzone,zoneName=ctx.zoneName,
        graveyard=predicted and predicted.id,graveyardName=predicted and predicted.name or "Unknown graveyard",
        warningGraveyard=warning and warning.id,warningGraveyardName=warning and warning.name or nil,
        selection=resolution.reason,assignmentSource=resolution.source,assignmentArea=resolution.assignmentArea,assignmentAreas=resolution.assignmentAreas,
        candidateScope=resolution.candidateScope,exactArea=death.exactArea,calc=calc,test=death.test,routeStatus="Not requested"
    }
    local previous=self.active[r.guid]
    if previous then
        self:CancelRoutesFor(previous)
        self.active[r.guid]=nil
        if self.OnVoidMarkTimerRemoved then self:OnVoidMarkTimerRemoved(previous,"replaced") end
    end
    self.active[r.guid]=r
    self.metrics.deaths=self.metrics.deaths+1
    if self.OnVoidMarkTimerCreated then self:OnVoidMarkTimerCreated(r) end

    -- The integrated row displays only the geometric countdown. Route work is
    -- requested explicitly by diagnostics, never on the ordinary kill path.

    self:PruneTimers()
    self:RenderRows()
    self:ArmTimer()
    self:Save()
end

function A:RequestTimerRoute(r,callback)
    if not r or self.active[r.guid]~=r then return end
    if r.routeRequested then return end
    local p=r.position
    local gy=self.Data.graveyards[r.warningGraveyard or r.graveyard]
    if not p or not self:Finite(p.uncertainty) or not gy then
        r.routeStatus="Cannot route an unlocated corpse or unknown graveyard"
        if callback then callback(r) end
        return
    end
    r.routeRequested=true; r.routeStatus="Queued"
    self:RequestRoute(gy,p,function(distance,status)
        if A.active[r.guid]~=r then return end
        r.routeRequested=nil; r.networkDistance=distance; r.routeStatus=status
        if distance and A:Finite(r.calc.speed) and r.calc.speed>0 then
            r.baseRouteSeconds=math.max(0,distance)/r.calc.speed
            r.routeSeconds,r.calibrationNote=A:ApplyRouteCalibration(r.baseRouteSeconds,r.calc.seconds,r.zone or r.area,gy.id,r.faction)
            r.routeAt=r.readyAt-r.calc.seconds+r.routeSeconds
        else r.routeSeconds=nil; r.routeAt=nil end
        A:Save()
        if callback then callback(r) end
    end,r)
end

function A:PruneTimers()
    local nowEpoch=self:Epoch(); local now=self:Now(); local list={}; local changed=false
    local linger=60 -- VoidMark integrated requirement: hold dead rows 60s after RETURN POSSIBLE
    for guid,r in pairs(self.active) do
        -- Keep the enemy visible after the earliest-return floor is reached.
        -- This is display-only; it never changes the calculated floor.
        if not self:Finite(r.readyAt) or not self:Finite(r.diedAt) or now>=r.readyAt+linger or nowEpoch-r.diedAt>self.db.settings.retention then
            self.active[guid]=nil
            if self.CancelRoutesFor then self:CancelRoutesFor(r) end
            if self.OnVoidMarkTimerRemoved then self:OnVoidMarkTimerRemoved(r, "expired") end
            changed=true
        else
            list[#list+1]=r
        end
    end
    table.sort(list,function(a,b) return a.diedAt>b.diedAt end)
    for i=65,#list do
        local r=list[i]
        self.active[r.guid]=nil
        if self.CancelRoutesFor then self:CancelRoutesFor(r) end
        if self.OnVoidMarkTimerRemoved then self:OnVoidMarkTimerRemoved(r, "capacity") end
        changed=true
    end
    if changed and self.char then self:Save() end
end

function A:RestoreTimers()
    local nowEpoch=self:Epoch(); local now=self:Now()
    for guid,r in pairs(self.char.timers) do
        if type(guid)=="string" and type(r)=="table" and self:Finite(r.diedAt) and type(r.calc)=="table" and self:Finite(r.calc.seconds) and r.calc.seconds>=0 and type(r.name)=="string" and self:Finite(r.savedAt) then
            local elapsed=nowEpoch-r.savedAt
            local savedRemaining=r.readyRemaining~=nil and r.readyRemaining or r.remaining
            if self:Finite(savedRemaining) and elapsed>=0 and r.diedAt<=nowEpoch and nowEpoch-r.diedAt<self.db.settings.retention then
                r.guid=guid
                -- Do not clamp at zero: a negative value means the row is already
                -- in its post-RETURN-POSSIBLE linger window.
                r.readyAt=now+savedRemaining-elapsed
                r.deathObservedAt=now-(nowEpoch-r.diedAt)
                r.routeRequested=nil; r.routeAt=nil
                if r.routeStatus=="Queued" then r.routeStatus="Not requested" end
                local p=r.position
                if p and (type(p)~="table" or not self:Finite(p.x) or not self:Finite(p.y) or (p.map~=0 and p.map~=1)
                    or (p.uncertainty~=nil and (not self:Finite(p.uncertainty) or p.uncertainty<0))) then
                    r.position=nil; r.timingRevision=nil
                end
                -- Re-evaluate older transient warnings using the corrected
                -- candidates. Old combat envelopes did not identify their
                -- source; treat those as unlocated. Never postpone a warning.
                if r.timingRevision~=self.timingRevision and self.ResolveGraveyard then
                    local deathAt=r.readyAt-r.calc.seconds
                    local p=r.position
                    if p and not r.exactArea and not p.sourceGUID and not tostring(p.source):match("^VMAPI.UnitPosition") then
                        p.uncertainty=nil
                    end
                    local res=self:ResolveGraveyard(p,r.area,r.faction,r.exactArea)
                    local calc=self:FloorFor(p,res,r.race,r.faction)
                    r.readyAt=math.min(r.readyAt,deathAt+calc.seconds)
                    -- Retain the earlier warning's elapsed-time origin.
                    calc.seconds=math.max(0,r.readyAt-deathAt)
                    r.calc=calc; r.timingRevision=self.timingRevision
                    r.warningGraveyard=calc.floorGY
                    r.warningGraveyardName=calc.floorGY and self.Data.graveyards[calc.floorGY].name
                    r.graveyard=res.predicted and res.predicted.id
                    r.graveyardName=res.predicted and res.predicted.name or "Unknown graveyard"
                    r.selection=res.reason; r.candidateScope=res.candidateScope
                    r.assignmentSource=res.source; r.assignmentArea=res.assignmentArea; r.assignmentAreas=res.assignmentAreas
                    r.routeRemaining=nil; r.routeSeconds=nil; r.routeStatus="Not requested"
                end
                if r.routeRemaining~=nil and not self:Finite(r.routeRemaining) then
                    r.routeRemaining=nil; r.routeSeconds=nil
                end
                if self:Finite(r.routeRemaining) then
                    r.routeAt=now+r.routeRemaining-elapsed
                elseif self:Finite(r.routeSeconds) and r.routeSeconds>=0 then
                    -- Older saved rows did not persist routeRemaining. Rebuild
                    -- relative to the saved earliest timer when possible.
                    r.routeAt=r.readyAt+(r.routeSeconds-r.calc.seconds)
                end
                self.active[guid]=r
                if self.OnVoidMarkTimerCreated then self:OnVoidMarkTimerCreated(r, true) end
            end
        end
    end
    self:PruneTimers(); self:RenderRows(); self:ArmTimer()
end

function A:ArmTimer()
    if self.uiTimer then self.uiTimer:Cancel(); self.uiTimer=nil end
    if not next(self.active) then return end
    -- One ticker for the whole window avoids allocating a new timer every second.
    self.uiTimer=C_Timer.NewTicker(1,function()
        A:PruneTimers()
        if A.CheckLiveTimers then A:CheckLiveTimers() end
        A:RenderRows()
        if not next(A.active) and A.uiTimer then
            A.uiTimer:Cancel(); A.uiTimer=nil
        end
    end)
end

local function clockText(seconds)
    local t=math.max(0,math.floor(seconds or 0))
    return string.format("%d:%02d",math.floor(t/60),t%60)
end

function A:RouteTimerLabel(r)
    if not r or not r.routeAt then return nil end
    local delta=r.routeAt-self:Now()
    if delta<=0 then return "NOW" end
    return clockText(delta)
end

function A:TimerLabel(r)
    local delta=r.readyAt-self:Now()
    if delta<=0 then
        local elapsed=math.floor(-delta)
        local route=self:RouteTimerLabel(r)
        if route and route~="NOW" then
            return string.format("EARLY +%d:%02d | ROUTE ~%s",math.floor(elapsed/60),elapsed%60,route)
        end
        return string.format("RETURN POSSIBLE +%d:%02d",math.floor(elapsed/60),elapsed%60)
    end
    local early=clockText(delta)
    local route=self:RouteTimerLabel(r)
    if route then return string.format("E %s | R ~%s",early,route) end
    return early
end

function A:ClearTimers()
    if self.CancelAllRoutes then self:CancelAllRoutes() end
    if self.OnVoidMarkTimerRemoved then
        for _,r in pairs(self.active) do self:OnVoidMarkTimerRemoved(r, "clear") end
    end
    self.active={}; self.char.timers={}; self:ArmTimer(); self:RenderRows()
end
