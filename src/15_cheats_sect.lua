-- src/15_cheats_sect.lua — Sect management cheats (MT.cheats.sect)
-- ── Sect ─────────────────────────────────────────────────────

-- Helper: iterate all living sect members, return list of hero pointers
function MT.cheats.sect.getSectMembers()
  MT.game.checkAlive()
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local playerForceID = readInteger(hero + 0x84)
  if not playerForceID then error("无法读取门派ID Cannot read belongForceID") end
  local wd = MT.game.getWorldData()
  local hl = readQword(wd + 0x50)
  if not hl or hl == 0 then error("角色列表为空 HerosList null") end
  local heroCount = readInteger(hl + 0x18)
  local itemsPtr = readQword(hl + 0x10)
  if not itemsPtr or itemsPtr == 0 then error("角色数据为空 HerosList items null") end
  local members = {}
  for i = 0, heroCount - 1 do
    local h = readQword(itemsPtr + 0x20 + i * 8)
    if h and h ~= 0 then
      local dead = readBytes(h + 0x61, 1)
      local fid = readInteger(h + 0x84)
      if fid == playerForceID and dead == 0 then
        table.insert(members, h)
      end
    end
  end
  if #members == 0 then error("无存活门派成员 No living sect members found") end
  return members, playerForceID
end

-- Helper: get the player's ForceData
function MT.cheats.sect.getPlayerForceData()
  MT.game.checkAlive()
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local playerForceID = readInteger(hero + 0x84)
  local wd = MT.game.getWorldData()
  local forces = readQword(wd + 0x48)
  local forceItems = readQword(forces + 0x10)
  local forceCount = readInteger(forces + 0x18)
  for i = 0, forceCount - 1 do
    local fd = readQword(forceItems + 0x20 + i * 8)
    if fd and fd ~= 0 and readInteger(fd + 0x10) == playerForceID then
      return fd, playerForceID
    end
  end
  error("门派数据未找到 Player ForceData not found")
end

MT.cheats.sect._memberLimitHook = nil

function MT.cheats.sect.memberLimitEnable(newLimit)
  MT.game.checkAlive()
  local c = MT.il2cpp.init()
  local fdClass = c.findClass("ForceData")
  if not fdClass then error("ForceData类未找到 ForceData class not found") end
  local gmfn = getAddress("GameAssembly.il2cpp_class_get_method_from_name")
  local nm = allocateMemory(64)

  -- Resolve BOTH methods before patching anything (atomic: both or neither)
  writeString(nm, "GetMaxHeroNum")
  local mi1 = executeCodeEx(0, nil, gmfn, fdClass, nm, 0)
  if not mi1 or mi1 == 0 then deAlloc(nm); error("GetMaxHeroNum未找到 not found") end
  local target1 = readQword(mi1)

  writeString(nm, "PopulationNotFull")
  local mi2 = executeCodeEx(0, nil, gmfn, fdClass, nm, 0)
  if not mi2 or mi2 == 0 then deAlloc(nm); error("PopulationNotFull未找到 not found") end
  local target2 = readQword(mi2)
  deAlloc(nm)

  -- Both resolved — now patch
  local orig1 = readBytes(target1, 14, true)
  local cave = allocateMemory(64, target1) or allocateMemory(64)
  local valueAddr = cave + 16
  writeFloat(valueAddr, newLimit * 1.0)
  local ripOff = (cave + 16) - (cave + 8)
  writeBytes(cave, 0xF3, 0x0F, 0x10, 0x05)
  writeInteger(cave + 4, ripOff)
  writeBytes(cave + 8, 0xC3)

  local jmpRel = cave - (target1 + 5)
  if jmpRel < -0x80000000 or jmpRel > 0x7FFFFFFF then
    deAlloc(cave)
    error("Cave too far for E9 rel32 — ASLR placement issue")
  end
  if jmpRel < 0 then jmpRel = 0x100000000 + jmpRel end
  writeBytes(target1, 0xE9)
  writeBytes(target1 + 1, jmpRel % 256, math.floor(jmpRel/256) % 256,
             math.floor(jmpRel/65536) % 256, math.floor(jmpRel/16777216) % 256)
  writeBytes(target1 + 5, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90)

  local orig2 = readBytes(target2, 3, true)
  writeBytes(target2, 0xB0, 0x01, 0xC3)  -- mov al,1; ret

  MT.cheats.sect._memberLimitHook = {
    target1 = target1, orig1 = orig1,
    target2 = target2, orig2 = orig2,
    cave = cave
  }
