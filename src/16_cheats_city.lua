-- src/16_cheats_city.lua — City planner cheats (MT.cheats.city)
-- ============================================================
-- Read/mutate area tile grids and instantly swap buildings.
-- Uses GameController's DestroyBuilding / BuildingBuildStart / BuildBuilding
-- via il2cpp_runtime_invoke. All 3 calls execute on the main thread via cmd=8.
-- ============================================================
MT.cheats = MT.cheats or {}
MT.cheats.city = {}

-- MI cache keyed by GA base — auto-invalidates on game restart.
local _cityMI = {gaBase = nil, destroy = nil, buildStart = nil, buildDone = nil, upgrade = nil}

local function _resolveCityMethods()
  local c = MT.il2cpp.init()
  if _cityMI.gaBase == c._gaBase and _cityMI.destroy and _cityMI.buildStart
     and _cityMI.buildDone and _cityMI.upgrade then return true end
  _cityMI.destroy = nil; _cityMI.buildStart = nil
  _cityMI.buildDone = nil; _cityMI.upgrade = nil
  if not c.gc or not c.gc.klass then return false, "GameController class not resolved" end
  local getMeth = getAddress("GameAssembly.il2cpp_class_get_method_from_name")
  if not getMeth or getMeth == 0 then return false, "il2cpp_class_get_method_from_name unavailable" end
  local function resolve(name, n)
    local nb = allocateMemory(32); writeString(nb, name)
    local m = executeCodeEx(0, nil, getMeth, c.gc.klass, nb, n)
    deAlloc(nb)
    return (m and m ~= 0) and m or nil
  end
  local d  = resolve("DestroyBuilding", 3)
  local bs = resolve("BuildingBuildStart", 3)
  local bd = resolve("BuildBuilding", 3)
  local up = resolve("UpgradeBuilding", 3)
  if not d  then return false, "DestroyBuilding MI missing" end
  if not bs then return false, "BuildingBuildStart MI missing" end
  if not bd then return false, "BuildBuilding MI missing" end
  if not up then return false, "UpgradeBuilding MI missing" end
  _cityMI.gaBase = c._gaBase
  _cityMI.destroy, _cityMI.buildStart, _cityMI.buildDone, _cityMI.upgrade = d, bs, bd, up
  return true
end

-- ============================================================
-- Read helpers
-- ============================================================

-- Returns list of AreaData pointers owned by the player (belongForceID matches).
function MT.cheats.city.getPlayerAreas()
  MT.game.checkAlive()
  local hero = MT.game.getHero()
  if not hero then error("Hero null") end
  local playerForceID = readInteger(hero + 0x84)
  local wd = MT.game.getWorldData()
  if not wd then error("WorldData null") end
  local areasList = readQword(wd + 0x30)
  if not areasList or areasList == 0 then return {} end
  local items = readQword(areasList + 0x10)
  local count = readInteger(areasList + 0x18) or 0
  local out = {}
  for i = 0, count - 1 do
    local a = readQword(items + 0x20 + i * 8)
    if a and a ~= 0 then
      local fid = readInteger(a + 0x70) or 0
      if fid == 0xFFFFFFFF then fid = -1 end  -- normalize unsigned read
      if fid == playerForceID then
        table.insert(out, a)
      end
    end
  end
  return out
end

-- Read an area's name (UTF-16 string)
function MT.cheats.city.getAreaName(area)
  if not area or area == 0 then return "" end
  local np = readQword(area + 0x18)
  if not np or np == 0 then return "" end
  local nl = readInteger(np + 0x10) or 0
  if nl <= 0 then return "" end
  return readString(np + 0x14, math.min(nl, 100) * 2, true) or ""
end

-- Returns {width, height, tiles=[{ptr,row,col,tileType,buildingID,buildingLv,buildingName,protected}, ...]}
function MT.cheats.city.getAreaGrid(area)
  if not area or area == 0 then return nil end
  local w = readInteger(area + 0xB8) or 0
  local h = readInteger(area + 0xBC) or 0
  local tilesList = readQword(area + 0xC0)
  if not tilesList or tilesList == 0 then return {width=w, height=h, tiles={}} end
  local items = readQword(tilesList + 0x10)
  local count = readInteger(tilesList + 0x18) or 0
  local tiles = {}
  for i = 0, count - 1 do
    local t = readQword(items + 0x20 + i * 8)
    if t and t ~= 0 then
      local entry = {
        ptr = t,
        row = readInteger(t + 0x44) or 0,
        col = readInteger(t + 0x48) or 0,
        tileType = readInteger(t + 0x30) or 0,
        buildingID = -1, buildingLv = 0, buildingName = "", protected = false,
        roadLv = 0, isRoad = false,
      }
      local bp = readQword(t + 0x28)
      if bp and bp ~= 0 then
        local rawID = readInteger(bp + 0x10) or -1
        if rawID == 0xFFFFFFFF then rawID = -1 end  -- CE readInteger returns unsigned
        entry.buildingID = rawID
        entry.buildingLv = readInteger(bp + 0x14) or 0
        entry.protected = (rawID == -1)
      end
      local rp = readQword(t + 0x38)  -- areaRoadData
      if rp and rp ~= 0 then
        local rLv = readInteger(rp + 0x14) or 0
        -- Out-of-range = the object was probably GC'd and memory reused.
        -- Treat as no road so the UI doesn't show garbage.
        if rLv < 0 or rLv > 100 then
          entry.isRoad = false
        else
          entry.isRoad = true
          entry.roadLv = rLv
        end
      end
      table.insert(tiles, entry)
    end
  end
  return {width = w, height = h, tiles = tiles}
