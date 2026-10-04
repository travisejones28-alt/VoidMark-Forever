local VMAPI = VoidMarkForever.API
-- VoidMark Enemy Moves
-- Native hostile PvP cooldown tracker.
VoidMarkEnemyMoves = VoidMarkEnemyMoves or {}
local EM = VoidMarkEnemyMoves

local VERSION = "1.3.3"
local MAX_ROWS = 8
local ROW_H, ROW_GAP = 22, 3
local HEADER_H, STATUS_H = 63, 22
local FRAME_W = 270

local C = {
    bg={0.010,0.006,0.018,0.985},
    panel={0.025,0.012,0.040,0.98},
    edge={0.56,0.18,0.88,1.00},
    glow={0.72,0.26,1.00,0.70},
    purple={0.78,0.38,1.00,1},
    dim={0.60,0.53,0.67,1},
    white={0.97,0.96,1.00,1},
    red={1.00,0.18,0.24,1},
    orange={1.00,0.57,0.10,1},
    green={0.30,1.00,0.52,1},
    blue={0.28,0.64,1.00,1},
    gray={0.62,0.62,0.68,1},
}

local SPELLS, CANON = {}, {}
local enemies, petOwner = {}, {}
local targetGUID, hoverGUID, vanishedGUID, vanishUntil, duelGUID, duelName, frame, options, ticker
local testMode, testGUID = false, "VOIDMARK-ENEMYMOVES-TEST"

local function Now() return GetTime() end
local function Clamp(v,lo,hi)
    v=tonumber(v) or lo
    if v<lo then return lo end
    if v>hi then return hi end
    return v
end
local function SetColor(fs,c) fs:SetTextColor(c[1],c[2],c[3],c[4] or 1) end
local function DB()
    VoidMarkDB = VoidMarkDB or {}
    VoidMarkDB.VoidMarkEnemyMoves = type(VoidMarkDB.VoidMarkEnemyMoves)=="table" and VoidMarkDB.VoidMarkEnemyMoves or {}
    local db=VoidMarkDB.VoidMarkEnemyMoves
    if db.enabled==nil then db.enabled=true end
    if db.scale==nil then db.scale=0.90 end
    if db.bgOpacity==nil then db.bgOpacity=0.90 end
    if db.frameOpacity==nil then db.frameOpacity=1.0 end
    return db
end
local function ShortTime(sec)
    if not sec or sec<=0 then return "0.0" end
    if sec>=60 then return string.format("%d:%02d",math.floor(sec/60),math.floor(sec%60)) end
    if sec<10 then return string.format("%.1f",sec) end
    return tostring(math.ceil(sec))
end

local function ActiveTime(sec)
    sec=math.max(0,tonumber(sec) or 0)
    if sec>=60 then return ShortTime(sec) end
    if sec<10 then return string.format("%.1fs",sec) end
    return string.format("%ds",math.ceil(sec))
end

local function AddSpell(ids,key,name,cd,active,category,color,opts)
    opts=opts or {}
    local d={key=key,name=name,cd=cd or 0,active=active or 0,category=category or "utility",
        color=color or "purple",class=opts.class,pet=opts.pet and true or false,
        reset=opts.reset,priority=opts.priority or 50,activeByID=opts.activeByID,
        sharedLockout=opts.sharedLockout}
    CANON[key]=d
    for _,id in ipairs(ids) do SPELLS[id]=d end
end

-- Rogue
AddSpell({1766,1767,1768,1769},"KICK","Kick",10,0,"control","orange",{class="ROGUE",priority=10})
AddSpell({408,8643},"KIDNEY_SHOT","Kidney Shot",20,0,"control","orange",{class="ROGUE",priority=11})
AddSpell({2094},"BLIND","Blind",210,0,"control","orange",{class="ROGUE",priority=12})
AddSpell({1776,1777,8629,11285,11286},"GOUGE","Gouge",10,0,"control","orange",{class="ROGUE",priority=13})
AddSpell({1856,1857},"VANISH","Vanish",210,0,"mobility","purple",{class="ROGUE",priority=20})
AddSpell({5277,26669},"EVASION","Evasion",210,15,"defensive","red",{class="ROGUE",priority=3})
AddSpell({2983,8696,11305},"SPRINT","Sprint",210,15,"mobility","purple",{class="ROGUE",priority=21})
AddSpell({14185},"PREPARATION","Preparation",600,0,"utility","blue",{class="ROGUE",priority=30,reset={"KICK","KIDNEY_SHOT","GOUGE","VANISH","BLIND","SPRINT","EVASION"}})

-- Mage
AddSpell({2139},"COUNTERSPELL","Counterspell",30,0,"control","orange",{class="MAGE",priority=10})
AddSpell({11958},"ICE_BLOCK","Ice Block",300,10,"defensive","red",{class="MAGE",priority=1})
AddSpell({11426,13031,13032,13033},"ICE_BARRIER","Ice Barrier",30,0,"defensive","red",{class="MAGE",priority=2})
AddSpell({1953},"BLINK","Blink",15,0,"mobility","purple",{class="MAGE",priority=20})
AddSpell({122,865,6131,10230},"FROST_NOVA","Frost Nova",21,0,"control","orange",{class="MAGE",priority=11})
AddSpell({12472},"COLD_SNAP","Cold Snap",600,0,"utility","blue",{class="MAGE",priority=30,reset={"ICE_BLOCK","ICE_BARRIER","FROST_NOVA"}})
AddSpell({12043},"PRESENCE_OF_MIND","Presence of Mind",180,15,"offensive","blue",{class="MAGE",priority=40})
AddSpell({12042},"ARCANE_POWER","Arcane Power",180,15,"offensive","blue",{class="MAGE",priority=41})
AddSpell({11129},"COMBUSTION","Combustion",180,0,"offensive","blue",{class="MAGE",priority=42})

-- Warrior
AddSpell({6552,6554},"PUMMEL","Pummel",10,0,"control","orange",{class="WARRIOR",priority=10})
AddSpell({72,1671,1672},"SHIELD_BASH","Shield Bash",12,0,"control","orange",{class="WARRIOR",priority=11})
AddSpell({20252,20616,20617},"INTERCEPT","Intercept",10,0,"mobility","purple",{class="WARRIOR",priority=20})
AddSpell({5246},"INTIMIDATING_SHOUT","Intimidating Shout",180,0,"control","orange",{class="WARRIOR",priority=12})
AddSpell({18499},"BERSERKER_RAGE","Berserker Rage",30,0,"utility","gray",{class="WARRIOR",priority=31})
AddSpell({676},"DISARM","Disarm",60,0,"control","orange",{class="WARRIOR",priority=13})
AddSpell({20230},"RETALIATION","Retaliation",1800,15,"defensive","red",{class="WARRIOR",priority=2})
AddSpell({1719},"RECKLESSNESS","Recklessness",1800,15,"offensive","blue",{class="WARRIOR",priority=40})
AddSpell({871},"SHIELD_WALL","Shield Wall",1800,10,"defensive","red",{class="WARRIOR",priority=1})

