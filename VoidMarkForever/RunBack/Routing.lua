local VMAPI = VoidMarkForever.API
local _, A = ...

A.routeQueue={}
A.routeCache={}
A.routeCacheOrder={}
A.localConnectorCache={}
A.localConnectorOrder={}
A.routeRootCache={}

local sqrt, floor, max, min=math.sqrt,math.floor,math.max,math.min
local SHORTCUT_RADIUS=75
local SHORTCUT_LIMIT=8
local SHORTCUT_CACHE_LIMIT=4096
local ROUTE_STRETCH_REJECT=2.25
local ROUTE_EXCESS_REJECT=250

-- First intersection of a directed network segment with the 40 yd reclaim disk.
local function entryDistance(n,m,goal)
    local dx,dy=m[1]-n[1],m[2]-n[2]
    local ox,oy=n[1]-goal.x,n[2]-goal.y
    local c=ox*ox+oy*oy-1600
    if c<=0 then return 0 end
    local a=dx*dx+dy*dy
    if a==0 then return nil end
    local b=2*(ox*dx+oy*dy)
    local disc=b*b-4*a*c
    if disc<0 then return nil end
    local t=(-b-sqrt(disc))/(2*a)
    if t>=0 and t<=1 then return t*sqrt(a) end
end

function A:GhostSpeed(race,faction)
    if race=="NightElf" then return 10.5,"Night Elf Wisp: 7 x 1.50" end
    if not race or race=="Unknown" then
        if faction~="Horde" then return 10.5,"Unknown race: fastest plausible Wisp" end
    end
    return 8.75,"Normal ghost: 7 x 1.25"
end

function A:FloorFor(p,resolution,race,faction)
    local speed,speedReason=self:GhostSpeed(race,faction)
    local r={seconds=0,distance=0,speed=speed,speedReason=speedReason,radius=40,delay=0,
        confidence="UNKNOWN",routeStatus="No route calculated",adjustment="No reaction/release padding"}
    if not p or not self:Finite(p.uncertainty) or p.uncertainty<0 then
        r.reason="Enemy location has no defensible distance bound; immediate warning"
        r.distance=nil
        return r
    end
    local closest,dist
    for _,g in ipairs(resolution.candidates) do
        local d=self:Distance(p,g)
        if d and (not dist or d<dist) then dist=d; closest=g end
    end
    if not closest then
        r.reason="No usable local graveyard data; immediate warning"
        r.distance=nil
        return r
    end
    r.floorGY=closest.id
    r.distance=max(0,dist-r.radius-p.uncertainty)
    local rawSeconds=r.distance/speed
    -- The geometric floor is already intentionally optimistic: we use the
    -- nearest eligible graveyard, subtract location uncertainty and the 40 yd
    -- reclaim radius, and use the fastest plausible ghost speed.  Do not apply
    -- an additional flat time subtraction here; the previous 35-second margin
    -- was compensating for bad graveyard assignment and made short routes
    -- collapse to near-zero warnings.
    r.seconds=max(0,rawSeconds)
    r.rawSeconds=rawSeconds
    r.safetySeconds=0
    r.confidence="LOW / LOWER BOUND"
    r.reason="Optimistic geometric lower bound; route estimate is diagnostic and never delays this warning"
    r.adjustment=string.format("Subtract %.1f yd location uncertainty and 40 yd reclaim radius; no extra flat time margin",p.uncertainty)
    return r
end

local function push(h,id,g,f)
    local v={id=id,g=g,f=f}
    local i=#h+1
    while i>1 do
        local p=floor(i/2)
        if h[p].f<=f then break end
        h[i]=h[p]
        i=p
    end
    h[i]=v
end

local function pop(h)
    local first=h[1]
    local last=table.remove(h)
    if #h>0 then
        local i=1
        while i*2<=#h do
            local c=i*2
            if c+1<=#h and h[c+1].f<h[c].f then c=c+1 end
            if h[c].f>=last.f then break end
            h[i]=h[c]
            i=c
        end
        h[i]=last
    end
    return first
end

function A:EnsureRouteData()
    if self.routeDataLoaded then return true end
    if self.LoadRouteData then return self:LoadRouteData() end
    return next(self.Data.nodes or {})~=nil
end

