-- OoT3D Editor - editor de partidas de Ocarina of Time 3D para 3DS (Lua Player Plus)
-- Edita copias de Checkpoint: Checkpoint (respaldar) -> este editor -> Checkpoint (restaurar)

local VERSION = "1.0.0"
local SAVES_ROOT = "/3ds/Checkpoint/saves"

local WHITE  = Color.new(255,255,255)
local GREY   = Color.new(150,150,150)
local YELLOW = Color.new(255,205,66)
local GREEN  = Color.new(80,230,80)
local RED    = Color.new(255,80,80)
local CYAN   = Color.new(90,200,255)
local SEL_BG = Color.new(40,60,110)

------------------------------------------------------------------------
-- Datos de la partida
------------------------------------------------------------------------
local buf = nil        -- tabla de bytes (indice 0..n-1)
local bufLen = 0
local filePath = nil
local crcAlg = nil     -- algoritmo de checksum detectado
local dirty = false
local message, messageColor = "", WHITE

local CHK_OFF = 0x14D8

local function rd8(o) return buf[o] end
local function wr8(o,v) buf[o] = v & 0xFF; dirty = true end
local function rd16(o) local v = buf[o] | (buf[o+1] << 8); if v >= 0x8000 then v = v - 0x10000 end; return v end
local function wr16(o,v) v = v & 0xFFFF; buf[o] = v & 0xFF; buf[o+1] = (v >> 8) & 0xFF; dirty = true end
local function rd32(o) return buf[o] | (buf[o+1] << 8) | (buf[o+2] << 16) | (buf[o+3] << 24) end
local function wr32(o,v) for i=0,3 do buf[o+i] = (v >> (8*i)) & 0xFF end; dirty = true end
local function getBits(o, shift, width) return (rd32(o) >> shift) & ((1 << width) - 1) end
local function setBits(o, shift, width, val)
  local mask = ((1 << width) - 1) << shift
  wr32(o, (rd32(o) & ~mask) | ((val << shift) & mask))
end
local function getBit16(o, bit) return ((buf[o] | (buf[o+1] << 8)) >> bit) & 1 end
local function setBit16(o, bit, on)
  local v = buf[o] | (buf[o+1] << 8)
  if on then v = v | (1 << bit) else v = v & ~(1 << bit) end
  wr16(o, v)
end
local function getBit32(o, bit) return (rd32(o) >> bit) & 1 end
local function setBit32(o, bit, on)
  local v = rd32(o)
  if on then v = v | (1 << bit) else v = v & ~(1 << bit) end
  wr32(o, v)
end

------------------------------------------------------------------------
-- Checksum (CRC-16). El juego no documenta la variante: se detecta
-- comparando con el checksum guardado en la propia partida.
------------------------------------------------------------------------
local function crcRefl(poly, init, xorout, first, last)
  local crc = init
  for i = first, last do
    local b = buf[i]
    if i >= CHK_OFF and i < CHK_OFF + 4 then b = 0 end
    crc = crc ~ b
    for _ = 1, 8 do
      if crc & 1 == 1 then crc = (crc >> 1) ~ poly else crc = crc >> 1 end
    end
  end
  return (crc ~ xorout) & 0xFFFF
end

local function crcNorm(poly, init, xorout, first, last)
  local crc = init
  for i = first, last do
    local b = buf[i]
    if i >= CHK_OFF and i < CHK_OFF + 4 then b = 0 end
    crc = crc ~ (b << 8)
    for _ = 1, 8 do
      if crc & 0x8000 ~= 0 then crc = ((crc << 1) ~ poly) & 0xFFFF else crc = (crc << 1) & 0xFFFF end
    end
  end
  return (crc ~ xorout) & 0xFFFF
end

