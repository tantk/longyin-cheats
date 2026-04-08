-- src/13_cheats_battle.lua — Battle cheats (MT.cheats.battle)
-- ── Battle ───────────────────────────────────────────────────

MT.cheats.battle._speedState = nil

function MT.cheats.battle.battleSpeedEnable(multi)
  local speedVal = multi
  if MT.cheats.battle._speedState then MT.cheats.battle._speedState.timer.destroy() end
  local speedTimer = createTimer(nil)
  speedTimer.Interval = 50
  speedTimer.OnTimer = function()
    local pid = getOpenedProcessID()
    if not pid or pid == 0 then speedTimer.Enabled = false; return end
    local ok, wd = pcall(MT.game.getWorldData)
    if ok and wd then pcall(writeFloat, wd + 0x1D0, speedVal) end
  end
  speedTimer.Enabled = true
  MT.cheats.battle._speedState = {timer = speedTimer, val = speedVal}
end

function MT.cheats.battle.battleSpeedDisable()
  local s = MT.cheats.battle._speedState
  if s and s.timer then s.timer.destroy() end
  MT.cheats.battle._speedState = nil
  local ok, wd = pcall(MT.game.getWorldData)
  if ok and wd then writeFloat(wd + 0x1D0, 1.0) end
end

function MT.cheats.battle.enemyOneHP()
  local c = MT.il2cpp.init()
  if not c:ensure("bc", "BattleController", 0x50) then error("未在战斗中 BattleController not loaded - enter battle first") end
  local bcInstance = readQword(c.bc.static + c.bc.instOff)
  if not bcInstance or bcInstance == 0 then error("未在战斗中 Not in battle") end
  local playerUnit = readQword(bcInstance + 0x1A8)
  if not playerUnit or playerUnit == 0 then error("玩家单位未找到 Player unit not found") end
  local pTeam = readQword(playerUnit + 0x58)
  if not pTeam or pTeam == 0 then error("玩家队伍为空 Player team null") end
  local playerTeamID = readInteger(pTeam + 0x10)
  local teams = readQword(bcInstance + 0x70)
  if not teams or teams == 0 then error("队伍列表为空 Teams list null") end
  local teamItems = readQword(teams + 0x10)
  if not teamItems or teamItems == 0 then error("队伍数据为空 Team items null") end
  local teamCount = readInteger(teams + 0x18)
  local killed = 0
  for t = 0, teamCount - 1 do
    local team = readQword(teamItems + 0x20 + t * 8)
    if team and team ~= 0 then
      local teamID = readInteger(team + 0x10)
      if teamID ~= playerTeamID then
        local units = readQword(team + 0x18)
        if units and units ~= 0 then
          local unitCount = readInteger(units + 0x18)
          local unitItems = readQword(units + 0x10)
          if unitItems and unitItems ~= 0 then
            for u = 0, unitCount - 1 do
              local unit = readQword(unitItems + 0x20 + u * 8)
              if unit and unit ~= 0 then
                local heroData = readQword(unit + 0x40)
                if heroData and heroData ~= 0 then
                  local hp = readFloat(heroData + 0x178)
                  if hp > 0 then
                    writeFloat(heroData + 0x178, 1.0)
                    killed = killed + 1
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return string.format("已将 %d 个敌人设为 1 HP", killed)
end
