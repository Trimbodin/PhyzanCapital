-- Geometry for the off-game mock: anchors, sizes, fonts and text metrics close enough to WoW's to audit layout.
-- Used by tools/test_addon.lua. Coordinates: origin bottom-left of UIParent, y up (as in WoW).
local G = { screenW = 1365, screenH = 768, all = {} }
local GLYPH = 0.55 -- average glyph width of Friz Quadrata, in em

-- Blizzard font objects (size from the default client fonts)
local BASE = { GameFontNormal = 12, GameFontHighlight = 12, GameFontDisable = 12, GameFontNormalSmall = 10,
  GameFontHighlightSmall = 10, GameFontDisableSmall = 10, GameFontNormalLarge = 16, GameFontHighlightLarge = 16,
  GameFontNormalHuge = 20, ChatFontNormal = 14 }
local function fontObject(name, size)
  local f = { _fontName = name, _size = size, _file = "Fonts\\FRIZQT__.TTF", _flags = name == "GameFontNormalHuge" and "OUTLINE" or "" }
  function f:GetFont() return self._file, self._size, self._flags end
  function f:SetFont(file, sz, flags) self._file, self._size, self._flags = file, sz, flags end
  function f:CopyFontObject(o) if type(o) == "string" then o = _G[o] end; self._size, self._file, self._flags = o._size, o._file, o._flags end
  function f:GetName() return self._fontName end
  return f
end
function G.installFonts()
  for n, sz in pairs(BASE) do _G[n] = fontObject(n, sz) end
  CreateFont = function(name) local f = fontObject(name, 12); _G[name] = f; return f end
end

local function fontOf(o)
  local f = o._font
  if type(f) == "string" then f = _G[f] end
  return f