-- Priest
AddSpell({15487},"SILENCE","Silence",45,0,"control","orange",{class="PRIEST",priority=10})
AddSpell({8122,8124,10888,10890},"PSYCHIC_SCREAM","Psychic Scream",26,0,"control","orange",{class="PRIEST",priority=11})
AddSpell({14751},"INNER_FOCUS","Inner Focus",180,0,"offensive","blue",{class="PRIEST",priority=40})
AddSpell({10060},"POWER_INFUSION","Power Infusion",180,15,"offensive","blue",{class="PRIEST",priority=41})

-- Warlock
AddSpell({6789,17925,17926},"DEATH_COIL","Death Coil",120,0,"control","orange",{class="WARLOCK",priority=10})
AddSpell({19244,19647},"SPELL_LOCK","Spell Lock",24,0,"control","orange",{class="WARLOCK",pet=true,priority=11})
AddSpell({6358},"SEDUCTION","Seduction",0,0,"control","orange",{class="WARLOCK",pet=true,priority=12})
AddSpell({6229,11739,11740},"SHADOW_WARD","Shadow Ward",30,30,"defensive","red",{class="WARLOCK",priority=3})
AddSpell({18708},"FEL_DOMINATION","Fel Domination",900,15,"utility","blue",{class="WARLOCK",priority=30})
AddSpell({7812,19438,19440,19441,19442,19443},"SACRIFICE","Sacrifice",30,30,"defensive","red",{class="WARLOCK",pet=true,priority=4})

-- Hunter
AddSpell({19503},"SCATTER_SHOT","Scatter Shot",30,0,"control","orange",{class="HUNTER",priority=10})
AddSpell({19577},"INTIMIDATION","Intimidation",60,0,"control","orange",{class="HUNTER",priority=11})
AddSpell({5384},"FEIGN_DEATH","Feign Death",30,0,"utility","gray",{class="HUNTER",priority=31})
AddSpell({19263},"DETERRENCE","Deterrence",300,10,"defensive","red",{class="HUNTER",priority=2})
AddSpell({19574},"BESTIAL_WRATH","Bestial Wrath",120,18,"offensive","blue",{class="HUNTER",priority=40})
AddSpell({3045},"RAPID_FIRE","Rapid Fire",300,15,"offensive","blue",{class="HUNTER",priority=41})

-- Druid
AddSpell({16979},"FERAL_CHARGE","Feral Charge",15,0,"control","orange",{class="DRUID",priority=10})
AddSpell({5211,6798,8983},"BASH","Bash",60,0,"control","orange",{class="DRUID",priority=11})
AddSpell({17116},"NATURES_SWIFTNESS_DRUID","Nature's Swiftness",180,15,"offensive","blue",{class="DRUID",priority=40})
AddSpell({29166},"INNERVATE","Innervate",360,20,"utility","blue",{class="DRUID",priority=31})
AddSpell({1850,9821},"DASH","Dash",300,15,"mobility","purple",{class="DRUID",priority=20})
AddSpell({22812},"BARKSKIN","Barkskin",60,15,"defensive","red",{class="DRUID",priority=3})

-- Paladin. Bubble ranks have different active durations in Classic Era.
-- Divine Shield, Divine Protection and Blessing of Protection also impose the
-- same 60s invulnerability lockout (Forbearance), so using one temporarily
-- blocks the other two even when their own cooldowns are otherwise ready.
AddSpell({642,1020},"DIVINE_SHIELD","Divine Shield",300,12,"defensive","red",{
    class="PALADIN",priority=1,
    activeByID={[642]=10,[1020]=12},
    sharedLockout={"DIVINE_PROTECTION","BLESSING_PROTECTION"},
})
AddSpell({498,5573},"DIVINE_PROTECTION","Divine Protection",300,8,"defensive","red",{
    class="PALADIN",priority=2,
    activeByID={[498]=6,[5573]=8},
    sharedLockout={"DIVINE_SHIELD","BLESSING_PROTECTION"},
})
AddSpell({1022,5599,10278},"BLESSING_PROTECTION","Blessing of Protection",180,10,"defensive","red",{
    class="PALADIN",priority=3,
    activeByID={[1022]=6,[5599]=8,[10278]=10},
    sharedLockout={"DIVINE_SHIELD","DIVINE_PROTECTION"},
})
AddSpell({853,5588,5589,10308},"HAMMER_JUSTICE","Hammer of Justice",30,0,"control","orange",{class="PALADIN",priority=10})
AddSpell({633,2800,10310},"LAY_ON_HANDS","Lay on Hands",2400,0,"defensive","red",{class="PALADIN",priority=4})
AddSpell({20216},"DIVINE_FAVOR","Divine Favor",120,20,"offensive","blue",{class="PALADIN",priority=40})

-- Shaman
AddSpell({8042,8044,8045,8046,10412,10413,10414},"EARTH_SHOCK","Earth Shock",5,0,"control","orange",{class="SHAMAN",priority=10})
AddSpell({16188},"NATURES_SWIFTNESS_SHAMAN","Nature's Swiftness",180,15,"offensive","blue",{class="SHAMAN",priority=40})
AddSpell({16166},"ELEMENTAL_MASTERY","Elemental Mastery",180,30,"offensive","blue",{class="SHAMAN",priority=41})
AddSpell({16190},"MANA_TIDE_TOTEM","Mana Tide Totem",300,12,"utility","blue",{class="SHAMAN",priority=31})
AddSpell({8177},"GROUNDING_TOTEM","Grounding Totem",15,0,"utility","gray",{class="SHAMAN",priority=32})

-- Engineering / items
AddSpell({23132},"SHADOW_REFLECTOR","Shadow Reflector",300,5,"defensive","red",{priority=4})

local TRINKET_NAMES={["Insignia of the Alliance"]=true,["Insignia of the Horde"]=true,["PvP Trinket"]=true}
local POTION_EFFECT_NAMES={
    -- PvP / control
    ["Free Action"]=true,
    ["Living Free Action"]=true,
    ["Invulnerability"]=true,
    ["Speed"]=true,
    ["Invisibility"]=true,
    ["Restoration"]=true,
    ["Restorative Potion"]=true,

    -- Defensive / resistance
    ["Greater Stoneshield"]=true,
    ["Stoneshield"]=true,
    ["Magic Resistance"]=true,
    ["Frost Protection"]=true,
    ["Fire Protection"]=true,
    -- Shadow Protection also names a Priest buff; potion IDs below identify it.
    ["Nature Protection"]=true,
    ["Arcane Protection"]=true,

    -- Rage / offensive potion effects
    ["Mighty Rage"]=true,
    ["Great Rage"]=true,
    ["Rage"]=true,
}

