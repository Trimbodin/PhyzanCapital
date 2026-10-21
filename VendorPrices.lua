-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital vendor prices and vendor locations.
-- The client exposes vendor SELL prices (C_Item.GetItemInfo sellPrice) but not vendor BUY prices, so buy prices are
-- recorded whenever a merchant window is open; otherwise the bundled world vendor database (Data/Vendors.lua) is used.
-- Recorded prices (they include your reputation discount) override the bundle.
local _, ns = ...
local V = {}
ns.Vendor = V

local function pack(...) return { n = select("#", ...), ... } end

-- NPC id from a unit GUID: "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>" (also Vehicle-...), or the old
-- hex form 0xF13000<npc 4 hex>... (6-hex entry on some cores). nil when it cannot be read.
function ns.NPCIDFromGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
  local hex = guid:match("^0x(%x+)$")
  if hex and #hex == 16 and hex:sub(1, 4):upper() == "F130" then return tonumber(hex:sub(7, 12), 16) end
  return nil
end

-- Key used for observed / missing vendors: the NPC id, or "name:<name>" when no id is known.
function V.Key(v)
  if not v then return nil end
  if v.npc then return v.npc end
  return v.name and ("name:" .. v.name) or nil
end

-- One merchant slot: { name, price, stack, numAvailable, extendedCost } or nil.
-- WoW Forever / modern clients: C_MerchantFrame.GetItemInfo(index) returns a table (GetMerchantItemInfo is gone).
-- Old clients: GetMerchantItemInfo; extendedCost is its 8th return with isPurchasable, 7th on older ones.
function V.MerchantItem(i)
  local f = ns.Fn(C_MerchantFrame, "GetItemInfo")
  if f then
    local ok, t = pcall(f, i)
    if not ok or type(t) ~= "table" then return nil end
    return { name = t.name, price = t.price, stack = t.stackCount, numAvailable = t.numAvailable,
      extendedCost = t.hasExtendedCost and true or false }
  end
  if type(GetMerchantItemInfo) ~= "function" then return nil end
  local r = pack(pcall(GetMerchantItemInfo, i))
  if not r[1] then return nil end
  local ext
  if r.n - 1 >= 8 then ext = r[9] else ext = r[8] end
  return { name = r[2], price = r[4], stack = r[5], numAvailable = r[6], extendedCost = ext == true }
end

function V.CanReadMerchant()
  return type(GetMerchantNumItems) == "function" and (ns.Fn(C_MerchantFrame, "GetItemInfo") ~= nil
    or type(GetMerchantItemInfo) == "function")
end

function V:Record()
  if not V.CanReadMerchant() then return end
  local ok0, n = pcall(GetMerchantNumItems)
  if not ok0 or not n then return end
  local merchant = ns.Plain(UnitName and UnitName("npc")) or "?"
  local npc = type(UnitGUID) == "function" and ns.NPCIDFromGUID(ns.Plain((select(2, pcall(UnitGUID, "npc"))))) or nil
  local now, added = time(), 0
  local zone = (GetRealZoneText and GetRealZoneText()) or nil
  local pos = ns.MapPin and ns.MapPin:PlayerPosition() -- where this merchant stands (for "See vendor on map")
  local items, complete = {}, true
  for i = 1, n do
    local mi = V.MerchantItem(i)
    if mi then
      local name, price, qty, numAvail, ext = mi.name, mi.price, mi.stack, mi.numAvailable, mi.extendedCost
      local link = type(GetMerchantItemLink) == "function" and select(2, pcall(GetMerchantItemLink, i)) or nil
      local id = ns.ItemIDFromLink(link)
      if not id then complete = false end -- item data not loaded yet: inventory not complete
      if id and type(price) == "number" and price > 0 and ext ~= true then
        qty = (type(qty) == "number" and qty > 0) and qty or 1
        local limited = (type(numAvail) == "number" and numAvail >= 0) or false
        ns.db.vendorPrices[id] = { unit = price / qty, stackPrice = price, stack = qty, name = name,
          ts = now, merchant = merchant, npc = npc, zone = zone, limited = limited,
          uiMapID = pos and pos.uiMapID, x = pos and pos.x, y = pos and pos.y }
        ns.TouchItem(id, name)
        items[id] = price / qty
        added = added + 1
      elseif id then
        items[id] = 0 -- sold for something other than money (tokens, honor): still sold here
      end
    else
      complete = false
    end
  end
  self.lastCount = added
  self:Observe(npc, merchant, zone, pos, items, complete)