end

-- Returns array of {id, name} for all entries in GameDataController.buildingDataBase
function MT.cheats.city.getAllBuildings()
  local c = MT.il2cpp.init()
  if not c.gdc then c:ensure("gdc", "GameDataController", 0x20) end
  local gdcInst = readQword(c.gdc.static + c.gdc.instOff)
  if not gdcInst or gdcInst == 0 then return {} end
  local lst = readQword(gdcInst + 0xE0)  -- buildingDataBase
  if not lst or lst == 0 then return {} end
  local items = readQword(lst + 0x10)
  local count = readInteger(lst + 0x18) or 0
  local out = {}
  for i = 0, count - 1 do
    local b = readQword(items + 0x20 + i * 8)
    if b and b ~= 0 then
      local np = readQword(b + 0x10)
      local name = ""
      if np and np ~= 0 then
        local nl = readInteger(np + 0x10) or 0
        if nl > 0 then name = readString(np + 0x14, math.min(nl, 50) * 2, true) or "" end
      end
      table.insert(out, {id = i, name = name})
    end
  end
  return out
end

-- ============================================================
-- Write: instant tile-building swap
-- ============================================================

-- Swap the building on `tile` to `newBuildingID` instantly, optionally upgrading
-- to `newLv` (1 = no upgrade; max effective is 10 per game's UpgradeBuilding cap).
-- Sequence:
--   1) DestroyBuilding(area, tile, false)   -- nulls tile.building if present
--   2) BuildingBuildStart(tile, newID, false)  -- allocates new AreaBuildingData
--   3) Write newBuildingData.buildTimeLeft = 0
--   4) BuildBuilding(area, newBuildingData, false)  -- applies all effects (lv=1)
--   5) For i = 2..newLv, call UpgradeBuilding(area, newBldg, false)
function MT.cheats.city.swapTileBuilding(area, tile, newBuildingID, newLv)
  if not area or area == 0 then return false, "area null" end
  if not tile or tile == 0 then return false, "tile null" end
  newLv = tonumber(newLv) or 1
  if newLv < 1 then newLv = 1 end
  if newLv > 10 then newLv = 10 end
  local ok, err = _resolveCityMethods()
  if not ok then return false, err end
  local c = MT.il2cpp.init()
  local gcInst = readQword(c.gc.static + c.gc.instOff)
  if not gcInst or gcInst == 0 then return false, "GameController instance null" end

  -- Refuse special tiles (CityWall=-1, CityGate=-2, Null=-3). These shouldn't
  -- accept buildings; calling BuildingBuildStart on them risks corruption.
  local curType = readInteger(tile + 0x30) or 0
  if curType < 0 then
    return false, string.format("tile is protected (tileType=%d)", curType)
  end

  -- Refuse protected (center / obstacle) buildings (buildingID == -1)
  local curBldg = readQword(tile + 0x28)
  if curBldg and curBldg ~= 0 then
    local bid = readInteger(curBldg + 0x10) or 0
    if bid == -1 or bid == 0xFFFFFFFF then
      return false, "tile has protected building (id=-1)"
    end
  end

  -- Scratch buffers for value-type args
  local boolBuf = allocateMemory(1); writeBytes(boolBuf, 0)         -- showInfo = false
  local idBuf   = allocateMemory(4); writeInteger(idBuf, newBuildingID)

  local function cleanup()
    deAlloc(boolBuf); deAlloc(idBuf)
  end

  -- 1) Destroy current (if any)
  if curBldg and curBldg ~= 0 then
    ok, err = MT.hook.invokeRuntime(gcInst, _cityMI.destroy, {area, tile, boolBuf})
    if not ok then cleanup(); return false, "Destroy: " .. tostring(err) end
  end

  -- 2) Start build
  ok, err = MT.hook.invokeRuntime(gcInst, _cityMI.buildStart, {tile, idBuf, boolBuf})
  if not ok then cleanup(); return false, "BuildStart: " .. tostring(err) end

  -- 3) Skip build time on the new AreaBuildingData
  local newBldg = readQword(tile + 0x28)
  if not newBldg or newBldg == 0 then cleanup(); return false, "new building not assigned to tile" end
  writeInteger(newBldg + 0x18, 0)  -- buildTimeLeft

  -- 4) Complete build (applies production / effects, lv=1)
  ok, err = MT.hook.invokeRuntime(gcInst, _cityMI.buildDone, {area, newBldg, boolBuf})
  if not ok then cleanup(); return false, "Build: " .. tostring(err) end

  -- 5) Upgrade to desired lv (each call adds +1, applies all side effects)
  for _ = 2, newLv do
    ok, err = MT.hook.invokeRuntime(gcInst, _cityMI.upgrade, {area, newBldg, boolBuf})
    if not ok then cleanup(); return false, "Upgrade: " .. tostring(err) end
  end

  cleanup()
  return true, string.format("swapped (lv %d)", newLv)
