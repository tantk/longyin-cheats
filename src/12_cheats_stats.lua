-- src/12_cheats_stats.lua — Stat cheats including toggles (MT.cheats.stats)
-- ── Stats ────────────────────────────────────────────────────

function MT.cheats.stats.restoreHP()
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local maxhp = readFloat(hero + 0x17C)
  writeFloat(hero + 0x178, maxhp)
  return string.format("生命已恢复至 %.0f", maxhp)
end

function MT.cheats.stats.clearInjury()
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  writeFloat(hero + 0x1A0, 0.0)
  writeFloat(hero + 0x1A4, 0.0)
  writeFloat(hero + 0x1A8, 0.0)
  return "所有伤势已清除 Injuries cleared"
end

function MT.cheats.stats.setStatCaps(val)
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local capValue = tonumber(val) or 99.0
  local lists = {0x130, 0x148, 0x160}
  local total = 0
  for _, offset in ipairs(lists) do
    local listPtr = readQword(hero + offset)
    if listPtr and listPtr ~= 0 then
      local count = readInteger(listPtr + 0x18)
      local items = readQword(listPtr + 0x10)
      if items and items ~= 0 and count then
        for j = 0, count - 1 do
          local cur = readFloat(items + 0x20 + j * 4)
          if cur and capValue > cur then
            writeFloat(items + 0x20 + j * 4, capValue)
            total = total + 1
          end
        end
      end
    end
  end
  return string.format("已提升 %d 项属性上限至 %.0f", total, capValue)
end

function MT.cheats.stats.setTalentPoints(val)
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local v = tonumber(val) or 10
  writeFloat(hero + 0x35C, v * 1.0)
  return string.format("天赋点已设置为 %.0f", v)
end

function MT.cheats.stats.setSkillLimit(val)
  local limit = tonumber(val) or 99
  local c = MT.il2cpp.init()
  if not c:ensure("gd", "GlobalData", nil, {skillOff=0x138}) then error("GlobalData未加载 GlobalData not loaded") end
  local listPtr = readQword(c.gd.static + c.gd.skillOff)
  if not listPtr or listPtr == 0 then error("武学数据未找到 MaxSkillNum list not found") end
  local count = readInteger(listPtr + 0x18)
  local items = readQword(listPtr + 0x10)
  for i = 0, count - 1 do
    writeFloat(items + 0x20 + i * 4, limit)
  end
  return string.format("已将 %d 级武学上限设为 %d Set %d tiers to %d", count, limit, count, limit)
end

function MT.cheats.stats.setFame(val)
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local v = tonumber(val) or 1000
  writeFloat(hero + 0x1C4, v * 1.0)
  writeFloat(hero + 0x1C8, 0.0)  -- clear bad fame
  return string.format("声望已设置为 %.0f, 恶名已清除", v)
end

function MT.cheats.stats.maxNpcFavor()
  local wd = MT.game.getWorldData()
  if not wd then error("世界数据为空 WorldData null") end
  local herosList = readQword(wd + 0x50)
  if not herosList or herosList == 0 then error("角色列表为空 HerosList null") end
  local heroCount = readInteger(herosList + 0x18)
  local itemsPtr = readQword(herosList + 0x10)
  if not itemsPtr or itemsPtr == 0 then error("角色数据为空 HerosList items null") end
  local boosted = 0
  for i = 1, heroCount - 1 do
    local npc = readQword(itemsPtr + 0x20 + i * 8)
    if npc and npc ~= 0 then
      writeFloat(npc + 0x124, 100.0)
      boosted = boosted + 1
    end
  end
  return string.format("已将 %d 个NPC好感设为 100", boosted)
end

