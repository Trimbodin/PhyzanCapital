-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital Crafting List (called "Shopping List" before 1.4.0): items to buy for crafting, per character.
-- Saved as PhyzanCapitalDB.shopping["Name-Realm"][itemID] (schema 4, see README; the key kept its old name so
-- lists saved by older versions load unchanged). Nothing is ever bought for you:
-- the list only remembers what to buy, and it counts down when you buy the item from a merchant yourself.
local _, ns = ...
local UI = ns.UI
local Shop = { counts = {}, pending = {} }
ns.Shop = Shop


function Shop:List(charKey)
  local db = ns.db
  db.shopping = db.shopping or {}
  local k = charKey or ns.CharKey()
  db.shopping[k] = db.shopping[k] or {}
  return db.shopping[k]
end

function Shop:Entries()
  local out = {}
  for _, e in pairs(self:List()) do out[#out + 1] = e end
  table.sort(out, function(a, b)
    if (a.added or 0) ~= (b.added or 0) then return (a.added or 0) < (b.added or 0) end
    return a.itemID < b.itemID
  end)
  return out
end

function Shop:Count() local n = 0; for _ in pairs(self:List()) do n = n + 1 end; return n end
function Shop:Remaining(e) return math.max(0, (e.qty or 1) - (e.bought or 0)) end

local function popup(text, fn, which) UI:Confirm({ which = which or "shop", text = text, onYes = fn }) end

-- "Add <item> to crafting list?" (Search / Price Lookup results, Professions reagents). opts = { qty (default 1),
-- recipe (the recipe it is for), vendorUnit, ahUnit }. An item already on the list gets "Add more?" instead (one
-- popup, never two). Never replaces an open bid / buyout / purchase question: buying always wins.
function Shop:AskAddItem(id, opts)
  if not id then return end
  opts = opts or {}
  if UI.confirmOpts and UI.confirmOpts.which == "trade" then return end
  local ahKey = ns.Ledger:LatestAHKey()
  local vendorUnit = opts.vendorUnit
  if vendorUnit == nil then vendorUnit = ns.Vendor:BuyPrice(id) end
  local ahUnit = opts.ahUnit
  if ahUnit == nil then ahUnit = ns.Ledger:AHPrice(ahKey, id) end
  vendorUnit, ahUnit = vendorUnit or nil, ahUnit or nil -- false = "known to have none" (reagent rows)
  local vendors = ns.Vendor:Vendors(id)
  local label = ns.ItemLabel(id, true)
  local recipe = opts.recipe
  local forText = recipe and string.format("\nfor %s (%d per craft)", ns.ItemName(recipe.id), opts.qty or 1) or ""
  local e = self:List()[id]
  if e then
    UI:Confirm({ which = "shopadd",
      text = string.format("%s is already on your crafting list\n(%d of %d bought).\n\nAdd more?%s", label, e.bought or 0, e.qty or 1, forText),
      edit = { label = "Add:", default = opts.qty or 1, numeric = true, width = 70 },
      onYes = function(value)
        local n = math.floor(tonumber(value) or 0)
        if n < 1 then ns.Print("quantity must be 1 or more - nothing added."); return end
        local cur = Shop:List()[id]
        if not cur then return end
        Shop:SetQty(id, (cur.qty or 1) + n)
        ns.Print(string.format("Crafting list: %s now x%d.", cur.name or ns.ItemName(id), cur.qty))
      end })
    ns.CountUsage("shop:askmore")
    return
  end
  local _, closest = ns.MapPin:RankVendors(vendors, ns.MapPin:PlayerSpot())
  local where
  if vendorUnit and closest then
    where = string.format("from %s\nat %s each", ns.MapPin:VendorText(closest), ns.Money(vendorUnit))
  elseif vendorUnit then
    where = "vendor price " .. ns.Money(vendorUnit) .. " (|cffff6060no friendly vendor known|r)"
  else
    where = "not sold by a known vendor - buy it on the auction house"
  end
  local ah = ahUnit and ("AH " .. ns.Money(ahUnit)) or "no AH price"
  UI:Confirm({ which = "shopadd",
    text = string.format("Add %s to crafting list?\n\n%s\n%s%s", label, where, ah, forText),
    edit = { label = "Quantity:", default = opts.qty or 1, numeric = true, width = 70 },
    onYes = function(value)
      local n = math.floor(tonumber(value) or 0)
      if n < 1 then ns.Print("quantity must be 1 or more - nothing added."); return end
      local margin = (ahUnit and vendorUnit) and (ahUnit * (1 - ns.CutFor(ahKey)) - vendorUnit) or nil
      Shop:Add({ id = id, buy = vendorUnit, src = vendorUnit and "vendor" or "AH", ahUnit = ahUnit,
        margin = margin, vendors = vendors }, n, ahKey)
    end })
  ns.CountUsage("shop:askadd")
end

-- Professions tab: a reagent of a recipe (quantity = per craft).
function Shop:AskAddReagent(rg, recipe)
  if not (rg and rg.id) then return end
  self:AskAddItem(rg.id, { qty = rg.qty or 1, recipe = recipe, vendorUnit = rg.vendorUnit or false, ahUnit = rg.ahUnit or false })
  ns.CountUsage("shop:askaddreagent")
end

local function setVendor(e, closest)
  local v = closest and closest.v or {}
  local loc = closest and closest.loc or {}
  e.vendorNpc, e.vendorName, e.vendorZone, e.vendorFaction, e.vendorLimited = v.npc, v.name, v.zone, v.faction, v.limited or nil
  e.vendorSeasonal, e.uiMapID, e.x, e.y = v.seasonal, loc.uiMapID, loc.x, loc.y
end

-- A vendor was marked "not here": every entry of this character that used it gets the next closest vendor.
function Shop:Repick(v)
  if not (v and ns.db and ns.db.shopping) then return 0 end
  local n = 0
  for id, e in pairs(self:List()) do
    if (v.npc and e.vendorNpc == v.npc) or (not v.npc and e.vendorName and e.vendorName == v.name) then
      local _, closest = ns.MapPin:RankVendors(ns.Vendor:Vendors(id), ns.MapPin:PlayerSpot())
      setVendor(e, closest)
      e.updated = time()
      n = n + 1
      ns.Print(string.format("Crafting list: %s now from %s.", e.name or ns.ItemName(id),
        e.vendorName and (e.vendorName .. " - " .. tostring(e.vendorZone)) or "no other friendly vendor known"))
    end
  end
  return n
end

function Shop:Add(s, qty, ahKey)
  ahKey = ahKey or ns.Ledger:LatestAHKey()
  local _, closest = ns.MapPin:RankVendors(s.vendors, ns.MapPin:PlayerSpot())
  local v = closest and closest.v or {}
  local list = self:List()
  local old = list[s.id]
  list[s.id] = {
    itemID = s.id, name = ns.ItemName(s.id), qty = math.max(1, math.floor(tonumber(qty) or 1)), bought = old and old.bought or 0,
    vendorUnit = s.buy, vendorSrc = s.src, ahUnit = s.ahUnit, margin = s.margin, ahKey = ahKey,
    added = old and old.added or time(), updated = time(),
  }
  setVendor(list[s.id], closest)
  self.counts[s.id] = self:BagCount(s.id)
  ns.Print(string.format("Crafting list: %s %s x%d (%s).", old and "updated" or "added", ns.ItemName(s.id), list[s.id].qty,
    v.name and (v.name .. " - " .. tostring(v.zone)) or "no friendly vendor known"))
  ns.CountUsage("shop:add")
  UI:Refresh()
end

function Shop:Remove(id, why)
  local list = self:List()
  local e = list[id]
  if not e then return end
  list[id] = nil
  self.counts[id], self.pending[id] = nil, nil
  -- flat history row for off-game analysis (PhyzanCapitalDB.shoppingLog, capped)
  local log = ns.db.shoppingLog or {}
  ns.db.shoppingLog = log
  log[#log + 1] = { char = ns.CharKey(), itemID = id, qty = e.qty, bought = e.bought or 0, vendorUnit = e.vendorUnit,
    ahUnit = e.ahUnit, margin = e.margin, added = e.added, removed = time(), reason = e.purchased and "purchased" or (why or "removed") }
  while #log > 500 do table.remove(log, 1) end
  ns.Print("Crafting list: removed " .. (e.name or ns.ItemName(id)) .. (why and (" (" .. why .. ")") or "") .. ".")
  UI:Refresh()
end

function Shop:SetQty(id, qty)
  local e = self:List()[id]
  qty = math.floor(tonumber(qty) or 0)
  if not e or qty < 1 then ns.Print("quantity must be 1 or more."); return false end
  e.qty = qty
  e.updated = time()
  if (e.bought or 0) >= qty then self:Remove(id, "already bought " .. e.bought) else UI:Refresh() end
  return true
end

function Shop:AskClear()
  local n = self:Count()
  if n == 0 then ns.Print("Crafting list is empty."); return end
  popup(string.format("Clear the crafting list (%d item%s)?", n, n == 1 and "" or "s"), function()
    local db = ns.db
    db.shopping[ns.CharKey()] = {}
    Shop.counts, Shop.pending = {}, {}
    ns.Print("Crafting list cleared.")
    ns.CountUsage("shop:clear")
    UI:Refresh()
  end)
end

-- Stored vendor as a Vendors()-style entry, so the map popup and distance use the closest-vendor logic.
function Shop:Vendor(e)
  if not e.vendorName then return nil end
  local v = { npc = e.vendorNpc, name = e.vendorName, zone = e.vendorZone, faction = e.vendorFaction, limited = e.vendorLimited,
    seasonal = e.vendorSeasonal, uiMapID = e.uiMapID, x = e.x, y = e.y, usable = true }
  local o = ns.Vendor:Observed(v) -- seen in game: its observed position wins
  if o then
    v.observed, v.seen = true, o.seen
    if o.uiMapID and o.x then v.uiMapID, v.x, v.y, v.zone = o.uiMapID, o.x, o.y, o.zone or v.zone end
  end
  v.missing = ns.Vendor:IsMissing(v) or nil
  return v
end
function Shop:AskMap(e)
  local v = self:Vendor(e)
  ns.MapPin:AskShow({ id = e.itemID, vendors = v and { v } or {} })
end

---------------------------------------------------------------------------
-- Purchases: while a merchant is open, a bag count increase of a listed item right after BuyMerchantItem for that
-- item counts as bought (without the hook: any increase while the merchant is open). Done = removed + chat line.
---------------------------------------------------------------------------
function Shop:BagCount(id)
  return ns.ItemCount(id) -- C_Item.GetItemCount (WoW Forever), else the old GetItemCount
end

local function merchantItemID(i)
  if type(GetMerchantItemLink) ~= "function" then return nil end
  local ok, link = pcall(GetMerchantItemLink, i)
  return ok and link and tonumber(tostring(link):match("item:(%d+)")) or nil
end

function Shop:Snapshot()
  self.counts = {}
  for id in pairs(self:List()) do self.counts[id] = self:BagCount(id) end
end

function Shop:CheckBags()
  local list = self:List()
  for id, e in pairs(list) do
    local now = self:BagCount(id)
    local before = self.counts[id]
    if now and before and now > before and self.merchantOpen
      and (not self.hooked or (self.pending[id] and time() - self.pending[id] <= 30)) then
      local got = now - before
      e.bought = (e.bought or 0) + got
      e.updated = time()
      if e.bought >= (e.qty or 1) then
        e.purchased = time()
        self:Remove(id, string.format("bought %d of %d", e.bought, e.qty))
      else
        ns.Print(string.format("Crafting list: bought %d %s, %d more to buy.", got, e.name or ns.ItemName(id), self:Remaining(e)))
        UI:Refresh()
      end
    end
    if list[id] then self.counts[id] = now end
  end
end

if type(hooksecurefunc) == "function" and type(BuyMerchantItem) == "function" then
  -- post-hook: only notes which listed item was bought; never calls anything itself
  hooksecurefunc("BuyMerchantItem", function(index)
    local ok, err = pcall(function()
      local id = merchantItemID(index)
      if id and Shop:List()[id] then Shop.pending[id] = time() end
    end)
    if not ok then pcall(ns.RecordError, "shopping hook", err) end
  end)
  Shop.hooked = true
end

ns.On("MERCHANT_SHOW", function()
  Shop.merchantOpen = true
  Shop:Snapshot()
  local list = Shop:List()
  if not next(list) or type(GetMerchantNumItems) ~= "function" then return end
  local ok, n = pcall(GetMerchantNumItems)
  for i = 1, (ok and tonumber(n)) or 0 do
    local id = merchantItemID(i)
    local e = id and list[id]
    if e then ns.Print(string.format("Crafting list: this vendor sells %s (need %d).", e.name or ns.ItemName(id), Shop:Remaining(e))) end
  end
end)
ns.On("MERCHANT_CLOSED", function()
  if Shop.merchantOpen then Shop:CheckBags() end
  Shop.merchantOpen = false
  Shop.pending = {}
end)
ns.On("BAG_UPDATE", function()
  if not Shop.merchantOpen or Shop.bagPending then return end
  Shop.bagPending = true
  ns.After(0.3, function() Shop.bagPending = false; Shop:CheckBags() end)
end)

---------------------------------------------------------------------------
-- Buttons on Blizzard's auction frame: created once, hidden; UI:ApplyBlizzardVisibility shows them only while our
-- window is open with 'Hide Blizzard's auction window' off, and hides them whenever our window closes.
---------------------------------------------------------------------------
function Shop:BlizzardButtons()
  local host = AuctionHouseFrame or AuctionFrame
  local scan = _G.PhyzanCapitalScanButton
  if not host or not scan then return end
  if not self.bOpen then
    self.bClear = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    self.bClear:SetSize(110, 22)
    self.bClear:SetText("Clear List")
    self.bClear:SetPoint("RIGHT", scan, "LEFT", -4, 0)
    self.bClear:SetScript("OnClick", function() Shop:AskClear() end)
    self.bOpen = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    self.bOpen:SetSize(110, 22)
    self.bOpen:SetText("Crafting List")
    self.bOpen:SetPoint("RIGHT", self.bClear, "LEFT", -4, 0)
    self.bOpen:SetScript("OnClick", function() UI:Show("shopping") end)
    self.bClear:Hide(); self.bOpen:Hide()
  end
  UI:ApplyBlizzardVisibility()
end
ns.On("AUCTION_HOUSE_SHOW", function() ns.After(0.6, function() Shop:BlizzardButtons() end) end)
ns.On("AUCTION_HOUSE_CLOSED", function() Shop:BlizzardButtons() end)

---------------------------------------------------------------------------
-- Crafting List tab
---------------------------------------------------------------------------
UI:RegisterTab("shopping", function(p)
  local S = UI.S
  local W = UI.PanelW()
  p.clear = UI.Button(p, "Clear Crafting List", 150, 22, function() Shop:AskClear() end)
  p.qtyLabel = UI.Label(p, "Quantity of selected:", "GameFontNormal")
  p.qty = UI.EditBox(p, 60, true)
  p.setQty = UI.Button(p, "Set", 60, 22, function()
    if p.selID then Shop:SetQty(p.selID, p.qty:GetText()) else ns.Print("click a row first.") end
  end)
  p.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if p.selID then Shop:SetQty(p.selID, self:GetText()) end end)
  p.sub = UI.Note(p, "", W - S(8))
  p.sub.text:SetFontObject(UI.Font("GameFontNormal"))
  p.sub:SetHeight(UI.LineH("GameFontNormal")); p.sub.text:SetHeight(UI.LineH("GameFontNormal"))
  local top = UI.Stack(p, { { flow = { p.clear, p.qtyLabel, p.qty, p.setQty } },
    { frame = p.sub, h = UI.LineH("GameFontNormal"), w = W - S(8) } }, S(4), -S(2), W - S(8), S(4))
  p.total = UI.Label(p, "", "GameFontNormal")
  p.total:SetPoint("BOTTOMLEFT", S(4), S(4))
  p.total:SetWidth(W - S(8)); p.total:SetHeight(UI.LineH("GameFontNormal"))
  if p.total.SetWordWrap then p.total:SetWordWrap(false) end
  p.list = UI.List(p, { { "Item", 240 }, { "Qty (bought / need)", 110 }, { "Vendor (zone, distance)", 380 }, { "Vendor / unit", 110 },
    { "AH now / unit", 110 }, { "Margin now / unit", 120 }, { "Map", 56 }, { "Not here", 86 }, { "Remove", 76 } },
    function(_, row) p.selID = row.data.itemID; p.qty:SetText(tostring(row.data.qty or 1)) end, 40,
    { sortable = true,
      actions = {
        { text = "Map", width = 48, tooltip = "See this vendor on the map", onClick = function(_, row) Shop:AskMap(row.data) end },
        { text = "Not here", width = 78, tooltip = "This vendor is not where Phyzan Capital says: mark it missing and use the next closest vendor",
          onClick = function(_, row)
            local v = Shop:Vendor(row.data)
            if v then ns.Vendor:AskMissing(v, row.data.itemID) else ns.Print("no vendor stored for this item.") end
          end },
        { text = "Remove", width = 68, tooltip = "Take this item off the crafting list", onClick = function(_, row) Shop:Remove(row.data.itemID, "removed by you") end },
      },
      onEnter = function(row, owner, hasItem)
        local e = row.data
        if not GameTooltip or not e then return end
        if not hasItem then GameTooltip:SetOwner(owner, "ANCHOR_CURSOR") end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("Added %s: vendor %s, AH %s, margin %s / unit", date("%Y-%m-%d %H:%M", e.added or 0),
          ns.Money(e.vendorUnit), ns.Money(e.ahUnit), ns.Money(e.margin)), 1, 1, 1, true)
        GameTooltip:AddLine("Click to select (edit the quantity above). Buying it from a vendor counts it down.", 0.7, 0.7, 0.7, true)
      end })
  p.list.frame:SetPoint("TOPLEFT", 0, top)
  p.list.frame:SetPoint("BOTTOMRIGHT", 0, UI.LineH("GameFontNormal") + S(8))