end

-- Delete the building on a tile via GameController.DestroyBuilding RPC.
-- Returns false if there is no building or it's protected (id=-1).
function MT.cheats.city.deleteBuilding(area, tile)
  if not area or area == 0 then return false, "area null" end
  if not tile or tile == 0 then return false, "tile null" end
  local cur = readQword(tile + 0x28)
  if not cur or cur == 0 then return false, "no building on this tile" end
  if readInteger(cur + 0x10) == -1 then
    return false, "protected building (id=-1)"
  end
  local ok, err = _resolveCityMethods()
  if not ok then return false, err end
  local c = MT.il2cpp.init()
  local gcInst = readQword(c.gc.static + c.gc.instOff)
  if not gcInst or gcInst == 0 then return false, "GameController instance null" end
  local boolBuf = allocateMemory(1); writeBytes(boolBuf, 0)
  ok, err = MT.hook.invokeRuntime(gcInst, _cityMI.destroy, {area, tile, boolBuf})
  deAlloc(boolBuf)
  if not ok then return false, "Destroy: " .. tostring(err) end
  return true, "building deleted"
end

-- Set the roadLv of an existing road on a single tile.
-- Refuses if the tile has no road (we do NOT allocate new road objects — that
-- path turned out to be unstable on irregular town layouts and could wipe an
-- entire city). Safe operation: just rewrites the level field + clears the
-- per-road upgrade timer.
function MT.cheats.city.setRoadLevel(area, tile, lv)
  if not tile or tile == 0 then return false, "tile null" end
  local road = readQword(tile + 0x38)
  if not road or road == 0 then return false, "此格不是道路 (no road on this tile)" end
  lv = tonumber(lv) or 1
  if lv < 1 then lv = 1 end
  if lv > 99 then lv = 99 end
  writeInteger(road + 0x14, lv)   -- roadLv
  writeInteger(road + 0x18, 0)    -- upgradeTimeLeft
  if area and area ~= 0 then
    pcall(function() writeBytes(area + 0xF0, 1) end)
  end
  return true, string.format("道路等级 → %d", lv)
end

-- Upgrade every road tile in an area to `targetLv` (1-5 typical).
-- Roads have no game-side upgrade method; we write roadLv directly + clear
-- upgradeTimeLeft. Returns (ok, msg, count).
function MT.cheats.city.upgradeAllRoads(area, targetLv)
  if not area or area == 0 then return false, "area null", 0 end
  targetLv = tonumber(targetLv) or 3
  if targetLv < 1 then targetLv = 1 end
  if targetLv > 99 then targetLv = 99 end
  local tilesList = readQword(area + 0xC0)
  if not tilesList or tilesList == 0 then return false, "tile list null", 0 end
  local items = readQword(tilesList + 0x10)
  local count = readInteger(tilesList + 0x18) or 0
  local upgraded = 0
  for i = 0, count - 1 do
    local t = readQword(items + 0x20 + i * 8)
    if t and t ~= 0 then
      local road = readQword(t + 0x38)
      if road and road ~= 0 then
        local curLv = readInteger(road + 0x14) or 0
        -- Treat out-of-range values as garbage from a freed-then-reused road object
        if curLv < 0 or curLv > 100 then curLv = 0 end
        if curLv < targetLv then
          writeInteger(road + 0x14, targetLv)   -- roadLv
          writeInteger(road + 0x18, 0)          -- upgradeTimeLeft
          upgraded = upgraded + 1
        end
      end
    end
  end
  -- Mark area dirty so UI repaints
  pcall(function() writeBytes(area + 0xF0, 1) end)
  return true, string.format("%d roads → lv %d", upgraded, targetLv), upgraded
end
