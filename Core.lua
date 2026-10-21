-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital Core: namespace, SavedVariables schema/migration, helpers, events, slash commands.
local addonName, ns = ...

ns.VERSION = "1.4.2"
ns.FEEDBACK_EMAIL = "kingofthefallllc@gmail.com"
ns.SCHEMA_VERSION = 8
ns.AH_CUT = 0.05 -- auction house cut on a sale (faction AH). Neutral AH cut is higher (15%), see ns.CutFor().

ns.PROFESSIONS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking",
                   "Tailoring", "Cooking", "First Aid", "Mining" }

local DEFAULT_SETTINGS = {
  dayStartHour = 7,        -- market day runs 07:00 -> 06:59 next day (local time)
  keepSnapshotDays = 14,   -- raw per-scan snapshots kept for this many market days
  maxSnapshotRows = 250000,-- hard cap on total raw listing rows kept (oldest scans dropped first)
  keepStatsDays = 120,     -- daily aggregates (dailyStats / estSales) kept this long
  autoOpen = true,         -- open the Phyzan Capital window when the auction house opens
  hideBlizzardAH = true,   -- make Blizzard's AuctionFrame invisible (alpha 0) while our window is shown
  hideSeasonalVendors = false, -- closest vendor: ignore vendors that only appear during world events (Darkmoon Faire, ...)
  textScale = 1.0,         -- size of all Phyzan Capital text (1.0 - 3.0, step 0.25); geometry scales with it (1.4.2: new installs 1.0, saved values kept)
  backend = "auto",        -- auction API: "auto", "modern" (C_AuctionHouse) or "legacy" (QueryAuctionItems)
  marketCategory = "",     -- Market tab: selected auction category path ("" = All, e.g. "Weapons/One-Handed/Daggers") (1.4.1)
  marketOpen = false,      -- Market tab: the selected category shows its sub-categories
  showCommands = true,     -- show the command list once per auction house visit when the window opens on Search (1.4.1)
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns.Print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then f:AddMessage("|cff33ff99Phyzan Capital|r: " .. table.concat(parts, " ")) end
end

function ns.ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("item:(%d+)")
  return id and tonumber(id) or nil
end

-- Parse "1g 20s 5c", "1g20s", "35s", "120c" or a plain number (copper). Returns copper or nil.
function ns.ParseMoney(str)
  if type(str) == "number" then return math.floor(str) end
  if type(str) ~= "string" then return nil end
  str = str:lower():gsub("%s+", "")
  if str == "" then return nil end
  if str:match("^%d+$") then return tonumber(str) end
  local total, matched = 0, false
  for num, unit in str:gmatch("(%d+)([gsc])") do
    matched = true
    num = tonumber(num)
    total = total + (unit == "g" and num * 10000 or unit == "s" and num * 100 or num)
  end
  if not matched or str:gsub("%d+[gsc]", "") ~= "" then return nil end
  return total
end

-- WoW's string.format raises "integer overflow attempting to store N" when %d/%i/%x get a value outside
-- the int32 range, and Lua's number..string concat switches to exponent notation at 1e14. Money values on
-- this server can exceed 2^31 copper (e.g. 539399281134), so every integer that may be large is formatted here.
function ns.IntStr(n)
  n = tonumber(n) or 0
  if n ~= n or n == math.huge or n == -math.huge then return "0" end
  return string.format("%.0f", n >= 0 and math.floor(n) or -math.floor(-n))
end

-- Persistent diagnostics (saved in PhyzanCapitalDB.debug, readable from disk after /reload).
function ns.DebugSet(key, value)
  if not ns.db then return end
  if type(ns.db.debug) ~= "table" then ns.db.debug = {} end
  ns.db.debug[key] = value
end
function ns.RecordError(where, msg, extra)
  local e = { ts = time(), where = tostring(where), msg = tostring(msg) }
  if type(extra) == "table" then for k, v in pairs(extra) do e[k] = v end end
  ns.DebugSet("lastError", e)
  if ns.db and type(ns.db.debug) == "table" then
    ns.db.debug.errorCount = (ns.db.debug.errorCount or 0) + 1
  end
  return e
end

-- Compact money string for edit boxes, e.g. "1g05s03c" (round-trips through ParseMoney).
function ns.MoneyInput(c)
  if not c then return "" end
  return (ns.Money(c):gsub(" ", ""))
end

function ns.Money(c)
  if not c then return "-" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, cc = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local out
  if g > 0 then out = string.format("%sg %02ds %02dc", ns.IntStr(g), s, cc)
  elseif s > 0 then out = string.format("%ds %02dc", s, cc)
  else out = string.format("%dc", cc) end
  return (neg and "-" or "") .. out
end

-- Market day key "YYYY-MM-DD": the calendar date on which the current 07:00 -> 06:59 window started.
-- Uses local time tables (date("*t")) so DST changes do not shift the boundary.
function ns.MarketDay(t)
  t = t or time()
  local startHour = (ns.db and ns.db.settings and ns.db.settings.dayStartHour) or 7
  local d = date("*t", t)
  if d.hour < startHour then
    d = date("*t", time({ year = d.year, month = d.month, day = d.day - 1, hour = 12 }))
  end
  return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

-- Day key N market days before the current one.
function ns.MarketDayOffset(n)
  local cur = ns.MarketDay()
  local y, m, d = cur:match("(%d+)-(%d+)-(%d+)")
  local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) - n, hour = 12 })
  return date("%Y-%m-%d", t)
