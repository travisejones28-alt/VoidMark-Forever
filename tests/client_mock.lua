NAMESPACE={}
NOW=100
SECRET={secret=true}
CLEU=nil
function issecretvalue(v) return v==SECRET end
unpack=unpack or table.unpack
bit={band=function(a,b) local r,p=0,1 while a>0 and b>0 do local x,y=a%2,b%2;if x==1 and y==1 then r=r+p end;a=math.floor(a/2);b=math.floor(b/2);p=p*2 end return r end}
bit.bor=function(a,b) return a+b-bit.band(a,b) end
function GetTime()return NOW end
function time()return 1800000000+NOW end
function date(f,t)return os.date(f,t or time()) end
GetServerTime=time
function GetGameTime()return 12,0 end
function GetBuildInfo()return "1.60.1","69913","",16001 end
function GetRealmName()return "TestRealm" end
function GetExpansionLevel()return 0 end
function InCombatLockdown()return false end
function IsInInstance()return false,"none" end
function IsInGroup()return true end
function IsInRaid()return false end
function GetZoneText()return "Duskwood" end
function GetSubZoneText()return "Raven Hill" end
function GetZonePVPInfo()return "contested" end
function GetNetStats()return 0,0,10,10 end
function GetCVar()return "1" end
function GetNumGroupMembers()return 2 end
function UnitName(u) if u=="player" then return "Hero","One" elseif u=="party1" then return "Friend","One" elseif u=="target" or u=="mouseover" or u=="nameplate1" then return "Enemy","One" end end
function UnitGUID(u) if u=="player" then return "Player-1-hero" elseif u=="party1" then return "Player-1-friend" elseif u=="target" or u=="mouseover" or u=="nameplate1" then return "Player-1-enemy" end end
function UnitExists(u)return UnitGUID(u)~=nil end
UnitIsPlayer=UnitExists
function UnitIsEnemy(_,u)return u=="target" or u=="mouseover" or u=="nameplate1" end
UnitCanAttack=UnitIsEnemy
function UnitClass(u)return "Hunter","HUNTER" end
function UnitRace()return "Human","Human" end
function UnitLevel()return 60 end
function UnitFactionGroup(u)return u=="player" and "Horde" or "Alliance" end
function UnitIsPVP()return true end
function UnitIsDeadOrGhost()return false end
function UnitIsFeignDeath()return false end
function UnitHealth()return 5000 end
function UnitHealthMax()return 5000 end
function UnitPosition()return 0,0,0,0 end
function GetGuildInfo()return "Test" end
function GetPlayerInfoByGUID(g)if g=="Player-1-enemy" then return "Hunter","HUNTER","Human","Human",2,"Enemy","One" end end
function CombatLogGetCurrentEventInfo()if CLEU then return unpack(CLEU) end error("restricted combat log") end
function UnitAura()return nil end
function GetSpellInfo(id)return "Spell"..tostring(id),nil,123 end
function GetSpellTexture()return 123 end
function GetSpellCooldown()return 0,0,1 end
function GetAddOnMetadata(_,key)return key=="Version" and "1.0.0" or "VoidMark" end
function GetNumFriends()return 0 end
function GetFriendInfo()return nil end
local frames={}
local obj
obj=function(name)
 local t={name=name,shown=false,scripts={},events={},width=300,height=100,attributes={}}
 return setmetatable(t,{__index=function(self,k)
  local methods={
   SetScript=function(s,key,fn)s.scripts[key]=fn end,GetScript=function(s,key)return s.scripts[key] end,
   RegisterEvent=function(s,e,handler)s.events[e]=handler or true end,UnregisterEvent=function(s,e)s.events[e]=nil end,UnregisterAllEvents=function(s)s.events={}end,
   Show=function(s)s.shown=true end,Hide=function(s)s.shown=false end,IsShown=function(s)return s.shown end,IsEnabled=function()return true end,
   GetName=function(s)return s.name end,GetParent=function(s)return s.parent or UIParent end,
   GetWidth=function(s)return s.width end,GetHeight=function(s)return s.height end,
   SetWidth=function(s,n)s.width=n end,SetHeight=function(s,n)s.height=n end,SetSize=function(s,w,h)s.width=w;s.height=h end,
   GetPoint=function()return "CENTER",UIParent,"CENTER",0,0 end,GetEffectiveScale=function()return 1 end,
   GetScale=function()return 1 end,GetAlpha=function()return 1 end,GetFrameLevel=function()return 1 end,
   GetLeft=function()return 0 end,GetRight=function()return 300 end,GetTop=function()return 500 end,GetBottom=function()return 0 end,
   GetFont=function()return "font",12,"" end,GetStringWidth=function()return 100 end,GetText=function(s)return s.text or "" end,
   SetText=function(s,v)s.text=v end,GetFontString=function(s)s.fs=s.fs or obj();return s.fs end,
   SetAttribute=function(s,k,v)s.attributes[k]=v end,GetAttribute=function(s,k)return s.attributes[k] end,
   CreateTexture=function(_,n)return obj(n) end,CreateFontString=function(_,n)return obj(n) end,
   GetNumPoints=function()return 1 end,GetChecked=function()return false end,GetValue=function()return 1 end,
   GetRegions=function()return obj(),obj(),obj() end,GetChildren=function()return obj(),obj() end,
  }
  if methods[k] then rawset(self,k,methods[k]);return methods[k] end
  local method=false
  for _,prefix in ipairs({'Set','Get','Enable','Disable','Register','Unregister','Clear','Start','Stop','Lock','Unlock','Hide','Show','Is','Create','Hook','Update','Refresh','New','Add','Fetch','Notify'})do if k:sub(1,#prefix)==prefix then method=true end end
  if rawget(self,"isaddon") and not method then return nil end
  if k:match('^[A-Z]') and (not method or k:match('Button$') or k:match('Frame$') or k:match('Label$')) then
   local child=obj();rawset(self,k,child);return child
  end
  if not method then return nil end
  local fn=function()end;rawset(self,k,fn);return fn
 end})
end
function CreateFrame(kind,name,parent,template)
 local t=obj(name);t.parent=parent;frames[#frames+1]=t;if name then _G[name]=t end;return t
end
UIParent=CreateFrame('Frame','UIParent');Minimap=CreateFrame('Frame','Minimap');GameTooltip=CreateFrame('Frame','GameTooltip')
DEFAULT_CHAT_FRAME={AddMessage=function()end};UIErrorsFrame=DEFAULT_CHAT_FRAME
RaidWarningFrame=CreateFrame('Frame');ChatTypeInfo={RAID_WARNING={r=1,g=0,b=0}}
StaticPopupDialogs={};SlashCmdList={};UISpecialFrames={};RAID_CLASS_COLORS=setmetatable({},{__index=function()return {r=1,g=.5,b=1,colorStr='ffaabbcc'}end})
SOUNDKIT={IG_CHARACTER_INFO_TAB=1,RAID_WARNING=1};MAX_PLAYER_LEVEL_TABLE={[0]=60};UNKNOWNOBJECT='Unknown';LOCALIZED_CLASS_NAMES_MALE={HUNTER='Hunter'}
C_ChatInfo={RegisterAddonMessagePrefix=function()end,SendAddonMessage=function()end}
C_Map={GetAreaInfo=function(id)return 'Area'..id end,GetBestMapForUnit=function()return 1431 end}
C_FriendList={GetNumFriends=function()return 0 end}
C_Timer={}
local timers={}
function C_Timer.After(_,fn)timers[#timers+1]=fn end
function C_Timer.NewTicker(_,fn)return {Cancel=function()end} end
function Drain()local queue=timers;timers={};for _,fn in ipairs(queue)do fn()end end
function Tick(elapsed) for _,f in ipairs(frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,elapsed)end end end
function Emit(event,...)
 for _,f in ipairs(frames)do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...)end end
 if VoidMark and VoidMark.events[event] then local h=VoidMark.events[event];if type(h)=='string' then VoidMark[h](VoidMark,event,...)end end
end
local locale=setmetatable({},{__index=function(_,k)return k end})
local libs={}
libs['AceLocale-3.0']={GetLocale=function()return locale end,NewLocale=function()return locale end}
libs['LibSharedMedia-3.0']={HashTable=function()return {}end,List=function()return {}end,Register=function()end,Fetch=function()return 'font'end}
libs['AceAddon-3.0']={NewAddon=function(_,name)local t=obj(name);t.isaddon=true;function t:NewModule(n) local m=obj(n);m.isaddon=true; return m end; function t:ScheduleRepeatingTimer()return 1 end;function t:ScheduleTimer(_,...)return 1 end;function t:CancelTimer()end;return t end}
libs['AceDB-3.0']={New=function(_,name,defaults) _G[name]=_G[name] or {};return {profile=defaults.profile,RegisterCallback=function()end}end}
setmetatable(libs,{__index=function(t,k)local v=obj(k);function v:AddToBlizOptions()return obj('Options')end;t[k]=v;return v end})
LibStub=setmetatable({GetLibrary=function(_,name)return libs[name] end},{__call=function(_,name)return libs[name]end})
function PanelTemplates_GetSelectedTab()return 1 end
for _,name in ipairs({'PlaySound','PlaySoundFile','SendChatMessage','SetCVar','UIFrameFadeIn','UIFrameFadeOut','CloseDropDownMenus','UIDropDownMenu_Initialize','UIDropDownMenu_AddButton','UIDropDownMenu_SetWidth','UIDropDownMenu_SetText','FauxScrollFrame_Update','FauxScrollFrame_OnVerticalScroll','PanelTemplates_TabResize','PanelTemplates_SetTab','PanelTemplates_SetNumTabs','RaidNotice_AddMessage','ToggleDropDownMenu','StaticPopup_Show','UIFrameFadeRemoveFrame','GetCurrentKeyBoardFocus'})do _G[name]=function()end end
function UIDropDownMenu_CreateInfo()return {}end
function FauxScrollFrame_GetOffset()return 0 end
function IsShiftKeyDown()return false end
function IsControlKeyDown()return false end
function GetScreenWidth()return 1920 end
function GetScreenHeight()return 1080 end
function GetCursorPosition()return 100,100 end
function GetNumBattlefieldScores()return 0 end
function GetNumBattlefieldStats()return 0 end
function GetNumBattlefieldPositions()return 0 end
-- Globals created by XML before its associated scripts run.
for _,n in ipairs({'VoidMarkStats','VoidMarkStatsTabFrame','VoidMarkStatsRefreshButton','VoidMarkStatsSummary','VoidMarkStatsScrollFrame','VoidMark_BarDropDownMenu'})do _G[n]=obj(n)end
function hooksecurefunc()end
function wipe(t)for k in pairs(t)do t[k]=nil end;return t end
function tinsert(t,v)table.insert(t,v)end
function strtrim(s)return s:match('^%s*(.-)%s*$')end
function GetLocale()return 'enUS'end
function format(...)return string.format(...)end
function GetNumSavedInstances()return 0 end
function GetNumLanguages()return 1 end
function GetLanguageByIndex()return 'Common',7 end
function UnitSex()return 2 end
function IsMounted()return false end
function UnitAffectingCombat()return false end
function GetInventoryItemLink()return nil end
function GetInventoryItemTexture()return nil end
function GetInventorySlotInfo()return 1 end
function GetHonorCurrency()return 0 end
function GetPVPLifetimeStats()return 0,0,0 end
function GetPVPYesterdayStats()return 0,0 end
function GetPVPSessionStats()return 0,0 end
function GetNumWhoResults()return 0 end
LibStub('AceDBOptions-3.0').GetOptionsTable=function()return {}end
function RaiseFrameLevel()end
function LowerFrameLevel()end
function GetNumAddOns()return 0 end
LibStub('LibSharedMedia-3.0').RegisterCallback=function()end
LibStub('LibSharedMedia-3.0').MediaType={STATUSBAR='statusbar',FONT='font'}
function ChatFrame_AddMessageEventFilter()end
function ChatFrame_RemoveMessageEventFilter()end
function UnitIsAFK()return false end
function UnitIsDND()return false end
function UnitIsUnit(a,b)return a==b end
function GetItemInfo()return nil end
function IsUsableSpell()return false end
function IsPlayerSpell()return false end
function IsSpellKnown()return false end
function UnitOnTaxi()return false end
function UnitPVPRank()return 0 end
