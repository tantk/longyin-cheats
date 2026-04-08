-- src/14_cheats_explore.lua — Exploration cheats (MT.cheats.explore)
-- ── Exploration ──────────────────────────────────────────────

MT.cheats.explore._horseState = nil

function MT.cheats.explore.horseSpeedEnable(multi)
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local horseItem = readQword(hero + 0x208)
  if not horseItem or horseItem == 0 then error("未装备坐骑 No horse equipped!") end
  local hdOff = 0x88
  local horseData = readQword(horseItem + hdOff)
  if not horseData or horseData == 0 then
    hdOff = 0x80
    horseData = readQword(horseItem + hdOff)
  end
  if not horseData or horseData == 0 then error("坐骑无数据 Horse has no HorseData") end
  local origSpeed = readFloat(horseData + 0x14)
  MT.cheats.explore._horseState = {addr = horseData + 0x14, val = origSpeed}
  writeFloat(horseData + 0x14, origSpeed * multi)
end

function MT.cheats.explore.horseSpeedDisable()
  local s = MT.cheats.explore._horseState
  if s then
    writeFloat(s.addr, s.val)
    MT.cheats.explore._horseState = nil
  end
end

function MT.cheats.explore.dungeonReveal()
  local c = MT.il2cpp.init()
  local ecClass = c.findClass("ExploreController")
  if not ecClass then error("探索控制器未找到 ExploreController not found") end
  local ecStatic = readQword(ecClass + 0xB8)
  if not ecStatic or ecStatic == 0 then error("ExploreController静态数据=0") end
  local ecInst = readQword(ecStatic + 0x8)
  if not ecInst or ecInst == 0 then error("未在迷宫中 Not in dungeon") end
  local inited = readBytes(ecInst + 0xD0, 1)
  if not inited or inited == 0 then error("请先进入迷宫 Enter a dungeon first") end
  local seeAllAddr = MT.method.findAddr(ecClass, "SeeAllTile", 0)
  if not seeAllAddr then error("SeeAllTile方法未找到 SeeAllTile not found") end
  local cb = getAddress("cmdBuf")
  if not cb or cb == 0 then error("未连接 Not connected (cmdBuf missing)") end
  writeQword(cb + 0x08, ecInst)
  writeQword(cb + 0x68, seeAllAddr)
  writeInteger(cb + 0x04, 0)
  writeInteger(cb, 6)
  local elapsed = 0
  while elapsed < 2000 do
    if readInteger(cb + 0x04) ~= 0 then break end
    sleep(16); elapsed = elapsed + 16
  end
  return "迷宫全开完成 Dungeon revealed!"
end

function MT.cheats.explore.infiniteStamina()
  local c = MT.il2cpp.init()
  local ecClass = c.findClass("ExploreController")
  if not ecClass then error("ExploreController not found") end
  local ecStatic = readQword(ecClass + 0xB8)
  if not ecStatic or ecStatic == 0 then error("ExploreController static=0") end
  local ecInst = readQword(ecStatic + 0x8)
  if not ecInst or ecInst == 0 then error("未在迷宫中 Not in dungeon") end
  writeInteger(ecInst + 0x98, 999)
  return "耐力已设为999 Stamina set to 999"
end
