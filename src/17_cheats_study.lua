-- src/17_cheats_study.lua — Skill-study minigame score lock (MT.cheats.study)
-- ============================================================
-- The skill-learning minigame (读书 / ReadBook grid) keeps the player's
-- current score at ReadBookController + 0x78 (float). ReadBookController + 0x60
-- (byte) is the "minigame open" flag: PlayerStudySkill-style entry sets it to 1,
-- SureFinishRead sets it back to 0. When enabled, a timer forces the score to a
-- user-chosen value WHILE the minigame is open, so the player can finish (阅毕)
-- with a desired score without playing the minigame. baseline score otherwise
-- untouched. Verified live: writing +0x78 snaps the on-screen score, and a
-- fresh study session re-applies it.
-- ============================================================
MT.cheats = MT.cheats or {}
MT.cheats.study = {}

-- (Re)set on every CT load. A stale score-lock timer from a previous session
-- (whose Lua object survives a CT reload) will see this flag = false on its
-- next fire and self-destruct via its captured upvalue — we never touch the
-- old timer object here (accessing a stale timer's props can C-level AV).
_mtStudyScoreOn = false
_mtStudyScoreVal = _mtStudyScoreVal or 9999
-- _mtStudyScoreTimer holds the live timer (tracked for explicit [DISABLE] kill)

local RBC_SCORE_OFF = 0x78   -- float: current minigame score
local RBC_OPEN_OFF  = 0x60   -- byte:  1 = minigame open, 0 = closed

local function _rbcInstance()
  local c = MT.il2cpp.init()
  if not c then return nil end
  local cls = c.findClass("ReadBookController")
  if not cls then return nil end
  local sf = readQword(cls + 0xB8)
  if not sf or sf == 0 then return nil end
  local inst = readQword(sf)
  return (inst ~= 0) and inst or nil
end

-- enableFn for makeToggleInput — receives the entered value.
function MT.cheats.study.scoreEnable(val)
  _mtStudyScoreVal = tonumber(val) or 9999
  _mtStudyScoreOn = true
  if _mtStudyScoreTimer then
    return "学习评分锁定 = " .. _mtStudyScoreVal  -- already running; value updated
  end
  local t = createTimer(getMainForm())
  t.Interval = 250
  t.OnTimer = function()
    -- Self-terminate when disabled (covers CT reload, which resets the flag).
    -- `t` is captured here, so we can safely destroy our own timer.
    if not _mtStudyScoreOn then
      pcall(function() t.Enabled = false; t.destroy() end)
      if _mtStudyScoreTimer == t then _mtStudyScoreTimer = nil end
      return
    end
    pcall(function()
      local inst = _rbcInstance()
      if not inst then return end                       -- not attached / no controller
      if (readInteger(inst + RBC_OPEN_OFF) & 0xFF) == 1 then  -- minigame open
        writeFloat(inst + RBC_SCORE_OFF, _mtStudyScoreVal)
      end
    end)
  end
  t.Enabled = true
  _mtStudyScoreTimer = t
  return "学习评分锁定 = " .. _mtStudyScoreVal
end

-- disableFn for makeToggleInput.
function MT.cheats.study.scoreDisable()
  _mtStudyScoreOn = false
  if _mtStudyScoreTimer then
    pcall(function() _mtStudyScoreTimer.Enabled = false; _mtStudyScoreTimer.destroy() end)
    _mtStudyScoreTimer = nil
  end
  return "已关闭 Disabled"
end
