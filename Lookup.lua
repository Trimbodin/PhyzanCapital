-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital offline price lookup (1.2.7): look up any item's last known auction price anywhere in the world,
-- from the scans saved in PhyzanCapitalDB (ah[*].lastKnown / ah[*].history, see Ledger.lua). Used by the
-- "Price Lookup" tab and by /capital price <item name>. Read-only: nothing here talks to the auction house.
local _, ns = ...
local LK = {}
ns.Lookup = LK

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
function LK.DayLabel(day) -- "2026-10-17" -> "Oct 17"
  local y, m, d = tostring(day or ""):match("^(%d+)-(%d+)-(%d+)$")
  if not y then return tostring(day) end
  return MONTHS[tonumber(m)] .. " " .. tonumber(d)
end
local function hourText(h) -- 7 -> "7:00 AM"
  local suffix = h < 12 and "AM" or "PM"
  local hh = h % 12; if hh == 0 then hh = 12 end
  return hh .. ":00 " .. suffix
end
function LK.MarketDayText(day)
  local h = (ns.db and ns.db.settings.dayStartHour) or 7
  local endH = (h + 23) % 24
  local e = endH % 12; if e == 0 then e = 12 end
  return string.format("market day %s (%s - %d:59 %s next day)", LK.DayLabel(day), hourText(h), e, endH < 12 and "AM" or "PM")
end
function LK.When(ts) return date("%b %d %H:%M", ts) end

