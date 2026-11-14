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
