local GT=TaliaaGankTracker
local F=VoidMarkForever
local warnings, sounds, chats, addonMessages, bnMessages, timers={}, {}, {}, {}, {}, {}
local oldNotice,oldSound,oldChat=RaidNotice_AddMessage,PlaySound,DEFAULT_CHAT_FRAME.AddMessage
local oldSend,oldAfter=C_ChatInfo.SendAddonMessage,C_Timer.After
RaidNotice_AddMessage=function(_,text) warnings[#warnings+1]=text end
PlaySound=function(id,channel) sounds[#sounds+1]={id=id,channel=channel} end
DEFAULT_CHAT_FRAME.AddMessage=function(_,text) chats[#chats+1]=text end
C_ChatInfo.SendAddonMessage=function(prefix,payload,channel)
    addonMessages[#addonMessages+1]={prefix=prefix,payload=payload,channel=channel}
end
BNSendGameData=function(id,prefix,payload)
    bnMessages[#bnMessages+1]={id=id,prefix=prefix,payload=payload}
end
C_Timer.After=function(delay,fn) timers[#timers+1]={delay=delay,fn=fn} end
local function eq(a,b,label) assert(a==b,label..": "..tostring(a).." ~= "..tostring(b)) end
local function packet(fields) return table.concat(fields,"\031") end

-- Native visible-unit spells work even when CLEU is unavailable. Both paths
-- share the cooldown, complete name and setting; allies/secret IDs stay silent.
CLEU=nil
GT:SetDistractAlertEnabled(true)
Emit("UNIT_SPELLCAST_SUCCEEDED","target","cast",1725)
eq(#warnings,1,"native Distract warning")
assert(warnings[1]:find("Enemy One",1,true),"Distract lost the secondary name")
eq(sounds[1].channel,"Master","Distract sound channel")
Emit("UNIT_SPELLCAST_SUCCEEDED","target","duplicate",1725)
eq(#warnings,1,"native duplicate")
NOW=NOW+4
Emit("UNIT_SPELLCAST_SUCCEEDED","player","friendly",1725)
Emit("UNIT_SPELLCAST_SUCCEEDED","target","secret",SECRET)
eq(#warnings,1,"friendly or secret cast alerted")
GT:ToggleDistractAlertEnabled()
Emit("UNIT_SPELLCAST_SUCCEEDED","target","disabled",1725)
eq(#warnings,1,"disabled Distract alerted")
GT:ToggleDistractAlertEnabled()
COMBATLOG_OBJECT_REACTION_HOSTILE=0x40
CLEU={NOW,"SPELL_CAST_SUCCESS",false,"Player-1-rogue","Sneaky-Two",0x40,0,"","",0,0,1725,"Distract",1}
F.ProbeCombatLog()
Emit("COMBAT_LOG_EVENT_UNFILTERED")
eq(#warnings,2,"readable CLEU Distract warning")
assert(warnings[2]:find("Sneaky Two",1,true),"CLEU warning lost full name")
NOW=NOW+4
CLEU[6]=0x10
Emit("COMBAT_LOG_EVENT_UNFILTERED")
eq(#warnings,2,"friendly CLEU alerted")
CLEU[6]=0x40; CLEU[12]=SECRET
Emit("COMBAT_LOG_EVENT_UNFILTERED")
eq(#warnings,2,"secret CLEU alerted")
CLEU=nil

-- KOS matches use complete identities, combine names/classes for 10 seconds,
-- keep requester-only guild checks private, and validate group senders.
local db=VoidMarkDB.VoidMarkKOSWho
local kos=VoidMarkPerCharDB.KOSData
local players=VoidMarkPerCharDB.PlayerData
kos["Enemy-One"]=true; kos["Enemy-Two"]=nil
players["Enemy-One"].reason={custom="Camped me"}
local before=#chats
VoidMarkKOS_OnWhoResult("Enemy-Two",60,"Hunter","Duskwood")
VoidMarkKOS_OnWhoResult("Enemy",60,"Hunter","Duskwood")
VoidMarkKOS_OnWhoResult(SECRET,60,"Hunter","Duskwood")
eq(#chats,before,"KOS matched incomplete or different secondary name")
VoidMarkKOS_OnWhoResult("Enemy-One",60,"Hunter","Duskwood")
eq(#chats,before+1,"local WHO KOS alert")
local banner=VoidMarkKOSWhoBanner
assert(banner:IsShown() and banner.Text:GetText():find("Enemy One (Hunter)",1,true),"KOS banner missing name/class")
eq(timers[#timers].delay,10,"KOS banner duration")
eq(#addonMessages,1,"KOS local match share")
eq(addonMessages[1].channel,"PARTY","KOS share channel")
assert(not addonMessages[1].payload:find("Camped me",1,true),"KOS reason shared by default")
VoidMarkKOS_OnWhoResult("Enemy-One",60,"Hunter","Duskwood")
eq(#chats,before+1,"WHO duplicate not suppressed")
eq(#addonMessages,1,"WHO duplicate share")
kos["Second-One"]=true; players["Second-One"]={}
VoidMarkKOS_OnWhoResult("Second-One",60,"Mage","Duskwood")
assert(banner.Text:GetText():find(", YOUR KOS: Second One (Mage)",1,true),"simultaneous KOS names not combined")
local oldTimer=timers[#timers-1].fn
oldTimer()
assert(banner:IsShown(),"stale timer hid newer KOS banner")
timers[#timers].fn()
assert(not banner:IsShown(),"KOS banner failed to expire")

IsInGuild=function() return true end
kos["Guild-One"]=true; players["Guild-One"]={}
before=#addonMessages
Emit("CHAT_MSG_ADDON","VMKOS1",packet({"G","Duskwood","Guild-One","60","Priest"}),"WHISPER","Friend-One")
assert(banner.Text:GetText():find("Guild One (Priest)",1,true),"requester-only guild KOS alert missing")
eq(#addonMessages,before,"private guild KOS redistributed")
before=#chats
Emit("CHAT_MSG_ADDON","VMKOS1",packet({"K","Other-One","60","Rogue","Duskwood",""}),"PARTY","Friend-Two")
Emit("CHAT_MSG_ADDON","VMKOS1",packet({"K","Other-One","60","Rogue","Duskwood",""}),"PARTY","Hero-One")
Emit("CHAT_MSG_ADDON","VMKOS1",SECRET,"PARTY","Friend-One")
eq(#chats,before,"unverified/self/secret share alerted")
Emit("CHAT_MSG_ADDON","VMKOS1",packet({"K","Other-One","60","Rogue","Duskwood",""}),"PARTY","Friend-One")
eq(#chats,before+1,"verified party KOS share missing")
assert(chats[#chats]:find("Friend One's KOS",1,true),"party owner name shortened")
SlashCmdList.VOIDMARKWHO("off")
before=#chats
VoidMarkKOS_OnWhoResult("Enemy-One",60,"Hunter","Redridge")
eq(#chats,before,"disabled KOS alerted")
SlashCmdList.VOIDMARKWHO("on")

-- Upgrade discards old peer links without touching kill history. Explicit
-- two-sided pairing still works; background and unsolicited probes do not.
local repo=TaliaaGankRepository
local sync=VoidMarkDB.TaliaaGankSync
eq(sync.pairConsentVersion,2,"pairing migration")
eq(sync.autoPair,false,"automatic pairing remained enabled")
assert(not sync.peerGameAccountID and not sync.peerSessionToken
    and not sync.peerName and not sync.peerBattleTag and not sync.lastKnownPeerGameAccountID,
    "legacy external account pairing survived upgrade")
local history=repo:GetHistoricalCount("Enemy-One","Player-1-enemy")
assert(not repo:StartPairing(true),"background pairing started")
local probe=packet({"P","nonce","Remote-Two","node","remote-session","77"})
Emit("BN_CHAT_MSG_ADDON","TGANK2",probe,77)
eq(#bnMessages,0,"unsolicited pair probe got a reply")
assert(not sync.peerGameAccountID,"unsolicited peer was linked")
assert(repo:StartPairing(false),"manual pairing unavailable")
Emit("BN_CHAT_MSG_ADDON","TGANK2",probe,77)
eq(sync.peerGameAccountID,77,"explicit pair failed")
eq(sync.peerSessionToken,"remote-session","explicit peer session missing")
repo:Unpair()
assert(not sync.peerGameAccountID and not sync.lastKnownPeerGameAccountID,"unpair retained peer link")
eq(repo:GetHistoricalCount("Enemy-One","Player-1-enemy"),history,"pairing migration changed history")

-- Suppressing the damage popup still records/announces new personal records.
VoidMarkDamageRecords:Toggle()
local damageFrame=VoidMarkDamageRecordsFrame
local damage=VoidMarkDB.VoidMarkDamageRecords
if damage.showPopup then damageFrame.PopupButton:GetScript("OnClick")() end
eq(damage.showPopup,false,"popup toggle off")
local popup
for _,frame in ipairs(TEST_FRAMES) do
    if rawget(frame,"Title") and frame.Title:GetText()=="NEW HIGH HIT" then popup=frame end
end
assert(popup and not popup:IsShown(),"toggle did not hide active popup")
CLEU={NOW,"SPELL_DAMAGE",false,"Player-1-hero","Hero-One",0,0,"Creature-1-x","Boar",0,0,8092,"Mind Blast",32,1200,0,0,0,0,0,false}
F.ProbeCombatLog()
Emit("COMBAT_LOG_EVENT_UNFILTERED")
eq(damage.characters["Hero-One-TestRealm"].records["SPELL:8092"].amount,1200,"popup off disabled damage tracking")
assert(not popup:IsShown(),"popup off still displayed a banner")
damageFrame.PopupButton:GetScript("OnClick")()
CLEU[15]=1300
Emit("COMBAT_LOG_EVENT_UNFILTERED")
assert(popup:IsShown(),"popup on did not display new record")
CLEU=nil
assert(VoidMarkEnemyMovesFrame:GetFrameStrata()=="LOW","Enemy Moves can cover stock bags")

-- Equipment calls can fail while Sapped outside combat. Retain the pending
-- request and retry from UNIT_AURA, marking success only after real equipment.
local gear=TaliaasRideOrDie
gear.db.sets.PvP={[1]="item:123"}; gear.db.defaultGroundSet="PvP"
TEST_EQUIP_BLOCKED=true
assert(not gear:EquipSet("PvP",true),"blocked swap reported success")
eq(gear.db.pendingGroundSet,"PvP","blocked swap discarded pending set")
timers={}; gear.gearRecheckScheduled=nil
gear:GetScript("OnEvent")(gear,"UNIT_AURA","player")
gear:QueueGearRecheck()
eq(#timers,1,"gear rechecks must coalesce")
TEST_EQUIP_BLOCKED=false
timers[1].fn()
eq(TEST_INVENTORY[1],"item:123","post-Sap gear not restored")
assert(not gear.db.pendingGroundSet and not gear.db.pendingMode,"successful swap retained pending state")
TEST_INVENTORY[1]=nil; TEST_IN_COMBAT=true
local attempts=TEST_EQUIP_ATTEMPTS
gear:QueueGearRecheck(); timers[#timers].fn()
eq(TEST_EQUIP_ATTEMPTS,attempts,"gear retry equipped in combat")
TEST_IN_COMBAT=false

RaidNotice_AddMessage=oldNotice; PlaySound=oldSound; DEFAULT_CHAT_FRAME.AddMessage=oldChat
C_ChatInfo.SendAddonMessage=oldSend; C_Timer.After=oldAfter
print("PASS: native/CLEU Distract, full-name KOS/privacy, pairing upgrade, popup control, frame layering and post-Sap gear recovery")
