-- src/00_init.lua — Global MT namespace and error settings
-- ============================================================
-- Long Yin Li Zhi Zhuan Xiu Gai Qi v8 -- Shared Core
-- Loaded once on CT open. All shared functions in MT namespace.
-- ============================================================

local _mtDiagPath = (os.getenv("TEMP") or ".") .. "\\ce_mt_load_diag.log"

local function _mtDiagWrite(msg)
  pcall(function()
    local f = io.open(_mtDiagPath, "a")
    if not f then return end
    f:write(os.date("%Y-%m-%d %H:%M:%S ") .. tostring(msg) .. "\n")
    f:close()
  end)
end

local function _mtObjType(v)
  local t = type(v)
  if t == "userdata" then
    local ok, className = pcall(function() return v.ClassName end)
    if ok and className then return "userdata:" .. tostring(className) end
  end
  return t
end

local function _mtTry(tag, fn)
  local ok, err = pcall(fn)
  if not ok then
    _mtDiagWrite("[cleanup] " .. tostring(tag) .. " failed: " .. tostring(err))
  end
  return ok, err
end

_mtDiagWrite("===== CT LOAD START =====")
_mtDiagWrite(string.format(
  "[pre] _maLoaderTimer=%s _maTabTimer=%s _skillLoaderTimer=%s _evtLoaderTimer=%s _staleCheckTimer=%s _flashTimers=%s _itemAdderForm=%s",
  _mtObjType(_maLoaderTimer), _mtObjType(_maTabTimer), _mtObjType(_skillLoaderTimer),
  _mtObjType(_evtLoaderTimer), _mtObjType(_staleCheckTimer), _mtObjType(_flashTimers), _mtObjType(_itemAdderForm)
))

-- Cleanup must NEVER prevent MT from being defined
_mtTry("cleanup block", function()
  -- Kill stale timers from previous CT load
  if _maLoaderTimer then _mtTry("_maLoaderTimer.destroy", function() _maLoaderTimer.Enabled = false; _maLoaderTimer.destroy() end) end
  if _maTabTimer then _mtTry("_maTabTimer.destroy", function() _maTabTimer.Enabled = false; _maTabTimer.destroy() end) end
  if _skillLoaderTimer then _mtTry("_skillLoaderTimer.destroy", function() _skillLoaderTimer.Enabled = false; _skillLoaderTimer.destroy() end) end
  if _evtLoaderTimer then _mtTry("_evtLoaderTimer.destroy", function() _evtLoaderTimer.Enabled = false; _evtLoaderTimer.destroy() end) end
  if _staleCheckTimer then _mtTry("_staleCheckTimer.destroy", function() _staleCheckTimer.Enabled = false; _staleCheckTimer.destroy() end) end
  -- Kill orphan flash timers
  if type(_flashTimers) == "table" then
    local n = 0
    for t in pairs(_flashTimers) do
      n = n + 1
      _mtTry("_flashTimers[" .. tostring(n) .. "].destroy", function() t.Enabled = false; t.destroy() end)
    end
    _mtDiagWrite("[cleanup] processed flash timers: " .. tostring(n))
  else
    _mtDiagWrite("[cleanup] _flashTimers is " .. _mtObjType(_flashTimers))
  end
  -- Destroy stale form from previous session
  if _itemAdderForm then _mtTry("_itemAdderForm.destroy", function() _itemAdderForm.destroy() end) end
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
MT.diag = _mtDiagWrite
MT.diagPath = _mtDiagPath
MT.diag("[init] MT namespace created")
