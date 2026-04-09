-- src/00_init.lua — Global MT namespace and error settings
-- ============================================================
-- Long Yin Li Zhi Zhuan Xiu Gai Qi v8 -- Shared Core
-- Loaded once on CT open. All shared functions in MT namespace.
-- ============================================================

local _mtDiagPath = nil
_mtDiagMem = type(_mtDiagMem) == "table" and _mtDiagMem or {}

local function _mtPushMem(msg)
  _mtDiagMem[#_mtDiagMem + 1] = os.date("%Y-%m-%d %H:%M:%S ") .. tostring(msg)
  if #_mtDiagMem > 400 then table.remove(_mtDiagMem, 1) end
end

local function _mtDiagCandidates()
  local out = {}
  local function add(base)
    if type(base) == "string" and base ~= "" then out[#out + 1] = base end
  end
  add(os.getenv("TEMP"))
  add(os.getenv("TMP"))
  add(os.getenv("APPDATA"))
  if type(getCheatEngineDir) == "function" then
    local ok, ceDir = pcall(getCheatEngineDir)
    if ok then add(ceDir) end
  end
  add(".")
  return out
end

local function _mtOpenDiagFile()
  local name = "ce_mt_load_diag.log"
  local cands = _mtDiagCandidates()
  for _, base in ipairs(cands) do
    local sep = (base:sub(-1) == "\\" or base:sub(-1) == "/") and "" or "\\"
    local path = base .. sep .. name
    local f = io.open(path, "a")
    if f then
      _mtDiagPath = path
      if type(MT) == "table" then MT.diagPath = _mtDiagPath end
      return f
    end
  end
  return nil
end

local function _mtDiagWrite(msg)
  _mtPushMem(msg)
  pcall(function()
    local f = _mtOpenDiagFile()
    if not f then return end
    f:write(_mtDiagMem[#_mtDiagMem] .. "\n")
    f:close()
  end)
end

local function _mtObjType(v)
  local t = type(v)
  -- Do NOT access .ClassName on userdata — can trigger C-level access violation
  -- on destroyed Delphi objects that pcall cannot catch
  return t
end

local function _mtTry(tag, fn)
  local ok, err = pcall(fn)
  if not ok then
    _mtDiagWrite("[cleanup] " .. tostring(tag) .. " failed: " .. tostring(err))
  end
  return ok, err
end

-- Rotate diag log: keep N-1 old sessions + 1 new = N total
local DIAG_KEEP_SESSIONS = 3
pcall(function()
  local f = _mtOpenDiagFile()
  if not f then return end
  f:close()
  local rf = io.open(_mtDiagPath, "r")
  if not rf then return end
  local content = rf:read("*a")
  rf:close()
  if #content == 0 then return end
  local sessions = {}
  local cur = ""
  for line in content:gmatch("[^\n]+") do
    if line:find("===== CT LOAD START =====") then
      if #cur > 0 then sessions[#sessions + 1] = cur end
      cur = line .. "\n"
    else
      cur = cur .. line .. "\n"
    end
  end
  if #cur > 0 then sessions[#sessions + 1] = cur end
  local keep = DIAG_KEEP_SESSIONS - 1  -- new session will be added after
  if #sessions > keep then
    local wf = io.open(_mtDiagPath, "w")
    if wf then
      for i = #sessions - keep + 1, #sessions do wf:write(sessions[i]) end
      wf:close()
    end
  end
end)
_mtDiagWrite("===== CT LOAD START =====")
_mtDiagWrite(string.format(
  "[pre] _maLoaderTimer=%s _maTabTimer=%s _skillLoaderTimer=%s _evtLoaderTimer=%s _staleCheckTimer=%s _flashTimers=%s _itemAdderForm=%s",
  _mtObjType(_maLoaderTimer), _mtObjType(_maTabTimer), _mtObjType(_skillLoaderTimer),
  _mtObjType(_evtLoaderTimer), _mtObjType(_staleCheckTimer), _mtObjType(_flashTimers), _mtObjType(_itemAdderForm)
))

-- Cleanup: disable stale timers, nil references. Do NOT call .destroy() —
-- it accesses Delphi objects that may be invalid, causing access violations.
_mtTry("cleanup block", function()
  local function disableTimer(name, t)
    if t then _mtTry(name, function() t.Enabled = false end) end
  end
  disableTimer("_maLoaderTimer", _maLoaderTimer)
  disableTimer("_maTabTimer", _maTabTimer)
  disableTimer("_skillLoaderTimer", _skillLoaderTimer)
  disableTimer("_evtLoaderTimer", _evtLoaderTimer)
  disableTimer("_staleCheckTimer", _staleCheckTimer)
  if type(_flashTimers) == "table" then
    local n = 0
    for t in pairs(_flashTimers) do
      n = n + 1
      _mtTry("flashTimer" .. n, function() t.Enabled = false end)
    end
    _mtDiagWrite("[cleanup] disabled " .. n .. " flash timers")
  else
    _mtDiagWrite("[cleanup] _flashTimers is " .. _mtObjType(_flashTimers))
  end
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
MT.getDiagPath = function() return _mtDiagPath end
MT.diag("[init] MT namespace created")
