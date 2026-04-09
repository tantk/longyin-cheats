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
