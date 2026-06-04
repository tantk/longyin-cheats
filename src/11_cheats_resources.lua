-- src/11_cheats_resources.lua — Cheat namespace init + resource cheats (MT.cheats.resources)
-- ============================================================
-- MT.cheats -- Cheat Logic Functions
-- ============================================================
MT.cheats = MT.cheats or {}
MT.cheats.resources = MT.cheats.resources or {}
MT.cheats.stats = MT.cheats.stats or {}
MT.cheats.battle = MT.cheats.battle or {}
MT.cheats.explore = MT.cheats.explore or {}
MT.cheats.sect = MT.cheats.sect or {}

-- ── Resources ────────────────────────────────────────────────

function MT.cheats.resources.setMoney(val)
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local itemListData = readQword(hero + 0x220)
  if not itemListData or itemListData == 0 then error("物品数据未找到 ItemListData not found") end
  writeInteger(itemListData + 0x18, math.floor(tonumber(val) or 9999))
  return string.format("银两已设置为 %d", tonumber(val) or 9999)
end

-- Personal house-storage weight cap (个人仓库上限, HeroData.selfStorage @0x228).
-- ItemListData.maxWeight is a float at +0x20. The game RECOMPUTES it back to the
-- default (1120) on house events, so a one-shot reverts. This is a FREEZE toggle:
-- a dedicated timer re-applies the value every ~200ms so it holds. Storage doesn't
-- delete over-cap items (just blocks adding), so the freeze is safe. NB: the game
-- REJECTS maxWeight >= 99999, so values are clamped to 99998 (use ~99000 to be safe).
-- (The character carry-weight cap, HeroData.itemListData @0x220, was removed: its
--  UI/enforcement doesn't hold cleanly with a freeze — pending investigation.)
_mtSelfStoreOn = false
_mtSelfStoreVal = _mtSelfStoreVal or 99000
-- _mtSelfStoreTimer holds the freeze timer

local function _clampWeight(v)
  v = tonumber(v) or 99000
  if v < 0 then v = 0 end
  if v >= 99999 then v = 99998 end  -- game rejects >= 99999
  return v
end

function MT.cheats.resources.selfStorageLimitEnable(val)
  _mtSelfStoreVal = _clampWeight(val)
  _mtSelfStoreOn = true
  if _mtSelfStoreTimer then
    return string.format("仓库上限锁定 = %.0f", _mtSelfStoreVal)
  end
  local t = createTimer(getMainForm())
  t.Interval = 200
  t.OnTimer = function()
    -- self-terminate when off (covers CT reload, which resets the flag); `t`
    -- captured so we destroy our own timer.
    if not _mtSelfStoreOn then
      pcall(function() t.Enabled = false; t.destroy() end)
      if _mtSelfStoreTimer == t then _mtSelfStoreTimer = nil end
      return
    end
    pcall(function()
      local hero = MT.game.getHero()
      if not hero then return end
      local s = readQword(hero + 0x228)
      if s and s ~= 0 then writeFloat(s + 0x20, _mtSelfStoreVal) end
    end)
  end
  t.Enabled = true
  _mtSelfStoreTimer = t
  return string.format("仓库上限锁定 = %.0f", _mtSelfStoreVal)
end

function MT.cheats.resources.selfStorageLimitDisable()
  _mtSelfStoreOn = false
  if _mtSelfStoreTimer then
    pcall(function() _mtSelfStoreTimer.Enabled = false; _mtSelfStoreTimer.destroy() end)
    _mtSelfStoreTimer = nil
  end
  return "已关闭 Disabled"
end

function MT.cheats.resources.setSectCurrency(val)
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local v = tonumber(val) or 9999
  writeFloat(hero + 0x1C0, v * 1.0)
  return string.format("门派贡献已设置为 %.0f", v)
end

function MT.cheats.resources.setFactionContrib(val)
  local wd = MT.game.getWorldData()
  if not wd then error("世界数据为空 WorldData null") end
  local forces = readQword(wd + 0x48)
  if not forces or forces == 0 then error("门派数据为空 Forces null") end
  local forceItems = readQword(forces + 0x10)
  local forceCount = readInteger(forces + 0x18)
  local newVal = tonumber(val) or 999
  local changed = 0
  for i = 0, forceCount - 1 do
    local fd = readQword(forceItems + 0x20 + i * 8)
    if fd and fd ~= 0 then
      writeFloat(fd + 0x170, newVal * 1.0)
      changed = changed + 1
    end
  end
  return string.format("已设置 %d 个门派贡献为 %.0f", changed, newVal)
end

function MT.cheats.resources.setMeteorite(val)
  local wd = MT.game.getWorldData()
  if not wd then error("世界数据为空 WorldData null") end
  local v = tonumber(val) or 999
  if v < 0 then error("数值无效 Invalid amount") end
  writeInteger(wd + 0x230, math.floor(v))  -- speEnhanceStone (was 0x228 pre-2026-06-04; WorldData +8 shift)
  return string.format("陨铁已设置为 %d", v)
end

function MT.cheats.resources.maxRarity()
  local hero = MT.game.getHero()
  if not hero then error("角色未找到 Hero not found") end
  local itemListData = readQword(hero + 0x220)
  if not itemListData or itemListData == 0 then error("物品数据未找到 ItemListData not found") end
  local allItem = readQword(itemListData + 0x28)
  if not allItem or allItem == 0 then error("物品列表为空 allItem list null") end
  local itemCount = readInteger(allItem + 0x18)
  local itemArr = readQword(allItem + 0x10)
  if not itemArr or itemArr == 0 then error("物品数组为空 Item array null") end
  local changed = 0
  for i = 0, itemCount - 1 do
    local item = readQword(itemArr + 0x20 + i * 8)
    if item and item ~= 0 then
      local cur = readInteger(item + 0x40)
      if cur ~= 5 then
        writeInteger(item + 0x40, 5)
        changed = changed + 1
      end
    end
  end
  return string.format("已将 %d/%d 物品设为最高品质", changed, itemCount)
end
