"""Lua 5.1 syntax, TOC/XML/asset validation and mocked client regressions.
Run with Python plus lupa (Lua 5.1 runtime); no WoW installation required.
"""
from pathlib import Path
import re,xml.etree.ElementTree as ET
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]/'VoidMarkForever'
LUA=LuaRuntime(unpack_returned_tuples=True)
compile_lua=LUA.eval('function(s,n) local f,e=loadstring(s,n); return f~=nil,e end')
count=0
for p in ROOT.rglob('*.lua'):
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
    if p.suffix not in ('.lua','.xml'): continue
    text=p.read_text()
    for match in re.finditer(r'Interface(?:\\+|/)Add[Oo]ns(?:\\+|/)VoidMarkForever(?:\\+|/)([A-Za-z0-9_./\\-]+)',text):
        path=re.sub(r'\\+','/',match[1])
        if path.endswith('/') : continue
        assert (ROOT/path).exists(),f'{p}: missing asset {path}'
LUA.execute((Path(__file__).parent/'client_mock.lua').read_text())
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
print(f'PASS: {count} Lua files; XML scripts, load graph/assets, startup and client regressions')
