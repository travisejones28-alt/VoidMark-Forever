local VMAPI = VoidMarkForever.API
local _, A = ...
function A:DefaultEnemyFaction()
    return VMAPI.UnitFactionGroup("player")=="Horde" and "Alliance" or "Horde"
end
function A:TestDeath(arg)
    if not self:IsOutdoor() then self:Print("Tests require an outdoor Eastern Kingdoms/Kalimdor map."); return end
    local ctx=self:PlayerContext(); local p=ctx.position
    if not p then self:Print("No current position available."); return end
    self.testNumber=(self.testNumber or 0)+1
    local faction=self:DefaultEnemyFaction(); local race
    if arg=="nightelf" then race="NightElf"; faction="Alliance"
    elseif arg=="normal" then race=faction=="Alliance" and "Human" or "Orc" end
    self:CreateTimer({guid="Test-"..self.testNumber.."-"..self:Now(),name="RunBack Test "..self.testNumber,at=self:Now(),position=p,context=ctx,
        exactArea=true,faction=faction,race=race,level=60,test=true})
    self.db.settings.hidden=false; self:ApplyAppearance()
end
function A:ZoneReport()
    local c=self:PlayerContext(); local out={"Taliaa Run Back "..self.version,"UI map: "..tostring(c.uiMap),"World continent/map: "..tostring(c.map),
        "Observer area: "..tostring(c.area).." "..self:AreaName(c.area),"Zone: "..tostring(c.zone).." "..self:AreaName(c.zone),"Subzone: "..tostring(c.subzone),
        "Enemy exact subzone is not exposed by these APIs.","Parent chain:"}
    for _,id in ipairs(c.chain) do
        out[#out+1]=id.." "..self:AreaName(id)
        for _,l in ipairs(self.Data.links[id] or {}) do out[#out+1]="  GY "..l[1].." faction "..l[2] end
    end
    if self.routeDataLoaded then
        out[#out+1]="Direct-area network nodes: "..tostring(self.Data.networkCounts[c.area] or 0)
        out[#out+1]="Zone network nodes: "..tostring(self.Data.networkCounts[c.zone] or 0)
    else out[#out+1]="Waypoint tables not loaded; request /trb route to load diagnostics." end
    out[#out+1]="Route confidence: public waypoint network, incomplete; never delays warning."
    local mp=c.uiMap and self:Safe(C_Map and C_Map.GetPlayerMapPosition,c.uiMap,"player")
    local explored=mp and self:Safe(C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition,c.uiMap,mp)
    out[#out+1]="Exploration-area hints (not exact terrain area): "..(type(explored)=="table" and table.concat(explored,", ") or "unavailable")
    self:ShowReport("Current zone diagnostics",table.concat(out,"\n")); return out
end
function A:GraveyardReport(arg)
    local c=self:PlayerContext(); self:RefreshLiveGraveyards(c.uiMap)
    local faction=arg=="alliance" and "Alliance" or arg=="horde" and "Horde" or self:DefaultEnemyFaction()
    local res=self:ResolveGraveyard(c.position,c.area,faction,true)
    local out={"Predicting "..faction.." release from OBSERVER position",res.reason,"Static assignment source: "..res.source,
        "Predicted: "..(res.predicted and (res.predicted.id.." "..res.predicted.name) or "unknown"),"Faction codes: 0 both, 469 Alliance, 67 Horde","Area and parent links (including rejected faction links):"}
    for _,id in ipairs(c.chain) do
        for _,l in ipairs(self.Data.links[id] or {}) do
            local g=self.Data.graveyards[l[1]]
            out[#out+1]=string.format("Area %d | GY %d %s | faction %d | %s",id,l[1],g and g.name or "missing",l[2],self:Eligible(l[2],faction) and "eligible" or "REJECT")
        end
    end
    out[#out+1]="Live map pins (API supplies NO faction/area eligibility):"
    for _,g in ipairs(self.liveGY[c.uiMap] or {}) do
        local static=self.Data.graveyards[g.id]; local difference=static and self:Distance(static,g)
        out[#out+1]=string.format("ID %s | %s | selectable for observer: %s | static delta %s yd",tostring(g.id),tostring(g.name),tostring(g.selectable),difference and string.format("%.1f",difference) or "unknown")
    end
    if #(self.liveGY[c.uiMap] or {})==0 then out[#out+1]="No live pins returned; static data retained." end
    self:ShowReport("Graveyard diagnostics",table.concat(out,"\n")); return out
end
function A:TargetReport()
    self:Observe("target"); local id=VMAPI.UnitGUID("target")
    if not id or not VMAPI.UnitIsPlayer("target") then self:Print("Target an enemy player first."); return end
    local i=self.seen[id] or {}; local p=self:WorldPosition("target")
    self:ShowReport("Target diagnostics",table.concat({tostring(i.name),id,"Race: "..tostring(i.race),"Faction: "..tostring(i.faction),"Class: "..tostring(i.class),
        p and string.format("World %d: %.2f, %.2f",p.map,p.x,p.y) or "Enemy coordinates unavailable. No bounded corpse position can be inferred.",
        "A confirmed live target may trigger a resurrection alert; it never changes or trains the countdown."},"\n"))
end
function A:Sample()
    local c=self:PlayerContext(); local speed=self:Safe(GetUnitSpeed,"player")
    local corpse=c.uiMap and self:Safe(C_DeathInfo and C_DeathInfo.GetCorpseMapPosition,c.uiMap)
    local release=c.uiMap and self:Safe(C_DeathInfo and C_DeathInfo.GetDeathReleasePosition,c.uiMap)
    local function xy(v) if v then local x,y=self:Safe(v.GetXY,v); return {x=x,y=y} end end
    local sample={epoch=self:Epoch(),context=c,isGhost=VMAPI.UnitIsGhost("player"),speed=speed,corpse=xy(corpse),release=xy(release),faction=VMAPI.UnitFactionGroup("player"),build=select(4,GetBuildInfo())}
    table.insert(self.db.diagnostics,sample); if #self.db.diagnostics>100 then table.remove(self.db.diagnostics,1) end
    self:Print("Saved own-position/ghost diagnostic; speed "..tostring(speed).." yd/s. No enemy resurrection timing recorded.")
end


-- TomTom-style coordinate audit.  The timer itself uses world coordinates
-- (yards), while the familiar zone x/y percentages are included so a player can
-- stand at a known coordinate and verify exactly which graveyard is being used.
function A:AnalyzePosition(arg)
    local c=self:PlayerContext()
    local p=c.position
    if not p then
        self:Print("No current world position available.")
        return
    end

    local faction
    if arg=="alliance" then faction="Alliance"
    elseif arg=="horde" then faction="Horde"
    else faction=self:DefaultEnemyFaction() end

    local mapX,mapY
    if c.uiMap and C_Map and C_Map.GetPlayerMapPosition then
        local mp=self:Safe(C_Map.GetPlayerMapPosition,c.uiMap,"player")
        if mp then
            local x,y=self:Safe(mp.GetXY,mp)
            if self:Finite(x) and self:Finite(y) then mapX,mapY=x*100,y*100 end
        end
    end

    local res=self:ResolveGraveyard(p,c.area,faction,true)
    local speed,speedReason=self:GhostSpeed(nil,faction)
    local floor=self:FloorFor({x=p.x,y=p.y,z=p.z,map=p.map,uncertainty=0},res,nil,faction)
    local out={
        "Taliaa Run Back coordinate analysis",
        string.format("Faction tested: %s",faction),
        string.format("Zone: %s | Subzone: %s | UI map: %s",tostring(c.zoneName or self:AreaName(c.zone)),tostring(c.subzone or ""),tostring(c.uiMap)),
        mapX and string.format("Map coordinate: %.2f, %.2f",mapX,mapY) or "Map coordinate: unavailable",
        string.format("World position: continent %s | %.2f, %.2f%s",tostring(p.map),p.x,p.y,self:Finite(p.z) and string.format(" | z %.2f",p.z) or ""),
        string.format("Observer area: %s (%s) | zone root: %s (%s)",tostring(c.area),self:AreaName(c.area),tostring(c.zone),self:AreaName(c.zone)),
        "Assignment: "..tostring(res.reason),
        string.format("Ghost speed used: %.2f yd/s | %s",speed,tostring(speedReason)),
        "Eligible graveyards (nearest first):"
    }

    local rows={}
    for _,g in ipairs(res.candidates or {}) do
        local d=self:Distance(p,g)
        if d then
            -- Match FloorFor's horizontal geometry, including its warning GY.
            local raw=math.max(0,d-40)/speed
            local safe=math.max(0,raw-(floor.safetySeconds or 0))
            rows[#rows+1]={g=g,d=d,raw=raw,safe=safe}
        end
    end
    table.sort(rows,function(a,b)
        if a.d==b.d then return a.g.id<b.g.id end
        return a.d<b.d
    end)

    for i,r in ipairs(rows) do
        out[#out+1]=string.format("%d. %s [ID %d] | %.0f yd | raw %.0fs | warning %.0fs%s",
            i,tostring(r.g.name),r.g.id,r.d,r.raw,r.safe,
            (floor.floorGY==r.g.id) and " | SELECTED" or "")
    end
    if #rows==0 then out[#out+1]="No eligible graveyard with usable world coordinates." end

    if floor.floorGY then
        local g=self.Data.graveyards[floor.floorGY]
        out[#out+1]=string.format("Timer driver: %s | %.0f yd after reclaim/uncertainty | %.0f sec warning floor",
            g and g.name or tostring(floor.floorGY),floor.distance or 0,floor.seconds or 0)
    else
        out[#out+1]="Timer driver: none (immediate warning)."
    end
    out[#out+1]="Note: straight-line world distance is intentionally the optimistic floor; waypoint routing may be shown separately but never makes the warning later."

    self:ShowReport("Coordinate / graveyard analysis",table.concat(out,"\n"))
    return out
end


-- Calibration ---------------------------------------------------------------
-- Arms the next PLAYER_DEAD and measures the player's own immediate-release
-- corpse run.  These samples only tune the advisory R estimate; they never
-- change the EARLIEST lower-bound warning.
local function median(values)
    if #values==0 then return nil end
    table.sort(values)
    local n=#values
    if n%2==1 then return values[(n+1)/2] end
    return (values[n/2]+values[n/2+1])/2
end

function A:CalibrationKey(zone,graveyard,faction)
    return table.concat({tostring(zone or 0),tostring(graveyard or 0),tostring(faction or "Unknown")},":")
end

function A:ValidCalibrationSample(v,graveyard)
    return self:Finite(graveyard) and type(v)=="table" and v.corpseRangeConfirmed==true
        and v.actualStartGY==graveyard and self:Finite(v.actualStartGYDistance) and v.actualStartGYDistance>=0 and v.actualStartGYDistance<=80
        and self:Finite(v.actualRun) and v.actualRun>0
        and self:Finite(v.releaseDelay) and v.releaseDelay>=0 and v.releaseDelay<=20
end

function A:GetRouteCalibration(zone,graveyard,faction)
    if not self.db or not self.db.calibration then return nil end
    local bucket=self.db.calibration.routes[self:CalibrationKey(zone,graveyard,faction)]
    if type(bucket)~="table" or type(bucket.samples)~="table" or #bucket.samples==0 then return nil end
    local routeFactors,geoFactors,releaseDelays={}, {}, {}
    for _,v in ipairs(bucket.samples) do
        if self:ValidCalibrationSample(v,graveyard) then
            if self:Finite(v.routeFactor) and v.routeFactor>=0.75 and v.routeFactor<=3 then routeFactors[#routeFactors+1]=v.routeFactor end
            if self:Finite(v.geoFactor) and v.geoFactor>=0.75 and v.geoFactor<=3 then geoFactors[#geoFactors+1]=v.geoFactor end
        end
    end
    local useRoute=#routeFactors>0
    for _,v in ipairs(bucket.samples) do
        if self:ValidCalibrationSample(v,graveyard) then
            local factor
            if useRoute then factor=v.routeFactor else factor=v.geoFactor end
            if self:Finite(factor) and factor>=0.75 and factor<=3 then releaseDelays[#releaseDelays+1]=v.releaseDelay end
        end
    end
    return {
        n=useRoute and #routeFactors or #geoFactors,stored=#bucket.samples,
        routeFactor=median(routeFactors),
        geoFactor=median(geoFactors),
        releaseDelay=median(releaseDelays) or 0,
        zone=zone,graveyard=graveyard,faction=faction,
    }
end

function A:CalibrationConfidence(n)
    n=tonumber(n) or 0
    if n>=5 then return "HIGH",1.00 end
    if n>=3 then return "GOOD",0.80 end
    if n==2 then return "DEVELOPING",0.60 end
    if n==1 then return "EXPERIMENTAL",0.35 end
    return "NONE",0
end

function A:ApplyRouteCalibration(baseRouteSeconds,floorSeconds,zone,graveyard,faction)
    if not self:Finite(baseRouteSeconds) then return baseRouteSeconds,nil end
    local c=self:GetRouteCalibration(zone,graveyard,faction)
    if not c then return math.max(floorSeconds or 0,baseRouteSeconds),"uncalibrated route | confidence NONE" end

    -- Do not let one unusual corpse run fully redefine the advisory ETA.
    -- Local calibration is blended toward the baseline until enough samples
    -- exist for that exact zone/graveyard/faction bucket.
    local confidence,weight=self:CalibrationConfidence(c.n)
    local observed=c.routeFactor or c.geoFactor or 1
    local factor=1+((observed-1)*weight)
    local release=(c.releaseDelay or 0)*weight

    local seconds=baseRouteSeconds*factor+release
    seconds=math.max(floorSeconds or 0,seconds)
    return seconds,string.format("local n=%d %s | observed x%.2f | applied x%.2f | +%.1fs release",c.n,confidence,observed,factor,release)
end

function A:ArmCalibration()
    if self.calibrationSession then
        self:Print("Calibration mode is already active. /trb calibrate cancel to stop it.")
        return
    end
    self.calibrationAuto=true
    self.calibrationSession={armed=true}
    self:Print("Calibration mode ON. Each death will be measured automatically until /trb calibrate cancel. RELEASE IMMEDIATELY and run straight to resurrection range.")
end

function A:StopCalibration(reason)
    if self.calibrationSession then self:CancelRoutesFor(self.calibrationSession) end
    if self.calibrationTicker then self.calibrationTicker:Cancel(); self.calibrationTicker=nil end
    self.calibrationSession=nil
    self.calibrationAuto=nil
    if reason then self:Print(reason) end
end

function A:RearmCalibration()
    if self.calibrationSession then self:CancelRoutesFor(self.calibrationSession) end
    if self.calibrationTicker then self.calibrationTicker:Cancel(); self.calibrationTicker=nil end
    if self.calibrationAuto then
        self.calibrationSession={armed=true}
        self:Print("Calibration re-armed for the next death.")
    else
        self.calibrationSession=nil
    end
end

function A:BeginCalibrationDeath()
    local s=self.calibrationSession
    if not s or not s.armed then return end
    local ctx=self:PlayerContext(); local p=ctx and ctx.position
    if not p then self:StopCalibration("Calibration failed: no world position at death."); return end

    local faction=VMAPI.UnitFactionGroup("player") or "Unknown"
    local _,race=VMAPI.UnitRace("player")
    local exact={x=p.x,y=p.y,z=p.z,map=p.map,source=p.source,uncertainty=0}
    local res=self:ResolveGraveyard(exact,ctx.area,faction,true)
    local calc=self:FloorFor(exact,res,race,faction)
    local gy=calc.floorGY and self.Data.graveyards[calc.floorGY] or res.predicted

    s.armed=false; s.phase="dead"; s.deadAt=self:Now(); s.epoch=self:Epoch()
    s.ctx=ctx; s.corpse=exact; s.faction=faction; s.race=race; s.resolution=res; s.calc=calc
    s.graveyard=gy and gy.id; s.graveyardName=gy and gy.name or "Unknown"
    self:Print(string.format("Calibration death captured: %s | E %.1fs. Release now and run straight back.",s.graveyardName,calc.seconds or 0))

    if gy and self.db.settings.routes then
        self:RequestRoute(gy,exact,function(distance,status)
            if A.calibrationSession~=s then return end
            s.routeStatus=status
            if distance and calc.speed and calc.speed>0 then s.baseRouteSeconds=distance/calc.speed end
        end,s)
    end

    if self.calibrationTicker then self.calibrationTicker:Cancel() end
    self.calibrationTicker=C_Timer.NewTicker(.10,function() A:CalibrationTick() end)
end

function A:CalibrationTick()
    local s=self.calibrationSession
    if not s or s.armed then return end
    local now=self:Now()
    if not s.ghostAt and VMAPI.UnitIsGhost("player") then
        s.ghostAt=now
        s.ghostStart=self:WorldPosition("player")
        s.releaseDelay=now-s.deadAt
        if s.ghostStart and s.resolution and s.resolution.candidates then
            local best,bestD
            for _,g in ipairs(s.resolution.candidates) do
                local d=self:Distance(s.ghostStart,g)
                if d and (not bestD or d<bestD) then best,bestD=g,d end
            end
            s.actualStartGY=best and best.id or nil
            s.actualStartGYName=best and best.name or nil
            s.actualStartGYDistance=bestD
        end
        self:Print(string.format("Release detected +%.1fs. Running timer started.",s.releaseDelay))
    end

    -- Completion comes from the client's corpse-range event. A horizontal
    -- 40 yd poll could incorrectly finish while on another terrain height.
    if now-s.deadAt>300 then self:StopCalibration("Calibration timed out after 5 minutes.") end
end

function A:FinishCalibration()
    local s=self.calibrationSession
    if not s or not s.ghostAt or not s.reclaimAt or not s.corpseRangeConfirmed then return end
    local total=s.reclaimAt-s.deadAt
    local run=s.reclaimAt-s.ghostAt
    local geo=s.calc and s.calc.seconds or nil
    local route=s.baseRouteSeconds
    local sample={
        at=self:Epoch(),zone=s.ctx and (s.ctx.zone or s.ctx.area),graveyard=s.graveyard,graveyardName=s.graveyardName,faction=s.faction,
        map=s.corpse and s.corpse.map,x=s.corpse and s.corpse.x,y=s.corpse and s.corpse.y,
        releaseDelay=s.releaseDelay,actualTotal=total,actualRun=run,geoSeconds=geo,routeSeconds=route,
        geoFactor=(geo and geo>0) and run/geo or nil,
        routeFactor=(route and route>0) and run/route or nil,
        actualStartGY=s.actualStartGY,actualStartGYDistance=s.actualStartGYDistance,
        corpseRangeConfirmed=true,
    }
    if not self:ValidCalibrationSample(sample,s.graveyard) then
        self:Print("Calibration discarded: release timing or actual graveyard could not validate this corpse run.")
        self:RearmCalibration(); return
    end
    local key=self:CalibrationKey(sample.zone,sample.graveyard,sample.faction)
    local bucket=self.db.calibration.routes[key]
    if type(bucket)~="table" then bucket={samples={}}; self.db.calibration.routes[key]=bucket end
    bucket.samples=type(bucket.samples)=="table" and bucket.samples or {}
    bucket.samples[#bucket.samples+1]=sample
    while #bucket.samples>20 do table.remove(bucket.samples,1) end

    local gyCheck=""
    if s.actualStartGY and s.graveyard and s.actualStartGY~=s.graveyard then
        gyCheck=string.format(" WARNING: actual ghost start was nearest %s [%s], predicted %s [%s].",tostring(s.actualStartGYName),tostring(s.actualStartGY),tostring(s.graveyardName),tostring(s.graveyard))
    end
    self:Print(string.format("CALIBRATION SAVED: death->range %.1fs | release %.1fs | ghost run %.1fs | E %.1fs%s",total,s.releaseDelay or 0,run,geo or 0,gyCheck))
    if route then self:Print(string.format("Route model %.1fs | run/model x%.2f. Future R estimates for this zone/GY will use this sample.",route,sample.routeFactor or 1))
    else self:Print(string.format("No waypoint route was available; geometric run factor x%.2f saved for this zone/GY.",sample.geoFactor or 1)) end
    self:RearmCalibration()
end

function A:CalibrationEvent(event)
    local s=self.calibrationSession
    if not s then return end
    if event=="PLAYER_DEAD" and s.armed then self:BeginCalibrationDeath()
    elseif event=="CORPSE_IN_RANGE" and not s.armed and VMAPI.UnitIsGhost("player") then
        self:CalibrationTick()
        if self.calibrationSession==s and s.ghostAt then
            s.corpseRangeConfirmed=true; s.reclaimAt=self:Now(); self:FinishCalibration()
        end
    elseif event=="PLAYER_UNGHOST" and not s.armed then
        self:Print("Calibration discarded: resurrection occurred before confirmed corpse range.")
        self:RearmCalibration()
    end
end

function A:CalibrationReport()
    local out={"Taliaa Run Back calibration data"}
    local count=0
    for key,b in pairs(self.db.calibration.routes or {}) do
        if type(b)=="table" and type(b.samples)=="table" and #b.samples>0 then
            count=count+#b.samples
            local parts={}; for v in key:gmatch("[^:]+") do parts[#parts+1]=v end
            local zoneID,gyID,faction=tonumber(parts[1]),tonumber(parts[2]),parts[3]
            local c=self:GetRouteCalibration(zoneID,gyID,faction)
            local zoneName=self:AreaName(zoneID)
            local gy=self.Data.graveyards and self.Data.graveyards[gyID]
            local gyName=(gy and gy.name) or (b.samples[#b.samples] and b.samples[#b.samples].graveyardName) or tostring(gyID)
            local confidence,weight=self:CalibrationConfidence(c and c.n or 0)
            local observed=c and (c.routeFactor or c.geoFactor) or nil
            local applied=observed and (1+((observed-1)*weight)) or nil
            out[#out+1]=string.format("%s -> %s | %s | accepted n=%d / stored %d | %s | route x%s | applied x%s | geo x%s | release %.1fs",zoneName,gyName,faction,c and c.n or 0,#b.samples,confidence,c and c.routeFactor and string.format("%.2f",c.routeFactor) or "?",applied and string.format("%.2f",applied) or "?",c and c.geoFactor and string.format("%.2f",c.geoFactor) or "?",c and c.releaseDelay or 0)
        end
    end
    if count==0 then out[#out+1]="No calibration samples yet." end
    out[#out+1]="Calibration affects only R (realistic/advisory). E remains the unchanged optimistic lower bound."
    self:ShowReport("Run-back calibration",table.concat(out,"\n"))
end

function A:TimerDetails(name,route)
    local r
    if name and name~="" then
        r=VoidMark.GetRunBackRecord and VoidMark:GetRunBackRecord(name)
    else
        local guid=self:Safe(VMAPI.UnitGUID,"target")
        r=guid and self.active[guid]
        if not r then
            for _,v in pairs(self.active) do if not r or v.diedAt>r.diedAt then r=v end end
        end
    end
    if not r then self:Print("No matching active timer. Use an exact name if realms share a name."); return end
    local function show(record) A:ShowReport("Enemy runback details",table.concat(A:DetailLines(record),"\n")) end
    show(r)
    if route or self.db.settings.routes then self:RequestTimerRoute(r,show) end
end

function A:InstallCommands()
    SLASH_TALIAARUNBACK1="/trb"
    SlashCmdList.TALIAARUNBACK=function(msg)
        local cmd,arg=msg:match("^%s*(%S*)%s*(.-)%s*$"); cmd=string.lower(cmd or ""); arg=string.lower(arg or "")
        if cmd=="" or cmd=="show" then
            if VoidMark and VoidMark.MainWindow then VoidMark.MainWindow:Show() else A:Print("Runback timers appear in the VoidMark window.") end
        elseif cmd=="test" then A:TestDeath(arg)
        elseif cmd=="gy" then A:GraveyardReport(arg)
        elseif cmd=="analyze" or cmd=="analyse" then A:AnalyzePosition(arg)
        elseif cmd=="zone" then A:ZoneReport()
        elseif cmd=="target" then A:TargetReport()
        elseif cmd=="details" then A:TimerDetails(arg,false)
        elseif cmd=="route" then A:TimerDetails(arg,true)
        elseif cmd=="routes" then
            if arg=="on" then A.db.settings.routes=true elseif arg=="off" then A.db.settings.routes=false end
            A:Print("Routes for requested details/calibration: "..tostring(A.db.settings.routes)..". Ordinary kills never start route searches.")
        elseif cmd=="sample" then A:Sample()
        elseif cmd=="calibrate" then
            if arg=="cancel" then A:StopCalibration("Calibration cancelled.")
            elseif arg=="report" then A:CalibrationReport()
            elseif arg=="clear" then A.db.calibration.routes={}; A:Print("Calibration data cleared.")
            else A:ArmCalibration() end
        elseif cmd=="settings" then A:ShowSettings()
        elseif cmd=="clear" then A:ClearTimers()
        elseif cmd=="debug" then
            A.db.settings.debug=not A.db.settings.debug
            A:Print(string.format("Debug %s | deaths %d | route jobs %d | slices %d | schema %d",tostring(A.db.settings.debug),A.metrics.deaths,A.metrics.jobs,A.metrics.slices,A.schema))
            A:Print("APIs: VMAPI.UnitPosition="..tostring(type(VMAPI.UnitPosition)).."; GetGraveyardsForMap="..tostring(C_DeathInfo and type(C_DeathInfo.GetGraveyardsForMap)))
        elseif cmd=="resetpos" then
            A.char.position=nil
            if A.frame then A.frame:ClearAllPoints(); A.frame:SetPoint("CENTER",UIParent,"CENTER",0,120)
            else A:Print("Runback timers use the VoidMark window; move it with the normal VoidMark controls.") end
        else A:Print("/trb [test [normal|nightelf], details [name], route [name], routes [on|off], analyze [alliance|horde], calibrate [report|cancel|clear], target, gy [alliance|horde], zone, sample, settings, debug, clear, resetpos]") end
    end
end
