-- src/03_game.lua — Game state helpers and method resolution (MT.game, MT.method)
-- ============================================================
-- MT.game -- getHero, getWorldData, isRunning, checkAlive
-- ============================================================
MT.game = {}

function MT.game.checkAlive()
  local gaAddr = getAddress("GameAssembly.dll")
  if not gaAddr or gaAddr < 0x100000 then
    error("Game not running - please reattach CE to the game")
  end
  local testRead = readBytes(gaAddr, 1)
  if not testRead then
    -- Stale CE state -- reinitialize symbol list
    reinitializeSymbolhandler()
    gaAddr = getAddress("GameAssembly.dll")
    if not gaAddr or gaAddr < 0x100000 then
      error("Stale CE state - please close CE and reopen")
    end
    testRead = readBytes(gaAddr, 1)
    if not testRead then
      error("Stale CE state - please close CE and reopen")
    end
  end
  return gaAddr
end

function MT.game.isRunning()
  local pid = getOpenedProcessID()
  if not pid or pid == 0 then return false end
  -- PID can be stale for dead process -- verify by reading memory
  local ga = getAddress("GameAssembly.dll")
  if not ga or ga < 0x100000 then return false end
  local b = readBytes(ga, 1)
  return b ~= nil
end

function MT.game.getHero()
  if not MT.game.isRunning() then return nil, "Game not running" end
  local c = MT.il2cpp.init()
  local inst = readQword(c.gc.static + c.gc.instOff)
  if not inst or inst == 0 then
    _il2cppCache = nil
    c = MT.il2cpp.init()
    inst = readQword(c.gc.static + c.gc.instOff)
    if not inst or inst == 0 then return nil, "GameController._instance null (load a save first)" end
  end
  local wd = readQword(inst + 0x20); if not wd or wd == 0 then return nil, "WorldData null" end
  local hl = readQword(wd + 0x50);  if not hl or hl == 0 then return nil, "HerosList null" end
  local ip = readQword(hl + 0x10);  if not ip or ip == 0 then return nil, "HerosList items null" end
  local h = readQword(ip + 0x20);   if not h or h == 0 then return nil, "Hero not found" end
  return h, inst
end

function MT.game.getWorldData()
  if not MT.game.isRunning() then return nil, "Game not running" end
  local c = MT.il2cpp.init()
  local inst = readQword(c.gc.static + c.gc.instOff)
  if not inst or inst == 0 then
    _il2cppCache = nil
    c = MT.il2cpp.init()
    inst = readQword(c.gc.static + c.gc.instOff)
    if not inst or inst == 0 then return nil, "GameController._instance null" end
  end
  local wd = readQword(inst + 0x20); if not wd or wd == 0 then return nil, "WorldData null" end
  return wd
end

-- ============================================================
-- MT.method -- findMethodAddr
-- ============================================================
MT.method = {}

function MT.method.findAddr(klass, methodName, paramCount)
  -- Single il2cpp call instead of iterating all methods
  local gmfn = getAddress("GameAssembly.il2cpp_class_get_method_from_name")
  local nm = allocateMemory(64); writeString(nm, methodName)
  local mi = executeCodeEx(0, nil, gmfn, klass, nm, paramCount or 0)
  deAlloc(nm)
  if not mi or mi == 0 then return nil end
  return readQword(mi) -- methodPointer at offset 0
end