end

function ns.After(sec, fn)
  if C_Timer and type(C_Timer.After) == "function" then
    C_Timer.After(sec, fn)
    return
  end
  local f = CreateFrame("Frame")
  local left = sec
  f:SetScript("OnUpdate", function(self, elapsed)
    left = left - elapsed
    if left <= 0 then self:SetScript("OnUpdate", nil); fn() end
  end)
end

-- Auction API backend, picked at runtime.
--   modern: retail-style C_AuctionHouse (ReplicateItems / SendBrowseQuery, AuctionHouseFrame)
--   legacy: QueryAuctionItems / GetAuctionItemInfo (AuctionFrame)
function ns.HasModernAH()
  return type(C_AuctionHouse) == "table" and (type(C_AuctionHouse.ReplicateItems) == "function"
    or type(C_AuctionHouse.SendBrowseQuery) == "function")
end
function ns.HasLegacyAH()
  return type(QueryAuctionItems) == "function" and type(GetAuctionItemInfo) == "function"
end
function ns.Backend()
  local pref = ns.db and ns.db.settings and ns.db.settings.backend or "auto"
  if pref == "modern" and ns.HasModernAH() then return "modern" end
  if pref == "legacy" and ns.HasLegacyAH() then return "legacy" end
  if ns.HasModernAH() then return "modern" end
  if ns.HasLegacyAH() then return "legacy" end
  return "none"
end

-- Diagnostics: printed by /capital debug and saved to db.debug.
function ns.Diagnostics()
  local function has(t, k) return (type(t) == "table" and type(t[k]) == "function") and true or false end
  local CA = C_AuctionHouse
  local d = {
    ts = time(), addonVersion = ns.VERSION, backend = ns.Backend(), backendSetting = ns.db and ns.db.settings.backend,
    ahOpen = ns.ahOpen and true or false,
    QueryAuctionItems = type(QueryAuctionItems) == "function", CanSendAuctionQuery = type(CanSendAuctionQuery) == "function",
    GetAuctionItemInfo = type(GetAuctionItemInfo) == "function", StartAuction = type(StartAuction) == "function",
    C_AuctionHouse = type(CA) == "table",
    ReplicateItems = has(CA, "ReplicateItems"), GetNumReplicateItems = has(CA, "GetNumReplicateItems"),
    GetReplicateItemInfo = has(CA, "GetReplicateItemInfo"), SendBrowseQuery = has(CA, "SendBrowseQuery"),
    GetBrowseResults = has(CA, "GetBrowseResults"), SendSearchQuery = has(CA, "SendSearchQuery"),
    PlaceBid = has(CA, "PlaceBid"), StartCommoditiesPurchase = has(CA, "StartCommoditiesPurchase"),
    PostItem = has(CA, "PostItem"), PostCommodity = has(CA, "PostCommodity"),
    GetProfessions = type(GetProfessions) == "function", GetSkillLineInfo = type(GetSkillLineInfo) == "function",
    C_Container = type(C_Container) == "table", ItemLocation = type(ItemLocation) == "table",
    C_ItemGetItemInfo = has(C_Item, "GetItemInfo"), GetItemInfo = type(GetItemInfo) == "function",
    C_MerchantFrame = has(C_MerchantFrame, "GetItemInfo"), GetMerchantItemInfo = type(GetMerchantItemInfo) == "function",
    C_TradeSkillUI = has(C_TradeSkillUI, "GetAllRecipeIDs"), GetTradeSkillLine = type(GetTradeSkillLine) == "function",
    C_SpellGetSpellName = has(C_Spell, "GetSpellName"), projectID = WOW_PROJECT_ID,
    AuctionFrame = AuctionFrame ~= nil, AuctionHouseFrame = AuctionHouseFrame ~= nil,
    scannerState = ns.Scanner and ns.Scanner.state, lastScanResult = ns.Scanner and ns.Scanner.lastResult and
      ((ns.Scanner.lastResult.ok and "ok" or "failed") .. ": " .. tostring(ns.Scanner.lastResult.reason or "")),
  }
  if type(GetBuildInfo) == "function" then
    local ok, v, b, dt, iface = pcall(GetBuildInfo)
    if ok then d.build, d.buildNumber, d.buildDate, d.interface = v, b, dt, iface end
  end
  return d
end

