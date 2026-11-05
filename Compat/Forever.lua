-- Client boundary. Original WoW functions stay untouched; only addon-owned
-- consumers use these readers. Never index, stringify or compare secret values.
local addon, namespace = ...
VoidMarkForever = VoidMarkForever or {}
local F = VoidMarkForever
F.Namespace = namespace
F.IsForever = true
F.Capabilities = { combatLog = false }
F.Errors = {}
F.API = {}
local unpack = unpack or table.unpack
local function pack(...) return {n=select('#',...),...} end
function F.Readable(value)
    if type(issecretvalue)=="function" then
        local ok,secret=pcall(issecretvalue,value)
        if not ok or secret then return nil end
    end
    return value
end
function F.Safe(fn,...)
    if type(fn)~="function" then return nil end
    local r=pack(pcall(fn,...))
    if not r[1] then return nil end
    for i=2,r.n do r[i]=F.Readable(r[i]) end
    return unpack(r,2,r.n)
end
function F.FullName(unit)
    local name,second=F.Safe(_G.UnitName,unit)
    if type(name)~="string" or name=="" then return nil end
    if type(second)=="string" and second~="" then return name.."-"..second end
    return name
end
function F.PlayerIdentity()
    local name=F.FullName("player") or "?"
    local realm=F.Safe(GetRealmName) or "?"
    return name,realm,name.."@"..realm
end
function F.DisplayName(name)
    name=F.Readable(name)
    if type(name)~="string" then return "" end
    return name:gsub("%-"," ",1)
end
F.TargetName=F.DisplayName
function F.SamePlayer(a,b) return a~=nil and b~=nil and a==b end
local functions={
    "UnitFullName","UnitInParty","UnitInRaid","UnitOnTaxi","UnitPVPRank","UnitExists","UnitIsPlayer","UnitIsEnemy","UnitCanAttack","UnitGUID","UnitName",
    "UnitClass","UnitRace","UnitLevel","UnitFactionGroup","UnitHealth","UnitHealthMax",
    "UnitIsDeadOrGhost","UnitIsDead","UnitIsGhost","UnitIsFeignDeath","UnitIsPVP",
    "UnitPosition","UnitBuff","UnitDebuff","UnitAura","UnitCreatureType","UnitIsConnected",
    "UnitIsUnit","UnitAffectingCombat","GetPlayerInfoByGUID","GetGuildInfo",
    "GetZonePVPInfo","IsInInstance","CheckInteractDistance","IsSpellInRange",
    "GetSpellCooldown","GetSpellTexture","GetSpellInfo","GetNetStats","GetFriendInfo",
    "GetNumFriends","GetAddOnMetadata","GetSpellLink","UnitCastingInfo","UnitChannelInfo",
}
for _,name in ipairs(functions) do
    local original=_G[name]
    F.API[name]=function(...) return F.Safe(original,...) end
end
-- Self records must include the secondary name, including killer/streak keys.
F.API.UnitName=function(unit)
    if unit=="player" then return F.FullName(unit) end
    return F.Safe(_G.UnitName,unit)
end
if not GetSpellInfo and C_Spell and C_Spell.GetSpellInfo then
    F.API.GetSpellInfo=function(id)
        local s=F.Safe(C_Spell.GetSpellInfo,id)
        if type(s)~="table" then return nil end
        return F.Readable(s.name),nil,F.Readable(s.iconID),F.Readable(s.castTime),F.Readable(s.minRange),F.Readable(s.maxRange),F.Readable(s.spellID)
    end
end
if not GetSpellTexture and C_Spell then
    F.API.GetSpellTexture=function(id) return F.Safe(C_Spell.GetSpellTexture,id) end
end
if not GetSpellCooldown and C_Spell then
    F.API.GetSpellCooldown=function(id)
        local s=F.Safe(C_Spell.GetSpellCooldown,id)
        if type(s)~="table" then return nil end
        return F.Readable(s.startTime),F.Readable(s.duration),F.Readable(s.isEnabled),F.Readable(s.modRate)
    end
end
local function Aura(unit,index,filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return nil end
    local a=F.Safe(C_UnitAuras.GetAuraDataByIndex,unit,index,filter)
    if type(a)~="table" then return nil end
    return F.Readable(a.name),F.Readable(a.icon),F.Readable(a.applications),F.Readable(a.dispelName),F.Readable(a.duration),F.Readable(a.expirationTime),F.Readable(a.sourceUnit),F.Readable(a.isStealable),nil,F.Readable(a.spellId)
end
if not UnitAura then F.API.UnitAura=Aura end
if not UnitBuff then F.API.UnitBuff=function(u,i) return Aura(u,i,"HELPFUL") end end
if not UnitDebuff then F.API.UnitDebuff=function(u,i) return Aura(u,i,"HARMFUL") end end
if not GetAddOnMetadata and C_AddOns then F.API.GetAddOnMetadata=function(...) return F.Safe(C_AddOns.GetAddOnMetadata,...) end end
function F.CombatInfo()
    if type(CombatLogGetCurrentEventInfo)~="function" then return nil end
    local values=pack(pcall(CombatLogGetCurrentEventInfo))
    if not values[1] then F.Capabilities.combatLog=false; return nil end
    -- A partially secret event cannot establish attribution. Discard it whole.
    for i=2,values.n do
        local value=F.Readable(values[i])
        if value==nil and type(issecretvalue)=="function" then
            local ok,secret=pcall(issecretvalue,values[i])
            if not ok or secret then F.Capabilities.combatLog=false; return nil end
        end
    end
    if type(values[3])~="string" then return nil end
    F.Capabilities.combatLog=true
    return unpack(values,2,values.n)
end
F.API.CombatLogGetCurrentEventInfo=F.CombatInfo
function F.RegisterEvent(frame,event,...)
    if event=="COMBAT_LOG_EVENT_UNFILTERED" then
        F.CombatConsumers=F.CombatConsumers or {}
        F.CombatConsumers[frame]=true
        if not F.CombatInfo() then return false end
    end
    local ok,err=pcall(frame.RegisterEvent,frame,event,...)
    if not ok then F.Errors[event]=tostring(err) end
    return ok
end
function F.IsGroupSender(sender)
    if type(sender)~="string" then return false end
    if sender==F.FullName("player") then return false end
    local raid=F.Safe(IsInRaid)
    for i=1,(raid and 40 or 4) do
        local unit=(raid and "raid" or "party")..i
        local full=F.FullName(unit)
        if full==sender or (full and F.DisplayName(full)==sender) then return true end
        -- Chat sender formatting may use a realm; match a readable unit GUID
        -- via the client's resolver, never via first-name-only comparison.
        local guid=F.Safe(UnitGUID,unit)
        local _,_,_,_,_,n,r=F.Safe(GetPlayerInfoByGUID,guid)
        if n and r and n.."-"..r==sender then return true end
    end
    return false
end

-- Do not register restricted combat events on the baseline client. Modules
-- become consumers only if the getter demonstrates a readable event.
function F.ProbeCombatLog()
    if not F.CombatInfo() then return false end
    for frame in pairs(F.CombatConsumers or {}) do
        local ok,err=pcall(frame.RegisterEvent,frame,"COMBAT_LOG_EVENT_UNFILTERED")
        if not ok then F.Errors.COMBAT_LOG_EVENT_UNFILTERED=tostring(err) end
    end
    return true
end
