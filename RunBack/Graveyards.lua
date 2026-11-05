local VMAPI = VoidMarkForever.API
local _, A = ...
A.liveGY={}; A.linkCache={}

function A:Eligible(team,faction)
    return team==0 or not faction or faction=="Unknown" or (team==469 and faction=="Alliance") or (team==67 and faction=="Horde")
end

local function IsUsableGraveyard(g)
    if not g then return false end
    -- Classic-DB includes test/internal graveyards that are not valid player
    -- release points. Never let those drive a PvP corpse-run timer.
    local name=string.lower(tostring(g.name or ""))
    if name:find("gm client",1,true) or name:find("do not bug",1,true) or name:find("test",1,true) then
        return false
    end
    return true
end

function A:ResolveLinks(area,faction)
    local key=tostring(area)..":"..tostring(faction)
    if self.linkCache[key] then return self.linkCache[key][1],self.linkCache[key][2] end
    for _,id in ipairs(self:AreaChain(area)) do
        local out={}
        for _,link in ipairs(self.Data.links[id] or {}) do
            if self:Eligible(link[2],faction) then
                local gy=self.Data.graveyards[link[1]]
                if IsUsableGraveyard(gy) then out[#out+1]={gy=gy,team=link[2],area=id} end
            end
        end
        if #out>0 then
            self.linkCache[key]={out,id}
            return out,id
        end
    end
    return {},nil
end

function A:RefreshLiveGraveyards(ui)
    if not ui then return end
    local rows=self:Safe(C_DeathInfo and C_DeathInfo.GetGraveyardsForMap,ui)
    local out={}
    if type(rows)=="table" then
        for _,r in ipairs(rows) do
            local safe={}
            for k,v in pairs(r) do safe[k]=VoidMarkForever.Readable(v) end
            r=safe
            local c,w
            if r.position then c,w=self:Safe(C_Map and C_Map.GetWorldPosFromMapPos,ui,r.position) end
            local x,y; if w then x,y=self:Safe(w.GetXY,w) end
            out[#out+1]={id=r.graveyardID,name=r.name,map=c,x=x,y=y,selectable=r.isGraveyardSelectable,poi=r.areaPoiID}
        end
    end
    self.liveGY[ui]=out
end

-- UI map rectangles bound local assignment possibilities; they do not prove
-- an enemy's terrain area. Include linked subareas of every intersecting map
-- so an observer across a border cannot veto the enemy's closer graveyard.
function A:PossibleAssignmentAreas(p)
    local roots,areas={},{}
    if not p or not self:Finite(p.x) or not self:Finite(p.y) or not self:Finite(p.uncertainty) or p.uncertainty<0 then return areas,roots end
    for _,m in pairs(self.Data.maps or {}) do
        if m[2]==p.map then
            local minX,maxX=math.min(m[3],m[5]),math.max(m[3],m[5])
            local minY,maxY=math.min(m[4],m[6]),math.max(m[4],m[6])
            local dx=math.max(minX-p.x,0,p.x-maxX)
            local dy=math.max(minY-p.y,0,p.y-maxY)
            if dx*dx+dy*dy<=p.uncertainty*p.uncertainty then roots[m[1]]=true end
        end
    end
    for area in pairs(self.Data.links) do
        for _,ancestor in ipairs(self:AreaChain(area)) do
            if roots[ancestor] then areas[#areas+1]=area; break end
        end
    end
    table.sort(areas)
    return areas,roots
end

function A:ResolveGraveyard(p,area,faction,exactArea)
    local candidates,seen={},{}
    local function add(g)
        if IsUsableGraveyard(g) and not seen[g.id] and (not p or g.map==p.map) then
            seen[g.id]=true; candidates[#candidates+1]=g
        end
    end
    local used,reason,scope,assignmentAreas
    if exactArea or not p or not self:Finite(p.uncertainty) then
        local links
        links,used=self:ResolveLinks(area,faction)
        for _,v in ipairs(links) do add(v.gy) end
        scope=exactArea and "known player/test area assignment" or "observer prediction only; enemy location unbounded"
        reason=used and string.format("First eligible linked area %d (%s)",used,self:AreaName(used)) or "No eligible area assignment"
    else
        local roots
        assignmentAreas,roots=self:PossibleAssignmentAreas(p)
        for _,id in ipairs(assignmentAreas) do
            for _,link in ipairs(self.Data.links[id] or {}) do
                if self:Eligible(link[2],faction) then add(self.Data.graveyards[link[1]]) end
            end
        end
        scope="local map coverage and linked subarea possibilities"
        reason=string.format("Enemy area unknown; %d possible linked areas intersect local map coverage",#assignmentAreas)
        -- Retain the Scarlet Monastery allowance without excluding other local
        -- possibilities when the corpse's area is not known.
        local faol=self.Data.graveyards[429]
        local distance=faol and self:Distance(p,faol)
        if faction=="Alliance" and roots[85] and distance and distance<=1200+p.uncertainty then
            add(faol); reason=reason.."; Faol's Rest retained for Scarlet Monastery vicinity"
        end
    end
    table.sort(candidates,function(a,b) return a.id<b.id end)
    local predicted,best
    for _,g in ipairs(candidates) do
        local d=self:Distance(p,g)
        if d then
            if self:Finite(p.z) and self:Finite(g.z) then d=(d*d+(p.z-g.z)^2)^.5 end
            if not best or d<best then predicted,best=g,d end
        end
    end
    if #candidates==0 then reason=reason.."; no usable local coverage, immediate warning" end
    return {predicted=predicted,candidates=candidates,assignmentArea=used,assignmentAreas=assignmentAreas,
        reason=reason,source="CMaNGOS Classic-DB; Era assignment unverified",exactArea=exactArea,candidateScope=scope}
end
