-- src/05_items.lua — Item creation functions (MT.items)
-- ============================================================
-- MT.items -- addBook, addMaterial, addMedFood, addHorse,
--             addEquipGenerated, addEquipment, addTreasure
-- ============================================================
MT.items = {}

function MT.items.addBook(skillID, rareLv)
  local S = MT.hook.S
  if not S.ready then return false, "Connect first" end
  local ok, ptr = MT.hook.mainThreadCreateAndAdd(3, S.setBookAddr, skillID, rareLv, 0)
  if not ok then return false, ptr end
  return true, MT.hook.getItemName(ptr)
end

function MT.items.addMaterial(subType, itemLv, rareLv)
  local S = MT.hook.S
  local RVA = MT.hook.RVA
  if not S.ready or not S.cmdBuf then return false, "Connect first" end
  if not RVA.genMaterial then
    -- Fallback to old method if GenerateMaterial not resolved
    local ok, ptr = MT.hook.mainThreadCreateAndAdd(5, S.base + RVA.setMat, subType, itemLv, rareLv)
    if not ok then return false, ptr end
    return true, MT.hook.getItemName(ptr)
  end
  -- Use GenerateMaterial(materialType, itemLv, bossLv) via cmd=4
  -- bossLv is read from xmm3 (not r9!), cmd=4 sets xmm3 from [+0x18]
  writeInteger(S.cmdBuf + 0x10, subType)
  writeInteger(S.cmdBuf + 0x14, itemLv)
  writeFloat(S.cmdBuf + 0x18, rareLv * 1.0)
  writeQword(S.cmdBuf + 0x68, S.base + RVA.genMaterial)
  writeInteger(S.cmdBuf + 0x04, 0)
  writeInteger(S.cmdBuf, 4)
  local elapsed = 0
  while elapsed < 3000 do
    if readInteger(S.cmdBuf + 0x04) ~= 0 then break end
    sleep(16); elapsed = elapsed + 16
  end
  if readInteger(S.cmdBuf + 0x04) ~= 1 then return false, "Generation failed" end
  local newItem = readQword(S.cmdBuf + 0x08)
  if not newItem or newItem == 0 then return false, "Returned null" end
  local itemName = MT.hook.getItemName(newItem)
  local ok2, result = MT.hook.mainThreadGetItem(newItem)
  if not ok2 then return false, result end
  return true, itemName
end

function MT.items.addMedFood(dbIndex, dbOffset, bossLv)
  local S = MT.hook.S
  local RVA = MT.hook.RVA
  if not S.ready or not S.cmdBuf then return false, "Connect first" end
  bossLv = bossLv or 5
  local genRVA = (dbOffset == 0x110) and RVA.genMedById or RVA.genFoodById
  if not genRVA then return false, "Generate method not resolved" end

  -- Use game's GenerateMedData(id, bossLv) or GenerateFoodData(id, bossLv) via cmd=4
  -- cmd=4: rcx=GC, edx=[+0x10]=id, r8d=[+0x14]=bossLv, call [+0x68]
  writeInteger(S.cmdBuf + 0x10, dbIndex)
  writeInteger(S.cmdBuf + 0x14, 0)
  writeFloat(S.cmdBuf + 0x18, bossLv * 1.0)  -- bossLv via xmm2
  writeQword(S.cmdBuf + 0x68, S.base + genRVA)
  writeInteger(S.cmdBuf + 0x04, 0)
  writeInteger(S.cmdBuf, 4)
  local elapsed = 0
  while elapsed < 3000 do
    if readInteger(S.cmdBuf + 0x04) ~= 0 then break end
    sleep(16); elapsed = elapsed + 16
  end
  if readInteger(S.cmdBuf + 0x04) ~= 1 then return false, "Generation failed" end
  local newItem = readQword(S.cmdBuf + 0x08)
  if not newItem or newItem == 0 then return false, "Returned null" end

  local itemName = MT.hook.getItemName(newItem)
  local ok2, result = MT.hook.mainThreadGetItem(newItem)
  if not ok2 then return false, result end
  return true, itemName
end