local CRC_VARIANTS = {
  {name="ARC",         f=crcRefl, poly=0xA001, init=0x0000, xo=0x0000},
  {name="MODBUS",      f=crcRefl, poly=0xA001, init=0xFFFF, xo=0x0000},
  {name="KERMIT",      f=crcRefl, poly=0x8408, init=0x0000, xo=0x0000},
  {name="X25",         f=crcRefl, poly=0x8408, init=0xFFFF, xo=0xFFFF},
  {name="MAXIM",       f=crcRefl, poly=0xA001, init=0x0000, xo=0xFFFF},
  {name="XMODEM",      f=crcNorm, poly=0x1021, init=0x0000, xo=0x0000},
  {name="CCITT-FALSE", f=crcNorm, poly=0x1021, init=0xFFFF, xo=0x0000},
  {name="GENIBUS",     f=crcNorm, poly=0x1021, init=0xFFFF, xo=0xFFFF},
  {name="BUYPASS",     f=crcNorm, poly=0x8005, init=0x0000, xo=0x0000},
}

local function computeCrc(alg)
  local last = (alg.range == "full") and (bufLen - 1) or (CHK_OFF - 1)
  return alg.v.f(alg.v.poly, alg.v.init, alg.v.xo, 0, last)
end

local function storedChecksum(le)
  if le then return buf[CHK_OFF] | (buf[CHK_OFF+1] << 8) end
  return (buf[CHK_OFF] << 8) | buf[CHK_OFF+1]
end

local function detectCrc()
  for _, v in ipairs(CRC_VARIANTS) do
    for _, range in ipairs({"full", "head"}) do
      local alg = {v=v, range=range}
      local c = computeCrc(alg)
      if c == storedChecksum(true) then alg.le = true; return alg end
      if c == storedChecksum(false) then alg.le = false; return alg end
    end
  end
  return nil
end

local function writeChecksum()
  local c = computeCrc(crcAlg)
  if crcAlg.le then buf[CHK_OFF] = c & 0xFF; buf[CHK_OFF+1] = (c >> 8) & 0xFF
  else buf[CHK_OFF] = (c >> 8) & 0xFF; buf[CHK_OFF+1] = c & 0xFF end
  buf[CHK_OFF+2] = 0; buf[CHK_OFF+3] = 0
end

------------------------------------------------------------------------
-- Offsets de la partida (SaveContext de Ocarina 3D)
------------------------------------------------------------------------
local O = {
  maxHealth=0x42, health=0x44, magicLevel=0x46, magic=0x47, rupees=0x48,
  magicAcquired=0x4E, doubleMagic=0x50, doubleDefense=0x51, bgsFlag=0x52,
  items=0x8C, ammo=0xA6, equipment=0xB6, upgrades=0xB8, quest=0xBC,
  gsTokens=0xE8, menuChild=0x138A, menuAdult=0x13A2,
}

local NONE = 0xFF

-- Mejoras: {nombre, bit, ancho, maximo}
local UPG = {
  quiver={0,3,3}, bombs={3,3,3}, strength={6,3,3}, dive={9,3,2},
  wallet={12,2,2}, seeds={14,3,3}, sticks={17,3,3}, nuts={20,3,3},
}
local function upg(k) local u = UPG[k]; return getBits(O.upgrades, u[1], u[2]) end
local function setUpg(k, v) local u = UPG[k]; setBits(O.upgrades, u[1], u[2], v) end

local WALLET_MAX = {[0]=99, 200, 500}
local AMMO_MAX = {
  sticks={[0]=0,10,20,30}, nuts={[0]=0,20,30,40}, bombs={[0]=0,20,30,40},
  quiver={[0]=0,30,40,50}, seeds={[0]=0,30,40,50},
}