-- Known Classic item-effect spell IDs whose visible combat-log name does not
-- necessarily contain the word "Potion". These all consume the normal potion
-- cooldown when produced by the corresponding potion item.
local POTION_EFFECT_IDS={
    [6615]=true,  -- Free Action
    [24364]=true, -- Living Free Action
    [3169]=true,  -- Limited Invulnerability
    [2379]=true,  -- Swiftness / Speed
    [17540]=true, -- Greater Stoneshield

    -- Mana potion item effects (combat log name is usually "Restore Mana")
    [437]=true,   -- Lesser Mana Potion
    [438]=true,   -- Mana Potion
    [2023]=true,  -- Greater Mana Potion
    [17530]=true, -- Superior Mana Potion
    [17531]=true, -- Major Mana Potion
    [21395]=true, -- Major Combat Mana Potion / BG variant

    -- Healing potion item effects
    [439]=true,   -- Minor Healing Potion
    [440]=true,   -- Lesser Healing Potion
    [2024]=true,  -- Greater Healing Potion
    [4042]=true,  -- Superior Healing Potion
    [17534]=true, -- Major Healing Potion

    -- Protection potion absorb effects
    [7237]=true,[7239]=true,[17544]=true, -- Frost
    [7230]=true,[17543]=true,             -- Fire
    [7241]=true,[7242]=true,[17548]=true, -- Shadow
    [7254]=true,[17546]=true,             -- Nature
    [17549]=true,                         -- Arcane
}

local POTION_DEF={key="POTION",name="Potion",cd=120,active=0,category="utility",color="gray",priority=24}
CANON.POTION=POTION_DEF

local POTION_EVENTS={
    SPELL_CAST_SUCCESS=true,
    SPELL_AURA_APPLIED=true,
    SPELL_AURA_REFRESH=true,
    SPELL_HEAL=true,
    SPELL_ENERGIZE=true,
}

local function IsPotionUse(spellID,spellName,subevent)
    if not POTION_EVENTS[subevent] then return false end

    if POTION_EFFECT_IDS[spellID] then
        return true
    end

    if type(spellName)~="string" or spellName=="" then return false end
    if spellName:lower():find("potion",1,true) then
        return true
    end

    return POTION_EFFECT_NAMES[spellName] and true or false
end

local function GetEnemy(guid,name,class)
    if not guid then return nil end
    local e=enemies[guid]
    if not e then e={guid=guid,name=name or "Unknown",class=class,spells={},seen={}} enemies[guid]=e end
    e.lastSeen=Now()
    if name and name~="" then e.name=name end
    if class and class~="" then e.class=class end
    return e
end
local function ClassFromGUID(guid)
    if not guid or not VMAPI.GetPlayerInfoByGUID then return nil end
    local _,class=VMAPI.GetPlayerInfoByGUID(guid)
    return class
end
local function LearnTargetPet()
    if VMAPI.UnitExists("target") and VMAPI.UnitIsPlayer("target") then
        local owner=VMAPI.UnitGUID("target")
        if owner and VMAPI.UnitExists("targetpet") then
            local pet=VMAPI.UnitGUID("targetpet")
            if pet then petOwner[pet]=owner end
        end
    end
end
local function ActiveDuration(def,spellID)
    if def and def.activeByID and spellID and def.activeByID[spellID] then
        return tonumber(def.activeByID[spellID]) or 0
    end
    return tonumber(def and def.active) or 0
end

local function ApplySharedLockout(e,def,now)
    if not e or not def or not def.sharedLockout then return end
    now=now or Now()
    for _,key in ipairs(def.sharedLockout) do
        local other=CANON[key]
        if other then
            local s=e.spells[key] or {}
            e.spells[key]=s
            s.key,s.name=other.key,other.name
            s.cooldownEnd=math.max(tonumber(s.cooldownEnd) or 0,now+60)
            s.sharedLockoutEnd=math.max(tonumber(s.sharedLockoutEnd) or 0,now+60)
        end
    end
end

local function StartCooldown(e,def,spellID)
    if not e or not def then return end
    local now=Now()
    local s=e.spells[def.key] or {}
    e.spells[def.key]=s
    s.key,s.name,s.usedAt=def.key,def.name,now
    s.cooldownEnd=now+(def.cd or 0)
    local duration=ActiveDuration(def,spellID)
    s.activeDuration=duration
    s.activeEnd=duration>0 and (now+duration) or nil
    s.lastSpellID=spellID or s.lastSpellID
    s.sharedLockoutEnd=nil
    e.seen[def.key]=true
    ApplySharedLockout(e,def,now)
end
local function ApplyReset(e,def)
    if not e or not def or not def.reset then return end
    for _,key in ipairs(def.reset) do
        local s=e.spells[key]
        if s then s.cooldownEnd=Now() end
    end
end
local function TrackSpell(ownerGUID,ownerName,ownerClass,spellID,spellName,event)
    local def=SPELLS[spellID]
    if not def and spellName and TRINKET_NAMES[spellName] then
        def={key="PVP_TRINKET",name="PvP Trinket",cd=300,active=0,category="utility",color="gray",priority=25}
    elseif IsPotionUse(spellID,spellName,event) then
        def=POTION_DEF
    end
    if not def then return false end
    local e=GetEnemy(ownerGUID,ownerName,ownerClass or def.class)
    if not e then return false end
    -- Local combat log plus multiple group observers can report one event.
    -- Coalesce repeats before starting cooldowns or applying resets again.
    e.lastEvents=e.lastEvents or {}
    local eventKey=tostring(spellID or def.key)..":"..tostring(event)
    local now=Now()
    if e.lastEvents[eventKey] and now-e.lastEvents[eventKey]<0.5 then return false end
    e.lastEvents[eventKey]=now
    if def.reset and event=="SPELL_CAST_SUCCESS" then
        StartCooldown(e,def,spellID) ApplyReset(e,def) return true
    end
    -- Any recognized potion-use event consumes the shared potion slot.
    -- Mana/healing potions commonly appear as SPELL_ENERGIZE/SPELL_HEAL,
    -- while protection/FAP/LIP-style pots often appear as aura applications.
    if def.key=="POTION" and POTION_EVENTS[event] then
        StartCooldown(e,def,spellID)
        return true
    end
    if event=="SPELL_CAST_SUCCESS" then
        StartCooldown(e,def,spellID)
    elseif event=="SPELL_AURA_APPLIED" or event=="SPELL_AURA_REFRESH" then
        local s=e.spells[def.key]
        -- If cast-success was not visible, an aura application still needs to
        -- restart a cooldown once the prior observed cooldown has expired.
        if not s or (s.cooldownEnd or 0)<=Now() then
            StartCooldown(e,def,spellID)
            s=e.spells[def.key]
        end
        local duration=ActiveDuration(def,spellID)
        if duration>0 then
            s.activeDuration=duration
            s.activeEnd=Now()+duration
        end
    elseif event=="SPELL_AURA_REMOVED" then
        local s=e.spells[def.key]
        if s then s.activeEnd=nil end
    end
    return true