function MT.items.addHorse(dbIndex, rareLv)
  local S = MT.hook.S
  local RVA = MT.hook.RVA
  if not S.ready or not S.cmdBuf then return false, "Connect first" end
  if not RVA.genHorseById then return false, "GenerateHorseData not resolved" end

  -- Use game's GenerateHorseData(id, bossLv) via cmd=4
  -- bossLv read from xmm2, cmd=4 sets xmm2 from [+0x18]
  writeInteger(S.cmdBuf + 0x10, dbIndex)
  writeInteger(S.cmdBuf + 0x14, 0)
  writeFloat(S.cmdBuf + 0x18, (rareLv or 5) * 1.0)
  writeQword(S.cmdBuf + 0x68, S.base + RVA.genHorseById)
  writeInteger(S.cmdBuf + 0x04, 0)
  writeInteger(S.cmdBuf, 4)
  local elapsed = 0
  while elapsed < 3000 do
    if readInteger(S.cmdBuf + 0x04) ~= 0 then break end
    sleep(16); elapsed = elapsed + 16
  end
  if readInteger(S.cmdBuf + 0x04) ~= 1 then return false, "Generation failed" end
  local newItem = readQword(S.cmdBuf + 0x08)
  if not newItem or newItem == 0 then return false, "Returned null" end

  -- Set 100% tame on the generated horse
  local horseData = readQword(newItem + S.OFF_HORSE)
  if horseData and horseData ~= 0 then
    writeFloat(horseData + 0x3C, 1.0)
  end

  local itemName = MT.hook.getItemName(newItem)
  local ok2, result = MT.hook.mainThreadGetItem(newItem)
  if not ok2 then return false, result end
  return true, itemName
end

function MT.items.addEquipGenerated(genRVA, dbIndex, bossLv, qualityRate, timeout)
  local S = MT.hook.S
  if not S.ready or not S.cmdBuf then return false, "Connect first" end
  timeout = timeout or 3000
  log(string.format("cmd4 GenEquip: RVA=%X idx=%d bossLv=%d rate=%.1f", genRVA, dbIndex, bossLv, qualityRate or 1.0))

  -- Write parameters to cmdBuf
  -- PARAMS SWAPPED: edx=bossLv, r8d=weaponIndex (confirmed by test)
  writeInteger(S.cmdBuf + 0x10, bossLv)        -- param1 (edx): boss level (stat scaling)
  writeInteger(S.cmdBuf + 0x14, dbIndex)       -- param2 (r8): weapon/armor DB index
  writeFloat(S.cmdBuf + 0x18, qualityRate or 1.0) -- param3 (xmm3): quality rate
  writeQword(S.cmdBuf + 0x68, S.base + genRVA)

  -- Trigger cmd=4
  writeInteger(S.cmdBuf + 0x04, 0)  -- clear status
  writeInteger(S.cmdBuf, 4)         -- set command

  -- Wait for completion
  local elapsed = 0
  while elapsed < timeout do
    local status = readInteger(S.cmdBuf + 0x04)
    if status == 1 then
      local newItem = readQword(S.cmdBuf + 0x08)
      if not newItem or newItem == 0 then return false, "Generator returned null" end
      local itemName = MT.hook.getItemName(newItem)
      log("Generated: " .. itemName .. " at " .. toHex(newItem))
      -- Apply affix preset if enabled (replaces random extraAddData)
      local affixRoot = nil
      if MT.cheats and MT.cheats.affix and MT.cheats.affix.enabled then
        local rootOk, rootResult = MT.cheats.affix.rootItem(newItem)
        if rootOk and rootResult and rootResult ~= 0 then
          affixRoot = rootResult
          local affixOk, affixErr = MT.cheats.affix.applyTo(newItem)
          if not affixOk then log("Affix preset failed: " .. tostring(affixErr)) end
        else
          log("Affix preset skipped: failed to root generated item (" .. tostring(rootResult) .. ")")
        end
      end
      -- Now add to inventory via cmd=1
      local ok2, _ = MT.hook.mainThreadGetItem(newItem)
      if affixRoot then
        local freeOk, freeErr = MT.cheats.affix.releaseRoot(affixRoot)
        if not freeOk then log("Affix preset root release failed: " .. tostring(freeErr)) end
      end
      if not ok2 then return false, "GetItem failed" end
      return true, itemName
    elseif status == 2 then
      return false, "Generator failed (status=2)"
    end
    sleep(16)
    elapsed = elapsed + 16
  end
  -- Timeout: dump full cmdBuf state for diagnosis
  local dCmd = readInteger(S.cmdBuf) or -1
  local dStatus = readInteger(S.cmdBuf + 0x04) or -1
  local dResult = readQword(S.cmdBuf + 0x08) or 0
  local dGC = readQword(S.cmdBuf + 0x20) or 0
  local dGate = readInteger(S.cmdBuf + 0x38) or -1
  local dHB = readInteger(S.cmdBuf + 0x40) or -1
  local dFunc = readQword(S.cmdBuf + 0x68) or 0
  local dump = string.format(
    "TIMEOUT DUMP: cmd=%d status=%d result=%s gc=%s gate=%d heartbeat=%d func=%s",
    dCmd, dStatus, toHex(dResult), toHex(dGC), dGate, dHB, toHex(dFunc))
  log(dump)
  return false, dump