function A:NearbyNodes(p,radius)
    local result={}
    if not p or not self:Finite(p.x) or not self:Finite(p.y) or not self:EnsureRouteData() then return result end
    local bx,by=floor(p.x/250),floor(p.y/250)
    for ix=bx-1,bx+1 do
        for iy=by-1,by+1 do
            for _,id in ipairs(self.Data.buckets[p.map..":"..ix..":"..iy] or {}) do
                local n=self.Data.nodes[id]
                local d=sqrt((p.x-n[1])^2+(p.y-n[2])^2)
                if d<=radius then result[#result+1]={id=id,d=d} end
            end
        end
    end
    table.sort(result,function(a,b) return a.d<b.d end)
    while #result>3 do table.remove(result) end
    return result
end

-- Return the top-level outdoor area/zone containing an area.  Local shortcut
-- connectors never jump between different zone roots, which prevents nearby
-- points on opposite sides of a zone boundary from being stitched together.
function A:RouteRoot(area)
    if not area then return nil end
    if self.routeRootCache[area] then return self.routeRootCache[area] end
    local original=area
    local current=area
    local seen={}
    while current and current~=0 and not seen[current] do
        seen[current]=true
        local row=self.Data.areas[current]
        local parent=row and row[1] or 0
        if not parent or parent==0 then break end
        current=parent
    end
    self.routeRootCache[original]=current or original
    return self.routeRootCache[original]
end

-- Sku's public graph is useful but sparse in places.  The old implementation
-- could therefore take a huge road-shaped detour between two waypoint chains
-- that are only a few yards apart.  Add very short local connectors between
-- nearby waypoint nodes in the SAME zone root.  These are deliberately capped
-- at 75 yd and are still treated as an approximation, never as proof that a
-- longer timer is safe.
function A:LocalConnectors(id)
    local cached=self.localConnectorCache[id]
    if cached then return cached end
    local n=self.Data.nodes[id]
    if not n then return {} end

    local out={}
    local bx,by=floor(n[1]/250),floor(n[2]/250)
    local root=self:RouteRoot(n[4])
    for ix=bx-1,bx+1 do
        for iy=by-1,by+1 do
            for _,other in ipairs(self.Data.buckets[n[3]..":"..ix..":"..iy] or {}) do
                if other~=id then
                    local m=self.Data.nodes[other]
                    if m and m[3]==n[3] and self:RouteRoot(m[4])==root then
                        local d=sqrt((m[1]-n[1])^2+(m[2]-n[2])^2)
                        if d>0 and d<=SHORTCUT_RADIUS then
                            out[#out+1]={id=other,d=d}
                        end
                    end
                end
            end
        end
    end
    table.sort(out,function(a,b)
        if a.d==b.d then return a.id<b.id end
        return a.d<b.d
    end)
    while #out>SHORTCUT_LIMIT do table.remove(out) end

    self.localConnectorCache[id]=out
    self.localConnectorOrder[#self.localConnectorOrder+1]=id
    if #self.localConnectorOrder>SHORTCUT_CACHE_LIMIT then
        local old=table.remove(self.localConnectorOrder,1)
        self.localConnectorCache[old]=nil
    end
    return out
end

local function directFloor(A,start,goal)
    local d=A:Distance(start,goal)
    if not d then return nil end
    local uncertainty=A:Finite(goal.uncertainty) and max(0,goal.uncertainty) or 0
    return max(0,d-40-uncertainty)
end

-- Convert the raw waypoint path into the same early-warning geometry used by
-- the timer (40 yd reclaim disk + corpse-location uncertainty), then reject
-- obviously bad graph detours instead of displaying a nonsense route value.
function A:DeliverRoute(raw,start,goal,callback,source)
    if not raw then
        callback(nil,source or "No route")
        return
    end
    local uncertainty=self:Finite(goal.uncertainty) and max(0,goal.uncertainty) or 0
    local adjusted=max(0,raw-uncertainty)
    local floorDistance=directFloor(self,start,goal)
    local stretch=(floorDistance and floorDistance>1) and adjusted/floorDistance or 1

    if floorDistance and adjusted-floorDistance>ROUTE_EXCESS_REJECT and stretch>ROUTE_STRETCH_REJECT then
        callback(nil,string.format("Rejected implausible waypoint detour (%.0f yd, %.2fx geometric floor); coverage incomplete",adjusted,stretch))
        return
    end

    callback(adjusted,string.format("Hybrid waypoint approximation; <=%d yd local connectors; %.2fx geometric floor; diagnostic only",
        SHORTCUT_RADIUS,stretch))
end

-- A* route diagnostic.  It is intentionally NOT allowed to postpone the
-- earliest-return warning.  A waypoint route is an upper-bound/approximation,
-- not proof that a shorter traversable route does not exist.
function A:RequestRoute(start,goal,callback,owner)
    if not start or not goal or start.map~=goal.map then callback(nil,"Missing or mismatched endpoints"); return end
    if #self.routeQueue>=64 then callback(nil,"Route queue full; try again later"); return end
    local a,b=self:NearbyNodes(start,80),self:NearbyNodes(goal,80)
    if #a==0 or #b==0 then
        callback(nil,"Network gap: no waypoint node within 80 yd of both endpoints")
        return
    end

    local key=start.map..":"..string.format("%.3f,%.3f:%.3f,%.3f",start.x,start.y,goal.x,goal.y)
    if self.routeCache[key] then
        self:DeliverRoute(self.routeCache[key],start,goal,callback,"Cached route")
        return
    end

    local job={heap={},dist={},closed={},ends={},goal=goal,start=start,callback=callback,key=key,expanded=0,owner=owner}
    for _,v in ipairs(b) do job.ends[v.id]=max(0,v.d-40) end

    local function heuristic(id)
        local n=A.Data.nodes[id]
        return max(0,sqrt((n[1]-goal.x)^2+(n[2]-goal.y)^2)-40)
    end
    job.heuristic=heuristic

    for _,v in ipairs(a) do
        job.dist[v.id]=v.d
        push(job.heap,v.id,v.d,v.d+heuristic(v.id))
    end

    self.routeQueue[#self.routeQueue+1]=job
    self.metrics.jobs=self.metrics.jobs+1
    self:ScheduleRouteSlice()
end

function A:CancelRoutesFor(owner)
    for i=#self.routeQueue,1,-1 do
        if self.routeQueue[i].owner==owner then table.remove(self.routeQueue,i) end
    end
    if owner then owner.routeRequested=nil end
end

function A:CancelAllRoutes()
    for _,job in ipairs(self.routeQueue) do
        if job.owner then job.owner.routeRequested=nil end
    end
    self.routeQueue={}
end

function A:ScheduleRouteSlice()
    if self.routeScheduled or #self.routeQueue==0 then return end
    self.routeScheduled=true
    C_Timer.After(.02,function()
        A.routeScheduled=false
        A:RouteSlice()
    end)
end

function A:RouteSlice()
    -- Reject stale owners before doing any graph expansion.
    while self.routeQueue[1] and self.routeQueue[1].owner do
        local owner=self.routeQueue[1].owner
        if (owner.guid and self.active[owner.guid]==owner) or self.calibrationSession==owner then break end
        table.remove(self.routeQueue,1)
    end
    local j=self.routeQueue[1]
    if not j then return end
    self.metrics.slices=self.metrics.slices+1
    local started=debugprofilestop and debugprofilestop() or 0
    local done,status,result=false,nil,nil

    for _=1,64 do
        if #j.heap==0 then
            done=true
            result=j.best
            status=result and "Hybrid waypoint approximation" or "Network disconnected"
            break
        end

        local v=pop(j.heap)
        if j.best and v.f>=j.best then
            done=true
            result=j.best
            status="Hybrid waypoint approximation"
            break
        end

        if not j.closed[v.id] and v.g==j.dist[v.id] then
            j.closed[v.id]=true
            j.expanded=j.expanded+1

            local tail=j.ends[v.id]
            if tail then j.best=min(j.best or math.huge,v.g+tail) end

            local n=self.Data.nodes[v.id]
            local neighborCost={}

            -- Keep all sourced graph links.
            for _,id in ipairs(n[5]) do
                local m=self.Data.nodes[id]
                if m and m[3]==n[3] then
                    local d=sqrt((m[1]-n[1])^2+(m[2]-n[2])^2)
                    if d>0 then neighborCost[id]=d end
                end
            end

            -- Add only very short same-zone-root connectors to bridge sparse
            -- waypoint chains.  If a sourced edge already exists, keep the
            -- shortest equivalent Euclidean cost.
            for _,link in ipairs(self:LocalConnectors(v.id)) do
                local old=neighborCost[link.id]
                if not old or link.d<old then neighborCost[link.id]=link.d end
            end

            for id,edgeCost in pairs(neighborCost) do
                if not j.closed[id] then
                    local m=self.Data.nodes[id]
                    local entry=entryDistance(n,m,j.goal)
                    if entry then j.best=min(j.best or math.huge,v.g+entry) end
                    local cost=v.g+edgeCost
                    if not j.dist[id] or cost<j.dist[id] then
                        j.dist[id]=cost
                        push(j.heap,id,cost,cost+j.heuristic(id))
                    end
                end
            end
        end

        if j.expanded>=60000 then
            done=true
            status="Search limit reached; no usable route estimate"
            break
        end
        if debugprofilestop and debugprofilestop()-started>=1 then break end
    end

    if done then
        table.remove(self.routeQueue,1)
        if result then
            self.routeCache[j.key]=result
            self.routeCacheOrder[#self.routeCacheOrder+1]=j.key
            if #self.routeCacheOrder>64 then
                self.routeCache[table.remove(self.routeCacheOrder,1)]=nil
            end
            self:DeliverRoute(result,j.start,j.goal,j.callback,status)
        else
            j.callback(nil,status)
        end
    end
    self:ScheduleRouteSlice()
end
