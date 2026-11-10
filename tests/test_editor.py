# Prueba del editor en PC: simula la API de LPP-3DS con lupa (pip install lupa)
# y recorre las paginas con una secuencia de botones. Uso: python tests/test_editor.py
# Con tu propia partida (opcional): SAVE=ruta/save00.bin python tests/test_editor.py
import struct, random, os
from lupa import lua53
random.seed(1)
SIZE=0x1500
b=bytearray(random.getrandbits(8) for _ in range(SIZE))
def w16(o,v): b[o:o+2]=struct.pack('<H',v&0xFFFF)
def w32(o,v): b[o:o+4]=struct.pack('<I',v)
w16(0x42,48); w16(0x44,48); b[0x46]=0; b[0x47]=0; w16(0x48,17); b[0x4E]=0;b[0x50]=0;b[0x51]=0;b[0x52]=0
for i in range(26): b[0x8C+i]=0xFF
b[0x8C+0]=0x00; b[0x8C+7]=0x07
for i in range(15): b[0xA6+i]=0
w16(0xB6,0x1111); w32(0xB8,(1<<17)|(1<<20)); w32(0xBC,0); w16(0xE8,5)
for i in range(24): b[0x138A+i]=0xFF; b[0x13A2+i]=0xFF
b[0x138A]=0; b[0x138B]=7; b[0x13A2]=0; b[0x13A3]=7
def ccitt(data):
    crc=0xFFFF
    for x in data:
        crc^=x<<8
        for _ in range(8):
            crc=((crc<<1)^0x1021)&0xFFFF if crc&0x8000 else (crc<<1)&0xFFFF
    return crc
def chk(buf):
    t=bytearray(buf); t[0x14D8:0x14DC]=b'\0\0\0\0'; return ccitt(t)
b[0x14D8:0x14DC]=b'\0\0\0\0'; c=chk(b); b[0x14D8:0x14DA]=struct.pack('<H',c)
import binascii
def arc(data):
    crc=0
    for x in data:
        crc^=x
        for _ in range(8): crc=(crc>>1)^0xA001 if crc&1 else crc>>1
    return crc
# Tamano y checksum reales de OoT3D: 0x14DC bytes, CRC-16/ARC en little-endian
# calculado sobre todo el archivo con los bytes 0x14D8-0x14DB en cero.
if os.environ.get('SAVE'):
    b=bytearray(open(os.environ['SAVE'],'rb').read()); SIZE=len(b)
else:
    b=bytearray(b[:0x14DC]); SIZE=len(b)
    b[0x14D8:0x14DC]=b'\0\0\0\0'; b[0x14D8:0x14DA]=struct.pack('<H',arc(b))
ccitt=arc
files={'/3ds/Checkpoint/saves/0x00335 Ocarina of Time 3D/20261110-1/save00.bin':bytes(b)}
dirs={'/3ds/Checkpoint/saves':['0x00335 Ocarina of Time 3D'],'/3ds/Checkpoint/saves/0x00335 Ocarina of Time 3D':['20261110-1'],'/3ds/Checkpoint/saves/0x00335 Ocarina of Time 3D/20261110-1':[]}
K=dict(KEY_A=1,KEY_B=2,KEY_SELECT=4,KEY_START=8,KEY_DRIGHT=16,KEY_DLEFT=32,KEY_DUP=64,KEY_DDOWN=128,KEY_R=256,KEY_L=512,KEY_X=1024,KEY_Y=2048,KEY_ZL=1<<14,KEY_ZR=1<<15)
seq=[]
def press(*ks):
    m=0
    for k in ks: m|=K[k]
    seq.extend([m,0])
seq+=[0,0,0]
press('KEY_A'); press('KEY_A')  # enter backup dir, open save00
press('KEY_A'); press('KEY_DDOWN'); press('KEY_DDOWN'); press('KEY_A'); press('KEY_DDOWN'); press('KEY_A')  # page1
press('KEY_R'); press('KEY_A'); press('KEY_DDOWN'); press('KEY_A'); press('KEY_DDOWN'); press('KEY_A') # wallet, rupees, sticks
press('KEY_R'); press('KEY_A')  # ammo sticks fill
press('KEY_R'); press('KEY_DDOWN'); press('KEY_DDOWN'); press('KEY_DDOWN'); press('KEY_A')  # bow
press('KEY_R'); press('KEY_R'); press('KEY_DDOWN'); press('KEY_DDOWN'); press('KEY_A')  # page6 equipo -> biggoron
press('KEY_R'); press('KEY_R'); for_=None
seq+=[]
press('KEY_DDOWN')
for _ in range(10): press('KEY_DDOWN')
press('KEY_A')  # tokens 100 (row 12)
press('KEY_START'); press('KEY_B'); press('KEY_START')
L=lua53.LuaRuntime(unpack_returned_tuples=True, encoding=None)
g=L.globals()
state={'i':0}
class Exit(Exception): pass
def read():
    i=state['i']; state['i']+=1
    return seq[i] if i<len(seq) else 8
handles={}
def io_open(p,mode):
    p=p.decode() if isinstance(p,bytes) else p
    if mode==1 and p not in files: return None
    if mode==4: files[p]=b''
    h=len(handles)+1; handles[h]=p; return h