end

function MT.items.addEquipment(dbOff, dbIndex, desiredLv, desiredRare)
  local S = MT.hook.S
  if not S.ready then return false, "Connect first" end
  if not S.gdc or S.gdc == 0 then return false, "GDC not found" end

  local db = readQword(S.gdc + dbOff)
  if not db or db == 0 then return false, "DataBase null" end
  local items = readQword(db + 0x10)
  local count = readInteger(db + 0x18)
  if dbIndex >= count then return false, string.format("Index %d >= count %d", dbIndex, count) end
  local template = readQword(items + 0x20 + dbIndex * 8)
  if not template or template == 0 then return false, "Template null" end

  -- Create new ItemData (type=0 for equipment)
  local ok2, ni = MT.hook.mainThreadAllocCtor(0)
  if not ok2 or not ni or ni == 0 then return false, "alloc fail" end

  -- Copy base ItemData fields from template
  writeInteger(ni + 0x10, readInteger(template + 0x10) or 0)  -- itemID
  writeInteger(ni + 0x18, readInteger(template + 0x18) or 0)  -- subType
  writeQword(ni + 0x20, readQword(template + 0x20) or 0)      -- name
  writeQword(ni + 0x28, readQword(template + 0x28) or 0)      -- checkName
  writeQword(ni + 0x30, readQword(template + 0x30) or 0)      -- describe
  writeInteger(ni + 0x38, readInteger(template + 0x38) or 0)   -- value
  writeInteger(ni + 0x3C, desiredLv or 3)                       -- itemLv
  writeInteger(ni + 0x40, desiredRare or 5)                     -- rareLv
  writeFloat(ni + 0x44, readFloat(template + 0x44) or 1.0)     -- weight

  -- Clone EquipmentData and generate stats from best existing equipment
  local templateEqd = readQword(template + 0x60)
  if templateEqd and templateEqd ~= 0 then
    local eqdClass = readQword(templateEqd)
    local newEqd = executeCodeEx(0, nil, S.objNew, eqdClass)
    if newEqd and newEqd ~= 0 then
      -- Copy all EquipmentData fields (0x10 to 0x4C)
      for off = 0x10, 0x4C, 4 do
        writeInteger(newEqd + off, readInteger(templateEqd + off) or 0)
      end
      writeQword(newEqd + 0x38, readQword(templateEqd + 0x38) or 0) -- animName
      writeQword(newEqd + 0x40, readQword(templateEqd + 0x40) or 0) -- equipPoisonData

      -- Find best existing equipment in inventory to clone stats from
      local bestBaseAdd = nil
      local bestExtraAdd = nil
      local bestLv = -1
      local heroIld = readQword(S.hero + 0x220)
      if heroIld and heroIld ~= 0 then
        local heroAllItem = readQword(heroIld + 0x28)
        if heroAllItem and heroAllItem ~= 0 then
          local heroItemCount = readInteger(heroAllItem + 0x18) or 0
          local heroItemArr = readQword(heroAllItem + 0x10)
          if heroItemArr and heroItemArr ~= 0 then
            for ii = 0, heroItemCount - 1 do
              local invItem = readQword(heroItemArr + 0x20 + ii * 8)
              if invItem and invItem ~= 0 and readInteger(invItem + 0x14) == 0 then
                local invEqd = readQword(invItem + 0x60)
                if invEqd and invEqd ~= 0 then
                  local invLv = readInteger(invItem + 0x3C) or 0
                  if invLv > bestLv then
                    bestLv = invLv
                    bestBaseAdd = readQword(invEqd + 0x20)
                    bestExtraAdd = readQword(invEqd + 0x28)
                  end
                end
              end
            end
          end
        end
      end

      -- Copy stat pointers from best existing equipment (pure memory, no executeCodeEx)
      if bestBaseAdd and bestBaseAdd ~= 0 then
        writeQword(newEqd + 0x20, bestBaseAdd)
        log("Copied baseAddData from lv " .. bestLv .. " equipment")
      else
        writeQword(newEqd + 0x20, readQword(templateEqd + 0x20) or 0)
      end

      if bestExtraAdd and bestExtraAdd ~= 0 then
        writeQword(newEqd + 0x28, bestExtraAdd)
      else
        writeQword(newEqd + 0x28, readQword(templateEqd + 0x28) or 0)
      end

      writeQword(ni + 0x60, newEqd)
    else
      writeQword(ni + 0x60, templateEqd) -- fallback
    end
  end

  local ok3, result = MT.hook.mainThreadGetItem(ni)
  if not ok3 then return false, result end
  return true, MT.hook.getItemName(ni)