------------------------------------------------------------------------
-- Objetos por casilla (ids del juego)
------------------------------------------------------------------------
local ITEM_NAME = {
  [0x00]="Palo Deku", [0x01]="Nuez Deku", [0x02]="Bombas", [0x03]="Arco",
  [0x04]="Flecha de fuego", [0x05]="Fuego de Din", [0x06]="Tirachinas",
  [0x07]="Ocarina de las hadas", [0x08]="Ocarina del Tiempo", [0x09]="Bombchus",
  [0x0A]="Gancho", [0x0B]="Gancho largo", [0x0C]="Flecha de hielo",
  [0x0D]="Viento de Farore", [0x0E]="Boomerang", [0x0F]="Lente de la Verdad",
  [0x10]="Judias magicas", [0x11]="Martillo Megaton", [0x12]="Flecha de luz",
  [0x13]="Amor de Nayru",
  [0x14]="Botella vacia", [0x15]="Pocion roja", [0x16]="Pocion verde",
  [0x17]="Pocion azul", [0x18]="Hada", [0x19]="Pez", [0x1A]="Leche Lon Lon",
  [0x1B]="Carta de Ruto", [0x1C]="Fuego azul", [0x1D]="Bicho", [0x1E]="Gran Poe",
  [0x1F]="Media leche", [0x20]="Poe",
  [0x21]="Huevo raro", [0x22]="Cuco", [0x23]="Carta de Zelda",
  [0x24]="Mascara Keaton", [0x25]="Mascara calavera", [0x26]="Mascara espectral",
  [0x27]="Capucha de conejo", [0x28]="Mascara Goron", [0x29]="Mascara Zora",
  [0x2A]="Mascara Gerudo", [0x2B]="Mascara de la Verdad", [0x2C]="Vendido",
  [0x2D]="Huevo de bolsillo", [0x2E]="Cuco de bolsillo", [0x2F]="Cojiro",
  [0x30]="Seta extrana", [0x31]="Medicina extrana", [0x32]="Sierra",
  [0x33]="Espada Goron rota", [0x34]="Receta", [0x35]="Rana ojona",
  [0x36]="Gotas oculares", [0x37]="Recibo",
  [0x45]="Botas de hierro", [0x46]="Botas levitadoras",
}