def io_size(h): return len(files[handles[h]])
def io_read(h,off,n): return files[handles[h]][off:off+n]
def io_write(h,off,s,n):
    p=handles[h]; data=bytearray(files[p]); raw=bytes(s)
    if len(data)<off+n: data.extend(b'\0'*(off+n-len(data)))
    data[off:off+n]=raw[:n]; files[p]=bytes(data)
def listdir(p):
    p=p.decode() if isinstance(p,bytes) else p
    out=[]
    for n in dirs.get(p,[]): out.append(L.table_from({b'name':n.encode(),b'directory':True}))
    for f in files:
        d,_,n=f.rpartition('/')
        if d==p: out.append(L.table_from({b'name':n.encode(),b'directory':False}))
    return L.table_from(out)
def exitf(): raise Exit()

keys=";".join("%s=%d"%(k,v) for k,v in K.items())
L.execute(("Color={new=function(r,g,b) return r*65536+g*256+b end} Screen={} Controls={} System={} io={} "+keys+" TOP_SCREEN=0 BOTTOM_SCREEN=1 FREAD=1 FWRITE=2 FCREATE=4 "
  "for _,f in ipairs({'refresh','clear','waitVblankStart','flip','debugPrint','fillRect'}) do Screen[f]=function() end end "
  "Controls.check=function(p,k) return (p & k) ~= 0 end").encode())
setter=L.eval(b"function(t,k,v) _G[t][k]=v end")
GW=[6, 4, 11, 12, 12, 12, 12, 6, 6, 6, 12, 12, 6, 12, 5, 12, 12, 6, 12, 12, 12, 12, 12, 12, 12, 12, 5, 6, 8, 9, 8, 12, 12, 11, 11, 10, 11, 11, 11, 11, 11, 8, 11, 11, 9, 12, 12, 12, 11, 12, 11, 12, 12, 11, 12, 12, 12, 12, 12, 6, 12, 6, 10, 12, 6, 10, 10, 9, 10, 10, 8, 10, 10, 4, 9, 10, 6, 12, 10, 10, 10, 10, 10, 10, 8, 10, 12, 12, 10, 12, 10, 8, 4, 8, 12, 13]
overflow=[]; nprint=[0]; seen=set()
def dprint(x,y,t,c,scr):
    nprint[0]+=1; seen.add((x,t.decode('latin1'),scr))
    w=sum(6 if ch<0x20 else GW[min(ch,0x7F)-0x20] for ch in t)
    if x+w>(400 if scr==0 else 320) or y>227 or x<0: overflow.append((x,y,t,scr))
import atexit; atexit.register(lambda: print('prints',nprint[0],'overflow',len(overflow),overflow[:5]))
setter(b'Screen',b'debugPrint',dprint)
setter(b'Controls',b'read',read); setter(b'System',b'listDirectory',listdir)
setter(b'System',b'doesFileExist',lambda p: (p.decode()) in files); setter(b'System',b'exit',exitf)
setter(b'io',b'open',io_open); setter(b'io',b'size',io_size); setter(b'io',b'read',io_read); setter(b'io',b'write',io_write); setter(b'io',b'close',lambda h: None)
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','sd','3ds','OoT3DEditor','index.lua'),encoding='utf8').read()
# capture string.char using latin-1 -> lupa decodes lua strings as bytes? ensure bytes passthrough
L2=L
try:
    L.execute(src.encode())
except Exception as e:
    print('stopped:', type(e).__name__, str(e)[:200])
p='/3ds/Checkpoint/saves/0x00335 Ocarina of Time 3D/20261110-1/save00.bin'
nb=files[p]; print('files', list(files)); print('frames used', state['i'], 'of', len(seq))
r16=lambda o: struct.unpack('<h',nb[o:o+2])[0]; r32=lambda o: struct.unpack('<I',nb[o:o+4])[0]
print('maxHealth',r16(0x42)//16,'health',r16(0x44)//16,'ddef',nb[0x51],'magic',nb[0x46],nb[0x47],nb[0x4E],nb[0x50])
print('wallet',(r32(0xB8)>>12)&3,'rupees',r16(0x48),'sticks upg',(r32(0xB8)>>17)&7,'stick ammo',nb[0xA6])
print('bow',hex(nb[0x8C+3]),'equip',hex(r16(0xB6)),'bgs',nb[0x52],'tokens',r16(0xE8),'quest',hex(r32(0xBC)))
print('menuChild',nb[0x138A:0x138A+24].hex(),'\nmenuAdult',nb[0x13A2:0x13A2+24].hex())
print('crc ok', struct.unpack('<H',nb[0x14D8:0x14DA])[0]==chk(nb), 'orig backup', p+'.orig' in files and files[p+'.orig']==bytes(b))
diff=[i for i in range(SIZE) if nb[i]!=b[i]]; print('changed offsets',[hex(x) for x in diff])
ok = struct.unpack('<H',nb[0x14D8:0x14DA])[0]==chk(nb) and len(nb)==SIZE and not overflow
print('RESULTADO:', 'OK' if ok else 'FALLO'); raise SystemExit(0 if ok else 1)