end

function MT.items.addTreasure(typeIdx, rareLv, bossLv, timeout)
  local S = MT.hook.S
  if not S.ready or not S.cmdBuf then return false, "Connect first" end
  timeout = timeout or 3000
  bossLv = bossLv or 5
  -- edx=typeIdx, r8d=rareLv, xmm3=bossLv (same pattern as GenerateWeapon)
  writeInteger(S.cmdBuf + 0x10, typeIdx)
  writeInteger(S.cmdBuf + 0x14, rareLv)
  writeFloat(S.cmdBuf + 0x18, bossLv * 1.0)
  writeQword(S.cmdBuf + 0x68, S.base + MT.hook.TREASURE_GEN_RVA)
  writeInteger(S.cmdBuf + 0x04, 0)
  writeInteger(S.cmdBuf, 4)
  local elapsed = 0
  while elapsed < timeout do
    local status = readInteger(S.cmdBuf + 0x04)
    if status == 1 then
      local newItem = readQword(S.cmdBuf + 0x08)
      if not newItem or newItem == 0 then return false, "Generator returned null" end
      local itemName = MT.hook.getItemName(newItem)
      local ok2, _ = MT.hook.mainThreadGetItem(newItem)
      if not ok2 then return false, "GetItem failed" end
      return true, itemName
    elseif status == 2 then
      return false, "Generator failed"
    end
    sleep(16)
    elapsed = elapsed + 16
  end
  return false, "Timeout"
end

-- ============================================================
-- MT.cheats.affix -- Predetermined random affix override
-- ============================================================
-- When enabled, replaces the random extraAddData (random affixes) on every
-- equipment generated via addEquipGenerated. baseAddData (rarity-tier stats)
-- is left untouched. Preset is in-memory only (does NOT persist across CT reloads).
MT.cheats = MT.cheats or {}
MT.cheats.affix = {
  preset = {},     -- array of {statID = int, value = float}; zero-value rows are removed
  enabled = false, -- global toggle
}

-- MI cache keyed by GA base — auto-invalidates on game restart.
local _affixMI = {gaBase = nil, reset = nil, set = nil, countValue = nil}
local _affixGCHandleNew = nil
local _affixGCHandleFree = nil

-- Compatibility for older UI code: no affix IDs are blocked.
function MT.cheats.affix.blockReason(statID) return nil end
function MT.cheats.affix.isBlockedStatID(statID) return false end

local function _validateAffixRow(row)
  local sid = tonumber(row and row.statID)
  local value = tonumber(row and row.value)
  if not sid or sid < 0 or sid > 214 or sid ~= math.floor(sid) then
    return false, nil, nil, "invalid stat id"
  end
  if not value or value == 0 then return false, sid, value, "zero value" end
  if value ~= value or value == math.huge or value == -math.huge then
    return false, sid, value, "non-finite value"
  end
  return true, sid, value
end

local function _resolveAffixMethods()
  local c = MT.il2cpp.init()
  if _affixMI.gaBase == c._gaBase and _affixMI.reset and _affixMI.set and _affixMI.countValue then return true end
  _affixMI.reset = nil; _affixMI.set = nil; _affixMI.countValue = nil
  local cls = c.findClass("HeroSpeAddData")
  if not cls then return false, "HeroSpeAddData class not found" end
  local itemCls = c.findClass("ItemData")
  if not itemCls then return false, "ItemData class not found" end
  local getMeth = getAddress("GameAssembly.il2cpp_class_get_method_from_name")
  if not getMeth or getMeth == 0 then return false, "class_get_method_from_name unavailable" end
  local nmR = allocateMemory(16); writeString(nmR, "Reset")
  local nmS = allocateMemory(16); writeString(nmS, "Set")
  local nmC = allocateMemory(32); writeString(nmC, "CountValueAndWeight")
  local r = executeCodeEx(0, nil, getMeth, cls, nmR, 0)
  local s = executeCodeEx(0, nil, getMeth, cls, nmS, 2)
  local cv = executeCodeEx(0, nil, getMeth, itemCls, nmC, 0)
  deAlloc(nmR); deAlloc(nmS); deAlloc(nmC)
  if not r or r == 0 then return false, "Reset MI missing" end
  if not s or s == 0 then return false, "Set MI missing" end
  if not cv or cv == 0 then return false, "CountValueAndWeight MI missing" end
  _affixMI.gaBase = c._gaBase
  _affixMI.reset = r
  _affixMI.set = s
  _affixMI.countValue = cv
  return true
