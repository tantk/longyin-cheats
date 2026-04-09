-- src/04_hook.lua — Hook state, allocWorkArea, shellExec, resolveAOBs, installMainThreadHook, discover, cleanup, command dispatch, helpers (MT.hook)
-- ============================================================
-- MT.hook -- Hook State, allocWorkArea, shellExec, resolveAOBs,
--            installMainThreadHook, discover, cleanup, commands
-- ============================================================
MT.hook = {}

-- Hook state (replaces loose locals in the old code)
MT.hook.S = {}            -- discovery state (hero, ild, cmdBuf, base, ready, etc.)
MT.hook.hookInstalled = false
MT.hook.WK = { code = nil, data = nil, str = nil }
MT.hook.RVA = {}
MT.hook.AOB_SIGS = {
  setBook   = {sig="48 8B 43 68 48 85 C0 0F 84 ?? ?? ?? ?? 89 78 10", off=0x3F},
  setMat    = {sig="89 6B 18 89 73 3C 89 7B 40", off=0x48},
  ctor      = {sig="C7 47 44 00 00 80 3F 48 8B CF E8 ?? ?? ?? ?? 89 5F 14 83 FB 06", off=0x6A},
  clone     = {sig="48 89 5C 24 08 57 48 83 EC 20 48 8B D9 E8 ?? ?? ?? ?? 48 8B F8 48 85 C0 74", off=0},
}
MT.hook._aobsResolved = false

-- Equipment / treasure DB definitions (used by discover and item functions)
MT.hook.equipDBs = {
  {name="Weapon Wu Qi",     off=0xF0,  genMethod="GenerateWeapon", genParams=4},
  {name="Armor Kui Jia",      off=0xF8,  genMethod="GenerateArmor", genParams=4},
  {name="Helmet Tou Kui",     off=0x100, genMethod="GenerateHelmet", genParams=4},
  {name="Shoes Xie",        off=0x108, genMethod="GenerateShoes", genParams=4},
  {name="Accessory Shi Pin",  off=nil,   genMethod="GenerateDecoration", genParams=4,
   staticItems={"Xiang Nang Sachet","Yu Shan Fan","Ban Zhi Ring","Yu Pei Pendant","Yao Dai Belt","Mian Ju Mask"}},
  {name="HorseArmor Ma Jia", off=nil,  genMethod="GenerateHorseArmorData", genParams=2,
   staticItems={"An Ju Saddle"}},
}
MT.hook.TREASURE_GEN_RVA = nil

-- ============================================================
-- MT.hook.allocWorkArea
-- ============================================================
function MT.hook.allocWorkArea()
  local WK = MT.hook.WK
  if WK.code then return true end
  -- Clean up stale symbols from previous session.
  -- IMPORTANT: unhook first if a prior session left Update pointing to old hookCode.
  if _ia_harmonyPtrSlot and _ia_origChainTarget then
    pcall(function() writeQword(_ia_harmonyPtrSlot, _ia_origChainTarget) end)
    _ia_harmonyPtrSlot = nil; _ia_origChainTarget = nil
  end
  if _ia_directPatch and _ia_directPatchAddr and _ia_directPatchOrigBytes then
    local n = _ia_patchLen or #_ia_directPatchOrigBytes
    pcall(function()
      for i = 1, n do writeBytes(_ia_directPatchAddr + i - 1, _ia_directPatchOrigBytes[i]) end
    end)
    _ia_directPatch = nil; _ia_patchLen = nil
    if _ia_relayCode then pcall(deAlloc, _ia_relayCode); _ia_relayCode = nil end
  end
  sleep(100) -- drain any in-flight Update before freeing hook memory
  -- Only unregister symbols, NEVER dealloc -- stale addresses from a previous
  -- game session can point to valid memory in the new process, and freeing
  -- them crashes the game. The old memory is already gone with the old process.
  for _, n in ipairs({"cmdBuf","hookCode","origUpdatePtr","wkCode","wkData","wkStr"}) do
    pcall(function() autoAssemble("unregistersymbol("..n..")") end)
  end
  local ok = autoAssemble([[
alloc(wkCode, 512)
alloc(wkData, 512)
alloc(wkStr, 256)
registersymbol(wkCode)
registersymbol(wkData)
registersymbol(wkStr)
wkStr:
db 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
db 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
wkData:
dq 0 0 0 0 0 0 0 0
wkCode:
ret
  ]])
  if not ok then return false end
  WK.code = getAddress("wkCode")
  WK.data = getAddress("wkData")
  WK.str = getAddress("wkStr")
  return true
end

-- ============================================================
-- MT.hook.resolveAOBs
-- ============================================================
function MT.hook.resolveAOBs()
  if MT.hook._aobsResolved then return end
  local RVA = MT.hook.RVA
  local AOB_SIGS = MT.hook.AOB_SIGS
  local base = getAddress("GameAssembly.dll")
  local modSize = getModuleSize("GameAssembly.dll") or 0x10000000
  for name, info in pairs(AOB_SIGS) do
    if not RVA[name] then
      local r = AOBScan(info.sig, "+X")
      if r and stringlist_getCount(r) >= 1 then
        local found = tonumber(stringlist_getString(r, 0), 16)
        if found >= base and found < base + modSize then
          RVA[name] = found - info.off - base
          log("AOB " .. name .. " -> RVA " .. string.format("%X", RVA[name]))
        end
        object_destroy(r)
      end
    end
  end
  MT.hook._aobsResolved = true
end

