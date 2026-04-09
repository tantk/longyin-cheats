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
  add("C:\\temp")  -- ASCII-safe fallback for Chinese/non-ASCII usernames
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
  "[pre] _maTabTimer=%s _evtLoaderTimer=%s _staleCheckTimer=%s _flashTimers=%s _itemAdderForm=%s",
  _mtObjType(_maTabTimer), _mtObjType(_evtLoaderTimer), _mtObjType(_staleCheckTimer), _mtObjType(_flashTimers), _mtObjType(_itemAdderForm)
))

-- Cleanup strategy:
-- TIMERS: do NOT touch — their callbacks guard against nil _itemAdderForm
--   and self-disable on next fire. Accessing .Enabled causes C-level AV.
-- FORM: safe to destroy (we created it, not a stale system object).
_mtDiagWrite("[cleanup] destroying stale form, nil-ing timer refs")
if _itemAdderForm then
  pcall(function() _itemAdderForm.destroy() end)
end
_maTabTimer = nil
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
