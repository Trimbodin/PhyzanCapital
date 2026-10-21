-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital UI: full-screen window (/capital) with tabs
--   Search/Browse, Buy (Trade.lua), Price Lookup (Lookup.lua), Market, Crafting List (ShoppingList.lua),
--   Professions (ProfessionsTab.lua), Settings. (1.4.0: no Sell/Post and no Vendor Swaps tab.)
-- Close with the X button or Escape. Trading tabs need the auction house open; analysis tabs work anywhere.
local _, ns = ...
local UI = { tab = "search", panels = {}, builders = {} }
ns.UI = UI

local ROW_H = 18 -- logical (1x) row height; real height = UI.S(ROW_H)
UI.ROW_H = ROW_H
UI.TAB_ORDER = {
  -- key, label, short label (used when the full labels do not fit on one line at large text sizes)
  { "search", "Search / Browse", "Search" }, { "buy", "Buy" }, { "market", "Market" },
  { "shopping", "Crafting List", "List" }, { "crafts", "Professions", "Profs" },
  { "settings", "Settings" },
}

---------------------------------------------------------------------------
-- Text scale. Every font we use is our own font object (CreateFont, copied from the Blizzard font with the size
-- multiplied by the scale, outline flags kept). Geometry is multiplied by the same scale with UI.S().
-- We never SetScale() the window: it stays exactly full-screen and the layout reflows to the space available.
---------------------------------------------------------------------------
UI.MIN_SCALE, UI.MAX_SCALE, UI.SCALE_STEP = 1.0, 3.0, 0.25
UI.scale = 1.0
function UI.ClampScale(v)
  v = tonumber(v) or 1.0
  v = math.floor(v / UI.SCALE_STEP + 0.5) * UI.SCALE_STEP
  return math.max(UI.MIN_SCALE, math.min(UI.MAX_SCALE, v))
end
local function S(v) return math.floor((v or 0) * UI.scale + 0.5) end
UI.S = S

function UI.ScreenW()
  local w = UIParent and UIParent.GetWidth and UIParent:GetWidth()
  return (type(w) == "number" and w > 0) and w or 1365
end
function UI.ScreenH()
  local h = UIParent and UIParent.GetHeight and UIParent:GetHeight()
  return (type(h) == "number" and h > 0) and h or 768
end
UI.MARGIN = 16 -- logical
function UI.ContentW() return UI.ScreenW() - 2 * S(UI.MARGIN) end

UI.fonts = {}
local FALLBACK_SIZE = { GameFontNormalHuge = 20, GameFontNormalLarge = 16, GameFontHighlightLarge = 16,
  GameFontNormalSmall = 10, GameFontHighlightSmall = 10, GameFontDisableSmall = 10, ChatFontNormal = 14 }
local function applyFont(f)
  local size = math.floor(f.baseSize * UI.scale + 0.5)
  if not (f.baseFile and pcall(f.SetFont, f, f.baseFile, size, f.baseFlags or "")) then f.failed = true end
  f.size = size
end
-- Our font object for a Blizzard font name (e.g. "GameFontHighlightSmall"); falls back to the name itself.
function UI.Font(base)
  base = base or "GameFontHighlight"
  local f = UI.fonts[base]
  if not f then
    local src = _G[base]
    if type(CreateFont) ~= "function" or type(src) ~= "table" or type(src.GetFont) ~= "function" then return base end
    local ok, obj = pcall(CreateFont, "PhyzanCapitalFont_" .. base)
    if not ok or type(obj) ~= "table" then return base end
    f = obj
    if f.CopyFontObject then pcall(f.CopyFontObject, f, src) end -- colour, shadow, justification
    local okF, file, size, flags = pcall(src.GetFont, src)
    f.baseFile = okF and file or nil
    f.baseSize = (okF and tonumber(size)) or FALLBACK_SIZE[base] or 12
    f.baseFlags = okF and flags or ""
    UI.fonts[base] = f
    applyFont(f)
  end
  return f
end
function UI.FontSize(base)
  local f = UI.Font(base)
  if type(f) == "table" and f.size then return f.size end
  return math.floor((FALLBACK_SIZE[base] or 12) * UI.scale + 0.5)
end
function UI.LineH(base) return math.ceil(UI.FontSize(base) * 1.3) end
-- Height a font string needs when wrapped to width w (uses GetStringHeight after SetWidth when available).
function UI.WrapHeight(fs, w, base)
  fs:SetWidth(w)
  local h = fs.GetStringHeight and fs:GetStringHeight()
  if type(h) ~= "number" or h <= 0 then
    local _, nl = tostring(fs:GetText() or ""):gsub("\n", "")
    local sw = fs.GetStringWidth and fs:GetStringWidth() or 0
    h = (nl + 1 + math.ceil((sw or 0) / math.max(1, w))) * UI.LineH(base)
  end
  return math.ceil(h + 2)
end
function UI:ApplyFonts()
  for _, f in pairs(self.fonts) do applyFont(f) end
end

---------------------------------------------------------------------------
-- Widget helpers (sizes are logical 1x values; scaled here)
---------------------------------------------------------------------------
function UI.Color(tex, r, g, b, a)
  if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(r, g, b, a) end
end

function UI.Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(UI.Font(font or "GameFontHighlight"))
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

-- One-line note at the bottom of a tab: cut with "..." when too long, full text in a tooltip on hover.
function UI.Note(parent, text, width)
  local h = CreateFrame("Frame", nil, parent)
  h:SetSize(width, UI.LineH("GameFontDisableSmall"))
  local fs = UI.Label(h, text, "GameFontDisableSmall")
  fs:SetPoint("LEFT", 0, 0)
  fs:SetWidth(width)
  fs:SetHeight(UI.LineH("GameFontDisableSmall"))
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  h.text = fs
  h:EnableMouse(true)
  h:SetScript("OnEnter", function(self)
    if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(fs:GetText() or "", 1, 1, 1, true); GameTooltip:Show() end
  end)
  h:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  function h:SetText(t) fs:SetText(t) end
  function h:GetText() return fs:GetText() end
  return h
end

-- Width a button needs for its text (never truncate a button label).
function UI.FitButton(b, minW, pad)
  local fs = b.GetFontString and b:GetFontString()
  local tw = fs and fs.GetStringWidth and fs:GetStringWidth()
  local w = minW or (b.GetWidth and b:GetWidth()) or 0
  pad = pad or S(20)
  if type(tw) == "number" and tw + pad > w then w = math.ceil(tw + pad) end
  b:SetWidth(w)
  return w
end

function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  if b.SetNormalFontObject then
    b:SetNormalFontObject(UI.Font("GameFontNormal"))
    b:SetHighlightFontObject(UI.Font("GameFontHighlight"))
    if b.SetDisabledFontObject then b:SetDisabledFontObject(UI.Font("GameFontDisable")) end
  end
  b:SetText(text)
  b:SetSize(S(w or 100), math.max(h or 22, UI.LineH("GameFontNormal") + S(5)))
  UI.FitButton(b, S(w or 100))
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.EditBox(parent, w, numeric)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  if e.SetFontObject then e:SetFontObject(UI.Font("ChatFontNormal")) end
  e:SetSize(S(w or 80), math.max(S(20), UI.LineH("ChatFontNormal") + S(4)))
  e:SetAutoFocus(false)
  if numeric and e.SetNumeric then e:SetNumeric(true) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

function UI.CheckBox(parent, text, onClick)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  local box = math.max(24, UI.LineH("GameFontHighlight") + S(2))
  c:SetSize(box, box)
  local l = UI.Label(parent, text)
  l:SetPoint("LEFT", c, "RIGHT", S(2), 0)
  c.label = l
  if onClick then c:SetScript("OnClick", onClick) end
  return c
end

-- Size of a widget for layout (a checkbox includes its label).
local function fsWidth(fs) -- a font string's laid-out width: its explicit width, else its text width
  local w = fs.GetWidth and fs:GetWidth()
  if type(w) ~= "number" or w <= 0 then w = fs.GetStringWidth and fs:GetStringWidth() or 0 end
  return w or 0
end
function UI.WidthOf(w)
  local width
  if w.GetStringWidth and not w.GetFontString then width = fsWidth(w) else width = (w.GetWidth and w:GetWidth()) or 0 end
  if w.label and w.label.GetStringWidth then width = width + S(2) + fsWidth(w.label) end
  return math.ceil(width)
end
function UI.HeightOf(w)
  local h = (w.GetHeight and w:GetHeight()) or 0
  if w.GetStringWidth and not w.GetFontString and (not h or h <= 0) then h = UI.LineH() end
  return math.ceil(h or 0)
end

