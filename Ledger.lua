-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital Ledger: turns raw scans into snapshots, per-day item stats, ESTIMATED sales and the "current" price view.
local _, ns = ...
local L = {}
ns.Ledger = L

local MAX_SAMPLES = 200 -- unit prices kept per item per day for the median

-- Time-left categories returned by GetAuctionItemTimeLeft: 1 Short, 2 Medium, 3 Long, 4 Very Long.
-- Classic durations: 1 = <30m, 2 = 30m-2h, 3 = 2h-8h, 4 = 8h-24h.
L.TL_MIN = { 0, 1800, 7200, 28800 }   -- an auction in this category has AT LEAST this many seconds left
L.TL_MAX = { 1800, 7200, 28800, 86400 }
L.TL_NAMES = { "Short", "Medium", "Long", "Very Long" }

local function sanitize(s)
  s = tostring(s or "")
  return (s:gsub("[|\n\r]", ""))
end

-- Snapshot row format (pipe-delimited, one string per listing; see README):
-- itemID|count|minBid|buyout|unitBuyout|timeLeft|seller|bidAmount
local function encodeRow(r)
  local I = ns.IntStr -- never %d: values can exceed int32 (WoW errors) or 1e14 (exponent notation)
  return table.concat({ I(r.itemID), I(r.count), I(r.minBid), I(r.buyout), I(r.unit), I(r.tl), sanitize(r.seller), I(r.bid) }, "|")
end

local function decodeRow(s)
  local id, c, mb, bo, u, tl, seller, bid = s:match("^(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|(%d+)$")
  if not id then return nil end
  return { itemID = tonumber(id), count = tonumber(c), minBid = tonumber(mb), buyout = tonumber(bo),
           unit = tonumber(u), tl = tonumber(tl), seller = seller, bid = tonumber(bid) }
end
L.decodeRow = decodeRow

-- Multiset of auctions keyed by a signature. The legacy API exposes no auction ID, so identical stacks from the
-- same seller at the same price are indistinguishable; we count them instead.
local function sig(r)
  local I = ns.IntStr
  return I(r.itemID) .. ":" .. I(r.count) .. ":" .. I(r.minBid) .. ":" .. I(r.buyout) .. ":" .. (r.seller or "")
end

local function buildMS(rows)
  local ms = {}
  for _, r in ipairs(rows) do
    local k = sig(r)
    local e = ms[k]
    if e then
      e.n = e.n + 1
      if (r.tl or 0) < e.tl then e.tl = r.tl or 0 end -- keep the shortest time-left (conservative for expiry)
      if (r.bid or 0) > e.bid then e.bid = r.bid end
    else
      ms[k] = { n = 1, itemID = r.itemID, count = r.count, buyout = r.buyout or 0, unit = r.unit or 0,
                tl = r.tl or 0, bid = r.bid or 0, minBid = r.minBid or 0 }
    end
  end
  return ms
end

function L:LoadMS(scan)
  if self.lastMS and self.lastMS.id == scan.id then return self.lastMS.ms end
  local snap = ns.db.snapshots[scan.id]
  if not snap then return nil end
  local rows = {}
  for i, s in ipairs(snap) do rows[i] = decodeRow(s) end
  return buildMS(rows)
end

-- Latest complete, un-pruned scan for the same AH before scanID.
function L:PrevComplete(scanID, ahKey)
  local scans = ns.db.scans
  for i = #scans, 1, -1 do
    local s = scans[i]
    if s.id < scanID and s.complete and not s.pruned and not s.aggregated and s.ahKey == ahKey then return s end
  end
  return nil
end

local function dayTable(root, day)
  local t = root[day]
  if not t then t = {}; root[day] = t end
  return t
end

local function median(list)
  local n = #list
  if n == 0 then return nil end
  local c = {}
  for i = 1, n do c[i] = list[i] end
  table.sort(c)
  if n % 2 == 1 then return c[(n + 1) / 2] end
  return math.floor((c[n / 2] + c[n / 2 + 1]) / 2 + 0.5)
end