local function range(a, b) local t = {}; for i=a,b do t[#t+1] = i end; return t end
local BOTTLE_IDS = {0x14,0x15,0x16,0x17,0x18,0x19,0x1A,0x1F,0x1C,0x1D,0x20,0x1E,0x1B}

-- {casilla, nombre de la casilla, ids posibles}
local SLOTS = {
  {0x00,"Palos Deku",{0x00}}, {0x01,"Nueces Deku",{0x01}}, {0x02,"Bombas",{0x02}},
  {0x03,"Arco",{0x03}}, {0x04,"Flecha de fuego",{0x04}}, {0x05,"Fuego de Din",{0x05}},
  {0x06,"Tirachinas",{0x06}}, {0x07,"Ocarina",{0x07,0x08}}, {0x08,"Bombchus",{0x09}},
  {0x09,"Gancho",{0x0A,0x0B}}, {0x0A,"Flecha de hielo",{0x0C}}, {0x0B,"Viento de Farore",{0x0D}},
  {0x0C,"Boomerang",{0x0E}}, {0x0D,"Lente",{0x0F}}, {0x0E,"Judias",{0x10}},
  {0x0F,"Martillo",{0x11}}, {0x10,"Flecha de luz",{0x12}}, {0x11,"Amor de Nayru",{0x13}},
  {0x16,"Intercambio adulto",range(0x2D,0x37)}, {0x17,"Intercambio nino",range(0x21,0x2C)},
}
local BOTTLE_SLOTS = {0x12,0x13,0x14,0x15}

local function cycleSlot(slot, ids, dir)
  local cur = rd8(O.items + slot)
  local opts = {NONE}
  for _, id in ipairs(ids) do opts[#opts+1] = id end
  local idx = 1
  for i, id in ipairs(opts) do if id == cur then idx = i end end
  idx = ((idx - 1 + dir) % #opts) + 1
  wr8(O.items + slot, opts[idx])
end

local function itemLabel(id)
  if id == NONE then return "-- no --" end
  return ITEM_NAME[id] or string.format("id %02X", id)
end

------------------------------------------------------------------------
-- Menu tactil (para que los objetos agregados aparezcan en la pantalla)
------------------------------------------------------------------------
local function menuHas(base, slot)
  for i=0,23 do if rd8(base+i) == slot then return true end end
  return false
end
local function menuRemove(base, slot)
  for i=0,23 do if rd8(base+i) == slot then wr8(base+i, NONE) end end
end
local function menuPush(base, slot, adult)
  for i=0,23 do
    if (i + 1) % 6 ~= 0 and rd8(base+i) == NONE then wr8(base+i, slot); return true end
  end
  if adult then
    for i=5,23,6 do if rd8(base+i) == NONE then wr8(base+i, slot); return true end end
  end
  return false
end
local MAGIC_ARROW = {[0x04]=true, [0x0A]=true, [0x10]=true}

local function syncMenus()
  local hasBow = rd8(O.items + 0x03) ~= NONE
  for slot=0,0x19 do
    local present = rd8(O.items + slot) ~= NONE
    if present then
      if not (MAGIC_ARROW[slot] and hasBow) then
        if not menuHas(O.menuChild, slot) then menuPush(O.menuChild, slot, false) end
        if not menuHas(O.menuAdult, slot) then menuPush(O.menuAdult, slot, true) end
      end
    else
      menuRemove(O.menuChild, slot)
      menuRemove(O.menuAdult, slot)
    end
  end
end

------------------------------------------------------------------------
-- Paginas de edicion
-- Cada fila: {label, get=function()->texto, lr=function(dir, big), a=function()}
------------------------------------------------------------------------
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function onoff(b) return b and "SI" or "no" end

local function ammoRow(label, slot, maxf)
  return {label=label,
    get=function() return tostring(rd8(O.ammo + slot)) .. " / " .. maxf() end,
    lr=function(d, big) wr8(O.ammo + slot, clamp(rd8(O.ammo + slot) + d * (big and 10 or 1), 0, maxf())) end,
    a=function() wr8(O.ammo + slot, maxf()) end}
end

local function upgRow(label, key, names)
  return {label=label,
    get=function() return names[upg(key)] or tostring(upg(key)) end,
    lr=function(d) setUpg(key, clamp(upg(key) + d, 0, UPG[key][3])) end,
    a=function() setUpg(key, UPG[key][3]) end}
end

local function bitRow(label, off, bit, is16, extra)
  return {label=label,
    get=function() return onoff((is16 and getBit16(off, bit) or getBit32(off, bit)) == 1) end,
    lr=function() local cur = (is16 and getBit16(off, bit) or getBit32(off, bit)) == 1
      if is16 then setBit16(off, bit, not cur) else setBit32(off, bit, not cur) end
      if extra then extra(not cur) end end,
    a=function() local cur = (is16 and getBit16(off, bit) or getBit32(off, bit)) == 1
      if is16 then setBit16(off, bit, not cur) else setBit32(off, bit, not cur) end
      if extra then extra(not cur) end end}
end

local SIZE3 = {[0]="ninguna","pequena","mediana","grande"}

local PAGES = {}

PAGES[#PAGES+1] = {title="Vida y magia", rows={
  {label="Corazones", get=function() return tostring(rd16(O.maxHealth) // 16) .. " / 20" end,
   lr=function(d) local h = clamp(rd16(O.maxHealth) // 16 + d, 3, 20); wr16(O.maxHealth, h*16); wr16(O.health, h*16) end,
   a=function() wr16(O.maxHealth, 320); wr16(O.health, 320) end},
  {label="Rellenar vida", get=function() return string.format("%.2f", rd16(O.health)/16) end,
   lr=function() wr16(O.health, rd16(O.maxHealth)) end, a=function() wr16(O.health, rd16(O.maxHealth)) end},
  {label="Defensa doble", get=function() return onoff(rd8(O.doubleDefense) ~= 0) end,
   lr=function() wr8(O.doubleDefense, rd8(O.doubleDefense) ~= 0 and 0 or 1) end,
   a=function() wr8(O.doubleDefense, rd8(O.doubleDefense) ~= 0 and 0 or 1) end},
  {label="Magia", get=function() local l = rd8(O.magicLevel); return ({[0]="sin magia","normal","doble"})[l] or tostring(l) end,
   lr=function(d) local l = clamp(rd8(O.magicLevel) + d, 0, 2)
     wr8(O.magicLevel, l); wr8(O.magicAcquired, l > 0 and 1 or 0); wr8(O.doubleMagic, l > 1 and 1 or 0); wr8(O.magic, l * 0x30) end,
   a=function() wr8(O.magicLevel, 2); wr8(O.magicAcquired, 1); wr8(O.doubleMagic, 1); wr8(O.magic, 0x60) end},
}}

PAGES[#PAGES+1] = {title="Rupias y bolsas", rows={
  {label="Bolsa de rupias", get=function() return ({[0]="normal (99)","adulto (200)","gigante (500)"})[upg("wallet")] end,
   lr=function(d) setUpg("wallet", clamp(upg("wallet") + d, 0, 2)) end, a=function() setUpg("wallet", 2) end},
  {label="Rupias", get=function() return tostring(rd16(O.rupees)) .. " / " .. WALLET_MAX[upg("wallet")] end,
   lr=function(d, big) wr16(O.rupees, clamp(rd16(O.rupees) + d * (big and 100 or 10), 0, WALLET_MAX[upg("wallet")])) end,
   a=function() wr16(O.rupees, WALLET_MAX[upg("wallet")]) end},
  upgRow("Bolsa de palos", "sticks", SIZE3),
  upgRow("Bolsa de nueces", "nuts", SIZE3),
  upgRow("Bolsa de bombas", "bombs", SIZE3),
  upgRow("Carcaj", "quiver", SIZE3),
  upgRow("Bolsa de semillas", "seeds", SIZE3),
  upgRow("Guantes / fuerza", "strength", {[0]="ninguno","brazalete Goron","guantes plata","guantes oro"}),
  upgRow("Escama", "dive", {[0]="ninguna","plata","oro"}),
}}

PAGES[#PAGES+1] = {title="Municion (A = llenar)", rows={
  ammoRow("Palos Deku", 0x00, function() return AMMO_MAX.sticks[upg("sticks")] end),
  ammoRow("Nueces Deku", 0x01, function() return AMMO_MAX.nuts[upg("nuts")] end),
  ammoRow("Bombas", 0x02, function() return AMMO_MAX.bombs[upg("bombs")] end),
  ammoRow("Flechas", 0x03, function() return AMMO_MAX.quiver[upg("quiver")] end),
  ammoRow("Semillas", 0x06, function() return AMMO_MAX.seeds[upg("seeds")] end),
  ammoRow("Bombchus", 0x08, function() return 50 end),
  ammoRow("Judias magicas", 0x0E, function() return 10 end),
}}

local itemRows = {}
for _, s in ipairs(SLOTS) do
  local slot, label, ids = s[1], s[2], s[3]
  itemRows[#itemRows+1] = {label=label,
    get=function() return itemLabel(rd8(O.items + slot)) end,
    lr=function(d) cycleSlot(slot, ids, d) end,
    a=function() if rd8(O.items + slot) == NONE then wr8(O.items + slot, ids[#ids]) else wr8(O.items + slot, NONE) end end}
end
PAGES[#PAGES+1] = {title="Objetos", rows=itemRows}

local bottleRows = {}
for i, slot in ipairs(BOTTLE_SLOTS) do
  bottleRows[#bottleRows+1] = {label="Botella " .. i,
    get=function() return itemLabel(rd8(O.items + slot)) end,
    lr=function(d) cycleSlot(slot, BOTTLE_IDS, d) end,
    a=function() wr8(O.items + slot, rd8(O.items + slot) == NONE and 0x14 or NONE) end}
end
PAGES[#PAGES+1] = {title="Botellas", rows=bottleRows}

local function bootsExtra(slot, id) return function(on) wr8(O.items + slot, on and id or NONE) end end
PAGES[#PAGES+1] = {title="Equipo", rows={
  bitRow("Espada Kokiri", O.equipment, 0, true),
  bitRow("Espada Maestra", O.equipment, 1, true),
  bitRow("Espada de Biggoron", O.equipment, 2, true, function(on) wr8(O.bgsFlag, on and 1 or 0) end),
  bitRow("Escudo Deku", O.equipment, 4, true),
  bitRow("Escudo Hyliano", O.equipment, 5, true),
  bitRow("Escudo espejo", O.equipment, 6, true),
  bitRow("Tunica Kokiri", O.equipment, 8, true),
  bitRow("Tunica Goron", O.equipment, 9, true),
  bitRow("Tunica Zora", O.equipment, 10, true),
  bitRow("Botas de hierro", O.equipment, 13, true, bootsExtra(0x18, 0x45)),
  bitRow("Botas levitadoras", O.equipment, 14, true, bootsExtra(0x19, 0x46)),
}}

local tokenRow = {label="Skulltulas doradas",
  get=function() return tostring(rd16(O.gsTokens)) .. " / 100" end,
  lr=function(d, big) local v = clamp(rd16(O.gsTokens) + d * (big and 10 or 1), 0, 100)
    wr16(O.gsTokens, v); setBit32(O.quest, 23, v > 0) end,
  a=function() wr16(O.gsTokens, 100); setBit32(O.quest, 23, true) end}

PAGES[#PAGES+1] = {title="Mision: canciones", rows={
  bitRow("Nana de Zelda", O.quest, 12), bitRow("Cancion de Epona", O.quest, 13),
  bitRow("Cancion de Saria", O.quest, 14), bitRow("Cancion del Sol", O.quest, 15),
  bitRow("Cancion del Tiempo", O.quest, 16), bitRow("Cancion de la Tormenta", O.quest, 17),
  bitRow("Minueto del Bosque", O.quest, 6), bitRow("Bolero del Fuego", O.quest, 7),
  bitRow("Serenata del Agua", O.quest, 8), bitRow("Requiem del Espiritu", O.quest, 9),
  bitRow("Nocturno de la Sombra", O.quest, 10), bitRow("Preludio de la Luz", O.quest, 11),
}}

PAGES[#PAGES+1] = {title="Mision: piedras y medallones", rows={
  bitRow("Esmeralda Kokiri", O.quest, 18), bitRow("Rubi Goron", O.quest, 19),
  bitRow("Zafiro Zora", O.quest, 20),
  bitRow("Medallon Bosque", O.quest, 0), bitRow("Medallon Fuego", O.quest, 1),
  bitRow("Medallon Agua", O.quest, 2), bitRow("Medallon Espiritu", O.quest, 3),
  bitRow("Medallon Sombra", O.quest, 4), bitRow("Medallon Luz", O.quest, 5),
  bitRow("Piedra de la Agonia", O.quest, 21), bitRow("Pase Gerudo", O.quest, 22),
  tokenRow,
}}

------------------------------------------------------------------------
-- Archivos
------------------------------------------------------------------------
local function loadFile(path)
  local h = io.open(path, FREAD)
  if not h then return false, "No se pudo abrir el archivo" end
  local size = tonumber(io.size(h))
  local data = io.read(h, 0, size)
  io.close(h)
  if size < 0x14DC then return false, "Archivo muy pequeno: no es una partida" end
  buf = {}
  for i = 1, size do buf[i-1] = string.byte(data, i) end
  bufLen = size
  crcAlg = detectCrc()
  if not crcAlg then buf = nil; return false, "Checksum no reconocido: no se edita" end
  filePath = path
  dirty = false
  return true
end

local function bufToString()
  local parts, chunk = {}, {}
  for i = 0, bufLen - 1 do
    chunk[#chunk+1] = string.char(buf[i])
    if #chunk == 512 then parts[#parts+1] = table.concat(chunk); chunk = {} end
  end
  parts[#parts+1] = table.concat(chunk)
  return table.concat(parts)
end

local function saveFile()
  syncMenus()
  writeChecksum()
  local data = bufToString()
  -- copia de seguridad la primera vez
  local bak = filePath .. ".orig"
  if not System.doesFileExist(bak) then
    local h0 = io.open(filePath, FREAD)
    local orig = io.read(h0, 0, tonumber(io.size(h0)))
    io.close(h0)
    local hb = io.open(bak, FCREATE)
    io.write(hb, 0, orig, orig:len())
    io.close(hb)
  end
  local h = io.open(filePath, FWRITE)
  io.write(h, 0, data, data:len())
  io.close(h)
  -- verificar
  local okAlg = detectCrc()
  dirty = false
  if okAlg then return true end
  return false
end

------------------------------------------------------------------------
-- Interfaz
------------------------------------------------------------------------
local pad, oldpad = Controls.read(), Controls.read()
local function pressed(k) return Controls.check(pad, k) and not Controls.check(oldpad, k) end

-- Dibujo solo cuando algo cambia, y 2 veces seguidas para que los dos
-- buffers de pantalla queden iguales (evita parpadeo y restos superpuestos).
local redraw = 2
local function anyKey() return pad ~= oldpad end
local function beginFrame()
  Screen.waitVblankStart()
  Screen.refresh()
  Screen.clear(TOP_SCREEN)
  Screen.clear(BOTTOM_SCREEN)
end
local function endFrame()
  Screen.flip()
end
-- Anchos reales de la fuente de LPP (debugPrint no recorta: si el texto
-- pasa el borde se escribe encima de otras cosas).
local GW = {6, 4, 11, 12, 12, 12, 12, 6, 6, 6, 12, 12, 6, 12, 5, 12, 12, 6, 12, 12, 12, 12, 12, 12, 12, 12, 5, 6, 8, 9, 8, 12, 12, 11, 11, 10, 11, 11, 11, 11, 11, 8, 11, 11, 9, 12, 12, 12, 11, 12, 11, 12, 12, 11, 12, 12, 12, 12, 12, 6, 12, 6, 10, 12, 6, 10, 10, 9, 10, 10, 8, 10, 10, 4, 9, 10, 6, 12, 10, 10, 10, 10, 10, 10, 8, 10, 12, 12, 10, 12, 10, 8, 4, 8, 12, 13}
local function charW(b) if b < 0x20 then return 6 end if b > 0x7F then b = 0x7F end return GW[b - 0x1F] end
local function textW(s) local w = 0 for i = 1, #s do w = w + charW(s:byte(i)) end return w end
local function clip(s, maxw)
  local w = 0
  for i = 1, #s do
    w = w + charW(s:byte(i))
    if w > maxw then return s:sub(1, i - 1) end
  end
  return s
end
local function clipLeft(s, maxw)
  local w = 0
  for i = #s, 1, -1 do
    w = w + charW(s:byte(i))
    if w > maxw then return s:sub(i + 1) end
  end
  return s
end
local function txt(x, y, s, c, scr, maxw)
  scr = scr or TOP_SCREEN
  s = tostring(s)
  local lim = (scr == TOP_SCREEN and 398 or 318) - x
  if maxw and maxw < lim then lim = maxw end
  Screen.debugPrint(x, y, clip(s, lim), c or WHITE, scr)
end
-- parte un texto en lineas que quepan en la pantalla de abajo
local function wrap(s, maxw)
  local lines, cur = {}, ""
  for word in s:gmatch("%S+") do
    local t = (cur == "" and word or cur .. " " .. word)
    if textW(t) <= maxw then cur = t else if cur ~= "" then lines[#lines+1] = cur end cur = word end
  end
  if cur ~= "" then lines[#lines+1] = cur end
  return lines
end

local function drawList(title, items, sel, scroll, top)
  txt(5, 5, title, YELLOW)
  local visible = 13
  for i = 1, visible do
    local idx = scroll + i
    local it = items[idx]
    if not it then break end
    local y = 20 + (i-1) * 15
    if idx == sel then Screen.fillRect(0, 399, y - 2, y + 11, SEL_BG, TOP_SCREEN) end
    if type(it) == "table" then
      local v = tostring(it.get())
      local vw = math.min(textW(v), 190)
      txt(4, y, it.label, idx == sel and WHITE or GREY, TOP_SCREEN, 398 - vw - 14)
      txt(398 - vw, y, v, idx == sel and CYAN or WHITE)
    else
      txt(4, y, it, idx == sel and WHITE or GREY)
    end
  end
  if #items > visible then local t = string.format("%d/%d", sel, #items); txt(398 - textW(t), 214, t, GREY) end
end

local function help(lines)
  for i, l in ipairs(lines) do txt(5, 5 + (i-1) * 15, l, WHITE, BOTTOM_SCREEN) end
  if message ~= "" then
    local ls = wrap(message, 310)
    for i = 1, math.min(#ls, 2) do txt(5, 200 + (i-1) * 15, ls[i], messageColor, BOTTOM_SCREEN) end
  end
end

local function fixScroll(sel, scroll) if sel <= scroll then return sel - 1 elseif sel > scroll + 13 then return sel - 13 end return scroll end

-- Explorador de archivos -------------------------------------------------
local function listDir(path)
  local ok, entries = pcall(System.listDirectory, path)
  if not ok or not entries then return {} end
  table.sort(entries, function(a, b) return a.name:lower() > b.name:lower() end)
  return entries
end

local function chooseFile()
  local path = SAVES_ROOT
  -- entrar directo a la carpeta de Ocarina 3D si existe
  for _, e in ipairs(listDir(SAVES_ROOT)) do
    if e.directory and (e.name:find("Ocarina") or e.name:find("0x00335") or e.name:find("0x00336")) then
      path = SAVES_ROOT .. "/" .. e.name
    end
  end
  local sel, scroll = 1, 0
  local entries = listDir(path)
  while true do
    pad = Controls.read()
    local names = {}
    for _, e in ipairs(entries) do names[#names+1] = (e.directory and "[" .. e.name .. "]" or e.name) end
    if #names == 0 then names = {"(carpeta vacia)"} end
    if pressed(KEY_DDOWN) then sel = math.min(sel + 1, #names) end
    if pressed(KEY_DUP) then sel = math.max(sel - 1, 1) end
    scroll = fixScroll(sel, scroll)
    if pressed(KEY_A) and entries[sel] then
      local e = entries[sel]
      local p = path .. "/" .. e.name
      if e.directory then path = p; entries = listDir(path); sel, scroll = 1, 0
      else
        local ok, err = loadFile(p)
        if ok then oldpad = pad; redraw = 2; return true end
        message, messageColor = err, RED
      end
    elseif pressed(KEY_B) then
      local parent = path:match("^(.*)/[^/]+$")
      if parent and parent ~= "" then path = parent; entries = listDir(path); sel, scroll = 1, 0 end
    elseif pressed(KEY_START) then
      System.exit()
    end
    if anyKey() then redraw = 2 end
    if redraw > 0 then
    redraw = redraw - 1
    beginFrame()
    drawList("Elige la partida", names, sel, scroll)
    help({"OoT3D Editor v" .. VERSION,
          clipLeft(path, 310),
          "", "1. Checkpoint: respalda",
          "    Ocarina 3D",
          "2. Aqui abre esa copia",
          "    (save00.bin)",
          "3. Edita y guarda: START",
          "4. Checkpoint: restaura",
          "", "A: abrir    B: subir",
          "START: salir"})
    endFrame()
    else Screen.waitVblankStart() end
    oldpad = pad
  end
end

-- Editor ----------------------------------------------------------------
local function editor()
  local page, sel, scroll = 1, 1, 0
  local confirmExit = false
  while true do
    pad = Controls.read()
    local rows = PAGES[page].rows
    if pressed(KEY_R) or pressed(KEY_ZR) then page = page % #PAGES + 1; sel, scroll = 1, 0; rows = PAGES[page].rows end
    if pressed(KEY_L) or pressed(KEY_ZL) then page = (page - 2) % #PAGES + 1; sel, scroll = 1, 0; rows = PAGES[page].rows end
    if pressed(KEY_DDOWN) then sel = math.min(sel + 1, #rows) end
    if pressed(KEY_DUP) then sel = math.max(sel - 1, 1) end
    local big = Controls.check(pad, KEY_Y)
    if pressed(KEY_DRIGHT) and rows[sel].lr then rows[sel].lr(1, big); message = "" end
    if pressed(KEY_DLEFT) and rows[sel].lr then rows[sel].lr(-1, big); message = "" end
    if pressed(KEY_A) and rows[sel].a then rows[sel].a(); message = "" end
    if pressed(KEY_START) then
      local ok = saveFile()
      if ok then message, messageColor = "Guardado. Ahora restaura la copia en Checkpoint.", GREEN
      else message, messageColor = "Guardado, pero el checksum no verifico.", RED end
    end
    if pressed(KEY_B) then
      if dirty and not confirmExit then
        confirmExit = true
        message, messageColor = "Sin guardar. Pulsa B otra vez", YELLOW
      else
        oldpad = pad
        redraw = 2
        return
      end
    end
    scroll = fixScroll(sel, scroll)
    if anyKey() then redraw = 2 end
    if redraw > 0 then
    redraw = redraw - 1
    beginFrame()
    drawList(string.format("%s  [%d/%d]", PAGES[page].title, page, #PAGES), rows, sel, scroll)
    help({clipLeft(filePath, 310),
          dirty and "* SIN GUARDAR" or "Sin cambios",
          "", "Arriba/Abajo: elegir",
          "Izq/Der: cambiar",
          "Y + Izq/Der: de 10 en 10",
          "A: maximo / activar",
          "L / R: cambiar pagina",
          "START: guardar",
          "B: volver"})
    endFrame()
    else Screen.waitVblankStart() end
    oldpad = pad
  end
end

while true do
  if chooseFile() then
    message = ""
    editor()
  end
end