-- Flow layout: places widgets left to right from (x, y) (real pixels, y negative = down) inside parent,
-- wrapping to a new line when the next one would pass maxW. Lines are vertically centred.
-- Returns the y just below the last line. Hidden widgets still take their place (stable layout).
function UI.Flow(parent, items, x, y, maxW, gap)
  gap = gap or S(8)
  local lines, line, cx = {}, {}, 0
  for _, it in ipairs(items) do
    local w = UI.WidthOf(it)
    if #line > 0 and cx + w > maxW then lines[#lines + 1] = line; line, cx = {}, 0 end
    line[#line + 1] = { it = it, x = cx, w = w, h = UI.HeightOf(it) }
    cx = cx + w + gap
  end
  if #line > 0 then lines[#lines + 1] = line end
  for _, ln in ipairs(lines) do
    local lh = 0
    for _, e in ipairs(ln) do if e.h > lh then lh = e.h end end
    for _, e in ipairs(ln) do
      e.it:ClearAllPoints()
      e.it:SetPoint("TOPLEFT", parent, "TOPLEFT", x + e.x, y - math.floor((lh - e.h) / 2))
    end
    y = y - lh - gap
  end
  return y
end

-- Vertical stack of blocks, re-run whenever text changes: { flow = {widgets} } | { text = fontString, font = base }
-- | { frame = f, h = height }. Wrapped text gets its measured height, so nothing below overlaps it.
function UI.Stack(parent, blocks, x, y, W, gap)
  gap = gap or S(8)
  for _, b in ipairs(blocks) do
    if b.flow then
      y = UI.Flow(parent, b.flow, x, y, W, gap)
    elseif b.text then
      local fs = b.text
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
      local h = (b.nowrap and UI.LineH(b.font)) or UI.WrapHeight(fs, W, b.font)
      if b.nowrap then fs:SetWidth(W); if fs.SetWordWrap then fs:SetWordWrap(false) end end
      fs:SetHeight(h)
      y = y - h - gap
    elseif b.frame then
      b.frame:ClearAllPoints()
      b.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
      b.frame:SetWidth(b.w or W)
      if b.h then b.frame:SetHeight(b.h) end
      y = y - (b.h or b.frame:GetHeight() or 0) - gap
    end
  end
  return y
end

-- Vertical scroll area for long forms: returns the scroll child; set child height with child:SetHeight().
function UI.ScrollArea(parent, width)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetAllPoints(parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(math.max(1, width or UI.PanelW()), 1)
  sf:SetScrollChild(child)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
    local v = (self.GetVerticalScroll and self:GetVerticalScroll() or 0) - delta * S(ROW_H) * 3
    self:SetVerticalScroll(math.max(0, math.min(max, v)))
  end)
  child.scroll = sf
  return child
end

-- Scrollable, selectable, optionally sortable list. cols = { {title, width}, ... } (width is a relative weight:
-- columns flex to fill the list's width; long text is cut with "..." and shown in full in the hover tooltip).
-- Rows are arrays of cell strings; row.data carries payload, row.sort[c] an optional sort key for column c.
-- A column may give a short title as a 3rd entry ({ "Available on AH", 110, "On AH" }), used when the full one does
-- not fit the column (large text); the full title is then in the header's tooltip.
-- opts: { sortable, onEnter(row, owner, hasItem), onRightClick, action = {text, width, tooltip, onClick}, width }
function UI.List(parent, cols, onSelect, maxRows, opts)
  opts = opts or {}
  local L = { cols = cols, data = {}, offset = 0, selected = nil, onSelect = onSelect, buttons = {}, rowH = 0 }
  local f = CreateFrame("Frame", nil, parent)
  L.frame = f
  f.pcList = L
  maxRows = maxRows or 60
  local cellFont = "GameFontHighlightSmall"
  -- row height follows the font (1x: 18 like before); a row with an action button fits the button's text
  local actions = opts.actions or (opts.action and { opts.action }) or {}
  local rowH = math.max(ROW_H, UI.LineH(cellFont) + S(3), #actions > 0 and (UI.LineH("GameFontNormal") + S(2)) or 0)
  L.rowH = rowH
  L.header = {}
  for c, col in ipairs(cols) do
    local hb = CreateFrame("Button", nil, f)
    hb:SetHeight(rowH)
    local h = UI.Label(hb, col[1], "GameFontNormalSmall")
    h:SetPoint("LEFT", 0, 0)
    if h.SetWordWrap then h:SetWordWrap(false) end
    hb.label = h
    hb:SetScript("OnEnter", function(self)
      if GameTooltip and ((h.IsTruncated and h:IsTruncated()) or (col[3] and h.GetText and h:GetText() ~= col[1])) then
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(col[1], 1, 0.82, 0); GameTooltip:Show()
      end
    end)
    hb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if opts.sortable then
      hb:SetScript("OnClick", function()
        if L.sortCol == c then L.sortDesc = not L.sortDesc else L.sortCol, L.sortDesc = c, true end
        ns.CountUsage("sort:" .. tostring(col[1]))
        L:Sort()
        L:Render()
      end)
    end
    L.header[c] = hb
  end
  for r = 1, maxRows do
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(rowH)
    b:SetPoint("TOPLEFT", 0, -r * rowH)
    b:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    UI.Color(hl, 1, 1, 1, 0.08)
    local sel = b:CreateTexture(nil, "BACKGROUND")
    sel:SetAllPoints()
    UI.Color(sel, 0.2, 0.6, 1, 0.25)
    sel:Hide()
    b.sel = sel
    local tint = b:CreateTexture(nil, "BACKGROUND") -- optional per-row colour (row.tint = {r, g, b, a})
    tint:SetAllPoints()
    tint:Hide()
    b.tint = tint
    b.cells = {}
    -- small buttons in the last columns of every row (e.g. "Map", "+List"), one column each, in order
    b.actions = {}
    for ai, act in ipairs(actions) do
      local ab = UI.Button(b, act.text or "?", act.width or 46, ROW_H - 2)
      ab:SetHeight(rowH - S(2))
      ab:SetScript("OnClick", function(self)
        local row = L.data[r + L.offset]
        if row then L.selected = r + L.offset; L:Render(); act.onClick(r + L.offset, row, self) end
      end)
      if act.tooltip then
        ab:SetScript("OnEnter", function(self)
          if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine(act.tooltip); GameTooltip:Show() end
        end)
        ab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
      end
      b.actions[ai] = ab
    end
    b.action = b.actions[1]
    for c = 1, #cols do
      local fs = UI.Label(b, "", cellFont)
      fs:SetHeight(rowH)
      if fs.SetWordWrap then fs:SetWordWrap(false) end -- long text ends in "..."
      b.cells[c] = fs
    end
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", function(self, button)
      local idx = r + L.offset
      if L.data[idx] then
        L.selected = idx
        L:Render()
        if button == "RightButton" and opts.onRightClick then opts.onRightClick(idx, L.data[idx], self); return end
        if L.onSelect then L.onSelect(idx, L.data[idx], self, button) end
      end
    end)
    -- Hover: item tooltip for rows with an itemID (GameTooltip:SetItemByID), plus any extra lines from opts.onEnter;
    -- other rows show the full text of cells that were cut off.
    b:SetScript("OnEnter", function(self)
      local row = L.data[r + L.offset]
      if not row or not GameTooltip then return end
      local hasItem = false
      if row.itemID then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        ns.Items:SetTooltip(GameTooltip, row.itemID)
        hasItem = true
      end
      if opts.onEnter then opts.onEnter(row, self, hasItem) end
      -- full text of every cell that was cut off ("...") at this text size
      local cut = {}
      for c, fs in ipairs(self.cells) do
        if not (hasItem and c == (row.itemCol or 1)) and fs.IsTruncated and fs:IsTruncated() and (row[c] or "") ~= "" then
          cut[#cut + 1] = { L.cols[c][1], row[c] }
        end
      end
      if #cut > 0 then
        if not hasItem and not opts.onEnter then GameTooltip:SetOwner(self, "ANCHOR_CURSOR") end
        GameTooltip:AddLine(" ")
        for _, t in ipairs(cut) do GameTooltip:AddDoubleLine(t[1], t[2], 1, 0.82, 0, 1, 1, 1) end
      end
      if hasItem or opts.onEnter or #cut > 0 then GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    L.buttons[r] = b
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    L.offset = math.max(0, math.min(#L.data - L:Visible(), L.offset - delta * 3))
    L:Render()
  end)
  L.footer = UI.Label(f, "", "GameFontDisableSmall")
  L.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -S(4), S(2))

  -- Column widths: weights scaled to fill the list width (frame width, or opts.width, or the content width).
  function L:Width()
    local w = self.frame.GetWidth and self.frame:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = opts.width or UI.ContentW() end
    return w
  end
  function L:Layout()
    local w = self:Width()
    if self.laidOut == w then return end
    self.laidOut = w
    self.footer:SetWidth(math.max(1, w - S(8)))
    if self.footer.SetWordWrap then self.footer:SetWordWrap(false) end
    if self.footer.SetJustifyH then self.footer:SetJustifyH("RIGHT") end
    local n = #self.cols
    -- action columns (last #actions columns) are exactly as wide as their buttons; the rest flex
    local fixed, fixedSum = {}, 0
    local b1 = self.buttons[1]
    for ai, ab in ipairs(b1 and b1.actions or {}) do
      local c = n - #b1.actions + ai
      fixed[c] = ab:GetWidth() + S(8)
      fixedSum = fixedSum + fixed[c]
    end
    local total = 0
    for c, col in ipairs(self.cols) do if not fixed[c] then total = total + col[2] end end
    local avail = w - S(8) - fixedSum
    self.colW = {}
    local x = S(4)
    for c, col in ipairs(self.cols) do
      local cw = fixed[c] or math.floor(avail * col[2] / total)
      self.colW[c] = cw
      local hb = self.header[c]
      hb:ClearAllPoints()
      hb:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, 0)
      hb:SetWidth(math.max(1, cw - S(4)))
      hb.label:SetWidth(math.max(1, cw - S(4)))
      for _, b in ipairs(self.buttons) do
        local fs = b.cells[c]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", b, "LEFT", x, 0)
        fs:SetWidth(math.max(1, cw - S(6)))
        local ab = fixed[c] and b.actions[c - (n - #b.actions)]
        if ab then ab:ClearAllPoints(); ab:SetPoint("LEFT", b, "LEFT", x + S(2), 0) end
      end
      x = x + cw
    end
    self.usedW = x
  end
  function L:Visible()
    local h = (self.frame.GetHeight and self.frame:GetHeight()) or 0
    if h <= 0 then return math.min(3, maxRows) end -- not laid out yet
    -- header row on top, footer line ("1-20 of 85") at the bottom
    local n = math.max(0, math.floor((h - UI.LineH("GameFontDisableSmall") - S(2)) / self.rowH) - 1)
    return math.min(n, maxRows)
  end
  -- frame height that shows exactly n rows
  function L:HeightFor(n) return (n + 1) * self.rowH + UI.LineH("GameFontDisableSmall") + S(2) + 1 end
  function L:Sort()
    local c = self.sortCol
    if not c then return end
    local desc = self.sortDesc
    local function key(row)
      local k = row.sort and row.sort[c]
      if k == nil then k = row[c] or "" end
      return k
    end
    table.sort(self.data, function(a, b)
      local ka, kb = key(a), key(b)
      if type(ka) ~= type(kb) then ka, kb = tostring(ka), tostring(kb) end
      if ka == kb then return false end
      if desc then return ka > kb end
      return ka < kb
    end)
  end
  function L:SetData(data, keepSelection)
    self.data = data or {}
    if not keepSelection then self.selected = nil end
    self:Sort()
    self.offset = math.max(0, math.min(self.offset, #self.data - self:Visible()))
    self:Render()
  end
  function L:Render()
    self:Layout()
    local vis = self:Visible()
    for c, hb in ipairs(self.header) do
      local arrow = (self.sortCol == c) and (self.sortDesc and " v" or " ^") or ""
      local t = self.cols[c][1] .. arrow
      hb.label:SetText(t)
      local short, cw = self.cols[c][3], self.colW and self.colW[c]
      if short and cw and hb.label.GetStringWidth and hb.label:GetStringWidth() > cw - S(4) then
        hb.label:SetText(short .. arrow)
      end
    end
    for r, b in ipairs(self.buttons) do
      local idx = r + self.offset
      local row = (r <= vis) and self.data[idx]
      if row then
        for c = 1, #self.cols do b.cells[c]:SetText(row[c] or "") end
        -- item column: coloured by quality with icon, resolved at render time so names that arrive later show up
        if row.itemID then b.cells[row.itemCol or 1]:SetText(ns.ItemLabel(row.itemID)) end
        if self.selected == idx then b.sel:Show() else b.sel:Hide() end
        if row.tint then UI.Color(b.tint, unpack(row.tint)); b.tint:Show() else b.tint:Hide() end
        b:Show()
      else
        b:Hide()
      end
    end
    if #self.data > vis then
      local ft = string.format("%d-%d of %d", self.offset + 1, math.min(#self.data, self.offset + vis), #self.data)
      self.footer:SetText(ft .. " (mouse wheel)")
      if self.footer.GetStringWidth and (self.footer:GetStringWidth() or 0) > self:Width() - S(8) then self.footer:SetText(ft) end
    else
      self.footer:SetText(#self.data == 0 and "(nothing to show)" or "")
    end
  end
  return L
end

---------------------------------------------------------------------------
-- Main frame
---------------------------------------------------------------------------
function UI:RegisterTab(key, build, refresh)
  self.builders[key] = { build = build, refresh = refresh }
end

local function makeFrame()
  UI.scale = UI.ClampScale(ns.db and ns.db.settings.textScale)
  UI:ApplyFonts()
  local tmpl = BackdropTemplateMixin and "BackdropTemplate" or nil
  local f = CreateFrame("Frame", "PhyzanCapitalFrame", UIParent, tmpl)
  f:SetAllPoints(UIParent)
  f:SetFrameStrata("HIGH") -- below DIALOG so confirmation popups stay on top
  f:SetToplevel(true)
  f:EnableMouse(true)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.96)
    f:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    UI.Color(bg, 0.04, 0.04, 0.06, 0.96)
  end
  if UISpecialFrames then
    local listed = false
    for _, n in ipairs(UISpecialFrames) do if n == "PhyzanCapitalFrame" then listed = true end end
    if not listed then table.insert(UISpecialFrames, "PhyzanCapitalFrame") end -- Escape closes
  end
  local M, W = math.min(S(UI.MARGIN), 24), UI.ScreenW()
  local innerW = W - 2 * M
  UI.margin = M

  -- line 1: title ......................... [Scan Auction House] [X]
  local close = CreateFrame("Button", "PhyzanCapitalCloseButton", f, "UIPanelCloseButton")
  local cs = math.max(S(24), UI.LineH("GameFontNormalLarge"))
  close:SetSize(cs, cs)
  close:SetPoint("TOPRIGHT", -S(4), -S(4))
  close:SetScript("OnClick", function() f:Hide() end)
  local scan = UI.Button(f, "Scan next page (99/99)", 120, 24) -- sized for the longest scanner label
  scan:SetText("Scan Auction House")
  scan:SetPoint("TOPRIGHT", close, "TOPLEFT", -S(8), -math.floor((cs - UI.HeightOf(scan)) / 2))
  scan:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  scan:SetScript("OnClick", function(_, button)
    if not ns.ahOpen then ns.Print("open the auction house to scan."); return end
    ns.Scanner:OnClick(button)
  end)
  f.scan = scan
  if ns.Scanner then ns.Scanner:AddButton(scan) end
  -- Feedback: always visible, left of the scan button
  local fb = UI.Button(f, "Feedback", 80, 24, function() UI:ShowFeedback("button") end)
  UI.FitButton(fb, S(60))
  fb:SetPoint("RIGHT", scan, "LEFT", -S(8), 0)
  if fb.SetScript then
    fb:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine("Suggestions and bug reports")
      GameTooltip:AddLine(ns.FEEDBACK_EMAIL, 1, 1, 1)
      GameTooltip:Show()
    end)
    fb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  end
  f.feedback = fb
  local title = UI.Label(f, "Phyzan Capital", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", M, -S(4) - math.floor((cs - UI.LineH("GameFontNormalLarge")) / 2))
  local titleW = UI.WidthOf(title)
  -- crafting list buttons (shown while the auction house is open): on this line when they fit, else on their own
  f.shopOpen = UI.Button(f, "Open Crafting List", 150, 24, function() UI:Show("shopping") end)
  f.shopClear = UI.Button(f, "Clear Crafting List", 150, 24, function() if ns.Shop then ns.Shop:AskClear() end end)
  local lineW = innerW - UI.WidthOf(scan) - UI.WidthOf(fb) - S(8) - cs - S(24)
  local function shopWidth() return UI.WidthOf(f.shopOpen) + UI.WidthOf(f.shopClear) + S(8) end
  local shopW = shopWidth()
  local shopInline = titleW + S(16) + shopW <= lineW
  if not shopInline then -- large text: short labels, the title may be cut ("...")
    f.shopOpen:SetText("Crafting List"); f.shopOpen:SetWidth(1); UI.FitButton(f.shopOpen, S(40))
    f.shopClear:SetText("Clear List"); f.shopClear:SetWidth(1); UI.FitButton(f.shopClear, S(40))
    shopW = shopWidth()
    shopInline = shopW + S(16) <= lineW -- the title is dropped when there is no room left for it
  end
  local fbLine2 = false
  if not shopInline and shopW + S(16) <= lineW + UI.WidthOf(fb) + S(8) then -- very large text: Feedback moves to line 2
    fbLine2, shopInline = true, true
    lineW = lineW + UI.WidthOf(fb) + S(8)
  end
  local tw = shopInline and (lineW - shopW - S(16)) or lineW
  title:SetWidth(math.max(1, tw))
  if tw < S(60) then title:Hide() end
  if title.SetWordWrap then title:SetWordWrap(false) end
  title:SetHeight(UI.LineH("GameFontNormalLarge"))
  local y = -S(4) - math.max(UI.LineH("GameFontNormalLarge"), cs, UI.HeightOf(scan)) - S(4)
  if shopInline then
    f.shopClear:SetPoint("RIGHT", fbLine2 and scan or fb, "LEFT", -S(16), 0)
    f.shopOpen:SetPoint("RIGHT", f.shopClear, "LEFT", -S(8), 0)
  else
    y = UI.Flow(f, { f.shopOpen, f.shopClear }, M, y, innerW, S(8))
  end

  -- line 2: AH status (left half) | character (right half); hover shows both in full
  f.ahStatus = UI.Label(f, "", "GameFontHighlight")
  f.ahStatus:SetPoint("TOPLEFT", f, "TOPLEFT", M, y)
  f.ahStatus:SetWidth(math.floor(innerW * 0.5) - S(8))
  f.charInfo = UI.Label(f, "", "GameFontHighlight")
  local line2H = UI.LineH("GameFontHighlight")
  if fbLine2 then
    fb:SetHeight(line2H) -- as tall as the text line, so the tab rows stay where they are
    fb:ClearAllPoints()
    fb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -M, y)
    f.charInfo:SetPoint("TOPRIGHT", fb, "TOPLEFT", -S(8), -math.floor((UI.HeightOf(fb) - UI.LineH("GameFontHighlight")) / 2))
    f.charInfo:SetWidth(math.max(S(40), math.floor(innerW * 0.5) - S(16) - UI.WidthOf(fb)))
  else
    f.charInfo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -M, y)
    f.charInfo:SetWidth(math.floor(innerW * 0.5) - S(8))
  end
  f.charInfo:SetJustifyH("RIGHT")
  for _, fs in ipairs({ f.ahStatus, f.charInfo }) do
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetHeight(UI.LineH("GameFontHighlight"))
  end
  local hover = CreateFrame("Frame", nil, f)
  hover:SetPoint("TOPLEFT", M, y)
  if fbLine2 then hover:SetPoint("TOPRIGHT", fb, "TOPLEFT", -S(4), 0) else hover:SetPoint("TOPRIGHT", -M, y) end
  hover:SetHeight(line2H)
  hover:EnableMouse(true)
  hover:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(f.ahStatus:GetText() or "", 1, 1, 1, true)
    GameTooltip:AddLine(f.charInfo:GetText() or "", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  hover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  if fbLine2 then
    f.ahStatus:ClearAllPoints()
    f.ahStatus:SetPoint("TOPLEFT", f, "TOPLEFT", M, y - math.floor((line2H - UI.LineH("GameFontHighlight")) / 2))
  end
  y = y - line2H - S(4)

  -- tabs: full names when they fit on one line, else short names, wrapping as a last resort
  f.tabs = {}
  local tabList, total = {}, 0
  for _, t in ipairs(UI.TAB_ORDER) do
    local b = UI.Button(f, t[2], 100, 20, function() UI:Show(t[1]) end)
    f.tabs[t[1]] = b
    tabList[#tabList + 1] = b
    total = total + UI.WidthOf(b) + S(4)
  end
  if total > innerW then
    for i, t in ipairs(UI.TAB_ORDER) do
      local b = tabList[i]
      b:SetText(t[3] or t[2])
      b:SetWidth(1)
      UI.FitButton(b, S(40), S(12))
    end
  end
  y = UI.Flow(f, tabList, M, y, innerW, S(4))

  -- scan status panel: scanner state (left) and last scan (right)
  local tmpl2 = BackdropTemplateMixin and "BackdropTemplate" or nil
  local sp = CreateFrame("Frame", nil, f, tmpl2)
  local spH = UI.LineH("GameFontHighlight") + S(8)
  sp:SetPoint("TOPLEFT", M, y)
  sp:SetPoint("TOPRIGHT", -M, y)
  sp:SetHeight(spH)
  if sp.SetBackdrop then
    sp:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    sp:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
  end
  f.lastScan = UI.Label(sp, "", "GameFontHighlightSmall")
  f.lastScan:SetPoint("RIGHT", -S(8), 0)
  f.lastScan:SetJustifyH("RIGHT")
  f.lastScan:SetWidth(math.floor(innerW * 0.34))
  sp.text = UI.Label(sp, "", "GameFontHighlight")
  sp.text:SetPoint("LEFT", S(8), 0)
  sp.text:SetWidth(innerW - math.floor(innerW * 0.34) - S(24))
  for _, fs in ipairs({ sp.text, f.lastScan }) do
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetHeight(UI.LineH("GameFontHighlight"))
  end
  f.scanPanel = sp
  y = y - spH - S(4)
  f.elapsed = 0
  f:SetScript("OnUpdate", function(self, el)
    self.elapsed = self.elapsed + el
    if self.elapsed > 0.5 then
      self.elapsed = 0
      local ok, err = pcall(UI.UpdateStatus, UI)
      if not ok and not UI.statusErrShown then UI.statusErrShown = true; ns.Print("status panel error: " .. tostring(err)); pcall(ns.RecordError, "status panel", err) end
    end
  end)

  f.content = CreateFrame("Frame", nil, f)
  f.content:SetPoint("TOPLEFT", M, y)
  f.content:SetPoint("BOTTOMRIGHT", -M, math.min(M, S(8)))
  f.contentTop = -y
  UI.contentW, UI.contentH = innerW, UI.ScreenH() + y - math.min(M, S(8))

  f.closedMsg = UI.Label(f.content, "Buying requires being at the auction house.\n" ..
    "Use the Price Lookup tab (or /capital price <item>) for last known prices.", "GameFontNormalHuge")
  f.closedMsg:SetPoint("CENTER")
  f.closedMsg:SetWidth(UI.contentW or innerW)
  if f.closedMsg.SetJustifyH then f.closedMsg:SetJustifyH("CENTER") end
  f.closedMsg:Hide()

  f:SetScript("OnHide", function()
    -- closing the window cancels an open auction confirmation (it would act on the AH behind a closed window)
    local d = UI.confirmFrame
    if d and d:IsShown() and UI.confirmOpts and UI.confirmOpts.which == "trade" then d:Hide() end
    UI:ApplyBlizzardVisibility()
  end)
  f:SetScript("OnShow", function() UI:ApplyBlizzardVisibility() end)
  f:Hide()
  return f
end

-- Inner size of the tab area (real pixels).
function UI.PanelW() return UI.contentW or UI.ContentW() end
function UI.PanelH() return UI.contentH or (UI.ScreenH() - S(200)) end

-- Change the text size: fonts update live, then the window is rebuilt so every size and position follows.
function UI:SetTextScale(v)
  v = UI.ClampScale(v)
  if ns.db then ns.db.settings.textScale = v end
  local was = self.frame and self.frame:IsShown()
  UI.scale = v
  self:ApplyFonts()
  if self.frame then
    local old = self.frame
    if ns.Scanner and ns.Scanner.buttons then
      for i = #ns.Scanner.buttons, 1, -1 do if ns.Scanner.buttons[i] == old.scan then table.remove(ns.Scanner.buttons, i) end end
    end
    old:Hide()
    old:SetScript("OnUpdate", nil)
    self.frame, self.panels = nil, {}
  end
  if self.confirmFrame then -- an open question is cancelled (= No) and the dialog rebuilt at the new size
    if self.confirmOpts then self:ConfirmAnswer(false) end
    self.confirmFrame:Hide(); self.confirmFrame = nil
  end
  if was then self:Show() end
  return v
end

---------------------------------------------------------------------------
-- Our own confirmation dialog, used for every Phyzan Capital question (Blizzard's StaticPopup sizes itself from
-- its own font, so it cannot hold our larger text). The dialog measures its text and grows to fit:
--   width  = clamp(widest line + padding, minimum, 80% of the screen), the message word-wraps at that width
--   height = title + message + (edit box) + button row + padding
-- opts = { text, title, kind = "yesno" | "ok", yes = "Yes", no = "No", onYes(value), onNo(), which,
--          edit = { label, default, numeric, width }, alt = { text, fn } (third button; on its own row if needed),
--          check = { label, checked, onChange(checked) } (check box above the buttons), justify = "LEFT" (message) }
-- UI.confirmReplacing is true while an open question is being replaced by a new one (its onNo can tell).
-- onYes runs directly inside the Yes button's OnClick (or the Enter key handler), so protected calls such as
-- PlaceBid keep the hardware event. Escape = No, Enter = Yes. A new question replaces an open one (= No).
---------------------------------------------------------------------------
function UI:ConfirmFrame()
  local d = self.confirmFrame
  if d then return d end
  d = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  _G.PhyzanCapitalConfirm = d
  d:SetFrameStrata("FULLSCREEN_DIALOG") -- above our HIGH window and above the vendor / choice menus (DIALOG)
  if d.SetToplevel then d:SetToplevel(true) end
  d:EnableMouse(true)
  if d.SetBackdrop then
    d:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  end
  d.pad = math.max(S(16), 20)
  d.title = UI.Label(d, "Phyzan Capital", "GameFontNormalLarge")
  d.title:SetJustifyH("CENTER")
  if d.title.SetWordWrap then d.title:SetWordWrap(false) end
  d.msg = UI.Label(d, "", "GameFontHighlight")
  d.msg:SetJustifyH("CENTER")
  if d.msg.SetJustifyV then d.msg:SetJustifyV("TOP") end
  if d.msg.SetWordWrap then d.msg:SetWordWrap(true) end
  -- very long messages that do not fit the screen even one font size smaller: shown in a mouse-wheel scroll area
  d.msgScroll = CreateFrame("ScrollFrame", nil, d)
  d.msgChild = CreateFrame("Frame", nil, d.msgScroll)
  d.msgChild:SetSize(1, 1)
  d.msgScroll:SetScrollChild(d.msgChild)
  if d.msgScroll.EnableMouseWheel then d.msgScroll:EnableMouseWheel(true) end
  d.msgScroll:SetScript("OnMouseWheel", function(sf, delta)
    local max = math.max(0, (d.msgChild:GetHeight() or 0) - (sf:GetHeight() or 0))
    local v = (sf.GetVerticalScroll and sf:GetVerticalScroll() or 0) - delta * UI.LineH("GameFontHighlightSmall") * 3
    sf:SetVerticalScroll(math.max(0, math.min(max, v)))
  end)
  d.smsg = UI.Label(d.msgChild, "", "GameFontHighlightSmall")
  if d.smsg.SetJustifyV then d.smsg:SetJustifyV("TOP") end
  if d.smsg.SetWordWrap then d.smsg:SetWordWrap(true) end
  d.smsg:SetPoint("TOPLEFT", d.msgChild, "TOPLEFT", 0, 0)
  d.msgScroll:Hide()
  d.measure = UI.Label(d, "", "GameFontHighlight") -- unconstrained, for line widths
  if d.measure.SetWordWrap then d.measure:SetWordWrap(false) end
  d.measure:Hide()
  d.editLabel = UI.Label(d, "", "GameFontNormal")
  d.edit = UI.EditBox(d, 80)
  d.check = UI.CheckBox(d, "", function(btn) -- optional check box (opts.check), e.g. "Don't show this again"
    local o = UI.confirmOpts
    if o and o.check and o.check.onChange then pcall(o.check.onChange, btn:GetChecked() and true or false) end
  end)
  d.check:Hide(); d.check.label:Hide()
  d.yes = UI.Button(d, "Yes", 90, 24)
  d.no = UI.Button(d, "No", 90, 24)
  -- protected actions run right here, inside the click
  d.yes:SetScript("OnClick", function() UI:ConfirmAnswer(true) end)
  d.no:SetScript("OnClick", function() UI:ConfirmAnswer(false) end)
  d.alt = UI.Button(d, "", 90, 24) -- optional third answer (opts.alt), e.g. "Vendor not here"
  d.alt:SetScript("OnClick", function() UI:ConfirmAnswer("alt") end)
  d.alt:Hide()
  d.edit:SetScript("OnEnterPressed", function() UI:ConfirmAnswer(true) end)
  d.edit:SetScript("OnTextChanged", function(eb, userInput)
    local o = UI.confirmOpts
    if userInput and o and o.edit and o.edit.readOnly then
      eb:SetText(tostring(o.edit.default or ""))
      if eb.HighlightText then eb:HighlightText() end
    end
  end)
  d.edit:SetScript("OnEditFocusGained", function(eb)
    local o = UI.confirmOpts
    if o and o.edit and o.edit.readOnly and eb.HighlightText then eb:HighlightText() end
  end)
  d.foot = UI.Label(d, "", "GameFontHighlight") -- optional text under the edit box (opts.footer)
  d.foot:SetJustifyH("CENTER")
  if d.foot.SetJustifyV then d.foot:SetJustifyV("TOP") end
  if d.foot.SetWordWrap then d.foot:SetWordWrap(true) end
  d.foot:Hide()
  d.edit:SetScript("OnEscapePressed", function() UI:ConfirmAnswer(false) end)
  if d.EnableKeyboard then d:EnableKeyboard(true) end
  -- SetPropagateKeyboardInput is blocked in combat on the modern client ("Interface action failed", not catchable
  -- by pcall). Default to passing keys on, so movement keys still work if a dialog is open in combat.
  local function canPropagate(frame)
    return frame.SetPropagateKeyboardInput and not (type(InCombatLockdown) == "function" and InCombatLockdown())
  end
  if canPropagate(d) then pcall(d.SetPropagateKeyboardInput, d, true) end
  d:SetScript("OnKeyDown", function(frame, key)
    local mine = key == "ESCAPE" or key == "ENTER" or key == "NUMPADENTER"
    if canPropagate(frame) then pcall(frame.SetPropagateKeyboardInput, frame, not mine) end
    if key == "ESCAPE" then UI:ConfirmAnswer(false)
    elseif key == "ENTER" or key == "NUMPADENTER" then UI:ConfirmAnswer(true) end
  end)
  d:SetScript("OnHide", function() if UI.confirmOpts then UI:ConfirmAnswer(false) end end)
  d:Hide()
  self.confirmFrame = d
  return d
end

-- yes = true (Yes / OK / Enter), false (No / Escape / closed) or "alt" (third button). Runs the callback synchronously.
function UI:ConfirmAnswer(yes)
  local o = self.confirmOpts
  if not o then return end
  self.confirmOpts = nil
  local d = self.confirmFrame
  local value = o.edit and d.edit:GetText() or nil
  if d:IsShown() then d:Hide() end
  local fn
  if yes == "alt" then fn = o.alt and o.alt.fn elseif yes then fn = o.onYes else fn = o.onNo end
  if fn then
    local ok, err = pcall(fn, value)
    if not ok then ns.Print("error: " .. tostring(err)); pcall(ns.RecordError, "confirm " .. tostring(o.which), err) end
  end
end

local function widestLine(fs, text)
  local w = 0
  for line in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
    fs:SetText(line ~= "" and line or " ")
    w = math.max(w, fs:GetStringWidth() or 0)
  end
  return w
end

function UI:Confirm(opts)
  if self.confirmOpts then -- replaced question = No
    self.confirmReplacing = true
    self:ConfirmAnswer(false)
    self.confirmReplacing = false
  end
  local d = self:ConfirmFrame()
  local text = tostring(opts.text or ""):gsub("^Phyzan Capital\n\n", "") -- the title already says it
  opts.text = text
  local pad, gap = d.pad, S(8)
  d.title:SetText(opts.title or "Phyzan Capital")
  d.yes:SetText(opts.kind == "ok" and (opts.okText or OKAY or "OK") or (opts.yes or YES or "Yes"))
  d.no:SetText(opts.no or NO or "No")
  for _, b in ipairs({ d.yes, d.no }) do b:SetWidth(1); UI.FitButton(b, S(90)) end
  local bw = math.max(d.yes:GetWidth(), d.no:GetWidth())
  d.yes:SetWidth(bw); d.no:SetWidth(bw)
  local rowW = opts.kind == "ok" and bw or (2 * bw + gap)
  local altW = 0
  if opts.alt then
    d.alt:SetText(opts.alt.text or "?"); d.alt:SetWidth(1); UI.FitButton(d.alt, S(90))
    altW = d.alt:GetWidth()
  end
  local editW = 0
  if opts.edit then
    d.editLabel:SetText(opts.edit.label or "")
    d.edit:SetWidth(S(opts.edit.width or 80))
    if d.edit.SetNumeric then d.edit:SetNumeric(opts.edit.numeric and true or false) end
    d.edit:SetText(tostring(opts.edit.default or ""))
    if opts.edit.readOnly then -- a text to copy (Ctrl+C): as wide as its text, typing puts it back
      d.measure:SetFontObject(UI.Font("ChatFontNormal"))
      d.measure:SetText(tostring(opts.edit.default or ""))
      d.edit:SetWidth(math.ceil((d.measure:GetStringWidth() or 0) + S(24)))
      d.measure:SetFontObject(UI.Font("GameFontHighlight"))
    end
    editW = UI.WidthOf(d.editLabel) + gap + d.edit:GetWidth()
  end
  local checkW = 0
  if opts.check then
    d.check.label:SetText(opts.check.label or "")
    d.check.label:SetWidth(0)
    d.check:SetChecked(opts.check.checked and true or false)
    checkW = UI.WidthOf(d.check)
  end
  local maxW = math.floor(UI.ScreenW() * 0.8)
  local minW = math.min(maxW, S(320))
  local footW = opts.footer and widestLine(d.measure, opts.footer) or 0
  local need = math.max(widestLine(d.measure, text), UI.WidthOf(d.title), rowW, editW, altW, checkW, footW) + 2 * pad
  local W = math.floor(math.max(minW, math.min(maxW, need)))
  local innerW = W - 2 * pad
  if altW > innerW then d.alt:SetWidth(innerW); altW = innerW end
  local altInline = opts.alt and (rowW + gap + altW <= innerW)
  local altRowH = (opts.alt and not altInline) and (d.alt:GetHeight() + gap) or 0
  -- message: wrap at the inner width, then measure
  d.msg:SetText(text)
  d.msg:SetJustifyH(opts.justify or "CENTER")
  d.msg:SetWidth(innerW)
  d.msg:SetFontObject(UI.Font("GameFontHighlight"))
  local msgH = math.ceil(d.msg:GetStringHeight() or UI.LineH("GameFontHighlight")) + 2
  if checkW > innerW then d.check.label:SetWidth(innerW - d.check:GetWidth() - S(2)); checkW = innerW end
  local footH = 0
  if opts.footer then
    d.foot:SetText(opts.footer)
    d.foot:SetWidth(innerW)
    footH = math.ceil(d.foot:GetStringHeight() or UI.LineH("GameFontHighlight")) + 2
  end
  local checkH = opts.check and (math.max(d.check:GetHeight(), UI.LineH("GameFontHighlight")) + gap) or 0
  local fixedH = 2 * pad + UI.LineH("GameFontNormalLarge") + 3 * gap + d.yes:GetHeight() + (opts.edit and d.edit:GetHeight() + gap or 0) + altRowH + checkH + (opts.footer and footH + gap or 0)
  if fixedH + msgH > UI.ScreenH() - S(10) then -- very long text: one size smaller rather than off screen
    d.msg:SetFontObject(UI.Font("GameFontHighlightSmall"))
    msgH = math.ceil(d.msg:GetStringHeight() or UI.LineH("GameFontHighlightSmall")) + 2
  end
  local avail = math.floor(UI.ScreenH() - S(10) - fixedH)
  d.scrolling = msgH > avail
  if d.scrolling then -- still too tall: the message scrolls (mouse wheel), the dialog stays on screen
    d.smsg:SetFontObject(UI.Font("GameFontHighlightSmall"))
    d.smsg:SetJustifyH(opts.justify or "CENTER")
    d.smsg:SetWidth(innerW)
    d.smsg:SetText("|cff808080(scroll with the mouse wheel)|r\n" .. text)
    local sh = math.ceil(d.smsg:GetStringHeight() or msgH) + 2
    d.smsg:SetHeight(sh)
    d.msgChild:SetSize(innerW, sh)
    d.msgScroll:SetSize(innerW, avail)
    d.msgScroll:SetVerticalScroll(0)
    msgH = avail
    d.msg:SetText("")
    d.msg:Hide(); d.msgScroll:Show()
  else
    d.msg:Show(); d.msgScroll:Hide()
  end
  d.msg:SetHeight(msgH)
  d.title:SetWidth(innerW)
  local titleH = UI.LineH("GameFontNormalLarge")
  local y = -pad
  d.title:ClearAllPoints(); d.title:SetPoint("TOP", d, "TOP", 0, y); d.title:SetHeight(titleH)
  y = y - titleH - gap
  d.msg:ClearAllPoints(); d.msg:SetPoint("TOP", d, "TOP", 0, y)
  d.msgScroll:ClearAllPoints(); d.msgScroll:SetPoint("TOP", d, "TOP", 0, y)
  y = y - msgH - gap
  if opts.edit then
    local eh = math.max(d.edit:GetHeight(), UI.LineH("GameFontNormal"))
    if editW > innerW then editW = innerW; d.edit:SetWidth(math.max(S(40), innerW - UI.WidthOf(d.editLabel) - gap)) end
    d.editLabel:ClearAllPoints(); d.editLabel:SetPoint("TOPLEFT", d, "TOPLEFT", math.floor((W - editW) / 2), y - math.floor((eh - UI.LineH("GameFontNormal")) / 2))
    d.edit:ClearAllPoints(); d.edit:SetPoint("LEFT", d.editLabel, "RIGHT", gap, 0)
    d.editLabel:Show(); d.edit:Show()
    y = y - eh - gap
  else
    d.editLabel:Hide(); d.edit:Hide()
  end
  if opts.footer then
    d.foot:SetHeight(footH)
    d.foot:ClearAllPoints(); d.foot:SetPoint("TOP", d, "TOP", 0, y)
    d.foot:Show()
    y = y - footH - gap
  else
    d.foot:Hide()
  end
  if opts.check then
    d.check:ClearAllPoints()
    d.check:SetPoint("TOPLEFT", d, "TOPLEFT", math.floor((W - checkW) / 2), y)
    d.check:Show(); d.check.label:Show()
    y = y - checkH
  else
    d.check:Hide(); d.check.label:Hide()
  end
  local bh = d.yes:GetHeight()
  d.yes:ClearAllPoints(); d.no:ClearAllPoints()
  d.alt:ClearAllPoints()
  local shift = altInline and math.floor((altW + gap) / 2) or 0 -- inline: centre the whole Yes/No/alt row
  if opts.kind == "ok" then
    d.yes:SetPoint("TOP", d, "TOP", -shift, y)
    d.no:Hide()
  else
    d.yes:SetPoint("TOPRIGHT", d, "TOP", -math.floor(gap / 2) - shift, y)
    d.no:SetPoint("TOPLEFT", d, "TOP", math.ceil(gap / 2) - shift, y)
    d.no:Show()
  end
  if opts.alt then
    if altInline then
      d.alt:SetPoint("LEFT", opts.kind == "ok" and d.yes or d.no, "RIGHT", gap, 0)
    else
      d.alt:SetPoint("TOP", d, "TOP", 0, y - bh - gap)
      y = y - altRowH
    end
    d.alt:Show()
  else
    d.alt:Hide()
  end
  y = y - bh - pad
  d:SetSize(W, -y)
  d:ClearAllPoints()
  d:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  self.confirmOpts = opts
  d:Show()
  if d.Raise then d:Raise() end
  if opts.edit and d.edit.SetFocus then d.edit:SetFocus(); if d.edit.HighlightText then d.edit:HighlightText() end end
  if self.OnConfirmShown then self.OnConfirmShown(opts, d) end -- test hook
  return d
end

UI.TRADE_TABS = { search = true, buy = true }

function ns.TimeAgo(ts)
  local d = time() - ts
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. " min ago" end
  if d < 86400 then return string.format("%dh %02dm ago", math.floor(d / 3600), math.floor((d % 3600) / 60)) end
  return math.floor(d / 86400) .. " days ago"
end

-- Latest complete scan for an AH (or any AH when ahKey is nil).
function UI.LastScan(ahKey)
  local scans = ns.db and ns.db.scans or {}
  for i = #scans, 1, -1 do
    local s = scans[i]
    if s.complete and (not ahKey or s.ahKey == ahKey) then return s end
  end
end

-- Warning for analysis tabs: nil when data is fresh.
function UI.StaleWarning(ahKey)
  local s = UI.LastScan(ahKey)
  if not s then return "|cffff6060No scan data yet - open the auction house and click 'Scan Auction House'.|r" end
  if time() - s.ts > 2 * 3600 then
    return "|cffffcc00Scan data is " .. ns.TimeAgo(s.ts):gsub(" ago", "") .. " old - rescan for current prices.|r"
  end
end

function UI:UpdateStatus()
  local f = self.frame
  if not f or not f:IsShown() or not ns.db then return end
  local text, state = ns.Scanner:StatusText()
  local color = (state == "scanning" and "|cff66ccff") or (state == "complete" and "|cff00ff00") or
    (state == "failed" and "|cffff6060") or "|cffcccccc"
  f.scanPanel.text:SetText(color .. text .. "|r")
  local last = UI.LastScan(ns.Ledger:LatestAHKey())
  f.lastScan:SetText(last and string.format("Last scan: %s, %d items", ns.TimeAgo(last.ts), last.items or 0) or "No scan data yet")
end

function UI:Panel(key)
  local p = self.panels[key]
  if p then return p end
  p = CreateFrame("Frame", nil, self.frame.content)
  p:SetAllPoints(self.frame.content)
  p:Hide()
  local b = self.builders[key]
  if b and b.build then b.build(p) end
  self.panels[key] = p
  return p
end

-- Everything Phyzan Capital puts on Blizzard's auction frame: its alpha (made invisible while our window is open)
-- and our three buttons parented to it (Scan Auction House, Crafting List, Clear List). Nothing else is touched:
-- no tabs are added, no Blizzard panel is hidden, its tab / display mode is never changed (calling Blizzard's
-- AuctionHouseFrame methods from an add-on could taint its own Post / Buy buttons).
function UI:BlizzardAttachments()
  local list = {}
  if ns.Scanner and ns.Scanner.button then list[#list + 1] = ns.Scanner.button end
  if ns.Shop then
    if ns.Shop.bOpen then list[#list + 1] = ns.Shop.bOpen end
    if ns.Shop.bClear then list[#list + 1] = ns.Shop.bClear end
  end
  return list
end

-- Our window open: Blizzard's AuctionFrame / AuctionHouseFrame invisible (alpha 0; never Hide() - that closes the
-- AH session). Our window closed (X, Escape, /capital): Blizzard's frame fully back to normal - alpha 1 and none of
-- our buttons on it. Our buttons only show on it while our window is open and 'Hide Blizzard's auction window' is off.
function UI:ApplyBlizzardVisibility()
  local ours = self.frame and self.frame:IsShown() and ns.ahOpen and ns.db and true or false
  local hide = ours and ns.db.settings.hideBlizzardAH and true or false
  for _, af in ipairs({ AuctionFrame or false, AuctionHouseFrame or false }) do
    if af and af.SetAlpha then pcall(af.SetAlpha, af, hide and 0 or 1) end
  end
  local showButtons = ours and not hide
  for _, b in ipairs(self:BlizzardAttachments()) do
    if showButtons then b:Show() else b:Hide() end
  end
end

function UI:Refresh()
  local f = self.frame
  if not f or not f:IsShown() or not ns.db then return end
  f.ahStatus:SetText(ns.ahOpen and ("|cff00ff00Auction house open|r - " .. ns.CurrentAHKey())
    or ("|cffff6060Auction house closed|r - analysis of " .. ns.Ledger:LatestAHKey()))
  local who, profs = ns.Char:Summary()
  f.charInfo:SetText(who .. "  |  " .. profs)
  for _, b in ipairs({ f.shopOpen, f.shopClear }) do if ns.ahOpen then b:Show() else b:Hide() end end
  self:UpdateStatus()
  for k, b in pairs(f.tabs) do
    -- Price Lookup (offline search) lives under the Search tab button
    local on = (k == self.tab) or (k == "search" and self.tab == "prices")
    if b.LockHighlight then if on then b:LockHighlight() else b:UnlockHighlight() end end
  end
  for k, p in pairs(self.panels) do if k ~= self.tab then p:Hide() end end
  if self.TRADE_TABS[self.tab] and not ns.ahOpen then
    if self.panels[self.tab] then self.panels[self.tab]:Hide() end
    f.closedMsg:Show()
    return
  end
  f.closedMsg:Hide()
  local p = self:Panel(self.tab)
  p:Show()
  local b = self.builders[self.tab]
  if b and b.refresh then
    local ok, err = pcall(b.refresh, p)
    if not ok then ns.Print("UI error: " .. tostring(err)) end
  end
end

function UI:Show(tab)
  if not ns.db then return end
  if not self.frame then self.frame = makeFrame() end
  if tab and self.builders[tab] then self.tab = tab end -- unknown (e.g. removed "sell"/"swaps") keeps the current tab
  self.tab = self.tab or "search"
  -- away from the auction house, searching means looking up saved prices
  if not ns.ahOpen and (self.tab == "search" or (not tab and self.TRADE_TABS[self.tab])) then self.tab = "prices" end
  ns.CountUsage("tab:" .. self.tab)
  if self.tab == "shopping" and ns.MapPin then ns.MapPin.forceSpot = true end -- re-read position on tab open
  self.frame:Show()
  self:Refresh()
end

function UI:Toggle()
  if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

---------------------------------------------------------------------------
-- Analysis tabs
---------------------------------------------------------------------------
-- Market (1.4.1): Blizzard's Browse category tree on the left (Categories.lua, the Forever client's own list) with the
-- number of scanned items in each category; clicking a category filters the list on the right. Clicking an item asks
-- "Add <item> to crafting list?" (same question as Search and Price Lookup).
local MARKET_COLS = { { "Item", 320 }, { "Listings", 90 }, { "Quantity", 90 }, { "Lowest / unit", 130 }, { "Median today", 130 },
  { "Average today", 130 }, { "Vendor sells for", 130 }, { "Vendor buy", 120 } }

function UI.MarketTreeW()
  return math.floor(math.max(S(120), math.min(S(230), UI.PanelW() * 0.26)))
end

local function marketRows(ahKey)
  local ah = ns.AH(ahKey)
  local day = ns.MarketDay()
  local stats = ah.dailyStats[day] or {}
  local list, ids = {}, {}
  for id, c in pairs(ah.current) do
    local st = stats[id] or {}
    local it = ns.TouchItem(id) or {}
    local vb = ns.Vendor:BuyPrice(id)
    local row = { ns.ItemName(id), itemID = id, tostring(c.n or 0), tostring(c.qty or 0), ns.Money(c.minUnit), ns.Money(st.medianUnit),
      ns.Money(st.avgUnit), ns.Money(it.sellPrice), ns.Money(vb) }
    row.sort = { ns.ItemName(id), c.n or 0, c.qty or 0, c.minUnit or 0, st.medianUnit or 0, st.avgUnit or 0, it.sellPrice or 0, vb or 0 }
    list[#list + 1] = row
    ids[#ids + 1] = id
  end
  return list, ids, day
end
UI.MarketRows = marketRows

UI:RegisterTab("market", function(p)
  local W = UI.PanelW()
  local treeW = UI.MarketTreeW()
  local gap = S(8)
  p.sub = UI.Label(p, "", "GameFontNormal")
  p.sub:SetPoint("TOPLEFT", S(4), -S(4))
  p.sub:SetWidth(W - S(8))
  if p.sub.SetWordWrap then p.sub:SetWordWrap(false) end
  p.note = UI.Note(p, "Categories as in the auction house's Browse list (click to filter; click again to open or close). " ..
    "Prices from your latest complete scan (lowest) and today's scans (median/average). Click a column header to sort, " ..
    "an item to add it to the crafting list.", W - S(8))
  p.note:SetPoint("BOTTOMLEFT", S(4), S(2))
  local top = S(8) + UI.LineH("GameFontNormal")
  local bottom = UI.LineH("GameFontDisableSmall") + S(8)
  -- category tree: a one-level list whose rows are indented by depth ("+" closed, "-" open)
  p.tree = UI.List(p, { { "Category", 5 }, { "Items", 2 } }, function(_, row)
    local st = ns.db.settings
    if row.path == st.marketCategory then st.marketOpen = not st.marketOpen
    else st.marketCategory, st.marketOpen = row.path, true end
    p.list.offset = 0
    ns.CountUsage("market:category")
    UI:Refresh()
  end, nil, { width = treeW })
  p.tree.frame:SetPoint("TOPLEFT", 0, -top)
  p.tree.frame:SetPoint("BOTTOMLEFT", 0, bottom)
  p.tree.frame:SetWidth(treeW)
  p.list = UI.List(p, MARKET_COLS, function(_, row)
    if row.itemID and ns.Shop then ns.Shop:AskAddItem(row.itemID) end
  end, nil, { sortable = true, width = W - treeW - gap })
  p.list.sortCol, p.list.sortDesc = 3, true
  p.list.frame:SetPoint("TOPLEFT", treeW + gap, -top)
  p.list.frame:SetPoint("BOTTOMRIGHT", 0, bottom)
end, function(p)
  local CT = ns.Categories
  local st = ns.db.settings
  local ahKey = ns.Ledger:LatestAHKey()
  local all, ids, day = marketRows(ahKey)
  local counts, paths = CT:Count(ids)
  local sel = st.marketCategory or ""
  if sel ~= "" and sel ~= "?" and sel ~= "~" and not CT:Find(sel) then sel = ""; st.marketCategory = "" end
  if (sel == "?" or sel == "~") and (counts[sel] or 0) == 0 then sel = ""; st.marketCategory = "" end -- nothing left there
  local shown = all
  if sel ~= "" then
    shown = {}
    for _, row in ipairs(all) do if paths[row.itemID][sel] then shown[#shown + 1] = row end end
  end
  -- tree rows
  local trows = {}
  for _, r in ipairs(CT:Rows(sel, st.marketOpen, counts)) do
    local mark = r.hasSub and ((r.path == sel and st.marketOpen or (sel:sub(1, #r.path + 1) == r.path .. "/")) and "- " or "+ ") or "  "
    local text = string.rep("   ", math.max(0, r.depth - 1)) .. (r.depth > 0 and mark or "") .. r.name
    local n = counts[r.path] or 0
    local color = (n == 0 and not r.special) and "|cff808080" or (r.depth <= 1 and "|cffffd100" or "|cffffffff")
    trows[#trows + 1] = { color .. text .. "|r", tostring(n), path = r.path }
  end
  p.tree:SetData(trows)
  for i, r in ipairs(trows) do if r.path == sel then p.tree.selected = i end end
  p.tree:Render()
  local node = (sel == "?" and CT.UNKNOWN_NAME) or (sel == "~" and CT.OTHER_NAME) or (sel ~= "" and CT:Find(sel).name) or "All"
  local warn = UI.StaleWarning(ahKey)
  p.sub:SetText((warn and (warn .. "   ") or "") .. string.format("Market for %s (market day %s, 07:00 - 06:59) - %s: %d of %d items",
    ahKey, day, node, #shown, #all))
  p.list:SetData(shown, true)
end)

-- "crafts" = the Professions tab (ProfessionsTab.lua)

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
UI:RegisterTab("settings", function(p)
  local db = ns.db
  local c = UI.ScrollArea(p, UI.PanelW())
  p.child = c
  local W = UI.PanelW() - S(24)
  local x, gap = S(4), S(8)
  local y = -S(6)

  p.charHead = UI.Label(c, "", "GameFontNormalLarge")
  p.charHead:SetPoint("TOPLEFT", x, y)
  p.charHead:SetWidth(W)
  if p.charHead.SetWordWrap then p.charHead:SetWordWrap(false) end
  y = y - UI.LineH("GameFontNormalLarge") - gap

  -- Text size: slider 1.0x - 3.0x in 0.25 steps (applied when released), plus - / + buttons
  p.tsLabel = UI.Label(c, "", "GameFontNormal")
  p.tsMinus = UI.Button(c, "-", 30, 22, function() UI:SetTextScale(UI.scale - UI.SCALE_STEP); ns.CountUsage("settings:textsize") end)
  p.tsPlus = UI.Button(c, "+", 30, 22, function() UI:SetTextScale(UI.scale + UI.SCALE_STEP); ns.CountUsage("settings:textsize") end)
  -- UISliderTemplateWithLabels on the modern client; OptionsSliderTemplate (deprecated there) on older ones
  local sliderTmpl = "OptionsSliderTemplate"
  if type(C_XMLUtil) == "table" and type(C_XMLUtil.GetTemplateInfo) == "function" then
    local okT, info = pcall(C_XMLUtil.GetTemplateInfo, "UISliderTemplateWithLabels")
    if okT and info then sliderTmpl = "UISliderTemplateWithLabels" end
  end
  local okS, slider = pcall(CreateFrame, "Slider", "PhyzanCapitalTextSizeSlider", c, sliderTmpl)
  if not okS or not slider then slider = CreateFrame("Slider", nil, c) end
  if slider.EnableMouse then slider:EnableMouse(true) end
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(math.min(S(260), math.floor(W * 0.5)), math.max(S(17), 17))
  slider:SetMinMaxValues(UI.MIN_SCALE, UI.MAX_SCALE)
  slider:SetValueStep(UI.SCALE_STEP)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  if slider.GetThumbTexture and not slider:GetThumbTexture() and slider.SetThumbTexture then
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  end
  for _, part in ipairs({ "Low", "High", "Text" }) do -- template labels (parentKey, or $parentLow etc.)
    local fs = rawget(slider, part) or (slider.GetName and slider:GetName() and _G[slider:GetName() .. part])
    if fs and fs.SetFontObject then
      fs:SetFontObject(UI.Font("GameFontHighlightSmall"))
      fs:SetText(part == "Low" and "1x" or part == "High" and "3x" or "")
    end
  end
  slider:SetValue(UI.scale)
  slider:SetScript("OnValueChanged", function(self, v)
    v = UI.ClampScale(v)
    p.tsLabel:SetText(string.format("Text size: %.2fx", v) .. (v ~= UI.scale and " (release to apply)" or ""))
  end)
  slider:SetScript("OnMouseUp", function(self)
    local v = UI.ClampScale(self:GetValue())
    if v ~= UI.scale then ns.CountUsage("settings:textsize"); UI:SetTextScale(v) end
  end)
  p.textSize = slider
  p.tsLabel:SetText("Text size: 3.00x (release to apply)") -- reserve the widest text so the row never reflows
  p.tsLabel:SetWidth(math.min(UI.WidthOf(p.tsLabel), math.floor(W * 0.45)))
  if p.tsLabel.SetWordWrap then p.tsLabel:SetWordWrap(false) end
  y = UI.Flow(c, { p.tsLabel, p.tsMinus, slider, p.tsPlus }, x, y, W, gap)
  p.tsLabel:SetText(string.format("Text size: %.2fx", UI.scale))

  -- check boxes with long labels: the label wraps instead of running off screen, and the next row moves down
  local function fitCheck(cb, rowW)
    local lw = rowW - (UI.WidthOf(cb) - UI.WidthOf(cb.label))
    if UI.WidthOf(cb) > rowW then
      cb.label:SetWidth(math.max(S(40), lw - S(4)))
      if cb.label.SetWordWrap then cb.label:SetWordWrap(true) end
      return math.max(0, UI.WrapHeight(cb.label, math.max(S(40), lw - S(4)), "GameFontHighlight") - cb:GetHeight())
    end
    return 0
  end
  p.autoOpen = UI.CheckBox(c, "Open Phyzan Capital automatically when the auction house opens", function(self)
    db.settings.autoOpen = self:GetChecked() and true or false
  end)
  y = UI.Flow(c, { p.autoOpen }, x, y, W, gap) - fitCheck(p.autoOpen, W)
  p.hideB = UI.CheckBox(c, "Hide Blizzard's auction window while Phyzan Capital is open", function(self)
    db.settings.hideBlizzardAH = self:GetChecked() and true or false
    UI:ApplyBlizzardVisibility()
  end)
  y = UI.Flow(c, { p.hideB }, x, y, W, gap) - fitCheck(p.hideB, W)
  p.hideSeasonal = UI.CheckBox(c, "Hide seasonal vendors (Darkmoon Faire, holiday vendors) when picking the closest vendor", function(self)
    db.settings.hideSeasonalVendors = self:GetChecked() and true or false
    ns.CountUsage("settings:hideseasonal")
  end)
  y = UI.Flow(c, { p.hideSeasonal }, x, y, W, gap) - fitCheck(p.hideSeasonal, W)
  p.showCmds = UI.CheckBox(c, "Show the command list when the auction house opens (once per visit)", function(self)
    db.settings.showCommands = self:GetChecked() and true or false
    ns.CountUsage("settings:showcommands")
  end)
  p.cmdsBtn = UI.Button(c, "Show commands", 140, 22, function() UI:ShowCommands("settings") end)
  UI.FitButton(p.cmdsBtn, S(80))
  local extra = fitCheck(p.showCmds, W)
  y = UI.Flow(c, { p.showCmds }, x, y, W, gap) - extra
  y = UI.Flow(c, { p.cmdsBtn }, x, y, W, gap)

  p.refresh = UI.Button(c, "Refresh", 100, 22, function()
    ns.CountUsage("settings:refresh")
    ns.Char:Refresh("button")
  end)
  p.clearO = UI.Button(c, "Clear manual overrides", 180, 22, function()
    ns.CountUsage("settings:clearoverride")
    ns.Char:ClearOverrides()
    ns.Char:Refresh("clear override")
  end)
  p.detectInfo = UI.Label(c, "last detected 00:00 (button)", "GameFontDisableSmall")
  y = UI.Flow(c, { p.refresh, p.clearO, p.detectInfo }, x, y, W, gap)

  p.profList = UI.Label(c, "", "GameFontHighlight")
  p.profList:SetPoint("TOPLEFT", x + S(6), y)
  p.profList:SetWidth(W - S(10))
  p.profList:SetJustifyV("TOP")
  p.formBottom = -y
  p.status = UI.Label(c, "", "GameFontHighlightSmall")
  p.status:SetPoint("TOPLEFT", p.profList, "BOTTOMLEFT", -S(6), -gap)
  p.status:SetWidth(W)
  p.status:SetJustifyV("TOP")
  p.W = W
end, function(p)
  local db = ns.db
  local who = ns.Char:Summary()
  p.charHead:SetText("Detected: " .. who .. "   (" .. ns.CharKey() .. ")")
  local lines = {}
  for _, sk in ipairs(ns.Char.SKILLS) do
    local rank, over, max = ns.Char:Skill(sk[1])
    if rank then
      lines[#lines + 1] = string.format("%s%s: %d%s%s", sk[1], sk[4] == "secondary" and " (secondary)" or "", rank,
        max and ("/" .. max) or "", over and "  |cffffcc00(manual override)|r" or "")
    end
  end
  p.profList:SetText(#lines > 0 and table.concat(lines, "\n") or "No professions detected yet - press Refresh or open your skills / profession window.")
  local rec = db.chars[ns.CharKey()]
  p.detectInfo:SetText(rec and rec.lastDetect and ("last detected " .. date("%H:%M", rec.lastDetect) .. " (" .. tostring(rec.lastReason) .. ")") or "")
  if ns.Char:HasOverrides() then p.clearO:Show() else p.clearO:Hide() end
  p.autoOpen:SetChecked(db.settings.autoOpen)
  p.hideB:SetChecked(db.settings.hideBlizzardAH)
  p.hideSeasonal:SetChecked(db.settings.hideSeasonalVendors)
  p.showCmds:SetChecked(db.settings.showCommands)
  lines = {}
  local n, rows = 0, 0
  for _, s in ipairs(db.scans) do n = n + 1; if not s.pruned then rows = rows + (s.rows or 0) end end
  lines[#lines + 1] = string.format("Market day %s. Scans stored: %d, raw rows kept: %d (cap %d, %d days).",
    ns.MarketDay(), n, rows, db.settings.maxSnapshotRows, db.settings.keepSnapshotDays)
  local last = db.scans[#db.scans]
  if last then
    lines[#lines + 1] = string.format("Last scan #%d %s, %s, %d listings%s.", last.id, date("%Y-%m-%d %H:%M", last.ts),
      last.mode, last.rows or 0, last.complete and "" or " (incomplete)")
  end
  local v, r = 0, 0
  for _ in pairs(db.vendorPrices) do v = v + 1 end
  for _ in pairs(db.recipes) do r = r + 1 end
  local vi = ns.VendorDataInfo
  if vi then lines[#lines + 1] = string.format("Bundled vendor database: %d items, %d vendors (generated %s).", vi.items, vi.vendors, vi.generated) end
  lines[#lines + 1] = string.format("Recorded vendor prices: %d. Recorded recipes: %d. Bundled recipes: %d.", v, r,
    (function() local c = 0; for _ in pairs(ns.RecipeData or {}) do c = c + 1 end; return c end)())
  local usage = {}
  for k, c in pairs(db.usage) do usage[#usage + 1] = { k, c } end
  table.sort(usage, function(a, b) return a[2] > b[2] end)
  local top = {}
  for i = 1, math.min(8, #usage) do top[i] = usage[i][1] .. "=" .. usage[i][2] end
  lines[#lines + 1] = "Most used: " .. (#top > 0 and table.concat(top, ", ") or "-")
  lines[#lines + 1] = "Slash commands: /capital help    Text size: /capital textsize 1-3"
  p.status:SetText(table.concat(lines, "\n"))
  p.textSize:SetValue(UI.scale)
  local h1 = UI.WrapHeight(p.profList, p.W - S(10), "GameFontHighlight")
  local h2 = UI.WrapHeight(p.status, p.W, "GameFontHighlightSmall")
  p.profList:SetHeight(h1)
  p.child:SetHeight(p.formBottom + h1 + h2 + S(24))
end)

---------------------------------------------------------------------------
-- Command list (1.4.1): our own OK dialog, left-aligned, with "Don't show this when the auction house opens".
-- Shown once per auction house visit when the window opens on Search / Browse, and by /capital help. Closing it puts
-- the keyboard focus back in the Search name box (when that tab is showing); a bid / buyout question that replaces
-- it keeps the focus for itself.
function UI:ShowCommands(reason)
  local lines = {}
  for _, c in ipairs(ns.HELP_COMMANDS or {}) do
    if not c.chatOnly then lines[#lines + 1] = "|cffffd100" .. c[1] .. "|r  " .. c[2] end
  end
  local st = ns.db.settings
  local function back()
    if UI.confirmReplacing then return end -- another question took over
    local sp = UI.panels and UI.panels.search
    if UI.tab == "search" and sp and sp.name and sp:IsShown() and sp.name.SetFocus then sp.name:SetFocus() end
  end
  ns.CountUsage("commands:" .. tostring(reason or "?"))
  return self:Confirm({ which = "commands", kind = "ok", title = "Phyzan Capital commands", justify = "LEFT",
    text = table.concat(lines, "\n"),
    check = { label = "Don't show this when the auction house opens", checked = not st.showCommands,
      onChange = function(v) st.showCommands = not v end },
    onYes = back, onNo = back })
end

-- Feedback: the game cannot open mail or web pages, so the address is shown selected in a box to copy (Ctrl+C)
function UI:ShowFeedback(reason)
  ns.CountUsage("feedback:" .. tostring(reason or "?"))
  return self:Confirm({ which = "feedback", kind = "ok", okText = CLOSE or "Close", title = "Phyzan Capital feedback",
    text = "Send suggestions and bug reports to:",
    edit = { label = "", default = ns.FEEDBACK_EMAIL, readOnly = true },
    footer = "|cffffd100Press Ctrl+C to copy|r\n\nPlease include this line in bug reports:\n" .. ns.ReportLine() })
end

ns.On("AUCTION_HOUSE_SHOW", function()
  ns.ahOpen = true
  if ns.db.settings.autoOpen then UI:Show(UI.TRADE_TABS[UI.tab] and UI.tab or "search") else UI:Refresh() end
  -- the command list, once per visit, before the first search (never over an open question)
  if not UI.commandsShownThisVisit and ns.db.settings.showCommands and ns.db.settings.autoOpen and UI.tab == "search"
    and UI.frame and UI.frame:IsShown() and not UI.confirmOpts then
    UI.commandsShownThisVisit = true
    UI:ShowCommands("ah open")
  end
  UI:ApplyBlizzardVisibility()
  -- Blizzard_AuctionHouseUI is load-on-demand: its frame can appear just after the event
  ns.After(0.5, function() UI:ApplyBlizzardVisibility() end)
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
  ns.ahOpen = false
  UI.commandsShownThisVisit = nil
  if UI.confirmOpts and UI.confirmOpts.which == "commands" then UI:ConfirmAnswer(false) end
  if UI.tab == "search" then UI.tab = "prices" end -- searching away from the AH = saved prices
  UI:ApplyBlizzardVisibility()
  UI:Refresh()
end)
