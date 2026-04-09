-- src/99_compat.lua — Backward-compatibility aliases and process watcher
-- ============================================================
-- Backward-compatibility aliases (old entries call these directly)
-- ============================================================
_il2cpp_init    = MT.il2cpp.init
_il2cpp_reset   = MT.il2cpp.reset
_getHero        = MT.game.getHero
_getWorldData   = MT.game.getWorldData
_findMethodAddr = MT.method.findAddr
_isGameRunning  = MT.game.isRunning
_checkGameAlive = MT.game.checkAlive

-- Also expose global UI functions for backward compatibility during transition
setStatus             = MT.ui.setStatus
isConnected           = MT.ui.isConnected
flashSuccess          = MT.ui.flashSuccess
flashFail             = MT.ui.flashFail
makeOneOff            = MT.ui.makeOneOff
makeToggle            = MT.ui.makeToggle
makeInput             = MT.ui.makeInput
makeToggleInput       = MT.ui.makeToggleInput
numericOnly           = MT.ui.numericOnly
enableThreadControls  = MT.ui.enableThreadControls

-- ============================================================
-- Process Watcher (auto-clear caches on process change)
-- ============================================================
if not _processWatcherInstalled then
  local lastPID = getOpenedProcessID()
  registerFormAddNotification(function(frm)
    -- This fires on various CE events. Check if PID changed.
    local curPID = getOpenedProcessID()
    if curPID ~= lastPID then
      lastPID = curPID
      _il2cppCache = nil
      MT.hook.hookInstalled = false
      MT.hook.S = {}
      print("[CT] Process changed -- caches cleared")
    end
  end)
  -- Also hook the OpenProcess event directly
  if getMainForm().ProcessLabel then
    local timer = createTimer()
    timer.Interval = 2000
    timer.OnTimer = function()
      local pid = getOpenedProcessID()
      if pid ~= lastPID then
        lastPID = pid
        _il2cppCache = nil
        MT.hook.hookInstalled = false
        MT.hook.S = {}
        print("[CT] Process changed (timer) -- cache cleared")
      end
    end
    timer.Enabled = true
    _staleCheckTimer = timer
  end
  _processWatcherInstalled = true
end

-- print suppressed — opens Lua Engine window which confuses users
if MT.diag then MT.diag("[MT] Shared core loaded (v8)") end