-- ============================================================
-- MT.hook.installMainThreadHook
-- ============================================================
function MT.hook.installMainThreadHook()
  if MT.hook.hookInstalled then return true end
  log("installMainThreadHook start (pointer-swap)")
  local S = MT.hook.S
  local base = getAddress("GameAssembly.dll")
  if not base or base < 0x100000 then return false, "GameAssembly.dll not loaded (base=" .. tostring(base) .. ")" end
  local modSize = getModuleSize("GameAssembly.dll") or 0x10000000

  -- Find GameController class via il2cpp API
  local getMethodFromName = getAddress("GameAssembly.il2cpp_class_get_method_from_name")
  local domainGet = getAddress("GameAssembly.il2cpp_domain_get")
  local domainGetAsm = getAddress("GameAssembly.il2cpp_domain_get_assemblies")
  local imageFromAsm = getAddress("GameAssembly.il2cpp_assembly_get_image")
  local classFromName = getAddress("GameAssembly.il2cpp_class_from_name")
  if not getMethodFromName or getMethodFromName == 0 then
    return false, "il2cpp_class_get_method_from_name not found"
  end
  if not classFromName or classFromName == 0 then
    return false, "il2cpp exports missing"
  end

  -- Use cached game image from discover()
  local gameImage = S.gameImage
  if not gameImage or gameImage == 0 then return false, "Game image not cached (run discover first)" end

  -- Use executeCodeEx (safe) instead of shellExec/createRemoteThread (crashes with BepInEx)
  local c_hook = MT.il2cpp.init()

  local function findClassFast(name)
    local ns = allocateMemory(16); writeString(ns, "")
    local cn = allocateMemory(64); writeString(cn, name)
    local k = executeCodeEx(0, nil, classFromName, gameImage, ns, cn)
    deAlloc(ns); deAlloc(cn)
    return k ~= 0 and k or nil
  end

  -- Use GameDataController.Update (not GameController.Update) — GC.Update has
  -- RIP-relative instructions in its prologue that break when relocated to relay.
  -- GDC.Update has simpler entry bytes (40 56 48 83 EC 30).
  local gdcClass = c_hook.gdc and c_hook.gdc.klass
  if not gdcClass then
    c_hook:ensure("gdc", "GameDataController", 0x20)
    gdcClass = c_hook.gdc and c_hook.gdc.klass
  end
  if not gdcClass then return false, "GameDataController class not found" end
  log("gcClass=" .. toHex(gdcClass))

  -- Get MethodInfo* for Update(0 params) via executeCodeEx
  local updateNameBuf = allocateMemory(32)
  writeString(updateNameBuf, "Update")
  local methodInfo = executeCodeEx(0, nil, getMethodFromName, gdcClass, updateNameBuf, 0)
  deAlloc(updateNameBuf)
  if not methodInfo or methodInfo == 0 then return false, "Update MethodInfo not found" end
  log("methodInfo=" .. toHex(methodInfo))

  -- Read the methodPointer (offset 0 of MethodInfo) = code address
  local updateCodeAddr = readQword(methodInfo)
  if not updateCodeAddr or updateCodeAddr == 0 then return false, "Update methodPointer is null" end
  log("updateCodeAddr=" .. toHex(updateCodeAddr))

  -- Read first 6 bytes to check for Harmony/BepInEx trampoline (FF 25 xx xx xx xx)
  local b1 = readBytes(updateCodeAddr, 1)
  local b2 = readBytes(updateCodeAddr + 1, 1)
  log(string.format("First 2 bytes at Update: %02X %02X", b1 or 0, b2 or 0))

  local harmonyPtrSlot = nil
  local origChainTarget = nil

  if b1 == 0xFF and b2 == 0x25 then
    -- FF 25 = jmp [rip + disp32]. Decode the disp32.
    local disp = readInteger(updateCodeAddr + 2)
    -- disp32 is signed; handle negative values
    if disp >= 0x80000000 then disp = disp - 0x100000000 end
    -- RIP-relative: target = addr_after_instruction + disp = (updateCodeAddr + 6) + disp
    harmonyPtrSlot = updateCodeAddr + 6 + disp
    origChainTarget = readQword(harmonyPtrSlot)
    log("Harmony trampoline detected!")
    log("  ptrSlot=" .. toHex(harmonyPtrSlot) .. " -> chainTarget=" .. toHex(origChainTarget))
  else
    -- No Harmony/BepInEx. Use short 5-byte E9 JMP to hookCode (allocated near GameAssembly).
    -- Only save bytes up to the first instruction boundary >= 5 -- avoids RIP-relative relocation.
    -- Check if Update is already E9-patched (stale from autoload or previous crash)
    if b1 == 0xE9 then
      log("WARNING: Stale E9 patch -- restoring original bytes: 40 56 48 83 EC 30")
      writeBytes(updateCodeAddr, {0x40, 0x56, 0x48, 0x83, 0xEC, 0x30})
      sleep(100)
      b1 = readBytes(updateCodeAddr, 1)
      b2 = readBytes(updateCodeAddr + 1, 1)
    end
    log("No Harmony trampoline -- will patch code entry directly")
    harmonyPtrSlot = nil
    _ia_directPatch = true
    _ia_directPatchAddr = updateCodeAddr

    -- Walk instructions to find boundary >= 5 bytes (E9 rel32 jump)
    -- GDC.Update has simple entry bytes (40 56 48 83 EC 30) without RIP-relative.
    local boundary = 0
    while boundary < 5 do
      local ok, s = pcall(disassemble, updateCodeAddr + boundary)
      if not ok or type(s) ~= "string" then
        return false, "Cannot disassemble at Update+" .. boundary
      end
      local hexBytes = s:match("%-%s(%x%x[%x ]-)%s%-")
      if not hexBytes then
        return false, "Cannot parse disassembly at Update+" .. boundary .. ": " .. s:sub(1, 80)
      end
      local instrSize = 0
      for _ in hexBytes:gmatch("%x%x") do instrSize = instrSize + 1 end
      if instrSize == 0 then
        return false, "Zero-length instruction at Update+" .. boundary
      end
      boundary = boundary + instrSize
    end
    _ia_patchLen = boundary
    log("Instruction boundary at " .. boundary .. " bytes")

    _ia_directPatchOrigBytes = {}
    for i = 0, boundary - 1 do
      _ia_directPatchOrigBytes[i + 1] = readBytes(updateCodeAddr + i, 1) or 0
    end
    local origBytesHex = ""
    for i = 1, boundary do origBytesHex = origBytesHex .. string.format("%02X ", _ia_directPatchOrigBytes[i]) end
    log("Original " .. boundary .. " bytes at Update: " .. origBytesHex)

    -- Build relay trampoline: [saved bytes] + [FF 25 00 00 00 00] + [updateCodeAddr+boundary]
    local relaySize = boundary + 6 + 8
    _ia_relayCode = allocateMemory(relaySize)
    for i = 1, boundary do writeBytes(_ia_relayCode + i - 1, _ia_directPatchOrigBytes[i]) end
    writeBytes(_ia_relayCode + boundary, {0xFF, 0x25, 0x00, 0x00, 0x00, 0x00})
    writeQword(_ia_relayCode + boundary + 6, updateCodeAddr + boundary)
    origChainTarget = _ia_relayCode
    log("Relay trampoline at " .. toHex(_ia_relayCode) .. " -> continues at " .. toHex(updateCodeAddr + boundary))
  end

  -- Use executeCodeEx-based class/method lookup (safe, no shellExec)
  local function findClassByName(name)
    return findClassFast(name)
  end

  local function resolveMethodPtr(klass, methodName, paramCount)
    local nmBuf = allocateMemory(64)
    writeString(nmBuf, methodName)
    local mi = executeCodeEx(0, nil, getMethodFromName, klass, nmBuf, paramCount)
    deAlloc(nmBuf)
    if not mi or mi == 0 then return nil end
    local ptr = readQword(mi)
    if not ptr or ptr == 0 then return nil end
    return ptr
  end

  -- Resolve item-related classes (NON-FATAL -- only needed for cmd=1 GetItem)
  -- These are deferred to ensureItemAdder() if they fail here
  local heroClass = findClassByName("HeroData")
  if heroClass then log("heroClass=" .. toHex(heroClass)) else log("HeroData: deferred") end

  local getItemPtr = heroClass and resolveMethodPtr(heroClass, "GetItem", 5) or nil
  if getItemPtr then log("getItemPtr=" .. toHex(getItemPtr)) else log("GetItem: deferred") end

  local itemDataClass = findClassByName("ItemData")
  if itemDataClass then log("itemDataClass=" .. toHex(itemDataClass)) else log("ItemData: deferred") end

  local setBookPtr = itemDataClass and resolveMethodPtr(itemDataClass, "SetBookData", 2) or nil
  if setBookPtr then
    log("setBookPtr=" .. toHex(setBookPtr) .. " RVA=" .. string.format("%X", setBookPtr - base))
    S.setBookAddr = setBookPtr
  else
    log("SetBookData: deferred")
  end

  -- Check if GetItem is Harmony-hooked (FF 25 trampoline). If so, unwrap to find the
  -- original IL2CPP code address so we bypass Harmony's managed hooks.
  if not getItemPtr then log("GetItem nil -- skipping Harmony check") end
  local gi_b1 = getItemPtr and readBytes(getItemPtr, 1) or nil
  local gi_b2 = getItemPtr and readBytes(getItemPtr + 1, 1) or nil
  log(string.format("GetItem first 2 bytes: %02X %02X", gi_b1 or 0, gi_b2 or 0))
  if gi_b1 == 0xFF and gi_b2 == 0x25 then
    local gi_disp = readInteger(getItemPtr + 2)
    if gi_disp >= 0x80000000 then gi_disp = gi_disp - 0x100000000 end
    local gi_ptrSlot = getItemPtr + 6 + gi_disp
    local gi_harmonyTarget = readQword(gi_ptrSlot)
    log("GetItem Harmony trampoline: ptrSlot=" .. toHex(gi_ptrSlot) .. " -> " .. toHex(gi_harmonyTarget))

    -- Harmony stub format: mov r10,DATA(10 bytes); mov rax,DISPATCHER(10 bytes); jmp rax(3 bytes)
    -- At DATA+0x08: pointer to the original native trampoline (the "real" function)
    local stub_b1 = readBytes(gi_harmonyTarget, 1)
    local stub_b2 = readBytes(gi_harmonyTarget + 1, 1)
    log(string.format("Harmony stub first 2 bytes: %02X %02X", stub_b1 or 0, stub_b2 or 0))
    if stub_b1 == 0x49 and stub_b2 == 0xBA then
      -- mov r10, imm64 -- read the DATA pointer
      local dataPtr = readQword(gi_harmonyTarget + 2)
      log("Harmony DATA ptr=" .. toHex(dataPtr))
      if dataPtr and dataPtr ~= 0 then
        -- Read first few qwords from DATA to find original function
        for off = 0, 0x28, 8 do
          local candidate = readQword(dataPtr + off)
          if candidate and candidate ~= 0 then
            local c1 = readBytes(candidate, 1)
            local c2 = readBytes(candidate + 1, 1)
            log(string.format("  DATA+%02X = %s -> %02X %02X", off, toHex(candidate), c1 or 0, c2 or 0))
            -- Real IL2CPP code typically starts with: 48 89 (mov [rsp+..]), 55 (push rbp), 56 (push rsi), 57 (push rdi)
            if c1 and (c1 == 0x48 or c1 == 0x55 or c1 == 0x56 or c1 == 0x57 or c1 == 0x40 or c1 == 0x53) then
              local inRange = (candidate >= base and candidate < base + modSize)
              if inRange then
                log("Found original GetItem code at DATA+" .. string.format("%02X", off) .. " = " .. toHex(candidate))
                getItemPtr = candidate
                break
              end
            end
          end
        end
      end
    end
  end
  log("Resolved: getItem=" .. toHex(getItemPtr))

  _ia_getItemPtr = getItemPtr

  -- Pre-allocate memory near GameAssembly.dll in Lua (silent, no CE dialog)
  -- This ensures E9 rel32 can reach hookCode from the patch target.
  local hookMem = allocateMemory(8192, S.base) or allocateMemory(8192)
  if not hookMem or hookMem == 0 then return false, "Failed to allocate hook memory" end
  local cmdBufMem = hookMem
  local hookCodeMem = hookMem + 0x100
  local origUpdateMem = hookMem + 0x1100
  -- Register as symbols so AA script can reference them
  autoAssemble("unregistersymbol(cmdBuf)\nunregistersymbol(hookCode)\nunregistersymbol(origUpdatePtr)")
  registerSymbol("cmdBuf", cmdBufMem)
  registerSymbol("hookCode", hookCodeMem)
  registerSymbol("origUpdatePtr", origUpdateMem)
  log(string.format("Pre-allocated: hookMem=%s cmdBuf=%s hookCode=%s origUpdate=%s",
    toHex(hookMem), toHex(cmdBufMem), toHex(hookCodeMem), toHex(origUpdateMem)))

  -- ============================================================
  -- cmdBuf Layout (120 bytes, shared between hookCode ASM and Lua callers)
  -- +0x00  cmd       (int32)  — command ID: 0=none, 1=GetItem, 2=CreateAndAdd, 3=AllocCtor, 4=GenEquip, 5=GenHero, 6=SimpleCall, 7=ThreeIntCall, 8=PtrCall(runtime_invoke)
  -- +0x04  status    (int32)  — 0=pending, 1=success, 2=error
  -- +0x08  result    (ptr64)  — return value from command
  -- +0x10  param1    (int32)  — edx for cmd=4 (bossLv/typeIdx), ecx for cmd=5/7
  -- +0x14  param2    (int32)  — r8d for cmd=4 (weaponIdx)
  -- +0x18  param3    (float)  — xmm2/xmm3 for cmd=4 (qualityRate)
  -- +0x20  gc        (ptr64)  — GameController._instance (written by discover)
  -- +0x28  hero      (ptr64)  — player HeroData pointer
  -- +0x30  getItemPtr(ptr64)  — resolved GetItem function address
  -- +0x38  gate      (int32)  — enable flag: 0=disabled, 1=enabled
  -- +0x40  heartbeat (int32)  — incremented every Update tick (liveness check)
  -- +0x48  objNew    (ptr64)  — il2cpp_object_new address
  -- +0x50  itemKlass (ptr64)  — ItemData class pointer
  -- +0x58  ctorAddr  (ptr64)  — ItemData..ctor address
  -- +0x60  (reserved)
  -- +0x68  funcAddr  (ptr64)  — function to call for cmd=4/6/7
  -- +0x70  (reserved)
  -- +0x78  (reserved)
  -- +0x80  (reserved)
  -- +0x88  thisPtr   (ptr64)  — this pointer for cmd=8 (runtime_invoke)
  -- +0x90  methodInfo(ptr64)  — MethodInfo* for cmd=8
  -- +0x98  exception (ptr64)  — exception output for cmd=8
  -- +0xA0  args[0]   (ptr64)  — arg pointer array for cmd=8
  -- +0xA8  args[1]   (ptr64)
  -- +0xB0  args[2]   (ptr64)
  -- +0xB8  args[3]   (ptr64)
  -- +0xC0  args[4]   (ptr64)
  -- ============================================================
  local aa = string.format([[
cmdBuf:
dq 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0

origUpdatePtr:
dq 0

label(doGetItem)
label(doCreateAndAdd)
label(doAllocAndCtor)
label(doGenEquip)
label(doGenHero)
label(skipNPCSkill)
label(skipNPCItem)
label(genHeroDone)
label(genHeroError)
label(doSimpleCall)
label(doThreeIntCall)
label(doPtrCall)
label(noPtrCallParams)
label(ptrCallReady)
label(skipSetup)
label(cmdDone)
label(cmdError)
label(noCmd)
label(tailcall)

hookCode:
  push rax
  push rbx
  mov rbx,cmdBuf
  mov eax,[rbx+40]
  inc eax
  mov [rbx+40],eax
  // cmdBuf[+20] = GameController (written by discover, do NOT overwrite with GDC's this)
  cmp dword ptr [rbx+38],1
  jne noCmd
  mov eax,[rbx]
  test eax,eax
  jz noCmd
  cmp eax,1
  je doGetItem
  cmp eax,2
  je doCreateAndAdd
  cmp eax,3
  je doAllocAndCtor
  cmp eax,4
  je doGenEquip
  cmp eax,5
  je doGenHero
  cmp eax,6
  je doSimpleCall
  cmp eax,7
  je doThreeIntCall
  cmp eax,8
  je doPtrCall
  mov dword ptr [rbx+04],2
  mov dword ptr [rbx],0
  jmp noCmd

doGetItem:
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  sub rsp,58
  mov rcx,[rbx+28]
  test rcx,rcx
  jz cmdError
  mov rdx,[rbx+08]
  test rdx,rdx
  jz cmdError
  xor r8d,r8d
  inc r8d
  xor r9d,r9d
  mov dword ptr [rsp+20],0
  mov byte ptr [rsp+28],0
  mov qword ptr [rsp+30],0
  mov rax,[rbx+30]
  call rax
  jmp cmdDone

doCreateAndAdd:
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  sub rsp,58
  mov rcx,[rbx+50]
  mov rax,[rbx+48]
  call rax
  test rax,rax
  jz cmdError
  mov [rbx+08],rax
  mov rcx,rax
  mov edx,[rbx+10]
  mov rax,[rbx+58]
  call rax
  mov rax,[rbx+60]
  test rax,rax
  jz skipSetup
  mov rcx,[rbx+08]
  mov edx,[rbx+14]
  mov r8d,[rbx+18]
  mov r9d,[rbx+1C]
  call rax
skipSetup:
  mov rcx,[rbx+28]
  test rcx,rcx
  jz cmdError
  mov rdx,[rbx+08]
  test rdx,rdx
  jz cmdError
  xor r8d,r8d
  inc r8d
  xor r9d,r9d
  mov dword ptr [rsp+20],0
  mov byte ptr [rsp+28],0
  mov qword ptr [rsp+30],0
  mov rax,[rbx+30]
  call rax
  jmp cmdDone

doAllocAndCtor:
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  sub rsp,58
  mov rcx,[rbx+50]
  mov rax,[rbx+48]
  call rax
  test rax,rax
  jz cmdError
  mov [rbx+08],rax
  mov rcx,rax
  mov edx,[rbx+10]
  mov rax,[rbx+58]
  call rax
  jmp cmdDone

doGenEquip:
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  sub rsp,58
  mov rcx,[rbx+20]
  test rcx,rcx
  jz cmdError
  mov edx,[rbx+10]
  mov r8d,[rbx+14]
  mov eax,[rbx+18]
  movd xmm2,eax
  movd xmm3,eax
  xor r9d,r9d
  mov qword ptr [rsp+20],0
  mov rax,[rbx+68]
  call rax
  test rax,rax
  jz cmdError
  mov [rbx+08],rax
  jmp cmdDone

doGenHero:
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  sub rsp,78
  mov rcx,[rbx+20]
  test rcx,rcx
  jz genHeroError
  xor edx,edx
  mov r8d,FFFFFFFF
  mov r9d,[rbx+10]
  mov eax,[rbx+14]
  mov dword ptr [rsp+20],eax
  mov qword ptr [rsp+28],0
  mov byte ptr [rsp+30],0
  mov eax,[rbx+18]
  mov dword ptr [rsp+38],eax
  mov byte ptr [rsp+40],0
  mov byte ptr [rsp+48],0
  mov qword ptr [rsp+50],0
  mov rax,[rbx+68]
  call rax
  test rax,rax
  jz genHeroError
  mov [rbx+08],rax
  mov rax,[rbx+78]
  test rax,rax
  jz skipNPCSkill
  mov rcx,[rbx+20]
  mov rdx,[rbx+08]
  call rax
skipNPCSkill:
  mov rax,[rbx+80]
  test rax,rax
  jz skipNPCItem
  mov rcx,[rbx+20]
  mov rdx,[rbx+08]
  call rax
skipNPCItem:
  mov rax,[rbx+70]
  test rax,rax
  jz genHeroDone
  mov rcx,[rbx+20]
  mov rdx,[rbx+08]
  xor r8d,r8d
  inc r8d
  call rax
genHeroDone:
  add rsp,78
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  mov dword ptr [rbx+04],1
  mov dword ptr [rbx],0
  jmp noCmd

genHeroError:
  add rsp,78
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  mov dword ptr [rbx+04],2
  mov dword ptr [rbx],0
  jmp noCmd

doThreeIntCall:
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  sub rsp,58
  mov rcx,[rbx+20]
  test rcx,rcx
  jz cmdError
  mov edx,[rbx+10]
  mov r8d,[rbx+14]
  mov r9d,[rbx+18]
  mov rax,[rbx+68]
  call rax
  test rax,rax
  jz cmdError
  mov [rbx+08],rax
  jmp cmdDone

doPtrCall:
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  sub rsp,58
  mov rcx,[rbx+90]
  test rcx,rcx
  jz cmdError8
  mov rdx,[rbx+88]
  cmp qword ptr [rbx+A0],0
  je noPtrCallParams
  lea r8,[rbx+A0]
  jmp ptrCallReady
noPtrCallParams:
  xor r8,r8
ptrCallReady:
  lea r9,[rbx+98]
  mov qword ptr [rbx+98],0
  mov rax,[rbx+68]
  call rax
  mov [rbx+08],rax
  cmp qword ptr [rbx+98],0
  jne cmdError8
  add rsp,58
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  mov dword ptr [rbx+04],1
  mov dword ptr [rbx],0
  jmp noCmd
cmdError8:
  add rsp,58
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  mov dword ptr [rbx+04],2
  mov dword ptr [rbx],0
  jmp noCmd

doSimpleCall:
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  sub rsp,58
  mov rcx,[rbx+08]
  xor edx,edx
  mov rax,[rbx+68]
  call rax
  mov [rbx+08],rax
  jmp cmdDone

cmdDone:
  add rsp,58
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  mov dword ptr [rbx+04],1
  mov dword ptr [rbx],0
  jmp noCmd

cmdError:
  add rsp,58
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  mov dword ptr [rbx+04],2
  mov dword ptr [rbx],0

noCmd:
  pop rbx
  pop rax

tailcall:
  jmp qword ptr [origUpdatePtr]
]]
  )

  log("AA script prepared")
  local ok, errMsg = autoAssemble(aa)
  log("autoAssemble returned: " .. tostring(ok) .. " err: " .. tostring(errMsg))
  if not ok then return false, "AA failed: " .. tostring(errMsg) end

  local cmdBufAddr = getAddress("cmdBuf")
  local hookCodeAddr = getAddress("hookCode")
  local origPtrSlot = getAddress("origUpdatePtr")
  log("cmdBuf=" .. toHex(cmdBufAddr) .. " hookCode=" .. toHex(hookCodeAddr) .. " origPtrSlot=" .. toHex(origPtrSlot))

  -- Write the chain target (Harmony handler or original code) to origUpdatePtr slot
  writeQword(origPtrSlot, origChainTarget)

  if harmonyPtrSlot then
    -- Overwrite Harmony's indirect jump pointer to point to our hook
    writeQword(harmonyPtrSlot, hookCodeAddr)
    local verify = readQword(harmonyPtrSlot)
    if verify ~= hookCodeAddr then return false, "Harmony ptrSlot write failed" end
    log("Wrote hookCode to Harmony ptrSlot OK")

    -- Store for DISABLE cleanup
    _ia_harmonyPtrSlot = harmonyPtrSlot
    _ia_origChainTarget = origChainTarget
    _ia_methodInfo = nil
    _ia_origUpdatePtr = nil
  elseif _ia_directPatch then
    -- Write JMP to hookCode at the patch address
    local rel32 = hookCodeAddr - (_ia_directPatchAddr + 5)
    local patch
    if rel32 >= -0x80000000 and rel32 <= 0x7FFFFFFF then
      -- Direct E9 rel32 JMP fits (hookCode is within 2GB)
      if rel32 < 0 then rel32 = rel32 + 0x100000000 end
      patch = {0xE9,
        rel32 % 256,
        math.floor(rel32 / 256) % 256,
        math.floor(rel32 / 65536) % 256,
        math.floor(rel32 / 16777216) % 256}
      for i = 6, _ia_patchLen do patch[#patch + 1] = 0x90 end
      log("Using direct E9 rel32 patch")
    else
      -- hookCode too far for E9 rel32 — patch with 14-byte FF 25 absolute jump
      -- Requires at least 14 bytes at the patch site (6 bytes FF25 + 8 bytes addr)
      if _ia_patchLen < 14 then
        -- Not enough space for FF 25 — use relay trampoline
        _ia_relayCode = allocateMemory(32)
        if not _ia_relayCode or _ia_relayCode == 0 then
          return false, "Failed to allocate relay trampoline"
        end
        writeBytes(_ia_relayCode, {0xFF, 0x25, 0x00, 0x00, 0x00, 0x00})
        writeQword(_ia_relayCode + 6, hookCodeAddr)
        local relRelay = _ia_relayCode - (_ia_directPatchAddr + 5)
        if relRelay < 0 then relRelay = relRelay + 0x100000000 end
        patch = {0xE9,
          relRelay % 256,
          math.floor(relRelay / 256) % 256,
          math.floor(relRelay / 65536) % 256,
          math.floor(relRelay / 16777216) % 256}
        for i = 6, _ia_patchLen do patch[#patch + 1] = 0x90 end
        log(string.format("Using relay trampoline at %s", toHex(_ia_relayCode)))
      else
        -- Enough space: write FF 25 00 00 00 00 + 8-byte hookCode addr directly
        patch = {0xFF, 0x25, 0x00, 0x00, 0x00, 0x00}
        local addrBytes = {}
        local addr = hookCodeAddr
        for i = 1, 8 do addrBytes[i] = addr % 256; addr = math.floor(addr / 256) end
        for i = 1, 8 do patch[#patch + 1] = addrBytes[i] end
        for i = 15, _ia_patchLen do patch[#patch + 1] = 0x90 end
        log(string.format("Using direct FF25 absolute jump to %s", toHex(hookCodeAddr)))
      end
    end
    writeBytes(_ia_directPatchAddr, patch)
    local verify = readBytes(_ia_directPatchAddr, 1)
    if verify ~= 0xE9 and verify ~= 0xFF then return false, "Direct code patch failed" end
    log(string.format("Direct patch OK at %s (first byte=%02X, padded to %d bytes)",
        toHex(_ia_directPatchAddr), verify, _ia_patchLen))

    _ia_harmonyPtrSlot = nil
    _ia_origChainTarget = nil
    _ia_methodInfo = nil
    _ia_origUpdatePtr = nil
  end

  log("Hook pointer written -- verifying heartbeat...")

  -- Verify the hook is actually running by watching the heartbeat counter
  local cmdBufAddr2 = getAddress("cmdBuf")
  local hb1 = readInteger(cmdBufAddr2 + 0x40) or 0
  sleep(200)  -- wait ~12 frames at 60fps
  local hb2 = readInteger(cmdBufAddr2 + 0x40) or 0
  log(string.format("Heartbeat check: before=%d after=%d (delta=%d)", hb1, hb2, hb2 - hb1))

  if hb2 <= hb1 then
    log("ERROR: Heartbeat not incrementing -- hook is NOT running!")
    -- Restore original pointer to avoid leaving broken hook
    if harmonyPtrSlot then
      writeQword(harmonyPtrSlot, origChainTarget)
      log("Restored Harmony pointer after failed heartbeat")
    elseif _ia_directPatch and _ia_directPatchOrigBytes then
      local n = _ia_patchLen or #_ia_directPatchOrigBytes
      for i = 1, n do writeBytes(_ia_directPatchAddr + i - 1, _ia_directPatchOrigBytes[i]) end
      log("Restored original bytes after failed heartbeat")
      _ia_directPatch = nil; _ia_patchLen = nil
      if _ia_relayCode then deAlloc(_ia_relayCode); _ia_relayCode = nil end
    end
    return false, "Hook installed but not running (heartbeat=0). Game may not call Update through this path."
  end

  -- Hook is running! Now enable command processing.
  writeInteger(cmdBufAddr2 + 0x38, 1)
  log("Hook verified and commands ENABLED")

  log("Hook installed OK")
  MT.hook.hookInstalled = true
  return true
end

-- ============================================================
-- MT.hook.discover
-- ============================================================
function MT.hook.discover(fastMode)
  MT.log.open()
  log("=== discover(" .. (fastMode and "fast" or "full") .. ") start ===")
  local S = MT.hook.S
  local RVA = MT.hook.RVA
  local equipDBs = MT.hook.equipDBs
  -- Only clear IL2CPP cache if GA base changed (game restarted)
  local newBase = getAddress("GameAssembly.dll")
  if _il2cppCache and _il2cppCache._gaBase == newBase then
    log("IL2CPP cache valid (base unchanged)")
  else
    _il2cppCache = nil
    log("IL2CPP cache cleared (base changed or first connect)")
  end
  MT.hook._aobsResolved = false
  MT.hook.S = {}
  S = MT.hook.S
  S.base = newBase
  log("S.base = " .. toHex(S.base))
  if not S.base or S.base == 0 then log("失败: GameAssembly.dll未加载 GA not loaded"); return false, "请先用CE连接游戏 Attach CE to game first" end
  if not MT.hook.allocWorkArea() then log("失败: 分配工作区失败 alloc work area failed"); return false, "内存分配失败 Memory alloc failed" end

  local classFromName = getAddress("GameAssembly.il2cpp_class_from_name")
  local objNew = getAddress("GameAssembly.il2cpp_object_new")
  if not objNew or objNew == 0 then log("失败: il2cpp导出函数缺失 il2cpp_object_new missing"); return false, "il2cpp导出缺失 请重启CE IL2CPP exports missing" end
  S.objNew = objNew

  -- Use executeCodeEx (proven safe) instead of shellExec/createRemoteThread (crashes)
  local c = MT.il2cpp.init()
  local gameImage = c.img
  S.gameImage = gameImage
  log("Game image from il2cpp.init: " .. toHex(gameImage))

  local function findClass(name)
    local ns = allocateMemory(16); writeString(ns, "")
    local cn = allocateMemory(64); writeString(cn, name)
    local k = executeCodeEx(0, nil, classFromName, gameImage, ns, cn)
    deAlloc(ns); deAlloc(cn)
    return k ~= 0 and k or nil
  end

  log("About to findClass GameController...")
  local gcClass = findClass("GameController")
  log("gcClass=" .. toHex(gcClass or 0))
  if not gcClass or gcClass == 0 then log("失败: GameController类未找到 GC class not found"); return false, "游戏类未找到 请重启CE GameController not found" end
  log("About to findClass GameDataController...")
  local gdcClass = findClass("GameDataController")
  log("gdcClass=" .. toHex(gdcClass or 0))

  local gc = readQword(c.gc.static + c.gc.instOff)
  if not gc or gc == 0 then log("失败: GC实例为空——请先加载存档 GC._instance null"); return false, "请先加载存档再连接 Load a save first" end
  S.gc = gc
  log("gc=" .. toHex(gc))

  if gdcClass then
    if c:ensure("gdc", "GameDataController", 0x20) then
      S.gdc = readQword(c.gdc.static + c.gdc.instOff)
    end
  end

  -- Auto-detect ItemData field offsets (changed between early f7 and f7.6+)
  -- f7.6+/f8: medFoodData=0x68, horseData=0x88
  -- early f7: medFoodData=0x60, horseData=0x80
  S.OFF_MEDFOOD = 0x68  -- default (f7.6+/f8)
  S.OFF_HORSE = 0x88
  if S.gdc and S.gdc ~= 0 then
    local hdb = readQword(S.gdc + 0x120) -- horseDataBase
    if hdb and hdb ~= 0 then
      local hitems = readQword(hdb + 0x10)
      local ht = hitems and readQword(hitems + 0x20) -- first horse template
      if ht and ht ~= 0 then
        local at88 = readQword(ht + 0x88)
        local at80 = readQword(ht + 0x80)
        if (not at88 or at88 == 0) and at80 and at80 ~= 0 then
          S.OFF_MEDFOOD = 0x60
          S.OFF_HORSE = 0x80
          log("Detected early f7 offsets: medFood=0x60, horse=0x80")
        else
          log("Using standard offsets: medFood=0x68, horse=0x88")
        end
      end
    end
  end

  local wd = readQword(gc + 0x20)
  if not wd or wd == 0 then log("失败: 世界数据为空 WorldData null"); return false, "世界数据为空 请加载存档 WorldData null" end
  local hl = readQword(wd + 0x50)
  if not hl or hl == 0 then log("失败: 角色列表为空 HerosList null"); return false, "角色列表为空 请加载存档 HerosList null" end
  local ip = readQword(hl + 0x10)
  if not ip or ip == 0 then log("失败: 角色数据为空 HerosList items null"); return false, "HerosList items null" end
  local ph = readQword(ip + 0x20)
  if not ph or ph == 0 then log("失败: 主角未找到 Hero not found"); return false, "主角未找到 请加载存档 Hero not found" end
  S.hero = ph
  local ild = readQword(ph + 0x220)
  if not ild or ild == 0 then return false, "ItemListData null" end
  S.ild = ild
  S.ildKlass = readQword(S.ild)
  log("hero=" .. toHex(ph) .. " ild=" .. toHex(ild))

  local ail = readQword(S.ild + 0x28)
  if not ail or ail == 0 then log("失败: 物品列表为空 allItem list null"); return false, "allItem list null" end
  local ic = readInteger(ail + 0x18)
  local ia = readQword(ail + 0x10)
  for i = 0, ic - 1 do
    local it = readQword(ia + 0x20 + i * 8)
    if it and it ~= 0 then
      if not S.itemKlass then S.itemKlass = readQword(it) end
    end
  end
  if not S.itemKlass then log("失败: 背包中无物品 No items in inventory"); return false, "背包为空 请先获得一个物品 No items in inventory" end
  log("数据正常 Data OK: wd=" .. toHex(wd) .. " hero=" .. toHex(ph) .. " items=" .. ic)

  -- Try loading RVAs from cache (keyed by GA DLL size)
  local gaSize = getModuleSize("GameAssembly.dll") or 0
  local cached = MT.cache.load(gaSize)
  if cached then
    local cacheHits = 0
    for k, v in pairs(cached) do
      local prefix, name = k:match("^(%a+)%.(.+)$")
      if prefix == "rva" and type(v) == "number" then
        RVA[name] = v
        cacheHits = cacheHits + 1
      elseif prefix == "aob" and type(v) == "number" then
        RVA[name] = v
        cacheHits = cacheHits + 1
      end
    end
    if cacheHits > 0 then
      log(string.format("Loaded %d RVAs from cache (GA=%d bytes)", cacheHits, gaSize))
    end
  end

  -- Resolve ALL method RVAs at runtime (skip if already cached)
  local gmfn = getAddress("GameAssembly.il2cpp_class_get_method_from_name")
  local function resolveRVA(klass, name, params)
    if RVA[name] then return RVA[name] end  -- skip if cached
    local nm = allocateMemory(64); writeString(nm, name)
    local mi = executeCodeEx(0, nil, gmfn, klass, nm, params)
    deAlloc(nm)
    if not mi or mi == 0 then return nil end
    local addr = readQword(mi)
    return addr and addr ~= 0 and (addr - S.base) or nil
  end

  local heroClass = c:ensure("hd", "HeroData") and c.hd.klass
  local itemClass = findClass("ItemData")
  local ildClass = findClass("ItemListData")

  if heroClass then
    RVA.getItem = resolveRVA(heroClass, "GetItem", 5)
  end
  if itemClass then
    RVA.ctor = resolveRVA(itemClass, ".ctor", 1)
    RVA.setBook = resolveRVA(itemClass, "SetBookData", 2)
    RVA.setMat = resolveRVA(itemClass, "SetMaterialData", 3)
    RVA.clone = resolveRVA(itemClass, "Clone", 0)
  end
  if ildClass then
    RVA.ildCtor = resolveRVA(ildClass, ".ctor", 0)
    RVA.mergeList = resolveRVA(ildClass, "MergeList", 1)
  end
  if gcClass then
    RVA.genMedById = resolveRVA(gcClass, "GenerateMedData", 2)
    RVA.genFoodById = resolveRVA(gcClass, "GenerateFoodData", 2)
    RVA.genHorseById = resolveRVA(gcClass, "GenerateHorseData", 2)
    RVA.genMaterial = resolveRVA(gcClass, "GenerateMaterial", 3)
    RVA.genHorseArmor = resolveRVA(gcClass, "GenerateHorseArmorData", 2)
  end
  S.setBookAddr = S.base + (RVA.setBook or 0)

  -- Resolve equipment generator RVAs
  if gcClass then
    for _, db in ipairs(equipDBs) do
      db.genRVA = RVA[db.genMethod] or resolveRVA(gcClass, db.genMethod, db.genParams)
      RVA[db.genMethod] = db.genRVA  -- ensure it's in RVA table for cache
    end
    MT.hook.TREASURE_GEN_RVA = RVA["GenerateTreasure"] or resolveRVA(gcClass, "GenerateTreasure", 3)
    RVA["GenerateTreasure"] = MT.hook.TREASURE_GEN_RVA
    if not RVA.genHeroData9 then RVA.genHeroData9 = nil end  -- 9-param overload
    if not RVA.worldAddHero then RVA.worldAddHero = nil end
    if not RVA.joinForce then RVA.joinForce = nil end
    -- Use method iterator (skip if all RVAs already cached)
    local needIter = not (RVA.recruitHero and RVA.genNPCSkill and RVA.genNPCItem
      and RVA.genHeroData6 and RVA.genHeroData9 and RVA.worldAddHero
      and RVA.joinForce and RVA.wdAddNewHero)
    local iterMethods = getAddress("GameAssembly.il2cpp_class_get_methods")
    local iterGetName = getAddress("GameAssembly.il2cpp_method_get_name")
    local iterGetParamName = getAddress("GameAssembly.il2cpp_method_get_param_name")
    -- Scan GameController methods (skip if all cached)
    if not needIter then log("All iter RVAs cached, skipping method scan") end
    local it = allocateMemory(8); writeQword(it, 0)
    for i = 1, needIter and 500 or 0 do
      local mi = executeCodeEx(0, nil, iterMethods, gcClass, it)
      if not mi or mi == 0 then break end
      local np = executeCodeEx(0, nil, iterGetName, mi)
      local mn = np and readString(np, 64) or ""
      local addr = readQword(mi)
      local rva = addr - S.base
      if mn == "ManagePlayerRecruitHero" and not RVA.recruitHero then RVA.recruitHero = rva end
      if mn == "RandomGenerateNPCSkill" and not RVA.genNPCSkill then RVA.genNPCSkill = rva end
      if mn == "RandomGenerateNPCItem" and not RVA.genNPCItem then RVA.genNPCItem = rva end
      if mn == "GenerateHeroData" and not RVA.genHeroData6 then
        local p1 = executeCodeEx(0, nil, iterGetParamName, mi, 0)
        local p1name = p1 and readString(p1, 32) or ""
        if p1name == "heroID" then RVA.genHeroData6 = rva end
      end
      if mn == "GenerateHeroData" and not RVA.genHeroData9 then
        -- Check if this is the 9-param overload (has sexLimit param)
        local p6 = executeCodeEx(0, nil, iterGetParamName, mi, 6)
        local p6name = p6 and readString(p6, 32) or ""
        if p6name == "sexLimit" then RVA.genHeroData9 = rva end
      end
      if mn == "WorldAddNewHero" then RVA.worldAddHero = rva end
    end
    deAlloc(it)
    -- Scan HeroData for JoinForce
    local hdClass2 = findClass("HeroData")
    if hdClass2 and not RVA.joinForce then
      it = allocateMemory(8); writeQword(it, 0)
      for i = 1, 200 do
        local mi = executeCodeEx(0, nil, iterMethods, hdClass2, it)
        if not mi or mi == 0 then break end
        local np = executeCodeEx(0, nil, iterGetName, mi)
        local mn = np and readString(np, 64) or ""
        if mn == "JoinForce" then RVA.joinForce = readQword(mi) - S.base; break end
      end
      deAlloc(it)
    end
    -- Scan WorldData for AddNewHero
    local wdClass = findClass("WorldData")
    if wdClass and not RVA.wdAddNewHero then
      it = allocateMemory(8); writeQword(it, 0)
      for i = 1, 200 do
        local mi = executeCodeEx(0, nil, iterMethods, wdClass, it)
        if not mi or mi == 0 then break end
        local np = executeCodeEx(0, nil, iterGetName, mi)
        local mn = np and readString(np, 64) or ""
        if mn == "AddNewHero" then RVA.wdAddNewHero = readQword(mi) - S.base; break end
      end
      deAlloc(it)
    end
    log(string.format("Hero RVAs: genHero9=%s wdAdd=%s joinForce=%s worldAddHero=%s",
      tostring(RVA.genHeroData9), tostring(RVA.wdAddNewHero), tostring(RVA.joinForce), tostring(RVA.worldAddHero)))
  end

  -- Log game version + resolved RVAs for crash analysis
  local gaSize = getModuleSize("GameAssembly.dll")
  local verInfo = "?"
  if c.gd then
    pcall(function()
      local gs = readQword(c.findClass("GlobalData") + 0xB8)
      local vn = readQword(gs + 0x68)
      local fn = readQword(gs + 0x70)
      local v = readString(vn + 0x14, readInteger(vn + 0x10) * 2, true)
      local f = readString(fn + 0x14, readInteger(fn + 0x10) * 2, true)
      verInfo = v .. " " .. f
    end)
  end
  log(string.format("Game: %s (GA=%d bytes)", verInfo, gaSize or 0))
  log(string.format("RVAs: getItem=%s ctor=%s genWeapon=%s genTreasure=%s",
    tostring(RVA.getItem), tostring(RVA.ctor), tostring(equipDBs[1].genRVA), tostring(MT.hook.TREASURE_GEN_RVA)))

  -- Count resolved RVAs
  local rvaCount = 0
  for _ in pairs(RVA) do rvaCount = rvaCount + 1 end
  log("已解析 Resolved " .. rvaCount .. " 个RVA地址")

  -- Install main-thread hook
  log("正在安装主线程钩子 Installing main-thread hook...")
  local hookOk, hookErr = MT.hook.installMainThreadHook()
  if not hookOk then log("失败: 钩子安装失败 hook install: " .. tostring(hookErr)); return false, "Hook: " .. (hookErr or "unknown") end
  log("钩子安装成功 Hook installed OK")

  local cmdBuf = getAddress("cmdBuf")
  S.cmdBuf = cmdBuf
  S.ready = true

  -- Write essential pointers to cmdBuf (needed by all commands, including fast mode)
  writeQword(cmdBuf + 0x20, S.gc or 0)
  writeQword(cmdBuf + 0x28, S.hero or 0)

  -- Fast mode: hook installed, done. Skip item/class resolution.
  if fastMode then
    log("discover(fast) OK -- hook only")
    return true, "Hook installed (fast mode)"
  end

  -- Full mode: resolve everything for item adding
  MT.hook.resolveAOBs()
  writeQword(cmdBuf + 0x28, S.hero)
  writeQword(cmdBuf + 0x30, _ia_getItemPtr or 0)
  writeQword(cmdBuf + 0x48, S.objNew)
  writeQword(cmdBuf + 0x50, S.itemKlass)
  writeQword(cmdBuf + 0x58, S.base + (RVA.ctor or 0))

  -- Save RVAs + AOBs to cache for next session
  if gaSize > 0 then
    local aobRVAs = {}
    for name, _ in pairs(MT.hook.AOB_SIGS) do
      if RVA[name] then aobRVAs[name] = RVA[name] end
    end
    if MT.cache.save(gaSize, RVA, aobRVAs) then
      log("RVA cache saved for GA=" .. gaSize)
    end
  end

  log("discover(full) OK: " .. ic .. " items")
  return true, string.format("OK! %d items. Hook:Y GDC:%s", ic, S.gdc and "Y" or "N")
end

-- ============================================================
-- MT.hook.cleanup -- Unhook and dealloc (called on DISABLE)
-- ============================================================
function MT.hook.cleanup()
  -- 1. Close debug log
  MT.log.close()

  -- 2. Disarm command gate + clear pending commands before unhook
  local ok_cb, cmdBufAddr = pcall(getAddress, "cmdBuf")
  if ok_cb and cmdBufAddr and cmdBufAddr ~= 0 then
    writeInteger(cmdBufAddr + 0x38, 0)  -- disable command processing
    writeInteger(cmdBufAddr, 0)          -- clear any pending command
    writeInteger(cmdBufAddr + 0x04, 0)   -- clear status
  end

  -- 3. Unhook GameController.Update
  if _ia_harmonyPtrSlot and _ia_origChainTarget then
    writeQword(_ia_harmonyPtrSlot, _ia_origChainTarget)
    print("[MultiTool] Restored Harmony trampoline pointer")
    _ia_harmonyPtrSlot = nil
    _ia_origChainTarget = nil
    sleep(100)
  elseif _ia_directPatch and _ia_directPatchAddr and _ia_directPatchOrigBytes then
    local n = _ia_patchLen or #_ia_directPatchOrigBytes
    for i = 1, n do writeBytes(_ia_directPatchAddr + i - 1, _ia_directPatchOrigBytes[i]) end
    print("[MultiTool] Restored original Update code bytes")
    _ia_directPatch = nil; _ia_patchLen = nil
    _ia_directPatchAddr = nil
    _ia_directPatchOrigBytes = nil
    if _ia_relayCode then deAlloc(_ia_relayCode); _ia_relayCode = nil end
    sleep(100)
  end

  -- 4. Dealloc + unregister symbols (pcall-guarded)
  local function tryDealloc(name)
    local ok2, addr = pcall(getAddress, name)
    if not ok2 or not addr or addr == 0 then return end
    pcall(autoAssemble, string.format("unregistersymbol(%s)", name))
    pcall(autoAssemble, string.format("dealloc(%s)", name))
  end
  tryDealloc("wkCode")
  tryDealloc("wkData")
  tryDealloc("wkStr")
  tryDealloc("cmdBuf")
  tryDealloc("hookCode")
  tryDealloc("origUpdatePtr")

  -- 5. Reset state
  MT.hook.hookInstalled = false
  MT.hook.S = {}
  MT.hook.WK = { code = nil, data = nil, str = nil }
  _ia_hookInstalled = nil
end

-- ============================================================
-- MT.hook command dispatch (main-thread calls)
-- ============================================================

function MT.hook.mainThreadGetItem(itemDataPtr, timeout)
  local S = MT.hook.S
  if not S.cmdBuf then return false, "Not connected" end
  timeout = timeout or 3000
  log(string.format("cmd1 GetItem: item=%s hero=%s getItemPtr=%s", toHex(itemDataPtr), toHex(S.hero), toHex(_ia_getItemPtr)))
  writeQword(S.cmdBuf + 0x08, itemDataPtr)
  writeQword(S.cmdBuf + 0x28, S.hero or 0)
  writeQword(S.cmdBuf + 0x30, _ia_getItemPtr or 0)
  writeInteger(S.cmdBuf + 0x04, 0)
  writeInteger(S.cmdBuf, 1)
  local elapsed = 0
  while elapsed < timeout do
    local status = readInteger(S.cmdBuf + 0x04)
    if status == 1 then
      return true, readQword(S.cmdBuf + 0x18)
    elseif status == 2 then
      return false, "Command failed (status=2)"
    end
    sleep(16)
    elapsed = elapsed + 16
  end
  local st = readInteger(S.cmdBuf + 0x04)
  local gcVal = readQword(S.cmdBuf + 0x20)
  local cmdVal = readInteger(S.cmdBuf) or 0
  local msg = string.format("Timeout cmd=%d st=%d gc=%X", cmdVal, st, gcVal or 0)
  log("cmd1 " .. msg)
  return false, msg
end

function MT.hook.mainThreadCreateAndAdd(itemType, setupFunc, arg1, arg2, arg3, timeout)
  local S = MT.hook.S
  local RVA = MT.hook.RVA
  if not S.cmdBuf then return false, "Not connected" end
  timeout = timeout or 3000
  log(string.format("cmd2 CreateAndAdd: type=%d setup=%s args=%s/%s/%s", itemType, toHex(setupFunc), tostring(arg1), tostring(arg2), tostring(arg3)))
  writeInteger(S.cmdBuf + 0x10, itemType)
  writeInteger(S.cmdBuf + 0x14, arg1 or 0)
  writeInteger(S.cmdBuf + 0x18, arg2 or 0)
  writeInteger(S.cmdBuf + 0x1C, arg3 or 0)
  writeQword(S.cmdBuf + 0x28, S.hero or 0)
  writeQword(S.cmdBuf + 0x30, _ia_getItemPtr or 0)
  writeQword(S.cmdBuf + 0x48, S.objNew)
  writeQword(S.cmdBuf + 0x50, S.itemKlass)
  writeQword(S.cmdBuf + 0x58, S.base + RVA.ctor)
  writeQword(S.cmdBuf + 0x60, setupFunc or 0)
  writeInteger(S.cmdBuf + 0x04, 0)
  writeInteger(S.cmdBuf, 2)
  local elapsed = 0
  while elapsed < timeout do
    local status = readInteger(S.cmdBuf + 0x04)
    if status == 1 then return true, readQword(S.cmdBuf + 0x08) end
    if status == 2 then return false, "CreateAndAdd failed" end
    sleep(16)
    elapsed = elapsed + 16
  end
  return false, "Timeout"
end

function MT.hook.mainThreadAllocCtor(itemType, timeout)
  local S = MT.hook.S
  local RVA = MT.hook.RVA
  if not S.cmdBuf then return false, "Not connected" end
  timeout = timeout or 3000
  log(string.format("cmd3 AllocCtor: type=%d", itemType))
  writeInteger(S.cmdBuf + 0x10, itemType)
  writeQword(S.cmdBuf + 0x48, S.objNew)
  writeQword(S.cmdBuf + 0x50, S.itemKlass)
  writeQword(S.cmdBuf + 0x58, S.base + RVA.ctor)
  writeInteger(S.cmdBuf + 0x04, 0)
  writeInteger(S.cmdBuf, 3)
  local elapsed = 0
  while elapsed < timeout do
    local status = readInteger(S.cmdBuf + 0x04)
    if status == 1 then return true, readQword(S.cmdBuf + 0x08) end
    if status == 2 then return false, "AllocCtor failed" end
    sleep(16)
    elapsed = elapsed + 16
  end
  return false, "Timeout"
end

-- ============================================================
-- MT.hook helpers (getItemName, allocItem, callFunc, mergeIntoInventory)
-- ============================================================

function MT.hook.getItemName(ptr)
  if not ptr or ptr == 0 then return "?" end
  local np = readQword(ptr + 0x20)
  if not np or np == 0 then return "?" end
  local nl = readInteger(np + 0x10)
  if not nl or nl <= 0 or nl > 200 then return "?" end
  return readString(np + 0x14, nl * 2, true) or "?"
end

-- (allocItem, callFunc, mergeIntoInventory removed — used shellExec/createRemoteThread
--  which is replaced by the main-thread hook commands cmd=1 through cmd=8)