-- AH identity: realm + faction, or Neutral when standing in a goblin AH zone. The zone is found by uiMapID
-- (any client language: Stranglethorn Vale 1434, Tanaris 1446, Winterspring 1452, walking up from sub-maps),
-- with the English zone names as a fallback.
local NEUTRAL_ZONES = { ["Tanaris"] = true, ["Stranglethorn Vale"] = true, ["Winterspring"] = true }
local NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true }
local function inNeutralZone()
  local cm = type(C_Map) == "table" and C_Map or nil
  if cm and type(cm.GetBestMapForUnit) == "function" then
    local ok, id = pcall(cm.GetBestMapForUnit, "player")
    for _ = 1, 6 do
      if not ok or type(id) ~= "number" then break end
      if NEUTRAL_MAPS[id] then return true end
      local info = type(cm.GetMapInfo) == "function" and cm.GetMapInfo(id) or nil
      if type(info) ~= "table" or type(info.parentMapID) ~= "number" or (tonumber(info.mapType) or 0) <= 2 then break end
      id = info.parentMapID
    end
  end
  local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
  return NEUTRAL_ZONES[zone] and true or false
end
ns.InNeutralZone = inNeutralZone
function ns.CurrentAHKey()
  local realm = (GetRealmName and GetRealmName()) or "?"
  local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "?"
  if inNeutralZone() then faction = "Neutral" end
  return realm .. "-" .. faction
end

function ns.CutFor(ahKey)
  if ahKey and ahKey:find("%-Neutral$") then return 0.15 end
  return ns.AH_CUT
end

-- One line to paste into bug reports: add-on version, client version/build, interface, locale.
function ns.ReportLine()
  local v, b, iface
  if type(GetBuildInfo) == "function" then
    local ok, a1, a2, _, a4 = pcall(GetBuildInfo)
    if ok then v, b, iface = a1, a2, a4 end
  end
  local loc = type(GetLocale) == "function" and GetLocale() or nil
  return string.format("Phyzan Capital %s, client %s (build %s), interface %s%s", ns.VERSION, tostring(v or "?"), tostring(b or "?"),
    tostring(iface or "?"), loc and (", " .. tostring(loc)) or "")
end

function ns.CharKey()
  local n = (UnitName and UnitName("player")) or "?"
  local r = (GetRealmName and GetRealmName()) or "?"
  return n .. "-" .. r
end

---------------------------------------------------------------------------
-- Client API wrappers. WoW Forever runs the modern (Mainline) API: the old globals GetItemInfo, GetItemIcon,
-- GetItemInfoInstant, GetItemCount, GetSpellInfo, GetContainer*, GetMerchantItemInfo and GetTradeSkill* do not
-- exist there. Every wrapper prefers the namespaced API, falls back to the old global only if it exists, and
-- returns nil instead of raising an error.
---------------------------------------------------------------------------
local function apiFn(t, k) return type(t) == "table" and type(t[k]) == "function" and t[k] or nil end
ns.Fn = apiFn

-- Secret values (Midnight/Forever addon restrictions) must not be compared, indexed or stored as keys.
function ns.Plain(v)
  if v ~= nil and type(issecretvalue) == "function" then
    local ok, secret = pcall(issecretvalue, v)
    if ok and secret then return nil end
  end
  return v
end

-- Same return list as the old GetItemInfo (name, link, quality, ..., texture = 10th, sellPrice = 11th);
-- nothing while the item is not cached.
function ns.GetItemInfo(item)
  if item == nil then return nil end
  local f = apiFn(C_Item, "GetItemInfo") or (type(GetItemInfo) == "function" and GetItemInfo) or nil
  if not f then return nil end
  local r = { pcall(f, item) }
  if not r[1] then return nil end
  return unpack(r, 2, table.maxn(r))
end

-- Icon file ID for an item, or nil. GetItemIconByID / GetItemInfoInstant work even before the item is cached.
function ns.ItemIcon(id)
  if not id then return nil end
  local function try(f, pick)
    if not f then return nil end
    local r = { pcall(f, id) }
    if r[1] then return r[1 + pick] end
  end
  local icon = try(apiFn(C_Item, "GetItemIconByID"), 1)
    or try(apiFn(C_Item, "GetItemInfoInstant"), 5)
    or try(type(GetItemIcon) == "function" and GetItemIcon or nil, 1)
    or try(type(GetItemInfoInstant) == "function" and GetItemInfoInstant or nil, 5)
    or select(10, ns.GetItemInfo(id))
  if not icon and ns.db and ns.db.items and ns.db.items[id] then icon = ns.db.items[id].icon end
  return icon
end

-- Number of an item in the bags (C_Item.GetItemCount on modern clients). nil when unknown.
function ns.ItemCount(id)
  local f = apiFn(C_Item, "GetItemCount") or (type(GetItemCount) == "function" and GetItemCount) or nil
  if not f then return nil end
  local ok, n = pcall(f, id)
  return ok and tonumber(n) or nil
end

