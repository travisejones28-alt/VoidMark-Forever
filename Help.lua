-- VoidMark Forever help: FAQ and every command, in Options > AddOns > VoidMark and /vm help.
-- Help window renderer. The same code ships in every VoidMark addon (one copy
-- per addon, own frame name), so each addon works on its own.
-- HELP = { title=..., intro=..., sections={ {title=..., commands={{'/cmd','what it does'},...}}
--                                            or {title=..., faq={{'Question?','Answer.'},...}} } }
local function HelpText(help,filter)
  if help.build then help.build(help) end
  filter=type(filter)=='string' and filter:lower():match('^%s*(.-)%s*$') or ''
  local function hit(...)
    if filter=='' then return true end
    for i=1,select('#',...) do
      local s=select(i,...)
      if type(s)=='string' and s:lower():find(filter,1,true) then return true end
    end
    return false
  end
  local out={}
  if filter=='' and help.intro then out[#out+1]=help.intro;out[#out+1]='' end
  local found=0
  for _,section in ipairs(help.sections or {}) do
    local lines={}
    for _,c in ipairs(section.commands or {}) do
      if hit(c[1],c[2],section.title) then lines[#lines+1]='|cffffd200'..c[1]..'|r  '..c[2];found=found+1 end
    end
    for _,q in ipairs(section.faq or {}) do
      if hit(q[1],q[2],section.title) then lines[#lines+1]='|cffffd200Q: '..q[1]..'|r';lines[#lines+1]='A: '..q[2];lines[#lines+1]='';found=found+1 end
    end
    if #lines>0 then
      out[#out+1]='|cffb86cff'..section.title:upper()..'|r'
      for _,l in ipairs(lines) do out[#out+1]=l end
      if lines[#lines]~='' then out[#out+1]='' end
    end
  end
  if found==0 then out[#out+1]='Nothing matches "'..filter..'".' end
  return table.concat(out,'\n'),found
end

local function HelpWindow(frameName,help)
  local w={help=help}
  local f,text,search
  local function render()
    if not f then return end
    local s=HelpText(help,search and search:GetText() or '')
    w.current=s
    text:SetText(s)
    local _,breaks=s:gsub('\n','\n')
    text:SetHeight(math.max(400,(breaks+1)*15+40))
  end
  local function build()
    f=CreateFrame('Frame',frameName,UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
    f:SetSize(580,620);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG')
    if f.SetToplevel then f:SetToplevel(true) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',function() f:StartMoving() end)
    f:SetScript('OnDragStop',function() f:StopMovingOrSizing() end)
    if f.SetBackdrop then
      f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
      f:SetBackdropColor(.035,.025,.06,.97);f:SetBackdropBorderColor(.48,.25,.72,1)
    end
    local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
    title:SetPoint('TOPLEFT',16,-14);title:SetText(help.title or 'Help')
    local close=CreateFrame('Button',nil,f,'UIPanelCloseButton')
    close:SetPoint('TOPRIGHT',-2,-2);close:SetScript('OnClick',function() f:Hide() end)
    local label=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    label:SetPoint('TOPLEFT',18,-48);label:SetText('Search:')
    search=CreateFrame('EditBox',frameName..'Search',f,'InputBoxTemplate')
    search:SetSize(220,20);search:SetPoint('TOPLEFT',70,-43)
    if search.SetAutoFocus then search:SetAutoFocus(false) end
    search:SetScript('OnTextChanged',function() render() end)
    search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    search:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
    local hint=f:CreateFontString(nil,'OVERLAY','GameFontDisableSmall')
    hint:SetPoint('LEFT',search,'RIGHT',12,0);hint:SetText('Click the text, Ctrl+A, Ctrl+C to copy.')
    local scroll=CreateFrame('ScrollFrame',frameName..'Scroll',f,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',16,-72);scroll:SetPoint('BOTTOMRIGHT',-34,16)
    text=CreateFrame('EditBox',nil,scroll)
    if text.SetMultiLine then text:SetMultiLine(true) end
    if text.SetFontObject then text:SetFontObject(GameFontHighlight) end
    if text.SetAutoFocus then text:SetAutoFocus(false) end
    text:SetWidth(520)
    text:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    -- Read only: typing puts the help text back.
    text:SetScript('OnTextChanged',function(self,user) if user and w.current then self:SetText(w.current) end end)
    scroll:SetScrollChild(text)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=frameName end
    f:Hide()
  end
  function w.Open(filter)
    if not f then build() end
    if filter~=nil and search then search:SetText(filter) end
    render();f:Show()
    return f
  end
  function w.Toggle()
    if f and f:IsShown() then f:Hide() else w.Open() end
  end
  function w.Text(filter) return HelpText(help,filter) end
  function w.Frame() return f end
  return w
end

-- The /vm list is read from VoidMark's own command table each time, so it is
-- always complete; the module commands below are listed by hand (a test checks them).
local MODULES={
 {title='PvP kills: /tgank',commands={
  {'/tgank','Show the kill tracker summary.'},
  {'/tgank show | hide','Show or hide the kill tracker and panic windows.'},
  {'/tgank stats  (or stat)','Today and this week.'},
  {'/tgank today  (or daily)','Today\'s kills (08:00 to 08:00, shared by both accounts).'},
  {'/tgank week  (or weekly)','This week\'s kills.'},
  {'/tgank records  (or record, best)','Lifetime kills and records.'},
  {'/tgank pets  (or petkills)','Hunter pet kills.'},
  {'/tgank streak','Current streak and best this session.'},
  {'/tgank revenge','Revenge marks (players who killed you).'},
  {'/tgank dhk','Dishonorable kills.'},
  {'/tgank unknown','Today\'s kills whose level is still unknown.'},
  {'/tgank report','Report the hunt shown in the window (today, week or records) to chat.'},
  {'/tgank reportboth','Report to your party (daily and weekly as set).'},
  {'/tgank party','Party announcements on or off.'},
  {'/tgank panic','Call for help: nearby threats with your location.'},
  {'/tgank panictest','Preview the panic message without sending it.'},
  {'/tgank panicstyle','Show the panic style (fixed to Banner).'},
  {'/tgank options  (or opt)','Kill tracker options.'},
  {'/tgank reset','Clear this character\'s streak, revenge and DHK session (history is kept).'},
  {'/tgank sessionreset  (or sessreset)','Same session reset; shared Today and lifetime history are not changed.'},
  {'/tgank pair | unpair','Pair or unpair kill history with your other account.'},
  {'/tgank sync','Sync recent kills now.'},
  {'/tgank fullsync','Full history sync (when available).'},
  {'/tgank repo [NAME | target | rebuild]  (or history)','History for a player or your target; rebuild repairs the index.'},
  {'/tgank build  (or version)','Kill tracker build.'},
  {'/tgank weekdebug','Where the weekly numbers come from.'},
  {'/tgank perf','Kill processing timings.'}}},
 {title='Runback timers: /trb',commands={
  {'/trb  (or /trb show)','Runback timers (they appear in the VoidMark window).'},
  {'/trb test [normal | nightelf]','Fake death to test a timer.'},
  {'/trb details [NAME]','How a timer was worked out.'},
  {'/trb route [NAME]','The same, with the graveyard route.'},
  {'/trb routes on | off','Allow route searches for details and calibration.'},
  {'/trb analyze [alliance | horde]  (or analyse)','Check your position for runback estimates.'},
  {'/trb calibrate [report | cancel | clear]','Calibrate run speed; report, stop or clear it.'},
  {'/trb target','Runback report for your target.'},
  {'/trb gy [alliance | horde]','Graveyards for this zone.'},
  {'/trb zone','Zone report.'},
  {'/trb sample','Record one position sample.'},
  {'/trb settings','Runback settings.'},
  {'/trb clear','Clear all timers.'},
  {'/trb debug','Debug counters and API checks.'},
  {'/trb resetpos','Where to move the timers (they use the VoidMark window).'}}},
 {title='Enemy moves: /emoves',commands={
  {'/emoves  (or /enemymoves)','Enemy cooldown alerts.'},
  {'/emoves show | hide','Show or hide the alerts.'},
  {'/emoves lock | unlock','Lock or move them.'},
  {'/emoves options  (or opt)','Options window.'},
  {'/emoves test','Show test alerts.'},
  {'/emoves reset','Reset position.'},
  {'/emoves debug','Debug output.'}}},
 {title='KOS zone alerts: /vmkos',commands={
  {'/vmkos on | off','Alerts when a KOS player is in your zone.'},
  {'/vmkos share on | off','Share sightings with your group.'},
  {'/vmkos reasons on | off','Include KOS reasons when sharing.'},
  {'/vmkos sound on | off','Alert sound.'},
  {'/vmkos cooldown 180','Seconds before the same player alerts again (30-1800).'}}},
 {title='Boats: /tb',commands={
  {'/tb  (or /tboats, /tb show)','Boat timer window.'},
  {'/tb hide','Hide it.'},
  {'/tb status  (or test)','Print timers.'},
  {'/tb overlay on | off','Compact overlay.'},
  {'/tb opacity 0-100','Overlay background darkness.'},
  {'/tb report on | off','Report new syncs to your group.'},
  {'/tb arrivals on | off','Arrival announcements.'},
  {'/tb departures on | off','Departure announcements.'},
  {'/tb countdown on | off','10, 5, 4, 3, 2, 1 departure countdown.'},
  {'/tb countdown5 on | off','Add 30, 25, 20, 15 second countdowns.'},
  {'/tb sync dark | aub | auberdine | bb | booty | ratchet | thera | theramore','Emergency sync of one boat route.'},
  {'/tb clear','Clear boat timers.'},
  {'/tb reset','Reset window position.'}}},
 {title='Ride or Die gear: /trd',commands={
  {'/trd  (or /rideordie, /taliaagear)','Gear-set window.'},
  {'/trd riding  (or ride)','Equip your riding set.'},
  {'/trd pvp','Equip your PvP set.'},
  {'/trd save riding | save ride | save pvp','Save what you wear as that set.'},
  {'/trd set NAME','Equip a saved set.'},
  {'/trd save NAME','Save what you wear as a set.'},
  {'/trd auto on | off','Swap sets automatically.'},
  {'/trd status','Current sets and auto state.'},
  {'/trd resetpos','Reset window position.'},
  {'/trd help','Short help in chat.'}}},
 {title='Taunt translator: /ttaunt',commands={
  {'/ttaunt  (or /taliaataunt)','Taunt window with saved phrases.'},
  {'/ts TEXT','Say TEXT translated for the other faction.'},
  {'/ty TEXT','Yell TEXT translated for the other faction.'}}},
 {title='Other tools',commands={
  {'/vmc  (or /mcmark, /vmc mark)','Mark your Mind Controlled enemy now.'},
  {'/vmc on | off','Auto-mark while Priest Mind Control is active.'},
  {'/vmc show | clear','Show or clear the mark.'},
  {'/tthreat  (or /tthreat status)','Threat check status.'},
  {'/tthreat target','Threat check on your target.'},
  {'/tthreat debug','Threat debug output.'},
  {'/vmminimap','Show the VoidMark minimap button again.'},
  {'/vmminimap hide  (or off)','Hide the minimap button.'},
  {'/vmf','Client diagnostics (build, detections, nameplates).'},
  {'Whisper "inv" or "invite"','From one of your Voidmark characters: you get a group invite.'}}},
 {title='FAQ',faq={
  {'How do I put someone on KOS?','Right-click them in the VoidMark list, or type /vm kos NAME. /vm ignore NAME stops them being tracked.'},
  {'The VoidMark window is off screen.','/vm reset puts the windows back. /vm show opens it.'},
  {'I lost the minimap button.','Type /vmminimap.'},
  {'Why do Today\'s kills reset at 08:00?','Today runs 08:00 to 08:00 on both accounts so they agree. /tgank reset only clears streak, revenge and DHK session.'},
  {'How do my two accounts share kills?','/tgank pair on both while online. Recent kills (24 hours) sync by themselves; older history stays.'},
  {'What is the runback timer?','The earliest an enemy you killed can be back, from their graveyard, the distance and ghost speed. "GY ?" means the graveyard could not be pinned down.'},
  {'Why no damage numbers?','Forever hides damage data from addons, so Damage Records was removed.'},
  {'Where are the settings?','Game Menu > Options > AddOns > VoidMark (or /vm config). This Help & Commands page is there too.'},
  {'Is my kill and KOS history safe after updates?','Yes. Updates keep your saved history; nothing is deleted.'}}}}

local HELP={title='VoidMark Forever: Help & commands',
 intro='Open this from Options > AddOns > VoidMark > Help & Commands, or type /vm help. Type in Search to filter.'}
-- /vm commands from VoidMark's own table, in its order.
function HELP.build(help)
 local list={}
 local slash=VoidMark and VoidMark.optionsSlash and VoidMark.optionsSlash.args or {}
 for key,opt in pairs(slash) do
  if type(opt)=='table' and opt.type~='description' and opt.type~='header' and not opt.cmdHidden then
   local desc=type(opt.desc)=='string' and opt.desc or (type(opt.name)=='string' and opt.name) or ''
   list[#list+1]={order=tonumber(opt.order) or 100,cmd='/vm '..key..(opt.type=='input' and ' NAME' or ''),desc=desc}
  end
 end
 table.sort(list,function(a,b) if a.order~=b.order then return a.order<b.order end return a.cmd<b.cmd end)
 local commands={{'/vm  (or /voidmark)','List VoidMark commands in chat.'}}
 for _,c in ipairs(list) do commands[#commands+1]={c.cmd,c.desc} end
 help.sections={{title='VoidMark: /vm',commands=commands}}
 for _,s in ipairs(MODULES) do help.sections[#help.sections+1]=s end
end
HELP.build(HELP)
VoidMarkForeverHelp=HelpWindow('VoidMarkForeverHelpWindow',HELP)

-- /vm help, and a Help & Commands page in the AddOns options.
if VoidMark and VoidMark.optionsSlash and VoidMark.optionsSlash.args then
 VoidMark.optionsSlash.args.help={name='Help',desc='Open the Help & commands window (FAQ and every command).',type='execute',order=2,
  func=function() VoidMarkForeverHelp.Open() end}
end
if VoidMark and VoidMark.options and VoidMark.options.args then
 VoidMark.options.args.Help={name='Help & Commands',type='group',order=90,args={
  open={name='Open searchable help',desc='A window you can search and copy from.',type='execute',order=1,width='double',
   func=function() VoidMarkForeverHelp.Open() end},
  text={name=function() return (VoidMarkForeverHelp.Text()) end,type='description',order=2,fontSize='medium'}}}
end
