-- Live port: visible combat rows preserve full identities and remain nonsecure.
local oldList=VoidMark.db.profile.CurrentList
VoidMark.db.profile.CurrentList=1
VoidMark.MainWindow:Show()
TEST_IN_COMBAT=true
VoidMark:QueueCombatSighting('Live-One','test')
VoidMark:QueueCombatSighting('Live-Two','test')
local overlay=VoidMark.CombatNearbyRows
assert(overlay and overlay:IsShown())
assert(overlay:GetFrameStrata()=='LOW','Combat rows cover stock windows')
local names={}
for _,row in ipairs(overlay.Rows) do
    if row:IsShown() then names[row.Name:GetText()]=true end
    assert(not next(row.attributes),'Visual row gained secure target attributes')
end
assert(names['Live One'] and names['Live Two'],'Combat names lost their secondary identity')
NOW=NOW+31
VoidMark:UpdateCombatQueueBar()
assert(not overlay:IsShown(),'Expired sightings remain visible')
VoidMark:QueueCombatSighting('Live-Three','test')
VoidMark.MainWindow:Hide()
VoidMark:UpdateCombatQueueBar()
assert(not overlay:IsShown(),'Combat rows remain over a hidden main window')
TEST_IN_COMBAT=false
VoidMark:ClearCombatSightings()
VoidMark.db.profile.CurrentList=oldList

-- An accepted kill recovers a missing timer without replacing a good one.
local rb=VoidMarkRunBack
local outdoor,capture,create=rb.IsOutdoor,rb.CaptureLocation,rb.CreateTimer
rb.IsOutdoor=function()return true end
rb.CaptureLocation=function()return nil,nil,nil end
local created=0
rb.CreateTimer=function(self,r) created=created+1; self.active[r.guid]=r end
local guid='Player-1-livefallback'
rb.active[guid]=nil; rb.lastDeath[guid]=nil
VoidMark:EnsureRunBackForConfirmedKill('Fallback-One',guid)
VoidMark:EnsureRunBackForConfirmedKill('Fallback-One',guid)
assert(created==1,'RunBack fallback duplicated or missed timer')
assert(rb.active[guid].faction=='Alliance','Fallback faction is incorrect')
rb.active[guid]=nil; rb.lastDeath[guid]=nil
rb.IsOutdoor,rb.CaptureLocation,rb.CreateTimer=outdoor,capture,create
local getRecord=VoidMark.GetRunBackRecord
VoidMark.GetRunBackRecord=function()return {readyAt=NOW-20,calc={confidence='UNKNOWN'}} end
assert(VoidMark:GetRunBackDisplay('Fallback-One').time=='GY ?','Unknown position claims immediate return')
VoidMark.GetRunBackRecord=getRecord
-- 1.2.8: normal (non-stealth) detections in combat show too, and anyone
-- already on the Nearby list without a row is shown.
VoidMark.db.profile.CurrentList=1
VoidMark.MainWindow:Show()
TEST_IN_COMBAT=true
local oldNearby=VoidMark.NearbyList
VoidMark.NearbyList={['Chad-Gonk']=NOW,['Allerinut-Goonrunner']=NOW-5}
VoidMark:RefreshCurrentList('Chad-Gonk')
local shown={}
for _,row in ipairs(VoidMark.CombatNearbyRows.Rows) do if row:IsShown() then shown[row.Name:GetText()]=true end end
assert(VoidMark.CombatNearbyRows:IsShown() and shown['Chad Gonk'] and shown['Allerinut Goonrunner'],'combat detections not shown')
-- Still nearby after 30s: the row stays.
NOW=NOW+40;VoidMark:UpdateCombatQueueBar();assert(VoidMark.CombatNearbyRows:IsShown(),'nearby enemy dropped after 30s')
VoidMark.NearbyList={};VoidMark:UpdateCombatQueueBar();assert(not VoidMark.CombatNearbyRows:IsShown(),'gone enemy kept')
TEST_IN_COMBAT=false
VoidMark:ClearCombatSightings()
VoidMark.NearbyList=oldNearby
VoidMark.db.profile.CurrentList=oldList
print('PASS: live combat rows, full names, expiry, hidden window and RunBack fallback; normal combat detections shown')

