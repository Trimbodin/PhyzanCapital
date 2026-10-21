-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital trading tabs: Search/Browse and Buy (selling happens in Blizzard's own auction window, 1.4.0).
-- Every server action (search query, bid, buyout) happens only inside a click handler or a confirmation
-- dialog's Accept click. There are no loops or timers that query or buy.
local _, ns = ...
local UI = ns.UI
local T = { results = {}, page = 0, total = 0, query = nil, pending = false, selected = nil }
ns.Trade = T

local QUALITIES = { { -1, "All qualities" }, { 0, "Poor" }, { 1, "Common" }, { 2, "Uncommon" }, { 3, "Rare" }, { 4, "Epic" } }
local TL_TEXT = { "< 30m", "30m - 2h", "2h - 8h", "8h - 24h" }
local PER_PAGE = NUM_AUCTION_ITEMS_PER_PAGE or 50

local function me() return (UnitName and UnitName("player")) or "" end

local function marketInfo(id)
  local ahKey = ns.ahOpen and ns.CurrentAHKey() or ns.Ledger:LatestAHKey()
  local ah = ns.AH(ahKey)
  local day = ns.MarketDay()
  local st = (ah.dailyStats[day] or {})[id] or {}
  local c = ah.current[id] or {}
  local it = ns.TouchItem(id) or {}
  return { lowest = c.minUnit, median = st.medianUnit, listedToday = st.quantity,
           sellPrice = it.sellPrice, vendorBuy = ns.Vendor:BuyPrice(id), ahKey = ahKey }
end
T.MarketInfo = marketInfo

---------------------------------------------------------------------------
-- Confirmation dialog
---------------------------------------------------------------------------
-- Yes/No through our own dialog (UI:Confirm). fn runs inside the Yes click, so PlaceBid / ConfirmCommoditiesPurchase
-- get the hardware event they need.
local function confirm(text, fn, onCancel)
  UI:Confirm({ which = "trade", text = text, onYes = function() fn() end, onNo = onCancel })
end
T.Confirm = confirm
local function modern() return ns.Backend() == "modern" end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
function T:Search(page)
  if not ns.ahOpen then ns.Print("open the auction house first."); return end
  if ns.Scanner:Busy() then ns.Print("a scan is running - wait for it to finish."); return end
  if modern() then
    if self.query then self.page = 0; ns.ModernAH:Search(self.query) end
    return
  end
  if ns.Backend() ~= "legacy" then ns.Print("no usable auction house API on this client (see /capital debug)."); return end
  local can = ns.Scanner.CanQuery()
  if not can then ns.Print("the server is throttling queries - click again in a moment."); return end
  local q = self.query
  if not q then return end
  local ok, err = pcall(QueryAuctionItems, q.name, q.minLevel, q.maxLevel, page, q.usable, q.quality, false, false, nil)
  if not ok then
    ok, err = pcall(QueryAuctionItems, q.name, q.minLevel, q.maxLevel, page, q.usable or nil,
      (q.quality ~= -1) and q.quality or nil)
  end
  if not ok then ns.Print("search failed: " .. tostring(err)); return end
  self.page = page
  self.pending = true
  self.selected = nil
  ns.CountUsage("action:search")
end

function T:ReadResults()
  local batch, total = ns.Scanner.NumItems()
  local rows = {}
  local n = math.min(batch, PER_PAGE)
  for i = 1, n do
    local r = ns.Scanner.ReadRow(i)
    if r then rows[#rows + 1] = r end
  end
  self.results = rows
  self.total = total
  self.fromFullScan = batch > PER_PAGE
  self.pending = false
  -- keep the selection only if the same auction is still at the same index
  local sel = self.selected
  if sel then
    local now = ns.Scanner.ReadRow(sel.index)
    if not (now and now.itemID == sel.itemID and now.count == sel.count and now.buyout == sel.buyout
            and now.seller == sel.seller) then
      self.selected = nil
    else
      self.selected = now
    end
  end
  if UI.frame and UI.frame:IsShown() then UI:Refresh() end
end

local readPending = false
ns.On("AUCTION_ITEM_LIST_UPDATE", function()
  if modern() or ns.Scanner:Busy() then return end
  if readPending then return end
  readPending = true
  ns.After(0.2, function() readPending = false; if ns.ahOpen then T:ReadResults() end end)
end)
ns.On("AUCTION_HOUSE_CLOSED", function()
  T.results, T.selected, T.total, T.pending = {}, nil, 0, false
end)

local function resultRows(list)
  local out = {}
  for _, r in ipairs(list) do
    local info = marketInfo(r.itemID)
    local vs = ""
    local ref = info.median or info.lowest
    if r.unit > 0 and ref and ref > 0 then vs = ns.IntStr(r.unit / ref * 100) .. "%" end
    local bidText = r.browse and "-" or (r.bid > 0) and (ns.Money(r.bid) .. (r.highBidder and " (you)" or "")) or ("min " .. ns.Money(r.minBid))
    if r.name and r.name ~= "" then ns.TouchItem(r.itemID, r.name) end
    local row = { ns.ItemName(r.itemID), itemID = r.itemID,
      tostring(r.count), bidText, r.buyout > 0 and ns.Money(r.buyout) or "-", r.unit > 0 and ns.Money(r.unit) or "-",
      vs, r.browse and "-" or (TL_TEXT[r.tl] or "?"),
      (r.browse and (r.ownItem and "(includes yours)" or "-")) or ((r.seller == me() or r.own) and (r.seller .. " (you)")) or r.seller }
    if r.browse then row[4] = "-"; row[5] = r.unit > 0 and ("from " .. ns.Money(r.unit)) or "-" end
    row.data = r
    out[#out + 1] = row
  end
  return out
end

local RESULT_COLS = { { "Item", 300 }, { "Qty", 50 }, { "Bid", 150 }, { "Buyout", 130 }, { "Per unit", 120 },
  { "vs market", 80 }, { "Time left", 90 }, { "Seller", 150 } }

---------------------------------------------------------------------------
-- Bid / buyout
---------------------------------------------------------------------------
local function nextMinBid(r)
  if r.modern then return (r.minBid and r.minBid > 0) and r.minBid or ((r.bid or 0) + 1) end
  if r.bid and r.bid > 0 then return r.bid + math.max(r.minInc or 0, 1) end
  return r.minBid
end
T.NextMinBid = nextMinBid

-- Re-reads the listing at its index and checks it is the same auction before sending the bid.
function T:PlaceBid(r, amount, isBuyout)
  if not ns.ahOpen then ns.Print("auction house is closed."); return end
  if r.modern then
    if GetMoney and GetMoney() < amount then ns.Print("not enough money."); return end
    return ns.ModernAH:PlaceBid(r, amount, isBuyout)
  end
  local now = ns.Scanner.ReadRow(r.index)
  if not (now and now.itemID == r.itemID and now.count == r.count and now.buyout == r.buyout
          and now.minBid == r.minBid and now.seller == r.seller) then
    ns.Print("that auction is no longer at the same position - search again."); return
  end
  if GetMoney and GetMoney() < amount then ns.Print("not enough money."); return end
  if type(PlaceAuctionBid) ~= "function" then ns.Print("PlaceAuctionBid is not available on this client."); return end
  local ok, err = pcall(PlaceAuctionBid, "list", r.index, amount)
  if ok then
    ns.CountUsage(isBuyout and "action:buyout" or "action:bid")
    ns.Print(string.format("%s sent: %s x%d for %s.", isBuyout and "Buyout" or "Bid", ns.ItemName(r.itemID), r.count, ns.Money(amount)))
  else
    ns.Print("bid failed: " .. tostring(err))
  end
end

function T:AskBid(r, amount)
  if not r then ns.Print("select an auction first."); return end
  if r.browse then ns.Print("pick a single auction on the Buy tab first."); return end
  if r.commodity then ns.Print("commodities cannot be bid on - use Buy quantity."); return end
  if r.seller == me() then ns.Print("you cannot bid on your own auction."); return end
  if r.highBidder then ns.Print("you are already the high bidder."); return end
  local minB = nextMinBid(r)
  if not amount or amount < minB then ns.Print("bid must be at least " .. ns.Money(minB)); return end
  if r.buyout > 0 and amount >= r.buyout then self:AskBuyout(r); return end
  confirm(string.format("Phyzan Capital\n\nBid %s on\n%s x%d\n(seller %s)?", ns.Money(amount), ns.ItemName(r.itemID), r.count, r.seller),
    function() T:PlaceBid(r, amount, false) end)
end

function T:AskBuyout(r)
  if not r then ns.Print("select an auction first."); return end
  if r.browse then ns.Print("pick a single auction on the Buy tab first."); return end
  if r.commodity then return ns.ModernAH:AskCommodity(r.itemID, r.count) end
  if r.own then ns.Print("you cannot buy your own auction."); return end
  if r.buyout <= 0 then ns.Print("this auction has no buyout."); return end
  if r.seller == me() then ns.Print("you cannot buy your own auction."); return end
  confirm(string.format("Phyzan Capital\n\nBuy out\n%s x%d\nfor %s total (%s each)?", ns.ItemName(r.itemID), r.count,
    ns.Money(r.buyout), ns.Money(r.unit)), function() T:PlaceBid(r, r.buyout, true) end)
end

---------------------------------------------------------------------------
-- Search tab
---------------------------------------------------------------------------
UI:RegisterTab("search", function(p)
  local S = UI.S
  local W = UI.PanelW()
  -- controls scroll when they need more than half the tab (very large text on a small screen)
  p.top = CreateFrame("Frame", nil, p)
  p.top:SetPoint("TOPLEFT", 0, 0)
  p.top:SetPoint("TOPRIGHT", 0, 0)
  local c = UI.ScrollArea(p.top, W)
  local l = UI.Label(c, "Name", "GameFontNormal")
  p.name = UI.EditBox(c, 220)
  p.name:SetWidth(math.min(p.name:GetWidth(), math.floor(W * 0.35)))
  local ll = UI.Label(c, "Level", "GameFontNormal")
  p.minL = UI.EditBox(c, 36, true)
  local dash = UI.Label(c, "-")
  p.maxL = UI.EditBox(c, 36, true)
  p.qIdx = 1
  p.quality = UI.Button(c, "All qualities", 130, 22, function(self) -- sized for the widest quality name
    p.qIdx = p.qIdx % #QUALITIES + 1
    self:SetText(QUALITIES[p.qIdx][2])
  end)
  p.quality:SetText(QUALITIES[1][2])
  p.usable = UI.CheckBox(c, "Usable only")
  local function doSearch()
    T.query = { name = p.name:GetText() or "", minLevel = tonumber(p.minL:GetText()), maxLevel = tonumber(p.maxL:GetText()),
                quality = QUALITIES[p.qIdx][1], usable = p.usable:GetChecked() and true or false }
    T:Search(0)
  end
  p.name:SetScript("OnEnterPressed", function(self) self:ClearFocus(); doSearch() end)
  p.go = UI.Button(c, "Search", 100, 22, doSearch)
  p.prev = UI.Button(c, "< Prev", 80, 22, function()
    if modern() then return end
    if T.query and T.page > 0 then T:Search(T.page - 1) end
  end)
  p.next = UI.Button(c, "Next >", 80, 22, function()
    if modern() then ns.ModernAH:SearchMore(); return end
    if T.query and (T.page + 1) * PER_PAGE < T.total then T:Search(T.page + 1) end
  end)
  p.pageText = UI.Label(c, "")

  p.toBuy = UI.Button(c, "Details / custom bid", 170, 24, function() UI:Show("buy") end)
  p.bid = UI.Button(c, "Bid (minimum)...", 140, 24, function()
    if T.selected then T:AskBid(T.selected, nextMinBid(T.selected)) else ns.Print("select an auction first.") end
  end)
  p.buyout = UI.Button(c, "Buy out...", 110, 24, function() T:AskBuyout(T.selected) end)
  p.lookup = UI.Button(c, "Price lookup (saved scans)", 200, 24, function() UI:Show("prices") end)
  p.sel = UI.Label(c, "", "GameFontHighlight")
  local blocks = {
    { flow = { l, p.name, ll, p.minL, dash, p.maxL, p.quality, p.usable, p.go, p.prev, p.next, p.toBuy, p.bid, p.buyout, p.lookup } },
    { text = p.pageText, font = "GameFontHighlight", nowrap = true },
    { text = p.sel, font = "GameFontHighlight", nowrap = true },
  }
  local h = -UI.Stack(c, blocks, S(4), -S(4), W - S(28), S(6))
  c:SetHeight(h)
  p.top:SetHeight(math.min(h, math.floor(UI.PanelH() * 0.4)))
  local y = -p.top:GetHeight()
  p.list = UI.List(p, RESULT_COLS, function(_, row)
    T.selected = row.data
    if row.data.browse then -- modern: one row per item; open its auctions on the Buy tab (click-triggered query)
      ns.ModernAH:Drill(row.data)
      UI:Show("buy")
    else
      UI:Refresh()
    end
    -- after the selection: "Add <item> to crafting list?" (never replaces a bid / buyout question)
    if ns.Shop and row.data.itemID then ns.Shop:AskAddItem(row.data.itemID) end
  end)
  p.list.frame:SetPoint("TOPLEFT", 0, y)
  p.list.frame:SetPoint("BOTTOMRIGHT", 0, S(4))
end, function(p)
  local rows = resultRows(T.results)
  p.list:SetData(rows, true)
  p.list.selected = nil
  if T.selected then
    for i, r in ipairs(rows) do if r.data.index == T.selected.index then p.list.selected = i end end
  end
  p.list:Render()
  local pages = math.max(1, math.ceil((T.total or 0) / PER_PAGE))
  if T.pending then p.pageText:SetText("searching...")
  elseif modern() then p.pageText:SetText(string.format("%d items%s - click an item to see its auctions", T.total or 0,
    T.modernFull and "" or " (more: Next >)"))
  elseif T.fromFullScan then p.pageText:SetText("showing first 50 of the full-scan list - run a search")
  else p.pageText:SetText(string.format("page %d / %d  (%d results)", T.page + 1, pages, T.total or 0)) end
  local s = T.selected
  if s and s.browse then s = nil end
  p.sel:SetText(s and string.format("Selected: %s x%d  -  buyout %s (%s each), next bid %s", ns.ItemName(s.itemID), s.count,
    s.buyout > 0 and ns.Money(s.buyout) or "none", s.unit > 0 and ns.Money(s.unit) or "-", ns.Money(nextMinBid(s)))
    or "Click a row to select an auction.")
end)

---------------------------------------------------------------------------
-- Buy tab: selected auction details, custom bid, other listings of the same item on this page
---------------------------------------------------------------------------
UI:RegisterTab("buy", function(p)
  local S = UI.S
  p.W = UI.PanelW()
  -- top part (details, bid controls) scrolls if it is taller than ~55% of the tab; the list gets the rest
  p.top = CreateFrame("Frame", nil, p)
  p.top:SetPoint("TOPLEFT", 0, 0)
  p.top:SetPoint("TOPRIGHT", 0, 0)
  p.top:SetHeight(S(200))
  local c = UI.ScrollArea(p.top, p.W)
  p.child = c
  p.info = UI.Label(c, "", "GameFontHighlightLarge")
  p.info:SetJustifyV("TOP")
  local bl = UI.Label(c, "Your bid (e.g. 1g 20s):", "GameFontNormal")
  p.amount = UI.EditBox(c, 140)
  p.bid = UI.Button(c, "Place bid...", 120, 24, function() T:AskBid(T.selected, ns.ParseMoney(p.amount:GetText())) end)
  p.buyout = UI.Button(c, "Buy out...", 120, 24, function() T:AskBuyout(T.selected) end)
  p.back = UI.Button(c, "Back to search", 140, 24, function() UI:Show("search") end)
  -- modern commodities: buy N units at the current cheapest prices (server quote, then confirm)
  p.qtyLabel = UI.Label(c, "Quantity:", "GameFontNormal")
  p.qty = UI.EditBox(c, 60, true)
  p.buyQty = UI.Button(c, "Buy quantity...", 130, 24, function()
    local d = ns.ModernAH.drill
    if d then ns.ModernAH:AskCommodity(d.itemID, tonumber(p.qty:GetText())) end
  end)
  local ol = UI.Label(c, "Other listings of this item on the current results page (click to select):", "GameFontNormal")
  p.otherLabel = ol
  p.blocks = { { text = p.info, font = "GameFontHighlightLarge" },
    { flow = { bl, p.amount, p.bid, p.buyout, p.back, p.qtyLabel, p.qty, p.buyQty } },
    { text = ol, font = "GameFontNormal" } }
  p.list = UI.List(p, RESULT_COLS, function(_, row) T.selected = row.data; p.lastSel = nil; UI:Refresh() end)
  p.list.frame:SetPoint("TOPLEFT", p.top, "BOTTOMLEFT", 0, -S(4))
  p.list.frame:SetPoint("BOTTOMRIGHT", 0, S(4))
  -- re-flow after every text change (info has 1-5 lines)
  function p.Relayout()
    local h = -UI.Stack(c, p.blocks, S(4), -S(4), p.W - S(28), S(6))
    c:SetHeight(h)
    local maxTop = math.floor(UI.PanelH() * 0.45)
    p.top:SetHeight(math.min(h, maxTop))
    p.list.laidOut = nil
  end
  p.Relayout()
end, function(p)
  local d = modern() and ns.ModernAH.drill
  local showQty = d and d.commodity and true or false
  for _, w in ipairs({ p.qtyLabel, p.qty, p.buyQty }) do if showQty then w:Show() else w:Hide() end end
  if d then
    p.otherLabel:SetText(d.pending and ("Loading auctions of " .. ns.ItemName(d.itemID) .. "...")
      or (d.commodity and "Price tiers (commodity - use Quantity + Buy quantity, or click a tier and Buy out):"
      or "All auctions of this item (click to select):"))
    local rows = resultRows(d.listings)
    p.list:SetData(rows, true)
    p.list.selected = nil
    local sel = T.selected
    if sel and sel.modern then
      for i, r in ipairs(rows) do if r.data.auctionID == sel.auctionID and r.data.unit == sel.unit then p.list.selected = i end end
    end
    p.list:Render()
    if not (sel and sel.modern) then
      p.info:SetText(ns.ItemName(d.itemID) .. "\nClick an auction below to select it.")
      return
    end
  elseif modern() then
    p.otherLabel:SetText("Select an item on the Search / Browse tab.")
  else
    p.otherLabel:SetText("Other listings of this item on the current results page (click to select):")
  end
  local s = T.selected
  if s and s.browse then s = nil end
  if not s then
    p.info:SetText("No auction selected. Search on the Search / Browse tab and click a row.")
    p.list:SetData({})
    return
  end
  local m = marketInfo(s.itemID)
  p.info:SetText(string.format(
    "%s  x%d\nSeller: %s     Time left: %s\nMinimum bid: %s     Current bid: %s%s     Next bid at least: %s\n" ..
    "Buyout: %s  (%s per unit)\nMarket: lowest now %s, median today %s, vendor pays %s each",
    ns.ItemName(s.itemID), s.count, s.seller, TL_TEXT[s.tl] or "?", ns.Money(s.minBid),
    s.bid > 0 and ns.Money(s.bid) or "none", s.highBidder and " (you)" or "", ns.Money(nextMinBid(s)),
    s.buyout > 0 and ns.Money(s.buyout) or "none", s.unit > 0 and ns.Money(s.unit) or "-",
    ns.Money(m.lowest), ns.Money(m.median), ns.Money(m.sellPrice)))
  local selKey = s.auctionID or s.index
  if p.lastSel ~= selKey then p.amount:SetText(ns.MoneyInput(nextMinBid(s))); p.lastSel = selKey end
  if d then return end
  local same = {}
  for _, r in ipairs(T.results) do if r.itemID == s.itemID then same[#same + 1] = r end end
  table.sort(same, function(a, b) return (a.unit > 0 and a.unit or math.huge) < (b.unit > 0 and b.unit or math.huge) end)
  local rows = resultRows(same)
  p.list:SetData(rows, true)
  p.list.selected = nil
  for i, r in ipairs(rows) do if r.data.index == s.index then p.list.selected = i end end
  p.list:Render()
end)

-- re-flow the Buy form after each refresh (its texts change height)
for _, key in ipairs({ "buy" }) do
  local b = UI.builders[key]
  local refresh = b.refresh
  b.refresh = function(p)
    local ok, err = pcall(refresh, p)
    if p.Relayout then p.Relayout() end
    if not ok then error(err, 0) end
  end
end
