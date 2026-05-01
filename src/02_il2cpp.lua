-- src/02_il2cpp.lua — IL2CPP class resolution, caching, ensure() (MT.il2cpp)
-- ============================================================
-- MT.il2cpp -- Class Resolution, Caching, ensure()
-- ============================================================
MT.il2cpp = {}

function MT.il2cpp.init()
  -- Check if cache is valid: GA base must match (game restart = new base)
  if _il2cppCache then
    local curGA = getAddress("GameAssembly.dll")
    if curGA and curGA == _il2cppCache._gaBase then return _il2cppCache end
    -- GA base changed = game restarted, clear stale cache
    _il2cppCache = nil
  end

  -- Validate game is alive, auto-fix stale symbols
  local gaAddr = MT.game.checkAlive()

  -- Validate ALL il2cpp exports upfront to prevent nearby allocation popup
  local exports = {
    domainGet = getAddress("GameAssembly.il2cpp_domain_get"),
    domainGetAsm = getAddress("GameAssembly.il2cpp_domain_get_assemblies"),
    asmGetImage = getAddress("GameAssembly.il2cpp_assembly_get_image"),
    classFromName = getAddress("GameAssembly.il2cpp_class_from_name"),
  }
  for name, addr in pairs(exports) do
    if not addr or addr < 0x100000 then
      error("Please attach to game and load a save first")
    end
  end

  local OFFSETS = {
    gc_inst = 0x0,
    gdc_inst = 0x20,
    gdc_tagBase = 0x198,
    gd_skill = 0x138,
    bc_inst = 0x50,
  }

  -- Step 1: Get Assembly-CSharp image
  -- Iterate all assemblies to find the one containing GameController
  -- (BepInEx/mods add assemblies after Assembly-CSharp, breaking last-index assumption)
  local domain = executeCodeEx(0, nil, exports.domainGet)
  if not domain or domain == 0 then error("il2cpp_domain_get failed") end
  local sizePtr = allocateMemory(8); writeQword(sizePtr, 0)
  local arr = executeCodeEx(0, nil, exports.domainGetAsm, domain, sizePtr)
  local count = readInteger(sizePtr); deAlloc(sizePtr)

  local cfn = exports.classFromName
  local ns = allocateMemory(16); writeString(ns, "")
  local cn = allocateMemory(64)

  local img = nil
  local gc = nil
  writeString(cn, "GameController")
  -- Search from last to first (Assembly-CSharp is usually near the end)
  for i = count - 1, 0, -1 do
    local asmPtr = readQword(arr + i * 8)
    if asmPtr and asmPtr ~= 0 then
      local testImg = executeCodeEx(0, nil, exports.asmGetImage, asmPtr)
      if testImg and testImg ~= 0 then
        local k = executeCodeEx(0, nil, cfn, testImg, ns, cn)
        if k and k ~= 0 then
          img = testImg
          gc = k
          break
        end
      end
    end
  end
  if not img or not gc then
    deAlloc(ns); deAlloc(cn)
    error("GameController not found in any assembly - is game loaded?")
  end

  -- Step 2: Find classes — allocate fresh buffer each time to avoid stale bytes
  local function findClass(name)
    local freshCn = allocateMemory(128)
    writeBytes(freshCn, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    writeString(freshCn, name)
    local k = executeCodeEx(0, nil, cfn, img, ns, freshCn)
    if not k or k == 0 then
      -- Fallback: scan all assemblies
      for i = 0, count - 1 do
        local asmPtr = readQword(arr + i * 8)
        if asmPtr and asmPtr ~= 0 then
          local testImg = executeCodeEx(0, nil, exports.asmGetImage, asmPtr)
          if testImg and testImg ~= 0 and testImg ~= img then
            k = executeCodeEx(0, nil, cfn, testImg, ns, freshCn)
            if k and k ~= 0 then break end
          end
        end
      end
    end
    deAlloc(freshCn)
    return (k and k ~= 0) and k or nil
  end
  if not gc then error("GameController not found - is game loaded?") end
  local gdc = findClass("GameDataController")
  local gd  = findClass("GlobalData")
  local hd  = findClass("HeroData")
  local bc  = findClass("BattleController")

  -- Log which classes were found/missing for diagnostics
  if MT.diag then
    local function yn(v) return v and "Y" or "N" end
    MT.diag(string.format("[il2cpp] classes: GC=%s GDC=%s GD=%s HD=%s BC=%s (img=%X, asmCount=%d)",
      yn(gc), yn(gdc), yn(gd), yn(hd), yn(bc), img or 0, count or 0))
  end

  deAlloc(ns); deAlloc(cn)

  local function klassData(k, instOff)
    if not k then return nil end
    return {klass=k, static=readQword(k+0xB8), instOff=instOff}
  end

  _il2cppCache = {
    _gaBase = gaAddr, img = img, _cfn = cfn,
    gc  = klassData(gc, OFFSETS.gc_inst),
    gdc = gdc and {klass=gdc, static=readQword(gdc+0xB8), instOff=OFFSETS.gdc_inst, tagBaseOff=OFFSETS.gdc_tagBase} or nil,
    gd  = gd and {klass=gd, static=readQword(gd+0xB8), skillOff=OFFSETS.gd_skill} or nil,
    hd  = hd and {klass=hd} or nil,
    bc  = bc and {klass=bc, static=readQword(bc+0xB8), instOff=OFFSETS.bc_inst} or nil,
  }

  -- Lazy resolver for classes not yet initialized
  _il2cppCache.findClass = function(name)
    local ns2 = allocateMemory(16); writeString(ns2, "")
    local cn2 = allocateMemory(128)
    writeBytes(cn2, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    writeString(cn2, name)
    local k = executeCodeEx(0, nil, _il2cppCache._cfn, _il2cppCache.img, ns2, cn2)
    deAlloc(ns2); deAlloc(cn2)
    return k ~= 0 and k or nil
  end

  -- Try to resolve missing classes on next access
  -- extraFields is an optional table of additional fields to attach (e.g., {skillOff=0x138})
  _il2cppCache.ensure = function(self, field, className, instOff, extraFields)
    local existing = self[field]
    if existing then
      -- Refresh static pointer if it was 0 (class wasn't fully initialized yet)
      if existing.klass and (not existing.static or existing.static == 0) then
        existing.static = readQword(existing.klass + 0xB8)
      end
      -- Apply any missing extra fields
      if extraFields then
        for fk, fv in pairs(extraFields) do
          if not existing[fk] then existing[fk] = fv end
        end
      end
      return existing
    end
    local k = self.findClass(className)
    if k then
      local entry = {klass=k, static=readQword(k+0xB8)}
      if instOff then entry.instOff = instOff end
      if extraFields then
        for fk, fv in pairs(extraFields) do entry[fk] = fv end
      end
      self[field] = entry
    end
    return self[field]
  end

  local found = 0
  for _, k in ipairs({gc, gdc, gd, hd, bc}) do if k then found = found + 1 end end

  -- Detect and display game version
  local verStr = "?"
  local fixStr = "?"
  if gd then
    local gdStatic = readQword(gd + 0xB8)
    if gdStatic and gdStatic ~= 0 then
      local vnPtr = readQword(gdStatic + 0x70)
      if vnPtr and vnPtr ~= 0 then
        local nl = readInteger(vnPtr + 0x10)
        if nl and nl > 0 then verStr = readString(vnPtr + 0x14, nl*2, true) or "?" end
      end
      local fnPtr = readQword(gdStatic + 0x78)
      if fnPtr and fnPtr ~= 0 then
        local nl = readInteger(fnPtr + 0x10)
        if nl and nl > 0 then fixStr = readString(fnPtr + 0x14, nl*2, true) or "?" end
      end
    end
  end
  local gaSize = getModuleSize("GameAssembly.dll") or 0
  local verMsg = string.format("[Long Yin Li Zhi Zhuan] Version %s %s (GA: %d bytes, %d/5 classes)", verStr, fixStr, gaSize, found)
  if MT.diag then MT.diag(verMsg) end

  return _il2cppCache
end

function MT.il2cpp.reset()
  _il2cppCache = nil
  if MT.diag then MT.diag("[il2cpp] Cache cleared") end
end