end

local function ResizeForRows(n)
    if not frame then return end
    n=math.max(0,math.min(MAX_ROWS,tonumber(n) or 0))
    local rowBlock=n>0 and (n*ROW_H+math.max(0,n-1)*ROW_GAP+5) or 0
    frame:SetHeight(HEADER_H+STATUS_H+rowBlock+8)
end
local function ApplyAppearance()
    if not frame then return end
    local db=DB()
    frame:SetScale(Clamp(db.scale,0.50,1.50))
    frame:SetAlpha(Clamp(db.frameOpacity,0.35,1.0))
    frame:SetBackdropColor(C.bg[1],C.bg[2],C.bg[3],Clamp(db.bgOpacity,0.15,1.0))
    frame:SetBackdropBorderColor(C.edge[1],C.edge[2],C.edge[3],C.edge[4])
end
local function SavePosition()
    local db=DB()
    local p,_,rp,x,y=frame:GetPoint(1)
    db.point,db.relPoint,db.x,db.y=p,rp,x,y
end
local function RestorePosition()
    if not frame then return end
    local db=DB()
    frame:ClearAllPoints()
    if db.point then frame:SetPoint(db.point,UIParent,db.relPoint or db.point,db.x or 0,db.y or 0)
    else frame:SetPoint("CENTER",UIParent,"CENTER",250,20) end
    ApplyAppearance()
end

local function BuildUI()
    if frame then return end
    frame=CreateFrame("Frame","VoidMarkEnemyMovesFrame",UIParent,"BackdropTemplate")
    frame:SetSize(FRAME_W,HEADER_H+STATUS_H+10)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
    frame:SetBackdropBorderColor(unpack(C.edge))

    -- Reuse VoidMark's generated banner art so Enemy Moves feels like a native
    -- module instead of a separate utility window.
    frame.Banner=frame:CreateTexture(nil,"BACKGROUND",nil,1)
    frame.Banner:SetPoint("TOPLEFT",4,-4)
    frame.Banner:SetPoint("TOPRIGHT",-4,-4)
    frame.Banner:SetHeight(58)
    -- Use the original high-resolution VoidMark banner and crop to the compact
    -- VOIDMARK + FIND • TRACK • GANK section. This stays sharper than scaling
    -- the smaller dedicated reference texture.
    frame.Banner:SetTexture("Interface\\AddOns\\VoidMarkForever\\Textures\\VoidMarkGeneratedHeader.tga")
    -- Frame the VOIDMARK wordmark itself, not the hood/artwork on the left.
    -- Shift the crop right so the logo fills the header cleanly.
    frame.Banner:SetTexCoord(0.20,0.90,0.00,1.00)
    frame.Banner:SetAlpha(0.98)

    -- Dark lower band keeps module text readable while leaving the banner art
    -- visible above and behind it.
    frame.HeaderTextBG=frame:CreateTexture(nil,"BACKGROUND",nil,2)
    frame.HeaderTextBG:SetPoint("BOTTOMLEFT",frame.Banner,"BOTTOMLEFT",0,0)
    frame.HeaderTextBG:SetPoint("BOTTOMRIGHT",frame.Banner,"BOTTOMRIGHT",0,0)
    frame.HeaderTextBG:SetHeight(1)
    frame.HeaderTextBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.HeaderTextBG:SetVertexColor(0,0,0,0)

    frame.HeaderLine=frame:CreateTexture(nil,"ARTWORK",nil,1)
    frame.HeaderLine:SetPoint("BOTTOMLEFT",frame.HeaderTextBG,"BOTTOMLEFT",0,0)
    frame.HeaderLine:SetPoint("BOTTOMRIGHT",frame.HeaderTextBG,"BOTTOMRIGHT",0,0)
    frame.HeaderLine:SetHeight(1)
    frame.HeaderLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.HeaderLine:SetVertexColor(0,0,0,0)

    frame:SetScript("OnDragStart",function(self) if not DB().locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() SavePosition() end)

    frame.Title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    frame.Title:SetText("")
    frame.Title:Hide()

    frame.Version=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    frame.Version:SetText("")
    frame.Version:Hide()

    frame.OptionsButton=CreateFrame("Button",nil,frame,"BackdropTemplate")
    frame.OptionsButton:SetSize(38,18)
    frame.OptionsButton:SetPoint("TOPRIGHT",-6,-5)
    frame.OptionsButton:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=6})
    frame.OptionsButton:SetBackdropColor(0.045,0.020,0.070,0.98)
    frame.OptionsButton:SetBackdropBorderColor(0.48,0.15,0.76,1)
    frame.OptionsButton.Text=frame.OptionsButton:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    frame.OptionsButton.Text:SetAllPoints()
    frame.OptionsButton.Text:SetText("OPT")
    SetColor(frame.OptionsButton.Text,C.purple)
    frame.OptionsButton:SetScript("OnEnter",function(self)
        self:SetBackdropColor(0.11,0.035,0.16,1)
        self:SetBackdropBorderColor(0.72,0.28,1.00,1)
        self.Text:SetTextColor(1,0.82,1,1)
    end)
    frame.OptionsButton:SetScript("OnLeave",function(self)
        self:SetBackdropColor(0.045,0.020,0.070,0.98)
        self:SetBackdropBorderColor(0.48,0.15,0.76,1)
        SetColor(self.Text,C.purple)
    end)

    frame.TargetClassIcon=frame:CreateTexture(nil,"OVERLAY")
    frame.TargetClassIcon:SetSize(14,14)
    frame.TargetClassIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    frame.TargetClassIcon:Hide()

    frame.Target=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    frame.Target:SetWidth(86)
    frame.Target:SetJustifyH("LEFT")
    frame.Target:SetShadowOffset(1,-1)
    frame.Target:SetShadowColor(0,0,0,1)
    frame.Target:SetText("No target")
    SetColor(frame.Target,C.white)

    frame.StatusBG=frame:CreateTexture(nil,"ARTWORK")
    frame.StatusBG:SetPoint("TOPLEFT",7,-HEADER_H)
    frame.StatusBG:SetPoint("TOPRIGHT",-7,-HEADER_H)
    frame.StatusBG:SetHeight(STATUS_H)
    frame.StatusBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.StatusBG:SetVertexColor(0.12,0.04,0.16,0.94)

    frame.TargetClassIcon:SetPoint("LEFT",frame.StatusBG,"LEFT",6,0)
    frame.Target:SetPoint("LEFT",frame.TargetClassIcon,"RIGHT",4,0)

    frame.StatusTop=frame:CreateTexture(nil,"OVERLAY")
    frame.StatusTop:SetPoint("TOPLEFT",frame.StatusBG,"TOPLEFT")
    frame.StatusTop:SetPoint("TOPRIGHT",frame.StatusBG,"TOPRIGHT")
    frame.StatusTop:SetHeight(1)
    frame.StatusTop:SetTexture("Interface\\Buttons\\WHITE8X8")
    frame.StatusTop:SetVertexColor(C.purple[1],C.purple[2],C.purple[3],0.42)

    frame.Status=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    frame.Status:SetPoint("LEFT",frame.Target,"RIGHT",4,0)
    frame.Status:SetPoint("RIGHT",frame.StatusBG,"RIGHT",-6,0)
    frame.Status:SetJustifyH("RIGHT")
    frame.Status:SetWordWrap(false)
    frame.Status:SetShadowOffset(1,-1)
    frame.Status:SetShadowColor(0,0,0,1)
    frame.Status:SetText("WAITING")
    SetColor(frame.Status,C.dim)

    frame.Rows={}
    local rowsTop=HEADER_H+STATUS_H+5
    for i=1,MAX_ROWS do
        local row=CreateFrame("StatusBar",nil,frame)
        frame.Rows[i]=row
        row:SetPoint("TOPLEFT",8,-(rowsTop+(i-1)*(ROW_H+ROW_GAP)))
        row:SetPoint("TOPRIGHT",-8,-(rowsTop+(i-1)*(ROW_H+ROW_GAP)))
        row:SetHeight(ROW_H)
        row:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        row:SetMinMaxValues(0,1)

        row.BG=row:CreateTexture(nil,"BACKGROUND")
        row.BG:SetAllPoints()
        row.BG:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.BG:SetVertexColor(0.025,0.016,0.035,0.98)

        row.LeftAccent=row:CreateTexture(nil,"OVERLAY")
        row.LeftAccent:SetPoint("TOPLEFT",row,"TOPLEFT")
        row.LeftAccent:SetPoint("BOTTOMLEFT",row,"BOTTOMLEFT")
        row.LeftAccent:SetWidth(2)
        row.LeftAccent:SetTexture("Interface\\Buttons\\WHITE8X8")

        row.TopSheen=row:CreateTexture(nil,"OVERLAY")
        row.TopSheen:SetPoint("TOPLEFT",row,"TOPLEFT",2,0)
        row.TopSheen:SetPoint("TOPRIGHT",row,"TOPRIGHT",0,0)
        row.TopSheen:SetHeight(1)
        row.TopSheen:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.TopSheen:SetVertexColor(1,1,1,0.12)

        row.IconBG=row:CreateTexture(nil,"ARTWORK")
        row.IconBG:SetSize(20,20)
        row.IconBG:SetPoint("LEFT",2,0)
        row.IconBG:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.IconBG:SetVertexColor(0.08,0.04,0.11,1)

        row.Icon=row:CreateTexture(nil,"OVERLAY")
        row.Icon:SetSize(16,16)
        row.Icon:SetPoint("CENTER",row.IconBG,"CENTER")
        row.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        row.Label=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row.Label:SetPoint("LEFT",row.IconBG,"RIGHT",5,0)
        row.Label:SetPoint("RIGHT",row,"RIGHT",-57,0)
        row.Label:SetJustifyH("LEFT")
        row.Label:SetShadowOffset(1,-1)
        row.Label:SetShadowColor(0,0,0,1)

        row.Time=row:CreateFontString(nil,"OVERLAY","GameFontNormal")
        row.Time:SetPoint("RIGHT",-5,0)
        row.Time:SetWidth(48)
        row.Time:SetJustifyH("RIGHT")
        row.Time:SetShadowOffset(1,-1)
        row.Time:SetShadowColor(0,0,0,1)
        row:Hide()
    end

    frame.OptionsButton:SetScript("OnClick",function()
        EM:ToggleOptions()
    end)

    RestorePosition()
    frame:Hide()