function MT.cheats.stats.maxFactionAffinity()
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local playerForceID = readInteger(hero + 0x84)
  local wd = MT.game.getWorldData()
  if not wd then error("世界数据为空 WorldData null") end
  local forces = readQword(wd + 0x48)
  if not forces or forces == 0 then error("门派数据为空 Forces null") end
  local forceItems = readQword(forces + 0x10)
  local forceCount = readInteger(forces + 0x18)
  local changed = 0
  -- Set all factions' favor toward player's faction to 100
  for i = 0, forceCount - 1 do
    local fd = readQword(forceItems + 0x20 + i * 8)
    if fd and fd ~= 0 then
      local fid = readInteger(fd + 0x10)
      if fid ~= playerForceID then
        local listPtr = readQword(fd + 0xD0)
        if listPtr and listPtr ~= 0 then
          local itemsArr = readQword(listPtr + 0x10)
          local size = readInteger(listPtr + 0x18)
          if itemsArr and itemsArr ~= 0 and playerForceID < size then
            writeFloat(itemsArr + 0x20 + playerForceID * 4, 100.0)
            changed = changed + 1
          end
        end
      end
    end
  end
  -- Also set player's faction favor toward all others
  local playerFD = nil
  for i = 0, forceCount - 1 do
    local fd = readQword(forceItems + 0x20 + i * 8)
    if fd and fd ~= 0 and readInteger(fd + 0x10) == playerForceID then playerFD = fd; break end
  end
  if playerFD then
    local listPtr = readQword(playerFD + 0xD0)
    if listPtr and listPtr ~= 0 then
      local itemsArr = readQword(listPtr + 0x10)
      local size = readInteger(listPtr + 0x18)
      if itemsArr and itemsArr ~= 0 then
        for j = 0, size - 1 do
          if j ~= playerForceID then
            writeFloat(itemsArr + 0x20 + j * 4, 100.0)
          end
        end
      end
    end
  end
  return string.format("已将 %d 个门派好感设为 100", changed)
end

-- ── Stats: Talent Slots (toggle) ────────────────────────────

MT.cheats.stats._talentSlotState = nil

function MT.cheats.stats.talentSlotEnable(slots)
  local n = math.floor(slots)
  local c = MT.il2cpp.init()
  if not c:ensure("hd", "HeroData") then error("HeroData未加载 HeroData not loaded yet") end
  local targetAddr = MT.method.findAddr(c.hd.klass, "GetMaxTagNum")
  if not targetAddr or targetAddr == 0 then error("GetMaxTagNum未找到 GetMaxTagNum not found") end
  local origBytes = {}
  for i = 0, 5 do origBytes[i+1] = readBytes(targetAddr + i, 1) end
  MT.cheats.stats._talentSlotState = {addr = targetAddr, orig = origBytes}
  -- mov eax, N; ret (encode N as 4-byte little-endian)
  writeBytes(targetAddr, {0xB8, n % 256, math.floor(n/256) % 256, math.floor(n/65536) % 256, math.floor(n/16777216) % 256, 0xC3})
end

function MT.cheats.stats.talentSlotDisable()
  local s = MT.cheats.stats._talentSlotState
  if s and s.orig and s.addr then
    for i = 1, #s.orig do writeBytes(s.addr + i - 1, s.orig[i]) end
    MT.cheats.stats._talentSlotState = nil
  end
end

-- ── Stats: Combat EXP Buff (toggle) ─────────────────────────

MT.cheats.stats._combatExpState = nil

function MT.cheats.stats.combatExpEnable(pct)
  local multi = pct / 100.0
  local c = MT.il2cpp.init()
  if not c:ensure("gdc", "GameDataController", 0x20, {tagBaseOff=0x198}) then error("GDC未加载 GDC not loaded") end
  local gdcInstance = readQword(c.gdc.static + c.gdc.instOff)
  if not gdcInstance or gdcInstance == 0 then error("GDC实例未找到 GDC instance not found") end
  local tagDataBase = readQword(gdcInstance + c.gdc.tagBaseOff)
  if not tagDataBase or tagDataBase == 0 then error("天赋数据为空 heroTagDataBase null") end
  local tagItems = readQword(tagDataBase + 0x10)
  if not tagItems or tagItems == 0 then error("天赋数据项为空 tagDataBase items null") end
  local tag222 = readQword(tagItems + 0x20 + 222 * 8)
  if not tag222 or tag222 == 0 then error("Tag222未找到 Tag 222 not found in DB") end
  local buffData = readQword(tag222 + 0x50)
  if not buffData or buffData == 0 then error("Tag222 buffData为空 Tag 222 buffData null") end
  local dict = readQword(buffData + 0x10)
  if not dict or dict == 0 then error("buffData字典为空 buffData dict null") end
  local entries = readQword(dict + 0x18)
  if not entries or entries == 0 then error("字典项为空 dict entries null") end
  local cnt = readInteger(dict + 0x20)
  local buffAddrs = {}
  for i = 0, cnt - 1 do
    local base = entries + 0x20 + i * 16
    local key = readInteger(base + 8)
    if key == 176 then buffAddrs.fight = base + 12 end
    if key == 177 then buffAddrs.book = base + 12 end
  end
  local origFight = buffAddrs.fight and readFloat(buffAddrs.fight) or 0
  local origBook = buffAddrs.book and readFloat(buffAddrs.book) or 0
  if buffAddrs.fight then writeFloat(buffAddrs.fight, multi) end
  if buffAddrs.book then writeFloat(buffAddrs.book, multi) end
  MT.cheats.stats._combatExpState = {addrs = buffAddrs, origFight = origFight, origBook = origBook}