end

-- Live observation of a merchant (schema 5): where it stands and what it sells. Overrides the bundled data for
-- location and inventory; a vendor seen in game is never "missing".
function V:Observe(npc, name, zone, pos, items, complete)
  local db = ns.db
  db.observedVendors = db.observedVendors or {}
  local key = npc or (name and ("name:" .. name))
  if not key then return end
  local o = db.observedVendors[key] or { firstSeen = time() }
  db.observedVendors[key] = o
  o.npc, o.name, o.zone, o.seen = npc, name, zone, time()
  if pos then o.uiMapID, o.x, o.y = pos.uiMapID, pos.x, pos.y end
  -- keep the last complete inventory; an incomplete read (uncached items) only adds to it
  if complete or not o.items then o.items = items else for id, p in pairs(items) do o.items[id] = p end end
  o.complete = complete or o.complete or false
  local c = 0; for _ in pairs(o.items) do c = c + 1 end
  o.itemCount = c
  -- bundled data that claims this NPC sells items it does not sell
  local wrong = 0
  if npc and o.complete and ns.VendorDB then
    for id, d in pairs(ns.VendorDB) do
      for k = 2, #d do
        if math.abs(d[k]) == npc and not o.items[id] then wrong = wrong + 1 end
      end
    end
  end
  o.bundledNotSold = wrong
  if db.vendorMissing and db.vendorMissing[key] then
    db.vendorMissing[key] = nil
    ns.Print(string.format("%s is here after all - 'not here' mark removed.", tostring(name)))
  end
  self.obsIndex = nil
  if wrong > 0 then
    ns.Print(string.format("%s: %d item(s) the bundled vendor data lists for this vendor are not sold here; they are flagged.", tostring(name), wrong))
  end
end