-- Add listings first seen today to the day's per-item stats.
-- First complete scan of a market day: every listing counts. Later scans: only listings not in the previous scan.
function L:UpdateDaily(ah, day, cur, prevSameDay)
  local stats = dayTable(ah.dailyStats, day)
  local samples = dayTable(ah.priceSamples, day)
  local touched = {}
  for k, e in pairs(cur) do
    local added = e.n - ((prevSameDay and prevSameDay[k] and prevSameDay[k].n) or 0)
    if added > 0 then
      local st = stats[e.itemID]
      if not st then
        st = { listings = 0, quantity = 0, pricedListings = 0, noBuyout = 0, sumUnit = 0,
               tl1 = 0, tl2 = 0, tl3 = 0, tl4 = 0, scans = 0 }
        stats[e.itemID] = st
      end
      st.listings = st.listings + added
      st.quantity = st.quantity + added * e.count
      local tk = "tl" .. (e.tl or 0)
      if st[tk] then st[tk] = st[tk] + added end
      if e.buyout > 0 then
        st.pricedListings = st.pricedListings + added
        st.sumUnit = st.sumUnit + e.unit * added
        st.minUnit = (st.minUnit and st.minUnit < e.unit) and st.minUnit or e.unit
        st.maxUnit = (st.maxUnit and st.maxUnit > e.unit) and st.maxUnit or e.unit
        local sm = samples[e.itemID]
        if not sm then sm = {}; samples[e.itemID] = sm end
        for _ = 1, added do
          if #sm >= MAX_SAMPLES then break end
          sm[#sm + 1] = e.unit
        end
      else
        st.noBuyout = st.noBuyout + added
      end
      touched[e.itemID] = true
    end
  end
  for id in pairs(touched) do
    local st = stats[id]
    if st.pricedListings > 0 then st.avgUnit = math.floor(st.sumUnit / st.pricedListings + 0.5) end
    st.medianUnit = median(samples[id] or {})
  end
  -- count the scan for every item present in it
  local present = {}
  for _, e in pairs(cur) do present[e.itemID] = true end
  for id in pairs(present) do if stats[id] then stats[id].scans = (stats[id].scans or 0) + 1 end end
end

-- ESTIMATED traded volume. For each auction present in the previous scan but missing now:
--   * if the elapsed time is shorter than the minimum time it had left (TL_MIN of its time-left category),
--     it cannot have expired, so it was bought out (or cancelled by the seller - we cannot tell) => probable sale;
--   * otherwise it vanished inside its expiry window => counted as expired, unless it carried a bid,
--     in which case the bidder most likely won it => bidWon.
-- This is a heuristic estimate, not real sales data.
function L:EstimateSales(ah, day, prev, cur, dt, scan)
  if dt <= 0 or dt > 48 * 3600 then scan.estSkipped = true; return end
  local es = dayTable(ah.estSales, day)
  local sold, expired = 0, 0
  for k, e in pairs(prev) do
    local gone = e.n - ((cur[k] and cur[k].n) or 0)
    if gone > 0 then
      local r = es[e.itemID]
      if not r then
        r = { sold = 0, soldQty = 0, soldValue = 0, expired = 0, expiredQty = 0, bidWon = 0, bidWonQty = 0 }
        es[e.itemID] = r
      end
      local minLeft = L.TL_MIN[e.tl] or 0
      if dt < minLeft then
        r.sold = r.sold + gone
        r.soldQty = r.soldQty + gone * e.count
        r.soldValue = r.soldValue + gone * (e.buyout > 0 and e.buyout or e.bid)
        sold = sold + gone
      elseif e.bid > 0 then
        r.bidWon = r.bidWon + gone
        r.bidWonQty = r.bidWonQty + gone * e.count
        r.soldValue = r.soldValue + gone * e.bid
      else
        r.expired = r.expired + gone
        r.expiredQty = r.expiredQty + gone * e.count
        expired = expired + gone
      end
    end
  end
  scan.estSold, scan.estExpired = sold, expired
end

-- Summary of the latest complete scan: lowest unit buyout, listed quantity and the 10 cheapest unit prices.
function L:UpdateCurrent(ah, rows, scanID, ts)
  local cur = {}
  local cheap = {}
  for _, r in ipairs(rows) do
    local c = cur[r.itemID]
    if not c then c = { n = 0, qty = 0, scanID = scanID, ts = ts }; cur[r.itemID] = c end
    c.n = c.n + 1
    c.qty = c.qty + r.count
    if (r.buyout or 0) > 0 then
      if not c.minUnit or r.unit < c.minUnit then c.minUnit = r.unit end
      local l = cheap[r.itemID]
      if not l then l = {}; cheap[r.itemID] = l end
      l[#l + 1] = { r.unit, r.count }
    end
  end
  for id, l in pairs(cheap) do
    table.sort(l, function(a, b) return a[1] < b[1] end)
    local parts = {}
    for i = 1, math.min(10, #l) do parts[i] = ns.IntStr(l[i][1]) .. ":" .. ns.IntStr(l[i][2]) end
    cur[id].cheapest = table.concat(parts, ",") -- "unitPrice:stackCount,..." ascending
  end
  ah.current = cur
end

-- rows: array of {itemID, name, quality, count, minBid, buyout, unit, tl, seller, bid}
-- aggregated = true for modern browse scans: one row per item (count = total quantity, unit = lowest unit price);
-- such scans update the "current" prices only (no daily stats, no sales estimate).
function L:IngestScan(mode, startTs, rows, complete, skipped, ahKey, aggregated)
  local db = ns.db
  local id = db.nextScanID
  db.nextScanID = id + 1
  local day = ns.MarketDay(startTs)
  ahKey = ahKey or ns.CurrentAHKey()
  local scan = { id = id, ts = startTs, endTs = time(), day = day, mode = mode, complete = complete and true or false,
                 rows = #rows, skipped = skipped or 0, ahKey = ahKey, char = ns.CharKey(), aggregated = aggregated or nil }
  table.insert(db.scans, scan)
  local snap = {}
  for i, r in ipairs(rows) do
    snap[i] = encodeRow(r)
    ns.TouchItem(r.itemID, r.name, r.quality)
  end
  db.snapshots[id] = snap
  if complete and aggregated then
    self:UpdateCurrent(ns.AH(ahKey), rows, id, startTs)
  elseif complete then
    local ah = ns.AH(ahKey)
    local cur = buildMS(rows)
    local prevScan = self:PrevComplete(id, ahKey)
    local prev = prevScan and self:LoadMS(prevScan)
    self:UpdateDaily(ah, day, cur, (prevScan and prevScan.day == day) and prev or nil)
    if prev then
      scan.comparedTo = prevScan.id
      self:EstimateSales(ah, day, prev, cur, startTs - prevScan.ts, scan)
    end
    self:UpdateCurrent(ah, rows, id, startTs)
    self.lastMS = { id = id, ms = cur }
  end
  if complete then self:UpdateLookup(ns.AH(ahKey), day) end
  self:Prune()
  return scan
end

---------------------------------------------------------------------------
-- Offline price lookup data (1.2.7). Compact and kept across reloads / logouts; never cleared when the AH closes.
--   ah.lastKnown[itemID] = { u = lowest unit buyout, t = scan time, n = listings, q = quantity }
--     updated by every complete scan; an item missing from the latest scan keeps its last known price.
--   ah.history[itemID] = "YYYY-MM-DD:low:median;..." one entry per market day (oldest first, at most HISTORY_DAYS);
--     low = lowest unit buyout seen that day, median = that day's median (full scans only, empty otherwise).
---------------------------------------------------------------------------
L.HISTORY_DAYS = 14

function L.DecodeHistory(s)
  local out = {}
  for day, low, med in (s or ""):gmatch("([%d%-]+):(%d*):(%d*)") do
    out[#out + 1] = { day = day, low = tonumber(low), median = tonumber(med) }
  end
  return out
end

local function encodeHistory(list)
  local parts = {}
  for i, h in ipairs(list) do
    parts[i] = h.day .. ":" .. (h.low and ns.IntStr(h.low) or "") .. ":" .. (h.median and ns.IntStr(h.median) or "")
  end
  return table.concat(parts, ";")
end

local function addHistory(ah, id, day, low, med)
  if not low and not med then return end
  local list = L.DecodeHistory(ah.history[id])
  local last = list[#list]
  if last and last.day == day then
    if low and (not last.low or low < last.low) then last.low = low end
    if med then last.median = med end
  elseif not last or last.day < day then
    list[#list + 1] = { day = day, low = low, median = med }
  else
    return -- older than what is stored (seeding happens oldest first)
  end
  while #list > L.HISTORY_DAYS do table.remove(list, 1) end
  ah.history[id] = encodeHistory(list)
end

function L:UpdateLookup(ah, day)
  ah.lastKnown = ah.lastKnown or {}
  ah.history = ah.history or {}
  local stats = ah.dailyStats[day] or {}
  for id, c in pairs(ah.current) do
    local old = ah.lastKnown[id]
    local newer = not (old and old.t and c.ts and c.ts < old.t) -- an older scan saved later keeps the newer price
    if newer and c.minUnit then
      ah.lastKnown[id] = { u = c.minUnit, t = c.ts, n = c.n, q = c.qty }
    elseif newer and not old then
      ah.lastKnown[id] = { t = c.ts, n = c.n, q = c.qty } -- listed without buyout: seen, no price
    end
    addHistory(ah, id, day, c.minUnit, stats[id] and stats[id].medianUnit)
  end
end

-- One-time fill from data saved by older versions (current prices + daily stats), oldest day first.
function L:SeedLookup()
  for _, ah in pairs(ns.db.ah) do
    if not ah.lookupSeeded then
      ah.lastKnown = ah.lastKnown or {}
      ah.history = ah.history or {}
      local days = {}
      for day in pairs(ah.dailyStats or {}) do days[#days + 1] = day end
      table.sort(days)
      for _, day in ipairs(days) do
        for id, st in pairs(ah.dailyStats[day]) do addHistory(ah, id, day, st.minUnit, st.medianUnit) end
      end
      for id, c in pairs(ah.current or {}) do
        if not ah.lastKnown[id] and (c.minUnit or c.ts) then ah.lastKnown[id] = { u = c.minUnit, t = c.ts, n = c.n, q = c.qty } end
        if c.minUnit and c.ts then addHistory(ah, id, ns.MarketDay(c.ts), c.minUnit, nil) end
      end
      ah.lookupSeeded = true
    end
  end
end

-- Retention: raw snapshots for keepSnapshotDays market days and at most maxSnapshotRows rows in total;
-- aggregates for keepStatsDays; price samples for 2 days.
function L:Prune()
  local db = ns.db
  if not db then return end
  local s = db.settings
  local snapCut = ns.MarketDayOffset(s.keepSnapshotDays - 1)
  local statCut = ns.MarketDayOffset(s.keepStatsDays - 1)
  local sampleCut = ns.MarketDayOffset(1)
  local total = 0
  for _, sc in ipairs(db.scans) do
    if not sc.pruned then
      if sc.day < snapCut or not db.snapshots[sc.id] then
        db.snapshots[sc.id] = nil
        sc.pruned = true
      else
        total = total + (sc.rows or 0)
      end
    end
  end
  local i = 1
  while total > s.maxSnapshotRows and i < #db.scans do -- never drop the newest scan
    local sc = db.scans[i]
    if not sc.pruned then
      db.snapshots[sc.id] = nil
      sc.pruned = true
      total = total - (sc.rows or 0)
    end
    i = i + 1
  end
  local keep = {}
  for _, sc in ipairs(db.scans) do
    if not (sc.pruned and sc.day < statCut) then keep[#keep + 1] = sc end
  end
  db.scans = keep
  for _, ah in pairs(db.ah) do
    for _, key in ipairs({ "dailyStats", "estSales" }) do
      for day in pairs(ah[key] or {}) do if day < statCut then ah[key][day] = nil end end
    end
    for day in pairs(ah.priceSamples or {}) do if day < sampleCut then ah.priceSamples[day] = nil end end
    -- price history: drop market days older than the stats retention (lastKnown is one small row per item, kept)
    for id, h in pairs(ah.history or {}) do
      local first = h:match("^([%d%-]+):")
      if first and first < statCut then
        local kept = {}
        for _, e in ipairs(L.DecodeHistory(h)) do if e.day >= statCut then kept[#kept + 1] = e end end
        ah.history[id] = (#kept > 0) and encodeHistory(kept) or nil
      end
    end
  end
end

-- Best known AH unit price for an item: current lowest buyout, else today's median, else yesterday's.
function L:AHPrice(ahKey, id)
  local ah = ns.AH(ahKey)
  local c = ah.current[id]
  if c and c.minUnit then return c.minUnit, "now" end
  for off = 0, 1 do
    local d = ah.dailyStats[ns.MarketDayOffset(off)]
    local st = d and d[id]
    if st and st.medianUnit then return st.medianUnit, off == 0 and "today" or "yesterday" end
  end
  return nil
end

function L:LatestAHKey()
  local scans = ns.db.scans
  for i = #scans, 1, -1 do if scans[i].complete then return scans[i].ahKey end end
  return ns.CurrentAHKey()
end
