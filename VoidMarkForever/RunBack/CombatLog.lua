local VMAPI = VoidMarkForever.API
local _, A = ...
local band=bit.band
local PLAYER=COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local HOSTILE=COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
local CONTROL=COMBATLOG_OBJECT_CONTROL_PLAYER or 0x100
local AFFILIATION=0x7 -- mine, party, raid; includes pets with player control
local damage={SWING_DAMAGE=true,RANGE_DAMAGE=true,SPELL_DAMAGE=true,SPELL_PERIODIC_DAMAGE=true,DAMAGE_SHIELD=true,DAMAGE_SPLIT=true}

function A:RefreshGroup()
    self.group={}; self.sourceUnits={}
    local function remember(u)
        local id=self:Safe(VMAPI.UnitGUID,u)
        if id then self.group[id]=true; self.sourceUnits[id]=u end
    end
    for _,u in ipairs({"player","pet"}) do remember(u) end
    for i=1,40 do
        local prefix=IsInRaid and IsInRaid() and "raid" or "party"
        if prefix=="party" and i>4 then break end
        for _,u in ipairs({prefix..i,prefix.."pet"..i}) do remember(u) end
    end
end

function A:FindGroupSourceUnit(guid)
    if not guid then return nil end
    local unit=self.sourceUnits and self.sourceUnits[guid]
    if unit and self:Safe(VMAPI.UnitExists,unit) and self:Safe(VMAPI.UnitGUID,unit)==guid then return unit end
    self:RefreshGroup()
    unit=self.sourceUnits[guid]
    if unit and self:Safe(VMAPI.UnitExists,unit) and self:Safe(VMAPI.UnitGUID,unit)==guid then return unit end
end

function A:IsOurSource(guid,flags)
    return guid and ((self.group and self.group[guid]) or (flags and band(flags,AFFILIATION)~=0 and band(flags,CONTROL)~=0))
end

function A:IsEnemyPlayer(guid,flags)
    return type(guid)=="string" and guid:sub(1,7)=="Player-" and type(flags)=="number" and band(flags,PLAYER)~=0 and band(flags,HOSTILE)~=0
end

function A:Observe(unit)
    -- Mouseover/nameplate/target events can fire while Blizzard marks the unit
    -- token as protected.  Identity reads on those tokens can taint the UI even
    -- though this observer never performs a protected action.  Read every unit
    -- field through the RunBack safe wrapper and abandon the observation when
    -- the token is not safely readable.
    if not unit then return end
    local isPlayer=self:Safe(VMAPI.UnitIsPlayer,unit)
    if not isPlayer then return end

    local guid=self:Safe(VMAPI.UnitGUID,unit)
    if type(guid)~="string" or guid:sub(1,7)~="Player-" then return end

    local name,realm=self:Safe(VMAPI.UnitName,unit)
    if not name or name=="" then return end
    if realm and realm~="" then name=name.."-"..realm end

    local _,class=self:Safe(VMAPI.UnitClass,unit)
    local _,race=self:Safe(VMAPI.UnitRace,unit)
    local faction=self:Safe(VMAPI.UnitFactionGroup,unit)
    local level=self:Safe(VMAPI.UnitLevel,unit)

    self.seen[guid]={name=name,level=level,class=class,race=race,faction=faction,observed=self:Now()}
    if unit~="mouseover" then self.units[guid]=unit end

    -- The protected-action report we captured came specifically through the
    -- UPDATE_MOUSEOVER_UNIT path while range/location enrichment was running.
    -- Identity is useful, but a mouseover envelope is optional: direct damage,
    -- target and nameplate observations can supply a conservative envelope.
    -- Skip range APIs entirely for mouseover so this event cannot enter the
    -- restricted VMAPI.CheckInteractDistance/VMAPI.IsSpellInRange/VMAPI.UnitPosition chain.
    if unit ~= "mouseover" then
        self:Safe(function()
            self:RememberEnemyEnvelope(guid,unit,"unit observation")
        end)
    end

    self:ScheduleCleanup()
    -- Life-state confirmation triggers detection/alerts only. It never changes
    -- the physical estimate. Mouseover remains identity-only.
    if unit~="mouseover" then self:ConfirmLiveObservation(guid,unit) end
end

function A:ConfirmLiveObservation(guid,unit)
    local r=self.active and self.active[guid]
    if not r or r.rezConfirmed or unit=="mouseover" then return false end
    if self:Now()-(r.deathObservedAt or self:Now())<0.5 then return false end
    if self:Safe(VMAPI.UnitGUID,unit)~=guid or self:Safe(VMAPI.UnitIsDeadOrGhost,unit)~=false then return false end
    if type(VMAPI.UnitIsFeignDeath)=="function" and self:Safe(VMAPI.UnitIsFeignDeath,unit)~=false then return false end
    r.rezConfirmed=true; r.rezObservedAt=self:Now(); r.rezObservedEpoch=self:Epoch()
    if self.OnVoidMarkRezConfirmed then self:OnVoidMarkRezConfirmed(r,unit) end
    self:Save()
    return true