-- Own stealth (and friendly stealth) must never raise the stealth alert, even
-- when the player/party unit was scanned moments earlier (10s scan cache).
do
    local alerted={}
    local oldStealth,oldProwl,oldPromote=VoidMark.AlertStealthPlayer,VoidMark.AlertProwlPlayer,VoidMark.PromoteStealthPlayer
    VoidMark.AlertStealthPlayer=function(_,name) alerted[#alerted+1]=name end
    VoidMark.AlertProwlPlayer=VoidMark.AlertStealthPlayer
    VoidMark.PromoteStealthPlayer=function(_,name) alerted[#alerted+1]='promote:'..name end
    VoidMarkForever.LastDetection={}
    for _,unit in ipairs({'player','party1'}) do
        VoidMark:ScanUnit(unit)                      -- primes the scan cache
        VoidMark:ForeverSpellcastEvent('UNIT_SPELLCAST_SUCCEEDED',unit,'cast',1784)
        VoidMark:ForeverSpellcastEvent('UNIT_SPELLCAST_SUCCEEDED',unit,'cast',1856)
        VoidMark:ForeverSpellcastEvent('UNIT_SPELLCAST_SUCCEEDED',unit,'cast',5215)
    end
    assert(#alerted==0,'Own/friendly stealth raised an alert: '..tostring(alerted[1]))
    -- A hostile stealth is still reported, including on a cached rescan.
    VoidMarkForever.LastDetection={}
    local ignored=VoidMarkPerCharDB.IgnoreData['Enemy-One']
    VoidMarkPerCharDB.IgnoreData['Enemy-One']=nil
    VoidMark:ScanUnit('target')
    VoidMark:ForeverSpellcastEvent('UNIT_SPELLCAST_SUCCEEDED','target','cast',1784)
    assert(#alerted>=1,'Hostile stealth no longer alerts')
    VoidMarkPerCharDB.IgnoreData['Enemy-One']=ignored
    VoidMark.AlertStealthPlayer,VoidMark.AlertProwlPlayer,VoidMark.PromoteStealthPlayer=oldStealth,oldProwl,oldPromote
    VoidMarkForever.LastDetection={}
end
print('PASS: own and friendly stealth/vanish/prowl never raise the stealth alert')

-- 1.2.9: Forever hides hostility (and sometimes aura ids) in combat. A Paladin
-- bubble must still show on Enemy Moves right away, not after it ends.
do
    local em=VoidMarkEnemyMoves
    em:SetEnabled(true)
    em:ClearHover()
    local oG,oN,oC,oCA,oIE,oA=UnitGUID,UnitName,UnitClass,UnitCanAttack,UnitIsEnemy,UnitAura
    UnitGUID=function(u) if u=="player" then return "Player-1-hero" elseif u=="target" or u=="nameplate1" then return "Player-1-pally" end end
    UnitName=function(u) if u=="player" then return "Hero","One" elseif u=="target" or u=="nameplate1" then return "Asgeirr" end end
    UnitClass=function(u) if u=="player" then return "Priest","PRIEST" end return "Paladin","PALADIN" end
    UnitCanAttack=function() return SECRET end
    UnitIsEnemy=function() return SECRET end
    -- F.API captured the originals at load; point it at the overrides too.
    local api=VoidMarkForever.API
    local savedAPI={}
    for _,n in ipairs({'UnitGUID','UnitName','UnitClass','UnitCanAttack','UnitIsEnemy','UnitAura'}) do
        savedAPI[n]=api[n]
        api[n]=function(...) return VoidMarkForever.Safe(_G[n],...) end
    end
    local auras={}
    UnitAura=function(u,i,filter)
        if u~="target" and u~="nameplate1" then return nil end
        local a=auras[filter] and auras[filter][i]
        if not a then return nil end
        return a.name,nil,0,nil,a.dur,NOW+a.dur,nil,nil,nil,a.id
    end
    TEST_IN_COMBAT=true
    Emit('PLAYER_TARGET_CHANGED')
    -- Divine Protection lands (readable id): frame shows ACTIVE immediately.
    auras.HELPFUL={{name='Divine Protection',dur=8,id=5573}}
    Emit('UNIT_AURA','target')
    local f=VoidMarkEnemyMovesFrame
    assert(f and f:IsShown(),'Bubble in combat did not show Enemy Moves')
    assert(tostring(f.Status:GetText()):find('ACTIVE',1,true),'Bubble not shown as active: '..tostring(f.Status:GetText()))
    -- Shared-lockout rows get the real spell icon, not a question mark.
    for i=1,3 do
        local tex=f.Rows[i].Icon.texture or (f.Rows[i].Icon.GetTexture and f.Rows[i].Icon:GetTexture())
        assert(tex~="Interface\\Icons\\INV_Misc_QuestionMark",'Row '..i..' icon is a question mark')
    end
    -- A hidden aura read mid-bubble is not treated as the bubble ending.
    auras.HELPFUL={{name=SECRET,dur=8,id=SECRET}}
    Emit('UNIT_AURA','target')
    assert(tostring(f.Status:GetText()):find('ACTIVE',1,true),'Hidden aura read ended the bubble')
    UnitGUID,UnitName,UnitClass,UnitCanAttack,UnitIsEnemy,UnitAura=oG,oN,oC,oCA,oIE,oA
    for n,fn in pairs(savedAPI) do api[n]=fn end
    TEST_IN_COMBAT=false
end
-- Forbearance alone (bubble id hidden) still locks all three bubbles for 60s.
do
    local em=VoidMarkEnemyMoves
    assert(em:ObserveSpell('Player-1-pally2','Pally-Two','PALADIN',25771,'SPELL_AURA_APPLIED'),'Forbearance not tracked')
    assert(not em:ObserveSpell('Player-1-hunter2','Hunt-Two','HUNTER',25771,'SPELL_AURA_APPLIED'),'Forbearance on a non-Paladin tracked')
end
print('PASS: bubbles show in combat when hostility/aura ids are hidden; Forbearance fallback; real icons')

-- 1.2.9: a nameplate whose enemy flag is hidden must not be cached as
-- "not an enemy" for 10s; a readable enemy faction detects it right away.
do
    local api=VoidMarkForever.API
    local oIE,apiIE=UnitIsEnemy,api.UnitIsEnemy
    local oF=UnitFactionGroup
    local oCA=UnitCanAttack
    UnitIsEnemy=function() return SECRET end
    UnitCanAttack=UnitIsEnemy
    api.UnitIsEnemy=function(...) return VoidMarkForever.Safe(UnitIsEnemy,...) end
    VoidMarkForever.LastDetection={}
    VoidMarkPerCharDB.IgnoreData['Enemy-One']=nil
    -- Faction hidden too: unknown, so nothing is detected and nothing cached.
    UnitFactionGroup=function() return SECRET end
    assert(VoidMark:ScanUnit('nameplate1')==nil,'Unknown hostility detected')
    assert(VoidMarkForever.LastDetection['Enemy-One']==nil,'Unknown hostility cached for 10s')
    -- Faction readable on the next scan: detected immediately.
    UnitFactionGroup=oF
    assert(VoidMark:ScanUnit('nameplate1')=='Enemy-One','Enemy with hidden flag not detected on next scan')
    UnitIsEnemy,api.UnitIsEnemy,UnitCanAttack=oIE,apiIE,oCA
    VoidMarkForever.LastDetection={}
end
print('PASS: hidden enemy flag is not cached; faction fallback detects at once')

-- 1.2.12: nameplates - enemy players red, NPCs blue, tapped mobs untouched,
-- remembered when Forever hides unit facts in combat; off restores the game's.
do
    local NC=VoidMarkNameplateColors
    assert(NC,'NameplateColors module loaded')
    local oG,oT,oIP=UnitGUID,UnitIsTapDenied,UnitIsPlayer
    local guids={nameplate1='Player-1-enemy',nameplate2='Creature-0-1-2-3-4-5',nameplate3='Creature-0-9-9-9-9-9'}
    UnitGUID=function(u) return guids[u] end
    UnitIsTapDenied=function(u) return u=='nameplate3' end
    local function bar() local b={};function b:SetStatusBarColor(r,g,bb) self.c={r,g,bb} end;return b end
    local p1,p2,p3={unit='nameplate1',healthBar=bar()},{unit='nameplate2',healthBar=bar()},{unit='nameplate3',healthBar=bar()}
    NC.Paint(p1);NC.Paint(p2);NC.Paint(p3)
    assert(p1.healthBar.c and p1.healthBar.c[1]>0.8 and p1.healthBar.c[3]<0.2,'enemy player red')
    assert(p2.healthBar.c and p2.healthBar.c[3]>0.9,'NPC blue')
    assert(not p3.healthBar.c,'tapped mob left gray')
    -- combat hides the GUID: still red (remembered)
    UnitGUID=function() return SECRET end;UnitIsPlayer=function() return SECRET end
    p1.healthBar.c=nil;NC.Paint(p1);assert(p1.healthBar.c and p1.healthBar.c[1]>0.8,'remembered in combat')
    -- Far-away name-only plate: the name gets the color (bar hidden).
    local function txt() local t={};function t:SetTextColor(r,g,b) self.c={r,g,b} end;return t end
    local far={unit='nameplate2',healthBar=bar(),name=txt()};far.healthBar.IsShown=function() return false end
    NC.Paint(far);assert(far.name.c and far.name.c[3]>0.9,'far NPC name blue')
    local near={unit='nameplate2',healthBar=bar(),name=txt()};near.healthBar.IsShown=function() return true end
    NC.Paint(near);assert(not near.name.c,'full plate keeps its white name')
    -- Dropdown picks: purple players, game color for NPCs.
    VoidMark.db.profile.NameplatePlayerColor='purple';VoidMark.db.profile.NameplateNpcColor='game'
    p1.healthBar.c=nil;NC.Paint(p1);assert(p1.healthBar.c[1]==0.64 and p1.healthBar.c[3]==1.00,'purple players')
    p2.healthBar.c=nil;NC.Paint(p2);assert(not p2.healthBar.c,'NPCs: game default')
    assert(NC.Choices().purple=='Purple' and #NC.ORDER==11,'dropdown choices')
    VoidMark.db.profile.NameplatePlayerColor=nil;VoidMark.db.profile.NameplateNpcColor=nil
    -- Gear menu window opens and shows both dropdowns.
    NC.ToggleWindow();assert(NC.window and NC.window:IsShown() and NC.window.player and NC.window.npc,'Nameplate Colors window')
    NC.window.enable:SetChecked(false);NC.window.enable:GetScript('OnClick')(NC.window.enable)
    assert(VoidMark.db.profile.NameplateColors==false,'window checkbox turns it off')
    -- Range and far-away names are game settings.
    local cv={nameplateMaxDistance='20',UnitNameNPC='1'};local oGet,oSet=GetCVar,SetCVar
    GetCVar=function(k) return cv[k] end;SetCVar=function(k,v) cv[k]=(k=='nameplateMaxDistance' and tonumber(v)>41) and '41' or v end
    assert(NC.SetDistance(41)==41 and cv.nameplateMaxDistance=='41','range 41')
    cv.UnitNameEnemyPlayerName='0'
    NC.SetFloatingNamesHidden(true);assert(NC.FloatingNamesHidden() and cv.UnitNameNPC=='0','far names hidden')
    assert(cv.UnitNameEnemyPlayerName=='1' and cv.UnitNameEnemyPetName=='0','far names: players only')
    NC.SetFloatingNamesHidden(false);assert(cv.UnitNameNPC=='1')
    GetCVar,SetCVar=oGet,oSet
    VoidMark.db.profile.NameplateColors=nil;NC.ToggleWindow();assert(not NC.window:IsShown())
    VoidMark.db.profile.NameplateColors=false
    p2.healthBar.c=nil;NC.Paint(p2);assert(not p2.healthBar.c,'off: game colors')
    VoidMark.db.profile.NameplateColors=nil
    UnitGUID,UnitIsTapDenied,UnitIsPlayer=oG,oT,oIP
end
print('PASS: nameplates enemy players red, NPCs blue, tapped gray, remembered in combat, toggle off')

-- 1.2.18: adopted from the Spy port - stealth after the nameplate goes, the loss
-- fallback, the fight map, notes and tags.
do
    local VMF=VoidMarkForever
    local api=VMF.API
    -- Vanish arrives just after the nameplate disappeared: still alerted.
    local got
    local oA,oP=VoidMark.AlertStealthPlayer,VoidMark.PromoteStealthPlayer
    VoidMark.AlertStealthPlayer=function(_,n) got=n end;VoidMark.PromoteStealthPlayer=function() end
    VMF.LastDetection={};VMF.LastDetectionEnemy={}
    assert(VMF.ScanUnit('nameplate1')=='Enemy-One')
    VoidMark:NamePlateEvent('NAME_PLATE_UNIT_REMOVED','nameplate1')
    local oE,aE=UnitExists,api.UnitExists
    UnitExists=function(u) if u=='nameplate1' then return false end return oE(u) end
    api.UnitExists=UnitExists
    VoidMark:ForeverSpellcastEvent('UNIT_SPELLCAST_SUCCEEDED','nameplate1',nil,1856)
    assert(got=='Enemy-One','Vanish after the plate went: no alert')
    got=nil;VoidMark:ForeverSpellcastEvent('UNIT_SPELLCAST_SUCCEEDED','nameplate1',nil,1787)
    assert(got=='Enemy-One','Stealth rank 4 not known')
    got=nil;NOW=NOW+3;VoidMark:ForeverSpellcastEvent('UNIT_SPELLCAST_SUCCEEDED','nameplate1',nil,1856)
    assert(got==nil,'stale plate memory still alerts')
    UnitExists,api.UnitExists=oE,aE
    VoidMark.AlertStealthPlayer,VoidMark.PromoteStealthPlayer=oA,oP

    -- Fight map: a loss is kept with where it happened.
    local oPos=C_Map.GetPlayerMapPosition
    C_Map.GetPlayerMapPosition=function() return {GetXY=function() return 0.4,0.6 end} end
    VoidMarkPerCharDB.Fights={}
    -- Loss fallback: recap names nobody; the one enemy who had us targeted gets it.
    local oU,aU=UnitIsUnit,api.UnitIsUnit
    UnitIsUnit=function(a,b) if a=='nameplate1target' and b=='player' then return true end return a==b end
    api.UnitIsUnit=UnitIsUnit
    VMF.TargetedMe={};VMF.LastDetection={}
    VMF.ScanUnit('nameplate1')
    assert(VMF.TargetedMe['Enemy-One'],'targeting enemy not noted')
    local oR=VMF.ReadDeathRecapKiller;VMF.ReadDeathRecapKiller=function() return nil,nil end
    local rec=VoidMarkPerCharDB.PlayerData['Enemy-One'];local before=rec and tonumber(rec.loses) or 0
    NOW=NOW+10;VMF.TargetedMe['Enemy-One'].at=NOW
    VoidMark:PlayerDeadEvent();Drain()
    rec=VoidMarkPerCharDB.PlayerData['Enemy-One']
    assert(rec and tonumber(rec.loses)==before+1,'sole targeter did not get the loss')
    -- Two targeters: nobody gets it.
    VMF.TargetedMe['Other-Guy']={guid='Player-1-other',at=NOW};NOW=NOW+10
    VMF.TargetedMe['Enemy-One'].at=NOW;VMF.TargetedMe['Other-Guy'].at=NOW
    VoidMark:PlayerDeadEvent();Drain()
    assert(tonumber(VoidMarkPerCharDB.PlayerData['Enemy-One'].loses)==before+1,'two targeters still credited')
    VMF.ReadDeathRecapKiller=oR;UnitIsUnit,api.UnitIsUnit=oU,aU;VMF.TargetedMe={}
    -- A friendly targeting us is never noted.
    local fm=VoidMarkFightMap
    local fights=fm:Store()
    assert(#fights==1 and fights[1].k=='L' and fights[1].n=='Enemy-One' and fights[1].x==0.4 and fights[1].m==1431,'loss not on the fight map')
    fm:Add('W','Enemy-One');assert(fights[2].k=='W')
    assert(#fm:Visible(1431)==2 and #fm:Visible(999)==0,'map filter')
    VoidMark.db.profile.FightMapPeriod='day';NOW=NOW+2*86400
    assert(#fm:Visible(1431)==0,'old fights shown for Last day')
    VoidMark.db.profile.FightMapPeriod='all';assert(#fm:Visible(1431)==2)
    VoidMark.db.profile.FightMapPeriod='off';assert(#fm:Visible(1431)==0)
    VoidMark.db.profile.FightMapPeriod=nil
    C_Map.GetPlayerMapPosition=nil;fm:Add('W','Enemy-One');assert(#fights==2,'fight added without a position')
    C_Map.GetPlayerMapPosition=oPos
    VoidMarkPerCharDB.Fights={}

    -- Notes and tags.
    local PN=VoidMarkPlayerNotes
    PN:SetNote('Enemy-One','  camps the |cffff0000Crossroads|r  ')
    assert(PN:Note('Enemy-One')=='camps the /cffff0000Crossroads/r','note not cleaned')
    PN:SetTag('Enemy-One','rival');assert(PN:Tag('Enemy-One')=='rival')
    assert(PN:Marker('Enemy-One'):find('RaidTargetingIcon_2',1,true),'rival marker')
    local lines={};local tip={AddLine=function(_,t) lines[#lines+1]=t end}
    PN:AddTooltip(tip,'Enemy-One');assert(lines[1]:find('Rival',1,true) and lines[2]:find('Crossroads',1,true))
    PN:SetTag('Enemy-One','bogus');assert(PN:Tag('Enemy-One')=='rival','bad tag accepted')
    PN:SetNote('Enemy-One','');PN:SetTag('Enemy-One',nil)
    assert(VoidMarkDB.PlayerNotes['Enemy-One']==nil,'empty entry kept')
    assert(PN:Marker('Enemy-One')=='')
    PN:SetNote('x',string.rep('a',300))
    assert(#PN:Note('x')==200);PN:SetNote('x','')
end
print('PASS: stealth after plate gone, loss fallback, fight map, notes and tags')

-- 1.2.19: Compact window style - slim 24px bar, rows move up, back to the banner.
do
    local VM=VoidMark.VoidMark
    local f=VoidMark.MainWindow
    assert(VM and f and VM.ApplyStyle,'window style missing')
    f:SetWidth(400)
    VM:SetStyle('compact')
    assert(VoidMark.db.profile.WindowStyle=='compact' and VM:IsCompact())
    assert(VM.HEADER_HEIGHT==22 and VM.ROW_TOP_OFFSET==24,'compact geometry')
    assert(f:GetWidth()<=260,'compact window not narrowed')
    assert(not f.VoidMarkGTCompactTextRight:IsShown(),'second stats block shown in compact')
    assert(f.VoidMarkNextButton:IsShown() and f.VoidMarkPrevButton:IsShown(),'list arrows')
    TaliaaGankTracker.totalKills=3;TaliaaGankTracker.currentStreak=2;TaliaaGankTracker:RefreshVoidMarkCompact()
    assert(f.VoidMarkGTCompactTextLeft:GetText()=='K 3  K/S 2','compact stats: '..tostring(f.VoidMarkGTCompactTextLeft:GetText()))
    local cur=VoidMark.db.profile.CurrentList;f.VoidMarkNextButton:GetScript('OnClick')()
    assert(VoidMark.db.profile.CurrentList==(cur%5)+1,'next list');VoidMark.db.profile.CurrentList=cur
    assert(f.VoidMarkCompactHood and f.VoidMarkCompactHood:IsShown(),'hood icon')
    assert(not f.VoidMarkGeneratedHeader:IsShown(),'banner still shown in compact')
    VM:SetStyle('bogus');assert(VM:IsCompact(),'bad style accepted')
    -- In combat the change waits for combat to end (secure rows).
    TEST_IN_COMBAT=true
    VM:SetStyle('banner')
    assert(VM.ROW_TOP_OFFSET==24 and VM.StylePending,'style moved secure rows in combat')
    TEST_IN_COMBAT=false
    VM.StyleWaiter:GetScript('OnEvent')(VM.StyleWaiter,'PLAYER_REGEN_ENABLED')
    assert(VM.HEADER_HEIGHT==106 and VM.ROW_TOP_OFFSET==108,'banner geometry')
    assert(f.VoidMarkGeneratedHeader:IsShown() and not f.VoidMarkCompactHood:IsShown(),'banner back')
    assert(f:GetWidth()>=300,'banner width not restored')
    TaliaaGankTracker:RefreshVoidMarkCompact()
    assert(not tostring(f.VoidMarkGTCompactTextRight:GetText()):find('DK',1,true),'DK still shown')
    VoidMark.db.profile.WindowStyle=nil
end
print('PASS: Compact / Banner window style')
