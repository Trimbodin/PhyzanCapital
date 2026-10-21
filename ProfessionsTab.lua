-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital "Professions" tab (replaces the old "Profitable Crafts" tab; same key "crafts", so /capital crafts
-- and a remembered tab still work). Lists the recipes you know per profession with what every reagent costs right
-- now (the cheaper of the latest AH price and the vendor price, saying which), the total cost, what the product
-- sells for after the AH cut, and the profit. Profitable recipes come first and are highlighted green.
-- Recipes come from your profession window (C_TradeSkillUI, recorded when you open it); until a profession has been
-- opened, the bundled trainer recipes up to your skill are shown as "probably known".
local _, ns = ...
local UI = ns.UI
local S = UI.S
local PT = { filter = nil, showLearnable = false }
ns.ProfTab = PT

local GREEN, RED, YELLOW = "|cff20ff20", "|cffff6060", "|cffffcc00"
local PROFIT_TINT = { 0.1, 0.65, 0.1, 0.22 }
local PROBABLY = "probably known - open your profession window to confirm"

local function money(c) return c and ns.Money(c) or (RED .. "no price|r") end
local function profitText(r)
  if not r.profit then return RED .. "missing price|r" end
  if r.profit > 0 then return GREEN .. "+" .. ns.Money(r.profit) .. "|r" end
  return RED .. "-" .. ns.Money(-r.profit) .. "|r"
end
local function whereText(rg)
  if rg.where == "vendor" then return "vendor" end
  if rg.where == "AH" then
    return (rg.ahWhen == "now" and "AH (scan)") or (rg.ahWhen == "today" and "AH (today's median)") or "AH (yesterday)"
  end
  return RED .. "no price|r"
end
PT.WhereText = whereText

-- 1.3.1 "Available on AH": total quantity listed in the latest complete scan of this auction house (all listings
-- added up; ah.current[id].qty, saved with the scan, so it also works away from the AH). 0 = scanned, none listed;
-- nil = no scan of this auction house yet.
function PT.Available(ahKey, id)
  local ah = ns.AH(ahKey)
  if not UI.LastScan(ahKey) and not next(ah.current or {}) then return nil end
  local c = ah.current and ah.current[id]
  return c and (c.qty or 0) or 0, c and (c.n or 0) or 0
end
local function availText(q) return q and ns.IntStr(q) or "no scan" end
PT.AvailText = availText