end

function A:CheckLiveTimers()
    -- A selected target/nameplate may keep the same token across resurrection,
    -- without another added/target-changed event. Reuse the existing UI tick.
    for guid,r in pairs(self.active) do
        local unit=self.units[guid]
        if unit and not r.rezConfirmed then self:ConfirmLiveObservation(guid,unit) end
    end
end

function A:ForgetUnit(unit)
    for guid,u in pairs(self.units) do if u==unit then self.units[guid]=nil end end
end

function A:CombatEvent(timestamp,event,hideCaster,sg,sn,sf,srf,dg,dn,df,drf,...)
    if not dg or (event~="UNIT_DIED" and event~="PARTY_KILL" and not damage[event]) then return end
    if not self:IsEnemyPlayer(dg,df) then return end
    local now=self:Now()

    if damage[event] then
        if self:IsOurSource(sg,sf) then
            self.involved[dg]=now
            -- Prefer a live target/nameplate envelope.  If the unit token has
            -- already vanished, direct damage itself supplies a deliberately
            -- loose combat-log range bound so a real kill does not collapse to
            -- immediate UNKNOWN/RETURN POSSIBLE.
            local captured=self:RememberEnemyEnvelopeByGUID(dg,"our damage event")
            if not captured and event~="SPELL_PERIODIC_DAMAGE" and event~="DAMAGE_SPLIT" then
                local spellID=(event=="SWING_DAMAGE") and nil or select(1,...)
                self:RememberDamageEventEnvelope(dg,event,spellID,"our direct damage event",sg)
            end
            self:ScheduleCleanup()
        end
        return
    end

    -- This engine receives its own death callback, independently of VoidMark/GT.
    -- Apply the same Hunter classification before pinning a fake corpse timer.
    local gt=TaliaaGankTracker
    local payload2,payload5=select(2,...),select(5,...)
    local unconscious
    if event=="PARTY_KILL" then unconscious=payload5 else unconscious=payload2 end
    if unconscious==true or unconscious==1 or unconscious=="1" then return end
    if gt and gt.IsUnitCurrentlyFeigningName and gt:IsUnitCurrentlyFeigningName(dn) then return end
    if event=="UNIT_DIED" and gt then
        if gt.ShouldSuppressHunterUnitDied and gt:ShouldSuppressHunterUnitDied(dn,dg) then return end
        if gt.IsRecentFeign and gt:IsRecentFeign(dn,dg) then return end
    end

    local eligible=(event=="PARTY_KILL" and self:IsOurSource(sg,sf)) or (self.involved[dg] and now-self.involved[dg]<=self.db.settings.assist)
    if not eligible then self.metrics.ignored=self.metrics.ignored+1; return end
    self.lastDeath=self.lastDeath or {}
    -- Match the central kill-credit duplicate window. A second event for the
    -- same death must not restart the row's countdown.
    if self.lastDeath[dg] and now-self.lastDeath[dg]<6 then return end
    if not self:IsOutdoor() then return end
    self.lastDeath[dg]=now; self.involved[dg]=nil
    local info=self.seen[dg] or {}
    local p,ctx,exact=self:CaptureLocation(dg)
    local faction=info.faction
    if not faction or faction=="Neutral" then
        local own=VMAPI.UnitFactionGroup("player"); faction=own=="Horde" and "Alliance" or own=="Alliance" and "Horde" or "Unknown"
    end
    local _,_,_,latency=self:Safe(VMAPI.GetNetStats)
    latency=self:Finite(latency) and math.max(0,latency/1000) or 0
    local death={guid=dg,name=info.name or dn,at=now-latency,observedAt=now,latency=latency,epoch=self:Epoch(),position=p,context=ctx,exactArea=exact,
        faction=faction,race=info.race,class=info.class,level=info.level}
    -- The event handler does no graveyard search, pathfinding, or UI work.
    C_Timer.After(0,function() A:CreateTimer(death) end)
    self:ScheduleCleanup()
end

function A:ScheduleCleanup()
    if not self.cleanupPending then
        self.cleanupPending=true
        C_Timer.After(30,function()
            A.cleanupPending=false; local t=A:Now()
            for id,v in pairs(A.involved) do if t-v>30 then A.involved[id]=nil end end
            for id,v in pairs(A.lastDeath or {}) do if t-v>30 then A.lastDeath[id]=nil end end
            for id,v in pairs(A.seen) do if t-v.observed>300 then A.seen[id]=nil; A.units[id]=nil end end
            for id,v in pairs(A.enemyBounds or {}) do if t-(v.at or 0)>30 then A.enemyBounds[id]=nil end end
            -- Re-arm only while transient observation/combat state remains.
            -- This guarantees stale entries eventually expire without keeping a
            -- permanent background ticker alive.
            if next(A.involved) or next(A.lastDeath or {}) or next(A.seen) or next(A.enemyBounds or {}) then
                A:ScheduleCleanup()
            end
        end)
    end
end
