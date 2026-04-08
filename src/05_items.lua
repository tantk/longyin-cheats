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
      -- Now add to inventory via cmd=1
      local ok2, _ = MT.hook.mainThreadGetItem(newItem)
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
