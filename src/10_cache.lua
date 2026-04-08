-- src/10_cache.lua — RVA/AOB cache and user config persistence (MT.cache, MT.config)
-- ============================================================
-- MT.cache -- RVA/AOB cache (persisted to %APPDATA%)
-- ============================================================
MT.cache = {}
MT.cache._dir = nil

function MT.cache.getDir()
  if MT.cache._dir then return MT.cache._dir end
  local appdata = os.getenv("APPDATA")
  if not appdata then return nil end
  local dir = appdata .. "\\longyin-cheats"
  -- NEVER use os.execute here — spawning cmd.exe freezes CE's GUI thread for seconds.
  -- Try writing a test file; if dir doesn't exist, cache/config simply won't persist
  -- until the user runs the game once (crash_recovery.ps1 creates the dir).
  local testFile = io.open(dir .. "\\.dircheck", "w")
  if testFile then
    testFile:close()
    os.remove(dir .. "\\.dircheck")
  else
    return nil  -- dir doesn't exist, skip caching
  end
  MT.cache._dir = dir
  return dir
end

function MT.cache.getPath(gaSize)
  local dir = MT.cache.getDir()
  if not dir then return nil end
  return dir .. "\\" .. tostring(gaSize) .. ".cache"
end

function MT.cache.load(gaSize)
  local path = MT.cache.getPath(gaSize)
  if not path then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local data = {}
  for line in f:lines() do
    local k, v = line:match("^([^=]+)=(.+)$")
    if k and v then data[k] = tonumber(v) or v end
  end
  f:close()
  return data
end

function MT.cache.save(gaSize, rvaTable, aobTable)
  local path = MT.cache.getPath(gaSize)
  if not path then return false end
  local f = io.open(path, "w")
  if not f then return false end
  for k, v in pairs(rvaTable) do
    if type(v) == "number" then f:write("rva." .. k .. "=" .. v .. "\n") end
  end
  for k, v in pairs(aobTable) do
    if type(v) == "number" then f:write("aob." .. k .. "=" .. v .. "\n") end
  end
  f:close()
  return true
end

-- ============================================================
-- MT.config -- User preferences (persisted to %APPDATA%)
-- ============================================================
MT.config = {}
MT.config._data = {}

function MT.config.getPath()
  local dir = MT.cache.getDir()
  if not dir then return nil end
  return dir .. "\\config.ini"
end

function MT.config.load()
  local path = MT.config.getPath()
  if not path then return end
  local f = io.open(path, "r")
  if not f then return end
  MT.config._data = {}
  for line in f:lines() do
    local k, v = line:match("^([^=]+)=(.+)$")
    if k and v then
      if v == "true" then v = true
      elseif v == "false" then v = false
      else v = tonumber(v) or v end
      MT.config._data[k] = v
    end
  end
  f:close()
end

function MT.config.save()
  local path = MT.config.getPath()
  if not path then return false end
  local f = io.open(path, "w")
  if not f then return false end
  for k, v in pairs(MT.config._data) do
    f:write(k .. "=" .. tostring(v) .. "\n")
  end
  f:close()
  return true
end

function MT.config.get(key, default)
  local v = MT.config._data[key]
  if v == nil then return default end
  return v
end

function MT.config.set(key, value)
  MT.config._data[key] = value
  MT.config.save()
end

-- Load config on startup
MT.config.load()
