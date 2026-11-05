"""Two independent Lua clients exchange recent history over an in-memory BNet bus."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
clients=[]
messages=[]
packets=[]
for index in range(2):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT/'tests/client_mock.lua').read_text())
    lua.execute(f'''
        math.randomseed({index+1})
        local unitName,unitGUID=UnitName,UnitGUID
        UnitName=function(u)if u=='player' then return 'Client{index}','One' end return unitName(u)end
        UnitGUID=function(u)if u=='player' then return 'Player-1-client{index}' end return unitGUID(u)end
    ''')
    lua.execute('''
        VoidMarkDB={}; VoidMarkPerCharDB={PlayerData={}}
        VoidMark={events={}}
        local timers={}
        C_Timer.After=function(delay,fn) timers[#timers+1]={at=NOW+delay,fn=fn} end
        function Step()
            NOW=NOW+0.1
            local pending=timers; timers={}
            for _,t in ipairs(pending)do
                if t.at<=NOW then t.fn() else timers[#timers+1]=t end
            end
            Tick(0.1)
        end
    ''')
    lua.globals().BNSendGameData=lambda target,prefix,payload,src=index: messages.append((src,int(target)-1,prefix,payload))
    for name in ['Compat/Forever.lua','GankRepository.lua']:
        lua.execute((ROOT/'VoidMarkForever'/name).read_text())
    lua.execute('Emit("PLAYER_LOGIN")')
    lua.execute(f'''
        local s=VoidMarkDB.TaliaaGankSync
        s.lastKnownPeerGameAccountID={2-index}
        s.nodeID='test{index}'
    ''')
    clients.append(lua)

def pump(count):
    for _ in range(count):
        for lua in clients: lua.globals().Step()
        pending=messages[:]; messages.clear()
        for src,dst,prefix,payload in pending:
            packets.append(payload)
            if dst in (0,1): clients[dst].globals().Emit('BN_CHAT_MSG_ADDON',prefix,payload,src+1)

for lua in clients: lua.execute('assert(TaliaaGankRepository:StartPairing(false))')
pump(25)
for lua in clients: lua.execute('assert(VoidMarkDB.TaliaaGankSync.peerSessionToken)')
# Seed different old histories directly, then rebuild their real indexes. They
# must be retained locally but never sent by recent online reconciliation.
for index,lua in enumerate(clients):
    lua.execute(f'''
        local h=VoidMarkDB.TaliaaGankGlobal.Forever.GankHistory
        for i=1,14000 do
            local id='old{index}-'..i
            h.events[id]={{id=id,t=time()-200000-i*7,name='Old-One',guid='Player-1-old{index}',killer='Hero-One'}}
        end
        local id='recent{index}'
        h.events[id]={{id=id,t=time()-100,name='Recent-{index}',guid='Player-1-recent{index}',killer='Hero-One'}}
        TaliaaGankRepository:RebuildIndexes()
    ''')
packets.clear()
clients[0].execute('assert(TaliaaGankRepository:SyncNow(false))')
pump(650)
for i,lua in enumerate(clients):
    if lua.eval('VoidMarkDB.TaliaaGankSync.syncing or VoidMarkDB.TaliaaGankSync.bulkReceivePending'):
        print('Unfinished client',i,'packets:',[p.split(chr(31)) for p in packets],flush=True)
for lua in clients:
    lua.execute('''
        local h=VoidMarkDB.TaliaaGankGlobal.Forever.GankHistory
        assert(h.events.recent0 and h.events.recent1,'Missing return-leg kill')
        local count=0; for _ in pairs(h.events)do count=count+1 end
        assert(count==14002,'Old history lost or transferred')
        local s=VoidMarkDB.TaliaaGankSync
        assert(not s.syncing and not s.bulkReceivePending,'Sync did not finish')
    ''')
assert len(packets)<30, f'Excessive traffic: {len(packets)} packets'
assert not any('old0-' in p or 'old1-' in p for p in packets), 'Old history sent online'
print(f'PASS: two-client recent sync, 28,000 retained old records, {len(packets)} packets')
