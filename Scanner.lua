-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital Scanner: "Scan Auction House" button (our window and Blizzard's AH frame) and scan status.
-- Every query is sent from the button's OnClick (a hardware event). Nothing is ever bought or bid on.
--   * Left-click when a full scan is allowed (CanSendAuctionQuery() 2nd return): one getAll query, then the
--     results are read in small chunks per frame to avoid freezing the client.
--   * Otherwise: paged scan, one page (50 listings) per click.
--   * Right-click: abort the current scan (partial data is saved as an incomplete scan, not used for stats).
local _, ns = ...
local S = { state = "idle" } -- idle | waiting | reading | paged
ns.Scanner = S

local PER_PAGE = NUM_AUCTION_ITEMS_PER_PAGE or 50
local CHUNK = 300        -- rows read per frame during a getAll scan
local MAX_RETRIES = 3    -- passes over rows whose item info was not loaded yet

local function canQuery()
  if type(CanSendAuctionQuery) ~= "function" then return false, false end
  local ok, a, b = pcall(CanSendAuctionQuery)
  if not ok then return false, false end
  return a and true or false, b and true or false
end
S.CanQuery = canQuery

local function sendQuery(page, getAll)
  if type(QueryAuctionItems) ~= "function" then return false, "QueryAuctionItems is not available" end
  -- Classic Era signature: (text, minLevel, maxLevel, page, usable, rarity, getAll, exactMatch, filterData)
  local ok, err = pcall(QueryAuctionItems, "", nil, nil, page, false, -1, getAll and true or false, false, nil)
  if not ok then
    ok, err = pcall(QueryAuctionItems, "", nil, nil, page, nil, nil, getAll and true or false)
  end
  return ok, err
end

-- Read one listing. Handles both the Classic Era return layout (with levelColHeader, itemId, hasAllInfo)
-- and the old 1.12 layout as a fallback.
local function readRow(i)
  if type(GetAuctionItemInfo) ~= "function" then return nil end
  local r = { pcall(GetAuctionItemInfo, "list", i) }
  if not r[1] then return nil end
  local name, count, quality, minBid, minInc, buyout, bid, highBidder, owner, itemID
  local level = r[7]
  if type(r[8]) == "number" then -- 1.12 layout: name,tex,count,quality,canUse,level,minBid,minInc,buyout,bid,highBidder,owner
    name, count, quality, minBid, minInc, buyout, bid, highBidder, owner = r[2], r[4], r[5], r[8], r[9], r[10], r[11], r[12], r[13]
  else                            -- Classic Era: ...,level,levelColHeader,minBid,minInc,buyout,bid,highBidder,bidderFull,owner,ownerFull,saleStatus,itemId,hasAllInfo
    name, count, quality, minBid, minInc, buyout, bid, highBidder, owner, itemID =
      r[2], r[4], r[5], r[9], r[10], r[11], r[12], r[13], r[15], r[18]
  end
  if not itemID and type(GetAuctionItemLink) == "function" then
    local ok, link = pcall(GetAuctionItemLink, "list", i)
    if ok then itemID = ns.ItemIDFromLink(link) end
  end
  if not itemID or not count or count < 1 then return nil end
  local tl = 0
  if type(GetAuctionItemTimeLeft) == "function" then
    local ok, v = pcall(GetAuctionItemTimeLeft, "list", i)
    if ok and v then tl = v end
  end
  buyout = buyout or 0
  return { itemID = itemID, name = name, quality = quality, count = count, minBid = minBid or 0,
           buyout = buyout, unit = buyout > 0 and math.max(1, math.floor(buyout / count + 0.5)) or 0,
           tl = tl, seller = owner or "", bid = bid or 0, minInc = minInc or 0,
           highBidder = (highBidder and highBidder ~= 0) and true or false, level = level, index = i }
end
S.ReadRow = readRow
S.SendQuery = sendQuery

-- true while a scan query/reading is in flight (searches must wait so results are not mixed up)
function S:Busy()
  return self.state == "waiting" or self.state == "reading" or self.state == "pagedReading"
end

local function numItems()
  if type(GetNumAuctionItems) ~= "function" then return 0, 0 end
  local ok, batch, total = pcall(GetNumAuctionItems, "list")
  if not ok then return 0, 0 end
  return batch or 0, total or batch or 0
end

S.NumItems = numItems

---------------------------------------------------------------------------
-- Buttons (one on Blizzard's AuctionFrame, one in the Phyzan Capital window)
---------------------------------------------------------------------------
S.buttons = {}
function S:AddButton(b) table.insert(self.buttons, b); self:UpdateButton() end

function S:UpdateButton()
  for _, b in ipairs(self.buttons) do self:UpdateOne(b) end
end

function S:UpdateOne(b)
  if self.state == "idle" then b:SetText("Scan Auction House")
  elseif self.state == "paged" and self.mode == "browse" then b:SetText("Scan more")
  elseif self.state == "paged" then b:SetText(string.format("Scan next page (%d/%d)", self.page + 2, self.numPages))
  else b:SetText("Scanning...") end
end

-- Human-readable scan status for the status panel. Returns text, state ("idle"|"scanning"|"complete"|"failed").
function S:StatusText()
  local _, all = canQuery()
  if self.state == "waiting" then
    if self.mode == "replicate" then return "Scanning: waiting for the server to send the full auction list (ReplicateItems)...", "scanning" end
    if self.mode == "browse" then return string.format("Scanning: browse query sent, %d items so far...", #(self.rows or {})), "scanning" end
    return (self.mode == "getAll") and "Scanning: waiting for the server to send the full auction list..."
      or string.format("Scanning: waiting for page %d...", self.page + 1), "scanning"
  elseif self.state == "reading" then
    local done = math.max(0, (self.index or 1) - 1)
    return string.format("Scanning: reading %d of %d rows (%d%%)", done, self.total or 0,
      (self.total or 0) > 0 and math.floor(100 * done / self.total) or 0), "scanning"
  elseif self.state == "pagedReading" then
    return string.format("Scanning: reading page %d of %d", self.page + 1, self.numPages or 1), "scanning"
  elseif self.state == "paged" and self.mode == "browse" then
    return string.format("Browse scan: %d items so far - click 'Scan more' for the next batch, right-click to stop", #(self.rows or {})), "scanning"
  elseif self.state == "paged" then
    return string.format("Paged scan: page %d of %d read (%d rows, %d%%) - click 'Scan next page' to continue, right-click to stop",
      self.page + 1, self.numPages, #(self.rows or {}), math.floor(100 * (self.page + 1) / math.max(1, self.numPages))), "scanning"
  end
  local r = self.lastResult
  local mode
  if ns.Backend() == "modern" then mode = ns.ModernAH:FullScanAvailability()
  elseif ns.Backend() == "none" then mode = "no auction house API found (see /capital debug)"
  else mode = all and "full scan available" or "full scan throttled - a click starts a paged scan" end
  if not r then return "Idle - " .. mode, "idle" end
  if r.ok then
    return string.format("Scan complete %s: %d rows, %d unique items (%s)  |  Idle - %s", date("%H:%M:%S", r.ts), r.rows,
      r.items, r.mode, mode), "complete"
  end
  return string.format("Scan %s at %s: %s (%d rows kept raw)  |  Idle - %s", r.failed and "FAILED" or "INCOMPLETE",
    date("%H:%M:%S", r.ts), r.reason or "?", r.rows or 0, mode), "failed"
end

local function playDone(ok)
  if type(PlaySound) ~= "function" then return end
  local kit = SOUNDKIT and (ok and (SOUNDKIT.AUCTION_WINDOW_OPEN or SOUNDKIT.READY_CHECK) or SOUNDKIT.RAID_WARNING)
  if not (kit and pcall(PlaySound, kit)) then
    if not pcall(PlaySound, ok and 5274 or 8959) then pcall(PlaySound, ok and "AuctionWindowOpen" or "RaidWarning") end
  end
end

function S:CreateButton()
  local host = AuctionHouseFrame or AuctionFrame -- modern (Blizzard_AuctionHouseUI) or legacy (Blizzard_AuctionUI)
  local old = _G.PhyzanCapitalScanButton -- never a second one on the same frame
  if not self.button and host and old and old.GetParent and old:GetParent() == host then self.button = old end
  if self.button or not host then return end
  local b = CreateFrame("Button", "PhyzanCapitalScanButton", host, "UIPanelButtonTemplate")
  b:Hide() -- shown / hidden with our window by UI:ApplyBlizzardVisibility
  b:SetSize(170, 22)
  b:SetPoint("TOPRIGHT", host, "TOPRIGHT", -40, host == AuctionHouseFrame and -28 or -14)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, button) S:OnClick(button) end)
  b:SetScript("OnEnter", function(btn)
    if not GameTooltip then return end
    GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("Phyzan Capital scan")
    local modernAH = ns.Backend() == "modern"
    if modernAH then -- C_AuctionHouse: ReplicateItems full scan, else a browse scan (lowest price + quantity per item)
      GameTooltip:AddLine("Left-click: full scan if allowed (about every 15 min), otherwise a browse scan.", 1, 1, 1, true)
      GameTooltip:AddLine("Shift-left-click: force a browse scan. Right-click: abort.", 1, 1, 1, true)
    else
      GameTooltip:AddLine("Left-click: full scan if allowed (about every 15 min), otherwise one page per click.", 1, 1, 1, true)
      GameTooltip:AddLine("Shift-left-click: force a paged scan. Right-click: abort.", 1, 1, 1, true)
    end
    local last = ns.db and (modernAH and ns.db.lastReplicateTs or ns.db.lastGetAllTs)
    if last then GameTooltip:AddLine("Last full scan request: " .. date("%H:%M", last), 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnUpdate", function(btn, elapsed)
    btn.t = (btn.t or 0) + elapsed
    if btn.t > 0.5 then btn.t = 0; S:UpdateButton() end
  end)
  self.button = b
  self:AddButton(b)
  if ns.UI then ns.UI:ApplyBlizzardVisibility() end
end

function S:Begin(mode)
  self.mode = mode
  self.rows = {}
  self.missing = {}
  self.startTs = time()
  self.ahKey = ns.CurrentAHKey()
  self.page = 0
  self.numPages = 1
  self.retries = 0
  self.aggregated = nil
  self.total, self.index, self.allowGrow, self.postProcess = nil, nil, nil, nil
  self.token = (self.token or 0) + 1
end

-- Record a failure that happened before any scan state existed (never fail silently).
function S:Fail(reason)
  ns.Print("Scan failed: " .. tostring(reason))
  self.lastResult = { ok = false, failed = true, ts = time(), rows = 0, items = 0, mode = self.mode or "?", reason = reason }
  self.state = "idle"
  playDone(false)
  self:UpdateButton()
  if ns.UI then ns.UI:Refresh() end
end

function S:OnClick(button)
  ns.CountUsage("scan:click")
  if button == "RightButton" then self:Abort("aborted by user"); return end
  local backend = ns.Backend()
  if backend == "modern" then
    local ok, err = pcall(ns.ModernAH.ScanClick, ns.ModernAH, button)
    if not ok then
      if self.state ~= "idle" then self:Abort("modern scan error: " .. tostring(err)) else self:Fail("modern scan error: " .. tostring(err)) end
    end
    self:UpdateButton()
    return
  elseif backend ~= "legacy" then
    self:Fail("no usable auction house API found on this client (see /capital debug)")
    return
  end
  if type(CanSendAuctionQuery) ~= "function" then
    self:Fail("CanSendAuctionQuery is missing - legacy auction API unavailable (see /capital debug)")
    return
  end
  local can, all = canQuery()
  if ns.Trade and ns.Trade.pending and self.state == "idle" then
    ns.Print("a search is still pending - try again in a moment."); return
  end
  if self.state == "idle" then
    if all and not (IsShiftKeyDown and IsShiftKeyDown()) then
      self:Begin("getAll")
      local ok, err = sendQuery(0, true)
      if not ok then self.state = "reading"; self.rows = {}; self:Abort("full scan query failed: " .. tostring(err)); return end
      ns.db.lastGetAllTs = time()
      self.state = "waiting"
      ns.Print("full scan requested - the client may freeze for a few seconds while the server answers.")
    elseif can then
      self:Begin("paged")
      local ok, err = sendQuery(0, false)
      if not ok then self.state = "reading"; self.rows = {}; self:Abort("query failed: " .. tostring(err)); return end
      self.state = "waiting"
    else
      ns.Print("the server is not accepting a query yet - click again in a moment.")
    end
  elseif self.state == "paged" then
    if not can then ns.Print("throttled by the server - click again in a moment."); return end
    local ok, err = sendQuery(self.page + 1, false)
    if not ok then ns.Print("query failed: " .. tostring(err)); return end
    self.page = self.page + 1
    self.state = "waiting"
  else
    ns.Print("scan in progress (" .. self.state .. "). Right-click to abort.")
  end
  self:UpdateButton()
end

---------------------------------------------------------------------------
-- Reading results
---------------------------------------------------------------------------
local reader = CreateFrame("Frame")

-- Generic chunked reader used by both backends: readFn(i) for i = 1..total, countFn() must stay == total.
function S:StartReading(total, readFn, countFn, allowGrow)
  self.total, self.index = total, 1
  self.readFn, self.countFn, self.allowGrow = readFn, countFn, allowGrow
  self.state = "reading"
  reader:SetScript("OnUpdate", function()
    local ok, err = pcall(S.ReadChunk, S)
    if not ok then S:Crash("reader", err) end
  end)
end

-- Saves what happened to the last scan into PhyzanCapitalDB.debug.lastScan (readable from disk after /reload).
function S:SaveDebug(result, reason, items)
  pcall(ns.DebugSet, "lastScan", { ts = time(), startTs = self.startTs, mode = self.mode, result = result,
    reason = reason, total = self.total, rows = self.rows and #self.rows or 0, missing = self.missing and #self.missing or 0,
    items = items, backend = ns.Backend() })
end

-- Any unexpected error during a scan ends up here: the scan is marked failed (never left in "reading").
function S:Crash(where, err, index)
  reader:SetScript("OnUpdate", nil)
  local reason = string.format("error in %s%s: %s", where, index and (" at row " .. ns.IntStr(index)) or "", tostring(err))
  pcall(ns.RecordError, "scan " .. where, err, { index = index, mode = self.mode, total = self.total })
  ns.Print("Scan failed: " .. reason)
  self:SaveDebug("failed", reason)
  self.lastResult = { ok = false, failed = true, ts = time(), rows = self.rows and #self.rows or 0, items = 0, mode = self.mode or "?", reason = reason }
  self.state, self.rows, self.missing, self.skippedPaged = "idle", nil, nil, nil
  self.readFn, self.countFn, self.postProcess = nil, nil, nil
  pcall(playDone, false)
  pcall(self.UpdateButton, self)
  if ns.UI then pcall(ns.UI.Refresh, ns.UI) end
end

function S:ReadChunk()
  local batch = (self.countFn or numItems)()
  if self.allowGrow and type(batch) == "number" and batch > self.total then self.total = batch end -- more data arrived
  if batch ~= self.total then self:Abort("the auction list changed while reading (another search?)"); return end
  local last = math.min(self.total, self.index + CHUNK - 1)
  local readFn = self.readFn or readRow
  for i = self.index, last do
    local ok, r = pcall(readFn, i)
    if not ok then self:Crash("reading", r, i); return end
    if r then self.rows[#self.rows + 1] = r else self.missing[#self.missing + 1] = i end
  end
  self.index = last + 1
  if self.index > self.total then
    reader:SetScript("OnUpdate", nil)
    self:RetryMissing(function() self:Finish(true) end)
  end
end

-- Re-read rows whose item info was not cached yet; give the client a moment between passes.
function S:RetryMissing(done)
  if #self.missing == 0 or self.retries >= MAX_RETRIES then done(); return end
  self.retries = self.retries + 1
  ns.After(1, function()
    if self.state == "idle" then return end
    local ok, err = pcall(function()
      local still = {}
      local readFn = self.readFn or readRow
      for _, i in ipairs(self.missing) do
        local r = readFn(i)
        if r then self.rows[#self.rows + 1] = r else still[#still + 1] = i end
      end
      self.missing = still
    end)
    if not ok then self:Crash("retrying unread rows", err); return end
    self:RetryMissing(done)
  end)
end

function S:OnListUpdate()
  if self.state ~= "waiting" then return end
  if self.mode == "getAll" then
    self:StartReading(numItems(), readRow, numItems)
  else
    self.state = "pagedReading"
    ns.After(0.3, function() -- let item info arrive; AUCTION_ITEM_LIST_UPDATE can fire several times per page
      if self.state ~= "pagedReading" then return end
      local batch, total = numItems()
      self.missing = {}
      for i = 1, batch do
        local r = readRow(i)
        if r then self.rows[#self.rows + 1] = r else self.missing[#self.missing + 1] = i end
      end
      self.retries = 0
      self:RetryMissing(function()
        self.skippedPaged = (self.skippedPaged or 0) + #self.missing
        self.numPages = math.max(1, math.ceil(total / PER_PAGE))
        if self.page + 1 >= self.numPages or batch == 0 then
          self:Finish(true)
        else
          self.state = "paged"
          self:UpdateButton()
        end
      end)
    end)
  end
  self:UpdateButton()
end

function S:Finish(complete, reason)
  reader:SetScript("OnUpdate", nil)
  local skipped = #(self.missing or {}) + (self.skippedPaged or 0)
  -- A scan with too many unreadable rows would distort comparisons, so treat it as incomplete.
  if complete and skipped > math.max(5, 0.005 * (#self.rows + skipped)) then
    complete = false
    reason = string.format("%d rows could not be read (item info not loaded)", skipped)
  end
  if #self.rows == 0 then
    -- never report "complete" for an empty scan
    reason = (skipped > 0) and string.format("0 auctions could be read (%d rows unreadable)", skipped) or "server returned 0 auctions"
    pcall(ns.RecordError, "scan finish", reason, { mode = self.mode, total = self.total })
    self.rows = nil -- Abort then takes its "failed" branch
    if self.state == "idle" then self.state = "reading" end
    self:Abort(reason)
    return
  end
  if self.postProcess then pcall(self.postProcess, self.rows); self.postProcess = nil end
  local okI, scan = pcall(ns.Ledger.IngestScan, ns.Ledger, self.mode, self.startTs, self.rows, complete, skipped, self.ahKey, self.aggregated)
  if not okI then self:Crash("saving the scan", scan); return end
  if not complete then scan.reason = reason end
  local uniq = {}
  local nItems = 0
  for _, r in ipairs(self.rows) do if not uniq[r.itemID] then uniq[r.itemID] = true; nItems = nItems + 1 end end
  scan.items = nItems
  self.lastResult = { ok = complete, ts = time(), rows = scan.rows, items = nItems, mode = self.mode, reason = reason, id = scan.id }
  if complete then
    if self.aggregated then
      ns.Print(string.format("Scan complete: %s items (browse summary: lowest price + quantity), %s unique items (scan #%s).",
        ns.IntStr(scan.rows), ns.IntStr(nItems), ns.IntStr(scan.id)))
    else
      ns.Print(string.format("Scan complete: %s auctions, %s unique items (scan #%s).", ns.IntStr(scan.rows), ns.IntStr(nItems), ns.IntStr(scan.id)))
    end
  else
    ns.Print(string.format("Scan incomplete: %s. %d listings saved raw (scan #%d), not used for prices.", reason or "?", scan.rows, scan.id))
  end
  self:SaveDebug(complete and "complete" or "incomplete", reason, nItems)
  if ns.db.debug then ns.db.debug.lastScanID = scan.id end
  playDone(complete)
  self.state, self.rows, self.missing, self.skippedPaged = "idle", nil, nil, nil
  self.readFn, self.countFn = nil, nil
  self:UpdateButton()
  if ns.UI then ns.UI:Refresh() end
end

function S:Abort(reason)
  if self.state == "idle" then return end
  reader:SetScript("OnUpdate", nil)
  if self.rows and #self.rows > 0 then
    self.missing = self.missing or {}
    self:Finish(false, reason)
  else
    ns.Print("Scan failed: " .. tostring(reason))
    self:SaveDebug("failed", reason, 0)
    self.lastResult = { ok = false, failed = true, ts = time(), rows = 0, items = 0, mode = self.mode, reason = reason }
    playDone(false)
    self.state = "idle"
    self:UpdateButton()
    if ns.UI then ns.UI:Refresh() end
  end
end

ns.On("AUCTION_HOUSE_SHOW", function()
  S:CreateButton(); S:UpdateButton()
  -- Blizzard_AuctionHouseUI is load-on-demand; AuctionHouseFrame may appear just after this event.
  ns.After(0.5, function() S:CreateButton(); S:UpdateButton() end)
  local b = ns.Backend()
  if b == "none" then ns.Print("warning: no usable auction house API found on this client - see /capital debug") end
end)
ns.On("AUCTION_HOUSE_CLOSED", function() if S.state ~= "idle" then S:Abort("auction house closed") end end)
ns.On("AUCTION_ITEM_LIST_UPDATE", function() if ns.Backend() == "legacy" then S:OnListUpdate() end end)

-- debug.scannerState is written to disk at logout / reload, so it always shows the state of the last session
-- (it used to be updated only by /capital debug and could stay "reading" from an old session).
ns.On("PLAYER_LOGOUT", function()
  pcall(ns.DebugSet, "scannerState", S.state)
  pcall(ns.DebugSet, "scannerStateTs", time())
  pcall(ns.DebugSet, "addonVersion", ns.VERSION)
end)
