-- src/00_init.lua — Global MT namespace and error settings
-- ============================================================
-- Long Yin Li Zhi Zhuan Xiu Gai Qi v8 -- Shared Core
-- Loaded once on CT open. All shared functions in MT namespace.
-- ============================================================

-- Cleanup must NEVER prevent MT from being defined
pcall(function()
  -- Kill stale timers from previous CT load
  if _maLoaderTimer then pcall(function() _maLoaderTimer.Enabled = false; _maLoaderTimer.destroy() end) end
  if _maTabTimer then pcall(function() _maTabTimer.Enabled = false; _maTabTimer.destroy() end) end
  if _skillLoaderTimer then pcall(function() _skillLoaderTimer.Enabled = false; _skillLoaderTimer.destroy() end) end
  if _evtLoaderTimer then pcall(function() _evtLoaderTimer.Enabled = false; _evtLoaderTimer.destroy() end) end
  if _staleCheckTimer then pcall(function() _staleCheckTimer.Enabled = false; _staleCheckTimer.destroy() end) end
  -- Kill orphan flash timers
  if type(_flashTimers) == "table" then
    for t in pairs(_flashTimers) do pcall(function() t.Enabled = false; t.destroy() end) end
  end
  -- Destroy stale form from previous session
  if _itemAdderForm then pcall(function() _itemAdderForm.destroy() end) end
end)
_maLoaderTimer = nil
_maTabTimer = nil
_skillLoaderTimer = nil
_evtLoaderTimer = nil
-- _autoConnectTimer preserved for autoload_save.lua
_staleCheckTimer = nil
_flashTimers = {}
_itemAdderForm = nil
_mtStatusLbl = nil
_threadGatedControls = {}

errorOnLookupFailure(false)
MT = {}