-- Localized spell name (C_Spell.GetSpellName / C_Spell.GetSpellInfo().name, else the old GetSpellInfo).
function ns.SpellName(id)
  local f = apiFn(C_Spell, "GetSpellName")
  if f then local ok, n = pcall(f, id); if ok and type(n) == "string" then return n end end
  f = apiFn(C_Spell, "GetSpellInfo")
  if f then local ok, t = pcall(f, id); if ok and type(t) == "table" and type(t.name) == "string" then return t.name end end
  if type(GetSpellInfo) == "function" then local ok, n = pcall(GetSpellInfo, id); if ok and type(n) == "string" then return n end end
  return nil
end

-- Bags: C_Container (table returns) with the old globals as fallback.
function ns.LastBag()
  return tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(NUM_BAG_SLOTS) or 4
end
function ns.BagNumSlots(bag)
  local f = apiFn(C_Container, "GetContainerNumSlots") or (type(GetContainerNumSlots) == "function" and GetContainerNumSlots) or nil
  if not f then return 0 end
  local ok, n = pcall(f, bag)
  return ok and tonumber(n) or 0
end
-- { count, link, locked, icon, itemID } for a bag slot, or nil when empty / unreadable.
function ns.BagItem(bag, slot)
  local f = apiFn(C_Container, "GetContainerItemInfo")
  if f then
    local ok, t = pcall(f, bag, slot)
    if not ok or type(t) ~= "table" then return nil end
    return { count = t.stackCount, link = t.hyperlink, locked = t.isLocked, icon = t.iconFileID,
      itemID = t.itemID or ns.ItemIDFromLink(t.hyperlink) }
  end
  if type(GetContainerItemInfo) ~= "function" then return nil end
  local ok, tex, count, locked, _, _, _, link, _, _, itemID = pcall(GetContainerItemInfo, bag, slot)
  if not ok or not count then return nil end
  if not link and type(GetContainerItemLink) == "function" then
    local ok2, l = pcall(GetContainerItemLink, bag, slot); if ok2 then link = l end
  end
  return { count = count, link = link, locked = locked, icon = tex, itemID = itemID or ns.ItemIDFromLink(link) }
end
function ns.PickupBagItem(bag, slot)
  local f = apiFn(C_Container, "PickupContainerItem") or (type(PickupContainerItem) == "function" and PickupContainerItem) or nil
  if f then pcall(f, bag, slot) end
end

-- Item cache in SavedVariables (name, quality, vendor sell price, stack size, icon).
-- When called without a name (display paths) and the client has not cached the item yet, the item is requested;
-- ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED then fill in the sell price (Items.lua).
function ns.TouchItem(id, name, quality)
  if not id or not ns.db then return end
  local it = ns.db.items[id]
  if not it then it = {}; ns.db.items[id] = it end
  if name and name ~= "" then it.name = name end
  if type(quality) == "number" and quality >= 0 then it.quality = quality end -- replicate rows report -1 when not loaded
  if it.sellPrice == nil then
    local n, _, q, _, _, _, _, stack, _, tex, sell = ns.GetItemInfo(id)
    if n then
      it.name = it.name or n
      it.quality = it.quality or q
      it.stack = stack
      it.sellPrice = sell or 0
      if tex and not it.icon then it.icon = tex end
    elseif name == nil and ns.Items and ns.Items.Request then
      ns.Items:Request(id)
    end
  end
  return it
end

-- Display name for an itemID; never a bare number (see Items.lua).
function ns.ItemName(id)
  if ns.Items then return ns.Items:Name(id) end
  local it = ns.db and ns.db.items[id]
  return (it and it.name) or ("Item #" .. tostring(id))
end
function ns.ItemLabel(id, noIcon)
  if ns.Items then return ns.Items:Label(id, noIcon) end
  return ns.ItemName(id)
end

-- Lightweight usage/query log: counts how often each view or command is used.
function ns.CountUsage(key)
  if not ns.db then return end
  ns.db.usage[key] = (ns.db.usage[key] or 0) + 1
  ns.db.usageLast[key] = time()
end

---------------------------------------------------------------------------
-- SavedVariables (documented in README.md, "SavedVariables schema")
---------------------------------------------------------------------------
local function ensure(t, k, v)
  if type(t[k]) ~= "table" then t[k] = v or {} end
  return t[k]
end