end, function(p)
  local ahKey = ns.Ledger:LatestAHKey()
  local ah = ns.AH(ahKey)
  local cut = ns.CutFor(ahKey)
  local spot = ns.MapPin:PlayerSpot()
  local rows, cost, profit, unknown = {}, 0, 0, 0
  for _, e in ipairs(Shop:Entries()) do
    local v = Shop:Vendor(e)
    local ranked = v and ns.MapPin:RankVendors({ v }, spot) or {}
    local c = ah.current[e.itemID]
    local ahNow = c and c.minUnit
    local margin = ahNow and e.vendorUnit and (ahNow * (1 - cut) - e.vendorUnit)
    local left = Shop:Remaining(e)
    cost = cost + (e.vendorUnit or 0) * left
    if margin then profit = profit + margin * left else unknown = unknown + 1 end
    local color = margin and (margin > 0 and "|cff00ff00" or "|cffff6060") or ""
    local row = { ns.ItemName(e.itemID), itemID = e.itemID, string.format("%d / %d", e.bought or 0, e.qty or 1),
      ranked[1] and (ns.MapPin:VendorText(ranked[1]) .. ns.MapPin.StateTag(ranked[1].v)) or "|cffff6060no friendly vendor known|r", ns.Money(e.vendorUnit),
      ahNow and ns.Money(ahNow) or "not in latest scan", margin and (color .. ns.Money(margin) .. "|r") or "-" }
    row.sort = { ns.ItemName(e.itemID), left, ranked[1] and (ranked[1].tier * 1e9 + (ranked[1].sortDist or 0)) or 1e12,
      e.vendorUnit or 0, ahNow or 0, margin or -1e12 }
    row.data = e
    rows[#rows + 1] = row
  end
  p.list:SetData(rows, true)
  local warn = UI.StaleWarning(ahKey)
  p.sub:SetText((warn and (warn .. "   ") or "") .. string.format("%d item%s for %s. AH prices from %s (cut %.0f%%).",
    #rows, #rows == 1 and "" or "s", ns.CharKey(), ahKey, cut * 100))
  p.total:SetText(string.format("Total vendor cost: %s     Estimated profit at current AH prices (after cut): %s%s", ns.Money(cost),
    ns.Money(profit), unknown > 0 and string.format("  (%d without an AH price)", unknown) or ""))
end)
