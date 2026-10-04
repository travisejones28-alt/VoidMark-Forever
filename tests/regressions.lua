assert(TaliaaGankRepository:CanonicalPlayerName('Enemy-One')~=TaliaaGankRepository:CanonicalPlayerName('Enemy-Two'),'Secondary names merged')
assert(VoidMarkForever.IsGroupSender('Friend-One'))
assert(not VoidMarkForever.IsGroupSender('Stranger-One'))
VoidMark:ScanUnit('target')
local before=TaliaaGankTracker.totalKills
VoidMarkForever.HandlePartyKill('Player-1-hero','Player-1-enemy')
Drain()
NOW=NOW+1
Tick(1)
local accepted=TaliaaGankTracker.totalKills
assert(accepted==before+1,'Native kill not recorded')
VoidMarkForever.HandlePartyKill('Player-1-hero','Player-1-enemy')
assert(TaliaaGankTracker.totalKills==accepted,'Duplicate kill counted')
NOW=NOW+10
VoidMarkForever.HandlePartyKill('Player-1-hero','Player-1-enemy',true)
assert(TaliaaGankTracker.totalKills==accepted,'Unconscious kill counted')
VoidMarkForever.HandlePartyKill('Player-1-stranger','Player-1-enemy')
assert(TaliaaGankTracker.totalKills==accepted,'Non-group kill counted')
local d=VoidMarkPerCharDB.PlayerData['Enemy-One']
assert(d.wins>=1,'Canonical W/L missing')
VoidMarkForever.RecordLoss('Enemy-One','Player-1-enemy')
local loses=d.loses
VoidMarkForever.RecordLoss('Enemy-One','Player-1-enemy')
assert(d.loses==loses,'Duplicate loss counted')
-- Recording damage requires a readable combat event attributable to this player.
CLEU={NOW,'SPELL_DAMAGE',false,'Player-1-hero','Hero-One',0,0,'Creature-1-x','Boar',0,0,8092,'Mind Blast',32,911,0,0,0,0,0,false}
VoidMarkForever.ProbeCombatLog()
Emit('COMBAT_LOG_EVENT_UNFILTERED')
local damage=VoidMarkDB.VoidMarkDamageRecords
assert(damage.characters['Hero-One-TestRealm'].records['SPELL:8092'].amount==911,'Damage record absent')
local namefn=UnitName
UnitName=function(u)if u=='player' then return 'Rogue','Two' end return namefn(u)end
CLEU[12]=1752;CLEU[13]='Sinister Strike';CLEU[15]=500
Emit('COMBAT_LOG_EVENT_UNFILTERED')
assert(not damage.characters['Rogue-Two-TestRealm'].records['SPELL:8092'],'Character damage records leaked')
CLEU[12]=SECRET
Emit('COMBAT_LOG_EVENT_UNFILTERED')
assert(not VoidMarkForever.Capabilities.combatLog,'Secret event accepted')
UnitName=namefn
-- Stale UI scores are reconciled from the existing history on the next sighting.
d.wins=0
VoidMarkForever.LastDetection['Enemy-One']=nil
VoidMark:ScanUnit('target')
assert(d.wins==TaliaaGankRepository:GetHistoricalCount('Enemy-One','Player-1-enemy'),'Initial sighting retained stale W/L')
local em=VoidMarkEnemyMoves
assert(em:ObserveSpell('Player-1-enemy','Enemy-One','ROGUE',408,'SPELL_CAST_SUCCESS'))
assert(not em:ObserveSpell('Player-1-enemy','Enemy-One','ROGUE',408,'SPELL_CAST_SUCCESS'),'Duplicate cooldown event accepted')
NOW=NOW+1
assert(em:ObserveSpell('Player-1-enemy','Enemy-One','ROGUE',14185,'SPELL_CAST_SUCCESS'),'Preparation missing')
assert(em:ObserveSpell('Player-1-enemy','Enemy-One','ROGUE',1856,'SPELL_CAST_SUCCESS'),'Vanish missing')
assert(not em:ObserveSpell('Player-1-enemy','Enemy-One','ROGUE',99999999,'SPELL_CAST_SUCCESS'),'Unknown spell accepted')
local acceptedBeforeFeign=TaliaaGankTracker.totalKills
TaliaaGankTracker:HandleHunterFeign('Player-1-enemy','Enemy-One')
assert(TaliaaGankTracker.totalKills==acceptedBeforeFeign,'Feign mutated kills')
local timersBefore=NAMESPACE.metrics.deaths
VoidMarkForever.HandlePartyKill('Player-1-hero','Player-1-enemy',true)
assert(NAMESPACE.metrics.deaths==timersBefore,'Feign created RunBack timer')
VoidMarkForever.AddInternalAlert('Friend One logged out.')
assert(VoidMarkDB.VoidMarkInternalAlerts[#VoidMarkDB.VoidMarkInternalAlerts].text=='Friend One logged out.')
VoidMarkForever.ShowAlertHistory()
-- KOS survives repeated initialization of the canonical shared view.
VoidMark:ToggleKOSPlayer(true,'Enemy-One')
VoidMark:CheckDatabase()
VoidMark:CheckDatabase()
assert(VoidMarkPerCharDB.KOSData['Enemy-One'],'KOS migration erased data')
VoidMark.ButtonName[1]='Enemy-One'
local row=VoidMark.MainWindow.Rows[1]
row.id=1;row.Name='Enemy-One'
VoidMark:ButtonClicked(row,'LeftButton')
IsControlKeyDown=function()return true end
VoidMark:ButtonClicked(row,'LeftButton')
assert(VoidMarkPerCharDB.IgnoreData['Enemy-One'],'Control-click lost handler arguments')
IsControlKeyDown=function()return false end
VoidMark:ButtonClicked(row,'RightButton')
assert(VoidMark.VoidMark.ContextMenu:IsShown(),'Native row action menu unavailable')