function ns.InitDB(fresh)
  if fresh or type(PhyzanCapitalDB) ~= "table" then PhyzanCapitalDB = {} end
  local db = PhyzanCapitalDB
  if db.schemaVersion and db.schemaVersion > ns.SCHEMA_VERSION then
    ns.Print("SavedVariables were written by a newer Phyzan Capital (schema " .. db.schemaVersion .. "). Data kept, but some features may misbehave.")
  end
  -- Migrations
  if db.schemaVersion and db.schemaVersion < 2 then
    -- v1 stored global manual skills/level; keep them as pending overrides for the first character that logs in
    if type(db.professions) == "table" and next(db.professions) then db.pendingV1Overrides = db.professions end
    db.professions, db.observedSkills = nil, nil
    if db.settings then db.settings.charLevel = nil end
    db.schemaVersion = 2
  end
  if db.schemaVersion and db.schemaVersion < 3 then
    -- v3: usage key tab:flips renamed to tab:swaps; scans may carry aggregated=true (modern browse scans)
    if type(db.usage) == "table" and db.usage["tab:flips"] then
      db.usage["tab:swaps"] = (db.usage["tab:swaps"] or 0) + db.usage["tab:flips"]
      db.usage["tab:flips"] = nil
      if type(db.usageLast) == "table" then
        db.usageLast["tab:swaps"] = db.usageLast["tab:swaps"] or db.usageLast["tab:flips"]
        db.usageLast["tab:flips"] = nil
      end
    end
    db.schemaVersion = 3
  end
  if db.schemaVersion and db.schemaVersion < 4 then
    db.schemaVersion = 4 -- 1.2.2: adds shopping / shoppingLog (new tables, nothing to convert)
  end
  if db.schemaVersion and db.schemaVersion < 5 then
    db.schemaVersion = 5 -- 1.2.3: adds observedVendors / vendorMissing (new tables, nothing to convert)
  end
  if db.schemaVersion and db.schemaVersion < 6 then
    db.schemaVersion = 6 -- 1.2.7: ah[*].lastKnown / ah[*].history, filled once from older data by Ledger:SeedLookup
  end
  if db.schemaVersion and db.schemaVersion < 7 then
    -- 1.3.0: 1.2.9 stored Tailoring and Cooking recipes a second time under "Fishing" (the Fishing window still
    -- returned the previous recipe list). Fishing, Herbalism and Skinning have no recipes: drop those entries.
    local dropped = 0
    for key, r in pairs(type(db.recipes) == "table" and db.recipes or {}) do
      local prof = (type(r) == "table" and r.prof) or tostring(key):match("^([^:]+):")
      if prof == "Fishing" or prof == "Herbalism" or prof == "Skinning" then db.recipes[key] = nil; dropped = dropped + 1 end
    end
    if dropped > 0 then
      if type(db.debug) ~= "table" then db.debug = {} end
      db.debug.recipesDropped = { ts = time(), n = dropped, why = "recorded under a gathering skill" }
    end
    db.schemaVersion = 7
  end
  if db.schemaVersion and db.schemaVersion < 8 then
    -- 1.4.0: no Sell/Post and no Vendor Swaps. Their saved data and settings are dropped; the crafting list keeps
    -- its key (db.shopping / db.shoppingLog), so every list entry survives unchanged.
    db.postLog = nil
    if type(db.settings) == "table" then
      for _, k in ipairs({ "undercut", "durationMode", "defaultDuration", "swapsOnlyProfitable", "postMode" }) do db.settings[k] = nil end
    end
    if type(db.debug) == "table" then db.debug.directPostBlocked, db.debug.postMode = nil, nil end
    db.schemaVersion = 8
  end
  db.schemaVersion = db.schemaVersion or ns.SCHEMA_VERSION
  db.addonVersion = ns.VERSION
  db.createdAt = db.createdAt or time()
  local s = ensure(db, "settings")
  for k, v in pairs(DEFAULT_SETTINGS) do if s[k] == nil then s[k] = v end end
  ensure(db, "chars")           -- ["Name-Realm"] = {level, professions = {[prof] = {rank, max, source, ts}}, lastDetect}
  ensure(db, "overrides")       -- ["Name-Realm"] = {level, professions = {[prof] = skill}} (hidden manual overrides)
  ensure(db, "items")           -- [itemID] = {name, quality, sellPrice, stack}
  ensure(db, "scans")           -- array of scan metadata
  ensure(db, "snapshots")       -- [scanID] = array of pipe-delimited listing rows
  ensure(db, "ah")              -- [ahKey] = {dailyStats, estSales, current, priceSamples}
  ensure(db, "vendorPrices")    -- [itemID] = recorded merchant buy price
  ensure(db, "recipes")         -- ["Prof:productItemID"] = recorded recipe
  ensure(db, "usage")           -- [key] = count
  ensure(db, "usageLast")       -- [key] = last-used unix time
  ensure(db, "shopping")        -- ["Name-Realm"] = {[itemID] = crafting list entry} (schema 4)
  ensure(db, "shoppingLog")     -- array of removed/purchased shopping entries (schema 4, last 500)
  ensure(db, "observedVendors") -- [npcID or "name:<name>"] = merchant seen in game: location + inventory (schema 5)
  ensure(db, "vendorMissing")   -- [npcID or "name:<name>"] = {npc, name, zone, itemID, ts} "vendor not here" marks (schema 5)
  db.nextScanID = db.nextScanID or 1
  ns.db = db
  return db
end

