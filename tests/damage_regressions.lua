-- Forever Damage Records: combat log is secret/unavailable, so damage is read from
-- UNIT_COMBAT on the target and attributed to the player's own cast/channel/melee.
local DR=VoidMarkDamageRecords
local function rec(key) return VoidMarkDB.VoidMarkDamageRecords.characters['Hero-One-TestRealm'].records[key] end
local function eq(a,b,m) if a~=b then error((m or 'mismatch')..': expected '..tostring(b)..', got '..tostring(a),2) end end
local oldGroup,oldCurrent,oldCanAttack=IsInGroup,IsCurrentSpell,UnitCanAttack
CLEU=nil                       -- Forever: CombatLogGetCurrentEventInfo errors / is secret
NOW=NOW+60                     -- well past any readable combat-log hit from earlier tests
local solo=true; IsInGroup=function() return not solo end
local melee=false; IsCurrentSpell=function(id) return id==6603 and melee end

-- Instant/cast spell: first hit after the cast is ours, a second hit is not.
Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-1',10947)
Emit('UNIT_COMBAT','target','WOUND','',1500,32)
eq(rec('SPELL:10947') and rec('SPELL:10947').amount,1500,'cast hit not recorded')
eq(rec('SPELL:10947').character,'Hero One','record must use the full Forever name')
eq(rec('SPELL:10947').targetName,'Enemy-One','target stored by full name')
Emit('UNIT_COMBAT','target','WOUND','',9999,32)
eq(rec('SPELL:10947').amount,1500,'second hit after one cast was credited')
-- Outside the travel window, with no melee, nothing is credited.
Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-2',10948)
NOW=NOW+2
Emit('UNIT_COMBAT','target','WOUND','',4321,32)
assert(not rec('SPELL:10948'),'late hit credited to an old cast')
-- Crits are flagged.
Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-3',10949)
Emit('UNIT_COMBAT','target','WOUND','CRITICAL',2100,32)
eq(rec('SPELL:10949').critical,true,'crit flag lost')

-- Channel (Mind Flay): every tick while solo; channel stop ends credit.
Emit('UNIT_SPELLCAST_CHANNEL_START','player','ch-1',15407)
Emit('UNIT_COMBAT','target','WOUND','',300,32)
Emit('UNIT_COMBAT','target','WOUND','',450,32)
eq(rec('SPELL:15407').amount,450,'channel ticks not recorded')
Emit('UNIT_SPELLCAST_CHANNEL_STOP','player','ch-1',15407)
Emit('UNIT_COMBAT','target','WOUND','',999,32)
eq(rec('SPELL:15407').amount,450,'hit after channel stop credited')

-- In a group only the first tick of a channel counts.
solo=false
Emit('UNIT_SPELLCAST_CHANNEL_START','player','ch-2',18807)
Emit('UNIT_COMBAT','target','WOUND','',500,32)
Emit('UNIT_COMBAT','target','WOUND','',800,32)
eq(rec('SPELL:18807').amount,500,'grouped channel credited other players hits')
Emit('UNIT_SPELLCAST_CHANNEL_STOP','player','ch-2',18807)
-- Grouped melee is never guessed.
melee=true
Emit('UNIT_COMBAT','target','WOUND','',3333,1)
assert(not rec('SWING') or rec('SWING').amount~=3333,'grouped melee guessed')
-- Solo melee is credited.
solo=true
Emit('UNIT_COMBAT','target','WOUND','',710,1)
eq(rec('SWING') and rec('SWING').amount>=710,true,'solo melee not recorded')
melee=false

-- Non-damage actions and other units are ignored.
Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-4',10950)
Emit('UNIT_COMBAT','target','HEAL','',5000,2)
Emit('UNIT_COMBAT','player','WOUND','',5000,1)
assert(not rec('SPELL:10950'),'heal or self damage recorded')
-- Friendly target ignored.
UnitCanAttack=function() return false end
Emit('UNIT_COMBAT','target','WOUND','',6000,32)
assert(not rec('SPELL:10950'),'friendly target damage recorded')
UnitCanAttack=oldCanAttack

-- Secret damage values: no crash, nothing recorded, window explains it.
Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-5',10951)
Emit('UNIT_COMBAT','target','WOUND','',SECRET,32)
assert(not rec('SPELL:10951'),'secret amount recorded')
eq(DR.hidden,true,'hidden values not detected')
DR:Toggle(); DR:Refresh()
assert(VoidMarkDamageRecordsFrame.Source:GetText():find('Tracking: hits on your target'),'source line missing')

-- A readable combat log still wins and is not double-counted by the fallback.
CLEU={NOW,'SPELL_DAMAGE',false,'Player-1-hero','Hero-One',0,0,'Creature-1-x','Boar',0,0,10952,'Spell10952',32,777,0,0,0,0,0,false}
VoidMarkForever.ProbeCombatLog()
Emit('COMBAT_LOG_EVENT_UNFILTERED')
eq(rec('SPELL:10952').amount,777,'combat log path broken')
Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-6',10953)
Emit('UNIT_COMBAT','target','WOUND','',888,32)
assert(not rec('SPELL:10953'),'fallback double-counted while combat log works')
eq(DR.source,'combatlog','source should be combat log')
CLEU=nil

IsInGroup,IsCurrentSpell=oldGroup,oldCurrent
print('PASS: Forever damage records from target damage (casts, channels, melee, groups, secrets, no double count)')
-- Probe must run safely even when the client blocks everything.
local printed={}
local oldAdd=DEFAULT_CHAT_FRAME.AddMessage
DEFAULT_CHAT_FRAME.AddMessage=function(_,m) printed[#printed+1]=m end
CLEU=nil
SlashCmdList.VOIDMARKDAMAGE('probe')
local text=table.concat(printed,'\n')
assert(text:find('combat log getter: blocked'),'probe did not report blocked combat log')
assert(text:find('Listening 25 seconds'),'probe did not arm listeners')
DEFAULT_CHAT_FRAME.AddMessage=oldAdd
print('PASS: /vmdmg probe reports client capabilities without errors')