-- itemID -> { observed vendor, ... } for vendors seen selling it
function V:ObservedSellers(id)
  if not self.obsIndex then
    self.obsIndex = {}
    for _, o in pairs(ns.db.observedVendors or {}) do
      for iid in pairs(o.items or {}) do
        local t = self.obsIndex[iid] or {}
        self.obsIndex[iid] = t
        t[#t + 1] = o
      end
    end
  end
  return self.obsIndex[id] or {}
end

function V:IsMissing(v)
  local k = V.Key(v)
  return k ~= nil and ns.db.vendorMissing ~= nil and ns.db.vendorMissing[k] ~= nil
end
function V:Observed(v)
  local k = V.Key(v)
  local o = k and ns.db.observedVendors and ns.db.observedVendors[k]
  if not o and v and v.name then o = ns.db.observedVendors and ns.db.observedVendors["name:" .. v.name] end
  return o
end

-- Mark a vendor as not present on this client (persisted). Refused for vendors seen in game.
function V:MarkMissing(v, itemID)
  local k = V.Key(v)
  if not k then return false end
  local o = self:Observed(v)
  if o or v.observed then
    ns.Print(string.format("%s was seen at a merchant window on %s - not marked as missing.", tostring(v.name),
      date("%Y-%m-%d %H:%M", (o and o.seen) or v.seen or 0)))
    return false
  end
  ns.db.vendorMissing = ns.db.vendorMissing or {}
  ns.db.vendorMissing[k] = { npc = v.npc, name = v.name, zone = v.zone, itemID = itemID, ts = time() }
  ns.Print(string.format("%s (%s) marked as not here; other vendors will be used. /capital vendors reset undoes this.", tostring(v.name), tostring(v.zone)))
  ns.CountUsage("vendor:missing")
  if ns.Shop and ns.Shop.Repick then ns.Shop:Repick(v) end
  if ns.UI then ns.UI:Refresh() end
  return true
end

function V:AskMissing(v, itemID, after)
  if not v then return end
  if self:Observed(v) or v.observed then self:MarkMissing(v, itemID); return end -- prints why not
  ns.UI:Confirm({ which = "vendormissing",
    text = string.format("Mark %s\n(%s)\nas not here?\n\nPhyzan Capital will stop using this vendor and pick the next closest one.",
      tostring(v.name), tostring(v.zone)),
    onYes = function() if V:MarkMissing(v, itemID) and after then after() end end })
end

function V:ResetMissing()
  local n = 0
  for _ in pairs(ns.db.vendorMissing or {}) do n = n + 1 end
  ns.db.vendorMissing = {}
  ns.Print(string.format("%d 'vendor not here' mark(s) cleared.", n))
  if ns.UI then ns.UI:Refresh() end
end

-- Unit buy price from a vendor: recorded at a merchant first, else the bundled vendor database. Returns price, source.
function V:BuyPrice(id)
  local r = ns.db.vendorPrices[id]
  if r and r.unit then return r.unit, "recorded" end
  local d = ns.VendorDB and ns.VendorDB[id]
  if d then return d[1], "bundled" end
  return nil
end

local function playerFaction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
end

-- All vendors known for an item: { {npc, name, zone, faction, limited, usable}, ... }, best first.
-- Best = usable by your faction, then unlimited stock. A merchant you recorded comes first.
function V:Vendors(id)
  local out = {}
  local d = ns.VendorDB and ns.VendorDB[id]
  local me = playerFaction()
  if d then
    for k = 2, #d do
      local npc = d[k]
      local limited = npc < 0
      npc = math.abs(npc)
      local n = ns.VendorNPCs and ns.VendorNPCs[npc]
      if n then
        local fac = n[3] or ""
        -- faction "" = not flagged in pfQuest (e.g. Darkmoon Faire, neutral goblins): treated as friendly
        out[#out + 1] = { npc = npc, name = n[1], zone = (ns.VendorZones and ns.VendorZones[n[2]]) or "?", faction = fac,
          limited = limited, usable = (fac == "AH") or (fac == "") or (me ~= nil and fac:find(me, 1, true) ~= nil),
          seasonal = ns.VendorSeasonal and ns.VendorSeasonal[npc] or nil }
      end
    end
  end
  -- live observations: location and inventory override the bundle
  local seen = {}
  for _, v in ipairs(out) do
    local o = V:Observed(v)
    if o then
      v.observed, v.seen = true, o.seen
      -- position and zone together (a zone name without a position would contradict the bundled pin)
      if o.uiMapID and o.x then v.uiMapID, v.x, v.y, v.zone = o.uiMapID, o.x, o.y, o.zone or v.zone end
      if o.complete and o.items and not o.items[id] then v.notSold = true end -- bundle says so, the merchant does not
    end
    seen[V.Key(v)] = true
  end
  for _, o in ipairs(V:ObservedSellers(id)) do
    local k = o.npc or ("name:" .. tostring(o.name))
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = { npc = o.npc, name = o.name, zone = o.zone or "?", faction = "", limited = false, usable = true,
        observed = true, seen = o.seen, uiMapID = o.uiMapID, x = o.x, y = o.y,
        seasonal = o.npc and ns.VendorSeasonal and ns.VendorSeasonal[o.npc] or nil }
    end
  end
  for _, v in ipairs(out) do v.missing = V:IsMissing(v) or nil end
  table.sort(out, function(a, b)
    if a.usable ~= b.usable then return a.usable end
    if a.limited ~= b.limited then return not a.limited end
    return a.name < b.name
  end)
  local r = ns.db.vendorPrices[id]
  if r and r.merchant then
    local rec = { npc = r.npc, name = r.merchant, zone = r.zone or "recorded", faction = "", limited = r.limited, usable = true,
      recorded = true, observed = true, seen = r.ts, uiMapID = r.uiMapID, x = r.x, y = r.y }
    -- same merchant in the list: merge (by NPC id when known, else by name; keeps its map position, no duplicate line)
    for i, v in ipairs(out) do
      if (r.npc and v.npc == r.npc) or (not (r.npc and v.npc) and v.name == r.merchant) then
        rec.npc, rec.faction, rec.seasonal = v.npc, v.faction, v.seasonal
        if v.zone and v.zone ~= "?" then rec.zone = v.zone end
        if not rec.uiMapID then rec.uiMapID, rec.x, rec.y = v.observed and v.uiMapID or nil, v.observed and v.x or nil, v.observed and v.y or nil end
        table.remove(out, i)
        break
      end
    end
    rec.missing = V:IsMissing(rec) or nil
    table.insert(out, 1, rec)
  end
  return out
end

local pending = false
local function onMerchant()
  if pending then return end
  pending = true
  ns.After(0.5, function() pending = false; V:Record() end)
end
ns.On("MERCHANT_SHOW", onMerchant)
ns.On("MERCHANT_UPDATE", onMerchant)