function ns.AH(ahKey)
  local a = ensure(ns.db.ah, ahKey)
  ensure(a, "dailyStats")   -- [day][itemID] = scalar stats row
  ensure(a, "estSales")     -- [day][itemID] = estimated sales/expirations
  ensure(a, "current")      -- [itemID] = latest complete scan summary
  ensure(a, "priceSamples") -- [day][itemID] = {unit prices}, used for the median; only recent days kept
  ensure(a, "lastKnown")    -- [itemID] = {u = lowest unit buyout, t = scan time, n, q} (offline price lookup, 1.2.7)
  ensure(a, "history")      -- [itemID] = "day:low:median;..." last 14 market days (offline price lookup, 1.2.7)
  return a
end

-- Effective skill for the current character: hidden manual override, else detected.
function ns.GetProfSkill(prof)
  return (ns.Char:Skill(prof))
end

function ns.GetCharLevel()
  return (ns.Char:Level())
end

function ns.NormalizeProf(s)
  if not s then return nil end
  local exact = ns.Char and ns.Char:Canonical(s)
  if exact then return exact end
  s = s:lower()
  for _, sk in ipairs(ns.Char.SKILLS) do
    local pl = sk[1]:lower()
    if #s >= 3 and pl:sub(1, #s) == s then return sk[1] end
  end
  return nil
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.handlers = {}
function ns.On(event, fn)
  ns.handlers[event] = ns.handlers[event] or {}
  table.insert(ns.handlers[event], fn)
  if ns.eventFrame then pcall(ns.eventFrame.RegisterEvent, ns.eventFrame, event) end
end

local ef = CreateFrame("Frame")
ns.eventFrame = ef
ef:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == addonName then
      ns.InitDB()
      -- debug fields that must never go stale: version and load time are refreshed on every load
      pcall(ns.DebugSet, "addonVersion", ns.VERSION)
      pcall(ns.DebugSet, "loadedTs", time())
      pcall(ns.DebugSet, "scannerState", "idle") -- a new session starts idle
      if ns.Ledger and ns.Ledger.SeedLookup then pcall(ns.Ledger.SeedLookup, ns.Ledger) end
      if ns.Ledger and ns.Ledger.Prune then pcall(ns.Ledger.Prune, ns.Ledger) end
    end
    return
  end
  if not ns.db then return end
  local list = ns.handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, event, ...)
    if not ok then
      ns.Print("error in " .. event .. ": " .. tostring(err))
      pcall(ns.RecordError, "event " .. event, err)
    end
  end
