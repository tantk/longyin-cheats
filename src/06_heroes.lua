-- src/06_heroes.lua — Hero generation functions (MT.heroes)
-- ============================================================
-- MT.heroes -- generate, generateNoFaction
-- ============================================================
MT.heroes = {}

function MT.heroes.generate(forceID, heroForceLv, sexLimit, timeout)
  local RVA = MT.hook.RVA
  local cb = getAddress("cmdBuf")
  if not cb or cb == 0 then return false, "cmdBuf not found" end
  local base = getAddress("GameAssembly.dll")
  if not base or base == 0 then return false, "GameAssembly not loaded" end
  if not RVA.genHeroData9 then return false, "GenerateHeroData(9) not resolved" end
  if not RVA.recruitHero then return false, "ManagePlayerRecruitHero not resolved" end
  timeout = timeout or 5000

  log(string.format("[GenHero] force=%d lv=%d sex=%d", forceID or 0, heroForceLv or 1, sexLimit or 0))
  log(string.format("[GenHero] RVAs: genHero9=%X recruit=%X npcSkill=%X npcItem=%X",
    RVA.genHeroData9, RVA.recruitHero, RVA.genNPCSkill or 0, RVA.genNPCItem or 0))
  log(string.format("[GenHero] Addrs: genHero9=%X recruit=%X",
    base + RVA.genHeroData9, base + RVA.recruitHero))

  -- cmd=5: GenerateHeroData(9) + ManagePlayerRecruitHero
  writeInteger(cb + 0x10, forceID or 0)
  writeFloat(cb + 0x14, (heroForceLv or 5) * 1.0)
  writeInteger(cb + 0x18, sexLimit or 0)
  writeQword(cb + 0x68, base + RVA.genHeroData9)
  writeQword(cb + 0x70, base + RVA.recruitHero)
  writeQword(cb + 0x78, RVA.genNPCSkill and (base + RVA.genNPCSkill) or 0)
  writeQword(cb + 0x80, RVA.genNPCItem and (base + RVA.genNPCItem) or 0)

  log(string.format("[GenHero] cmdBuf: [+10]=%d [+14]=%.1f [+18]=%d",
    readInteger(cb + 0x10), readFloat(cb + 0x14), readInteger(cb + 0x18)))
  log(string.format("[GenHero] cmdBuf: [+68]=%X [+70]=%X [+78]=%X [+80]=%X",
    readQword(cb + 0x68), readQword(cb + 0x70), readQword(cb + 0x78), readQword(cb + 0x80)))
  log(string.format("[GenHero] gc=%X hero=%X", readQword(cb + 0x20) or 0, readQword(cb + 0x28) or 0))

  writeInteger(cb + 0x04, 0)
  writeInteger(cb, 5)
  log("[GenHero] cmd=5 dispatched, waiting...")

  local elapsed = 0
  while elapsed < timeout do
    local status = readInteger(cb + 0x04)
    if status == 1 then
      local heroData = readQword(cb + 0x08)
      log(string.format("[GenHero] SUCCESS! heroData=%X", heroData or 0))
      return true, heroData
    elseif status == 2 then
      return false, "Generation failed"
    end
    sleep(16)
    elapsed = elapsed + 16
  end
  return false, "Timeout"
end

function MT.heroes.generateNoFaction(heroForceLv, timeout)
  local RVA = MT.hook.RVA
  local cb = getAddress("cmdBuf")
  if not cb or cb == 0 then return false, "cmdBuf not found" end
  local base = getAddress("GameAssembly.dll")
  if not RVA.worldAddHero then return false, "WorldAddNewHero not resolved" end
  timeout = timeout or 5000

  -- Use cmd=4 (doGenEquip) slot to call WorldAddNewHero
  -- WorldAddNewHero(gc, forceID=-1, heroForceLv, outSideForce=false)
  writeInteger(cb + 0x10, -1)
  writeInteger(cb + 0x14, heroForceLv or 1)
  writeFloat(cb + 0x18, 0)
  writeQword(cb + 0x68, base + RVA.worldAddHero)

  writeInteger(cb + 0x04, 0)
  writeInteger(cb, 4)

  local elapsed = 0
  while elapsed < timeout do
    local status = readInteger(cb + 0x04)
    if status == 1 then
      local heroData = readQword(cb + 0x08)
      return true, heroData
    elseif status == 2 then return false, "Failed"
    end
    sleep(16); elapsed = elapsed + 16
  end
  return false, "Timeout"
end
