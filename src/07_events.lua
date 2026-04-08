-- src/07_events.lua — Event spawning (MT.events)
-- ============================================================
-- MT.events -- spawn
-- ============================================================
MT.events = {}

function MT.events.spawn(templateIdx, difficulty, timeout)
  local S = MT.hook.S
  if not S.ready or not S.cmdBuf then return false, "Connect first" end
  timeout = timeout or 5000
  local cb = S.cmdBuf

  -- Find WorldEventController
  local c = _il2cppCache
  if not c then return false, "il2cpp not ready" end
  local wecClass = c.findClass("WorldEventController")
  if not wecClass then return false, "WEC class not found" end
  local sf = readQword(wecClass + 0xB8)
  if not sf or sf == 0 then return false, "WEC static=0" end
  local wecInst = readQword(sf)
  if not wecInst or wecInst == 0 then return false, "WEC instance=0" end
  local dbList = readQword(wecInst + 0x18)
  if not dbList or dbList == 0 then return false, "DB list=0" end
  local dbCount = readInteger(dbList + 0x18)
  if templateIdx >= dbCount then return false, "Index out of range" end
  local items = readQword(dbList + 0x10)
  local template = readQword(items + 0x20 + templateIdx * 8)
  if not template or template == 0 then return false, "Template null" end

  local nameObj = readQword(template + 0x10)
  local evtName = ""
  if nameObj and nameObj ~= 0 then
    local nl = readInteger(nameObj + 0x10)
    if nl and nl > 0 and nl < 30 then evtName = readString(nameObj + 0x14, nl*2, true) or "" end
  end

  -- Step 1: Call 2-param CreateWorldEvent to handle area selection + clone + registration
  if not S.createWorldEventMI then
    local getMeth = getAddress("GameAssembly.il2cpp_class_get_method_from_name")
    local wecKlass = readQword(wecInst)
    local strBuf = allocateMemory(64)
    writeString(strBuf, "CreateWorldEvent")
    S.createWorldEventMI = executeCodeEx(0, nil, getMeth, wecKlass, strBuf, 1)
    deAlloc(strBuf)
    if not S.createWorldEventMI or S.createWorldEventMI == 0 then
      S.createWorldEventMI = nil
      return false, "CreateWorldEvent MI not found"
    end
    log(string.format("[SpawnEvent] CreateWorldEvent MI=%X", S.createWorldEventMI))
  end

  local riAddr = getAddress("GameAssembly.il2cpp_runtime_invoke")
  if not riAddr or riAddr == 0 then return false, "runtime_invoke not found" end

  -- Count events before spawn to find the new one after
  local gcC = MT.il2cpp.init()
  local gcInst = readQword(gcC.gc.static + gcC.gc.instOff)
  local worldData = gcInst and readQword(gcInst + 0x20) or 0
  local eventList = worldData ~= 0 and readQword(worldData + 0x80) or 0
  local countBefore = eventList ~= 0 and readInteger(eventList + 0x18) or 0

  -- Set difficultyRate on template so the game creates the icon with correct color
  -- Then override +0x64 after creation for exact difficulty
  local origRate = 0
  local rateObj = readQword(template + 0x50)
  if difficulty and difficulty > 0 and rateObj and rateObj ~= 0 then
    origRate = readFloat(rateObj + 0x68)
    writeFloat(rateObj + 0x68, difficulty * 1.0)
  end

  writeQword(cb + 0xA0, template)
  writeQword(cb + 0x90, S.createWorldEventMI)
  writeQword(cb + 0x88, wecInst)
  writeQword(cb + 0x68, riAddr)
  writeInteger(cb + 0x04, 0)
  writeInteger(cb, 8)
  local elapsed = 0
  while elapsed < timeout do
    local st = readInteger(cb + 0x04)
    if st and st ~= 0 then break end
    sleep(16); elapsed = elapsed + 16
  end

  -- Restore original difficultyRate
  if difficulty and difficulty > 0 and rateObj and rateObj ~= 0 then
    writeFloat(rateObj + 0x68, origRate)
  end

  local finalStatus = readInteger(cb + 0x04)
  if not finalStatus or finalStatus ~= 1 then return false, "CreateWorldEvent failed (status=" .. tostring(finalStatus) .. ")" end

  -- Override +0x64 to exact desired difficulty (difficultyRate * random gave approximate value)
  if difficulty and difficulty > 0 then
    eventList = readQword(worldData + 0x80)
    local countAfter = eventList ~= 0 and readInteger(eventList + 0x18) or 0
    if countAfter > countBefore then
      local evtItems = readQword(eventList + 0x10)
      local newEvt = readQword(evtItems + 0x20 + (countAfter - 1) * 8)
      if newEvt and newEvt ~= 0 then
        writeFloat(newEvt + 0x64, difficulty * 1.0)
      end
    end
  end

  return true, evtName
end