-- Everything we know about one item: the newest lastKnown entry across the auction houses you scanned.
function LK:Info(id)
  local best, bestKey
  for ahKey, ah in pairs(ns.db.ah) do
    local e = ah.lastKnown and ah.lastKnown[id]
    if e and (not best or (e.t or 0) > (best.t or 0)) then best, bestKey = e, ahKey end
  end
  local it = ns.TouchItem(id) or {}
  local vb = ns.Vendor:BuyPrice(id)
  local info = { id = id, name = ns.ItemName(id), vendorBuy = vb, vendorSell = (it.sellPrice and it.sellPrice > 0) and it.sellPrice or nil }
  if not best then return info end
  local ah = ns.AH(bestKey)
  info.ahKey, info.unit, info.ts, info.listings, info.quantity = bestKey, best.u, best.t, best.n, best.q
  info.day = best.t and ns.MarketDay(best.t)
  info.history = ns.Ledger.DecodeHistory(ah.history and ah.history[id])
  -- typical price: today's median, else the newest stored daily median, else the median of the stored daily lows
  local today = ah.dailyStats[ns.MarketDay()]
  if today and today[id] and today[id].medianUnit then
    info.median, info.medianSrc = today[id].medianUnit, "today's median"
  else
    for i = #info.history, 1, -1 do
      local h = info.history[i]
      if h.median then info.median, info.medianSrc = h.median, "median on " .. LK.DayLabel(h.day); break end
    end
    if not info.median then
      local lows = {}
      for _, h in ipairs(info.history) do if h.low then lows[#lows + 1] = h.low end end
      if #lows >= 2 then
        table.sort(lows)
        local n = #lows
        info.median = (n % 2 == 1) and lows[(n + 1) / 2] or math.floor((lows[n / 2] + lows[n / 2 + 1]) / 2 + 0.5)
        info.medianSrc = string.format("median of the lowest prices on %d market days", n)
      end
    end
  end
  return info
end

-- Name index: names cached from the client, bundled names (Data/ItemNames.lua) and every item with scan data.
function LK:Candidates()
  local seen, out = {}, {}
  local function add(id)
    if id and not seen[id] then
      seen[id] = true
      local name = ns.ItemName(id)
      if name and not name:find("^Item #") then out[#out + 1] = { id = id, name = name, low = name:lower() } end
    end
  end
  for _, ah in pairs(ns.db.ah) do for id in pairs(ah.lastKnown or {}) do add(id) end end
  for id, it in pairs(ns.db.items) do if it.name then add(id) end end
  for id in pairs(ns.ItemNames or {}) do add(id) end
  return out
end

-- Partial, case-insensitive name match. Items with a saved price first, then exact, prefix, word start, shorter names.
function LK:Find(query, limit)
  local q = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then return {} end
  local hits = {}
  for _, c in ipairs(self:Candidates()) do
    local pos = c.low:find(q, 1, true)
    if pos then
      local priced = false
      for _, ah in pairs(ns.db.ah) do local e = ah.lastKnown and ah.lastKnown[c.id]; if e and e.u then priced = true; break end end
      local rank = (c.low == q and 0) or (pos == 1 and 1) or (c.low:sub(pos - 1, pos - 1) == " " and 2) or 3
      hits[#hits + 1] = { id = c.id, name = c.name, priced = priced, rank = rank }
    end
  end
  table.sort(hits, function(a, b)
    if a.priced ~= b.priced then return a.priced end
    if a.rank ~= b.rank then return a.rank < b.rank end
    if #a.name ~= #b.name then return #a.name < #b.name end
    return a.name < b.name
  end)
  local out = {}
  for i = 1, math.min(limit or 50, #hits) do out[i] = hits[i] end
  return out, #hits
end

function LK.Headline(info)
  if not info.unit then
    return info.ts and string.format("Listed without a buyout in the last scan that had it (%s ago)", (ns.TimeAgo(info.ts):gsub(" ago", "")))
      or "No auction house price saved yet (scan the auction house to record one)"
  end
  return string.format("Last known price (scanned %s ago)", (ns.TimeAgo(info.ts):gsub(" ago", "")))
end

-- Chat line for /capital price
function LK:ChatLines(info)
  local lines = {}
  if info.unit then
    lines[1] = string.format("%s: last known price %s each (lowest buyout, scanned %s ago on %s, %s, %s).", ns.ItemLabel(info.id, true),
      ns.Money(info.unit), (ns.TimeAgo(info.ts):gsub(" ago", "")), LK.When(info.ts), LK.MarketDayText(info.day), info.ahKey)
  else
    lines[1] = string.format("%s: %s.", ns.ItemLabel(info.id, true), LK.Headline(info))
  end
  local extra = {}
  if info.median then extra[#extra + 1] = "typical " .. ns.Money(info.median) .. " (" .. info.medianSrc .. ")" end
  if info.vendorBuy then extra[#extra + 1] = "vendor sells it for " .. ns.Money(info.vendorBuy) end
  if info.vendorSell then extra[#extra + 1] = "vendor buys it for " .. ns.Money(info.vendorSell) end
  if #extra > 0 then lines[#lines + 1] = "  " .. table.concat(extra, ", ") .. "." end
  if info.history and #info.history > 1 then
    local parts = {}
    for i = #info.history, math.max(1, #info.history - 4), -1 do
      local h = info.history[i]
      parts[#parts + 1] = LK.DayLabel(h.day) .. " " .. ns.Money(h.low)
    end
    lines[#lines + 1] = "  Lowest per market day: " .. table.concat(parts, ", ") .. "."
  end
  if not ns.ahOpen then lines[#lines + 1] = "  (Buying requires being at the auction house.)" end
  return lines
end

-- /capital price <item name>
function LK:Chat(query)
  query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if query == "" then ns.Print("usage: /capital price <item name>  (part of the name is enough)"); return end
  local hits, total = self:Find(query, 6)
  if #hits == 0 then ns.Print("no item called '" .. query .. "' found in your scans or the item list."); return end
  for _, l in ipairs(self:ChatLines(self:Info(hits[1].id))) do ns.Print(l) end
  if total > 1 then
    local others = {}
    for i = 2, #hits do others[#others + 1] = hits[i].name end
    ns.Print(string.format("  %d more match(es)%s%s - type more of the name, or use the Price Lookup tab.", total - 1,
      #others > 0 and ": " or "", table.concat(others, ", ")))
  end
  ns.CountUsage("cmd:price")
end

---------------------------------------------------------------------------
-- "Price Lookup" tab: works anywhere (it is not one of the trading tabs)
---------------------------------------------------------------------------
local UI = ns.UI
local S = UI.S
local AH_NEEDED = "Buying requires being at the auction house."

function LK:Run(text)
  self.query = text
  self.results = self:Find(text, 50)
  self.selected = self.results[1] and self.results[1].id or nil
  ns.CountUsage("lookup:search")
  UI:Refresh()
end

-- Result rows (volume is deliberately not shown).
function LK:Rows()
  local rows = {}
  for _, h in ipairs(self.results or {}) do
    local info = self:Info(h.id)
    local row = { info.name, itemID = h.id, info.unit and ns.Money(info.unit) or "|cff999999no scan price|r",
      info.median and ns.Money(info.median) or "-", info.ts and ns.TimeAgo(info.ts) or "-",
      info.vendorBuy and ns.Money(info.vendorBuy) or "-" }
    row.data = info
    rows[#rows + 1] = row
  end
  return rows
end

function LK:DetailLines(info)
  local l = {}
  if info.unit then
    l[#l + 1] = string.format("Lowest buyout: %s each.", ns.Money(info.unit))
  end
  if info.ts then
    l[#l + 1] = string.format("Scanned %s (%s), %s.", LK.When(info.ts), LK.MarketDayText(info.day), info.ahKey or "?")
  end
  l[#l + 1] = info.median and string.format("Typical price: %s (%s).", ns.Money(info.median), info.medianSrc)
    or "Typical price: not enough scans yet."
  l[#l + 1] = string.format("Vendor: sells it to you for %s, buys it from you for %s.",
    info.vendorBuy and ns.Money(info.vendorBuy) or "- (not sold by a known vendor)",
    info.vendorSell and ns.Money(info.vendorSell) or "-")
  return table.concat(l, "\n")
end

function LK:HistoryText(info)
  local h = info.history or {}
  if #h == 0 then return "" end
  local parts = {}
  for i = #h, 1, -1 do
    local e = h[i]
    parts[#parts + 1] = LK.DayLabel(e.day) .. ": " .. (e.low and ns.Money(e.low) or "-") ..
      (e.median and (" (median " .. ns.Money(e.median) .. ")") or "")
  end
  return "Price history, lowest buyout per market day (newest first): " .. table.concat(parts, ",  ")
end

local function setEnabled(b, on)
  b.pcDisabled = not on
  if on then if b.Enable then b:Enable() end elseif b.Disable then b:Disable() end
end

UI:RegisterTab("prices", function(p)
  local W = UI.PanelW() - S(8)
  local c = UI.ScrollArea(p, UI.PanelW())
  p.child = c
  p.title = UI.Label(c, "Look up the last known auction price of any item from your saved scans - works anywhere.", "GameFontNormal")
  local ql = UI.Label(c, "Item name", "GameFontNormal")
  p.q = UI.EditBox(c, 260)
  p.q:SetWidth(math.min(p.q:GetWidth(), math.floor(W * 0.45)))
  p.q:SetScript("OnEnterPressed", function(self) self:ClearFocus(); LK:Run(self:GetText()) end)
  p.q:SetScript("OnTextChanged", function(self, userInput)
    local t = self:GetText() or ""
    if userInput and #t >= 3 then LK:Run(t) end
  end)
  p.go = UI.Button(c, "Look up", 100, 22, function() LK:Run(p.q:GetText()) end)
  p.status = UI.Label(c, "", "GameFontNormal")
  p.list = UI.List(c, { { "Item", 260 }, { "Last known lowest (each)", 180 }, { "Typical", 120 }, { "Scanned", 140 },
    { "Vendor sells for", 130 } }, function(_, row)
      LK.selected = row.itemID
      UI:Refresh()
      if ns.Shop then ns.Shop:AskAddItem(row.itemID) end -- "Add <item> to crafting list?"
    end, 12, { width = W })
  p.head = UI.Label(c, "", "GameFontNormalLarge")
  p.detail = UI.Label(c, "", "GameFontHighlight")
  p.hist = UI.Label(c, "", "GameFontHighlightSmall")
  p.buy = UI.Button(c, "Search at the AH", 160, 24, function()
    if not ns.ahOpen then ns.Print(AH_NEEDED); return end
    local id = LK.selected
    if not id then return end
    UI:Show("search")
    local sp = UI.panels.search
    if sp and sp.name then sp.name:SetText(ns.ItemName(id)) end
    ns.Trade.query = { name = ns.ItemName(id), quality = -1, usable = false }
    ns.Trade:Search(0)
  end)
  p.btnNote = UI.Label(c, "", "GameFontNormal")
  function p.Relayout(nRows)
    p.list.frame:SetHeight(p.list:HeightFor(math.max(3, math.min(nRows or 3, 12))))
    local y = UI.Stack(c, {
      { text = p.title, font = "GameFontNormal" },
      { flow = { ql, p.q, p.go } },
      { text = p.status, font = "GameFontNormal" },
      { frame = p.list.frame, w = W },
      { text = p.head, font = "GameFontNormalLarge" },
      { text = p.detail, font = "GameFontHighlight" },
      { text = p.hist, font = "GameFontHighlightSmall" },
      { flow = { p.buy } },
      { text = p.btnNote, font = "GameFontNormal" },
    }, S(4), -S(4), W - S(8), S(6))
    c:SetHeight(-y + S(4))
    p.list.laidOut = nil
  end
end, function(p)
  if (p.q:GetText() or "") == "" and LK.query then p.q:SetText(LK.query) end
  local last = UI.LastScan(nil)
  if ns.ahOpen then
    p.status:SetText("|cff00ff00At the auction house|r - 'Search at the AH' shows the live listings.")
  else
    p.status:SetText("|cffffcc00Not at the auction house: these are last known prices from your saved scans" ..
      (last and (" (latest scan " .. ns.TimeAgo(last.ts) .. ")") or " (no scan saved yet)") .. ". " .. AH_NEEDED .. "|r")
  end
  local rows = LK:Rows()
  local sel
  for i, r in ipairs(rows) do if r.itemID == LK.selected then sel = i end end
  local info = sel and rows[sel].data
  if info then
    p.head:SetText(LK.Headline(info) .. ": " .. ns.ItemLabel(info.id, true))
    p.detail:SetText(LK:DetailLines(info))
    p.hist:SetText(LK:HistoryText(info))
  else
    p.head:SetText((LK.query and #rows == 0) and ("No item matching '" .. LK.query .. "'.") or "Type part of an item name and press Enter.")
    p.detail:SetText("")
    p.hist:SetText("")
  end
  for _, b in ipairs({ p.buy }) do
    setEnabled(b, ns.ahOpen and info ~= nil)
    if info then b:Show() else b:Hide() end
  end
  p.btnNote:SetText(info and (ns.ahOpen and "" or ("|cffff6060" .. AH_NEEDED .. "|r")) or "")
  p.Relayout(#rows)
  p.list:SetData(rows, true)
  p.list.selected = sel
  p.list:Render()
end)