end

function MT.cheats.stats.combatExpDisable()
  local s = MT.cheats.stats._combatExpState
  if s and s.addrs then
    if s.addrs.fight and s.origFight then writeFloat(s.addrs.fight, s.origFight) end
    if s.addrs.book and s.origBook then writeFloat(s.addrs.book, s.origBook) end
    MT.cheats.stats._combatExpState = nil
  end
end

-- ── Stats: Living EXP Buff (toggle) ─────────────────────────

MT.cheats.stats._livingExpState = nil

function MT.cheats.stats.livingExpEnable(pct)
  local multi = pct / 100.0
  local c = MT.il2cpp.init()
  if not c:ensure("gdc", "GameDataController", 0x20, {tagBaseOff=0x198}) then error("GDC未加载 GDC not loaded") end
  local gdcInstance = readQword(c.gdc.static + c.gdc.instOff)
  if not gdcInstance or gdcInstance == 0 then error("GDC实例未找到 GDC instance not found") end
  local tagDataBase = readQword(gdcInstance + c.gdc.tagBaseOff)
  if not tagDataBase or tagDataBase == 0 then error("天赋数据为空 heroTagDataBase null") end
  local tagItems = readQword(tagDataBase + 0x10)
  if not tagItems or tagItems == 0 then error("天赋数据项为空 tagDataBase items null") end
  local tag243 = readQword(tagItems + 0x20 + 243 * 8)
  if not tag243 or tag243 == 0 then error("Tag243未找到 Tag 243 not found in DB") end
  local buffData = readQword(tag243 + 0x50)
  if not buffData or buffData == 0 then error("Tag243 buffData为空 Tag 243 buffData null") end
  local dict = readQword(buffData + 0x10)
  if not dict or dict == 0 then error("buffData字典为空 buffData dict null") end
  local entries = readQword(dict + 0x18)
  if not entries or entries == 0 then error("字典项为空 dict entries null") end
  local cnt = readInteger(dict + 0x20)
  local livingAddr = nil
  for i = 0, cnt - 1 do
    local base = entries + 0x20 + i * 16
    local key = readInteger(base + 8)
    if key == 178 then livingAddr = base + 12 end
  end
  local origVal = livingAddr and readFloat(livingAddr) or 0
  if livingAddr then writeFloat(livingAddr, multi) end
  MT.cheats.stats._livingExpState = {addr = livingAddr, origVal = origVal}
end

function MT.cheats.stats.livingExpDisable()
  local s = MT.cheats.stats._livingExpState
  if s and s.addr and s.origVal then
    writeFloat(s.addr, s.origVal)
    MT.cheats.stats._livingExpState = nil
  end
end

-- ── Stats: Character Creation ────────────────────────────────

function MT.cheats.stats.getStartMenuController()
  local c = MT.il2cpp.init()
  local klass = c.findClass("StartMenuController")
  if not klass then error("请先进入角色创建界面 [Enter character creation screen first]") end
  local sf = readQword(klass + 0xB8)
  local inst = readQword(sf)
  if not inst or inst == 0 then error("请先进入创建界面 StartMenuController instance null") end
  return inst, klass
