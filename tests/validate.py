"""Lua 5.1 syntax, TOC/XML/asset validation and mocked client regressions.
Run with Python plus lupa (Lua 5.1 runtime); no WoW installation required.
"""
from pathlib import Path
import re,xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
LUA=LuaRuntime(unpack_returned_tuples=True)
compile_lua=LUA.eval('function(s,n) local f,e=loadstring(s,n); return f~=nil,e end')
count=0
for p in ROOT.rglob('*.lua'):
    if any(part in {'tests','tools','dist','.github'} for part in p.relative_to(ROOT).parts): continue
    ok,error=compile_lua(p.read_text(),str(p))
    assert ok,error
    count+=1
loaded=[]
def xml(p):
    tree=ET.parse(p)
    for node in tree.iter():
        file=node.attrib.get('file')
        tag=node.tag.rsplit('}',1)[-1]
        if file and tag in ('Script','Include'):
            target=p.parent/file.replace('\\','/')
            assert target.exists(),target
            if tag=='Include': xml(target)
            else: loaded.append(target)
        if tag in ('OnLoad','OnClick','OnEvent','OnShow','OnHide','OnEnter','OnLeave','OnUpdate','PreClick') and node.text:
            ok,error=compile_lua('return function(self,button,elapsed,...)\n'+node.text+'\nend',str(p))
            assert ok,error
for line in (ROOT/'VoidMarkForever.toc').read_text().splitlines():
    line=line.strip()
    if not line or line.startswith('#'):continue
    p=ROOT/line.replace('\\','/')
    assert p.exists(),p
    if p.suffix=='.xml':xml(p)
    else:loaded.append(p)
assert len(loaded)==len(set(loaded)),'Duplicated script loading'
for p in ROOT.rglob('*'):
    if any(part in {'tests','tools','dist','.github'} for part in p.relative_to(ROOT).parts): continue
    if p.suffix not in ('.lua','.xml'): continue
    text=p.read_text()
    for match in re.finditer(r'Interface(?:\\+|/)Add[Oo]ns(?:\\+|/)VoidMarkForever(?:\\+|/)([A-Za-z0-9_./\\-]+)',text):
        path=re.sub(r'\\+','/',match[1])
        if path.endswith('/') : continue
        assert (ROOT/path).exists(),f'{p}: missing asset {path}'
for name in re.findall(r'"([a-z]+\.ogg)"',(ROOT/'KillEffects.lua').read_text()):
    assert (ROOT/'Sounds'/'KillEffects'/name).is_file(),f'Missing kill sound: {name}'
LUA.execute((Path(__file__).parent/'client_mock.lua').read_text())
# Upgrade from a pre-consent installation with an old external account link.
LUA.execute('''VoidMarkDB={TaliaaGankSync={autoPair=true,peerGameAccountID=99,
    peerSessionToken="legacy",peerName="Old-One",peerBattleTag="Old#1",
    lastKnownPeerGameAccountID=99}}''')
def run(file):
    LUA.globals().TEST_SOURCE=(ROOT/file).read_text()
    LUA.globals().TEST_NAME=file
    LUA.execute('assert(loadstring(TEST_SOURCE,TEST_NAME))("VoidMarkForever",NAMESPACE)')
run('Compat/Forever.lua')
LUA.execute('''
assert(VoidMarkForever.FullName("target")=="Enemy-One")
assert(VoidMarkForever.FullName("player")=="Hero-One")
assert(VoidMarkForever.API.UnitName("player")=="Hero-One")
assert(VoidMarkForever.Readable(SECRET)==nil)
assert(VoidMarkForever.Safe(function() return SECRET,4 end)==nil)
local a,b=VoidMarkForever.Safe(function() return SECRET,4 end); assert(a==nil and b==4)
assert(VoidMarkForever.CombatInfo()==nil)
''')
# Boot all active feature files with a mocked WoW UI, then initialize Ace addon.
for p in loaded:
    if 'Libs' in p.parts or p.name=='Forever.lua':continue
    run(str(p.relative_to(ROOT)))
LUA.execute('''
VoidMark:OnInitialize()
Emit("ADDON_LOADED","VoidMarkForever")
Emit("PLAYER_LOGIN")
VoidMark:OnEnable()
Emit("PLAYER_ENTERING_WORLD")
Drain()
''')
LUA.execute((Path(__file__).parent/'regressions.lua').read_text())
LUA.execute((Path(__file__).parent/'feature_regressions.lua').read_text())
LUA.execute((Path(__file__).parent/'live_regressions.lua').read_text())
LUA.execute((Path(__file__).parent/'help_regressions.lua').read_text())
# Help lists every subcommand each module's slash handler accepts.
import re
help_text=(ROOT/'Help.lua').read_text()
listed={}
for entry in re.findall(r"\{'(/\w+[^']*)'",help_text):
    cmd=entry.split()[0]
    listed.setdefault(cmd,set()).update(re.findall(r'[\w-]+',entry))
    for alias in re.findall(r'(/\w+)',entry): listed.setdefault(alias,set()).update(re.findall(r'[\w-]+',entry))
for line in (ROOT/'VoidMarkForever.toc').read_text().splitlines():
    line=line.strip().replace('\\','/')
    if not line.endswith('.lua') or line=='Help.lua': continue
    source=(ROOT/line).read_text(errors='ignore')
    for m in re.finditer(r'SLASH_(\w+?)1 *= *["\']([^"\']+)["\']',source):
        name,cmd=m.group(1),m.group(2)
        assert cmd in listed, f'Help.lua does not list {cmd} ({line})'
        h=re.search(r'^([ \t]*)SlashCmdList(?:\.|\[["\'])'+name+r'["\']?\]? *= *function',source,re.M)
        if not h: continue
        indent=h.group(1); body=[]
        for l in source[h.end():].split('\n')[1:]:
            if l.startswith(indent+'end') and not l[len(indent):len(indent)+1].isspace(): break
            body.append(l)
        words=set()
        for w in re.findall(r'\b(?:cmd|msg|lower|command|arg|rest) *== *"([^"]+)"','\n'.join(body)): words.update(re.findall(r'[\w-]+',w))
        checked=globals().setdefault('checked',{}); checked[cmd]=len(words)
        missing=sorted(w for w in words if w not in listed[cmd] and w not in ('help','faq','commands'))
        assert not missing, f'Help.lua is missing {cmd} {missing}'
assert checked.get('/tgank',0)>=30 and checked.get('/tb',0)>=20, checked
print('PASS: Help lists every module slash command ('+str(sum(checked.values()))+' subcommands)')
# Audio settings and cancellation run in isolation, using the real module.
audio=LuaRuntime(unpack_returned_tuples=True)
audio.execute((Path(__file__).parent/'kill_effects_regression.lua').read_text())
print(f'PASS: {count} Lua files; XML scripts, load graph/assets, startup and client regressions')
