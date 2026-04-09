-- src/08_ui.lua — UI helper functions (MT.ui)
-- ============================================================
-- MT.ui -- UI helper functions
-- ============================================================
MT.ui = {}

-- Table of thread-gated controls: each entry = {panel=, btn=, edit=nil}
_threadGatedControls = {}

-- Registry of active flash timers (killed on CT reload / form close)
_flashTimers = {}

--- Wrap a callback in pcall for safe button clicks
function MT.ui.safeClick(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      print("[MT] Error: " .. tostring(err))
    end
    return ok, err
  end
end

--- Update the status bar label
function MT.ui.setStatus(msg, color)
  if _mtStatusLbl then
    if msg then
      -- Strip CE's internal script prefix: [string "local syntaxcheck,memrec=..."]:NNN:
      msg = msg:gsub('%[string "local syntaxcheck,memrec=.-"%]:%d+:%s*', '')
      -- Also strip other CE prefixes
      msg = msg:gsub('%[string ".-"%]:%d+:%s*', '')
    end
    _mtStatusLbl.Caption = msg or ""
    _mtStatusLbl.Font.Color = color or 0x000000
  end
end

--- Check whether the command buffer symbol exists and the hook is enabled
function MT.ui.isConnected()
  local ok, addr = pcall(getAddress, "cmdBuf")
  if not ok or not addr or addr == 0 then return false end
  -- Check the enable flag at offset 0x38
  local flag = readInteger(addr + 0x38)
  return flag and flag ~= 0
end

--- Green flash on success -- reverts after 1.2 s
function MT.ui.flashSuccess(panel, btn, origCaption, msg)
  panel.Color = 0x88FF88   -- light green BGR
  btn.Caption = "Done OK!"
  MT.ui.setStatus(msg, 0x008000)
  local t = createTimer(nil)
  t.Interval = 1200
  _flashTimers[t] = true
  t.OnTimer = function(sender)
    t.Enabled = false; _flashTimers[t] = nil; t.destroy()
    if not _itemAdderForm then return end
    pcall(function() if _itemAdderForm.Visible then panel.Color = 0xE0E0E0; btn.Caption = origCaption end end)
  end
  t.Enabled = true
end

--- Red flash on failure -- reverts after 1.5 s
function MT.ui.flashFail(panel, btn, origCaption, msg)
  panel.Color = 0x4444FF   -- light red in BGR
  btn.Caption = "FAIL"
  MT.ui.setStatus(msg, 0x0000FF)
  local t = createTimer(nil)
  t.Interval = 1500
  _flashTimers[t] = true
  t.OnTimer = function(sender)
    t.Enabled = false; _flashTimers[t] = nil; t.destroy()
    if not _itemAdderForm then return end
    pcall(function() if _itemAdderForm.Visible then panel.Color = 0xE0E0E0; btn.Caption = origCaption end end)
  end
  t.Enabled = true
end

--- Apply numeric-only filter to an Edit control (digits, minus, dot, backspace)
function MT.ui.numericOnly(edt)
  edt.OnKeyPress = function(sender, key)
    if key == "\b" then return key end
    if key == "-" or key == "." or (key >= "0" and key <= "9") then return key end
    return ""
  end
end

--- Create a one-off action button (Panel + Button)
function MT.ui.makeOneOff(parent, x, y, w, h, caption, callback, needsThread)
  local pnl = createPanel(parent)
  pnl.Left = x; pnl.Top = y; pnl.Width = w; pnl.Height = h
  pnl.BevelOuter = 1
  pnl.Color = 0xE0E0E0
  pnl.Caption = ""

  local b = createButton(pnl)
  b.Left = 2; b.Top = 2; b.Width = w - 4; b.Height = h - 4
  b.Caption = caption


  if needsThread then
    b.Enabled = false
    pnl.Color = 0xC0C0C0
    table.insert(_threadGatedControls, {panel = pnl, btn = b})
  end

  b.OnClick = MT.ui.safeClick(function(sender)
    local cap = caption
    local ok, msg = pcall(callback)
    if ok and msg then
      if msg == false then
        MT.ui.flashFail(pnl, b, cap, "Action failed")
      elseif type(msg) == "string" then
        MT.ui.flashSuccess(pnl, b, cap, msg)
      else
        MT.ui.flashSuccess(pnl, b, cap, cap .. " done")
      end
    elseif not ok then
      MT.ui.flashFail(pnl, b, cap, tostring(msg))
    else
      MT.ui.flashSuccess(pnl, b, cap, cap .. " done")
    end
  end)

  return pnl, b
end

--- Create a toggle button (Panel + Button, ON/OFF state)
function MT.ui.makeToggle(parent, x, y, w, h, caption, enableFn, disableFn, needsThread)
  local pnl = createPanel(parent)
  pnl.Left = x; pnl.Top = y; pnl.Width = w; pnl.Height = h
  pnl.BevelOuter = 1
  pnl.Color = 0xE0E0E0
  pnl.Caption = ""

  local b = createButton(pnl)
  b.Left = 2; b.Top = 2; b.Width = w - 4; b.Height = h - 4
  b.Caption = caption


  local isOn = false

  if needsThread then
    b.Enabled = false
    pnl.Color = 0xC0C0C0
    table.insert(_threadGatedControls, {panel = pnl, btn = b})
  end

  b.OnClick = MT.ui.safeClick(function(sender)
    if not isOn then
      local ok, err = pcall(enableFn)
      if ok then
        isOn = true
        pnl.Color = 0x4444FF   -- red-ish BGR = toggle ON
        b.Caption = caption .. " [ON]"
        MT.ui.setStatus(caption .. " enabled", 0x008000)
      else
        MT.ui.flashFail(pnl, b, caption, tostring(err))
      end
    else
      local ok, err = pcall(disableFn)
      if ok then
        isOn = false
        pnl.Color = 0xE0E0E0
        b.Caption = caption
        MT.ui.setStatus(caption .. " disabled", 0x808080)
      else
        MT.ui.flashFail(pnl, b, caption .. " [ON]", tostring(err))
      end
    end
  end)

  return pnl, b
end

--- Create an input field with button (Panel + Edit + Button)
function MT.ui.makeInput(parent, x, y, w, h, caption, editW, default, callback, needsThread)
  local pnl = createPanel(parent)
  pnl.Left = x; pnl.Top = y; pnl.Width = w; pnl.Height = h
  pnl.BevelOuter = 1
  pnl.Color = 0xE0E0E0
  pnl.Caption = ""

  local edt = createEdit(pnl)
  edt.Left = 4; edt.Top = 4; edt.Width = editW; edt.Height = h - 8
  edt.Text = default or ""

  MT.ui.numericOnly(edt)

  local btnW = w - editW - 10
  local b = createButton(pnl)
  b.Left = editW + 6; b.Top = 2; b.Width = btnW; b.Height = h - 4
  b.Caption = caption


  if needsThread then
    b.Enabled = false
    edt.Enabled = false
    pnl.Color = 0xC0C0C0
    table.insert(_threadGatedControls, {panel = pnl, btn = b, edit = edt})
  end

  b.OnClick = MT.ui.safeClick(function(sender)
    local cap = caption
    local val = edt.Text
    local ok, msg = pcall(callback, val)
    if ok and msg then
      if msg == false then
        MT.ui.flashFail(pnl, b, cap, "Action failed")
      elseif type(msg) == "string" then
        MT.ui.flashSuccess(pnl, b, cap, msg)
      else
        MT.ui.flashSuccess(pnl, b, cap, cap .. " done")
      end
    elseif not ok then
      MT.ui.flashFail(pnl, b, cap, tostring(msg))
    else
      MT.ui.flashSuccess(pnl, b, cap, cap .. " done")
    end
  end)

  return pnl, b, edt
end

--- Create a toggle button with an editable multiplier value (Panel + Edit + Button)
function MT.ui.makeToggleInput(parent, x, y, w, h, caption, editW, default, enableFn, disableFn, needsThread)
  local pnl = createPanel(parent)
  pnl.Left = x; pnl.Top = y; pnl.Width = w; pnl.Height = h
  pnl.BevelOuter = 1
  pnl.Color = 0xE0E0E0
  pnl.Caption = ""

  local edt = createEdit(pnl)
  edt.Left = 4; edt.Top = 4; edt.Width = editW; edt.Height = h - 8
  edt.Text = default or ""

  MT.ui.numericOnly(edt)

  local btnW = w - editW - 10
  local b = createButton(pnl)
  b.Left = editW + 6; b.Top = 2; b.Width = btnW; b.Height = h - 4
  b.Caption = caption


  local isOn = false

  if needsThread then
    b.Enabled = false
    edt.Enabled = false
    pnl.Color = 0xC0C0C0
    table.insert(_threadGatedControls, {panel = pnl, btn = b, edit = edt})
  end

  b.OnClick = MT.ui.safeClick(function(sender)
    if not isOn then
      local multiplier = tonumber(edt.Text) or tonumber(default) or 1
      local ok, err = pcall(enableFn, multiplier)
      if ok then
        isOn = true
        pnl.Color = 0x4444FF
        b.Caption = caption .. " [ON]"
        edt.Enabled = false
        MT.ui.setStatus(caption .. " enabled (x" .. tostring(multiplier) .. ")", 0x008000)
      else
        MT.ui.flashFail(pnl, b, caption, tostring(err))
      end
    else
      local ok, err = pcall(disableFn)
      if ok then
        isOn = false
        pnl.Color = 0xE0E0E0
        b.Caption = caption
        edt.Enabled = true
        MT.ui.setStatus(caption .. " disabled", 0x808080)
      else
        MT.ui.flashFail(pnl, b, caption .. " [ON]", tostring(err))
      end
    end
  end)

  return pnl, b, edt
end

-- ============================================================
-- Layout System — auto-positioning, never use manual pixel values
-- Usage:
--   local L = MT.ui.lay(parent, {x=12, y=12})
--   L:section("资源 Resources")
--   L:makeInput("银两 Money", 80, "9999", callback, false)
--   L:makeOneOff("品质全满 MaxRarity", callback, false)
--   L:sectionGap()
--   L:section("属性 Stats")
-- ============================================================

local Layout = {}
Layout.__index = Layout

function MT.ui.lay(parent, opts)
  opts = opts or {}
  local self = setmetatable({}, Layout)
  self.parent = parent
  self.x0 = opts.x or 12       -- left margin
  self.y  = opts.y or 8        -- current Y
  self.btnW = opts.btnW or 388  -- button/panel width
  self.btnH = opts.btnH or 36   -- button height
  self.rowH = opts.rowH or 44   -- row height (btnH + gap)
  self.editW = opts.editW or 80 -- default edit width
  self.sGap = opts.sGap or 16   -- section gap
  self.hdrH = opts.hdrH or 28   -- header line height
  self.hdrSize = opts.hdrSize or 14  -- header font size
  self.controls = {}  -- track created controls
  return self
end

function Layout:section(text)
  local lbl = createLabel(self.parent)
  lbl.Left = self.x0; lbl.Top = self.y
  lbl.Caption = text
  lbl.Font.Size = self.hdrSize
  lbl.Font.Style = fsBold
  self.y = self.y + self.hdrH
  return lbl
end

function Layout:sectionGap()
  self.y = self.y + self.sGap
  return self
end

function Layout:makeOneOff(caption, callback, needsThread)
  local pnl, btn = MT.ui.makeOneOff(self.parent, self.x0, self.y, self.btnW, self.btnH, caption, callback, needsThread)
  self.y = self.y + self.rowH
  return pnl, btn
end

function Layout:makeInput(caption, editW, default, callback, needsThread)
  local pnl, btn, edt = MT.ui.makeInput(self.parent, self.x0, self.y, self.btnW, self.btnH, caption, editW or self.editW, default, callback, needsThread)
  self.y = self.y + self.rowH
  return pnl, btn, edt
end

function Layout:makeToggle(caption, enableFn, disableFn, needsThread)
  local pnl, btn = MT.ui.makeToggle(self.parent, self.x0, self.y, self.btnW, self.btnH, caption, enableFn, disableFn, needsThread)
  self.y = self.y + self.rowH
  return pnl, btn
end

function Layout:makeToggleInput(caption, editW, default, enableFn, disableFn, needsThread)
  local pnl, btn, edt = MT.ui.makeToggleInput(self.parent, self.x0, self.y, self.btnW, self.btnH, caption, editW or self.editW, default, enableFn, disableFn, needsThread)
  self.y = self.y + self.rowH
  return pnl, btn, edt
end

-- Inline row builder: auto-positions controls left-to-right
-- Usage:
--   local r = L:inlineRow()
--   local lbl = r:label("等级:")
--   local edt = r:edit("0", 60)
--   r:gap(20)
--   local lbl2 = r:label("性别:")
--   local cmb = r:combo({"随机","男","女"}, 150)
--   L:advanceRow()
local InlineRow = {}
InlineRow.__index = InlineRow

function Layout:inlineRow()
  local row = setmetatable({}, InlineRow)
  row.parent = self.parent
  row.x0 = self.x0
  row.x = self.x0
  row.y = self.y
  row.h = self.btnH
  row.spacing = 14
  row.labelPad = 4  -- vertical offset for label centering
  return row
end

function Layout:advanceRow(multiplier)
  self.y = self.y + self.rowH * (multiplier or 1)
  return self
end

function Layout:skip(px)
  self.y = self.y + px
  return self
end

function InlineRow:label(text)
  local lbl = createLabel(self.parent)
  lbl.Left = self.x; lbl.Top = self.y + self.labelPad
  lbl.Caption = text
  -- Label to its control: no extra gap (CE auto-width includes padding)
  self.x = self.x + lbl.Width
  return lbl
end

function InlineRow:edit(default, width)
  width = width or 60
  local edt = createEdit(self.parent)
  edt.Left = self.x; edt.Top = self.y
  edt.Width = width; edt.Height = self.h - 4
  edt.Text = default or ""
  MT.ui.numericOnly(edt)
  self.x = self.x + width + self.spacing
  return edt
end

function InlineRow:combo(items, width)
  width = width or 120
  local cmb = createComboBox(self.parent)
  cmb.Left = self.x; cmb.Top = self.y
  cmb.Width = width; cmb.Height = self.h - 4
  cmb.Style = csDropDownList
  for _, item in ipairs(items) do cmb.Items.add(item) end
  cmb.ItemIndex = 0
  self.x = self.x + width + self.spacing
  return cmb
end

-- Check if a control would clip its parent and cap the width
function InlineRow:_capWidth(x, width)
  local parentW = 0
  pcall(function() parentW = self.parent.ClientWidth or self.parent.Width or 0 end)
  if parentW > 0 and (x + width) > parentW then
    width = math.max(40, parentW - x - 4)
  end
  return width
end

function InlineRow:button(caption, width, callback)
  width = self:_capWidth(self.x, width or 120)
  local pnl = createPanel(self.parent)
  pnl.Left = self.x; pnl.Top = self.y; pnl.Width = width; pnl.Height = self.h
  pnl.BevelOuter = 1; pnl.Color = 0xC0C0C0; pnl.Caption = ""
  local btn = createButton(pnl)
  btn.Left = 1; btn.Top = 1; btn.Width = width - 2; btn.Height = self.h - 2
  btn.Caption = caption; btn.Enabled = false
  table.insert(_threadGatedControls, {panel = pnl, btn = btn})
  if callback then
    btn.OnClick = MT.ui.safeClick(function()
      local cap = caption
      local ok, msg = pcall(callback)
      if ok and msg then MT.ui.flashSuccess(pnl, btn, cap, tostring(msg))
      elseif not ok then MT.ui.flashFail(pnl, btn, cap, tostring(msg)) end
    end)
  end
  self.x = self.x + width + self.spacing
  return pnl, btn
end

function InlineRow:gap(px)
  self.x = self.x + (px or 20)
  return self
end

-- Snap to absolute column position (relative to row origin x0)
-- Use this to align controls vertically across rows
function InlineRow:col(absX)
  self.x = self.x0 + absX
  return self
end

function InlineRow:hintLabel(text)
  local lbl = createLabel(self.parent)
  lbl.Left = self.x; lbl.Top = self.y + self.labelPad
  lbl.Caption = text
  lbl.Font.Size = lbl.Font.Size - 3
  lbl.Font.Color = 0x808080
  self.x = self.x + lbl.Width + 4
  return lbl
end

-- ============================================================
-- Multi-Column Layout
-- Usage:
--   local mc = MT.ui.columns(parent, 2)  -- 2 equal columns
--   local mc = MT.ui.columns(parent, {0.4, 0.6})  -- 40%/60% split
--   local L1 = mc:get(1)  -- Layout object for column 1
--   local L2 = mc:get(2)  -- Layout object for column 2
-- ============================================================

function MT.ui.columns(parent, colSpec, opts)
  opts = opts or {}
  local margin = opts.margin or 12
  local colGap = opts.gap or 20
  local totalW = opts.width or 1240  -- usable width (form inner)
  local btnH = opts.btnH or 36
  local rowH = opts.rowH or 44
  local hdrSize = opts.hdrSize or 14
  local startY = opts.y or 12

  -- Parse column spec: number = equal columns, table = proportions
  local proportions = {}
  if type(colSpec) == "number" then
    for i = 1, colSpec do proportions[i] = 1 / colSpec end
  elseif type(colSpec) == "table" then
    proportions = colSpec
  else
    proportions = {1}
  end

  local numCols = #proportions
  local availW = totalW - margin * 2 - colGap * (numCols - 1)
  local cols = {}
  local x = margin

  for i, prop in ipairs(proportions) do
    local colW = math.floor(availW * prop)
    cols[i] = MT.ui.lay(parent, {
      x = x, y = startY,
      btnW = colW - 12,
      btnH = btnH, rowH = rowH,
      hdrSize = hdrSize,
    })
    cols[i]._colW = colW
    x = x + colW + colGap
  end

  local mc = {cols = cols}
  function mc:get(idx) return self.cols[idx] end
  return mc
end

-- ============================================================
-- Grid Layout — define column widths once, all rows auto-align
-- Usage:
--   local g = L:grid({160, 50, 50, 50, 50, 120})
--   g:row():combo(items):label("等级:"):edit("5"):label("品质:"):edit("5"):button("Add", cb)
--   g:row():combo(items2):label("等级:"):edit("5"):label("品质:"):edit("5"):button("Gen", cb)
--   -- All columns perfectly aligned across rows
-- ============================================================

local Grid = {}
Grid.__index = Grid

function Layout:grid(widths, opts)
  opts = opts or {}
  local g = setmetatable({}, Grid)
  g.parent = self.parent
  g.layout = self  -- parent Layout for Y tracking
  g.x0 = self.x0
  g.widths = widths
  g.gap = opts.gap or 6  -- gap between columns
  g.btnH = self.btnH or 36
  g.rowH = self.rowH or 44
  -- Pre-calculate column X positions
  g.colX = {}
  local x = 0
  for i, w in ipairs(widths) do
    g.colX[i] = x
    x = x + w + g.gap
  end
  return g
end

function Grid:row()
  local row = setmetatable({}, {__index = Grid._Row})
  row.grid = self
  row.parent = self.parent
  row.y = self.layout.y
  row.x0 = self.grid and self.x0 or self.x0
  row.colIdx = 1
  row.btnH = self.btnH
  return row
end

function Grid:advanceRow()
  self.layout.y = self.layout.y + self.rowH
  return self
end

-- Grid Row — each method places control in next column and advances
Grid._Row = {}

function Grid._Row:_cellX()
  local idx = self.colIdx
  local x = self.grid.x0 + (self.grid.colX[idx] or 0)
  local w = self.grid.widths[idx] or 80
  self.colIdx = idx + 1
  return x, w
end

function Grid._Row:combo(items, overrideW)
  local x, w = self:_cellX()
  w = overrideW or w
  local cmb = createComboBox(self.parent)
  cmb.Left = x; cmb.Top = self.y; cmb.Width = w; cmb.Height = self.btnH - 4
  cmb.Style = csDropDownList
  if type(items) == "table" then
    for _, item in ipairs(items) do cmb.Items.add(item) end
    if cmb.Items.Count > 0 then cmb.ItemIndex = 0 end
  end
  return self, cmb
end

function Grid._Row:label(text)
  local x, w = self:_cellX()
  local lbl = createLabel(self.parent)
  lbl.Left = x; lbl.Top = self.y + 4
  lbl.Caption = text
  return self, lbl
end

function Grid._Row:edit(default, overrideW)
  local x, w = self:_cellX()
  w = overrideW or w
  local edt = createEdit(self.parent)
  edt.Left = x; edt.Top = self.y; edt.Width = w; edt.Height = self.btnH - 4
  edt.Text = default or ""
  MT.ui.numericOnly(edt)
  return self, edt
end

function Grid._Row:button(caption, overrideW, callback)
  local x, w = self:_cellX()
  w = overrideW or w
  -- Cap to parent width
  local parentW = 0
  pcall(function() parentW = self.parent.ClientWidth or self.parent.Width or 0 end)
  if parentW > 0 and (x + w) > parentW then w = math.max(40, parentW - x - 4) end
  local pnl = createPanel(self.parent)
  pnl.Left = x; pnl.Top = self.y; pnl.Width = w; pnl.Height = self.btnH
  pnl.BevelOuter = 1; pnl.Color = 0xC0C0C0; pnl.Caption = ""
  local btn = createButton(pnl)
  btn.Left = 1; btn.Top = 1; btn.Width = w - 2; btn.Height = self.btnH - 2
  btn.Caption = caption; btn.Enabled = false
  table.insert(_threadGatedControls, {panel = pnl, btn = btn})
  if callback then
    btn.OnClick = MT.ui.safeClick(function()
      local cap = caption
      local ok, msg = pcall(callback)
      if ok and msg then MT.ui.flashSuccess(pnl, btn, cap, tostring(msg))
      elseif not ok then MT.ui.flashFail(pnl, btn, cap, tostring(msg)) end
    end)
  end
  return self, pnl, btn
end

function Grid._Row:skip(n)
  self.colIdx = self.colIdx + (n or 1)
  return self
end

--- Estimate text width in pixels for a given font size
--- CJK chars ~fontSize*1.3, Latin chars ~fontSize*0.7
function MT.ui.textWidth(text, fontSize)
  fontSize = fontSize or 13
  local w = 0
  for i = 1, #text do
    local b = text:byte(i)
    if b > 127 then
      -- UTF-8 multi-byte: count only the leading byte
      if b >= 0xC0 then w = w + fontSize * 1.3 end
    else
      w = w + fontSize * 0.7
    end
  end
  return math.floor(w + 16)  -- +16 padding for column header margins
end

--- Add columns to a ListView with auto-calculated widths from header text
--- cols = { {"Header", minWidth}, ... }  — minWidth is minimum, auto expands if text is wider
function MT.ui.autoColumns(lv, cols, fontSize)
  fontSize = fontSize or 13
  for _, c in ipairs(cols) do
    local col = lv.Columns.add()
    col.Caption = c[1]
    local autoW = MT.ui.textWidth(c[1], fontSize)
    col.Width = math.max(c[2] or 0, autoW)
  end
end

--- Enable all thread-gated controls (called after successful connect)
function MT.ui.enableThreadControls()
  for _, entry in ipairs(_threadGatedControls) do
    pcall(function()
      if entry.btn then entry.btn.Enabled = true end
      if entry.edit then entry.edit.Enabled = true end
      if entry.panel then entry.panel.Color = 0xE0E0E0 end
    end)
  end
end