end

function MT.cheats.sect.memberLimitDisable()
  local h = MT.cheats.sect._memberLimitHook
  if h then
    for i, b in ipairs(h.orig1) do
      writeBytes(h.target1 + i - 1, b)
    end
    for i, b in ipairs(h.orig2) do
      writeBytes(h.target2 + i - 1, b)
    end
    deAlloc(h.cave)
    MT.cheats.sect._memberLimitHook = nil
  end
end

function MT.cheats.sect.setSectTalentPoints(val)
  local pts = tonumber(val) or 99
  local members = MT.cheats.sect.getSectMembers()
  for _, h in ipairs(members) do
    writeFloat(h + 0x35C, pts * 1.0)
  end
  return string.format("%d人天赋点已设%d", #members, pts)
end

function MT.cheats.sect.setSectTalentSlots(val)
  local slots = tonumber(val) or 99
  local c2 = MT.il2cpp.init()
  if not c2:ensure("hd", "HeroData") then error("HeroData未加载 HeroData not loaded") end
  local targetAddr = MT.method.findAddr(c2.hd.klass, "GetMaxTagNum")
  if not targetAddr or targetAddr == 0 then error("GetMaxTagNum未找到 GetMaxTagNum not found") end
  _sectTalentCapPatches = {}
  for i = 0, 5 do _sectTalentCapPatches[i+1] = readBytes(targetAddr + i, 1) end
  local b0 = slots % 256
  local b1 = math.floor(slots / 256) % 256
  local b2 = math.floor(slots / 65536) % 256
  local b3 = math.floor(slots / 16777216) % 256
  writeBytes(targetAddr, {0xB8, b0, b1, b2, b3, 0xC3})
  return string.format("天赋槽上限已设%d", slots)
end

function MT.cheats.sect.sectProdigy()
  local cb = getAddress("cmdBuf")
  if not cb or cb == 0 then error("请先连接 cmdBuf not found - connect first") end

  local c = MT.il2cpp.init()
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local playerForceID = readInteger(hero + 0x84)
  local wd = MT.game.getWorldData()
  local hl = readQword(wd + 0x50)
  local heroCount = readInteger(hl + 0x18)
  local itemsPtr = readQword(hl + 0x10)

  -- Resolve AddTag MethodInfo
  local hdClass = c.hd and c.hd.klass or c.findClass("HeroData")
  if not hdClass then error("HeroData类未找到 HeroData class not found") end
  local getMethods = getAddress("GameAssembly.il2cpp_class_get_methods")
  local getMethodName = getAddress("GameAssembly.il2cpp_method_get_name")
  local riAddr = getAddress("GameAssembly.il2cpp_runtime_invoke")

  local addTagMI = nil
  local iter = allocateMemory(8); writeQword(iter, 0)
  while true do
    local mi = executeCodeEx(0, nil, getMethods, hdClass, iter)
    if not mi or mi == 0 then break end
    local np = executeCodeEx(0, nil, getMethodName, mi)
    if np and readString(np, 64) == "AddTag" and not addTagMI then addTagMI = mi end
  end
  deAlloc(iter)
  if not addTagMI then error("AddTag方法未找到 AddTag MethodInfo not found") end

  -- Check if hero has a given tag
  local function heroHasTag(h, tagID)
    local tagList = readQword(h + 0x360)
    if not tagList or tagList == 0 then return false end
    local count = readInteger(tagList + 0x18)
    local items = readQword(tagList + 0x10)
    if not items or items == 0 then return false end
    for j = 0, count - 1 do
      local tag = readQword(items + 0x20 + j * 8)
      if tag and tag ~= 0 and readInteger(tag + 0x10) == tagID then return true end
    end
    return false
  end

  -- Call AddTag on main thread via hookCode cmd=8 (runtime_invoke)
  local function mainThreadAddTag(heroPtr, tagID)
    local vals = allocateMemory(32)
    writeInteger(vals + 0, tagID)
    writeFloat(vals + 4, -1.0)         -- permanent
    writeInteger(vals + 8, 0)          -- showInfo = false
    writeInteger(vals + 12, 0)         -- needFreshHeroDetail = false
    writeQword(cb + 0xA0, vals + 0)   -- params[0] = &id
    writeQword(cb + 0xA8, vals + 4)   -- params[1] = &time
    writeQword(cb + 0xB0, 0)          -- params[2] = null (string source)
    writeQword(cb + 0xB8, vals + 8)   -- params[3] = &showInfo
    writeQword(cb + 0xC0, vals + 12)  -- params[4] = &needFreshHeroDetail
    writeQword(cb + 0x90, addTagMI)
    writeQword(cb + 0x88, heroPtr)
    writeQword(cb + 0x68, riAddr)
    writeInteger(cb + 0x04, 0)
    writeInteger(cb, 8)
    local elapsed = 0
    while elapsed < 2000 do
      if readInteger(cb + 0x04) ~= 0 then break end
      sleep(16); elapsed = elapsed + 16
    end
    deAlloc(vals)
    return readInteger(cb + 0x04) == 1
  end

  local count222 = 0
  local count243 = 0
  for i = 0, heroCount - 1 do
    local h = readQword(itemsPtr + 0x20 + i * 8)
    if h and h ~= 0 then
      local dead = readBytes(h + 0x61, 1)
      local fid = readInteger(h + 0x84)
      if fid == playerForceID and dead == 0 then
        if not heroHasTag(h, 222) then
          if mainThreadAddTag(h, 222) then count222 = count222 + 1 end
        end
        if not heroHasTag(h, 243) then
          if mainThreadAddTag(h, 243) then count243 = count243 + 1 end
        end
      end
    end
  end
  return string.format("武学天才+%d人, 博学多才+%d人", count222, count243)
end

function MT.cheats.sect.maxLoyalty()
  local members = MT.cheats.sect.getSectMembers()
  for _, h in ipairs(members) do
    writeFloat(h + 0x1CC, 100.0)
  end
  return string.format("%d人忠诚度已设100", #members)
end

function MT.cheats.sect.maxSkillSlots()
  local members = MT.cheats.sect.getSectMembers()
  local count = 0
  for _, h in ipairs(members) do
    local mfs = readQword(h + 0x148)
    if mfs and mfs ~= 0 then
      local cnt = readInteger(mfs + 0x18)
      local items = readQword(mfs + 0x10)
      if items and items ~= 0 then
        for j = 0, cnt - 1 do
          writeFloat(items + 0x20 + j * 4, 120.0)
        end
        count = count + 1
      end
    end
  end
  return string.format("%d人武学槽位已设120", count)
end

function MT.cheats.sect.maxResources()
  local playerFD = MT.cheats.sect.getPlayerForceData()
  local rs = readQword(playerFD + 0x88)
  local rsItems = readQword(rs + 0x10)
  local rsSize = readInteger(rs + 0x18)
  local rm = readQword(playerFD + 0x90)
  local rmItems = readQword(rm + 0x10)
  local filled = 0
  for i = 0, rsSize - 1 do
    local mx = readFloat(rmItems + 0x20 + i * 4)
    writeFloat(rsItems + 0x20 + i * 4, mx)
    filled = filled + 1
  end
  return string.format("%d项资源已填满", filled)
end

MT.cheats.sect._noCostPatches = nil

function MT.cheats.sect.noCostEnable()
  MT.game.checkAlive()
  local c = MT.il2cpp.init()
  local fdClass = c.findClass("ForceData")
  if not fdClass then error("ForceData类未找到 ForceData not found") end
  local getMethods = getAddress("GameAssembly.il2cpp_class_get_methods")
  local getMethodName = getAddress("GameAssembly.il2cpp_method_get_name")

  MT.cheats.sect._noCostPatches = {}
  local iter = allocateMemory(8); writeQword(iter, 0)
  local patched = {}
  while true do
    local mi = executeCodeEx(0, nil, getMethods, fdClass, iter)
    if not mi or mi == 0 then break end
    local namePtr = executeCodeEx(0, nil, getMethodName, mi)
    if namePtr and namePtr ~= 0 then
      local mname = readString(namePtr, 64)
      if mname == "CostResource" then
        local addr = readQword(mi)
        if addr and addr ~= 0 and not patched[addr] then
          local origByte = readBytes(addr, 1)
          table.insert(MT.cheats.sect._noCostPatches, {addr=addr, orig=origByte})
          patched[addr] = true
          writeBytes(addr, 0xC3)  -- ret immediately
        end
      end
    end
  end
  deAlloc(iter)
  if #MT.cheats.sect._noCostPatches == 0 then error("CostResource方法未找到 No CostResource methods found") end
end

function MT.cheats.sect.noCostDisable()
  if MT.cheats.sect._noCostPatches then
    for _, p in ipairs(MT.cheats.sect._noCostPatches) do
      writeBytes(p.addr, p.orig)
    end
    MT.cheats.sect._noCostPatches = nil
  end
end

function MT.cheats.sect.research100()
  local playerFD = MT.cheats.sect.getPlayerForceData()
  local activeID = readInteger(playerFD + 0x128)
  if activeID < 0 then error("当前无研究 [No active research]") end
  local tld = readQword(playerFD + 0x130)
  local tldItems = readQword(tld + 0x10)
  local tldCnt = readInteger(tld + 0x18)
  for i = 0, tldCnt - 1 do
    local e = readQword(tldItems + 0x20 + i * 8)
    if e and e ~= 0 and readInteger(e + 0x10) == activeID then
      writeFloat(e + 0x18, 1.0)
      return string.format("研究%d进度已设100%%, 等1天完成", activeID)
    end
  end
  error("研究" .. activeID .. "未找到 Active tech not found in techLvData")
end

function MT.cheats.sect.build1Day()
  MT.game.checkAlive()
  local wd = MT.game.getWorldData()
  local areas = readQword(wd + 0x30)
  if not areas or areas == 0 then error("区域数据为空 Areas null") end
  local areaCount = readInteger(areas + 0x18)
  local areaItems = readQword(areas + 0x10)
  if not areaItems or areaItems == 0 then error("区域数据为空 Area items null") end
  local completed = 0
  for i = 0, areaCount - 1 do
    local area = readQword(areaItems + 0x20 + i * 8)
    if area and area ~= 0 then
      local tiles = readQword(area + 0xC0)
      if tiles and tiles ~= 0 then
        local tileCount = readInteger(tiles + 0x18)
        local tileItems = readQword(tiles + 0x10)
        if tileCount and tileItems and tileItems ~= 0 then
          for t = 0, tileCount - 1 do
            local tile = readQword(tileItems + 0x20 + t * 8)
            if tile and tile ~= 0 then
              local bldg = readQword(tile + 0x28)
              if bldg and bldg ~= 0 then
                local bt = readInteger(bldg + 0x18) or 0
                local ut = readInteger(bldg + 0x1C) or 0
                local dt = readInteger(bldg + 0x20) or 0
                if bt > 0 then writeInteger(bldg + 0x18, 1); completed = completed + 1 end
                if ut > 0 then writeInteger(bldg + 0x1C, 1); completed = completed + 1 end
                if dt > 0 then writeInteger(bldg + 0x20, 1); completed = completed + 1 end
              end
            end
          end
        end
      end
    end
  end
  return string.format("%d个建筑操作剩余1天", completed)
end