end

local function IsOnNearbyList(e)
    if not e or not e.name or not VoidMark or type(VoidMark.NearbyList)~="table" then return false end
    if VoidMark.NearbyList[e.name] then return true end
    local short=tostring(e.name):match("^([^%-]+)") or tostring(e.name)
    for name in pairs(VoidMark.NearbyList) do
        local nshort=VoidMarkForever.DisplayName(name)
        if nshort==short then return true end
    end
    return false
end

local function CurrentEnemy()
    if testMode then return enemies[testGUID] end
    if hoverGUID and enemies[hoverGUID] then return enemies[hoverGUID] end
    if targetGUID and enemies[targetGUID] then return enemies[targetGUID] end
    if vanishedGUID and vanishUntil and Now()<vanishUntil then
        local e=enemies[vanishedGUID]
        if e and e.class=="ROGUE" and IsOnNearbyList(e) then return e end
    end
    vanishedGUID=nil
    vanishUntil=nil
    return nil
end
local function Remaining(s,def,now)
    -- Enemy Moves answers "when can they use it again?".
    -- ACTIVE is a separate state with its own remaining duration.
    local active=s.activeEnd and s.activeEnd>now
    local activeRemain=active and math.max(0,s.activeEnd-now) or 0
    local cooldownRemain=math.max(0,(s.cooldownEnd or 0)-now)
    return cooldownRemain,active,activeRemain
end
local function BuildRows(e,now)
    local list={}
    if e then
        for key,s in pairs(e.spells or {}) do
            local def=CANON[key]
            if not def and key=="PVP_TRINKET" then def={key=key,name="PvP Trinket",cd=300,active=0,category="utility",color="gray",priority=25} end
            if def then
                local remain,active,activeRemain=Remaining(s,def,now)
                if remain>0 or active then
                    list[#list+1]={
                        state=s,
                        def=def,
                        remain=remain,
                        active=active,
                        activeRemain=activeRemain,
                    }
                end
            end
        end
    end
    table.sort(list,function(a,b)
        if a.active~=b.active then return a.active end
        if (a.def.priority or 50)~=(b.def.priority or 50) then return (a.def.priority or 50)<(b.def.priority or 50) end
        return a.remain<b.remain
    end)
    return list
end
local function ColorFor(def,active)
    if active and def.category=="defensive" then return C.red end
    return C[def.color] or C.purple
end
local function UpdateTarget()
    if testMode then return end
    targetGUID=nil
    if VMAPI.UnitExists("target") and VMAPI.UnitIsPlayer("target") and VMAPI.UnitCanAttack("player","target") then
        targetGUID=VMAPI.UnitGUID("target")
        if vanishedGUID and targetGUID~=vanishedGUID then
            vanishedGUID=nil
            vanishUntil=nil
        end
        local name,realm=VMAPI.UnitName("target")
        if name and realm and realm~="" then name=name.."-"..realm end
        local _,class=VMAPI.UnitClass("target")
        if targetGUID and name then GetEnemy(targetGUID,name,class) end
        LearnTargetPet()
    end
end

