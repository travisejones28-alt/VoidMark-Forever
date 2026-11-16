-- Help & Commands: /vm list comes from VoidMark's own table; the window and
-- the AddOns options page exist and open.
local H=VoidMarkForeverHelp
assert(H,'help window object')
local text=H.Text()
for key,opt in pairs(VoidMark.optionsSlash.args) do
  if type(opt)=='table' and opt.type~='description' and not opt.cmdHidden then
    assert(text:find('/vm '..key,1,true),'/vm '..key..' missing from help')
  end
end
assert(VoidMark.optionsSlash.args.help and VoidMark.options.args.Help,'help command and options page')
VoidMark.optionsSlash.args.help.func()
local f=H.Frame(); assert(f and f:IsShown(),'opens from /vm help')
f:Hide()
VoidMark.options.args.Help.args.open.func(); assert(f:IsShown(),'opens from the options page')
assert(VoidMark.options.args.Help.args.text.name():find('/tgank',1,true),'options page lists module commands')
local t,n=H.Text('boat'); assert(n>0 and t:find('/tb countdown',1,true))
assert(VoidMark.optionsFrames.Help,'Help & Commands frame registered in AddOns options')
print('PASS: Help & Commands window and AddOns options page')
