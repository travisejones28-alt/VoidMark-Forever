local VMAPI = VoidMarkForever.API
local _, A = ...

function A:BuildAreaIndex()
    self.areaNames={}; self.children={}
    for id,r in pairs(self.Data.areas) do
        local name=self:Safe(C_Map and C_Map.GetAreaInfo,id) or r[3]
        self.areaNames[name]=self.areaNames[name] or {}; table.insert(self.areaNames[name],id)
        if r[1]~=0 then self.children[r[1]]=self.children[r[1]] or {}; table.insert(self.children[r[1]],id) end
    end
end

function A:AreaChain(id)
    local chain,seen={},{}
    while id and id~=0 and not seen[id] do
        seen[id]=true; chain[#chain+1]=id; local a=self.Data.areas[id]; id=a and a[1]
    end
    return chain
end

function A:AreaName(id)
    return id and (self:Safe(C_Map and C_Map.GetAreaInfo,id) or (self.Data.areas[id] and self.Data.areas[id][3]) or tostring(id)) or "unknown"
end

function A:WorldPosition(unit)
    local x,y,z,map=self:Safe(VMAPI.UnitPosition,unit)
    if self:Finite(x) and self:Finite(y) and (map==0 or map==1) then
        return {x=x,y=y,z=z,map=map,source="VMAPI.UnitPosition("..unit..")",uncertainty=0}
    end
    -- GetPlayerMapPosition is explicitly limited to player/party; never invent enemy coordinates.
    if unit~="player" and not unit:match("^party%d$") and not unit:match("^raid%d+$") then return end
    local ui=self:Safe(C_Map and C_Map.GetBestMapForUnit,unit)
    local p=ui and self:Safe(C_Map and C_Map.GetPlayerMapPosition,ui,unit)
    if p then
        local mapID,w=self:Safe(C_Map and C_Map.GetWorldPosFromMapPos,ui,p)
        if w and (mapID==0 or mapID==1) then
            local wx,wy=self:Safe(w.GetXY,w)
            if self:Finite(wx) and self:Finite(wy) then
                return {x=wx,y=wy,map=mapID,source="C_Map world conversion ("..unit..")",uncertainty=0}
            end
        end
    end
end

function A:InferOutdoorZoneFromPosition(p)
    if not p or not self:Finite(p.x) or not self:Finite(p.y) or (p.map~=0 and p.map~=1) then return nil,nil end
    local bestZone,bestUI,bestArea
    for ui,m in pairs(self.Data.maps or {}) do
        local zone,continent=m[1],m[2]
        if continent==p.map and self.Data.links[zone] then
            local minX,maxX=math.min(m[3],m[5]),math.max(m[3],m[5])
            local minY,maxY=math.min(m[4],m[6]),math.max(m[4],m[6])
            if p.x>=minX and p.x<=maxX and p.y>=minY and p.y<=maxY then
                local area=(maxX-minX)*(maxY-minY)
                if not bestArea or area<bestArea then
                    bestZone,bestUI,bestArea=zone,ui,area
                end
            end
        end
    end
    return bestZone,bestUI
end

function A:PlayerContext()
    local p=self:WorldPosition("player")
    local ui=self:Safe(C_Map and C_Map.GetBestMapForUnit,"player")
    local mapping=ui and self.Data.maps[ui]
    local zone=mapping and mapping[1]
    local inferred=false

    -- Cave/entrance micro-maps (Wailing Caverns is a common example) can be
    -- returned by GetBestMapForUnit even though they are not present in our
    -- outdoor zone map table.  Recover the enclosing outdoor zone directly
    -- from the player's continent world coordinates instead of dropping to
    -- UNKNOWN graveyard.  Only zones with static graveyard assignments are
    -- eligible for this fallback.
    if not zone and p then
        local inferredZone,inferredUI=self:InferOutdoorZoneFromPosition(p)
        if inferredZone then
            zone=inferredZone
            ui=inferredUI or ui
            mapping=ui and self.Data.maps[ui]
            inferred=true
        end
    end

    local sub=self:Safe(GetSubZoneText) or ""
    local id=zone
    if zone then
        for _,candidate in ipairs(self.areaNames[sub] or {}) do
            for _,ancestor in ipairs(self:AreaChain(candidate)) do
                if ancestor==zone then id=candidate; break end
            end
        end
    end
    return {uiMap=ui,area=id,zone=zone,subzone=sub,zoneName=self:Safe(GetZoneText),position=p,chain=self:AreaChain(id),map=p and p.map or (mapping and mapping[2]),inferredZone=inferred}
end

-- Build a compact list of player spells that can provide a current hostile-unit
-- upper range bound through VMAPI.IsSpellInRange().  This is only used as a geometry
-- bound; spell damage, sightings and later reappearances never train the timer.
function A:GetSpellRangeInfo(identifier)
    local name,minRange,maxRange
    if C_Spell and type(C_Spell.GetSpellInfo)=="function" then
        local info=self:Safe(C_Spell.GetSpellInfo,identifier)
        if type(info)=="table" then
            name=info.name
            minRange=tonumber(info.minRange) or 0
            maxRange=tonumber(info.maxRange) or 0
        end
    end
    if (not maxRange or maxRange<=0) and type(VMAPI.GetSpellInfo)=="function" then
        local n,_,_,_,mn,mx=self:Safe(VMAPI.GetSpellInfo,identifier)
        name=name or n
        minRange=tonumber(mn) or minRange or 0
        maxRange=tonumber(mx) or maxRange or 0
    end
    return name,minRange or 0,maxRange or 0
end

function A:BuildRangeSpellCache()
    local list,seen={},{}
    if type(GetNumSpellTabs)~="function" or type(GetSpellTabInfo)~="function" or type(GetSpellBookItemName)~="function" then
        self.rangeSpells=list; return list
    end
    local tabs=self:Safe(GetNumSpellTabs) or 0
    for tab=1,tabs do
        local _,_,offset,num=self:Safe(GetSpellTabInfo,tab)
        offset,num=tonumber(offset) or 0,tonumber(num) or 0
        for i=offset+1,offset+num do
            local spellName,_,spellID=self:Safe(GetSpellBookItemName,i,BOOKTYPE_SPELL or "spell")
            local key=spellID or spellName
            if key and not seen[key] then
                local infoName,minRange,maxRange=self:GetSpellRangeInfo(spellID or spellName)
                if maxRange and maxRange>0 and maxRange<=100 then
                    seen[key]=true
                    list[#list+1]={name=spellName or infoName,id=spellID,min=minRange,max=maxRange,index=i}
                end
            end
        end
    end
    table.sort(list,function(a,b) if a.max==b.max then return tostring(a.name)<tostring(b.name) end return a.max<b.max end)
    self.rangeSpells=list
    return list
end

local function PositiveRangeResult(v)
    return v==1 or v==true
end

function A:SpellRangeBound(unit)
    if not unit or not self:Safe(VMAPI.UnitExists,unit) or not self:Safe(VMAPI.UnitIsPlayer,unit) or not self:Safe(VMAPI.UnitCanAttack,"player",unit) then return nil end
    local list=self.rangeSpells or self:BuildRangeSpellCache()
    for _,s in ipairs(list) do
        local ok
        if C_Spell and type(C_Spell.IsSpellInRange)=="function" then
            ok=self:Safe(C_Spell.IsSpellInRange,s.id or s.name,unit)
        end
        if ok==nil and type(VMAPI.IsSpellInRange)=="function" then
            ok=self:Safe(VMAPI.IsSpellInRange,s.name,unit)
        end
        if PositiveRangeResult(ok) then
            -- Add 8 yd for hitbox/API edge behavior.  We want a conservative
            -- upper bound, not a cosmetic range estimate.
            return s.max+8,s.name
        end
    end
end

function A:FindUnitByGUID(guid)
    if not guid then return nil end
    local unit=self.units and self.units[guid]
    -- Never recycle a mouseover token into range/location enrichment. Blizzard
    -- can mark mouseover as protected even after the original observation
    -- callback returns, which would reopen the protected API chain.
    if unit=="mouseover" then unit=nil end
    if unit and self:Safe(VMAPI.UnitExists,unit) and self:Safe(VMAPI.UnitGUID,unit)==guid then return unit end
    for _,u in ipairs({"target","focus"}) do
        if self:Safe(VMAPI.UnitExists,u) and self:Safe(VMAPI.UnitGUID,u)==guid then
            self.units[guid]=u
            return u
        end
    end
    -- Nameplate tokens can exist even if our cached token was cleared/reused.
    -- Scan them on the damage/death event before declaring the corpse unbounded.
    for i=1,40 do
        local u="nameplate"..i
        if self:Safe(VMAPI.UnitExists,u) and self:Safe(VMAPI.UnitGUID,u)==guid then
            self.units[guid]=u
            return u
        end
    end
end

-- When a direct damage combat-log event arrives after the hostile unit token has
-- vanished, recent direct damage supplies a loose modeled range allowance.
-- Projectile travel and exceptional movement prevent a certified bound.
-- A live unit-token range envelope always wins.
function A:RememberDamageEventEnvelope(guid,event,spellID,reason,sourceGUID)
    if not guid then return false end
    local sourceUnit=self:FindGroupSourceUnit(sourceGUID)
    if not sourceUnit then return false end
    local anchor=self:WorldPosition(sourceUnit)
    if not anchor then return false end
    local bound,label
    if event=="SWING_DAMAGE" then
        bound=15
        label="melee damage event from "..sourceUnit
    elseif event=="RANGE_DAMAGE" or event=="SPELL_DAMAGE" or event=="DAMAGE_SHIELD" then
        local spellName,_,maxRange=self:GetSpellRangeInfo(spellID)
        if maxRange and maxRange>0 then
            -- Large slack covers hitboxes plus caster/target movement between a
            -- ranged cast and projectile impact.  Overstating uncertainty makes
            -- the warning earlier, never later.
            bound=maxRange+30
            label=string.format("direct %s event from %s (%s; %.0f yd allowance)",event,sourceUnit,spellName or tostring(spellID),bound)
        else
            -- Unknown spell ranges get a loose allowance. This is a heuristic,
            -- not evidence of a guaranteed maximum caster/target separation.
            bound=60
            label=string.format("direct %s event from %s (60 yd allowance)",event,sourceUnit)
        end
    else
        return false
    end
    anchor.uncertainty=bound
    anchor.source=label
    self.enemyBounds=self.enemyBounds or {}
    self.enemyBounds[guid]={x=anchor.x,y=anchor.y,z=anchor.z,map=anchor.map,uncertainty=bound,source=anchor.source,sourceGUID=sourceGUID,at=self:Now(),reason=reason or "damage event",damage=true}
    return true
end

-- Capture the tightest defensible CURRENT envelope around the enemy.  The
-- envelope is centered on our world position because Era does not expose
-- hostile-player world coordinates.  A positive range result is useful even
-- when VMAPI.UnitPosition(enemy) is unavailable.
function A:CurrentEnemyEnvelope(unit)
    -- Mouseover identity may be observed, but never use it for hostile
    -- VMAPI.UnitPosition / interact / spell-range queries.
    if not unit or unit=="mouseover" or not self:Safe(VMAPI.UnitExists,unit) or not self:Safe(VMAPI.UnitIsPlayer,unit) then return nil end
    local exact=self:WorldPosition(unit)
    if exact then return exact,0,"exact hostile VMAPI.UnitPosition" end
    local anchor=self:WorldPosition("player")
    if not anchor then return nil end

    -- Follow/interact is a cheap, reliable close-range upper bound when true.
    if self:Safe(VMAPI.CheckInteractDistance,unit,4) then
        anchor.uncertainty=40
        anchor.source="observer + positive follow-range check (40 yd envelope)"
        return anchor,40,"follow range"
    end

    local spellRange,spell=self:SpellRangeBound(unit)
    if spellRange then
        anchor.uncertainty=spellRange
        anchor.source=string.format("observer + VMAPI.IsSpellInRange(%s) upper bound (%.0f yd envelope)",spell,spellRange)
        return anchor,spellRange,"spell range"
    end
end

function A:RememberEnemyEnvelope(guid,unit,reason)
    if not guid then return end
    local p=self:CurrentEnemyEnvelope(unit)
    if not p or not self:Finite(p.uncertainty) then return end
    self.enemyBounds=self.enemyBounds or {}
    self.enemyBounds[guid]={
        x=p.x,y=p.y,z=p.z,map=p.map,uncertainty=p.uncertainty,
        source=p.source,at=self:Now(),reason=reason or "observation"
    }
end

function A:RememberEnemyEnvelopeByGUID(guid,reason)
    local unit=self:FindUnitByGUID(guid)
    if not unit then return false end
    local before=self.enemyBounds and self.enemyBounds[guid]
    self:RememberEnemyEnvelope(guid,unit,reason)
    local after=self.enemyBounds and self.enemyBounds[guid]
    return after~=nil and after~=before
end

function A:CaptureLocation(guid)
    local unit=self:FindUnitByGUID(guid)
    local ctx=self:PlayerContext()
    self.context=ctx

    -- First try the enemy token at death time.
    if unit then
        local p=self:CurrentEnemyEnvelope(unit)
        if p then return p,ctx,false end
    end

    -- If the unit token vanished with death, use a very recent envelope sampled
    -- on our damage event/nameplate.  Expand it for elapsed time rather than
    -- pretending the old sample is the corpse coordinate.
    local b=self.enemyBounds and self.enemyBounds[guid]
    if b and self:Finite(b.uncertainty) then
        local age=math.max(0,self:Now()-(b.at or self:Now()))
        -- Older samples cannot bound instant movement or transport reliably.
        -- Keep recent combat geometry, but never stretch a stale observation
        -- across the full assist-credit window and call it a safe location.
        local maxAge=2.0
        if age<=maxAge then
            local p={x=b.x,y=b.y,z=b.z,map=b.map,source=b.source,uncertainty=b.uncertainty,sourceGUID=b.sourceGUID}
            -- Model allowance for travel plus an instant movement ability.
            -- This is an optimistic estimate, not a certified motion limit.
            p.uncertainty=p.uncertainty+6+(16*age)+(age>0 and 40 or 0)
            p.source=string.format("recent combat envelope; %.2f s old; expanded to %.1f yd",age,p.uncertainty)
            return p,ctx,false
        end
    end

    -- Last resort remains explicitly unbounded.  We will warn immediately
    -- rather than fabricate a corpse location.
    local proxy=self:WorldPosition("player")
    if proxy then
        proxy.source="observer position; enemy coordinates unavailable and no fresh range envelope"
        proxy.uncertainty=nil
    end
    return proxy,ctx,false
end