end
function G.textSize(o) local f = fontOf(o); return (f and f._size) or 12 end
local function plain(s)
  s = tostring(s or "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return s
end
-- width of one line of text in pixels (|T..:w:h|t icons count as their width)
local function lineWidth(line, size)
  local icons = 0
  line = line:gsub("|T[^|]-:(%d+):%d+|t", function(w) icons = icons + tonumber(w); return "" end)
  return #line * size * GLYPH + icons
end
function G.stringWidth(o)
  local size, w = G.textSize(o), 0
  for line in (plain(o._text) .. "\n"):gmatch("([^\n]*)\n") do w = math.max(w, lineWidth(line, size)) end
  return math.ceil(w)
end
function G.stringHeight(o)
  local size = G.textSize(o)
  local lh = size * 1.2
  local width = o._w
  local lines = 0
  for line in (plain(o._text) .. "\n"):gmatch("([^\n]*)\n") do
    local lw = lineWidth(line, size)
    if width and width > 0 and o._wrap ~= false then lines = lines + math.max(1, math.ceil(lw / width)) else lines = lines + 1 end
  end
  return math.ceil(lines * lh)
end

-- anchors ---------------------------------------------------------------
local H = { TOPLEFT = "L", LEFT = "L", BOTTOMLEFT = "L", TOPRIGHT = "R", RIGHT = "R", BOTTOMRIGHT = "R", TOP = "C", BOTTOM = "C", CENTER = "C" }
local V = { TOPLEFT = "T", TOP = "T", TOPRIGHT = "T", BOTTOMLEFT = "B", BOTTOM = "B", BOTTOMRIGHT = "B", LEFT = "C", RIGHT = "C", CENTER = "C" }

function G.rect(o, depth)
  depth = (depth or 0) + 1
  if depth > 60 then error("anchor loop") end
  if o == UIParent or o._isScreen then return 0, G.screenW, G.screenH, 0 end
  local L, R, T, B, CX, CY
  for pt, a in pairs(o._points or {}) do
    local rel = a.rel or o._parent or UIParent
    local l, r, t, b = G.rect(rel, depth)
    local rp = a.relPoint or pt
    local px = (H[rp] == "L" and l) or (H[rp] == "R" and r) or (l + r) / 2
    local py = (V[rp] == "T" and t) or (V[rp] == "B" and b) or (t + b) / 2
    px, py = px + (a.x or 0), py + (a.y or 0)
    if H[pt] == "L" then L = px elseif H[pt] == "R" then R = px else CX = px end
    if V[pt] == "T" then T = py elseif V[pt] == "B" then B = py else CY = py end
  end
  local w, h = G.width(o, true), G.height(o, true)
  if L and R then -- two anchors win over the size
  elseif L then R = L + (w or 0)
  elseif R then L = R - (w or 0)
  elseif CX then L, R = CX - (w or 0) / 2, CX + (w or 0) / 2
  else L, R = 0, w or 0 end
  if T and B then
  elseif T then B = T - (h or 0)
  elseif B then T = B + (h or 0)
  elseif CY then T, B = CY + (h or 0) / 2, CY - (h or 0) / 2
  else T, B = G.screenH, G.screenH - (h or 0) end
  return L, R, T, B
end
local function hasTwo(o, axis)
  local a, b
  for pt in pairs(o._points or {}) do
    local k = axis == "h" and H[pt] or V[pt]
    if k == (axis == "h" and "L" or "T") then a = true elseif k == (axis == "h" and "R" or "B") then b = true end
  end
  return a and b
end
function G.width(o, noAnchors)
  if o == UIParent or o._isScreen then return G.screenW end
  if not noAnchors and hasTwo(o, "h") then local l, r = G.rect(o); return r - l end
  if o._w then return o._w end
  if o._isFS then return G.stringWidth(o) end
  return nil
end
function G.height(o, noAnchors)
  if o == UIParent or o._isScreen then return G.screenH end
  if not noAnchors and hasTwo(o, "v") then local _, _, t, b = G.rect(o); return t - b end
  if o._h then return o._h end
  if o._isFS then return G.stringHeight(o) end
  return nil
end

-- methods merged into every mock widget
G.methods = {
  SetPoint = function(self, pt, rel, relPoint, x, y)
    self._points = self._points or {}
    if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint
    elseif type(relPoint) == "number" then relPoint, x, y = nil, relPoint, x end
    if type(rel) == "string" then rel = _G[rel] end
    self._points[pt] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
  end,
  ClearAllPoints = function(self) self._points = {} end,
  SetAllPoints = function(self, rel)
    self._points = {}
    if type(rel) == "string" then rel = _G[rel] end
    self._points.TOPLEFT = { rel = rel, x = 0, y = 0 }
    self._points.BOTTOMRIGHT = { rel = rel, x = 0, y = 0 }
  end,
  SetSize = function(self, w, h) self._w, self._h = w, h end,
  SetWidth = function(self, w) self._w = w end,
  SetHeight = function(self, h) self._h = h end,
  GetWidth = function(self) return G.width(self) or 0 end,
  GetHeight = function(self) return G.height(self) or 0 end,
  GetLeft = function(self) local l = G.rect(self); return l end,
  GetRight = function(self) local _, r = G.rect(self); return r end,
  GetTop = function(self) local _, _, t = G.rect(self); return t end,
  GetBottom = function(self) local _, _, _, b = G.rect(self); return b end,
  SetFontObject = function(self, f) self._font = f end,
  GetFontObject = function(self) return self._font end,
  SetWordWrap = function(self, v) self._wrap = v and true or false end,
  GetStringWidth = function(self) return G.stringWidth(self) end,
  GetStringHeight = function(self) return G.stringHeight(self) end,
  IsTruncated = function(self)
    if self._wrap ~= false then return false end
    return self._w ~= nil and G.stringWidth(self) > G.width(self) + 0.5
  end,
  SetScrollChild = function(self, c)
    self._scrollChild = c
    c._inScroll = self
    if not next(c._points or {}) then c._points = { TOPLEFT = { rel = self, x = 0, y = 0 } } end
  end,
  GetScrollChild = function(self) return self._scrollChild end,
  SetVerticalScroll = function(self, v) self._vscroll = v end,
  GetVerticalScroll = function(self) return self._vscroll or 0 end,
  SetMinMaxValues = function(self, a, b) self._min, self._max = a, b end,
  SetValue = function(self, v)
    self._value = v
    if self._scripts and self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end
  end,
  GetValue = function(self) return self._value end,
  GetThumbTexture = function() return {} end,
}
return G
