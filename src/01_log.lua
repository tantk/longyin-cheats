-- src/01_log.lua — Debug logging (MT.log)
-- ============================================================
-- MT.log -- Debug Logging
-- ============================================================
MT.log = {}

do
  local LOG_PATH = os.getenv("TEMP") .. "\\ce_itemadder_debug.log"
  local _logFile = nil

  function MT.log.open()
    _logFile = io.open(LOG_PATH, "w")
    if _logFile then _logFile:write("=== MultiTool v8 Debug Log ===\n") end
  end

  function MT.log.write(msg)
    if _logFile then _logFile:write(os.date("%H:%M:%S ") .. tostring(msg) .. "\n"); _logFile:flush() end
    -- Forward to diagnostic system so Copy Diag captures connect-phase logs
    if MT.diag then pcall(MT.diag, tostring(msg)) end
  end

  function MT.log.close()
    if _logFile then _logFile:close(); _logFile = nil end
  end

  function MT.log.toHex(addr)
    if not addr then return "nil" end
    return string.format("%X", addr)
  end
end

-- Shorthand aliases used internally
local log = MT.log.write
local toHex = MT.log.toHex
