-- src/09_data.lua — Data loading and treasure type definitions (MT.data)
-- ============================================================
-- MT.data -- Databases for dropdowns (used by form code)
-- ============================================================
MT.data = {}

-- Load a pipe-delimited data file from embedded table files.
-- Returns a list of tables, each with fields split by "|".
-- First field is always converted to number (the ID).
function MT.data.loadFile(filename)
  local content = nil
  -- 1. Check CT's directory (companion data files shipped alongside CT)
  pcall(function()
    local ctPath = getOpenedFile()
    if ctPath and #ctPath > 0 then
      local dir = ctPath:match("(.*[/\\])")
      if dir then
        local f = io.open(dir .. filename, "r")
        if f then content = f:read("*a"); f:close() end
      end
    end
  end)
  -- 2. Fall back to CE embedded table files (small files in Files section)
  if not content then
    local tf = findTableFile(filename)
    if tf then
      local tmpPath = getTempFolder() .. filename
      tf.saveToFile(tmpPath)
      local f = io.open(tmpPath, "r")
      if f then content = f:read("*a"); f:close() end
    end
  end
  if not content then
    print("[MT.data] File not found: " .. filename)
    return {}
  end
  local items = {}
  for line in content:gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")  -- trim
    if line and #line > 0 then
      local parts = {}
      -- Split by | preserving empty fields (gmatch("[^|]+") skips empties)
      local pos = 1
      while true do
        local pipePos = line:find("|", pos, true)
        if pipePos then
          table.insert(parts, line:sub(pos, pipePos - 1))
          pos = pipePos + 1
        else
          table.insert(parts, line:sub(pos))
          break
        end
      end
      if #parts >= 2 then
        parts[1] = tonumber(parts[1]) or parts[1]
        table.insert(items, parts)
      end
    end
  end
  return items
end

-- Convert loaded data to {id, "display name"} format for dropdown compatibility
function MT.data.toDropdown(data, nameCols)
  local result = {}
  for _, row in ipairs(data) do
    local id = row[1]
    local parts = {}
    for _, col in ipairs(nameCols or {2}) do
      if row[col] then table.insert(parts, row[col]) end
    end
    table.insert(result, {id, table.concat(parts, " ")})
  end
  return result
end

-- Lazy-loaded databases (populated on first access)
MT.data._cache = {}
function MT.data.get(name)
  if MT.data._cache[name] then return MT.data._cache[name] end
  local loaders = {
    skillDB  = function() return MT.data.toDropdown(MT.data.loadFile("skills.dat"), {2, 3}) end,
    medDB    = function() return MT.data.toDropdown(MT.data.loadFile("medicine.dat"), {2, 3, 4}) end,
    foodDB   = function() return MT.data.toDropdown(MT.data.loadFile("food.dat"), {2, 3, 4}) end,
    horseDB  = function() return MT.data.toDropdown(MT.data.loadFile("horses.dat"), {2}) end,
    matDB    = function() return MT.data.toDropdown(MT.data.loadFile("materials.dat"), {2, 3}) end,
  }
  if loaders[name] then
    MT.data._cache[name] = loaders[name]()
    return MT.data._cache[name]
  end
  return nil
end

-- Load stat names from GameDataController.speAddDataBase (215 entries)
-- Returns table: statNames[id] = "name"
function MT.data.loadStatNames()
  if MT.data._statNames then return MT.data._statNames end
  local c = MT.il2cpp.init()
  if not c.gdc then c:ensure("gdc", "GameDataController", 0x20) end
  local gdcInst = readQword(c.gdc.static + c.gdc.instOff)
  if not gdcInst or gdcInst == 0 then return {} end
  local speDB = readQword(gdcInst + 0x90)
  if not speDB or speDB == 0 then return {} end
  local speItems = readQword(speDB + 0x10)
  local speCount = readInteger(speDB + 0x18)
  local names = {}
  for i = 0, speCount - 1 do
    local spe = readQword(speItems + 0x20 + i * 8)
    if spe and spe ~= 0 then
      local np = readQword(spe + 0x10)
      if np and np ~= 0 then
        local nl = readInteger(np + 0x10)
        names[i] = readString(np + 0x14, nl * 2, true)
      end
    end
  end
  MT.data._statNames = names
  return names