end)
pcall(ef.RegisterEvent, ef, "ADDON_LOADED")
for ev in pairs(ns.handlers) do pcall(ef.RegisterEvent, ef, ev) end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- One list for the chat help and the command popup (UI:ShowCommands). Only commands that exist.
-- chatOnly: troubleshooting commands listed by /capital help in chat but not in the popup window
local HELP_COMMANDS = {
  { "/capital", "open or close the window (also /pc, /ahl)" },
  { "/capital help", "this list" },
  { "/capital search", "Search / Browse (away from the AH: Price Lookup)" },
  { "/capital prices", "Price Lookup: saved prices, anywhere" },
  { "/capital price <item>", "last auction price in chat (part of a name works)" },
  { "/capital buy", "Buy tab: selected auction, custom bid" },
  { "/capital market", "Market tab by auction category" },
  { "/capital craftlist", "Crafting List (craftlist clear empties it)" },
  { "/capital professions", "Professions: recipes, costs, profit" },
  { "/capital settings", "Settings tab" },
  { "/capital feedback", "where to send suggestions and bug reports" },
  { "/capital profs", "your level and professions (refresh: detect again)" },
  { "/capital status", "scan and data summary" },
  { "/capital vendors", "vendors seen / 'not here' (vendors reset)" },
  { "/capital textsize <1-3>", "text size, e.g. 1.5 or 2 (default 1)" },
  { "/capital autoopen on|off", "open with the auction house" },
  { "/capital hideblizzard on|off", "hide Blizzard's auction window" },
  { "/capital debug", "auction API info for troubleshooting" },
  { "/capital backend auto|modern|legacy", "force the auction API (default auto)", chatOnly = true },
  { "/capital setcap N", "raw listing rows kept (default 250000)", chatOnly = true },
  { "/capital reset", "wipe scans, prices and recipes (asks first)" },
}
ns.HELP_COMMANDS = HELP_COMMANDS
local HELP = {}
for _, c in ipairs(HELP_COMMANDS) do HELP[#HELP + 1] = c[1] .. " - " .. c[2] end
HELP[#HELP + 1] = "Scanning: with the auction house open, click 'Scan Auction House' (full scan about every 15 min, otherwise one page per click; right-click aborts)."
HELP[#HELP + 1] = "Every search, bid and buyout needs your click; nothing is automated. Sell in Blizzard's own auction house window."

local function status()
  local db = ns.db
  local n, rows, last = 0, 0, nil
  for _, s in ipairs(db.scans) do
    n = n + 1
    if not s.pruned then rows = rows + (s.rows or 0) end
    last = s
  end
  local vend, rec = 0, 0
  for _ in pairs(db.vendorPrices) do vend = vend + 1 end
  for _ in pairs(db.recipes) do rec = rec + 1 end
  ns.Print(string.format("schema v%d, %d scans (%d raw rows kept), %d recorded vendor prices, %d recorded recipes, market day %s",
    db.schemaVersion, n, rows, vend, rec, ns.MarketDay()))
  if last then
    ns.Print(string.format("last scan #%d %s (%s, %s, %d rows) at %s", last.id, last.ahKey or "?", last.mode,
      last.complete and "complete" or "partial", last.rows or 0, date("%Y-%m-%d %H:%M", last.ts)))
  end
end
ns.Status = status

local TAB_ALIASES = { search = "search", browse = "search", buy = "buy",
  market = "market", volume = "market", prices = "prices", lookup = "prices", crafts = "crafts", professions = "crafts", profs = "crafts", prof = "crafts", recipes = "crafts", settings = "settings" }
-- removed in 1.4.0: selling happens in Blizzard's window, Vendor Swaps is gone
local REMOVED = { sell = "Sell / Post", post = "Sell / Post", postmode = "Sell / Post", undercut = "Sell / Post",
  durationmode = "Sell / Post", swaps = "Vendor Swaps", flips = "Vendor Swaps" }

local function onOff(v)
  v = (v or ""):lower()
  if v == "on" or v == "1" or v == "true" then return true end
  if v == "off" or v == "0" or v == "false" then return false end
  return nil
end


SLASH_PHYZANCAPITAL1 = "/capital"
SLASH_PHYZANCAPITAL2 = "/pc"
SLASH_PHYZANCAPITAL3 = "/ahl"
SlashCmdList["PHYZANCAPITAL"] = function(msg)
  if not ns.db then ns.InitDB() end
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  ns.CountUsage("cmd:" .. (cmd == "" and "toggle" or cmd))
  local st = ns.db.settings
  if cmd == "" or cmd == "show" or cmd == "toggle" then
    if ns.UI then ns.UI:Toggle() end
  elseif cmd == "price" or cmd == "pricecheck" then
    ns.Lookup:Chat(rest)
  elseif cmd == "feedback" or cmd == "bug" or cmd == "contact" then
    ns.Print("suggestions and bug reports: " .. ns.FEEDBACK_EMAIL .. " (" .. ns.ReportLine() .. ")")
    if ns.UI and ns.UI.ShowFeedback then ns.UI:ShowFeedback("cmd") end
  elseif cmd == "help" or cmd == "commands" then
    for _, l in ipairs(HELP) do ns.Print(l) end
    if ns.UI and ns.UI.ShowCommands then ns.UI:ShowCommands("help") end
  elseif cmd == "craftlist" or cmd == "crafting" or cmd == "craftinglist" or cmd == "list" or cmd == "shopping" then -- "shopping": old name, hidden alias
    if rest:lower() == "clear" then ns.Shop:AskClear() elseif ns.UI then ns.UI:Show("shopping") end
  elseif cmd == "vendors" or cmd == "vendor" then
    if rest:lower() == "reset" then ns.Vendor:ResetMissing()
    else
      local seen, miss = 0, 0
      for _ in pairs(ns.db.observedVendors) do seen = seen + 1 end
      for _, m in pairs(ns.db.vendorMissing) do
        miss = miss + 1
        ns.Print(string.format("  not here: %s (%s), marked %s", tostring(m.name), tostring(m.zone), date("%Y-%m-%d %H:%M", m.ts or 0)))
      end
      ns.Print(string.format("%d vendor(s) seen in game, %d marked 'not here' (/capital vendors reset clears the marks).", seen, miss))
    end
  elseif REMOVED[cmd] then
    ns.Print(REMOVED[cmd] .. " was removed in 1.4.0" .. (REMOVED[cmd] == "Sell / Post"
      and ": the game blocks add-on posting, so sell in Blizzard's own auction house window." or "."))
  elseif TAB_ALIASES[cmd] then
    if ns.UI then ns.UI:Show(TAB_ALIASES[cmd]) end
  elseif cmd == "refresh" then
    ns.Char:Refresh("slash")
    local a, b = ns.Char:Summary()
    ns.Print(a .. " - " .. b)
  elseif cmd == "profs" then
    local a, b = ns.Char:Summary()
    ns.Print(a .. " - " .. b .. (ns.Char:HasOverrides() and "  (* = manual override, /capital clearoverride)" or ""))
  -- Hidden manual overrides (not in help): win over detection for this character until cleared.
  elseif cmd == "setlevel" then
    local n = tonumber(rest)
    if n and n >= 1 and n <= 60 then
      ns.Char:SetOverride("level", nil, math.floor(n))
      ns.Print("level override " .. math.floor(n) .. " (clear with /capital clearoverride)")
    else ns.Print("usage: /capital setlevel N (1-60)") end
  elseif cmd == "setprof" then
    local name, skill = rest:match("^(.-)%s+(%d+)$")
    local prof = ns.NormalizeProf(name)
    skill = tonumber(skill)
    if prof and skill and skill >= 0 and skill <= 300 then
      ns.Char:SetOverride("prof", prof, skill > 0 and skill or nil)
      ns.Print(prof .. " override " .. (skill > 0 and skill or "removed") .. " (clear all with /capital clearoverride)")
    else
      ns.Print("usage: /capital setprof <profession> <skill 0-300>")
    end
  elseif cmd == "clearoverride" or cmd == "clearoverrides" then
    ns.Char:ClearOverrides()
    ns.Char:Refresh("clear override")
    ns.Print("manual overrides cleared; using detected level and skills.")
  elseif cmd == "setcap" then
    local n = tonumber(rest)
    if n and n >= 1000 then
      st.maxSnapshotRows = math.floor(n)
      ns.Ledger:Prune()
      ns.Print("raw row cap set to " .. st.maxSnapshotRows)
    else ns.Print("usage: /capital setcap N (>= 1000)") end
  elseif cmd == "autoopen" or cmd == "hideblizzard" then
    local v = onOff(rest)
    if v == nil then ns.Print("usage: /capital " .. cmd .. " on|off") else
      if cmd == "autoopen" then st.autoOpen = v else st.hideBlizzardAH = v end
      ns.Print(cmd .. " " .. (v and "on" or "off"))
      if ns.UI then ns.UI:ApplyBlizzardVisibility() end
    end
  elseif cmd == "status" then
    status()
  elseif cmd == "debug" then
    local d = ns.Diagnostics()
    if type(ns.db.debug) ~= "table" then ns.db.debug = {} end
    for k, v in pairs(d) do ns.db.debug[k] = v end -- keep lastScan / lastError / replicate info
    local keys = {}
    for k in pairs(d) do keys[#keys + 1] = k end
    table.sort(keys)
    ns.Print("debug (saved to SavedVariables as PhyzanCapitalDB.debug; /reload to write it to disk):")
    local line = {}
    for _, k in ipairs(keys) do
      local v = d[k]
      line[#line + 1] = k .. "=" .. (type(v) == "number" and ns.IntStr(v) or tostring(v))
      if #line == 6 then ns.Print(table.concat(line, ", ")); line = {} end
    end
    if #line > 0 then ns.Print(table.concat(line, ", ")) end
    local dbg = ns.db.debug
    if type(dbg.lastScan) == "table" then
      local ls = dbg.lastScan
      ns.Print(string.format("last scan: %s, %s, total %s, read %s, missing %s, items %s, %s", tostring(ls.mode), tostring(ls.result),
        ns.IntStr(ls.total), ns.IntStr(ls.rows), ns.IntStr(ls.missing), ns.IntStr(ls.items), tostring(ls.reason or "")))
    end
    if type(dbg.lastError) == "table" then
      ns.Print(string.format("last error (%s): %s%s", tostring(dbg.lastError.where), tostring(dbg.lastError.msg),
        dbg.lastError.index and (" at row " .. ns.IntStr(dbg.lastError.index)) or ""))
    end
  elseif cmd == "textsize" or cmd == "textscale" then
    local v = tonumber((rest:gsub("[xX]$", "")))
    if v and ns.UI then
      local applied = ns.UI:SetTextScale(v)
      ns.Print(string.format("text size %.2fx%s", applied, applied ~= v and " (allowed: 1.0 - 3.0 in steps of 0.25)" or ""))
    else ns.Print(string.format("usage: /capital textsize <1.0 - 3.0> (now %.2fx)", tonumber(st.textScale) or 1)) end
  elseif cmd == "backend" then
    rest = rest:lower()
    if rest == "auto" or rest == "modern" or rest == "legacy" then
      st.backend = rest
      ns.Print("backend setting " .. rest .. " -> using " .. ns.Backend())
    else ns.Print("usage: /capital backend auto|modern|legacy (now: " .. st.backend .. " -> " .. ns.Backend() .. ")") end
  elseif cmd == "reset" then
    local function wipe()
      local keep = { "settings", "chars", "overrides", "usage", "usageLast", "shopping", "shoppingLog", "observedVendors", "vendorMissing" }
      local saved = {}
      for _, k in ipairs(keep) do saved[k] = ns.db[k] end
      ns.InitDB(true)
      for _, k in ipairs(keep) do ns.db[k] = saved[k] end
      if ns.Ledger then ns.Ledger.lastMS = nil end
      ns.Print("all scan, vendor and recipe data wiped (settings, characters, crafting list and usage counters kept).")
      if ns.UI then ns.UI:Refresh() end
    end
    if ns.UI and ns.UI.Confirm then
      ns.UI:Confirm({ which = "reset", text = "Delete all scans, stats, vendor prices and recorded recipes?\n\n" ..
        "Settings, characters, the crafting list and usage counters are kept.", onYes = wipe })
    elseif rest:lower() == "confirm" then wipe()
    else ns.Print("Type '/capital reset confirm' to delete all scans, stats, vendor prices and recorded recipes.") end
  else
    ns.Print("unknown command '" .. cmd .. "'. /capital help")
  end
end