end

function MT.cheats.stats.setAttrPoints(val)
  MT.game.checkAlive()
  local smc = MT.cheats.stats.getStartMenuController()
  local v = tonumber(val) or 999
  writeInteger(smc + 0x80, math.floor(v))
  return string.format("属性点已设置为 %d", v)
end

function MT.cheats.stats.setFightPoints(val)
  MT.game.checkAlive()
  local smc = MT.cheats.stats.getStartMenuController()
  local v = tonumber(val) or 999
  writeInteger(smc + 0x84, math.floor(v))
  return string.format("武学点已设置为 %d", v)
end

function MT.cheats.stats.setLivingPoints(val)
  MT.game.checkAlive()
  local smc = MT.cheats.stats.getStartMenuController()
  local v = tonumber(val) or 999
  writeInteger(smc + 0x88, math.floor(v))
  return string.format("生活点已设置为 %d", v)
end

function MT.cheats.stats.setCreationTalentPoints(val)
  MT.game.checkAlive()
  local c = MT.il2cpp.init()
  local klass = c.findClass("StartGameSettingController")
  if not klass then error("请先进入角色创建界面 [Enter character creation screen first]") end
  local sf = readQword(klass + 0xB8)
  local inst = readQword(sf)
  if not inst or inst == 0 then error("StartGameSettingController instance null") end
  local player = readQword(inst + 0x18)
  if not player or player == 0 then error("请先进入角色创建界面 [Player data null]") end
  local v = tonumber(val) or 999
  writeFloat(player + 0x35C, v * 1.0)
  return string.format("创建天赋点已设置为 %d", v)
end

MT.cheats.stats._ccTagSlotOrig = nil

function MT.cheats.stats.creationTalentSlotEnable(slots)
  MT.game.checkAlive()
  local n = math.floor(slots)
  if n < 1 or n > 99 then error("天赋槽范围1-99") end
  local c = MT.il2cpp.init()
  local klass = c.findClass("StartMenuController")
  if not klass then error("请先进入角色创建界面 [Enter character creation screen first]") end

  local chooseAddr = MT.method.findAddr(klass, "StartChooseTagClicked", 1)
  if not chooseAddr then error("StartChooseTagClicked not found") end
  local refreshAddr = MT.method.findAddr(klass, "RefreshTagMenu", 0)
  if not refreshAddr then error("RefreshTagMenu not found") end

  local origPatches = {}

  -- Patch 1: StartChooseTagClicked — scan for 83 78 18 05 (cmp [rax+18h], 5)
  local found1 = false
  for off = 0, 0x400 do
    local a = chooseAddr + off
    if readBytes(a, 1) == 0x83 and readBytes(a+2, 1) == 0x18 and readBytes(a+3, 1) == 0x05 then
      origPatches[1] = {addr = a+3, val = readBytes(a+3, 1)}
      writeBytes(a+3, n)
      found1 = true
      break
    end
  end

  -- Patch 2: RefreshTagMenu — scan for 83 F8 05 (cmp eax, 5)
  local found2 = false
  for off = 0, 0x1000 do
    local a = refreshAddr + off
    if readBytes(a, 1) == 0x83 and readBytes(a+1, 1) == 0xF8 and readBytes(a+2, 1) == 0x05 then
      origPatches[2] = {addr = a+2, val = readBytes(a+2, 1)}
      writeBytes(a+2, n)
      found2 = true
      break
    end
  end

  if not found1 or not found2 then
    -- Restore any partial patches
    for _, o in ipairs(origPatches) do writeBytes(o.addr, o.val) end
    error(string.format("Only found %d/2 patch locations", (found1 and 1 or 0) + (found2 and 1 or 0)))
  end

  MT.cheats.stats._ccTagSlotOrig = origPatches
end

function MT.cheats.stats.creationTalentSlotDisable()
  local patches = MT.cheats.stats._ccTagSlotOrig
  if patches then
    for _, o in ipairs(patches) do writeBytes(o.addr, o.val) end
    MT.cheats.stats._ccTagSlotOrig = nil
  end
end