end

-- Read a HeroSpeAddData dictionary (Dictionary<int,float> at obj+0x10)
-- Returns string and numeric total. showPct=true formats values as percentages.
-- IL2CPP Dict layout: count at dict+0x20, entries array at dict+0x18,
-- each entry 16 bytes at entries+0x20: hashCode(4) next(4) key(4) value(4)
function MT.data.readSpeDict(ptr, showPct)
  if not ptr or ptr == 0 then return "", 0 end
  local dict = readQword(ptr + 0x10)
  if not dict or dict == 0 then return "", 0 end
  local cnt = readInteger(dict + 0x20)
  if not cnt or cnt <= 0 then return "", 0 end
  local entries = readQword(dict + 0x18)
  if not entries or entries == 0 then return "", 0 end
  local statNames = MT.data.loadStatNames()
  local speDB = MT.data._speAddDB  -- for showPercent lookup
  local parts = {}
  local total = 0
  for i = 0, cnt - 1 do
    local base = entries + 0x20 + i * 16
    local hash = readInteger(base)  -- skip tombstoned entries (hashCode < 0)
    if not hash or hash < 0 then goto nextEntry end
    local key = readInteger(base + 8)
    local val = readFloat(base + 12)
    if statNames[key] then
      total = total + math.abs(val)
      local isPct = false
      if speDB and speDB[key] then isPct = speDB[key].showPct end
      local sign = val >= 0 and "+" or ""
      if isPct or showPct then
        parts[#parts + 1] = statNames[key] .. sign .. string.format("%.0f%%", val * 100)
      else
        parts[#parts + 1] = statNames[key] .. sign .. string.format("%.0f", val)
      end
    end
    ::nextEntry::
  end
  return table.concat(parts, ", "), total
end

-- Load speAddDataBase with showPercent flags (for use effect formatting)
function MT.data.loadSpeAddDB()
  if MT.data._speAddDB then return MT.data._speAddDB end
  local c = MT.il2cpp.init()
  if not c.gdc then c:ensure("gdc", "GameDataController", 0x20) end
  local gdcInst = readQword(c.gdc.static + c.gdc.instOff)
  if not gdcInst or gdcInst == 0 then return {} end
  local speDB = readQword(gdcInst + 0x90)
  if not speDB or speDB == 0 then return {} end
  local speItems = readQword(speDB + 0x10)
  local speCount = readInteger(speDB + 0x18)
  local db = {}
  for i = 0, speCount - 1 do
    local spe = readQword(speItems + 0x20 + i * 8)
    if spe and spe ~= 0 then
      db[i] = { showPct = readBytes(spe + 0x38, 1) == 1 }
    end
  end
  MT.data._speAddDB = db
  return db
end

-- Read addDamageRatio (AttriNumData at skill+0x48) as formatted text
-- attri: 力道,灵巧,智力,意志,体质,经脉 | fightSkill: 内功-射术 | Hp,Power,Mana
function MT.data.readDmgBonus(sk)
  local addDmg = readQword(sk + 0x48)
  if not addDmg or addDmg == 0 then return "" end
  local attriNames = {"力道","灵巧","智力","意志","体质","经脉"}
  local fightNames = {"内功","轻功","绝技","拳掌","剑法","刀法","长兵","奇门","射术"}
  local parts = {}
  local attriList = readQword(addDmg + 0x10)
  if attriList and attriList ~= 0 then
    local ac = readInteger(attriList + 0x18) or 0
    local ai = readQword(attriList + 0x10)
    if ai and ai ~= 0 then
      for i = 0, math.min(ac - 1, 5) do
        local v = readFloat(ai + 0x20 + i * 4)
        if v ~= 0 then parts[#parts + 1] = attriNames[i + 1] .. string.format(v < 1 and "%.1f" or "%.0f", v) end
      end
    end
  end
  local fightList = readQword(addDmg + 0x18)
  if fightList and fightList ~= 0 then
    local fc = readInteger(fightList + 0x18) or 0
    local fi = readQword(fightList + 0x10)
    if fi and fi ~= 0 then
      for i = 0, math.min(fc - 1, 8) do
        local v = readFloat(fi + 0x20 + i * 4)
        if v ~= 0 then parts[#parts + 1] = fightNames[i + 1] .. string.format(v < 1 and "%.1f" or "%.0f", v) end
      end
    end
  end
  local hp = readFloat(addDmg + 0x28)
  local pw = readFloat(addDmg + 0x2C)
  local mn = readFloat(addDmg + 0x30)
  if hp ~= 0 then parts[#parts + 1] = "生命" .. string.format(hp < 1 and "%.1f" or "%.0f", hp) end
  if pw ~= 0 then parts[#parts + 1] = "体力" .. string.format(pw < 1 and "%.1f" or "%.0f", pw) end
  if mn ~= 0 then parts[#parts + 1] = "内力" .. string.format(mn < 1 and "%.1f" or "%.0f", mn) end
  return table.concat(parts, ",")
end

-- Load all 996 skills from GameDataController.kungfuSkillDataBase
-- Returns list of skill tables with all fields
function MT.data.loadLiveSkills()
  if MT.data._liveSkills then return MT.data._liveSkills end
  local c = MT.il2cpp.init()
  if not c.gdc then c:ensure("gdc", "GameDataController", 0x20) end
  local gdcInst = readQword(c.gdc.static + c.gdc.instOff)
  if not gdcInst or gdcInst == 0 then return nil end
  local skillDB = readQword(gdcInst + 0x128)
  if not skillDB or skillDB == 0 then return nil end
  local skillItems = readQword(skillDB + 0x10)
  local skillCount = readInteger(skillDB + 0x18)
  if not skillItems or skillCount <= 0 then return nil end

  local typeNames = {"内功","轻功","绝技","拳掌","剑法","刀法","长兵","奇门","射术"}
  local rareNames = {"基础","进阶","上乘","秘传","顶极","绝世"}

  local function readStr(ptr)
    if not ptr or ptr == 0 then return "" end
    local nl = readInteger(ptr + 0x10)
    if not nl or nl <= 0 then return "" end
    return readString(ptr + 0x14, math.min(nl, 200) * 2, true) or ""
  end

  local function readAtkRange(sk)
    local atkList = readQword(sk + 0x70)
    if not atkList or atkList == 0 then return "" end
    local ac = readInteger(atkList + 0x18)
    if not ac or ac <= 0 then return "" end
    local ai = readQword(atkList + 0x10)
    local ar = readQword(ai + 0x20)
    if not ar or ar == 0 then return "" end
    return (readInteger(ar + 0x14) or 0) .. "-" .. (readInteger(ar + 0x18) or 0)
  end

  local function readSpeEffects(sk)
    local speList = readQword(sk + 0xB0)
    if not speList or speList == 0 then return "" end
    local sc = readInteger(speList + 0x18)
    if not sc or sc <= 0 then return "" end
    local si = readQword(speList + 0x10)
    local names = {}
    for j = 0, math.min(sc - 1, 8) do
      local se = readQword(si + 0x20 + j * 8)
      if se and se ~= 0 then
        names[#names + 1] = readStr(readQword(se + 0x10))
      end
    end
    return table.concat(names, ", ")
  end

  local function readPosture(ptr)
    if not ptr or ptr == 0 then return {} end
    local pl = readQword(ptr + 0x10)
    if not pl or pl == 0 then return {} end
    local cnt = readInteger(pl + 0x18)
    local pi = readQword(pl + 0x10)
    local vals = {}
    for i = 0, math.min((cnt or 0) - 1, 5) do
      vals[i + 1] = readFloat(pi + 0x20 + i * 4)
    end
    return vals
  end

  local skills = {}
  for i = 0, skillCount - 1 do
    local sk = readQword(skillItems + 0x20 + i * 8)
    if sk and sk ~= 0 then
      local hide = readBytes(sk + 0xC8, 1)
      if hide ~= 1 then
        local skillType = readInteger(sk + 0x30)
        local rareLv = readInteger(sk + 0x34)
        local manaCost = readFloat(sk + 0x38)
        local baseDmg = readFloat(sk + 0x3C)
        local addDmg = readQword(sk + 0x48)
        skills[#skills + 1] = {
          id = readInteger(sk + 0x14),
          forceID = readInteger(sk + 0x18),
          name = readStr(readQword(sk + 0x20)),
          desc = readStr(readQword(sk + 0x28)),
          type = skillType,
          typeName = typeNames[skillType + 1] or "?",
          rareLv = rareLv,
          rareName = rareNames[rareLv + 1] or tostring(rareLv),
          manaCost = manaCost,
          baseDmg = baseDmg,
          expRatio = readFloat(sk + 0x40),
          atkRange = readAtkRange(sk),
          upgrade = "", upgradeTotal = 0, equip = "", use = "",
          effects = readSpeEffects(sk),
          weapon = readStr(readQword(sk + 0x98)),
          maxUse = readInteger(sk + 0x84),
          atkPosture = readPosture(readQword(sk + 0x88)),
          defPosture = readPosture(readQword(sk + 0x90)),
          dmgBonus = MT.data.readDmgBonus(sk),
        }
        local s = skills[#skills]
        s.upgrade, s.upgradeTotal = MT.data.readSpeDict(readQword(sk + 0x58))
        s.equip = MT.data.readSpeDict(readQword(sk + 0x60))
        s.use = MT.data.readSpeDict(readQword(sk + 0x68), true)
      end
    end
  end
  MT.data._liveSkills = skills
  return skills
end

-- Load force/sect names from WorldData
function MT.data.loadForceNames()
  if MT.data._forceNames then return MT.data._forceNames end
  local wd = MT.game.getWorldData()
  if not wd then return {} end
  local forces = readQword(wd + 0x48)
  if not forces or forces == 0 then return {} end
  local fItems = readQword(forces + 0x10)
  local fCount = readInteger(forces + 0x18)
  local names = {}
  for i = 0, fCount - 1 do
    local fd = readQword(fItems + 0x20 + i * 8)
    if fd and fd ~= 0 then
      local forceID = readInteger(fd + 0x10)
      local np = readQword(fd + 0x18)  -- forceName at +0x18
      if np and np ~= 0 then
        local nl = readInteger(np + 0x10)
        if nl and nl > 0 then
          names[forceID] = readString(np + 0x14, nl * 2, true) or ""
        end
      end
    end
  end
  names[0xFFFFFFFF] = "江湖"
  names[4294967295] = "江湖"  -- same as 0xFFFFFFFF in Lua number
  MT.data._forceNames = names
  return names
end

-- Load full skill database from embedded skills_full.dat
-- Returns list of skill tables matching the live format
-- Parse effect text fields into lookup dicts for dynamic column sorting
function MT.data._parseSkillEffects(skills)
  local function parseEffects(text)
    local dict = {}
    if not text or text == "" then return dict end
    for part in text:gmatch("[^,]+") do
      part = part:match("^%s*(.-)%s*$")
      -- Try "name+val%" or "name+val" first (upgrade/equip/use format)
      local name, val = part:match("^(.-)([+-]%d+%%?)$")
      if not name or not val then
        -- Try "nameVal" without sign (dmgBonus format like "内力0.2")
        name, val = part:match("^(.-)(%d+%.?%d*)$")
      end
      if name and val then
        name = name:match("^%s*(.-)%s*$")
        local numVal = tonumber((val:gsub("%%", ""))) or 0
        if #name > 0 then dict[name] = numVal end
      end
    end
    return dict
  end
  MT.data._allStatNames = {}
  for _, sk in ipairs(skills) do
    sk._upg = parseEffects(sk.upgrade)
    sk._eqp = parseEffects(sk.equip)
    sk._use = parseEffects(sk.use)
    sk._dmg = parseEffects(sk.dmgBonus)
    for n in pairs(sk._upg) do MT.data._allStatNames[n] = true end
    for n in pairs(sk._eqp) do MT.data._allStatNames[n] = true end
    for n in pairs(sk._use) do MT.data._allStatNames[n] = true end
    for n in pairs(sk._dmg) do MT.data._allStatNames["伤害:" .. n] = true end
  end
end

function MT.data.loadSkillsFull()
  if MT.data._skillsFull then return MT.data._skillsFull end
  -- Load pre-compiled Lua table (faster than pipe-delimited parsing)
  local content = nil
  pcall(function()
    local ctPath = getOpenedFile()
    if ctPath and #ctPath > 0 then
      local dir = ctPath:match("(.*[/\\])")
      if dir then
        local f = io.open(dir .. "skills_full.lua", "r")
        if f then content = f:read("*a"); f:close() end
      end
    end
  end)
  if not content then
    local tf = findTableFile("skills_full.lua")
    if tf then
      local tmp = getTempFolder() .. "skills_full.lua"
      tf.saveToFile(tmp)
      local f = io.open(tmp, "r")
      if f then content = f:read("*a"); f:close() end
    end
  end
  if content then
    local fn = load(content)
    if fn then
      local skills = fn()
      -- Parse effect text into dicts (needed for dynamic column sorting)
      MT.data._parseSkillEffects(skills)
      MT.data._skillsFull = skills
      return skills
    end
  end
  -- Fallback: pipe-delimited .dat format
  local raw = MT.data.loadFile("skills_full.dat")
  if not raw or #raw == 0 then return nil end
  local skills = {}
  local function parsePosture(s)
    if not s or s == "" then return {} end
    local vals = {}
    for v in s:gmatch("[^,]+") do vals[#vals+1] = tonumber(v) or 0 end
    return vals
  end
  for _, row in ipairs(raw) do
    skills[#skills+1] = {
      id = tonumber(row[1]) or 0, name = row[2] or "",
      type = tonumber(row[3]) or 0, typeName = row[4] or "",
      rareLv = tonumber(row[5]) or 0, rareName = row[6] or "",
      forceID = tonumber(row[7]) or 4294967295, forceName = row[8] or "江湖",
      manaCost = tonumber(row[9]) or 0, baseDmg = tonumber(row[10]) or 0,
      atkRange = row[11] or "", upgrade = row[12] or "",
      upgradeTotal = tonumber(row[13]) or 0, equip = row[14] or "",
      use = row[15] or "", effects = row[16] or "",
      atkPosture = parsePosture(row[17]), defPosture = parsePosture(row[18]),
      weapon = row[19] or "", maxUse = tonumber(row[20]) or 0,
      dmgBonus = row[21] or "", desc = row[22] or "",
    }
  end
  MT.data._parseSkillEffects(skills)
  MT.data._skillsFull = skills
  return skills
end

-- Load force names from embedded forces.dat
function MT.data.loadForcesDat()
  if MT.data._forcesDat then return MT.data._forcesDat end
  local raw = MT.data.loadFile("forces.dat")
  if not raw or #raw == 0 then return {} end
  local names = {}
  for _, row in ipairs(raw) do
    names[tonumber(row[1]) or 0] = row[2] or ""
  end
  MT.data._forcesDat = names
  return names
end

-- Treasure types (small enough to keep inline)
MT.data.treasureTypes = {
  "乐器 Instrument","棋谱 Chess Manual","字帖 Calligraphy","画本 Painting","香炉 Incense Burner",
  "服饰 Clothing","珠玉 Jewel","酒器 Wine Vessel","史书 History Book","典籍 Classic Text",
}
