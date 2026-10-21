-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital modern auction backend (retail-style C_AuctionHouse API, AuctionHouseFrame).
-- Used when ns.Backend() == "modern". Every query, bid and purchase is started from a click
-- (scan button, search/next buttons, or a confirmation dialog's Accept). Nothing runs in a loop.
--   Full scan:   C_AuctionHouse.ReplicateItems() -> REPLICATE_ITEM_LIST_UPDATE -> GetReplicateItemInfo(0..n-1)
--   Fallback:    SendBrowseQuery("") -> AUCTION_HOUSE_BROWSE_RESULTS_UPDATED/ADDED -> GetBrowseResults()
--                (one row per item: lowest unit price + total quantity; stored as an "aggregated" scan),
--                more results per click via RequestMoreBrowseResults() until HasFullBrowseResults().
--   Search/Buy:  SendBrowseQuery, SendSearchQuery(itemKey) -> ITEM_/COMMODITY_SEARCH_RESULTS_UPDATED,
--                PlaceBid(auctionID, amount), StartCommoditiesPurchase -> COMMODITY_PRICE_UPDATED -> Confirm...
local _, ns = ...
local M = { owner = nil, drill = nil }
ns.ModernAH = M

local COOLDOWN = 15 * 60
local function CA() return C_AuctionHouse end
local function has(name) local c = CA(); return type(c) == "table" and type(c[name]) == "function" end
M.Has = has

local function pack(...) return { n = select("#", ...), ... } end

local function sorts()
  local E = Enum and Enum.AuctionHouseSortOrder
  if not E then return {} end
  return { { sortOrder = E.Price, reverseSort = false }, { sortOrder = E.Name, reverseSort = false } }
end

function M:FullScanAvailability()
  if not has("ReplicateItems") then return "full scan (ReplicateItems) not available - a click starts a browse scan" end
  local last = ns.db.lastReplicateTs
  if last and time() - last < COOLDOWN then
    return string.format("full scan available in ~%d min - a click now starts a browse scan",
      math.ceil((COOLDOWN - (time() - last)) / 60))
  end
  return "full scan available (shift-click: browse scan)"
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
local requested = {}
local function requestItemLoad(id)
  if requested[id] then return end
  requested[id] = true
  if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
    pcall(C_Item.RequestLoadItemDataByID, id)
  elseif Item and type(Item.CreateFromItemID) == "function" then
    pcall(function() Item:CreateFromItemID(id):ContinueOnItemLoad(function() ns.TouchItem(id) end) end)
  end
end

-- Replicate row i (1-based for the generic reader; the API is 0-based).
local function readReplicate(i)
  local idx = i - 1
  local r = pack(pcall(CA().GetReplicateItemInfo, idx))
  if not r[1] then return nil end
  local name, count, quality, minBid, minInc, buyout, bid, highBidder, owner, itemID, hasAll =
    r[2], r[4], r[5], r[9], r[10], r[11], r[12], r[13], r[15], r[18], r[19]
  if not itemID and has("GetReplicateItemLink") then
    local ok, link = pcall(CA().GetReplicateItemLink, idx)
    if ok then itemID = ns.ItemIDFromLink(link) end
  end
  if not itemID or not count or count < 1 then return nil end
  if hasAll == false then requestItemLoad(itemID) end
  local tl = 0
  if has("GetReplicateItemTimeLeft") then
    local ok, v = pcall(CA().GetReplicateItemTimeLeft, idx)
    if ok and type(v) == "number" then tl = v end
  end
  buyout = buyout or 0
  return { itemID = itemID, name = name, quality = quality, count = count, minBid = minBid or 0, buyout = buyout,
    unit = buyout > 0 and math.max(1, math.floor(buyout / count + 0.5)) or 0, tl = tl, seller = owner or "",
    bid = bid or 0, minInc = minInc or 0, highBidder = highBidder and true or false, index = i }
end

-- Time-left bands: some clients return 0..3 (Enum.AuctionHouseTimeLeftBand), others 1..4. Normalize to 1..4.
local function normalizeTL(rows)
  local minTL = math.huge
  for _, r in ipairs(rows) do if r.tl < minTL then minTL = r.tl end end
  local shift = (minTL == 0) and 1 or 0
  for _, r in ipairs(rows) do r.tl = math.min(4, math.max(1, r.tl + shift)) end
end

function M:ScanClick(button)
  local S = ns.Scanner
  if not ns.ahOpen then S:Fail("open the auction house first"); return end
  if S.state == "idle" then
    local forceBrowse = IsShiftKeyDown and IsShiftKeyDown()
    local last = ns.db.lastReplicateTs
    if has("ReplicateItems") and not forceBrowse and not (last and time() - last < COOLDOWN) then
      S:Begin("replicate")
      local ok, err = pcall(CA().ReplicateItems)
      if not ok then S.state = "reading"; S:Abort("ReplicateItems failed: " .. tostring(err)); return end
      ns.db.lastReplicateTs = time()
      S.state = "waiting"
      ns.Print("full scan requested (ReplicateItems) - the client may freeze for a few seconds while the server answers.")
      self.rep = { requestTs = time(), events = 0, checks = 0 }
      self:CheckReplicate(false) -- starts the 2s poll; data already cached by the client is picked up too
    elseif has("SendBrowseQuery") then
      if last and time() - last < COOLDOWN and not forceBrowse then
        ns.Print("full scan is on cooldown - running a browse scan (lowest price + quantity per item).")
      end
      self:StartBrowseScan()
    else
      S:Fail("neither C_AuctionHouse.ReplicateItems nor SendBrowseQuery is usable")
    end
  elseif S.state == "paged" and S.mode == "browse" then
    if not has("RequestMoreBrowseResults") then S:Finish(false, "RequestMoreBrowseResults is missing"); return end
    self.owner = "scan"
    local ok, err = pcall(CA().RequestMoreBrowseResults)
    if not ok then S:Abort("RequestMoreBrowseResults failed: " .. tostring(err)); return end
    S.state = "waiting"
  else
    ns.Print("scan in progress (" .. tostring(S.state) .. "). Right-click to abort.")
  end
end

-- REPLICATE_ITEM_LIST_UPDATE can fire before the data is there (count 0), and the count can still grow
-- for a moment after the first event. So: re-check on every event and poll every 2s (a read, not a query)
-- for up to REPLICATE_WAIT seconds after the request; start reading once the count is > 0 and unchanged
-- between two checks. Only a count that stays 0 for the whole wait is reported as "server returned 0 auctions".
local REPLICATE_WAIT = 60
local function numReplicate()
  local ok, n = pcall(CA().GetNumReplicateItems)
  if not ok then return nil, n end
  return tonumber(n) or 0
end

function M:CheckReplicate(fromEvent)
  local S = ns.Scanner
  if S.state ~= "waiting" or S.mode ~= "replicate" then return end
  local info = self.rep
  if not info then return end
  if fromEvent then info.events = info.events + 1 end
  local n, err = numReplicate()
  if not n then S:Abort("GetNumReplicateItems failed: " .. tostring(err)); return end
  info.lastCount = n
  pcall(ns.DebugSet, "replicate", { requestTs = info.requestTs, events = info.events, lastCount = n, checks = info.checks })
  -- wait for the server's event (a count read right after the request may still be the previous list),
  -- unless the event seems to be missing entirely and data has been sitting there for 10s
  local ready = n > 0 and info.prevCount == n and (info.events > 0 or time() - info.requestTs >= 10)
  if ready then
    self.rep = nil
    S.postProcess = normalizeTL
    S:StartReading(n, readReplicate, function() return numReplicate() or -1 end, true)
    return
  end
  info.prevCount = n
  if time() - info.requestTs >= REPLICATE_WAIT then
    self.rep = nil
    if info.events == 0 then
      S:Abort(string.format("the server sent no REPLICATE_ITEM_LIST_UPDATE within %ds (throttled?) - click again for a browse scan", REPLICATE_WAIT))
    else
      S:Abort(string.format("server returned 0 auctions (%d updates in %ds)", info.events, REPLICATE_WAIT))
    end
    return
  end
  if not info.polling then
    info.polling = true
    local token = S.token
    ns.After(n > 0 and 0.5 or 2, function()
      info.polling = false
      info.checks = info.checks + 1
      if S.token == token and self.rep == info then self:CheckReplicate(false) end
    end)
  end
end

function M:OnReplicate() self:CheckReplicate(true) end

function M:BrowseQuery(text, filters, minLevel, maxLevel)
  local q = { searchString = text or "", sorts = sorts(), filters = filters or {}, itemClassFilters = {} }
  if minLevel then q.minLevel = minLevel end
  if maxLevel then q.maxLevel = maxLevel end
  return pcall(CA().SendBrowseQuery, q)
end

local function browseRows()
  local ok, list = pcall(CA().GetBrowseResults)
  if not ok or type(list) ~= "table" then return nil, tostring(list) end
  local rows = {}
  for _, b in ipairs(list) do
    local key = b.itemKey
    local id = key and key.itemID
    if id and b.minPrice then
      rows[#rows + 1] = { itemID = id, count = b.totalQuantity or 0, minBid = 0, buyout = b.minPrice, unit = b.minPrice,
        tl = 0, seller = "", bid = 0, browse = true, itemKey = key, ownItem = b.containsOwnerItem }
    end
  end
  return rows
end
M.BrowseRows = browseRows

local function fullBrowse()
  if not has("HasFullBrowseResults") then return true end
  local ok, v = pcall(CA().HasFullBrowseResults)
  return ok and v and true or false
end

function M:StartBrowseScan()
  local S = ns.Scanner
  S:Begin("browse")
  S.aggregated = true
  self.owner = "scan"
  local ok, err = self:BrowseQuery("")
  if not ok then S.state = "reading"; S:Abort("SendBrowseQuery failed: " .. tostring(err)); return end
  S.state = "waiting"
  local token = S.token
  ns.After(30, function()
    if S.state == "waiting" and S.mode == "browse" and S.token == token then
      S:Abort("no browse results from the server within 30s")
    end
  end)
end

function M:OnBrowseResults()
  local S = ns.Scanner
  if self.owner == "scan" and S.mode == "browse" and (S.state == "waiting" or S.state == "paged") then
    local rows, err = browseRows()
    if not rows then S:Abort("GetBrowseResults failed: " .. tostring(err)); return end
    S.rows = rows
    if fullBrowse() then S:Finish(true) else S.state = "paged"; S:UpdateButton() end
    if ns.UI then ns.UI:UpdateStatus() end
  elseif self.owner == "search" then
    local T = ns.Trade
    local rows = browseRows() or {}
    T.results, T.total, T.page, T.pending, T.fromFullScan = rows, #rows, 0, false, false
    T.modernFull = fullBrowse()
    if ns.UI then ns.UI:Refresh() end
  end
end

---------------------------------------------------------------------------
-- Search / drill-down / buy
---------------------------------------------------------------------------
local QUALITY_FILTER = { [0] = "PoorQuality", [1] = "CommonQuality", [2] = "UncommonQuality", [3] = "RareQuality", [4] = "EpicQuality" }

function M:Search(q)
  local S = ns.Scanner
  if not has("SendBrowseQuery") then ns.Print("SendBrowseQuery is not available on this client."); return end
  if S.state == "paged" and S.mode == "browse" then S:Finish(false, "interrupted by a search") end
  local filters = {}
  local F = Enum and Enum.AuctionHouseFilter
  if F then
    if q.usable and F.UsableOnly then filters[#filters + 1] = F.UsableOnly end
    if q.quality and q.quality >= 0 and F[QUALITY_FILTER[q.quality]] then filters[#filters + 1] = F[QUALITY_FILTER[q.quality]] end
  end
  self.owner = "search"
  local ok, err = self:BrowseQuery(q.name, filters, q.minLevel, q.maxLevel)
  if not ok then ns.Print("search failed: " .. tostring(err)); return end
  ns.Trade.pending = true
  ns.Trade.selected = nil
  self.drill = nil
  ns.CountUsage("action:search")
end

function M:SearchMore()
  if not has("RequestMoreBrowseResults") or ns.Trade.modernFull then return end
  self.owner = "search"
  local ok, err = pcall(CA().RequestMoreBrowseResults)
  if not ok then ns.Print("more results failed: " .. tostring(err)) else ns.Trade.pending = true end
end

local function isCommodity(key)
  if has("GetItemKeyInfo") then
    local ok, info = pcall(CA().GetItemKeyInfo, key)
    if ok and type(info) == "table" and info.isCommodity ~= nil then return info.isCommodity end
  end
  return nil
end

-- Drill into one item: all its auctions (items) or price tiers (commodities).
function M:Drill(row)
  if not row or not row.itemKey then return end
  if not has("SendSearchQuery") then ns.Print("SendSearchQuery is not available."); return end
  self.drill = { itemKey = row.itemKey, itemID = row.itemID, commodity = isCommodity(row.itemKey), listings = {}, pending = true }
  local ok, err = pcall(CA().SendSearchQuery, row.itemKey, sorts(), true)
  if not ok then ns.Print("item search failed: " .. tostring(err)); self.drill.pending = false end
  ns.CountUsage("action:drill")
end

local function sameKey(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  return a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0) and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end

function M:OnItemResults(itemKey)
  local d = self.drill
  if not d or (itemKey and not sameKey(itemKey, d.itemKey)) then return end
  local ok, n = pcall(CA().GetNumItemSearchResults, d.itemKey)
  if not ok then ns.Print("GetNumItemSearchResults failed: " .. tostring(n)); return end
  local list = {}
  for i = 1, (n or 0) do
    local ok2, r = pcall(CA().GetItemSearchResultInfo, d.itemKey, i)
    if ok2 and type(r) == "table" and r.auctionID then
      local qty = r.quantity or 1
      local buyout = r.buyoutAmount or 0
      list[#list + 1] = { modern = true, auctionID = r.auctionID, itemID = d.itemID, count = qty, buyout = buyout,
        unit = buyout > 0 and math.floor(buyout / qty + 0.5) or 0, bid = r.bidAmount or 0, minBid = r.minBid or 0,
        tl = (r.timeLeft or 0) + 1, seller = (r.owners and r.owners[1]) or "", highBidder = false,
        own = r.containsOwnerItem and true or false }
    end
  end
  d.listings, d.pending, d.commodity = list, false, false
  if ns.UI then ns.UI:Refresh() end
end

function M:OnCommodityResults(itemID)
  local d = self.drill
  if not d or (itemID and itemID ~= d.itemID) then return end
  local ok, n = pcall(CA().GetNumCommoditySearchResults, d.itemID)
  if not ok then ns.Print("GetNumCommoditySearchResults failed: " .. tostring(n)); return end
  local list = {}
  for i = 1, (n or 0) do
    local ok2, r = pcall(CA().GetCommoditySearchResultInfo, d.itemID, i)
    if ok2 and type(r) == "table" then
      local secs = r.timeLeftSeconds or 0
      local tl = (secs < 1800 and 1) or (secs < 7200 and 2) or (secs < 28800 and 3) or 4
      list[#list + 1] = { modern = true, commodity = true, auctionID = r.auctionID, itemID = d.itemID, count = r.quantity or 0,
        unit = r.unitPrice or 0, buyout = (r.unitPrice or 0) * (r.quantity or 0), bid = 0, minBid = 0, tl = tl,
        seller = (r.owners and r.owners[1]) or "", own = (r.numOwnerItems or 0) > 0 }
    end
  end
  d.listings, d.pending, d.commodity = list, false, true
  if ns.UI then ns.UI:Refresh() end
end

function M:PlaceBid(r, amount, isBuyout)
  if not has("PlaceBid") then ns.Print("C_AuctionHouse.PlaceBid is not available."); return end
  local ok, err = pcall(CA().PlaceBid, r.auctionID, amount)
  if ok then
    ns.CountUsage(isBuyout and "action:buyout" or "action:bid")
    ns.Print(string.format("%s sent: %s x%d for %s.", isBuyout and "Buyout" or "Bid", ns.ItemName(r.itemID), r.count, ns.Money(amount)))
  else
    ns.Print("bid failed: " .. tostring(err))
  end
end

-- Commodities: step 1 (click) asks the server for a price quote; step 2 (Accept in the dialog) confirms.
function M:AskCommodity(itemID, qty)
  if not has("StartCommoditiesPurchase") or not has("ConfirmCommoditiesPurchase") then
    ns.Print("commodity purchase API is not available."); return
  end
  if not qty or qty < 1 then ns.Print("enter a quantity."); return end
  local ok, err = pcall(CA().StartCommoditiesPurchase, itemID, qty)
  if not ok then ns.Print("commodity purchase failed: " .. tostring(err)); return end
  self.purchase = { itemID = itemID, qty = qty }
  ns.Print("getting a price quote for " .. qty .. " x " .. ns.ItemName(itemID) .. "...")
end

function M:OnCommodityPrice(unitPrice, totalPrice)
  local p = self.purchase
  if not p then return end
  ns.Trade.Confirm(string.format("Phyzan Capital\n\nBuy %d x %s\nfor %s total (%s each)?", p.qty, ns.ItemName(p.itemID),
    ns.Money(totalPrice), ns.Money(unitPrice)), function()
      local ok, err = pcall(CA().ConfirmCommoditiesPurchase, p.itemID, p.qty)
      if ok then ns.CountUsage("action:buycommodity"); ns.Print("purchase confirmed.") else ns.Print("purchase failed: " .. tostring(err)) end
      self.purchase = nil
    end, function()
      if has("CancelCommoditiesPurchase") then pcall(CA().CancelCommoditiesPurchase) end
      self.purchase = nil
    end)
end

---------------------------------------------------------------------------
-- No posting (1.4.0). WoW Forever ignores PostItem / PostCommodity from add-on code (see README), so selling is
-- done in Blizzard's own auction house window; the add-on has no Sell tab any more.
-- ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN are still kept in debug.blocked (last 20) for diagnostics.
---------------------------------------------------------------------------
function M:OnBlocked(event, addon, fn)
  local d = ns.db and ns.db.debug
  if ns.db and type(d) ~= "table" then ns.db.debug = {}; d = ns.db.debug end
  if d then
    d.blocked = type(d.blocked) == "table" and d.blocked or {}
    table.insert(d.blocked, { t = time(), event = event, addon = tostring(addon), fn = tostring(fn) })
    while #d.blocked > 20 do table.remove(d.blocked, 1) end
  end
  if tostring(addon) == "PhyzanCapital" then
    ns.Print("|cffff6060The game blocked|r " .. tostring(fn) .. " (blamed on Phyzan Capital).")
  end
end

---------------------------------------------------------------------------
local function modern() return ns.Backend() == "modern" end
ns.On("REPLICATE_ITEM_LIST_UPDATE", function() if modern() then M:OnReplicate() end end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() if modern() then M:OnBrowseResults() end end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function() if modern() then M:OnBrowseResults() end end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(_, key) if modern() then M:OnItemResults(key) end end)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, id) if modern() then M:OnCommodityResults(id) end end)
ns.On("COMMODITY_PRICE_UPDATED", function(_, unit, total) if modern() then M:OnCommodityPrice(unit, total) end end)
ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
  if M.purchase then ns.Print("price no longer available - search again."); M.purchase = nil end
end)
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
  ns.On(ev, function(event, addon, fn) M:OnBlocked(event, addon, fn) end)
end
for _, ev in ipairs({ "MACRO_ACTION_BLOCKED", "MACRO_ACTION_FORBIDDEN" }) do
  ns.On(ev, function(event, fn) M:OnBlocked(event, "macro", fn) end)
end
ns.On("AUCTION_HOUSE_CLOSED", function()
  M.drill, M.purchase, M.owner = nil, nil, nil
end)