function EM:Refresh()
    BuildUI()
    local db=DB()
    if not db.enabled then frame:Hide() return end
    local e=CurrentEnemy()
    if not e then frame:Hide() return end

    local cc=RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
    local shortName=tostring(e.name or "Unknown"):match("^([^%-]+)") or tostring(e.name or "Unknown")
    frame.Target:SetText(shortName)

    if cc then
        frame.Target:SetTextColor(cc.r,cc.g,cc.b,1)
    else
        SetColor(frame.Target,C.white)
    end

    local coords=CLASS_ICON_TCOORDS and e.class and CLASS_ICON_TCOORDS[e.class]
    if coords then
        frame.TargetClassIcon:SetTexCoord(coords[1],coords[2],coords[3],coords[4])
        frame.TargetClassIcon:Show()
    else
        frame.TargetClassIcon:Hide()
    end

    local list=BuildRows(e,Now())
    if #list==0 then
        frame.Status:SetText("NO COOLDOWNS") SetColor(frame.Status,C.dim) frame.StatusBG:SetVertexColor(0.09,0.04,0.12,0.90)
    elseif list[1].active then
        frame.Status:SetText(string.format("ACTIVE: %s (%s)",list[1].def.name,ActiveTime(list[1].activeRemain or 0)))
        local c=list[1].def.category=="defensive" and C.red or C.orange
        SetColor(frame.Status,c) frame.StatusBG:SetVertexColor(c[1]*0.25,c[2]*0.25,c[3]*0.25,0.95)
    else
        frame.Status:SetText(string.format("TRACKING %d COOLDOWN%s",#list,#list==1 and "" or "S"))
        SetColor(frame.Status,C.purple) frame.StatusBG:SetVertexColor(0.12,0.04,0.16,0.92)
    end

    ResizeForRows(math.min(#list,MAX_ROWS))
    for i,row in ipairs(frame.Rows) do
        local item=list[i]
        if item then
            local def,s=item.def,item.state
            local c=ColorFor(def,item.active)
            local total=item.active and math.max((item.state and item.state.activeDuration) or def.active or 1,1)
                or math.max(((item.state and item.state.sharedLockoutEnd) and item.remain<=60.1) and 60 or (def.cd or 1),1)
            local barValue=item.active and math.max(0,item.activeRemain or 0) or item.remain
            row:SetMinMaxValues(0,total)
            row:SetValue(math.min(total,barValue))
            row:SetStatusBarColor(c[1],c[2],c[3],item.active and 0.88 or 0.66)
            row.LeftAccent:SetVertexColor(c[1],c[2],c[3],1)
            row.IconBG:SetVertexColor(c[1]*0.20,c[2]*0.20,c[3]*0.20,0.98)
            row.TopSheen:SetVertexColor(1,1,1,item.active and 0.22 or 0.10)
            if s.lastSpellID and VMAPI.GetSpellTexture then
                local tex=VMAPI.GetSpellTexture(s.lastSpellID)
                if tex then row.Icon:SetTexture(tex) else row.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
            elseif def.key=="POTION" then row.Icon:SetTexture("Interface\\Icons\\INV_Potion_54")
            else row.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
            if item.active then
                row.Label:SetText(string.format("|cffffffff%s|r  |cffff4d5dACTIVE|r |cffffb36b%s|r",def.name,ActiveTime(item.activeRemain or 0)))
            else
                row.Label:SetText("|cfff2edf7"..def.name.."|r")
            end
            row.Time:SetText(ShortTime(item.remain))
            SetColor(row.Time,item.active and C.red or c)
            row:Show()
        else row:Hide() end
    end
    frame:Show()
end

local function EnsureOptions()
    if options then return options end
    options=CreateFrame("Frame","VoidMarkEnemyMovesOptions",UIParent,"BackdropTemplate")
    options:SetSize(270,205) options:SetPoint("CENTER") options:SetFrameStrata("DIALOG") options:SetMovable(true) options:EnableMouse(true)
    options:RegisterForDrag("LeftButton") options:SetScript("OnDragStart",options.StartMoving) options:SetScript("OnDragStop",options.StopMovingOrSizing)
    options:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10})
    options:SetBackdropColor(0.018,0.010,0.026,0.98) options:SetBackdropBorderColor(0.48,0.16,0.72,0.95)
    local title=options:CreateFontString(nil,"OVERLAY","GameFontNormalLarge") title:SetPoint("TOPLEFT",10,-9) title:SetText("ENEMY MOVES OPTIONS") SetColor(title,C.purple)
    local close=CreateFrame("Button",nil,options,"UIPanelCloseButton") close:SetPoint("TOPRIGHT",-3,-3)

    local enabled=CreateFrame("CheckButton",nil,options,"UICheckButtonTemplate")
    enabled:SetPoint("TOPLEFT",12,-42) enabled.Text=options:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    enabled.Text:SetPoint("LEFT",enabled,"RIGHT",3,0) enabled.Text:SetText("Enable Enemy Moves")
    enabled:SetScript("OnClick",function(self) DB().enabled=self:GetChecked() and true or false EM:Refresh() end)
    options.Enabled=enabled

    local lock=CreateFrame("CheckButton",nil,options,"UICheckButtonTemplate")
    lock:SetPoint("TOPLEFT",12,-69) lock.Text=options:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lock.Text:SetPoint("LEFT",lock,"RIGHT",3,0) lock.Text:SetText("Lock position")
    lock:SetScript("OnClick",function(self) DB().locked=self:GetChecked() and true or false end)
    options.Lock=lock

    local function Slider(name,label,minv,maxv,step,y,onchange)
        local s=CreateFrame("Slider",name,options,"OptionsSliderTemplate")
        s:SetPoint("TOPLEFT",22,y) s:SetWidth(220) s:SetMinMaxValues(minv,maxv) s:SetValueStep(step) s:SetObeyStepOnDrag(true)
        local fs=_G[name.."Text"]
        if fs then fs:SetText(label) end
        s:SetScript("OnValueChanged",onchange)
        return s
    end
    options.Scale=Slider("VoidMarkEnemyMovesScale","Scale",0.50,1.50,0.05,-105,function(_,v) DB().scale=v ApplyAppearance() end)
    options.Opacity=Slider("VoidMarkEnemyMovesOpacity","Overall opacity",0.35,1.0,0.05,-150,function(_,v) DB().frameOpacity=v ApplyAppearance() end)
    options:SetScript("OnShow",function()
        local db=DB()
        options.Enabled:SetChecked(db.enabled) options.Lock:SetChecked(db.locked)
        options.Scale:SetValue(db.scale) options.Opacity:SetValue(db.frameOpacity)
    end)
    options:Hide()
    return options
end

function EM:Toggle()
    BuildUI()
    local db=DB()
    if frame:IsShown() then
        db.enabled=false
        frame:Hide()
    else
        db.enabled=true
        UpdateTarget()
        EM:Refresh()
    end
end
function EM:ToggleOptions()
    local f=EnsureOptions()
    if f:IsShown() then f:Hide() else f:Show() end
end
function EM:SetEnabled(v)
    DB().enabled=v and true or false
    if not DB().enabled then
        hoverGUID=nil
        frame:Hide()
    else
        UpdateTarget()
        EM:Refresh()
    end
end

function EM:IsEnabled()
    return DB().enabled and true or false
end

function EM:ToggleEnabled()
    EM:SetEnabled(not EM:IsEnabled())
    return EM:IsEnabled()
end

local function FindEnemyByName(name,guid)
    if guid and enemies[guid] then return guid,enemies[guid] end
    if not name then return nil,nil end
    local short=VoidMarkForever.DisplayName(name)
    for g,e in pairs(enemies) do
        local en=e and e.name
        local es=en and (tostring(en):match("^([^%-]+)") or tostring(en))
        if en==name or es==short then return g,e end
    end
    return nil,nil
end


function EM:HoverPlayer(name,guid)
    if not DB().enabled or testMode then return false end
    local g,e=FindEnemyByName(name,guid)
    if not g or not e then
        if hoverGUID then hoverGUID=nil EM:Refresh() end
        return false
    end
    local rows=BuildRows(e,Now())
    if #rows==0 then
        if hoverGUID then hoverGUID=nil EM:Refresh() end
        return false
    end
    hoverGUID=g
    EM:Refresh()
    return true
end

function EM:ClearHover()
    if not hoverGUID then return end
    hoverGUID=nil
    EM:Refresh()
end

local function IsHostilePlayer(flags)
    if not flags or not bit or not bit.band then return false end
    return bit.band(flags,COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400)~=0
       and bit.band(flags,COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040)~=0
end

local function SamePlayerName(a,b)
    if not a or not b then return false end
    if a==b then return true end
    local as=a:match("^([^%-]+)")
    local bs=b:match("^([^%-]+)")
    return as and bs and as==bs
end
local SHARE_PREFIX="VMEM1"
local recentShares={}

local function RegisterSharePrefix()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix,SHARE_PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix,SHARE_PREFIX)
    end
end

local function SendShareMessage(msg,channel)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        return pcall(C_ChatInfo.SendAddonMessage,SHARE_PREFIX,msg,channel)
    elseif SendAddonMessage then
        return pcall(SendAddonMessage,SHARE_PREFIX,msg,channel)
    end
end

local function ShareChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function BroadcastTracked(ownerGUID,ownerName,ownerClass,spellID,event)
    local channel=ShareChannel()
    if not channel or not ownerGUID or not spellID or not event then return end

    local key=table.concat({tostring(ownerGUID),tostring(spellID),tostring(event)},"|")
    local now=Now()
    if recentShares[key] and now-recentShares[key]<0.15 then return end
    recentShares[key]=now

    local msg=table.concat({
        tostring(ownerGUID),
        tostring(ownerName or ""),
        tostring(ownerClass or ""),
        tostring(spellID),
        tostring(event),
    },"~")
    SendShareMessage(msg,channel)
end

local function ReceiveTrackedMessage(message)
    if type(message)~="string" or #message>255 then return end
    local guid,name,class,spellID,event=message:match("^([^~]+)~([^~]*)~([^~]*)~([^~]+)~([^~]+)$")
    spellID=tonumber(spellID)
    if not guid or guid:sub(1,7)~="Player-" or not spellID or not event then return end
    if not SPELLS[spellID] then return end
    if event~="SPELL_CAST_SUCCESS"
        and event~="SPELL_AURA_APPLIED"
        and event~="SPELL_AURA_REFRESH"
        and event~="SPELL_AURA_REMOVED" then
        return
    end

    local tracked=TrackSpell(guid,name~="" and name or nil,class~="" and class or nil,spellID,nil,event)
    if tracked and (guid==targetGUID or guid==hoverGUID or guid==vanishedGUID or testMode) then
        EM:Refresh()
    end
end


local eventFrame=CreateFrame("Frame")
VoidMarkForever.RegisterEvent(eventFrame,"COMBAT_LOG_EVENT_UNFILTERED")
VoidMarkForever.RegisterEvent(eventFrame,"PLAYER_TARGET_CHANGED")
VoidMarkForever.RegisterEvent(eventFrame,"PLAYER_ENTERING_WORLD")
VoidMarkForever.RegisterEvent(eventFrame,"DUEL_REQUESTED")
VoidMarkForever.RegisterEvent(eventFrame,"DUEL_INBOUNDS")
VoidMarkForever.RegisterEvent(eventFrame,"DUEL_FINISHED")
VoidMarkForever.RegisterEvent(eventFrame,"CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent",function(_,event,...)
    if event=="PLAYER_TARGET_CHANGED" then
        testMode=false
        UpdateTarget()
        -- During a duel, remember the opponent GUID as soon as they are targeted.
        if duelName and VMAPI.UnitExists("target") and VMAPI.UnitIsPlayer("target") then
            local n,r=VMAPI.UnitName("target")
            local full=n
            if n and r and r~="" then full=n.."-"..r end
            if n==duelName or full==duelName then
                duelGUID=VMAPI.UnitGUID("target")
            end
        end
        EM:Refresh()
        return
    end
    if event=="PLAYER_ENTERING_WORLD" then
        RegisterSharePrefix()
        BuildUI()
        UpdateTarget()
        EM:Refresh()
        return
    end
    if event=="CHAT_MSG_ADDON" then
        local prefix,message,channel,sender=...
        local player=VMAPI.UnitName("player")
        local realm=GetRealmName and GetRealmName()
        local fullSelf=player and realm and (player.."-"..realm:gsub("%s", ""))
        if sender==player or sender==fullSelf then return end
        if prefix==SHARE_PREFIX and (channel=="PARTY" or channel=="RAID") and VoidMarkForever.IsGroupSender(sender) then
            ReceiveTrackedMessage(message)
        end
        return
    end
    if event=="DUEL_REQUESTED" then
        duelName=...
        if VMAPI.UnitExists("target") and VMAPI.UnitIsPlayer("target") then
            local n,r=VMAPI.UnitName("target")
            local full=n
            if n and r and r~="" then full=n.."-"..r end
            if n==duelName or full==duelName then duelGUID=VMAPI.UnitGUID("target") end
        end
        return
    end
    if event=="DUEL_INBOUNDS" then
        if not duelGUID and VMAPI.UnitExists("target") and VMAPI.UnitIsPlayer("target") then
            duelGUID=VMAPI.UnitGUID("target")
            local n,r=VMAPI.UnitName("target")
            duelName=n
            if n and r and r~="" then duelName=n.."-"..r end
        end
        return
    end
    if event=="DUEL_FINISHED" then
        duelGUID=nil
        duelName=nil
        return
    end

    local _,subevent,_,sourceGUID,sourceName,sourceFlags,_,destGUID,destName,_,_,spellID,spellName=VMAPI.CombatLogGetCurrentEventInfo()
    if subevent~="SPELL_CAST_SUCCESS"
        and subevent~="SPELL_AURA_APPLIED"
        and subevent~="SPELL_AURA_REFRESH"
        and subevent~="SPELL_AURA_REMOVED"
        and subevent~="SPELL_HEAL"
        and subevent~="SPELL_ENERGIZE" then
        return
    end
    -- Aura removals sometimes omit the original caster. Use the known aura
    -- recipient so an ended buff disappears immediately instead of lingering.
    local removedEnemy = subevent=="SPELL_AURA_REMOVED" and not sourceGUID
        and destGUID and enemies[destGUID]
    if not sourceGUID and not removedEnemy then return end

    local ownerGUID,ownerName,ownerClass
    if removedEnemy then
        ownerGUID,ownerName,ownerClass=destGUID,destName,removedEnemy.class
    elseif IsHostilePlayer(sourceFlags)
        or (duelGUID and sourceGUID==duelGUID)
        or (duelName and SamePlayerName(sourceName,duelName)) then
        if duelName and SamePlayerName(sourceName,duelName) and not duelGUID then
            duelGUID=sourceGUID
        end
        ownerGUID,ownerName,ownerClass=sourceGUID,sourceName,ClassFromGUID(sourceGUID)
    elseif petOwner[sourceGUID] then
        ownerGUID=petOwner[sourceGUID]
        local e=enemies[ownerGUID]
        ownerName=e and e.name
        ownerClass=e and e.class
    elseif targetGUID and sourceGUID==targetGUID then
        ownerGUID=sourceGUID
        local n,r=VMAPI.UnitName("target")
        if n and r and r~="" then n=n.."-"..r end
        ownerName=n or sourceName
        ownerClass=select(2,VMAPI.UnitClass("target")) or ClassFromGUID(sourceGUID)
    else
        return
    end

    local def=SPELLS[spellID]
    if def and def.pet and not petOwner[sourceGUID] and not IsHostilePlayer(sourceFlags) then return end
    local wasCurrentTarget = targetGUID and ownerGUID==targetGUID
    local tracked=TrackSpell(ownerGUID,ownerName,ownerClass,spellID,spellName,subevent)
    if tracked then
        BroadcastTracked(ownerGUID,ownerName,ownerClass,spellID,subevent)
    end

    -- Only Rogues get a post-target-loss grace period, and only when we
    -- actually observe that Rogue Vanish while they are the active target.
    local trackedDef=SPELLS[spellID]
    if tracked and wasCurrentTarget and trackedDef and trackedDef.key=="VANISH" then
        local e=enemies[ownerGUID]
        if e and e.class=="ROGUE" and IsOnNearbyList(e) then
            vanishedGUID=ownerGUID
            vanishUntil=Now()+30
        end
    end

    if DB().debug and tracked then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffb45cff[EnemyMoves]|r %s used %s (%s)",ownerName or "?",spellName or "?",tostring(spellID)))
    elseif DB().debug and IsHostilePlayer(sourceFlags)
        and (subevent=="SPELL_HEAL" or subevent=="SPELL_ENERGIZE")
        and sourceGUID==destGUID then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffb45cff[EnemyMoves RAW]|r %s %s (%s)",subevent,spellName or "?",tostring(spellID)))
    end
    if ownerGUID==targetGUID or ownerGUID==vanishedGUID or testMode then EM:Refresh() end
end)

local lastCacheCleanup=0
local function PruneTrackingCaches(now)
    if now-lastCacheCleanup<30 then return end
    lastCacheCleanup=now
    for key,at in pairs(recentShares) do
        if now-at>5 then recentShares[key]=nil end
    end
    for guid,e in pairs(enemies) do
        if guid~=targetGUID and guid~=hoverGUID and guid~=vanishedGUID and guid~=testGUID
            and now-(e.lastSeen or now)>3600 then
            enemies[guid]=nil
        elseif e.lastEvents then
            for key,at in pairs(e.lastEvents) do
                if now-at>5 then e.lastEvents[key]=nil end
            end
        end
    end
    for pet,owner in pairs(petOwner) do
        if not enemies[owner] and owner~=targetGUID then petOwner[pet]=nil end
    end
end

ticker=C_Timer.NewTicker(0.10,function()
    if not (InCombatLockdown and InCombatLockdown()) then PruneTrackingCaches(Now()) end
    if frame and frame:IsShown() then EM:Refresh() end
    LearnTargetPet()
end)

local function TestStart()
    BuildUI()
    testMode=true
    local e=GetEnemy(testGUID,"Cartach","ROGUE")
    e.spells={}
    e.seen={}
    local function fake(key,remain,id)
        local d=CANON[key]
        local s={key=key,name=d.name,usedAt=Now()-2,cooldownEnd=Now()+remain,lastSpellID=id}
        e.spells[key]=s
        e.seen[key]=true
    end
    fake("BLIND",282,2094)
    fake("VANISH",197,1856)
    fake("KIDNEY_SHOT",14,408)
    fake("KICK",7.2,1766)
    fake("EVASION",171,5277)
    fake("SPRINT",46,2983)
    fake("POTION",83,nil)
    EM:Refresh()
end

SLASH_VOIDMARKENEMYMOVES1="/emoves"
SLASH_VOIDMARKENEMYMOVES2="/enemymoves"
SlashCmdList.VOIDMARKENEMYMOVES=function(msg)
    msg=string.lower(strtrim(msg or ""))
    if msg=="test" then TestStart()
    elseif msg=="options" or msg=="opt" then EM:ToggleOptions()
    elseif msg=="show" then
        DB().enabled=true
        UpdateTarget()
        EM:Refresh()
    elseif msg=="hide" then
        DB().enabled=false
        if frame then frame:Hide() end
    elseif msg=="lock" then DB().locked=true
    elseif msg=="unlock" then DB().locked=false
    elseif msg=="debug" then
        DB().debug=not DB().debug
        DEFAULT_CHAT_FRAME:AddMessage("|cffb45cff[EnemyMoves]|r debug "..(DB().debug and "ON" or "OFF"))
    elseif msg=="reset" then
        local db=DB()
        db.point=nil
        db.relPoint=nil
        db.x=nil
        db.y=nil
        if frame then RestorePosition() frame:Show() end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffb45cffEnemy Moves|r: /emoves test | show | hide | options | lock | unlock | debug | reset")
    end
end

-- Readable UNIT_SPELLCAST/UNIT_AURA observations use the canonical tracker.
function EM:ObserveSpell(guid,name,class,id,event)
    local tracked=TrackSpell(guid,name,class,id,nil,event)
    if not tracked then return false end
    BroadcastTracked(guid,name,class,id,event)
    local def=SPELLS[id]
    if guid==targetGUID and def and def.key=="VANISH" then
        vanishedGUID=guid; vanishUntil=Now()+30
    end
    if guid==targetGUID or guid==hoverGUID or guid==vanishedGUID then self:Refresh() end
    return true
end