-- Rows for the recipe list (also used by the tests): profitable first, then the rest, missing prices last.
function PT:Rows(ahKey)
  local book = ns.Prof:RecipeBook(ahKey)
  local rows, profitable, missing = {}, 0, 0
  for _, e in ipairs(book) do
    if not PT.filter or PT.filter == e.name then
      local lists = { e.recipes }
      if PT.showLearnable then lists[2] = e.learnable end
      for _, list in ipairs(lists) do
        for _, r in ipairs(list) do
          local status = r.status
          if status == "known" then status = GREEN .. "known|r" elseif status == "probably known" then status = YELLOW .. "probably known|r" end
          -- the item column is drawn as the coloured item name with icon (how many it makes is in the detail line)
          local row = { ns.ItemName(r.id), itemID = r.id, e.name, status,
            r.cost and ns.Money(r.cost) or (YELLOW .. ns.Money(r.knownCost) .. "+?|r"),
            r.revenue and ns.Money(r.revenue) or (RED .. "no price|r"), profitText(r),
            r.margin and ((r.profit > 0 and GREEN or RED) .. ns.IntStr(r.margin * 100) .. "%|r") or "" }
          local avail = PT.Available(ahKey, r.id)
          row[#row + 1] = availText(avail)
          row.sort = { ns.ItemName(r.id), e.name, r.status or "", r.cost or r.knownCost or 0, r.revenue or -1,
            r.profit or -math.huge, r.margin or -math.huge, avail or -1 }
          row.data = r
          if r.profit and r.profit > 0 then row.tint = PROFIT_TINT; profitable = profitable + 1 end
          if not r.profit then missing = missing + 1 end
          rows[#rows + 1] = row
        end
      end
    end
  end
  -- one ordering across professions: profitable (by profit), unprofitable, missing prices
  local function group(r) return r.data.profit and (r.data.profit > 0 and 1 or 2) or 3 end
  for i, r in ipairs(rows) do r.order = i end
  table.sort(rows, function(a, b)
    local ga, gb = group(a), group(b)
    if ga ~= gb then return ga < gb end
    if ga < 3 and a.data.profit ~= b.data.profit then return a.data.profit > b.data.profit end
    return a.order < b.order
  end)
  return rows, book, profitable, missing
end

-- Header lines: professions, scan age / missing prices, gathering notes, "probably known" notes.
function PT:InfoText(ahKey, book, profitable, missing)
  local profs, gather, probable = {}, {}, {}
  for _, e in ipairs(book) do
    local t = e.name .. " " .. e.skill .. (e.max and ("/" .. e.max) or "")
    if e.gathering then gather[#gather + 1] = t
    else
      profs[#profs + 1] = string.format("%s (%d recipes)", t, #e.recipes)
      if e.source == "bundled" then probable[#probable + 1] = e.name end
    end
  end
  local sub
  if #profs == 0 and #gather == 0 then
    sub = "No professions detected for this character. Open your skills or profession window, or press Refresh on the Settings tab."
  else
    sub = (#profs > 0 and table.concat(profs, ", ") or "No crafting professions") ..
      string.format("  -  %s%d profitable|r", GREEN, profitable)
  end
  local lines = {}
  local scan = UI.LastScan(ahKey)
  local warn = UI.StaleWarning(ahKey)
  if warn then lines[#lines + 1] = warn
  elseif scan then lines[#lines + 1] = string.format("Prices: %s, scanned %s. Sale value is after the %d%% auction house cut.",
    ahKey, ns.TimeAgo(scan.ts), math.floor(ns.CutFor(ahKey) * 100 + 0.5)) end
  if scan then lines[#lines + 1] = PT:AvailNote(ahKey, scan) end
  if missing > 0 then
    lines[#lines + 1] = string.format("%s%d recipe(s) have a missing price (no AH scan price and no vendor price) - shown last.|r", RED, missing)
  end
  if #probable > 0 then
    lines[#lines + 1] = string.format("%s%s: no recipes recorded yet, so these are the bundled trainer recipes up to your skill, %s.|r",
      YELLOW, table.concat(probable, ", "), PROBABLY)
  end
  if #gather > 0 then
    lines[#lines + 1] = table.concat(gather, ", ") .. ": gathering skill(s) - nothing to craft; sell what you gather (see the Market tab)."
  end
  return sub, table.concat(lines, "\n")
end

-- What "Available on AH" counts, from which scan.
function PT:AvailNote(ahKey, scan)
  local t = "Available on AH = total quantity listed in that scan (" ..
    (scan.aggregated and "browse scan: the server's total per item" or "full scan: all listings added up") .. ")."
  local scans = ns.db.scans or {}
  local newest = scans[#scans]
  if newest and newest ~= scan and not newest.complete and (not ahKey or newest.ahKey == ahKey) and newest.ts >= scan.ts then
    t = t .. " " .. YELLOW .. "A newer scan (" .. ns.TimeAgo(newest.ts) .. ") did not finish and is not used.|r"
  end
  return t
end

function PT:DetailText(r)
  if not r then return "Click a recipe to see its reagents." end
  local cut = ns.CutFor(ns.Ledger:LatestAHKey())
  local t = string.format("%s (%s), makes %s. Reagents %s, sells for %s each on the AH (%s), %s after the %d%% cut: %s.",
    ns.ItemName(r.id), r.prof, (r.minMade ~= r.maxMade) and (r.minMade .. "-" .. r.maxMade) or tostring(r.minMade),
    r.cost and ns.Money(r.cost) or "?", money(r.value),
    r.valueWhen == "now" and "latest scan" or (r.valueWhen and (r.valueWhen .. "'s median")) or "no price",
    r.revenue and ns.Money(r.revenue) or "?", math.floor(cut * 100 + 0.5), "profit " .. profitText(r))
  local ahKey = ns.Ledger:LatestAHKey()
  local q, n = PT.Available(ahKey, r.id)
  t = t .. "  Available on AH: " .. (q and (ns.IntStr(q) .. (q > 0 and n ~= q and (" in " .. ns.IntStr(n) .. " listings") or "")) or "no scan") .. "."
  if r.status == "probably known" then t = t .. "  " .. YELLOW .. "(" .. PROBABLY .. ")|r" end
  if r.recipeItem then t = t .. "  " .. YELLOW .. "(needs the recipe: " .. ns.ItemName(r.recipeItem) .. ")|r" end
  return t
end

function PT:ReagentRows(r)
  local rows = {}
  local ahKey = ns.Ledger:LatestAHKey()
  for _, rg in ipairs(r and r.reagents or {}) do
    local avail = PT.Available(ahKey, rg.id)
    local row = { ns.ItemName(rg.id), itemID = rg.id, tostring(rg.qty), money(rg.unit), whereText(rg), money(rg.cost),
      rg.ahUnit and ns.Money(rg.ahUnit) or "-", rg.vendorUnit and ns.Money(rg.vendorUnit) or "-", availText(avail) }
    row.sort = { ns.ItemName(rg.id), rg.qty or 0, rg.unit or math.huge, whereText(rg), rg.cost or math.huge,
      rg.ahUnit or math.huge, rg.vendorUnit or math.huge, avail or -1 }
    row.data = rg
    rows[#rows + 1] = row
  end
  return rows
end

UI:RegisterTab("crafts", function(p)
  -- everything sits in a vertical scroll area, so large text (2x-3x) on small screens still fits
  local W = UI.PanelW() - S(8)
  local c = UI.ScrollArea(p, UI.PanelW())
  p.child = c
  p.sub = UI.Label(c, "", "GameFontNormal")
  p.info = UI.Label(c, "", "GameFontHighlightSmall")
  p.fAll = UI.Button(c, "All professions", 120, 22, function() PT.filter = nil; PT.selected = nil; UI:Refresh() end)
  p.fbtn = {}
  p.learn = UI.CheckBox(c, "Also show profitable recipes you could learn", function(self)
    PT.showLearnable = self:GetChecked() and true or false; UI:Refresh()
  end)
  local cut = math.floor(ns.CutFor(ns.Ledger:LatestAHKey()) * 100 + 0.5)
  p.list = UI.List(c, { { "Makes", 260 }, { "Profession", 110 }, { "Status", 130 }, { "Reagent cost", 120 },
    { string.format("Sells for (after %d%% cut)", cut), 170 }, { "Profit", 110 }, { "Margin", 70 },
    { "Available on AH", 110, "On AH" } }, function(_, row)
    PT.selected = row.data and (row.data.prof .. ":" .. tostring(row.data.id))
    UI:Refresh()
  end, nil, { width = W, sortable = true })
  p.detail = UI.Label(c, "", "GameFontNormal")
  p.reagents = UI.List(c, { { "Reagent", 240 }, { "Need", 50 }, { "Cheapest each", 120 }, { "From", 140 }, { "Cost", 110 },
    { "AH price", 110 }, { "Vendor price", 110 }, { "Available on AH", 110, "On AH" } }, function(_, row)
    if row.data and ns.Shop then ns.Shop:AskAddReagent(row.data, PT.current) end
  end, nil, { width = W, sortable = true })
  p.note = UI.Label(c, "Click a recipe to see its reagents, then click a reagent to put it on your crafting list. " ..
    "Cheapest = the lower of the latest AH price and the vendor price. Click a column header to sort.", "GameFontDisableSmall")
  function p.Relayout(nRecipes, nReagents)
    local flow = { p.fAll }
    for _, b in ipairs(p.fOrder or {}) do if b:IsShown() then flow[#flow + 1] = b end end
    flow[#flow + 1] = p.learn
    local x = S(4)
    local y = UI.Stack(c, { { text = p.sub, font = "GameFontNormal" }, { text = p.info, font = "GameFontHighlightSmall" },
      { flow = flow } }, x, -S(4), W - S(8), S(4))
    -- recipe list: up to ~55% of the visible height (at least 4 rows); reagent list: all reagents (at least 3 rows)
    local visH = UI.PanelH()
    local want = p.list:HeightFor(math.max(4, math.min(nRecipes or 4, 30)))
    local listH = math.max(p.list:HeightFor(4), math.min(want, math.floor(visH * 0.55)))
    local frames = {
      { frame = p.list.frame, h = listH, w = W },
      { text = p.detail, font = "GameFontNormal" },
      { frame = p.reagents.frame, h = p.reagents:HeightFor(math.max(3, nReagents or 3)), w = W },
      { text = p.note, font = "GameFontDisableSmall" },
    }
    -- lists start at x = 0 like the other tabs; texts are indented
    y = UI.Stack(c, frames, 0, y, W, S(4))
    for _, fs in ipairs({ p.detail, p.note }) do
      local _, rel, _, _, oy = fs:GetPoint()
      if rel then fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", c, "TOPLEFT", x, oy); fs:SetWidth(W - S(8)) end
    end
    c:SetHeight(-y + S(4))
    p.list.laidOut, p.reagents.laidOut = nil, nil
  end
end, function(p)
  local ahKey = ns.Ledger:LatestAHKey()
  local rows, book, profitable, missing = PT:Rows(ahKey)
  -- profession filter buttons (crafting professions with recipes)
  p.fOrder = {}
  for _, e in ipairs(book) do
    if not e.gathering then
      local b = p.fbtn[e.name]
      if not b then
        local name = e.name
        b = UI.Button(p.child, name, 90, 22, function() PT.filter = name; PT.selected = nil; UI:Refresh() end)
        p.fbtn[name] = b
      end
      p.fOrder[#p.fOrder + 1] = b
    end
  end
  local present = {}
  for _, b in ipairs(p.fOrder) do present[b] = true end
  for name, b in pairs(p.fbtn) do
    if present[b] then b:Show() else b:Hide(); if PT.filter == name then PT.filter = nil end end
    if b.LockHighlight then if PT.filter == name then b:LockHighlight() else b:UnlockHighlight() end end
  end
  if p.fAll.LockHighlight then if PT.filter then p.fAll:UnlockHighlight() else p.fAll:LockHighlight() end end
  p.learn:SetChecked(PT.showLearnable)
  local sub, info = PT:InfoText(ahKey, book, profitable, missing)
  p.sub:SetText(sub)
  p.info:SetText(info)
  -- selection: keep the clicked recipe, else the first one
  local sel
  for i, row in ipairs(rows) do
    if PT.selected and (row.data.prof .. ":" .. tostring(row.data.id)) == PT.selected then sel = i end
  end
  PT.current = sel and rows[sel].data or nil
  p.detail:SetText(PT:DetailText(PT.current))
  p.Relayout(#rows, PT.current and #PT.current.reagents or 0)
  p.list:SetData(rows, true)
  p.list.selected = sel
  p.list:Render()
  p.reagents:SetData(PT:ReagentRows(PT.current))
end)