end

local function _resolveGCHandleExports()
  if _affixGCHandleNew and _affixGCHandleFree then return true end
  _affixGCHandleNew = getAddress("GameAssembly.il2cpp_gchandle_new")
  _affixGCHandleFree = getAddress("GameAssembly.il2cpp_gchandle_free")
  if not _affixGCHandleNew or _affixGCHandleNew == 0 then return false, "gchandle_new missing" end
  if not _affixGCHandleFree or _affixGCHandleFree == 0 then return false, "gchandle_free missing" end
  return true
end

function MT.cheats.affix.rootItem(itemPtr)
  if not itemPtr or itemPtr == 0 then return false, "null item" end
  local ok, err = _resolveGCHandleExports()
  if not ok then return false, err end
  return MT.hook.mainThreadSimpleCall(_affixGCHandleNew, itemPtr)
end

function MT.cheats.affix.releaseRoot(handle)
  if not handle or handle == 0 then return true end
  local ok, err = _resolveGCHandleExports()
  if not ok then return false, err end
  return MT.hook.mainThreadSimpleCall(_affixGCHandleFree, handle)
end

-- Persistence (preset only; toggle state is per-session).
function MT.cheats.affix.save()
  if not MT.config or not MT.config.set then return end
  local parts = {}
  for _, r in ipairs(MT.cheats.affix.preset) do
    if r.statID and r.value and r.value ~= 0 then
      parts[#parts + 1] = string.format("%d:%g", r.statID, r.value)
    end
  end
  pcall(MT.config.set, "affix.preset", table.concat(parts, ","))
end

function MT.cheats.affix.load()
  if not MT.config or not MT.config.get then return end
  local enc = MT.config.get("affix.preset", "")
  MT.cheats.affix.preset = {}
  if type(enc) == "string" and enc ~= "" then
    for pair in enc:gmatch("[^,]+") do
      local k, v = pair:match("^(%d+):(.+)$")
      if k and v then
        local sid = tonumber(k); local sv = tonumber(v)
        if sid and sv then
          table.insert(MT.cheats.affix.preset, {statID = sid, value = sv})
        end
      end
    end
  end
end

function MT.cheats.affix.applyTo(itemPtr)
  if not itemPtr or itemPtr == 0 then return false, "null item" end
  local eqd = readQword(itemPtr + 0x60)
  if not eqd or eqd == 0 then return true end  -- not equipment, silently skip
  local extra = readQword(eqd + 0x28)
  if not extra or extra == 0 then return false, "no extraAddData" end

  local ok, err = _resolveAffixMethods()
  if not ok then return false, err end

  -- 1) Clear all existing random affixes
  ok, err = MT.hook.invokeRuntime(extra, _affixMI.reset, nil)
  if not ok then return false, "Reset: " .. tostring(err) end

  -- 2) Write preset entries
  if #MT.cheats.affix.preset == 0 then return true end
  local keyBuf = allocateMemory(4)
  local valBuf = allocateMemory(4)
  local applied = 0
  local skipped = 0
  for _, row in ipairs(MT.cheats.affix.preset) do
    local rowOk, sid, value, reason = _validateAffixRow(row)
    if rowOk then
      writeInteger(keyBuf, sid)
      writeFloat(valBuf, value)
      ok, err = MT.hook.invokeRuntime(extra, _affixMI.set, {keyBuf, valBuf})
      if not ok then
        deAlloc(keyBuf); deAlloc(valBuf)
        return false, string.format("Set(%d,%g): %s", sid, value, tostring(err))
      end
      applied = applied + 1
    elseif reason ~= "zero value" then
      skipped = skipped + 1
      log(string.format("Affix preset skipped %s: %s", tostring(sid or "?"), tostring(reason)))
    end
  end
  deAlloc(keyBuf); deAlloc(valBuf)
  if applied > 0 then
    ok, err = MT.hook.invokeRuntime(itemPtr, _affixMI.countValue, nil)
    if not ok then log("Affix preset CountValueAndWeight failed: " .. tostring(err)) end
  end
  log(string.format("Affix preset applied: %d stats, skipped: %d", applied, skipped))
  return true
end
