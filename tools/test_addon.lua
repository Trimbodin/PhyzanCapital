-- Off-game smoke test: runs the addon against a mocked WoW API in plain Lua 5.1.
-- Usage (from the addon folder): lua5.1 tools/test_addon.lua [out_savedvariables.lua]
local OUT = arg[1] or "/tmp/PhyzanCapital_SV.lua"
local clock = os.time({ year = 2026, month = 10, day = 17, hour = 9, min = 0 })
time = function(t) if t then return os.time(t) end return clock end
date = function(f, t) return os.date(f, t or clock) end

-- Emulate WoW's string.format: %d/%i/%x/%X/%c/%o/%u with a value outside int32 raises
-- "integer overflow attempting to store N" (plain Lua 5.1 on 64-bit silently accepts it).
do
  local realFormat = string.format
  local function wowFormat(fmt, ...)
    local args, n = { ... }, select("#", ...)
    local ai = 0
    for flags, conv in tostring(fmt):gmatch("%%([-+ #0]*%d*%.?%d*)([%a%%])") do
      if conv ~= "%" then
        ai = ai + 1
        if conv:match("[dixXcou]") then
          local v = args[ai]
          if type(v) == "number" and (v > 2147483647 or v < -2147483648) then
            error("integer overflow attempting to store " .. realFormat("%.0f", v), 2)
          end
        end
      end
    end
    local _ = n
    return realFormat(fmt, ...)
  end
  string.format = wowFormat
end

-- generic mock widget (geometry, fonts and text metrics from tools/mock_geometry.lua)
local GEO = dofile("tools/mock_geometry.lua")
GEO.installFonts()
local registry = {}
local mock
local function child(parent, o) if parent then parent._children = parent._children or {}; table.insert(parent._children, o) end end
mock = function(name)
  local o = { _scripts = {}, _shown = true, _text = "", _checked = false, _name = name }
  return setmetatable(o, { __index = function(t, k)
    if type(k) == "string" and not k:match("^%u") then return nil end -- fields (and private mock state) are nil unless set
    if k == "GetFontString" then return nil end -- only template buttons have one (set in CreateFrame)
    if (k == "GetStringWidth" or k == "GetStringHeight" or k == "IsTruncated" or k == "SetWordWrap") and not rawget(t, "_isFS") then return nil end
    local impl = {
      SetScript = function(self, s, f) self._scripts[s] = f end,
      GetScript = function(self, s) return self._scripts[s] end,
      HookScript = function(self, s, f)
        local old = self._scripts[s]
        self._scripts[s] = function(...) if old then old(...) end; f(...) end
      end,
      Show = function(self) local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end,
      Hide = function(self) local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end,
      IsShown = function(self) return self._shown end,
      SetText = function(self, s) self._text = s end,
      GetText = function(self) return self._text end,
      GetName = function(self) return self._name end,
      SetChecked = function(self, v) self._checked = v and true or false end,
      GetChecked = function(self) return self._checked end,
      CreateFontString = function(self, _, _, font)
        local fs = mock(); fs._isFS = true; fs._parent = self; fs._font = font; child(self, fs); return fs
      end,
      CreateTexture = function(self) local tx = mock(); tx._isTex = true; tx._parent = self; child(self, tx); return tx end,
      RegisterEvent = function(self, e) registry[e] = registry[e] or {}; table.insert(registry[e], self) end,
      SetAlpha = function(self, a) self._alpha = a end,
      SetFrameStrata = function(self, st) self._strata = st end,
    }
    local f = impl[k] or GEO.methods[k] or function() end
    rawset(t, k, f)
    return f
  end })
end
CreateFrame = function(kind, name, parent, template)
  local f = mock(name)
  f._parent, f._kind, f._template = parent, kind, template
  child(parent, f)
  if name then _G[name] = f end
  if template and tostring(template):find("UIPanelButtonTemplate", 1, true) then
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", f, "CENTER", 0, 0)
    f._fs = fs
    f.GetFontString = function() return fs end
    f.SetText = function(self, s) self._text = s; fs._text = s end
    f.SetNormalFontObject = function(_, o) fs._font = o end
  end
  if template and tostring(template):find("InputBoxTemplate", 1, true) then f._font = "ChatFontNormal" end
  return f
end
UIParent = mock("UIParent"); UIParent._isScreen = true
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print((m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end }
UISpecialFrames = {}
StaticPopupDialogs = {}
local lastPopup
StaticPopup_Show = function(which, text, _, data)
  local dialog = mock("StaticPopup1")
  lastPopup = { which = which, text = text, data = data, dialog = dialog }
  return dialog
end
SlashCmdList = {}
local timers = {}
local holdLong, longTimers = false, {} -- holdLong: timers of 10 s or more (timeouts) wait in longTimers, not run by flush()
C_Timer = { After = function(s, f) if holdLong and (tonumber(s) or 0) >= 10 then table.insert(longTimers, f) else table.insert(timers, f) end end }
local function flush() for _ = 1, 20 do local t = timers; timers = {}; if #t == 0 then return end; for _, f in ipairs(t) do f() end end end
GetRealmName = function() return "Forever" end
UnitFactionGroup = function() return "Alliance" end
UnitName = function(u) if u == "npc" then return "Tharynn Bouden" end return "Fredrick" end
GetRealZoneText = function() return "Stormwind City" end
IsShiftKeyDown = function() return false end
GetMoney = function() return 1000000 end
local playerLevel = 37
UnitLevel = function() return playerLevel end
GetSpellInfo = function(id) local m = { [3908] = "Tailoring", [2550] = "Cooking" }; return m[id] end
-- classic skills pane: headers can be collapsed; rows: {name, isHeader, isExpanded, rank, max}
local skillTree = {
  { "Class Skills", true, true, { { "Defense", 185, 185 } } },
  { "Professions", true, false, { { "Tailoring", 142, 150 }, { "Herbalism", 88, 150 } } },
  { "Secondary Skills", true, false, { { "Cooking", 60, 75 }, { "First Aid", 120, 150 } } },
}
local function skillRows()
  local rows = {}
  for _, h in ipairs(skillTree) do
    rows[#rows + 1] = { h[1], true, h[3] }
    if h[3] then for _, c in ipairs(h[4]) do rows[#rows + 1] = { c[1], false, false, c[2], c[3] } end end
  end
  return rows
end
GetNumSkillLines = function() return #skillRows() end
GetSkillLineInfo = function(i) local r = skillRows()[i]; if not r then return nil end
  return r[1], r[2], r[3], r[4] or 0, 0, 0, r[5] or 0, false, nil, nil, 0, 0, "" end
local function headerAt(i) local r = skillRows()[i]; for _, h in ipairs(skillTree) do if h[1] == r[1] then return h end end end
ExpandSkillHeader = function(i) headerAt(i)[3] = true end
CollapseSkillHeader = function(i) headerAt(i)[3] = false end
local ITEMS = { [2589] = { "Linen Cloth", 1, 20, 13 }, [2996] = { "Bolt of Linen Cloth", 1, 20, 40 },
  [2320] = { "Coarse Thread", 1, 20, 2 }, [2604] = { "Red Dye", 1, 20, 12 }, [2572] = { "Red Linen Robe", 2, 1, 120 },
  [1251] = { "Linen Bandage", 1, 20, 10 }, [2321] = { "Fine Thread", 1, 20, 25 }, [2569] = { "Linen Boots", 1, 1, 22 } }
GetItemInfo = function(id)
  local it = ITEMS[id]; if not it then return nil end
  return it[1], "item:" .. id, it[2], 1, 1, "Trade Goods", "Cloth", it[3], "", "tex", it[4]
end

-- AH mock
AuctionFrame = mock("AuctionFrame")
local auctions, list = {}, {}
local function addAuction(id, count, minBid, buyout, tl, seller) table.insert(auctions, { id, count, minBid, buyout, tl, seller, 0 }) end
CanSendAuctionQuery = function() return true, true end
QueryAuctionItems = function(name, _, _, page, _, _, getAll)
  list = {}
  if getAll then for i, a in ipairs(auctions) do list[i] = a end
  else
    local matches = {}
    for _, a in ipairs(auctions) do if name == "" or ITEMS[a[1]][1]:lower():find(name:lower(), 1, true) then matches[#matches + 1] = a end end
    for i = page * 50 + 1, math.min(#matches, page * 50 + 50) do list[#list + 1] = matches[i] end
    list.total = #matches
  end
end
GetNumAuctionItems = function() return #list, list.total or #list end
GetAuctionItemInfo = function(_, i)
  local a = list[i]; if not a then return nil end
  return ITEMS[a[1]][1], "tex", a[2], 1, true, 1, "REQ", a[3], 5, a[4], a[7], false, nil, a[6], a[6], 0, a[1], true
end
GetAuctionItemTimeLeft = function(_, i) return list[i] and list[i][5] end
GetAuctionItemLink = function(_, i) return list[i] and ("|Hitem:" .. list[i][1] .. ":0|h") end
local bids = {}
PlaceAuctionBid = function(_, i, amount) table.insert(bids, { i, amount }) end

-- merchant / tradeskill / bags mocks
GetMerchantNumItems = function() return 2 end
GetMerchantItemInfo = function(i) if i == 1 then return "Coarse Thread", "t", 10, 1, -1, true, true, false end return "Red Dye", "t", 50, 1, -1, true, true, false end
GetMerchantItemLink = function(i) return i == 1 and "item:2320" or "item:2604" end
local bagCounts = {}
GetItemCount = function(id) return bagCounts[id] or 0 end
BuyMerchantItem = function(i, qty) local id = i == 1 and 2320 or 2604; bagCounts[id] = (bagCounts[id] or 0) + (qty or 1) end
hooksecurefunc = function(name, fn) local orig = _G[name]; _G[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end end
GetTradeSkillLine = function() return "Tailoring", 145, 150 end
GetNumTradeSkills = function() return 2 end
GetTradeSkillInfo = function(i) if i == 1 then return "Cloth", "header" end return "Red Linen Robe", "optimal" end
GetTradeSkillItemLink = function() return "item:2572" end
GetTradeSkillNumMade = function() return 1, 1 end
GetTradeSkillNumReagents = function() return 3 end
local R = { { 2996, 3 }, { 2320, 2 }, { 2604, 2 } }
GetTradeSkillReagentInfo = function(_, j) return "x", "t", R[j][2], 0 end
GetTradeSkillReagentItemLink = function(_, j) return "item:" .. R[j][1] end
C_Container = {
  GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
  GetContainerItemInfo = function(b, s) if b == 0 and s == 1 then return { stackCount = 20, hyperlink = "item:2589" } end end,
  PickupContainerItem = function() end,
}
local sellSlot
CursorHasItem = function() return false end
ClearCursor = function() end
ClickAuctionSellItemButton = function() sellSlot = 2589 end
GetAuctionSellItemInfo = function() if sellSlot then return "Linen Cloth", "tex", 20, 1, true, 13, 13, 1, 20, 2589 end end
local posted
StartAuction = function(...) posted = { ... } end
CalculateAuctionDeposit = function() return 60 end

local function fire(e, ...)
  for _, f in ipairs(registry[e] or {}) do local s = f._scripts.OnEvent; if s then s(f, e, ...) end end
  flush()
end

-- load addon in .toc order
local ns = {}
for line in io.lines("PhyzanCapital.toc") do
  line = line:gsub("\r", "")
  if line ~= "" and not line:match("^##") then
    local chunk = assert(loadfile((line:gsub("\\", "/"))))
    chunk("PhyzanCapital", ns)
  end
end
fire("ADDON_LOADED", "PhyzanCapital")
-- our confirmation dialog (UI:Confirm) -> lastPopup; data.fn / data.onCancel answer it like the Yes / No buttons
do
  local OLD = { mappin = "PHYZANCAPITAL_MAPPIN", mapinfo = "PHYZANCAPITAL_MAPINFO", shop = "PHYZANCAPITAL_SHOP",
    shopadd = "PHYZANCAPITAL_SHOP", trade = "PHYZANCAPITAL_CONFIRM", reset = "PHYZANCAPITAL_RESET" }
  ns.UI.OnConfirmShown = function(o, d)
    lastPopup = { which = OLD[o.which] or o.which, kind = o.kind, text = o.text, dialog = d, opts = o,
      data = { fn = function() ns.UI:ConfirmAnswer(true) end, onCancel = function() ns.UI:ConfirmAnswer(false) end } }
  end
end
assert(PhyzanCapitalDB and PhyzanCapitalDB.schemaVersion == 8)
fire("PLAYER_LOGIN")
do
  local rec = PhyzanCapitalDB.chars["Fredrick-Forever"]
  assert(rec and rec.level == 37, "level detected")
  assert(rec.professions.Tailoring.rank == 142 and rec.professions.Tailoring.max == 150, "tailoring detected")
  assert(rec.professions.Cooking.rank == 60 and rec.professions["First Aid"].rank == 120 and rec.professions.Herbalism.rank == 88)
  assert(rec.professions.Defense == nil, "non-professions ignored")
  assert(skillTree[2][3] == false and skillTree[3][3] == false and skillTree[1][3] == true, "collapsed headers restored")
  print("detected:", ns.Char:Summary())
end
playerLevel = 38; fire("PLAYER_LEVEL_UP", 38)
assert(ns.GetCharLevel() == 38, "level up")

-- scan 1 (09:00) and scan 2 (09:20): some auctions disappear
for i = 1, 30 do addAuction(2589, 20, 200, 300 + i, (i % 4) + 1, "Seller" .. (i % 5)) end
addAuction(2996, 5, 200, 400, 3, "Bob"); addAuction(2320, 10, 5, 10, 4, "Bob") -- thread under vendor price? 1c/u < 2c sell
addAuction(2604, 1, 30, 40, 4, "Ann"); addAuction(2572, 1, 3000, 6000, 3, "Ann"); addAuction(2321, 1, 50, 300, 4, "Ann")
fire("AUCTION_HOUSE_SHOW")
assert(ns.ahOpen and PhyzanCapitalFrame and PhyzanCapitalFrame:IsShown(), "window should auto-open")
assert(AuctionFrame._alpha == 0, "blizzard AH hidden")
ns.Scanner:OnClick("LeftButton"); fire("AUCTION_ITEM_LIST_UPDATE")
for _ = 1, 5 do local f = registry; local _ = f end
-- reader runs in OnUpdate: pump it
local function pumpReader()
  for _, fr in pairs(_G) do end
end
-- find reader frame: scanner sets OnUpdate on an unnamed frame; call it until idle
local guard = 0
while ns.Scanner.state ~= "idle" and guard < 100 do
  guard = guard + 1
  ns.Scanner:ReadChunk(); flush()
end
assert(#PhyzanCapitalDB.scans == 1 and PhyzanCapitalDB.scans[1].complete, "scan1")
-- remove: 3 very-long/long auctions (sales), 1 short (expiry)
local removed = 0
for i = #auctions, 1, -1 do
  local a = auctions[i]
  if a[1] == 2589 and removed < 4 and (a[5] == 4 or a[5] == 3 or (a[5] == 1 and removed == 3)) then table.remove(auctions, i); removed = removed + 1 end
end
addAuction(2589, 10, 100, 150, 4, "NewGuy")
clock = clock + 20 * 60
ns.Scanner:OnClick("LeftButton"); fire("AUCTION_ITEM_LIST_UPDATE")
guard = 0
while ns.Scanner.state ~= "idle" and guard < 100 do guard = guard + 1; ns.Scanner:ReadChunk(); flush() end
local ah = ns.AH(ns.CurrentAHKey())
local day = ns.MarketDay()
print("est sales linen:", ah.estSales[day][2589].sold, ah.estSales[day][2589].expired, "daily listings", ah.dailyStats[day][2589].listings)
assert(ah.dailyStats[day][2589].listings == 31)

-- vendor + tradeskill + profit
fire("MERCHANT_SHOW")
assert(PhyzanCapitalDB.vendorPrices[2320].unit == 10)
skillTree[2][4][1][2] = 145 -- skill-up seen by both the trade window and the skills pane
fire("TRADE_SKILL_SHOW")
assert(PhyzanCapitalDB.recipes["Tailoring:2572"].reagents == "2996:3;2320:2;2604:2")
assert(PhyzanCapitalDB.chars["Fredrick-Forever"].professions.Tailoring.rank == 145, "tradeskill window updates rank")
-- hidden overrides win, clear restores detection
SlashCmdList.PHYZANCAPITAL("setprof tailoring 80")
SlashCmdList.PHYZANCAPITAL("setlevel 20")
assert(ns.GetProfSkill("Tailoring") == 80 and ns.GetCharLevel() == 20 and ns.Char:HasOverrides())
SlashCmdList.PHYZANCAPITAL("clearoverride")
assert(ns.GetProfSkill("Tailoring") == 145 and ns.GetCharLevel() == 38 and not ns.Char:HasOverrides(), "override cleared")
-- GetProfessions API is preferred when present
GetProfessions = function() return 1, nil, nil, 2 end
GetProfessionInfo = function(i) if i == 1 then return "Schneiderei", "t", 150, 225, 0, 0, 197 end return "Fishing", "t", 50, 75, 0, 0, 356 end
ns.Char:Refresh("test")
assert(ns.GetProfSkill("Tailoring") == 150 and ns.GetProfSkill("Fishing") == 50 and ns.GetProfSkill("Cooking") == nil, "GetProfessions via skillLineID")
GetProfessions, GetProfessionInfo = nil, nil
ns.Char:Refresh("test")
assert(ns.GetProfSkill("Cooking") == 60)
local crafts = ns.Prof:GetProfitable(ns.CurrentAHKey())
print("profitable crafts:", #crafts, crafts[1] and crafts[1].name, crafts[1] and crafts[1].profit)
-- bundled vendor DB: vials are sold in packs of 5 for 20c -> 4c per unit; recorded prices override
assert(ns.VendorDB[3371][1] == 4, "vial per-unit price")
assert(ns.VendorDB[2321] and ns.Vendor:BuyPrice(2321) == 100)
local vs = ns.Vendor:Vendors(2321)
assert(#vs > 1 and vs[1].name and vs[1].zone, "vendor list")
print("fine thread best vendor:", vs[1].name, vs[1].zone, vs[1].faction, "of", #vs)
PhyzanCapitalDB.vendorPrices[2321] = { unit = 95, merchant = "Test Merchant", zone = "Goldshire" }
assert(ns.Vendor:BuyPrice(2321) == 95 and ns.Vendor:Vendors(2321)[1].recorded, "recorded overrides bundle")
-- 1.4.0: Vendor Swaps and Sell / Post are gone; the vendor data stays for the crafting list, lookup and professions
assert(ns.Vendor.GetSwaps == nil and ns.Vendor.GetReverse == nil and ns.Swaps == nil, "1.4.0: swaps code removed")
assert(ns.Handoff == nil and ns.Trade.AskPost == nil and ns.Trade.PutInSellSlot == nil and ns.Trade.BagItems == nil
  and ns.ModernAH.SendPost == nil and ns.ModernAH.PostMode == nil and ns.ModernAH.Handoff == nil, "1.4.0: sell code removed")

local pr = ns.UI.panels -- UI tabs
local tabKeys = {}
for _, t in ipairs(ns.UI.TAB_ORDER) do tabKeys[#tabKeys + 1] = t[1] .. "=" .. t[2]; ns.UI:Show(t[1]) end
assert(table.concat(tabKeys, ",") == "search=Search / Browse,buy=Buy,market=Market,shopping=Crafting List,crafts=Professions,settings=Settings",
  "1.4.0 tab list: " .. table.concat(tabKeys, ","))
for _, k in ipairs({ "sell", "swaps" }) do
  assert(ns.UI.builders[k] == nil and pr[k] == nil, "1.4.0: no " .. k .. " tab")
  for _, t in ipairs(ns.UI.TAB_ORDER) do assert(t[1] ~= k) end
end
print("header:", PhyzanCapitalFrame.charInfo:GetText(), "|", PhyzanCapitalFrame.lastScan:GetText())
print("status:", PhyzanCapitalFrame.scanPanel.text:GetText())
assert(PhyzanCapitalFrame.lastScan:GetText():find("Last scan", 1, true), "last scan header")
assert(PhyzanCapitalFrame.scanPanel.text:GetText():find("Scan complete", 1, true), "status complete")
assert(ns.UI.panels.market.sub:GetText() ~= nil)
print("settings:", (pr.settings.profList:GetText():gsub("\n", "; ")))
pr.settings.refresh._scripts.OnClick()
-- search + buyout via confirmation
ns.UI:Show("search")
ns.Trade.query = { name = "robe", quality = -1, usable = false }
ns.Trade:Search(0); fire("AUCTION_ITEM_LIST_UPDATE")
assert(#ns.Trade.results == 1, "search results")
ns.Trade.selected = ns.Trade.results[1]
ns.Trade:AskBuyout(ns.Trade.selected)
assert(lastPopup and lastPopup.text:find("Buy out"), "popup")
print("popup:", (lastPopup.text:gsub("\n", " | ")))
-- No: nothing is placed
lastPopup.dialog.no._scripts.OnClick(lastPopup.dialog.no)
assert(#bids == 0 and not lastPopup.dialog:IsShown(), "No places nothing")
-- Yes: PlaceAuctionBid runs synchronously inside the Yes button's OnClick (the hardware event), no timer involved
ns.Trade:AskBuyout(ns.Trade.selected)
local inClick = false
local realPlace = PlaceAuctionBid
PlaceAuctionBid = function(...) assert(inClick, "PlaceAuctionBid outside the click"); return realPlace(...) end
local yesBtn = lastPopup.dialog.yes
inClick = true; yesBtn._scripts.OnClick(yesBtn); inClick = false
PlaceAuctionBid = realPlace
assert(bids[1] and bids[1][2] == 6000, "buyout placed")
ns.UI:Show("buy")
-- failed scan (query error) and abort states
local sounds = 0
PlaySound = function() sounds = sounds + 1 end
local realQ = QueryAuctionItems
QueryAuctionItems = function() error("boom") end
ns.Scanner:OnClick("LeftButton")
assert(ns.Scanner.lastResult and ns.Scanner.lastResult.failed and sounds == 1, "failed scan state")
print("status after failure:", (ns.Scanner:StatusText()))
QueryAuctionItems = realQ

-- paged scan (full scan throttled): 2 pages, one click each
for i = 1, 40 do addAuction(2996, 1, 50, 60 + i, 2, "Pager") end
CanSendAuctionQuery = function() return true, false end
clock = clock + 10 * 60
local nScans = #PhyzanCapitalDB.scans
ns.Scanner:OnClick("LeftButton"); fire("AUCTION_ITEM_LIST_UPDATE")
assert(ns.Scanner.state == "paged", "paged state after page 1: " .. tostring(ns.Scanner.state))
ns.Scanner:OnClick("LeftButton"); fire("AUCTION_ITEM_LIST_UPDATE")
assert(ns.Scanner.state == "idle" and #PhyzanCapitalDB.scans == nScans + 1, "paged scan finished")
assert(PhyzanCapitalDB.scans[#PhyzanCapitalDB.scans].rows == #auctions, "paged rows")
assert(ns.Scanner.lastResult.ok and sounds == 2, "complete + sound")
print("status after paged:", (ns.Scanner:StatusText()))
CanSendAuctionQuery = function() return true, true end

-- slash commands / close
SlashCmdList.PHYZANCAPITAL("help")
SlashCmdList.PHYZANCAPITAL("status")
SlashCmdList.PHYZANCAPITAL("")
assert(not PhyzanCapitalFrame:IsShown() and AuctionFrame._alpha == 1, "toggle closes and restores blizzard AH")
fire("AUCTION_HOUSE_CLOSED")
SlashCmdList.PHYZANCAPITAL("crafts")
ns.UI:Show("search") -- closed message path

clock = clock + 3 * 3600
assert(ns.UI.StaleWarning(ns.CurrentAHKey()):find("old", 1, true), "stale warning")
assert(ns.UI.StaleWarning("Nowhere-Alliance"):find("No scan data", 1, true))
clock = clock - 3 * 3600

-- next market day boundary: 06:59 belongs to the previous day
local t0 = os.time({ year = 2026, month = 10, day = 18, hour = 6, min = 59 })
assert(ns.MarketDay(t0) == "2026-10-17" and ns.MarketDay(t0 + 60) == "2026-10-18", "market day boundary")
assert(ns.ParseMoney("1g20s5c") == 12005 and ns.ParseMoney(ns.MoneyInput(12005)) == 12005 and ns.ParseMoney("abc") == nil)

-- ===== modern C_AuctionHouse backend =====
do
  local sounds2 = 0
  PlaySound = function() sounds2 = sounds2 + 1 end
  -- no backend at all: click must fail loudly
  local saveQ, saveG = QueryAuctionItems, GetAuctionItemInfo
  QueryAuctionItems, GetAuctionItemInfo = nil, nil
  fire("AUCTION_HOUSE_SHOW")
  assert(ns.Backend() == "none")
  ns.Scanner:OnClick("LeftButton")
  assert(ns.Scanner.lastResult.failed and ns.Scanner.lastResult.reason:find("no usable", 1, true) and sounds2 == 1, "none backend fails loudly")
  QueryAuctionItems, GetAuctionItemInfo = saveQ, saveG
  -- legacy without CanSendAuctionQuery (the original silent no-op)
  local saveC = CanSendAuctionQuery; CanSendAuctionQuery = nil
  ns.Scanner:OnClick("LeftButton")
  assert(ns.Scanner.lastResult.failed and ns.Scanner.lastResult.reason:find("CanSendAuctionQuery", 1, true), "missing CanSendAuctionQuery reported")
  CanSendAuctionQuery = saveC
  fire("AUCTION_HOUSE_CLOSED")

  -- modern client mock
  Enum = { ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }, AuctionHouseSortOrder = { Price = 0, Name = 1 },
    AuctionHouseFilter = { UsableOnly = 1, PoorQuality = 2, CommonQuality = 3, UncommonQuality = 4, RareQuality = 5, EpicQuality = 6 } }
  ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { bag = b, slot = s } end }
  C_Item = { RequestLoadItemDataByID = function() end }
  AuctionHouseFrame = mock("AuctionHouseFrame")
  -- {itemID, count, minBid, buyout, timeLeftBand(0-3), owner}
  local MA = { { 2589, 20, 200, 260, 3, "Bob" }, { 2589, 10, 100, 140, 2, "Ann" }, { 2996, 5, 100, 250, 1, "Cid" },
    { 2604, 1, 10, 15, 0, "Fredrick" }, { 2572, 1, 3000, 5000, 3, "Ann" } }
  local calls = { replicate = 0, bids = {}, start = {}, confirm = {}, cancel = 0, postItem = nil, postComm = nil }
  local browseFull, lastBrowse = false, nil
  repHidden = false
  local function browseList(text)
    local by, order = {}, {}
    for _, a in ipairs(MA) do
      if text == "" or ITEMS[a[1]][1]:lower():find(text:lower(), 1, true) then
        local e = by[a[1]]
        if not e then e = { itemKey = { itemID = a[1], itemLevel = 0, itemSuffix = 0 }, totalQuantity = 0 }; by[a[1]] = e; order[#order + 1] = e end
        e.totalQuantity = e.totalQuantity + a[2]
        local u = math.floor(a[4] / a[2] + 0.5)
        if not e.minPrice or u < e.minPrice then e.minPrice = u end
      end
    end
    return order
  end
  local browseRes = {}
  C_AuctionHouse = {
    ReplicateItems = function() calls.replicate = calls.replicate + 1 end,
    GetNumReplicateItems = function() if repHidden then return 0 end return #MA end,
    GetReplicateItemInfo = function(i) local a = MA[i + 1]; if not a then return nil end
      return ITEMS[a[1]][1], "tex", a[2], 1, true, 1, 0, a[3], 5, a[4], 0, false, nil, a[6], a[6], 0, a[1], i ~= 1 end,
    GetReplicateItemTimeLeft = function(i) return MA[i + 1][5] end,
    GetReplicateItemLink = function(i) return "|Hitem:" .. MA[i + 1][1] .. ":0|h" end,
    SendBrowseQuery = function(q) lastBrowse = q
      local all = browseList(q.searchString)
      browseRes = {}
      local lim = (q.searchString == "") and 2 or #all
      for i = 1, math.min(lim, #all) do browseRes[i] = all[i] end
      browseFull = #browseRes == #all
    end,
    GetBrowseResults = function() return browseRes end,
    HasFullBrowseResults = function() return browseFull end,
    RequestMoreBrowseResults = function() browseRes = browseList(lastBrowse.searchString); browseFull = true end,
    GetItemKeyInfo = function(key) return { isCommodity = key.itemID ~= 2572 } end,
    SendSearchQuery = function() end,
    GetNumCommoditySearchResults = function(id) local n = 0; for _, a in ipairs(MA) do if a[1] == id then n = n + 1 end end; return n end,
    GetCommoditySearchResultInfo = function(id, i) local k = 0
      for idx, a in ipairs(MA) do if a[1] == id then k = k + 1; if k == i then
        return { itemID = id, quantity = a[2], unitPrice = math.floor(a[4] / a[2] + 0.5), auctionID = 100 + idx,
          owners = { a[6] }, timeLeftSeconds = 40000, numOwnerItems = a[6] == "Fredrick" and 1 or 0 } end end end end,
    GetNumItemSearchResults = function() return 1 end,
    GetItemSearchResultInfo = function(_, i) if i == 1 then return { auctionID = 105, quantity = 1, buyoutAmount = 5000,
      bidAmount = 0, minBid = 3000, timeLeft = 3, owners = { "Ann" } } end end,
    PlaceBid = function(id, amt) table.insert(calls.bids, { id, amt }) end,
    StartCommoditiesPurchase = function(id, q) calls.start = { id, q } end,
    ConfirmCommoditiesPurchase = function(id, q) calls.confirm = { id, q } end,
    CancelCommoditiesPurchase = function() calls.cancel = calls.cancel + 1 end,
    IsSellItemValid = function() return true end,
    GetItemCommodityStatus = function() return 2 end,
    PostItem = function(...) calls.postItem = { ... }; return false end,
    PostCommodity = function(...) calls.postComm = { ... }; return false end,
    CalculateCommodityDeposit = function() return 30 end,
    CalculateItemDeposit = function() return 45 end,
  }
  assert(ns.Backend() == "modern", "modern detected")
  ns.Scanner.button = nil
  fire("AUCTION_HOUSE_SHOW")
  assert(ns.Scanner.button and ns.Scanner.button._parent == AuctionHouseFrame, "scan button on AuctionHouseFrame")
  assert(AuctionHouseFrame._alpha == 0, "modern blizzard AH hidden")

  -- full scan via ReplicateItems
  local nScans = #PhyzanCapitalDB.scans
  ns.Scanner:OnClick("LeftButton")
  assert(calls.replicate == 1 and ns.Scanner.state == "waiting" and ns.Scanner.mode == "replicate")
  fire("REPLICATE_ITEM_LIST_UPDATE")
  local g = 0
  while ns.Scanner.state ~= "idle" and g < 50 do g = g + 1; ns.Scanner:ReadChunk(); flush() end
  local sc = PhyzanCapitalDB.scans[#PhyzanCapitalDB.scans]
  assert(#PhyzanCapitalDB.scans == nScans + 1 and sc.mode == "replicate" and sc.complete and sc.rows == #MA, "replicate scan")
  assert(ns.Scanner.lastResult.ok, "replicate ok")
  local snap = PhyzanCapitalDB.snapshots[sc.id]
  local first = type(snap) == "table" and snap[1] or nil
  print("replicate snapshot sample:", tostring(first))
  assert(ns.AH(ns.CurrentAHKey()).current[2589].minUnit == 13, "replicate current price")


  -- large money values (> int32) and a zero-count-then-data replicate sequence
  local BIG = 539399281134
  table.insert(MA, { 2321, 1, BIG, BIG, 3, "Rich" })
  table.insert(MA, { 2320, 20, 1e15, 2e15, 3, "Richer" }) -- absurd stack total beyond 1e14
  clock = clock + 16 * 60
  repHidden = true
  ns.Scanner:OnClick("LeftButton")
  fire("REPLICATE_ITEM_LIST_UPDATE") -- fires early, count still 0
  assert(ns.Scanner.state == "waiting", "keeps waiting on count 0")
  repHidden = false
  fire("REPLICATE_ITEM_LIST_UPDATE")
  g = 0
  while ns.Scanner.state == "waiting" and g < 10 do g = g + 1; fire("REPLICATE_ITEM_LIST_UPDATE") end
  assert(ns.Scanner.state == "reading", "reads once data arrived")
  g = 0
  while ns.Scanner.state ~= "idle" and g < 50 do g = g + 1; ns.Scanner:ReadChunk(); flush() end
  assert(ns.Scanner.lastResult.ok and ns.Scanner.lastResult.rows == #MA, "big-value scan complete")
  sc = PhyzanCapitalDB.scans[#PhyzanCapitalDB.scans]
  local foundBig = false
  for _, row in ipairs(PhyzanCapitalDB.snapshots[sc.id]) do if row:find("|539399281134|539399281134|539399281134|", 1, true) then foundBig = true end
    assert(not row:find("e+", 1, true), "no exponent notation in snapshot: " .. row) end
  assert(foundBig, "big buyout stored exactly")
  local cur = ns.AH(ns.CurrentAHKey()).current
  assert(cur[2321].minUnit == BIG and cur[2320].minUnit == 1e14, "big current price")
  assert(ns.Money(BIG) == "53939928g 11s 34c", ns.Money(BIG))
  ns.Ledger.lastMS = nil
  local ms = ns.Ledger:LoadMS(sc) -- decode round trip
  local bigKey = false
  for k in pairs(ms) do if k:find("539399281134", 1, true) then bigKey = true end end
  assert(bigKey, "multiset key keeps big value")
  for _, tab in ipairs({ "market", "swaps", "crafts", "settings", "search", "buy" }) do ns.UI:Show(tab) end
  ns.UI:UpdateStatus()
  assert(PhyzanCapitalDB.debug.lastScan.result == "complete" and PhyzanCapitalDB.debug.lastScan.rows == #MA, "debug.lastScan saved")
  -- abort while reading with big values (the AUCTION_HOUSE_CLOSED path from the bug report)
  clock = clock + 16 * 60
  ns.Scanner:OnClick("LeftButton"); fire("REPLICATE_ITEM_LIST_UPDATE")
  assert(ns.Scanner.state == "reading")
  ns.Scanner.rows[1] = ns.Scanner.readFn(6) -- the 539399281134c auction has been read
  fire("AUCTION_HOUSE_CLOSED")
  assert(ns.Scanner.lastResult and not ns.Scanner.lastResult.ok and ns.Scanner.lastResult.rows == 1, "partial scan saved on close")
  assert(ns.Scanner.state == "idle", "close during scan does not error or stick")
  fire("AUCTION_HOUSE_SHOW")
  -- count stays 0 for the whole wait: failed, never "complete"
  clock = clock + 16 * 60
  repHidden = true
  local nBefore = #PhyzanCapitalDB.scans
  ns.Scanner:OnClick("LeftButton"); fire("REPLICATE_ITEM_LIST_UPDATE")
  clock = clock + 61
  fire("REPLICATE_ITEM_LIST_UPDATE")
  assert(ns.Scanner.state == "idle" and ns.Scanner.lastResult.failed and ns.Scanner.lastResult.reason:find("0 auctions", 1, true), "zero count fails")
  assert(#PhyzanCapitalDB.scans == nBefore, "no empty scan stored")
  repHidden = false
  -- rows that can't be read at all: failed, not complete
  clock = clock + 16 * 60
  local realInfo = C_AuctionHouse.GetReplicateItemInfo
  C_AuctionHouse.GetReplicateItemInfo = function() return nil end
  ns.Scanner:OnClick("LeftButton"); fire("REPLICATE_ITEM_LIST_UPDATE")
  g = 0
  while ns.Scanner.state ~= "idle" and g < 50 do g = g + 1; if ns.Scanner.state == "reading" then ns.Scanner:ReadChunk() end; flush() end
  assert(ns.Scanner.lastResult.failed and ns.Scanner.lastResult.reason:find("0 auctions could be read", 1, true), "unreadable rows fail")
  C_AuctionHouse.GetReplicateItemInfo = realInfo
  -- an error while reading row 2: failed with row index, saved to debug.lastError, scanner not stuck
  clock = clock + 16 * 60
  ns.Scanner:OnClick("LeftButton"); fire("REPLICATE_ITEM_LIST_UPDATE")
  local rf = ns.Scanner.readFn
  ns.Scanner.readFn = function(i) if i == 2 then error("boom row") end return rf(i) end
  ns.Scanner:ReadChunk()
  assert(ns.Scanner.state == "idle" and ns.Scanner.lastResult.failed and ns.Scanner.lastResult.reason:find("row 2", 1, true), "reader error reported")
  assert(PhyzanCapitalDB.debug.lastError.index == 2 and PhyzanCapitalDB.debug.lastError.msg:find("boom row", 1, true), "lastError saved")
  -- an error while saving the scan: failed, not stuck in "reading"
  clock = clock + 16 * 60
  local realIngest = ns.Ledger.IngestScan
  ns.Ledger.IngestScan = function() error("integer overflow attempting to store 539399281134") end
  ns.Scanner:OnClick("LeftButton"); fire("REPLICATE_ITEM_LIST_UPDATE")
  g = 0
  while ns.Scanner.state ~= "idle" and g < 50 do g = g + 1; ns.Scanner:ReadChunk(); flush() end
  assert(ns.Scanner.lastResult.failed and ns.Scanner.lastResult.reason:find("saving the scan", 1, true), "ingest error reported")
  ns.Ledger.IngestScan = realIngest
  -- WoW-style format guard really catches %d overflow
  assert(not pcall(string.format, "%d", BIG), "format emulation active")
  -- second click within 15 min: browse scan fallback (aggregated), paged via "Scan more"
  clock = clock + 60
  local nRep = calls.replicate
  ns.Scanner:OnClick("LeftButton")
  assert(calls.replicate == nRep and ns.Scanner.mode == "browse" and lastBrowse.searchString == "", "browse fallback")
  fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  assert(ns.Scanner.state == "paged", "browse partial")
  print("status browse:", (ns.Scanner:StatusText()))
  ns.Scanner:OnClick("LeftButton")
  fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  assert(ns.Scanner.state == "idle" and ns.Scanner.lastResult.ok, "browse complete")
  sc = PhyzanCapitalDB.scans[#PhyzanCapitalDB.scans]
  assert(sc.aggregated and sc.mode == "browse" and sc.rows == 6, "aggregated browse scan")

  -- replicate times out (throttled) -> failure with reason
  clock = clock + 16 * 60
  local realR = C_AuctionHouse.ReplicateItems
  ns.Scanner:OnClick("LeftButton")
  assert(ns.Scanner.mode == "replicate")
  -- timers already flushed by fire(); simulate no event: run a fresh timeout by calling Abort path via timer
  if ns.Scanner.state == "waiting" then ns.Scanner:Abort("test timeout") end
  assert(ns.Scanner.lastResult.failed, "replicate timeout failed")
  C_AuctionHouse.ReplicateItems = function() error("throttled") end
  clock = clock + 16 * 60
  ns.Scanner:OnClick("LeftButton")
  assert(ns.Scanner.lastResult.failed and ns.Scanner.lastResult.reason:find("ReplicateItems failed", 1, true), "replicate error reported")
  C_AuctionHouse.ReplicateItems = realR

  -- search via browse, drill into a commodity, buy quantity with quote + confirm
  ns.Trade.query = { name = "linen", quality = -1, usable = true }
  ns.Trade:Search(0)
  assert(lastBrowse.searchString == "linen" and lastBrowse.filters[1] == Enum.AuctionHouseFilter.UsableOnly, "modern search")
  fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  assert(#ns.Trade.results == 3 and ns.Trade.results[1].browse, "browse results in search tab")
  ns.UI:Show("search")
  ns.Trade:AskBuyout(ns.Trade.results[1]) -- browse row: refused
  local cloth
  for _, r in ipairs(ns.Trade.results) do if r.itemID == 2589 then cloth = r end end
  ns.ModernAH:Drill(cloth)
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
  assert(#ns.ModernAH.drill.listings == 2 and ns.ModernAH.drill.commodity, "commodity listings")
  ns.UI:Show("buy")
  ns.ModernAH:AskCommodity(2589, 25)
  assert(calls.start[1] == 2589 and calls.start[2] == 25)
  lastPopup = nil
  fire("COMMODITY_PRICE_UPDATED", 13, 330)
  assert(lastPopup and lastPopup.text:find("25 x", 1, true), "commodity confirm")
  lastPopup.data.fn()
  assert(calls.confirm[1] == 2589 and calls.confirm[2] == 25, "commodity purchase confirmed")
  ns.ModernAH:AskCommodity(2589, 5); fire("COMMODITY_PRICE_UPDATED", 13, 65)
  lastPopup.data.onCancel()
  assert(calls.cancel == 1, "commodity cancel")

  -- drill into a non-commodity item, buy out via PlaceBid
  ns.ModernAH:Drill({ itemKey = { itemID = 2572, itemLevel = 0, itemSuffix = 0 }, itemID = 2572 })
  fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2572, itemLevel = 0, itemSuffix = 0 })
  local robe = ns.ModernAH.drill.listings[1]
  assert(robe and robe.auctionID == 105 and not ns.ModernAH.drill.commodity)
  ns.Trade.selected = robe; ns.UI:Show("buy")
  ns.Trade:AskBuyout(robe); lastPopup.data.fn()
  assert(calls.bids[1][1] == 105 and calls.bids[1][2] == 5000, "PlaceBid buyout")
  ns.Trade:AskBid(robe, 3000); lastPopup.data.fn()
  assert(calls.bids[2][2] == 3000, "PlaceBid bid")

  -- 1.4.0: clicking a Search result = the old behaviour (select / open its auctions on Buy) + "Add <item> to crafting list?"
  ns.Shop:List()[2589] = nil
  ns.Trade.query = { name = "linen", quality = -1, usable = false }
  ns.Trade:Search(0); fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
  ns.UI:Show("search")
  local srows = ns.UI.panels.search.list.data
  local ci
  for i, r in ipairs(srows) do if r.data.itemID == 2589 then ci = i end end
  lastPopup = nil
  ns.UI.panels.search.list.onSelect(ci, srows[ci])
  assert(ns.UI.tab == "buy" and ns.ModernAH.drill and ns.ModernAH.drill.itemID == 2589, "search click still opens the auctions on Buy")
  assert(lastPopup and lastPopup.which == "PHYZANCAPITAL_SHOP" and lastPopup.text:find("Linen Cloth", 1, true) and lastPopup.text:find("^Add .* to crafting list%?")
    and lastPopup.opts.edit.default == 1, "search click: crafting list popup: " .. tostring(lastPopup and lastPopup.text))
  lastPopup.dialog.edit:SetText("4"); lastPopup.data.fn()
  assert(ns.Shop:List()[2589] and ns.Shop:List()[2589].qty == 4, "search click: added x4")
  -- already on the list: one popup that says so and adds more
  lastPopup = nil
  ns.UI:Show("search")
  ns.UI.panels.search.list.onSelect(ci, ns.UI.panels.search.list.data[ci])
  assert(lastPopup and lastPopup.text:find("already on your crafting list", 1, true) and not lastPopup.text:find("to crafting list?", 1, true),
    "already there: " .. tostring(lastPopup and lastPopup.text))
  lastPopup.dialog.edit:SetText("2"); lastPopup.data.fn()
  assert(ns.Shop:List()[2589].qty == 6, "already there: quantity bumped to 6")
  -- the popup never blocks buying: a buy question replaces it, and it never replaces a buy question
  ns.UI.panels.search.list.onSelect(ci, ns.UI.panels.search.list.data[ci])
  ns.ModernAH:AskCommodity(2589, 3); fire("COMMODITY_PRICE_UPDATED", 13, 39)
  assert(lastPopup.which == "PHYZANCAPITAL_CONFIRM" and lastPopup.text:find("Buy 3 x", 1, true), "buy question replaces the crafting popup")
  local buyPopup = lastPopup
  ns.UI.panels.search.list.onSelect(ci, ns.UI.panels.search.list.data[ci])
  assert(lastPopup == buyPopup and ns.UI.confirmOpts and ns.UI.confirmOpts.which == "trade", "crafting popup never replaces a buy question")
  calls.confirm = nil
  buyPopup.data.fn()
  assert(calls.confirm and calls.confirm[2] == 3 and ns.Shop:List()[2589].qty == 6, "purchase still confirmed; list unchanged")
  ns.Shop:List()[2589] = nil
  -- removed commands say so
  local said, realPrint = {}, ns.Print
  ns.Print = function(m) said[#said + 1] = m; realPrint(m) end
  SlashCmdList.PHYZANCAPITAL("sell")
  SlashCmdList.PHYZANCAPITAL("postmode direct")
  SlashCmdList.PHYZANCAPITAL("swaps")
  ns.Print = realPrint
  assert(#said == 3 and said[1]:find("Sell / Post was removed in 1.4.0", 1, true) and said[2]:find("removed", 1, true)
    and said[3]:find("Vendor Swaps was removed", 1, true), "removed commands explained")

  -- debug command
  SlashCmdList.PHYZANCAPITAL("debug")
  local d = PhyzanCapitalDB.debug
  assert(d and d.backend == "modern" and d.ReplicateItems and d.SendBrowseQuery and d.QueryAuctionItems and d.ahOpen, "debug saved")
  SlashCmdList.PHYZANCAPITAL("backend legacy"); assert(ns.Backend() == "legacy")
  SlashCmdList.PHYZANCAPITAL("backend auto"); assert(ns.Backend() == "modern")
  fire("AUCTION_HOUSE_CLOSED")
  print("modern backend tests ok")
end

-- ===== item names, tooltips, vendor map pin =====
do
  local tipItem
  GameTooltip = mock("GameTooltip")
  GameTooltip.SetItemByID = function(_, id) tipItem = id end
  local requestedIDs = {}
  local liveNames = {}
  C_Item = {
    RequestLoadItemDataByID = function(id) requestedIDs[id] = true end,
    GetItemNameByID = function(id) return liveNames[id] end,
    GetItemQualityByID = function(id) return liveNames[id] and 3 or nil end,
    GetItemIconByID = function(id) return liveNames[id] and 12345 or nil end,
  }
  -- bundled name before the server answers, then the live name once GET_ITEM_INFO_RECEIVED arrives
  assert(PhyzanCapitalDB.items[4824] == nil)
  assert(ns.ItemName(4824) == "Blurred Axe" and requestedIDs[4824], "bundled name + load requested")
  assert(ns.ItemLabel(4824):find("|cff1eff00Blurred Axe|r", 1, true), "quality colour from bundled data")
  liveNames[4824] = "Blurred Axe"
  fire("GET_ITEM_INFO_RECEIVED", 4824, true)
  assert(PhyzanCapitalDB.items[4824].name == "Blurred Axe" and PhyzanCapitalDB.items[4824].quality == 3
    and PhyzanCapitalDB.items[4824].icon == 12345, "live info cached")
  assert(ns.ItemLabel(4824):find("|T12345:" .. math.floor(14 * ns.UI.scale + 0.5) .. ":" .. math.floor(14 * ns.UI.scale + 0.5) .. "|t", 1, true), "icon in label (scaled)")
  -- unknown custom item: never a bare number
  assert(ns.ItemName(279999) == "Item #279999 (loading\226\128\166)" and requestedIDs[279999], "unknown item placeholder")
  liveNames[279999] = "Mathystral Shard"
  fire("ITEM_DATA_LOAD_RESULT", 279999, true)
  assert(ns.ItemName(279999) == "Mathystral Shard", "ITEM_DATA_LOAD_RESULT caches name")
  -- replicate rows with quality -1 never overwrite a real quality
  ns.TouchItem(4824, nil, -1)
  assert(PhyzanCapitalDB.items[4824].quality == 3)

  -- names everywhere (Crafting List rows), item tooltip on hover
  fire("AUCTION_HOUSE_SHOW")
  PhyzanCapitalDB.items[2320] = nil -- Coarse Thread: not cached, not live -> bundled name
  ns.Shop:Add({ id = 2320, vendors = ns.Vendor:Vendors(2320), buy = 10, src = "bundled", ahUnit = 50 }, 2)
  ns.UI:Show("shopping")
  local sw = ns.UI.panels.shopping
  assert(#sw.list.data > 0, "crafting list rows")
  for _, b in ipairs(sw.list.buttons) do
    if b._shown then
      local t = b.cells[1]._text
      assert(not t:match("^%d+$") and not t:match("^item:"), "bare id shown: " .. t)
    end
  end
  local idx
  for i, row in ipairs(sw.list.data) do if row.itemID == 2320 then idx = i end end
  assert(idx and sw.list.data[idx][1] == "Coarse Thread", "bundled name in crafting list row")
  sw.list.offset = 0
  local btn = sw.list.buttons[idx]
  btn._scripts.OnEnter(btn)
  assert(tipItem == 2320, "item tooltip on hover")
  ns.Shop:Remove(2320, "test")

  -- map pin via C_Map user waypoint
  local wp, cleared, superTracked, openedMap = nil, 0, false, nil
  UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
  C_Map = { SetUserWaypoint = function(p) wp = p end, ClearUserWaypoint = function() cleared = cleared + 1; wp = nil end,
    GetUserWaypoint = function() return wp end, CanSetUserWaypointOnMap = function() return true end }
  C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) superTracked = v end }
  OpenWorldMap = function(m) openedMap = m end
  lastPopup = nil
  ns.MapPin:AskShow({ id = 2320, vendors = ns.Vendor:Vendors(2320) })
  assert(lastPopup and lastPopup.text:find("Tharynn Bouden", 1, true), "map question names the vendor")
  lastPopup.data.fn()
  assert(wp and wp.uiMapID == 1429 and math.abs(wp.position.x - 0.418) < 1e-9 and math.abs(wp.position.y - 0.672) < 1e-9, "waypoint Elwynn 41.8,67.2")
  assert(not superTracked and openedMap == 1429 and ns.MapPin.current.method == "waypoint", "waypoint + map opened, no protected supertrack call")
  assert(not PhyzanCapitalFrame:IsShown(), "our window hides so the map is visible")
  -- another vendor replaces the pin
  local ranked2, closest2 = ns.MapPin:RankVendors(ns.Vendor:Vendors(2321), nil)
  local firstV, loc2 = closest2.v, closest2.loc
  local recE
  for _, e in ipairs(ranked2) do if e.v.recorded then recE = e end end
  assert(recE and recE.tier == 5, "recorded merchant without position ranked after located friendly vendors")
  lastPopup = nil
  ns.MapPin:AskShow({ id = 2321, vendors = { recE.v } }) -- only that one: no coordinates, OK only
  assert(lastPopup.text:find("No map coordinates", 1, true) and lastPopup.kind == "ok")
  lastPopup.data.fn()
  assert(cleared == 0)
  ns.MapPin:AskShow({ id = 2321, vendors = ns.Vendor:Vendors(2321) })
  assert(lastPopup.text:find(firstV.name, 1, true), "closest vendor is asked first")
  lastPopup.data.fn()
  assert(cleared == 1 and wp.uiMapID == loc2.uiMapID and math.abs(wp.position.x - loc2.x / 100) < 1e-9, "previous pin replaced")
  print("second pin:", firstV.name, loc2.zone, loc2.uiMapID, loc2.x, loc2.y)
  -- someone else's waypoint is not cleared
  wp = { uiMapID = 1453, position = { x = 0.5, y = 0.5 } }
  ns.MapPin:Clear()
  assert(cleared == 1 and wp and ns.MapPin.current == nil, "foreign waypoint untouched")
  -- clearing our own pin
  ns.MapPin:Show(ns.MapPin:NPCLocation(66))
  ns.MapPin:Clear()
  assert(wp == nil and cleared == 2, "pin cleared")


  -- closest vendor from the player's position (same zone > same continent > other continent; hostile excluded)
  do
    local playerMap, px, py = 1429, 0.42, 0.65 -- Goldshire
    C_Map = { GetBestMapForUnit = function() return playerMap end,
      GetPlayerMapPosition = function() return { x = px, y = py, GetXY = function(self) return self.x, self.y end } end }
    ns.MapPin.spotTs = nil
    local spot = ns.MapPin:PlayerSpot(true)
    assert(spot and spot.uiMapID == 1429 and spot.x == 42 and spot.y == 65, "player spot")
    local r1, c1 = ns.MapPin:RankVendors(ns.Vendor:Vendors(2320), spot)
    assert(c1 and c1.tier == 1 and c1.loc.uiMapID == 1429 and c1.dist and c1.dist < 200, "same-zone vendor closest: " .. ns.MapPin:VendorText(c1))
    print("closest in Goldshire:", ns.MapPin:VendorText(c1))
    -- Stormwind: a Stormwind vendor of Fine Thread, distance in yards
    playerMap, px, py = 1453, 0.5, 0.6
    ns.MapPin.spotTs = nil
    local r2, c2 = ns.MapPin:RankVendors(ns.Vendor:Vendors(2321), ns.MapPin:PlayerSpot(true))
    assert(c2.loc.uiMapID == 1453 and ns.MapPin:VendorText(c2):find(" yd)", 1, true), "Stormwind vendor")
    print("closest in Stormwind:", ns.MapPin:VendorText(c2))
    -- Alliance player in Orgrimmar: Horde vendors excluded; closest Alliance/neutral vendor is on Kalimdor or flagged other continent
    playerMap, px, py = 1454, 0.5, 0.5
    ns.MapPin.spotTs = nil
    local r3, c3 = ns.MapPin:RankVendors(ns.Vendor:Vendors(2321), ns.MapPin:PlayerSpot(true))
    assert(c3 and c3.v.usable, "hostile never closest")
    for _, e in ipairs(r3) do if not e.v.usable then assert(e.tier > 10) end end
    print("closest from Orgrimmar (Alliance):", ns.MapPin:VendorText(c3))
    -- a vendor only on the other continent
    local ek = { { name = "EK Vendor", npc = 66, usable = true, zone = "Elwynn Forest" } }
    local _, c4 = ns.MapPin:RankVendors(ek, ns.MapPin:PlayerSpot())
    assert(c4.tier == 3 and ns.MapPin:VendorText(c4):find("other continent", 1, true), "other continent")
    -- throttle: position not re-read within 3 seconds unless forced
    playerMap = 1429
    assert(ns.MapPin:PlayerSpot().uiMapID == 1454, "throttled")
    clock = clock + 4
    assert(ns.MapPin:PlayerSpot().uiMapID == 1429, "re-read after throttle")
    -- the Crafting List shows the stored vendor with its distance; a zone change refreshes it (after the throttle delay)
    ns.Shop:Add({ id = 2320, vendors = ns.Vendor:Vendors(2320), buy = 10, src = "bundled", ahUnit = 50 }, 2)
    ns.UI:Show("shopping")
    local row
    for _, r in ipairs(sw.list.data) do if r.itemID == 2320 then row = r end end
    assert(row[3]:find("Elwynn Forest", 1, true) and row[3]:find(" yd)", 1, true), "closest text: " .. row[3])
    local before = row[3]
    playerMap, px, py = 1453, 0.5, 0.6
    fire("ZONE_CHANGED_NEW_AREA")
    for _, r in ipairs(sw.list.data) do if r.itemID == 2320 then row = r end end
    assert(row[3] ~= before, "zone change refreshes the distance: " .. row[3])
    ns.Shop:Remove(2320, "test")
    C_Map = nil
    ns.MapPin.spotTs = nil
  end

  -- 1.2.1: "Map" button / row click -> "See vendor on map?" Yes/No popup above our window
  do
    local playerMap, px, py = 1429, 0.42, 0.65
    local wp2
    C_Map = { GetBestMapForUnit = function() return playerMap end,
      GetPlayerMapPosition = function() return { x = px, y = py } end,
      SetUserWaypoint = function(pt) wp2 = pt end, ClearUserWaypoint = function() wp2 = nil end, GetUserWaypoint = function() return wp2 end }
    ns.MapPin.spotTs = nil
    ns.Shop:Add({ id = 2320, vendors = ns.Vendor:Vendors(2320), buy = 10, src = "bundled", ahUnit = 50 }, 2)
    ns.UI:Show("shopping")
    assert(PhyzanCapitalFrame._strata == "HIGH", "our frame is HIGH strata (below DIALOG)")
    local i2320
    for i, r in ipairs(sw.list.data) do if r.itemID == 2320 then i2320 = i end end
    sw.list.offset = 0
    local rb = sw.list.buttons[i2320]
    assert(rb.actions[1] and rb.actions[1]._text == "Map", "per-row Map button")
    lastPopup = nil
    rb.actions[1]._scripts.OnClick(rb.actions[1])
    assert(lastPopup and lastPopup.which == "PHYZANCAPITAL_MAPPIN" and lastPopup.text:find("See vendor on map?", 1, true)
      and lastPopup.text:find("Tharynn Bouden", 1, true) and lastPopup.text:find("Elwynn Forest", 1, true), "map popup text: " .. tostring(lastPopup and lastPopup.text))
    assert(lastPopup.dialog._strata == "FULLSCREEN_DIALOG", "popup raised above our window")
    assert(lastPopup.dialog.yes:IsShown() and lastPopup.dialog.no:IsShown() and lastPopup.dialog.yes._fs._text == "Yes", "Yes/No")
    lastPopup.data.onCancel() -- No
    assert(PhyzanCapitalFrame:IsShown() and wp2 == nil, "No keeps the window and sets no pin")
    rb.actions[1]._scripts.OnClick(rb.actions[1])
    lastPopup.data.fn()
    assert(wp2 and wp2.uiMapID == 1429 and math.abs(wp2.position.x - 0.418) < 1e-9, "Yes sets the waypoint")
    ns.Shop:Remove(2320, "test")
    -- vendor without coordinates: OK-only popup
    lastPopup = nil
    ns.MapPin:AskShow({ id = 2320, vendors = { { name = "Nowhere Bob", zone = "Somewhere", usable = true } } })
    assert(lastPopup.which == "PHYZANCAPITAL_MAPINFO" and lastPopup.text:find("No map coordinates", 1, true)
      and lastPopup.kind == "ok" and not lastPopup.dialog.no:IsShown() and lastPopup.dialog.yes._fs._text == "OK", "no-coords popup offers only OK")
    lastPopup.data.fn()

    -- seasonal vendors: Flik (14860, Darkmoon Faire) sells Heavy Leather Ball (18662)
    assert(ns.VendorSeasonal[14860] == "Darkmoon Faire", "Flik tagged")
    local fv = ns.Vendor:Vendors(18662)
    assert(fv[1].npc == 14860 and fv[1].seasonal == "Darkmoon Faire" and fv[1].usable, "Flik vendor entry (neutral)")
    local _, cf = ns.MapPin:RankVendors(fv, ns.MapPin:PlayerSpot())
    assert(cf and cf.v.npc == 14860 and ns.MapPin:VendorText(cf):find("Darkmoon Faire (only when the faire is in town)", 1, true), "seasonal note")
    -- a regular vendor wins over a nearer seasonal one
    local mixed = { fv[1], { npc = 777, name = "Amy Davenport", zone = "Redridge Mountains", usable = true } }
    local _, cm = ns.MapPin:RankVendors(mixed, ns.MapPin:PlayerSpot())
    assert(cm.v.npc == 777, "non-seasonal preferred as closest")
    -- the map question notes the faire; "Hide seasonal vendors" drops it from the closest-vendor choice
    lastPopup = nil
    ns.MapPin:AskShow({ id = 18662, vendors = fv })
    assert(lastPopup.text:find("only when the faire is in town", 1, true), "popup notes the faire")
    ns.db.settings.hideSeasonalVendors = true
    local _, hidden = ns.MapPin:RankVendors(fv, ns.MapPin:PlayerSpot())
    assert(hidden == nil or hidden.v.npc ~= 14860, "hidden with Hide seasonal vendors")
    ns.UI:Show("settings")
    assert(ns.UI.panels.settings.hideSeasonal:GetChecked(), "checkbox reflects setting")
    ns.db.settings.hideSeasonalVendors = false

    -- 1.2.3 seasonal fix: holiday fireworks vendors have no cmangos spawn at all -> tagged, never the closest
    for _, npc in ipairs({ 8116, 8117, 8118, 8121, 8122 }) do
      assert(ns.VendorSeasonal[npc] and ns.VendorSeasonal[npc]:find("Holiday Fireworks Vendor", 1, true), "fireworks vendor tagged " .. npc)
    end
    assert(not ns.VendorSeasonal[5569], "Fizzlebang Booms (permanent Ironforge spawn) is not seasonal")
    assert(ns.MapPin.SeasonalNote({ seasonal = ns.VendorSeasonal[8117] }) == ns.VendorSeasonal[8117], "note not doubled")
    local rv = ns.Vendor:Vendors(5740)
    local _, rc = ns.MapPin:RankVendors(rv, ns.MapPin:PlayerSpot())
    assert(rc and not rc.v.seasonal and rc.v.npc ~= 8117, "Red Fireworks Rocket: closest is a regular vendor")
    print("Red Fireworks Rocket closest:", ns.MapPin:VendorText(rc))

    -- (a) live merchant observation: NPC id from the GUID, observed position and inventory override the bundle
    local gNum, gInfo, gLink, gName = GetMerchantNumItems, GetMerchantItemInfo, GetMerchantItemLink, UnitName
    local savedVP = { [2320] = ns.db.vendorPrices[2320], [5740] = ns.db.vendorPrices[5740] }
    local merchant = { npc = 5569, name = "Fizzlebang Booms", items = { { 2320, "Coarse Thread", 10 } } }
    UnitGUID = function(u) if u == "npc" then return "Creature-0-4372-0-11-" .. merchant.npc .. "-00002A3B4C" end end
    UnitName = function(u) if u == "npc" then return merchant.name end return "Fredrick" end
    GetMerchantNumItems = function() return #merchant.items end
    GetMerchantItemInfo = function(i) local it = merchant.items[i]; return it[2], "t", it[3], 1, -1, true, true, false end
    GetMerchantItemLink = function(i) return "item:" .. merchant.items[i][1] end
    playerMap, px, py = 1455, 0.70, 0.50
    ns.MapPin.spotTs = nil
    assert(ns.NPCIDFromGUID("Creature-0-4372-0-11-5569-00002A3B4C") == 5569 and ns.NPCIDFromGUID("Player-1-0ABC") == nil, "guid parse")
    -- first visit: the merchant does not sell Red Fireworks Rocket, which the bundle lists for it -> flagged
    fire("MERCHANT_SHOW"); flush()
    local o = ns.db.observedVendors[5569]
    assert(o and o.bundledNotSold == 1 and o.items[2320] == 10 and not o.items[5740], "bundle claim not confirmed")
    local cv
    for _, v in ipairs(ns.Vendor:Vendors(5740)) do if v.npc == 5569 then cv = v end end
    assert(cv and cv.notSold and cv.observed, "not-sold flag")
    local _, cc = ns.MapPin:RankVendors(ns.Vendor:Vendors(5740), ns.MapPin:PlayerSpot())
    assert(cc and cc.v.npc ~= 5569, "not-sold vendor is never the closest, even right next to it")
    local found
    for _, v in ipairs(ns.Vendor:Vendors(2320)) do if v.npc == 5569 then found = v end end
    assert(found and found.observed, "observed inventory adds a seller the bundle does not know")
    -- second visit: now it sells the rockets
    merchant.items = { { 5740, "Red Fireworks Rocket", 100 } }
    fire("MERCHANT_SHOW"); flush()
    o = ns.db.observedVendors[5569]
    assert(o and o.name == "Fizzlebang Booms" and o.uiMapID == 1455 and math.abs(o.x - 70) < 1e-6 and o.items[5740] == 100 and o.complete
      and o.bundledNotSold == 0, "observed vendor")
    rv = ns.Vendor:Vendors(5740)
    local fz
    for _, v in ipairs(rv) do if v.npc == 5569 then fz = v end end
    assert(fz and fz.observed and fz.uiMapID == 1455 and math.abs(fz.x - 70) < 1e-6, "observed location overrides the bundle")
    _, rc = ns.MapPin:RankVendors(rv, ns.MapPin:PlayerSpot())
    assert(rc.v.npc == 5569, "in Ironforge next to it: the observed vendor is the closest")
    -- (c) a vendor seen in game is never marked missing
    assert(ns.Vendor:MarkMissing(fz, 5740) == false and not ns.Vendor:IsMissing(fz), "seen vendor not marked")
    lastPopup = nil
    ns.Vendor:AskMissing(fz, 5740)
    assert(lastPopup == nil, "no question for a seen vendor")

    -- (b) "Vendor not here" from the map popup: marks, re-picks, asks again for the next vendor
    playerMap, px, py = 1429, 0.42, 0.65
    ns.MapPin.spotTs = nil
    local s5740 = { id = 5740, vendors = ns.Vendor:Vendors(5740) }
    local _, first = ns.MapPin:RankVendors(s5740.vendors, ns.MapPin:PlayerSpot())
    assert(not first.v.observed, "closest from Elwynn is a bundled vendor")
    lastPopup = nil
    ns.MapPin:AskShow(s5740)
    local dlg = lastPopup.dialog
    assert(lastPopup.which == "PHYZANCAPITAL_MAPPIN" and dlg.alt:IsShown() and dlg.alt._fs._text == "Vendor not here", "alt button")
    dlg.alt._scripts.OnClick(dlg.alt)
    assert(lastPopup.which == "vendormissing" and lastPopup.text:find(first.v.name, 1, true), "asks before marking")
    lastPopup.data.fn()
    assert(ns.Vendor:IsMissing(first.v) and ns.db.vendorMissing[first.v.npc].itemID == 5740, "marked missing (persisted)")
    assert(lastPopup.which == "PHYZANCAPITAL_MAPPIN" and not lastPopup.text:find(first.v.name, 1, true), "re-picked: asks for the next vendor")
    assert(lastPopup.text:find("Fizzlebang Booms", 1, true) and not lastPopup.dialog.alt:IsShown(), "next one is the seen vendor: no 'not here' offered")
    lastPopup.data.onCancel()
    ns.db.observedVendors[5569] = nil; ns.Vendor.obsIndex = nil -- continue with bundled vendors only
    ns.db.vendorPrices[5740] = nil
    local _, second = ns.MapPin:RankVendors(ns.Vendor:Vendors(5740), ns.MapPin:PlayerSpot())
    assert(not second.v.observed, "bundled second vendor")
    assert(second.v.npc ~= first.v.npc, "missing vendor dropped from closest")
    -- Crafting List row "Not here": entry moves to the next vendor
    ns.Shop:Add({ id = 5740, vendors = ns.Vendor:Vendors(5740), buy = 100, src = "bundled", ahUnit = 500, margin = 300 }, 5)
    local se = ns.Shop:List()[5740]
    assert(se.vendorNpc == second.v.npc, "crafting list entry uses the current closest")
    ns.UI:Show("shopping")
    local sp2 = ns.UI.panels.shopping
    local nb
    for r, row in ipairs(sp2.list.data) do if row.itemID == 5740 then nb = sp2.list.buttons[r].actions[2] end end
    assert(nb and nb._text == "Not here", "shopping Not here button")
    nb._scripts.OnClick(nb)
    assert(lastPopup.which == "vendormissing", "shopping not-here asks")
    lastPopup.data.fn()
    se = ns.Shop:List()[5740]
    assert(ns.Vendor:IsMissing({ npc = second.v.npc }) and se.vendorNpc ~= second.v.npc and se.vendorNpc ~= first.v.npc, "shopping entry re-picked")
    ns.Shop:Remove(5740, "test")
    -- seeing a marked vendor at its merchant window clears the mark
    merchant.npc, merchant.name = first.v.npc, first.v.name
    fire("MERCHANT_SHOW"); flush()
    assert(not ns.Vendor:IsMissing(first.v) and ns.db.observedVendors[first.v.npc], "seen -> mark removed")
    assert(ns.Vendor:MarkMissing(first.v, 5740) == false, "and can no longer be marked")
    -- /capital vendors reset
    SlashCmdList.PHYZANCAPITAL("vendors")
    SlashCmdList.PHYZANCAPITAL("vendors reset")
    assert(next(ns.db.vendorMissing) == nil, "vendors reset")
    -- restore the merchant mocks; forget the test observations
    GetMerchantNumItems, GetMerchantItemInfo, GetMerchantItemLink, UnitName = gNum, gInfo, gLink, gName
    UnitGUID = nil
    ns.db.observedVendors[first.v.npc] = nil
    ns.db.vendorPrices[2320], ns.db.vendorPrices[5740] = savedVP[2320], savedVP[5740]
    ns.Vendor.obsIndex = nil
    ns.MapPin.spotTs = nil

    -- item name from Data/ItemNames.lua when the live client returns nil (or an empty string)
    C_Item = { GetItemNameByID = function() return nil end, GetItemQualityByID = function() return nil end,
      RequestLoadItemDataByID = function() end }
    local realGII = GetItemInfo
    GetItemInfo = function() return nil end
    PhyzanCapitalDB.items[18662] = { quality = 1 } -- cached quality but no name (as seen in real SavedVariables)
    assert(ns.ItemName(18662) == "Heavy Leather Ball", "bundled name with live nil")
    C_Item.GetItemNameByID = function() return "" end
    assert(ns.ItemName(18662) == "Heavy Leather Ball", "bundled name with live empty string")
    assert(ns.ItemLabel(18662):find("Heavy Leather Ball", 1, true) and not ns.ItemLabel(18662):find("18662", 1, true), "label")
    GetItemInfo = realGII
    C_Map = nil
    ns.MapPin.spotTs = nil
  end
  -- fallback: no C_Map waypoint API -> one texture on the world map canvas, only on that map
  C_Map = nil
  local canvas = mock("Canvas"); canvas.GetWidth = function() return 1000 end; canvas.GetHeight = function() return 660 end
  local shownMap = 1429
  WorldMapFrame = mock("WorldMapFrame")
  WorldMapFrame.GetCanvas = function() return canvas end
  WorldMapFrame.GetMapID = function() return shownMap end
  ns.MapPin:Show(ns.MapPin:NPCLocation(66))
  assert(ns.MapPin.current.method == "pin" and PhyzanCapitalMapPin._shown, "fallback pin shown on its map")
  shownMap = 1453; ns.MapPin:UpdateFallbackPin()
  assert(not PhyzanCapitalMapPin._shown, "pin hidden on other maps")
  ns.MapPin:Show(ns.MapPin:NPCLocation(777)); shownMap = 1433; ns.MapPin:UpdateFallbackPin()
  assert(PhyzanCapitalMapPin._shown and ns.MapPin.current.npc == 777, "single pin moved to new vendor")
  ns.MapPin:Clear()
  assert(not PhyzanCapitalMapPin._shown)
  -- bundled zone -> uiMapID facts
  local want = { ["Stormwind City"] = 1453, ["Ironforge"] = 1455, ["Orgrimmar"] = 1454, ["Elwynn Forest"] = 1429 }
  for i, z in ipairs(ns.VendorZones) do if want[z] then assert(ns.VendorZoneUiMap[i] == want[z], z); want[z] = nil end end
  assert(next(want) == nil, "all reference zones present")
  -- 1.3.0: bundled Stormwind positions are converted to WoW Forever's Stormwind map (recorded: Gunther Weller 64.1,68.7,
  -- Innkeeper Allison 60.4,75.2); Ironforge is unchanged (Poranna Snowbraid recorded 43.0,28.4)
  local gw, ia, ps = ns.MapPin:NPCLocation(1289), ns.MapPin:NPCLocation(6740), ns.MapPin:NPCLocation(5154)
  assert(math.abs(gw.x - 64.1) <= 0.3 and math.abs(gw.y - 68.7) <= 0.3, "Stormwind fix: Gunther Weller " .. gw.x .. "," .. gw.y)
  assert(math.abs(ia.x - 60.4) <= 0.3 and math.abs(ia.y - 75.2) <= 0.3, "Stormwind fix: Innkeeper Allison " .. ia.x .. "," .. ia.y)
  assert(ps.zone == "Ironforge" and math.abs(ps.x - 43.0) <= 0.3 and math.abs(ps.y - 28.4) <= 0.3, "Ironforge unchanged")
  fire("AUCTION_HOUSE_CLOSED")
  print("names + map pin tests ok")
end

-- 1.2.2 crafting list (renamed from "Shopping List" in 1.4.0)
do
  fire("AUCTION_HOUSE_SHOW")
  local UI = ns.UI
  -- adding asks Yes/No with a quantity box; No changes nothing
  lastPopup = nil
  ns.Shop:AskAddItem(2320, { ahUnit = 20 })
  assert(lastPopup and lastPopup.which == "PHYZANCAPITAL_SHOP" and lastPopup.text:find("^Add ")
    and lastPopup.text:find("Coarse Thread", 1, true) and lastPopup.text:find("to crafting list?", 1, true)
    and not lastPopup.text:lower():find("shopping", 1, true), "add popup: " .. tostring(lastPopup and lastPopup.text))
  assert(lastPopup.dialog.no:IsShown() and lastPopup.dialog.edit:IsShown() and lastPopup.dialog.edit:GetText() == tostring(lastPopup.opts.edit.default), "Yes/No + quantity box")
  lastPopup.data.onCancel()
  assert(lastPopup.dialog._strata == "FULLSCREEN_DIALOG", "raised")
  assert(ns.Shop:Count() == 0, "nothing added before Yes")
  lastPopup = nil
  ns.Shop:AskAddItem(2320, { ahUnit = 20 })
  lastPopup.data.fn() -- Yes
  local list = PhyzanCapitalDB.shopping["Fredrick-Forever"]
  local e = list[2320]
  assert(e and e.itemID == 2320 and e.name == "Coarse Thread" and e.qty >= 1 and e.bought == 0 and e.added == clock
    and e.vendorUnit and e.ahUnit and e.margin and e.vendorName and e.vendorZone and e.ahKey, "entry stored")
  print("crafting list entry:", e.qty, e.vendorName, e.vendorZone, e.uiMapID, e.x, e.y, e.vendorUnit, e.ahUnit, e.margin)
  -- shopping tab
  UI:Show("shopping")
  local sp = UI.panels.shopping
  assert(#sp.list.data == 1 and sp.list.data[1][2] == "0 / " .. e.qty and sp.list.data[1][3]:find(e.vendorName, 1, true), "row")
  assert(sp.total:GetText():find("Total vendor cost", 1, true) and sp.total:GetText():find("Estimated profit", 1, true), "totals")
  assert(#sp.list.cols == 9 and sp.list.buttons[1].actions[1]._text == "Map" and sp.list.buttons[1].actions[2]._text == "Not here" and sp.list.buttons[1].actions[3]._text == "Remove")
  -- quantity: select + set; min 1
  sp.list.buttons[1]._scripts.OnClick(sp.list.buttons[1], "LeftButton")
  sp.qty:SetText("0"); sp.setQty._scripts.OnClick(sp.setQty)
  assert(list[2320].qty == e.qty, "qty 0 rejected")
  sp.qty:SetText("8"); sp.setQty._scripts.OnClick(sp.setQty)
  assert(list[2320].qty == 8, "qty set")
  -- Map button: same Yes/No map popup for the stored vendor
  lastPopup = nil
  sp.list.buttons[1].actions[1]._scripts.OnClick(sp.list.buttons[1].actions[1])
  assert(lastPopup and (lastPopup.which == "PHYZANCAPITAL_MAPPIN" or lastPopup.which == "PHYZANCAPITAL_MAPINFO")
    and lastPopup.text:find(e.vendorName, 1, true), "map popup from crafting list")
  -- header buttons only while the AH is open
  assert(UI.frame.shopOpen:IsShown() and UI.frame.shopClear:IsShown(), "shop buttons shown at AH")
  local hb = { UI.frame.shopOpen._fs._text, UI.frame.shopClear._fs._text }
  assert((hb[1] == "Open Crafting List" and hb[2] == "Clear Crafting List") or (UI.scale > 1.5 and hb[1] == "Crafting List" and hb[2] == "Clear List"),
    "header buttons renamed: " .. hb[1] .. " / " .. hb[2])
  -- merchant: announce, count purchases made with BuyMerchantItem only
  local printed = {}
  local oldPrint = ns.Print
  ns.Print = function(m) printed[#printed + 1] = m; oldPrint(m) end
  bagCounts[2320] = 3
  fire("MERCHANT_SHOW")
  local said = false
  for _, m in ipairs(printed) do if m:find("Crafting list: this vendor sells Coarse Thread (need 8)", 1, true) then said = true end end
  assert(said, "merchant announcement")
  bagCounts[2320] = 4; fire("BAG_UPDATE", 0)       -- not a purchase (no BuyMerchantItem)
  assert(list[2320].bought == 0, "loot is not a purchase")
  BuyMerchantItem(1, 5); fire("BAG_UPDATE", 0)
  assert(list[2320].bought == 5, "bought 5")
  BuyMerchantItem(1, 5); fire("BAG_UPDATE", 0)
  assert(list[2320] == nil, "removed when complete")
  local log = PhyzanCapitalDB.shoppingLog[#PhyzanCapitalDB.shoppingLog]
  assert(log.itemID == 2320 and log.reason == "purchased" and log.bought == 10 and log.qty == 8, "history row")
  fire("MERCHANT_CLOSED")
  ns.Print = oldPrint
  -- manual remove and clear (with confirm)
  ns.Shop:Add({ id = 2320, buy = 10, ahUnit = 20, margin = 9, qty = 4, vendors = ns.Vendor:Vendors(2320) }, 4)
  ns.Shop:Add({ id = 2604, buy = 50, ahUnit = 80, margin = 26, qty = 2, vendors = ns.Vendor:Vendors(2604) }, 2)
  UI:Show("shopping")
  local rmBtn
  for r, row in ipairs(sp.list.data) do if row.itemID == 2604 then rmBtn = sp.list.buttons[r].actions[3] end end
  rmBtn._scripts.OnClick(rmBtn)
  assert(list[2604] == nil and list[2320], "manual remove")
  lastPopup = nil
  SlashCmdList.PHYZANCAPITAL("list clear")
  assert(lastPopup and lastPopup.which == "PHYZANCAPITAL_SHOP" and lastPopup.text:find("Clear the crafting list", 1, true) and list[2320], "clear asks")
  lastPopup.data.fn()
  assert(ns.Shop:Count() == 0, "cleared")
  SlashCmdList.PHYZANCAPITAL("list")
  assert(UI.tab == "shopping" and UI.frame:IsShown(), "/capital list")
  -- 1.4.0: /capital craftlist, with /capital shopping kept as a hidden alias
  for _, cmd in ipairs({ "craftlist", "shopping", "crafting" }) do
    UI:Show("market"); UI.frame:Hide()
    SlashCmdList.PHYZANCAPITAL(cmd)
    assert(UI.tab == "shopping" and UI.frame:IsShown(), "/capital " .. cmd .. " opens the Crafting List")
  end
  -- help names craftlist, not shopping
  local helpOut, rp = {}, ns.Print
  ns.Print = function(m) helpOut[#helpOut + 1] = m end
  SlashCmdList.PHYZANCAPITAL("help")
  ns.Print = rp
  local helpText = table.concat(helpOut, "\n")
  assert(helpText:find("craftlist", 1, true) and not helpText:lower():find("shopping", 1, true)
    and not helpText:find("postmode", 1, true) and not helpText:find("swaps", 1, true), "help updated")
  -- leave two entries for the layout audit and the SavedVariables export
  ns.Shop:Add({ id = 2320, buy = 10, ahUnit = 20, margin = 9, qty = 4, vendors = ns.Vendor:Vendors(2320) }, 40)
  ns.Shop:Add({ id = 2604, buy = 50, ahUnit = 80, margin = 26, qty = 2, vendors = ns.Vendor:Vendors(2604) }, 2)
  -- Blizzard frame buttons: only while Blizzard's window is visible
  PhyzanCapitalScanButton = PhyzanCapitalScanButton or mock("PhyzanCapitalScanButton")
  ns.db.settings.hideBlizzardAH = false
  ns.Shop:BlizzardButtons()
  assert(ns.Shop.bOpen:IsShown() and ns.Shop.bClear:IsShown(), "blizzard frame buttons when not hidden")
  ns.db.settings.hideBlizzardAH = true
  UI:ApplyBlizzardVisibility()
  assert(not ns.Shop.bOpen:IsShown(), "hidden with Blizzard's window")
  fire("AUCTION_HOUSE_CLOSED")
  assert(not UI.frame.shopOpen:IsShown(), "header buttons hidden when AH closed")
  fire("AUCTION_HOUSE_SHOW")
  print("crafting list tests ok")
end

local function plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- 1.4.1 Market category tree: classification (live / cache / bundled / unknown), tree structure, counts, filtering,
-- item clicks, persistence of the selection
do
  local CT, UI = ns.Categories, ns.UI
  -- Blizzard order and names (Camelot = WoW Forever)
  local root = CT:Root()
  local function names(path) local n = CT:Find(path); local t = {}; for _, s in ipairs(n.sub or {}) do t[#t + 1] = s.name end; return table.concat(t, ",") end
  assert(root.name == "All" and names("") == "Weapons,Armor,Containers,Consumables,Trade Goods,Ammo,Recipes,Quest Items,Miscellaneous", "top level: " .. names(""))
  assert(names("Weapons") == "One-Handed,Two-Handed,Ranged,Miscellaneous", names("Weapons"))
  assert(names("Weapons/One-Handed") == "One-Handed Axes,One-Handed Maces,One-Handed Swords,Daggers,Fist Weapons,Wands", names("Weapons/One-Handed"))
  assert(names("Weapons/Two-Handed") == "Two-Handed Axes,Two-Handed Maces,Two-Handed Swords,Polearms,Staves", names("Weapons/Two-Handed"))
  assert(names("Weapons/Ranged") == "Bows,Crossbows,Guns,Thrown", names("Weapons/Ranged"))
  assert(names("Weapons/Miscellaneous") == "Fishing Pole,Other", names("Weapons/Miscellaneous"))
  assert(names("Armor") == "Plate,Mail,Leather,Cloth,Relic,Miscellaneous", names("Armor"))
  for _, a in ipairs({ "Plate", "Mail", "Leather", "Cloth" }) do
    assert(names("Armor/" .. a) == "Head,Shoulder,Chest,Waist,Legs,Feet,Wrist,Hands,Relic", a .. ": " .. names("Armor/" .. a))
  end
  assert(names("Armor/Relic") == "Idols,Librams,Totems", names("Armor/Relic"))
  assert(names("Armor/Miscellaneous") == "Neck,Cloak,Finger,Trinket,Held In Off-hand,Shields,Shirt", names("Armor/Miscellaneous"))
  assert(names("Containers") == "Regular Bags,Ammo,Trade Bags", names("Containers"))
  assert(names("Consumables") == "Explosives,Potions,Elixirs,Flasks,Scrolls,Food & Drink,Bandages,Item Enhancements,Draughts,Devices,Other", names("Consumables"))
  assert(names("Consumables/Item Enhancements") == "Permanent,Temporary", names("Consumables/Item Enhancements"))
  assert(names("Trade Goods") == "Parts,Cloth,Leather,Metal & Stone,Cooking,Herb,Enchanting,Elemental,Other", names("Trade Goods"))
  assert(names("Ammo") == "Arrow,Bullet", names("Ammo"))
  assert(names("Recipes") == "Leatherworking,Tailoring,Engineering,Blacksmithing,Cooking,Alchemy,First Aid,Enchanting,Book", names("Recipes"))
  assert(names("Miscellaneous") == "Junk,Reagent,Pet,Holiday,Other,Mount", names("Miscellaneous"))
  -- bundled class map (Forever Item DB2): every bundled item name has a class
  assert(select(1, CT.BundledClass(2589)) == 7 and select(2, CT.BundledClass(2589)) == 5, "bundled: Linen Cloth = Trade Goods / Cloth")
  local a, b, c = CT.BundledClass(2572); assert(a == 4 and b == 1 and c == 20, "bundled: Red Linen Robe = cloth robe")
  local missing = 0
  for id in pairs(ns.ItemNames or {}) do if not CT.BundledClass(id) then missing = missing + 1 end end
  assert(missing <= 1, "bundled class map covers the bundled names (" .. missing .. " missing)")

  -- live classification via C_Item.GetItemInfoInstant (+ equipLoc), cached in db.items
  local LIVE = {
    [2589] = { 7, 5, "" }, [2996] = { 7, 5, "" }, [2572] = { 4, 1, "INVTYPE_ROBE" }, [4824] = { 2, 0, "INVTYPE_WEAPONMAINHAND" },
    [2901] = { 2, 14, "INVTYPE_WEAPONMAINHAND" }, [5740] = { 0, 8, "" }, [990002] = { 4, 1, "INVTYPE_CLOAK" }, [990003] = { 13, 0, "" },
  }
  local savedCI, savedGII = C_Item, GetItemInfoInstant
  C_Item = setmetatable({ GetItemInfoInstant = function(id)
    local l = LIVE[id]; if not l then return nil end
    return id, "Type", "SubType", l[3], 1000 + id, l[1], l[2]
  end }, { __index = savedCI })
  GetItemInfoInstant = nil
  for _, id in ipairs({ 2589, 2996, 2572, 4824, 2901, 2512, 5740, 990001, 990002, 990003 }) do ns.db.items[id] = ns.db.items[id] or {}; local it = ns.db.items[id]; it.classID, it.subClassID, it.invType, it.equipLoc = nil, nil, nil, nil end
  local c1, s1, i1, src = CT:Classify(2572)
  assert(c1 == 4 and s1 == 1 and i1 == 20 and src == "live", "live classification with the robe slot")
  assert(ns.db.items[2572].classID == 4 and ns.db.items[2572].invType == 20 and ns.db.items[2572].equipLoc == "INVTYPE_ROBE", "cached in SavedVariables")
  assert(select(4, CT:Classify(2572)) == "cache", "second call from the cache")
  assert(select(4, CT:Classify(2512)) == "bundled" and ns.db.items[2512].classID == nil, "no live data: bundled map, not stored")
  local reqd = {}
  local realReq = ns.Items.Request
  ns.Items.Request = function(_, id) reqd[id] = true end
  assert(CT:Classify(990001) == nil and reqd[990001], "unknown item: requested")
  ns.Items.Request = realReq

  -- the Market tab with these items (latest scan)
  local key = ns.Ledger:LatestAHKey()
  local ah = ns.AH(key)
  local savedCur = ah.current
  ah.current = {}
  for _, id in ipairs({ 2589, 2996, 2572, 4824, 2901, 2512, 5740, 990001, 990002, 990003 }) do ah.current[id] = { n = 1, qty = id % 7 + 1, minUnit = id } end
  local st = ns.db.settings
  st.marketCategory, st.marketOpen = "", false
  UI:Show("market")
  local p = UI.panels.market
  local function treeRow(path) for i, r in ipairs(p.tree.data) do if r.path == path then return i, r end end end
  local function count(path) local _, r = treeRow(path); return r and tonumber(r[2]) end
  assert(p.tree.data[1].path == "" and count("") == 10 and #p.list.data == 10, "All at the top with every item")
  assert(count("Trade Goods") == 2 and count("Armor") == 2 and count("Weapons") == 2 and count("Ammo") == 1 and count("Consumables") == 1, "top level counts")
  assert(count("Recipes") == 0 and count("~") == 1 and count("?") == 1, "empty category shows 0; key = outside every category; one unclassified")
  assert(not treeRow("Armor/Cloth"), "collapsed: no subcategories shown")
  local function click(path) local i, r = treeRow(path); assert(i, "tree row " .. path); p.tree.onSelect(i, r) end
  click("Armor")
  assert(st.marketCategory == "Armor" and st.marketOpen and treeRow("Armor/Cloth") and not treeRow("Armor/Cloth/Chest"), "Armor opens one level")
  assert(#p.list.data == 2 and p.sub:GetText():find("Armor: 2 of 10 items", 1, true), "Armor filters the list: " .. p.sub:GetText())
  click("Armor/Cloth")
  assert(count("Armor/Cloth") == 2 and treeRow("Armor/Cloth/Chest") and count("Armor/Cloth/Chest") == 1 and count("Armor/Cloth/Head") == 0, "cloth: robe in Chest, cloak only in Cloth")
  click("Armor/Cloth/Chest")
  assert(#p.list.data == 1 and p.list.data[1].itemID == 2572, "robe under Cloth > Chest")
  click("Armor/Miscellaneous")
  assert(count("Armor/Miscellaneous/Cloak") == 1, "cloak also in Miscellaneous > Cloak (as in the client)")
  click("Armor/Miscellaneous/Cloak")
  assert(#p.list.data == 1 and p.list.data[1].itemID == 990002, "cloak filter")
  click("Weapons"); click("Weapons/Miscellaneous"); click("Weapons/Miscellaneous/Other")
  assert(#p.list.data == 1 and p.list.data[1].itemID == 2901, "generic weapon in Weapons > Miscellaneous > Other")
  click("Weapons"); click("Weapons/One-Handed"); click("Weapons/One-Handed/One-Handed Axes")
  assert(#p.list.data == 1 and p.list.data[1].itemID == 4824, "one-handed axe")
  click("Ammo"); click("Ammo/Arrow")
  assert(#p.list.data == 1 and p.list.data[1].itemID == 2512, "bundled arrow")
  click("~"); assert(#p.list.data == 1 and p.list.data[1].itemID == 990003, "outside every category")
  click("Trade Goods")
  assert(#p.list.data == 2 and st.marketOpen, "Trade Goods: cloth + bolt")
  click("Trade Goods")
  assert(not st.marketOpen and not treeRow("Trade Goods/Cloth") and #p.list.data == 2, "second click closes the branch, filter stays")
  -- sorting and columns kept: same 8 columns, sorted by quantity (descending) by default, header click re-sorts
  assert(#p.list.cols == 8 and p.list.sortCol == 3 and p.list.sortDesc, "market columns and default sort")
  assert(tonumber(p.list.data[1][3]) >= tonumber(p.list.data[2][3]), "sorted by quantity")
  -- item click: the crafting list popup (also when it is already listed), in every category
  click("Trade Goods"); click("Trade Goods/Cloth")
  local before = ns.Shop:List()[2996] and ns.Shop:List()[2996].qty or 0
  if before > 0 then ns.Shop:Remove(2996) end
  local ri
  for i, r in ipairs(p.list.data) do if r.itemID == 2996 then ri = i end end
  lastPopup = nil
  p.list.onSelect(ri, p.list.data[ri])
  assert(lastPopup and lastPopup.which == "PHYZANCAPITAL_SHOP" and plain(lastPopup.text):find("^Add Bolt of Linen Cloth to crafting list%?") and lastPopup.opts.edit,
    "market click: crafting list popup with quantity: " .. tostring(lastPopup and lastPopup.text))
  lastPopup.dialog.edit:SetText("3"); lastPopup.data.fn()
  assert(ns.Shop:List()[2996] and ns.Shop:List()[2996].qty == 3, "market click: added x3")
  lastPopup = nil
  p.list.onSelect(ri, p.list.data[ri])
  assert(lastPopup and plain(lastPopup.text):find("Bolt of Linen Cloth is already on your crafting list", 1, true), "market click: already listed")
  lastPopup.dialog.edit:SetText("2"); lastPopup.data.fn()
  assert(ns.Shop:List()[2996].qty == 5, "market click: added 2 more")
  ns.Shop:Remove(2996)
  for _, path in ipairs({ "", "Armor/Cloth/Chest", "Weapons/Miscellaneous/Other", "~", "?" }) do -- every kind of category
    if path ~= "" and path ~= "~" and path ~= "?" then st.marketCategory = path; st.marketOpen = true; UI:Refresh() else click(path) end
    lastPopup = nil
    p.list.onSelect(1, p.list.data[1])
    assert(lastPopup and lastPopup.which == "PHYZANCAPITAL_SHOP", "popup in " .. path)
    lastPopup.data.onCancel()
  end
  -- unknown item arrives: GET_ITEM_INFO_RECEIVED classifies it and the tree slots it in
  LIVE[990001] = { 15, 2, "" }
  click("?")
  fire("GET_ITEM_INFO_RECEIVED", 990001, true); flush()
  assert(ns.db.items[990001].classID == 15 and count("?") == nil and count("Miscellaneous") == 1, "slotted in after GET_ITEM_INFO_RECEIVED")
  assert(st.marketCategory == "", "vanished pseudo-category falls back to All")
  click("Miscellaneous"); assert(count("Miscellaneous/Pet") == 1, "pet")
  -- a removed category in the settings resets to All
  st.marketCategory = "No/Such/Category"; UI:Refresh()
  assert(st.marketCategory == "" and #p.list.data == 10, "unknown saved category -> All")
  st.marketCategory, st.marketOpen = "Trade Goods/Cloth", true
  UI:Refresh()
  assert(#p.list.data == 2, "selection from the settings")
  -- persistence: db.items class fields and the selection are plain data in SavedVariables
  assert(type(PhyzanCapitalDB.items[2589].classID) == "number" and PhyzanCapitalDB.settings.marketCategory == "Trade Goods/Cloth", "saved")
  ah.current = savedCur
  C_Item, GetItemInfoInstant = savedCI, savedGII
  st.marketCategory, st.marketOpen = "", false
  print("market tree ok")
end

-- 1.4.1 command list popup: once per AH visit on Search, "Don't show again", Settings, /capital help, focus, buying
do
  local UI, st = ns.UI, ns.db.settings
  fire("AUCTION_HOUSE_CLOSED")
  st.showCommands, st.autoOpen = true, true
  UI:Show("search")
  local sp = UI.panels.search
  local focus = 0
  sp.name.SetFocus = function() focus = focus + 1 end
  UI.frame:Hide()
  lastPopup = nil
  fire("AUCTION_HOUSE_SHOW")
  assert(UI.tab == "search" and lastPopup and lastPopup.which == "commands" and lastPopup.kind == "ok", "shown on AH open")
  local d = lastPopup.dialog
  local text = plain(lastPopup.text)
  for _, c in ipairs(ns.HELP_COMMANDS) do
    assert((text:find(c[1], 1, true) and text:find(c[2], 1, true)) or (c.chatOnly and not text:find(c[1], 1, true)), "lists " .. c[1])
  end
  assert(text:find("/capital feedback", 1, true), "feedback command listed")
  assert(text:find("/capital craftlist", 1, true) and text:find("/capital price <item>", 1, true) and not text:find("postmode", 1, true)
    and not text:find("swaps", 1, true) and not text:find("/capital shopping", 1, true), "only existing commands")
  assert(d.check:IsShown() and not d.check:GetChecked() and d.check.label:GetText():find("Don't show", 1, true), "don't-show check box")
  assert(d.msg:GetText():find("/capital craftlist", 1, true) and lastPopup.opts.justify == "LEFT", "message in the dialog, left aligned")
  -- every listed command really exists (the handler knows it)
  local unknown = {}
  local realPrint = ns.Print
  ns.Print = function(msg, ...) if tostring(msg):lower():find("unknown command", 1, true) then unknown[#unknown + 1] = tostring(msg) end end
  local saveShown = lastPopup
  for _, c in ipairs(ns.HELP_COMMANDS) do
    local arg = c[1]:gsub("^/capital%s*", ""):gsub("<item>", "linen"):gsub("%s*<.->", ""):gsub("%s*%[.-%]", "")
    if arg ~= "" and arg ~= "reset" and arg ~= "help" then
      UI.confirmOpts = nil
      local ok, err = pcall(SlashCmdList.PHYZANCAPITAL, arg)
      if not ok then unknown[#unknown + 1] = arg .. ": " .. tostring(err) end
    end
  end
  ns.Print = realPrint
  assert(#unknown == 0, "listed command unknown: " .. table.concat(unknown, "; "))
  -- back to the popup state
  if UI.confirmOpts then UI:ConfirmAnswer(false) end
  fire("AUCTION_HOUSE_CLOSED"); st.showCommands, st.autoOpen = true, true
  UI.frame:Hide(); lastPopup = nil; fire("AUCTION_HOUSE_SHOW")
  assert(lastPopup and lastPopup ~= saveShown and lastPopup.which == "commands", "shown again after a new visit")
  d = lastPopup.dialog
  -- OK closes it and hands the keyboard back to the search box
  focus = 0
  d.yes._scripts.OnClick(d.yes)
  assert(not d:IsShown() and not UI.confirmOpts and focus == 1, "OK: closed, focus back on the search box")
  -- same visit: not again (also when the AH frame is re-shown)
  lastPopup = nil; fire("AUCTION_HOUSE_SHOW")
  assert(lastPopup == nil, "once per visit")
  -- Escape closes it too, focus back
  fire("AUCTION_HOUSE_CLOSED"); UI.frame:Hide(); lastPopup = nil; fire("AUCTION_HOUSE_SHOW")
  d = lastPopup.dialog; focus = 0
  d._scripts.OnKeyDown(d, "ESCAPE")
  assert(not d:IsShown() and focus == 1, "Escape: closed, focus back")
  -- "Don't show again"
  fire("AUCTION_HOUSE_CLOSED"); UI.frame:Hide(); lastPopup = nil; fire("AUCTION_HOUSE_SHOW")
  d = lastPopup.dialog
  d.check:SetChecked(true); d.check._scripts.OnClick(d.check)
  assert(st.showCommands == false, "check box turns it off")
  d.yes._scripts.OnClick(d.yes)
  fire("AUCTION_HOUSE_CLOSED"); UI.frame:Hide(); lastPopup = nil; fire("AUCTION_HOUSE_SHOW")
  assert(lastPopup == nil and UI.tab == "search", "not shown when turned off")
  -- /capital help shows it anytime (box reflects the setting)
  SlashCmdList.PHYZANCAPITAL("help")
  assert(lastPopup and lastPopup.which == "commands" and lastPopup.dialog.check:GetChecked(), "/capital help shows the popup")
  lastPopup.dialog.yes._scripts.OnClick(lastPopup.dialog.yes)
  -- Settings: check box + button
  UI:Show("settings")
  local sp2 = UI.panels.settings
  assert(not sp2.showCmds:GetChecked(), "settings shows it off")
  sp2.showCmds:SetChecked(true); sp2.showCmds._scripts.OnClick(sp2.showCmds)
  assert(st.showCommands == true, "re-enabled in Settings")
  lastPopup = nil; sp2.cmdsBtn._scripts.OnClick(sp2.cmdsBtn)
  assert(lastPopup and lastPopup.which == "commands", "Settings button shows it")
  UI:ConfirmAnswer(false)
  -- closing the AH closes it; it never blocks buying: a buy question replaces it and keeps the keyboard
  fire("AUCTION_HOUSE_CLOSED"); UI.frame:Hide(); lastPopup = nil; fire("AUCTION_HOUSE_SHOW")
  assert(lastPopup.which == "commands")
  fire("AUCTION_HOUSE_CLOSED")
  assert(not lastPopup.dialog:IsShown() and not UI.confirmOpts, "AH closed: popup closed")
  UI.frame:Hide(); lastPopup = nil; fire("AUCTION_HOUSE_SHOW")
  assert(lastPopup.which == "commands")
  focus = 0
  ns.ModernAH:AskCommodity(2589, 3); fire("COMMODITY_PRICE_UPDATED", 13, 39)
  assert(lastPopup.which == "PHYZANCAPITAL_CONFIRM" and lastPopup.text:find("Buy 3 x", 1, true) and focus == 0, "buy question replaces it, no focus steal")
  lastPopup.data.onCancel()
  -- not on other tabs: auto-open off or another trade tab remembered
  fire("AUCTION_HOUSE_CLOSED"); st.autoOpen = false; UI.frame:Hide(); lastPopup = nil; fire("AUCTION_HOUSE_SHOW")
  assert(lastPopup == nil, "no popup without auto-open")
  st.autoOpen = true
  sp.name.SetFocus = nil
  print("command popup ok")
end

-- 1.4.2 Feedback: button in the top bar (visible on Search / Browse), dialog with the address to copy, /capital feedback
do
  local UI = ns.UI
  fire("AUCTION_HOUSE_CLOSED"); ns.db.settings.showCommands = false
  UI.frame:Hide(); fire("AUCTION_HOUSE_SHOW")
  assert(UI.tab == "search" and UI.frame:IsShown(), "search landing page")
  local fb = UI.frame.feedback
  assert(fb and fb:IsShown() and fb:GetText() == "Feedback", "Feedback button visible on Search / Browse")
  local savedGBI = GetBuildInfo
  GetBuildInfo = function() return "1.60.1", "70450", "Oct 1 2026", 16001 end
  lastPopup = nil
  fb._scripts.OnClick(fb)
  assert(lastPopup and lastPopup.which == "feedback" and lastPopup.kind == "ok", "feedback dialog")
  local d = lastPopup.dialog
  assert(d.msg:GetText() == "Send suggestions and bug reports to:" and d.title:GetText() == "Phyzan Capital feedback", "feedback text")
  assert(d.yes:GetText() == "Close" and not d.no:IsShown(), "one Close button")
  assert(d.edit:IsShown() and d.edit:GetText() == "kingofthefallllc@gmail.com" and ns.FEEDBACK_EMAIL == "kingofthefallllc@gmail.com", "address in the box")
  local foot = d.foot:GetText()
  assert(d.foot:IsShown() and foot:find("Press Ctrl+C to copy", 1, true) and foot:find("Phyzan Capital " .. ns.VERSION, 1, true)
    and foot:find("1.60.1 (build 70450), interface 16001", 1, true), "hint and report line: " .. foot)
  assert(ns.VERSION == "1.4.2", "version")
  -- read-only and pre-selected: typing puts the address back (selected again)
  local hl = 0
  d.edit.HighlightText = function() hl = hl + 1 end
  d.edit:SetText("x"); d.edit._scripts.OnTextChanged(d.edit, true)
  assert(d.edit:GetText() == ns.FEEDBACK_EMAIL and hl == 1, "read-only box")
  d.edit._scripts.OnEditFocusGained(d.edit)
  assert(hl == 2, "selected again on focus")
  d.edit:SetText("5"); d.edit._scripts.OnTextChanged(d.edit, false) -- our own SetText is left alone
  d.edit:SetText(ns.FEEDBACK_EMAIL)
  d.edit._scripts.OnEnterPressed(d.edit)
  assert(not d:IsShown() and not UI.confirmOpts, "Enter closes it")
  d.edit.HighlightText = nil
  -- a normal quantity box is not read-only
  ns.Shop:AskAddItem(2589)
  lastPopup.dialog.edit:SetText("7"); lastPopup.dialog.edit._scripts.OnTextChanged(lastPopup.dialog.edit, true)
  assert(lastPopup.dialog.edit:GetText() == "7" and not lastPopup.dialog.foot:IsShown(), "quantity box still editable, no footer")
  lastPopup.data.onCancel()
  -- /capital feedback: same dialog plus a chat line; also away from the AH
  fire("AUCTION_HOUSE_CLOSED")
  local printed = {}
  local realPrint = ns.Print
  ns.Print = function(m) printed[#printed + 1] = tostring(m) end
  lastPopup = nil
  SlashCmdList.PHYZANCAPITAL("feedback")
  ns.Print = realPrint
  assert(lastPopup and lastPopup.which == "feedback" and printed[1]:find(ns.FEEDBACK_EMAIL, 1, true), "/capital feedback")
  lastPopup.dialog.yes._scripts.OnClick(lastPopup.dialog.yes)
  assert(not UI.confirmOpts, "Close closes it")
  -- the Feedback button is on every tab, also away from the AH
  for _, t in ipairs({ "prices", "market", "shopping", "crafts", "settings" }) do UI:Show(t); assert(UI.frame.feedback:IsShown(), "feedback on " .. t) end
  GetBuildInfo = savedGBI
  print("feedback ok")
end

-- 1.2.2 text size: build every tab at 1x, 2x and 3x on two screen sizes and audit the layout
do
  GameTooltip = GameTooltip or mock("GameTooltip")
  fire("AUCTION_HOUSE_SHOW")
  if ns.UI.confirmOpts then ns.UI:ConfirmAnswer(false) end
  -- the Market tree with a deep branch open (Armor > Plate > slots) and long names
  ns.db.settings.marketCategory, ns.db.settings.marketOpen = "Armor/Miscellaneous", true
  local UI = ns.UI
  local BASE = { GameFontNormal = 12, GameFontHighlight = 12, GameFontDisable = 12, GameFontNormalSmall = 10,
    GameFontHighlightSmall = 10, GameFontDisableSmall = 10, GameFontNormalLarge = 16, GameFontHighlightLarge = 16,
    GameFontNormalHuge = 20, ChatFontNormal = 14 }
  local function fontOf(o) local f = rawget(o, "_font"); if type(f) == "string" then f = _G[f] end; return f end
  local function shown(o) while o and o ~= UIParent do if not rawget(o, "_shown") then return false end; o = rawget(o, "_parent") end; return true end
  local function walk(o, fn, sc, inList)
    for _, c in ipairs(rawget(o, "_children") or {}) do
      local csc = sc or rawget(c, "_inScroll")
      local il = inList or rawget(c, "pcList")
      fn(c, csc, il)
      walk(c, fn, csc, il)
    end
  end
  local function intersects(a, b)
    return a[1] < b[2] - 1 and b[1] < a[2] - 1 and a[4] < b[3] - 1 and b[4] < a[3] - 1
  end
  local problems, checks = {}, 0
  local function bad(ctx, msg) if #problems < 40 then problems[#problems + 1] = ctx .. ": " .. msg end end
  local function audit(ctx)
    local W, H = GEO.screenW, GEO.screenH
    local scale = UI.scale
    local items = {}
    local function name(o)
      local t = rawget(o, "_text"); if (t == nil or t == "") and rawget(o, "_fs") then t = o._fs._text end
      return (rawget(o, "_kind") or (rawget(o, "_isFS") and "FontString") or "?") .. " '" .. tostring(t or ""):sub(1, 40) .. "'"
    end
    walk(UI.frame, function(o, sc, inList)
      if rawget(o, "_isTex") or not shown(o) then return end
      local l, r, t, b = GEO.rect(o)
      checks = checks + 1
      -- 1. inside the screen (inside its scroll frame horizontally when in a scroll area)
      if sc then
        local sl, sr = GEO.rect(sc)
        if l < sl - 1 or r > sr + 1 then bad(ctx, name(o) .. string.format(" outside its scroll area x %.0f-%.0f (area %.0f-%.0f)", l, r, sl, sr)) end
      elseif l < -1 or r > W + 1 or b < -1 or t > H + 1 then
        bad(ctx, name(o) .. string.format(" off screen (%.0f,%.0f)-(%.0f,%.0f) screen %dx%d", l, b, r, t, W, H))
      end
      -- 2. our scaled fonts on every text
      if rawget(o, "_isFS") or rawget(o, "_kind") == "EditBox" then
        local f = fontOf(o)
        local fname = f and f._fontName or "?"
        local base = fname:match("^PhyzanCapitalFont_(.+)$")
        if not base then bad(ctx, name(o) .. " uses font " .. fname .. " (not ours)")
        elseif f._size + 0.5 < BASE[base] * scale then bad(ctx, name(o) .. " font " .. f._size .. " < " .. BASE[base] .. "x" .. scale) end
        -- 3. single-line text fits its height
        local h = rawget(o, "_h")
        if rawget(o, "_isFS") and rawget(o, "_wrap") == false and h and h + 0.5 < f._size * 1.2 then bad(ctx, name(o) .. " height " .. h .. " < line") end
      end
      -- 4. button labels never cut
      local fs = rawget(o, "_fs")
      if fs and (fs._text or "") ~= "" and GEO.stringWidth(fs) > (r - l) + 0.5 then
        bad(ctx, name(o) .. string.format(" text %d wider than button %.0f", GEO.stringWidth(fs), r - l))
      end
      -- 5. list rows fit the font, columns fit the list, rows stay inside the list
      local L = rawget(o, "pcList")
      if L then
        local cellSize = GEO.textSize(L.buttons[1].cells[1])
        if L.rowH < cellSize * 1.2 then bad(ctx, "list row height " .. L.rowH .. " < font " .. cellSize) end
        if (L.usedW or 0) > (r - l) + 1 then bad(ctx, string.format("list columns %d wider than list %.0f", L.usedW, r - l)) end
        local vis = L:Visible()
        if vis < 2 and (t - b) > 0 then bad(ctx, "list shows only " .. vis .. " rows (height " .. (t - b) .. ")") end
        if t - (vis + 1) * L.rowH < b - 1 and vis > 3 then bad(ctx, "list rows run past the list bottom") end
      end
      -- 6. collect controls and labels for the overlap check (list internals excluded)
      if not inList then
        local kind = rawget(o, "_kind")
        local isLabel = rawget(o, "_isFS") and (o._text or "") ~= "" and not rawget(rawget(o, "_parent"), "_fs")
          and rawget(rawget(o, "_parent"), "_kind") ~= "Button"
        if (kind == "Button" and rawget(o, "_template")) or kind == "EditBox" or kind == "CheckButton" or kind == "Slider" or isLabel then
          if not (rawget(o, "_isFS") and rawget(o, "_parent") and rawget(rawget(o, "_parent"), "_fs") == o) then
            items[#items + 1] = { o = o, rect = { l, r, t, b }, sc = sc }
          end
        end
      end
    end)
    for i = 1, #items do
      for j = i + 1, #items do
        local a, b2 = items[i], items[j]
        if a.sc == b2.sc and intersects(a.rect, b2.rect) then
          bad(ctx, name(a.o) .. " overlaps " .. name(b2.o))
        end
      end
    end
  end
  local tabs = { "search", "prices", "buy", "market", "shopping", "crafts", "settings" }
  for _, screen in ipairs({ { 1365, 768 }, { 1920, 1080 } }) do
    GEO.screenW, GEO.screenH = screen[1], screen[2]
    for _, sc in ipairs({ 1.0, 2.0, 3.0 }) do
      UI:Show("search")
      UI:SetTextScale(sc)
      assert(UI.scale == sc and PhyzanCapitalDB.settings.textScale == sc)
      for _, tab in ipairs(tabs) do
        UI:Show(tab)
        audit(string.format("%dx%d %.1fx %s", screen[1], screen[2], sc, tab))
        if tab == "crafts" then -- 1.3.1: "Available on AH" header and a 5-digit count fit their columns
          local pc = UI.panels.crafts
          for _, L in ipairs({ pc.list, pc.reagents }) do
            local c = #L.cols
            local hl = L.header[c].label
            assert(L.cols[c][1] == "Available on AH", "Available column is last")
            assert(GEO.stringWidth(hl) <= L.colW[c] - UI.S(4) + 0.5, string.format("%dx%d %.1fx Available header '%s' fits (%d > %d)",
              screen[1], screen[2], sc, tostring(hl._text), GEO.stringWidth(hl), L.colW[c] - UI.S(4)))
            local cell = L.buttons[1].cells[c]
            local old = cell._text
            cell:SetText("88888")
            assert(GEO.stringWidth(cell) <= L.colW[c] - UI.S(6) + 0.5, string.format("%.1fx Available count fits", sc))
            cell:SetText(old)
          end
        end
      end
      -- 1.4.0: the six remaining tab buttons sit in one tidy row (or wrapped rows) with even spacing, no holes
      do
        local prevR, prevT, rowL, nTabs = nil, nil, nil, 0
        for _, t in ipairs(UI.TAB_ORDER) do
          local tb = UI.frame.tabs[t[1]]
          assert(tb and tb:IsShown(), "tab button shown: " .. t[1])
          nTabs = nTabs + 1
          local l, r, top = GEO.rect(tb)
          if prevT and math.abs(top - prevT) < 1 then
            assert(math.abs(l - prevR - UI.S(4)) <= 1, string.format("%.1fx %dx%d: gap before tab %s (%.0f)", sc, GEO.screenW, GEO.screenH, t[1], l - prevR))
          else
            if rowL then assert(math.abs(l - rowL) <= 1, "wrapped tab row starts at the left edge") end
            rowL = rowL or l
          end
          prevR, prevT = r, top
        end
        assert(nTabs == 6, "six tabs")
        -- Feedback button: visible, on screen, inside the top bar, not over the scan button or the close button
        local fbb = UI.frame.feedback
        local fl, fr, ft, fbo = GEO.rect(fbb)
        assert(fbb:IsShown() and fl >= 0 and fr <= GEO.screenW and fbo >= 0 and ft <= GEO.screenH, "feedback button on screen")
        assert(GEO.stringWidth(fbb._fs) <= fbb:GetWidth() and GEO.textSize(fbb._fs) >= 12 * sc, "feedback label fits and is scaled")
        local sl = GEO.rect(UI.frame.scan)
        local _, _, _, tb = GEO.rect(UI.frame.tabs.search)
        assert(fr <= sl or fbo >= tb, "feedback beside the scan button or on line 2, above the tabs")
      end
      -- popups at this size
      -- our confirmation dialog with long texts: everything inside the frame, frame on screen
      local long = string.rep("Supercalifragilistic Name ", 3):sub(1, 60)
      assert(#long == 60)
      local cases = {
        { text = "Phyzan Capital\n\nAdd |cff1eff00Red Fireworks Rocket|r to crafting list?\n\nfrom Sayge - Elwynn Forest (2,345 yd)  " ..
          "|cffffd100[Darkmoon Faire (only when the faire is in town)]|r\nat 25s 00c each\nAH lowest 1g 20s 00c, margin 89s 00c / unit",
          edit = { label = "Quantity:", default = 20, numeric = true, width = 70 } },
        { text = "See vendor on map?\n\n" .. long .. "\n" .. long .. " - Stranglethorn Vale, other continent\n(limited stock)\n" ..
          "|cffffd100Darkmoon Faire (only when the faire is in town)|r" },
        { text = "See vendor on map?\n\n|cff1eff00Red Fireworks Rocket|r\nWizbang Booms\nIronforge, other continent\n" ..
          "|cffffd100Holiday Fireworks Vendor (holiday only, no permanent spawn)|r", alt = { text = "Vendor not here", fn = function() end } },
        { text = "Buy out\n" .. long .. " x20\nfor 53939928g 11s 34c total (2696996g 40s 56c each)?" },
        { text = string.rep("A very long single line without any breaks that must wrap inside the dialog ", 6), kind = "ok" },
      }
      -- the command list (left aligned, with the "don't show again" check box)
      local cl = {}
      for _, cmd in ipairs(ns.HELP_COMMANDS) do if not cmd.chatOnly then cl[#cl + 1] = "|cffffd100" .. cmd[1] .. "|r  " .. cmd[2] end end
      cases[#cases + 1] = { text = table.concat(cl, "\n"), kind = "ok", justify = "LEFT", title = "Phyzan Capital commands",
        check = { label = "Don't show this when the auction house opens", checked = false, onChange = function() end } }
      -- the feedback dialog: message, read-only address box, hint + report line, Close
      cases[#cases + 1] = { text = "Send suggestions and bug reports to:", kind = "ok", okText = "Close", title = "Phyzan Capital feedback",
        edit = { label = "", default = "kingofthefallllc@gmail.com", readOnly = true },
        footer = "|cffffd100Press Ctrl+C to copy|r\n\nPlease include this line in bug reports:\nPhyzan Capital 1.4.2, client 1.60.1 (build 70450), interface 16001, enUS" }
      if sc == 3.0 then -- far too long for the screen at normal size: drops one font size and still fits
        cases[#cases + 1] = { text = string.rep("A very long single line without any breaks that must wrap inside the dialog ", 9), kind = "ok", small = true }
      end
      for ci, c in ipairs(cases) do
        local yes = 0
        c.onYes = function() yes = yes + 1 end
        local d = UI:Confirm(c)
        local dl, dr, dt, db = GEO.rect(d)
        local ctx = string.format("dialog %d at %.1fx %dx%d", ci, sc, GEO.screenW, GEO.screenH)
        assert(dl >= 0 and dr <= GEO.screenW and db >= 0 and dt <= GEO.screenH, ctx .. " on screen")
        assert(dr - dl <= GEO.screenW * 0.8 + 1, ctx .. " width <= 80% of the screen")
        assert(d._strata == "FULLSCREEN_DIALOG", ctx .. " strata")
        local function inside(w, what)
          local l, r, t, b = GEO.rect(w)
          assert(l >= dl and r <= dr and t <= dt and b >= db, string.format("%s: %s outside the dialog (%.0f,%.0f)-(%.0f,%.0f) vs (%.0f,%.0f)-(%.0f,%.0f)",
            ctx, what, l, b, r, t, dl, db, dr, dt))
          return l, r, t, b
        end
        local _, _, mt, mb = inside(d.msg, "message")
        assert(GEO.stringHeight(d.msg) <= (mt - mb) + 0.5, ctx .. " message height fits")
        local fname = d.msg._font._fontName
        if d.scrolling then -- too tall even one size smaller: the message scrolls inside the dialog
          assert(c.check and not d.msg:IsShown() and d.msgScroll:IsShown(), ctx .. " only the command list needs to scroll")
          local _, _, st2, sb2 = inside(d.msgScroll, "message scroll area")
          assert(st2 - sb2 > 4 * GEO.textSize(d.smsg), ctx .. " scroll area shows several lines")
          assert(d.smsg._font._fontName == "PhyzanCapitalFont_GameFontHighlightSmall" and GEO.textSize(d.smsg) >= 10 * sc, ctx .. " scroll text scaled")
          assert(d.smsg:GetText():find("/capital reset", 1, true), ctx .. " whole list in the scroll area")
          local maxs = d.msgChild:GetHeight() - d.msgScroll:GetHeight()
          assert(maxs > 0, ctx .. " scrollable")
          d.msgScroll._scripts.OnMouseWheel(d.msgScroll, -100)
          assert(math.abs(d.msgScroll:GetVerticalScroll() - maxs) < 1, ctx .. " wheel scrolls to the end")
          fname, c.small = "PhyzanCapitalFont_GameFontHighlight", nil
          if sc == 3.0 then print(ctx .. ": command list scrolls") end
        else
          assert(d.msg:IsShown() and not d.msgScroll:IsShown(), ctx .. " no scroll area for short messages")
        end
        assert((fname == "PhyzanCapitalFont_GameFontHighlight" and GEO.textSize(d.msg) >= 12 * sc)
          or ((c.small or c.check) and fname == "PhyzanCapitalFont_GameFontHighlightSmall" and GEO.textSize(d.msg) >= 10 * sc) or d.scrolling, ctx .. " scaled font")
        if c.small and GEO.screenH == 768 then assert(fname:find("Small", 1, true), ctx .. " smaller font when needed") end
        inside(d.title, "title")
        local _, _, yt = inside(d.yes, "yes button")
        assert(yt < mb, ctx .. " buttons below the message")
        assert(GEO.stringWidth(d.yes._fs) <= d.yes:GetWidth(), ctx .. " yes label fits")
        if c.kind ~= "ok" then
          inside(d.no, "no button")
          assert(GEO.stringWidth(d.no._fs) <= d.no:GetWidth(), ctx .. " no label fits")
          local _, yr = GEO.rect(d.yes); local nl = GEO.rect(d.no)
          assert(yr <= nl, ctx .. " buttons side by side")
        end
        if c.alt then
          local al, ar, at = inside(d.alt, "alt button")
          assert(d.alt:IsShown() and GEO.stringWidth(d.alt._fs) <= d.alt:GetWidth(), ctx .. " alt label fits")
          local _, nr, _, nb = GEO.rect(d.no)
          local yl, yr, _, yb = GEO.rect(d.yes)
          assert(al >= nr or at <= nb, ctx .. " alt beside or below No")
          assert(at <= yb or al >= yr or ar <= yl, ctx .. " alt does not overlap Yes")
          assert(ar <= dr, ctx .. " alt inside")
        else
          assert(not d.alt:IsShown(), ctx .. " no alt button unless asked")
        end
        if c.footer then
          local _, _, ftp, fbt = inside(d.foot, "footer")
          assert(GEO.stringHeight(d.foot) <= ftp - fbt + 0.5, ctx .. " footer height fits")
          local _, _, _, eb2 = GEO.rect(d.edit)
          assert(ftp <= eb2 + 1 and fbt > yt, ctx .. " footer between the box and the button")
          assert(GEO.stringWidth(d.edit) <= d.edit:GetWidth(), ctx .. " address fits its box")
          assert(d.yes._fs:GetText() == "Close", ctx .. " Close")
        else
          assert(not d.foot:IsShown(), ctx .. " no footer unless asked")
        end
        if c.check then
          inside(d.check, "check box"); inside(d.check.label, "check box label")
          local _, _, _, cb = GEO.rect(d.check)
          assert(cb > yt, ctx .. " check box above the buttons")
          local _, _, _, mb2 = GEO.rect(d.msg)
          local _, _, ct = GEO.rect(d.check)
          assert(ct <= mb2 + 1, ctx .. " check box below the message")
        else
          assert(not d.check:IsShown(), ctx .. " no check box unless asked")
        end
        if c.edit then
          inside(d.edit, "edit box"); inside(d.editLabel, "edit label")
          assert(rawget(d.edit, "_font")._fontName == "PhyzanCapitalFont_ChatFontNormal", ctx .. " edit box font")
          local _, _, _, eb = GEO.rect(d.edit)
          assert(eb > yt, ctx .. " edit box above the buttons")
        end
        -- Enter = Yes for the first case, Escape = No otherwise; both close the dialog
        if sc == 3.0 and GEO.screenW == 1365 then print(string.format("%s: %.0fx%.0f, message %.0f high", ctx, dr - dl, dt - db, mt - mb)) end
        d._scripts.OnKeyDown(d, ci == 1 and "ENTER" or "ESCAPE")
        assert(not d:IsShown() and yes == (ci == 1 and 1 or 0), ctx .. " keys")
      end
      print(string.format("layout %dx%d at %.1fx: tab rows y=%d, content %dx%d", screen[1], screen[2], sc,
        UI.frame.contentTop, UI.PanelW(), UI.PanelH()))
    end
  end
  if #problems > 0 then for _, p in ipairs(problems) do print("LAYOUT: " .. p) end end
  assert(#problems == 0, #problems .. " layout problems")
  print("layout audit ok: " .. checks .. " widget checks")
  -- slash command and slider (clamped, step 0.25)
  GEO.screenW, GEO.screenH = 1365, 768
  SlashCmdList.PHYZANCAPITAL("textsize 2.6")
  assert(UI.scale == 2.5 and PhyzanCapitalDB.settings.textScale == 2.5, "textsize rounds to 0.25 steps")
  SlashCmdList.PHYZANCAPITAL("textsize 9")
  assert(UI.scale == 3.0, "textsize clamps to 3")
  SlashCmdList.PHYZANCAPITAL("textsize 0.5")
  assert(UI.scale == 1.0, "textsize clamps to 1")
  UI:Show("settings")
  local sp = UI.panels.settings
  sp.textSize:SetValue(1.75)
  assert(sp.tsLabel:GetText():find("release to apply", 1, true) and UI.scale == 1.0, "slider waits for release")
  sp.textSize._scripts.OnMouseUp(sp.textSize)
  assert(UI.scale == 1.75 and UI.frame:IsShown() and UI.tab == "settings", "slider applies live and stays on Settings")
  UI.panels.settings.tsPlus._scripts.OnClick()
  assert(UI.scale == 2.0, "+ button")
  -- the rebuilt window's scan button is the only one registered with the scanner from our frame
  local own = 0
  for _, b in ipairs(ns.Scanner.buttons) do if rawget(b, "_parent") and b._parent._name == "PhyzanCapitalFrame" and b == UI.frame.scan then own = own + 1 end end
  assert(own == 1, "scan button re-registered once")
  -- truncated cells show their full text on hover
  UI:Show("market")
  local L = UI.panels.market.list
  L:SetData({ { "Short", "1", "2", string.rep("Very long text ", 10), "", "", "", "" } })
  local lines = {}
  GameTooltip.AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. "=" .. b end
  L.buttons[1]._scripts.OnEnter(L.buttons[1])
  assert(#lines == 1 and lines[1]:find("Lowest / unit=Very long", 1, true), "truncated cell tooltip")
  print("text size tests ok")
end

-- write SavedVariables in WoW's format
local function ser(v, ind)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t ~= "table" then return tostring(v) end
  local out, n = { "{\n" }, #v
  for i = 1, n do out[#out + 1] = ind .. "\t" .. ser(v[i], ind .. "\t") .. ", -- [" .. i .. "]\n" end
  local keys = {}
  for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local ks = type(k) == "string" and string.format("[%q]", k) or ("[" .. tostring(k) .. "]")
    out[#out + 1] = ind .. "\t" .. ks .. " = " .. ser(v[k], ind .. "\t") .. ",\n"
  end
  out[#out + 1] = ind .. "}"
  return table.concat(out)
end
local fh = assert(io.open(OUT, "w"))
fh:write("\nPhyzanCapitalDB = " .. ser(PhyzanCapitalDB, "") .. "\n")
fh:close()
-- v1 -> v2 migration: global manual skills become overrides for the first character that logs in
PhyzanCapitalDB = { schemaVersion = 1, professions = { Tailoring = 99 }, observedSkills = { Tailoring = 50 }, settings = { charLevel = 60 },
  usage = { ["tab:flips"] = 4, ["tab:swaps"] = 1 }, usageLast = { ["tab:flips"] = 123 } }
ns.InitDB()
assert(PhyzanCapitalDB.usage["tab:swaps"] == 5 and PhyzanCapitalDB.usage["tab:flips"] == nil and PhyzanCapitalDB.usageLast["tab:swaps"] == 123, "v3 usage migration")
assert(PhyzanCapitalDB.schemaVersion == 8 and PhyzanCapitalDB.professions == nil and PhyzanCapitalDB.settings.charLevel == nil)
fire("PLAYER_LOGIN")
assert(ns.GetProfSkill("Tailoring") == 99 and ns.Char:HasOverrides(), "v1 migration")
-- 1.3.1 (schema 7) -> 1.4.0 (schema 8): Sell/Post + Vendor Swaps data dropped, the Shopping List entries become the
-- Crafting List unchanged (same key), unknown settings untouched
PhyzanCapitalDB = { schemaVersion = 7, addonVersion = "1.3.1",
  settings = { undercut = 5, durationMode = 2, defaultDuration = 3, swapsOnlyProfitable = true, postMode = "blizzard", textScale = 2.0,
    hideSeasonalVendors = true },
  postLog = { { ts = 1, itemID = 2589, mode = "blizzard", result = "handed off" } },
  debug = { directPostBlocked = true, postMode = "blizzard", blocked = { { event = "ADDON_ACTION_BLOCKED", fn = "C_AuctionHouse.PostItem()" } } },
  shopping = { ["Fredrick-Forever"] = { [2320] = { itemID = 2320, name = "Coarse Thread", qty = 8, bought = 3, vendorUnit = 10, ahUnit = 20,
    vendorName = "Tharynn Bouden", vendorZone = "Elwynn Forest", added = 100 } },
    ["Alt-Forever"] = { [2604] = { itemID = 2604, name = "Red Dye", qty = 2, bought = 0, vendorUnit = 50 } } },
  shoppingLog = { { itemID = 2321, qty = 1, bought = 1, reason = "purchased" } } }
ns.InitDB()
do
  local d = PhyzanCapitalDB
  assert(d.schemaVersion == 8 and d.postLog == nil, "v8: postLog dropped")
  for _, k in ipairs({ "undercut", "durationMode", "defaultDuration", "swapsOnlyProfitable", "postMode" }) do
    assert(d.settings[k] == nil, "v8: setting " .. k .. " dropped")
  end
  assert(d.settings.textScale == 2.0 and d.settings.hideSeasonalVendors == true, "v8: other settings kept")
  assert(d.debug.directPostBlocked == nil and d.debug.postMode == nil and #d.debug.blocked == 1, "v8: debug post flags dropped, block record kept")
  local e = d.shopping["Fredrick-Forever"][2320]
  assert(e and e.qty == 8 and e.bought == 3 and e.vendorName == "Tharynn Bouden" and e.added == 100, "v8: crafting list entry kept as it was")
  assert(d.shopping["Alt-Forever"][2604].qty == 2 and #d.shoppingLog == 1, "v8: other characters' lists and history kept")
  assert(ns.Shop:List()[2320] == e and ns.Shop:Count() == 1, "v8: Crafting List reads the old entries")
  ns.InitDB() -- running again changes nothing
  assert(d.shopping["Fredrick-Forever"][2320].qty == 8 and d.schemaVersion == 8, "v8: migration is idempotent")
  print("schema 8 migration ok")
end
-- ===== WoW Forever client (1.60.1, Interface 16001, Mainline API) =====
-- A second, fresh copy of the addon runs in its own global environment that models the Forever client: only the
-- modern namespaced APIs exist. The classic globals (GetItemInfo, GetItemIcon, GetItemInfoInstant, GetItemCount,
-- GetSpellInfo, GetContainer*, GetMerchantItemInfo, GetTradeSkill*, GetCraft*, GetSkillLineInfo, QueryAuctionItems,
-- StartAuction, ...) are simply absent, registering a classic-only event raises an error, and calling a protected
-- function is recorded as an "Interface action failed".
do
  local LEGACY = {}
  for _, n in ipairs({ "GetItemInfo", "GetItemIcon", "GetItemInfoInstant", "GetItemCount", "GetSpellInfo",
    "GetContainerNumSlots", "GetContainerItemInfo", "GetContainerItemLink", "PickupContainerItem", "UseContainerItem",
    "GetMerchantItemInfo", "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink",
    "GetTradeSkillNumMade", "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
    "GetNumCrafts", "GetCraftInfo", "GetCraftDisplaySkillLine", "GetCraftSkillLine", "GetNumSkillLines", "GetSkillLineInfo",
    "ExpandSkillHeader", "CollapseSkillHeader", "QueryAuctionItems", "CanSendAuctionQuery", "GetAuctionItemInfo",
    "GetNumAuctionItems", "GetAuctionItemLink", "GetAuctionItemTimeLeft", "PlaceAuctionBid", "StartAuction",
    "CalculateAuctionDeposit", "ClickAuctionSellItemButton", "GetAuctionSellItemInfo", "AuctionFrame" }) do LEGACY[n] = true end
  local LEGACY_EVENTS = { AUCTION_ITEM_LIST_UPDATE = true, NEW_AUCTION_UPDATE = true, CRAFT_SHOW = true, CRAFT_UPDATE = true }
  local legacyProbed, protectedCalls, chat = {}, {}, {}
  local env = {}
  setmetatable(env, { __index = function(_, k)
    if LEGACY[k] then legacyProbed[k] = true end
    return nil
  end })
  for _, k in ipairs({ "string", "table", "math", "pairs", "ipairs", "type", "tostring", "tonumber", "select", "unpack",
    "pcall", "xpcall", "error", "next", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "assert", "print",
    "time", "date", "C_Timer" }) do env[k] = _G[k] end
  env._G = env
  for k, v in pairs(_G) do if type(v) == "table" and rawget(v, "_fontName") then env[k] = v end end -- Blizzard font objects
  env.CreateFont = function(name) local f = CreateFont(name); env[name] = f; return f end

  registry = {} -- events of this copy only (the first copy's frames no longer receive events)
  local function wrapFrame(f, name)
    if name then env[name] = f end
    f.RegisterEvent = function(self, e)
      if LEGACY_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"") end
      registry[e] = registry[e] or {}; table.insert(registry[e], self)
    end
    return f
  end
  env.CreateFrame = function(kind, name, parent, template) return wrapFrame(CreateFrame(kind, name, parent, template), name) end
  env.UIParent = UIParent
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m; print((m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end }
  env.UISpecialFrames, env.StaticPopupDialogs, env.SlashCmdList = {}, {}, {}
  env.GetRealmName = function() return "Classic Beta PvE" end
  env.UnitFactionGroup = function() return "Alliance" end
  local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
  local npcName = "Tharynn Bouden"
  env.UnitName = function(u) if u == "npc" then return npcName end return "Phyzan" end
  env.UnitGUID = function(u) if u == "npc" then return "Creature-0-1-0-1-6567-0000ABCDEF" end return "Player-1-0001" end
  env.issecretvalue = function(v) return v == SECRET end
  env.GetRealZoneText = function() return "Elwynn Forest" end
  env.IsShiftKeyDown = function() return false end
  env.GetMoney = function() return 500000 end
  env.UnitLevel = function() return 14 end
  env.GetBuildInfo = function() return "1.60.1", "70450", "Oct 1 2026", 16001 end
  env.WOW_PROJECT_ID = 18
  env.NUM_BAG_SLOTS, env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 5
  local inCombat = false
  env.InCombatLockdown = function() return inCombat end
  env.hooksecurefunc = function(name, fn) local orig = env[name]; env[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end end
  local tipLines = {}
  env.GameTooltip = mock("GameTooltip")
  env.GameTooltip.AddLine = function(_, s) tipLines[#tipLines + 1] = tostring(s) end
  env.GameTooltip.SetItemByID = function() end
  env.PlaySound = function() end
  env.SOUNDKIT = { AUCTION_WINDOW_OPEN = 5274, RAID_WARNING = 8959 }
  env.C_XMLUtil = { GetTemplateInfo = function(n) if n == "UISliderTemplateWithLabels" then return { type = "Slider" } end end }

  -- C_Item: GetItemInfo returns nothing until the item is "cached"; icons and counts work without a cache
  local cached, requested = { [2320] = true, [2604] = true, [2996] = true, [2572] = true }, {}
  local bagCounts = { [2589] = 20, [2320] = 5 }
  env.C_Item = {
    GetItemInfo = function(id) id = tonumber(id) or tonumber(tostring(id):match("item:(%d+)"))
      local it = ITEMS[id]; if not it or not cached[id] then return nil end
      return it[1], "item:" .. id, it[2], 1, 1, "Trade Goods", "Cloth", it[3], "", 1000 + id, it[4] end,
    GetItemNameByID = function(id) return cached[id] and ITEMS[id] and ITEMS[id][1] or nil end,
    GetItemQualityByID = function(id) return cached[id] and ITEMS[id] and ITEMS[id][2] or nil end,
    GetItemIconByID = function(id) return ITEMS[id] and (1000 + id) or nil end,
    GetItemInfoInstant = function(id) return id, "Trade Goods", "Cloth", "", 1000 + id end,
    GetItemCount = function(id) return bagCounts[id] or 0 end,
    RequestLoadItemDataByID = function(id) requested[id] = true end,
  }
  env.C_Spell = { GetSpellName = function(id) return ({ [3908] = "Schneiderei", [2550] = "Kochkunst" })[id] end }
  -- character: Phyzan, level 14 - Tailoring 86, Skinning 75, Fishing 1, Cooking 44 (localized names, some without skillLine)
  local PROFS = { { "Schneiderei", 86, 150, 197 }, { "Skinning", 75, 150, 393 }, nil, { "Fishing", 1, 75, 356 }, { "Kochkunst", 44, 75, nil } }
  env.GetProfessions = function() return 1, 2, nil, 4, 5 end
  env.GetProfessionInfo = function(i) local p = PROFS[i]; return p[1], 136000 + i, p[2], p[3], 2, 0, p[4] end
  local robes = {} -- gear for the posting tests: robes[bag] = true puts a Red Linen Robe in slot 2
  local boots = 0 -- Linen Boots (gear): bag 1 slots 1..boots, one per slot
  -- bags: bag 0 slot 1 Linen Cloth x20 (icon in the slot info), reagent bag 5 slot 1 Coarse Thread x5 (no icon field)
  env.C_Container = {
    GetContainerNumSlots = function(b) if b == 1 then return 20 end return (b == 0 or b == 5) and 2 or 0 end,
    GetContainerItemInfo = function(b, s)
      if b == 0 and s == 1 then return { stackCount = 20, hyperlink = "|cffffffff|Hitem:2589::::::::14:::::|h[Linen Cloth]|h|r", iconFileID = 132889, itemID = 2589 } end
      if b == 5 and s == 1 then return { stackCount = 5, hyperlink = "|Hitem:2320|h", itemID = 2320 } end
      if b == 1 and s <= boots then return { stackCount = 1, hyperlink = "|Hitem:2569|h", itemID = 2569, iconFileID = 3569 } end
      if (b == 0 or b == 5) and s == 2 and robes[b] then return { stackCount = 1, hyperlink = "|Hitem:2572|h", itemID = 2572, iconFileID = 3572 } end
    end,
    PickupContainerItem = function() end,
  }
  env.ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { bag = b, slot = s } end }
  env.CursorHasItem = function() return false end
  env.ClearCursor = function() end
  env.GetCursorInfo = function() return nil end
  -- merchant: C_MerchantFrame.GetItemInfo tables; slot 3 costs a token (extended cost)
  local MERCH = { { 2320, "Coarse Thread", 10, 1 }, { 2604, "Red Dye", 50, 1 }, { 2589, "Linen Cloth", 0, 1, true } }
  env.GetMerchantNumItems = function() return #MERCH end
  env.C_MerchantFrame = { GetItemInfo = function(i) local m = MERCH[i]; if not m then return nil end
    return { name = m[2], texture = 1000 + m[1], price = m[3], stackCount = m[4], numAvailable = -1, isPurchasable = true,
      isUsable = true, hasExtendedCost = m[5] or false } end }
  env.GetMerchantItemLink = function(i) return MERCH[i] and ("|Hitem:" .. MERCH[i][1] .. "|h") or nil end
  env.BuyMerchantItem = function(i, q) local id = MERCH[i][1]; bagCounts[id] = (bagCounts[id] or 0) + (q or 1) end
  -- map: waypoint API; C_SuperTrack is protected on Forever
  local wp
  env.C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return { x = 0.418, y = 0.672 } end,
    SetUserWaypoint = function(p) wp = p end, ClearUserWaypoint = function() wp = nil end, GetUserWaypoint = function() return wp end,
    CanSetUserWaypointOnMap = function() return true end }
  env.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
  env.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() protectedCalls[#protectedCalls + 1] = "C_SuperTrack.SetSuperTrackedUserWaypoint" end }
  env.OpenWorldMap = function() end
  -- profession window: C_TradeSkillUI
  local linked = false
  local RECIPES = {
    [2963] = { info = { name = "Bolt of Linen Cloth", learned = true, relativeDifficulty = 2 },
      sc = { outputItemID = 2996, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2589 } } } } } },
    [2389] = { info = { name = "Red Linen Robe", learned = true, relativeDifficulty = 0 },
      sc = { outputItemID = 2572, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
        { reagentType = 1, quantityRequired = 3, reagents = { { itemID = 2996 } } }, { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2320 } } },
        { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2604 } } }, { reagentType = 0, quantityRequired = 1, reagents = { { itemID = 99999 } } } } } },
    [3914] = { info = { name = "Brown Linen Pants", learned = false }, sc = { outputItemID = 4343, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {} } },
  }
  env.C_TradeSkillUI = {
    IsTradeSkillReady = function() return true end,
    IsTradeSkillLinked = function() return linked end,
    IsTradeSkillGuild = function() return false end,
    GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Schneiderei", skillLevel = 87, maxSkillLevel = 150 } end,
    GetChildProfessionInfo = function() return { professionID = 0, skillLevel = 0 } end,
    GetAllRecipeIDs = function() return { 2963, 2389, 3914 } end,
    GetRecipeInfo = function(id) return RECIPES[id] and RECIPES[id].info end,
    GetRecipeSchematic = function(id) return RECIPES[id] and RECIPES[id].sc end,
  }
  -- auction house: C_AuctionHouse only, AuctionHouseFrame (no AuctionFrame)
  env.Enum = { ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 }, AuctionHouseSortOrder = { Price = 0, Name = 1 },
    AuctionHouseFilter = { UsableOnly = 1 } }
  env.AuctionHouseFrame = mock("AuctionHouseFrame")
  local FA = { { 2589, 20, 200, 260, 3, "Bob" }, { 2320, 10, 5, 10, 3, "Ann" }, { 2604, 1, 30, 40, 2, "Ann" } }
  local posted
  local postCalls, needsConfirm = {}, false
  local ahReady, inYes = true, false -- IsThrottledMessageSystemReady(); true only while our Yes button's OnClick runs
  env.C_AuctionHouse = {
    ReplicateItems = function() end,
    GetNumReplicateItems = function() return #FA end,
    GetReplicateItemInfo = function(i) local a = FA[i + 1]; if not a then return nil end
      return ITEMS[a[1]][1], 1000 + a[1], a[2], 1, true, 1, 0, a[3], 5, a[4], 0, false, nil, a[6], a[6], 0, a[1], true end,
    GetReplicateItemTimeLeft = function(i) return FA[i + 1][5] end,
    SendBrowseQuery = function() end, GetBrowseResults = function() return {} end, HasFullBrowseResults = function() return true end,
    IsSellItemValid = function() return true end,
    GetItemCommodityStatus = function(loc) return (loc.bag == 1 or loc.slot == 2) and 1 or 2 end,
    GetAvailablePostCount = function(loc) if loc.bag == 1 then return boots end return loc.slot == 2 and 1 or 20 end,
    IsThrottledMessageSystemReady = function() return ahReady end,
    CalculateCommodityDeposit = function() return 15 end,
    CalculateItemDeposit = function() return 40 end,
    PostCommodity = function(...) posted = { ... }; postCalls[#postCalls + 1] = { "PostCommodity", ... }; return needsConfirm end,
    PostItem = function(...) postCalls[#postCalls + 1] = { "PostItem", inClick = inYes, n = select("#", ...), ... }; return needsConfirm end,
    ConfirmPostCommodity = function(...) postCalls[#postCalls + 1] = { "ConfirmPostCommodity", ... } end,
    ConfirmPostItem = function(...) postCalls[#postCalls + 1] = { "ConfirmPostItem", ... } end,
  }
  env.Enum.AuctionHouseError = { NotEnoughMoney = 0, ItemNotFound = 4, DatabaseError = 10 }
  env.AUCTION_DURATION_ONE, env.AUCTION_DURATION_TWO, env.AUCTION_DURATION_THREE = "12 Hours", "24 Hours", "48 Hours"

  -- load a fresh copy in this environment
  local ns2 = {}
  for line in io.lines("PhyzanCapital.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^##") then
      local chunk = assert(loadfile((line:gsub("\\", "/"))))
      setfenv(chunk, env)
      chunk("PhyzanCapital", ns2)
    end
  end
  fire("ADDON_LOADED", "PhyzanCapital")
  local DB = env.PhyzanCapitalDB
  assert(type(DB) == "table" and DB.schemaVersion == 8 and DB.addonVersion == ns2.VERSION, "Forever: SavedVariables initialised")
  local fpopup
  ns2.UI.OnConfirmShown = function(o, d) fpopup = { text = o.text, dialog = d, opts = o } end

  -- 1. level + professions from GetProfessions/GetProfessionInfo (no skills pane on Forever); localized names via C_Spell
  fire("PLAYER_LOGIN")
  local rec = DB.chars["Phyzan-Classic Beta PvE"]
  assert(rec and rec.level == 14, "Forever: level")
  local pr = rec.professions
  assert(pr.Tailoring and pr.Tailoring.rank == 86 and pr.Skinning.rank == 75 and pr.Fishing.rank == 1, "Forever: professions via skillLine")
  assert(pr.Cooking and pr.Cooking.rank == 44, "Forever: localized name resolved through C_Spell.GetSpellName")

  -- 2. item data: C_Item.GetItemInfo; uncached items are requested and filled in when ITEM_DATA_LOAD_RESULT arrives
  local it = ns2.TouchItem(2589)
  assert(it and it.sellPrice == nil and requested[2589], "Forever: uncached item requested")
  cached[2589] = true
  fire("ITEM_DATA_LOAD_RESULT", 2589, true)
  assert(DB.items[2589].sellPrice == 13 and DB.items[2589].stack == 20 and DB.items[2589].name == "Linen Cloth", "Forever: sell price via C_Item.GetItemInfo")
  assert(ns2.TouchItem(2320).sellPrice == 2, "Forever: cached item sell price")
  assert(ns2.ItemIcon(2604) == 3604 and ns2.ItemCount(2589) == 20, "Forever: C_Item icon + count")

  -- 3. merchant window: C_MerchantFrame.GetItemInfo
  fire("MERCHANT_SHOW")
  assert(DB.vendorPrices[2320] and DB.vendorPrices[2320].unit == 10 and DB.vendorPrices[2604].unit == 50, "Forever: vendor prices recorded")
  assert(DB.vendorPrices[2589] == nil, "Forever: extended-cost slot not priced")
  local ov = DB.observedVendors[6567]
  assert(ov and ov.name == "Tharynn Bouden" and ov.items[2589] == 0 and ov.uiMapID == 1429 and ov.complete, "Forever: merchant observed")
  npcName = SECRET -- a secret unit name is never stored or compared
  fire("MERCHANT_UPDATE")
  assert(DB.vendorPrices[2320].merchant == "?" and DB.observedVendors[6567], "Forever: secret merchant name ignored")
  npcName = "Tharynn Bouden"
  fire("MERCHANT_UPDATE")
  -- shopping list counts purchases with C_Item.GetItemCount
  ns2.Shop:List()[2320] = { itemID = 2320, name = "Coarse Thread", qty = 3, bought = 0, added = 1 }
  ns2.Shop:Snapshot()
  env.BuyMerchantItem(1, 3)
  fire("BAG_UPDATE")
  assert(ns2.Shop:List()[2320] == nil, "Forever: shopping list purchase counted")
  fire("MERCHANT_CLOSED")

  -- 4. profession window: C_TradeSkillUI (learned recipes only, basic reagents only)
  PROFS[1][2] = 87 -- a skill-up seen by both the profession window and GetProfessionInfo
  fire("TRADE_SKILL_SHOW")
  assert(DB.recipes["Tailoring:2996"] and DB.recipes["Tailoring:2996"].reagents == "2589:2", "Forever: recipe recorded")
  assert(DB.recipes["Tailoring:2572"].reagents == "2996:3;2320:2;2604:2" and not DB.recipes["Tailoring:2572"].incomplete, "Forever: optional reagent ignored")
  assert(DB.recipes["Tailoring:4343"] == nil, "Forever: unlearned recipe skipped")
  assert(DB.recipes["Tailoring:2572"].difficulty == "optimal" and DB.recipes["Tailoring:2572"].knownBy == "Phyzan-Classic Beta PvE")
  assert(rec.professions.Tailoring.rank == 87, "Forever: tradeskill window updates rank")
  linked = true
  RECIPES[3914].info.learned = true
  fire("TRADE_SKILL_LIST_UPDATE")
  assert(DB.recipes["Tailoring:4343"] == nil, "Forever: linked profession window not recorded as yours")
  linked = false
  RECIPES[3914].info.learned = false
  -- 1.3.0: the Fishing window still returning the previous (Tailoring) list is not stored as Fishing recipes
  local TS = env.C_TradeSkillUI
  local baseInfo = TS.GetBaseProfessionInfo
  TS.GetBaseProfessionInfo = function() return { professionID = 356, professionName = "Fishing", skillLevel = 20, maxSkillLevel = 75 } end
  fire("TRADE_SKILL_SHOW")
  for k in pairs(DB.recipes) do assert(not k:find("^Fishing:"), "Forever: no recipes under Fishing: " .. k) end
  -- the game's own per-recipe profession wins over the window's (Cooking window, Tailoring recipe)
  TS.GetBaseProfessionInfo = function() return { professionID = 185, professionName = "Cooking", skillLevel = 60, maxSkillLevel = 150 } end
  TS.GetProfessionInfoByRecipeID = function(rid)
    if rid == 2963 or rid == 2389 then return { professionID = 197, professionName = "Tailoring" } end
    return { professionID = 0 }
  end
  TS.IsRecipeInSkillLine = function(_, lineID) return lineID == 197 end
  fire("TRADE_SKILL_SHOW")
  for k in pairs(DB.recipes) do assert(not k:find("^Cooking:"), "Forever: Tailoring recipes not stored as Cooking: " .. k) end
  assert(DB.recipes["Tailoring:2996"] and DB.debug.recipeMismatch and DB.debug.recipeMismatch.window == "Cooking"
    and DB.debug.recipeMismatch.moved == 2, "Forever: mismatch recorded in debug")
  -- while the window switches profession (DATA_SOURCE_CHANGING .. CHANGED) nothing is read
  TS.GetProfessionInfoByRecipeID = nil
  DB.recipes["Tailoring:2996"] = nil
  fire("TRADE_SKILL_DATA_SOURCE_CHANGING"); fire("TRADE_SKILL_LIST_UPDATE")
  assert(DB.recipes["Tailoring:2996"] == nil, "Forever: not read while the data source changes")
  TS.GetBaseProfessionInfo, TS.IsRecipeInSkillLine = baseInfo, nil
  fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
  assert(DB.recipes["Tailoring:2996"] and DB.recipes["Tailoring:2996"].reagents == "2589:2", "Forever: read after the data source changed")
  assert(rec.professions.Tailoring.rank == 87, "Forever: Tailoring rank kept")

  -- 5. auction house: scan, Market; no Sell/Post and no Vendor Swaps any more (1.4.0)
  fire("AUCTION_HOUSE_SHOW")
  assert(ns2.Backend() == "modern" and env.PhyzanCapitalFrame and env.PhyzanCapitalFrame:IsShown(), "Forever: window opens")
  ns2.Scanner:OnClick("LeftButton"); fire("REPLICATE_ITEM_LIST_UPDATE"); fire("REPLICATE_ITEM_LIST_UPDATE")
  local g = 0
  while ns2.Scanner.state ~= "idle" and g < 50 do g = g + 1; if ns2.Scanner.state == "reading" then ns2.Scanner:ReadChunk() end; flush() end
  assert(ns2.Scanner.lastResult and ns2.Scanner.lastResult.ok and ns2.Scanner.lastResult.rows == 3, "Forever: replicate scan")
  ns2.UI:Show("market")
  local mrow
  for _, row in ipairs(ns2.UI.panels.market.list.data) do if row.itemID == 2589 then mrow = row end end
  assert(mrow and mrow[7] == "13c", "Forever: Market 'Vendor sells for' column filled: " .. tostring(mrow and mrow[7]))
  assert(ns2.Vendor.GetReverse == nil and ns2.Vendor.GetSwaps == nil, "Forever: swap calculations removed")
  tipLines = {}
  local sb = env.PhyzanCapitalScanButton
  sb._scripts.OnEnter(sb)
  assert(table.concat(tipLines, "\n"):find("browse scan", 1, true), "Forever: scan tooltip describes the C_AuctionHouse scan")
  local function chatHas(t) for i = #chat, math.max(1, #chat - 8), -1 do if chat[i]:find(t, 1, true) then return true end end end
  -- 1.4.0: nothing can post. No sell panel, no posting code, the old commands only explain; Blizzard's sell frames untouched
  local AHF5 = env.AuctionHouseFrame
  local tainting = {}
  for _, m in ipairs({ "SetPostItem", "SetDisplayMode", "ClearPostItem" }) do
    AHF5[m] = function() tainting[#tainting + 1] = m end
  end
  AHF5.ItemSellFrame = { SetItem = function() tainting[#tainting + 1] = "ItemSellFrame:SetItem" end }
  AHF5.CommoditiesSellFrame = { SetItem = function() tainting[#tainting + 1] = "CommoditiesSellFrame:SetItem" end }
  assert(ns2.UI.panels.sell == nil and ns2.UI.panels.swaps == nil and ns2.UI.builders.sell == nil and ns2.UI.builders.swaps == nil
    and ns2.UI.frame.tabs.sell == nil and ns2.UI.frame.tabs.swaps == nil, "Forever: Sell and Vendor Swaps tabs gone")
  assert(ns2.Trade.BagItems == nil and ns2.Trade.AskPost == nil and ns2.Trade.PutInSellSlot == nil and ns2.Handoff == nil
    and ns2.ModernAH.Post == nil and ns2.ModernAH.posting == nil, "Forever: posting code gone")
  ns2.UI:Show("sell")
  assert(ns2.UI.tab ~= "sell", "Forever: Show('sell') does not open a removed tab")
  for _, cmd in ipairs({ "sell", "post", "postmode direct", "undercut 5", "durationmode 2", "swaps", "flips" }) do
    local before = #chat
    env.SlashCmdList.PHYZANCAPITAL(cmd)
    assert(#chat == before + 1 and chat[#chat]:find("was removed in 1.4.0", 1, true), "Forever: /capital " .. cmd .. " explains the removal")
  end
  assert(chatHas("sell in Blizzard's own auction house window"), "Forever: points to Blizzard's window")
  assert(#postCalls == 0, "Forever: no PostItem/PostCommodity call ever")
  -- diagnostics still kept: a blocked or forbidden action blamed on us is recorded and told in chat
  fire("ADDON_ACTION_FORBIDDEN", "PhyzanCapital", "SomethingProtected()")
  assert(DB.debug.blocked[#DB.debug.blocked].event == "ADDON_ACTION_FORBIDDEN" and chatHas("blamed on Phyzan Capital"), "Forever: forbidden recorded")
  local nChat = #chat
  fire("ADDON_ACTION_BLOCKED", "OtherAddon", "Foo()")
  assert(DB.debug.blocked[#DB.debug.blocked].fn == "Foo()" and #chat == nChat, "Forever: another add-on's block is recorded quietly")
  assert(#tainting == 0, "Forever: Blizzard's auction frame untouched: " .. table.concat(tainting, ", "))
  -- stale debug fields: version on load, scanner state at logout
  assert(DB.debug.addonVersion == ns2.VERSION, "Forever: debug.addonVersion current")
  fire("PLAYER_LOGOUT")
  assert(DB.debug.scannerState == "idle" and DB.debug.scannerStateTs, "Forever: scanner state saved at logout")

  -- 6. confirmation dialog: no SetPropagateKeyboardInput while in combat
  ns2.UI:Confirm({ which = "test", text = "Test?", onYes = function() end })
  local d = ns2.UI.confirmFrame
  local propagate = {}
  d.SetPropagateKeyboardInput = function(_, v) propagate[#propagate + 1] = v; if inCombat then protectedCalls[#protectedCalls + 1] = "SetPropagateKeyboardInput" end end
  d._scripts.OnKeyDown(d, "W")
  assert(propagate[#propagate] == true, "Forever: keys pass through out of combat")
  inCombat = true
  d._scripts.OnKeyDown(d, "W")
  d._scripts.OnKeyDown(d, "ESCAPE")
  inCombat = false
  assert(not d:IsShown(), "Forever: Escape still answers No in combat")

  -- 7. map pin: user waypoint, no protected C_SuperTrack call
  ns2.MapPin:Show({ name = "Tharynn Bouden", zone = "Elwynn Forest", uiMapID = 1429, x = 41.8, y = 67.2 })
  assert(wp and wp.uiMapID == 1429 and ns2.MapPin.current.method == "waypoint", "Forever: waypoint placed")

  -- 8. Settings tab: modern slider template, no posting settings any more; every tab builds without UI errors
  ns2.UI:Show("settings")
  assert(env.PhyzanCapitalTextSizeSlider and env.PhyzanCapitalTextSizeSlider._template == "UISliderTemplateWithLabels", "Forever: slider template")
  assert(ns2.UI.panels.settings.durMode == nil and ns2.UI.panels.settings.undercut == nil, "Forever: no posting settings")
  for _, t in ipairs(ns2.UI.TAB_ORDER) do ns2.UI:Show(t[1]) end
  ns2.UI:Show("shopping")

  -- 10. closing the add-on (X, /capital, Escape) restores Blizzard's AuctionHouseFrame; reopening adds nothing twice
  local AHF = env.AuctionHouseFrame
  local blizzCalls = {}
  for _, m in ipairs({ "SetDisplayMode", "SetParent", "ClearAllPoints", "EnableMouse" }) do
    AHF[m] = function() blizzCalls[#blizzCalls + 1] = m end
  end
  local origHide = AHF.Hide
  AHF.Hide = function(self) blizzCalls[#blizzCalls + 1] = "Hide"; return origHide(self) end
  env.PanelTemplates_SetTab = function() blizzCalls[#blizzCalls + 1] = "PanelTemplates_SetTab" end
  local function attached()
    local n, shown = 0, 0
    for _, c in ipairs(rawget(AHF, "_children") or {}) do
      if rawget(c, "_kind") then n = n + 1; if c:IsShown() then shown = shown + 1 end end
    end
    return n, shown
  end
  local F = env.PhyzanCapitalFrame
  fire("AUCTION_HOUSE_CLOSED"); flush()
  DB.settings.hideBlizzardAH, DB.settings.autoOpen = true, true
  fire("AUCTION_HOUSE_SHOW"); flush()
  local n, shown = attached()
  assert(F:IsShown() and AHF._alpha == 0 and n == 3 and shown == 0, "Forever: open - Blizzard frame invisible, our 3 buttons hidden: " .. n .. "/" .. shown)
  env.PhyzanCapitalCloseButton._scripts.OnClick(env.PhyzanCapitalCloseButton) -- X
  n, shown = attached()
  assert(not F:IsShown() and AHF._alpha == 1 and n == 3 and shown == 0, "Forever: X restores Blizzard's AH, nothing of ours on it")
  env.SlashCmdList.PHYZANCAPITAL("") -- /capital reopens
  assert(F:IsShown() and AHF._alpha == 0 and select(1, attached()) == 3, "Forever: /capital reattaches without duplicates")
  -- an open buy confirmation is cancelled when the window closes
  local bought = 0
  ns2.UI:Confirm({ which = "trade", text = "Buy out\nLinen Cloth x2\nfor 26c total (13c each)?", onYes = function() bought = bought + 1 end })
  assert(fpopup.dialog:IsShown(), "Forever: confirm open")
  env.SlashCmdList.PHYZANCAPITAL("") -- /capital closes
  assert(not F:IsShown() and not fpopup.dialog:IsShown() and bought == 0 and AHF._alpha == 1 and select(2, attached()) == 0,
    "Forever: /capital close restores and cancels the open confirmation")
  -- 'Hide Blizzard's auction window' off: our buttons only while our window is open
  DB.settings.hideBlizzardAH = false
  env.SlashCmdList.PHYZANCAPITAL("")
  n, shown = attached()
  assert(F:IsShown() and AHF._alpha == 1 and shown == 3, "Forever: buttons on the visible Blizzard frame while we are open")
  for _, name in ipairs(env.UISpecialFrames) do if name == "PhyzanCapitalFrame" then env[name]:Hide() end end -- Escape
  assert(not F:IsShown() and select(2, attached()) == 0 and AHF._alpha == 1, "Forever: Escape restores")
  DB.settings.hideBlizzardAH = true
  -- open / close / open the auction house a few times: auto-opens, never duplicates
  for _ = 1, 3 do
    fire("AUCTION_HOUSE_CLOSED"); flush()
    assert(AHF._alpha == 1 and select(2, attached()) == 0, "Forever: AH closed - restored")
    fire("AUCTION_HOUSE_SHOW"); flush()
    assert(F:IsShown() and AHF._alpha == 0, "Forever: AH reopen auto-opens the add-on")
  end
  n = attached()
  assert(n == 3, "Forever: still exactly 3 buttons on Blizzard's frame after reopening: " .. n)
  assert(#blizzCalls == 0, "Forever: Blizzard's frame was never hidden, re-parented or switched: " .. table.concat(blizzCalls, ", "))
  AHF.Hide = origHide

  -- 11. Professions tab (replaces Profitable Crafts): known recipes per profession with reagent costs
  local PT = ns2.ProfTab
  local ahKey = ns2.Ledger:LatestAHKey()
  local cur = ns2.AH(ahKey).current
  cur[2996] = { minUnit = 900, n = 1, qty = 5 }   -- Bolt of Linen Cloth sells for 9s
  cur[2572] = { minUnit = 2000, n = 1, qty = 1 }  -- Red Linen Robe sells for 20s
  cur[2320] = { minUnit = 50, n = 1, qty = 10 }   -- Coarse Thread on the AH for 50c (vendor: 10c -> vendor wins)
  cur[2604] = { minUnit = 30, n = 1, qty = 1 }    -- Red Dye on the AH for 30c (vendor: 50c -> AH wins)
  env.SlashCmdList.PHYZANCAPITAL("professions")
  assert(ns2.UI.tab == "crafts" and F:IsShown(), "Forever: /capital professions opens the tab")
  local tabLabel
  for _, t in ipairs(ns2.UI.TAB_ORDER) do if t[1] == "crafts" then tabLabel = t[2] end end
  assert(tabLabel == "Professions", "Forever: tab is called Professions")
  local pp = ns2.UI.panels.crafts
  local rows, book = PT:Rows(ahKey)
  local byName = {}
  for _, e in ipairs(book) do byName[e.name] = e end
  assert(byName.Tailoring and byName.Tailoring.source == "recorded" and #byName.Tailoring.recipes == 2, "Forever: Tailoring = the 2 recorded recipes")
  assert(byName.Cooking and byName.Cooking.source == "bundled" and #byName.Cooking.recipes > 0, "Forever: Cooking falls back to bundled recipes")
  for _, r in ipairs(byName.Cooking.recipes) do assert(r.status == "probably known", "Forever: bundled = probably known") end
  assert(byName.Skinning.gathering and byName.Fishing.gathering, "Forever: gathering skills noted")
  local info = pp.info:GetText()
  assert(info:find("probably known - open your profession window to confirm", 1, true), "Forever: probably-known note")
  assert(info:find("Skinning 75", 1, true) and info:find("Fishing 1", 1, true) and info:find("gathering", 1, true), "Forever: gathering note: " .. info)
  assert(info:find("missing price", 1, true), "Forever: missing prices are reported")
  -- profitable first + highlighted; names, never IDs
  local robeRow, boltRow
  for i, row in ipairs(rows) do
    if row.data.id == 2572 then robeRow = i end
    if row.data.id == 2996 then boltRow = i end
    assert(not row[1]:find("Item #", 1, true) and not row[1]:match("^%d+$") and not row[1]:find("item:", 1, true), "Forever: name, not ID: " .. row[1])
  end
  local robe, bolt = rows[robeRow].data, rows[boltRow].data
  assert(bolt.profit and bolt.profit > 0 and robe.profit and robe.profit < 0, "Forever: bolt profitable, robe loses money")
  assert(rows[1].data.id == 2996 and rows[1].tint and boltRow < robeRow, "Forever: profitable first and highlighted")
  local seenUnprofitable = false
  for _, row in ipairs(rows) do
    local good = row.data.profit and row.data.profit > 0
    if not good then seenUnprofitable = true end
    assert(not (good and seenUnprofitable), "Forever: no profitable recipe after an unprofitable one")
    assert((row.tint ~= nil) == (good and true or false), "Forever: highlight only profitable")
  end
  -- robe reagents: 3 bolts (AH 9s), 2 thread (vendor 10c < AH 50c), 2 dye (AH 30c < vendor 50c); value 20s after 5% cut
  local rg = {}
  for _, x in ipairs(robe.reagents) do rg[x.id] = x end
  assert(rg[2996].unit == 900 and rg[2996].where == "AH" and rg[2996].qty == 3, "Forever: bolt from the AH")
  assert(rg[2320].unit == 10 and rg[2320].where == "vendor" and rg[2320].ahUnit == 50, "Forever: thread from the vendor (cheaper)")
  assert(rg[2604].unit == 30 and rg[2604].where == "AH" and rg[2604].vendorUnit == 50, "Forever: dye from the AH (cheaper)")
  assert(robe.cost == 2780 and math.abs(robe.revenue - 1900) < 0.01 and math.abs(robe.profit + 880) < 0.01,
    "Forever: robe cost 27s 80c, value 19s after the cut, profit -8s 80c")
  assert(rows[robeRow][6]:find("-8s 80c", 1, true) and rows[boltRow][6]:find("+", 1, true), "Forever: profit cells")
  -- detail + reagent list for the clicked recipe
  pp.list.onSelect(robeRow, rows[robeRow])
  assert(PT.current and PT.current.id == 2572, "Forever: recipe selected")
  assert(pp.detail:GetText():find("Red Linen Robe (Tailoring)", 1, true) and pp.detail:GetText():find("after the 5% cut", 1, true), "Forever: detail text")
  local rrows = pp.reagents.data
  assert(#rrows == 3, "Forever: 3 reagent rows")
  local threadRow
  for i, r in ipairs(rrows) do
    if r.itemID == 2320 then threadRow = i; assert(r[2] == "2" and r[4] == "vendor", "Forever: thread row qty + source") end
    if r.itemID == 2604 then assert(r[4] == "AH (scan)", "Forever: dye row source") end
  end
  -- click a reagent -> "Add ... to crafting list?" Yes/No with the recipe quantity
  fpopup = nil
  pp.reagents.onSelect(threadRow, rrows[threadRow])
  assert(fpopup and fpopup.text:find("to crafting list?", 1, true) and fpopup.text:find("Coarse Thread", 1, true)
    and fpopup.text:find("(2 per craft)", 1, true) and fpopup.opts.edit.default == 2, "Forever: reagent -> crafting list popup: " .. tostring(fpopup and fpopup.text))
  assert(ns2.Shop:List()[2320] == nil, "Forever: nothing added before Yes")
  fpopup.dialog.yes._scripts.OnClick(fpopup.dialog.yes)
  assert(ns2.Shop:List()[2320] and ns2.Shop:List()[2320].qty == 2, "Forever: reagent added to the crafting list")
  ns2.Shop:List()[2320] = nil
  -- re-sorting after prices change: robe becomes profitable when it sells for 40s
  cur[2572].minUnit = 4000
  ns2.UI:Refresh()
  rows = PT:Rows(ahKey)
  assert(rows[1].data.id == 2572 and rows[1].tint, "Forever: most profitable first")
  -- 1.3.1: "Available on AH" = total quantity listed in the latest scan (recipe list + reagents + detail)
  local function rowFor(list, id) for _, r in ipairs(list) do if (r.data and (r.data.id or r.itemID) == id) or r.itemID == id then return r end end end
  rows = PT:Rows(ahKey)
  assert(pp.list.cols[8][1] == "Available on AH" and rowFor(rows, 2996)[8] == "5" and rowFor(rows, 2572)[8] == "1",
    "Professions: Available column (units listed)")
  pp.list.onSelect(1, rows[1]) -- robe
  local rr = pp.reagents.data
  assert(pp.reagents.cols[8][1] == "Available on AH" and rowFor(rr, 2996)[8] == "5" and rowFor(rr, 2320)[8] == "10"
    and rowFor(rr, 2604)[8] == "1", "Professions: Available per reagent")
  assert(pp.detail:GetText():find("Available on AH: 1.", 1, true), "Professions: Available in the detail: " .. pp.detail:GetText())
  assert(pp.info:GetText():find("Available on AH = total quantity listed in that scan", 1, true), "Professions: header explains Available")
  local dye = cur[2604]
  cur[2604] = nil -- scanned, nothing listed
  ns2.UI:Refresh()
  assert(rowFor(pp.reagents.data, 2604)[8] == "0", "Professions: scanned but not listed = 0")
  cur[2604] = dye
  cur[2996].n = 2
  PT.selected = "Tailoring:2996"; ns2.UI:Refresh()
  assert(pp.detail:GetText():find("Available on AH: 5 in 2 listings.", 1, true), "Professions: listings in the detail")
  cur[2996].n = 1
  assert(PT.Available("Nowhere-Realm", 2996) == nil and PT.AvailText(nil) == "no scan", "Professions: no scan of that AH")
  for _, r in ipairs(rows) do assert(not r[8]:match("^%d%d%d%d%d+$") or r[8] == ns2.IntStr(PT.Available(ahKey, r.data.id)), "no IDs") end
  -- a newer scan that did not finish is mentioned (not used)
  table.insert(DB.scans, { id = 999, ts = time(), complete = false, ahKey = ahKey, rows = 1 })
  ns2.UI:Refresh()
  assert(pp.info:GetText():find("did not finish and is not used", 1, true), "Professions: unfinished newer scan noted")
  table.remove(DB.scans)
  -- sort by Available (click the header: highest first, again: lowest first); other columns sort too
  pp.list.header[8]._scripts.OnClick(pp.list.header[8])
  local d = pp.list.data
  for i = 2, #d do assert(d[i - 1].sort[8] >= d[i].sort[8], "Professions: sorted by Available, highest first") end
  assert(pp.list.header[8].label._text:find(" v", 1, true), "Professions: sort arrow")
  pp.list.header[8]._scripts.OnClick(pp.list.header[8])
  for i = 2, #pp.list.data do assert(pp.list.data[i - 1].sort[8] <= pp.list.data[i].sort[8], "Professions: lowest first") end
  ns2.UI:Refresh()
  for i = 2, #pp.list.data do assert(pp.list.data[i - 1].sort[8] <= pp.list.data[i].sort[8], "Professions: sort kept on refresh") end
  pp.reagents.header[8]._scripts.OnClick(pp.reagents.header[8])
  assert(pp.reagents.data[1][8] == "5" or pp.reagents.data[1].sort[8] >= pp.reagents.data[#pp.reagents.data].sort[8], "Professions: reagents sortable")
  pp.list.sortCol, pp.reagents.sortCol, PT.selected = nil, nil, nil
  ns2.UI:Refresh()
  -- old scan: the age is shown
  local last = ns2.UI.LastScan(ahKey)
  local ts = last.ts
  last.ts = time() - 3 * 86400
  ns2.UI:Refresh()
  assert(pp.info:GetText():find("3 days old", 1, true), "Forever: scan age shown when prices are old")
  last.ts = ts
  ns2.UI:Refresh()
  assert(pp.info:GetText():find("scanned", 1, true), "Forever: fresh scan time shown")
  -- filter by profession; learnable recipes only on request
  PT.filter = "Cooking"; ns2.UI:Refresh()
  for _, row in ipairs(pp.list.data) do assert(row[2] == "Cooking", "Forever: profession filter") end
  PT.filter = nil
  pp.learn:SetChecked(true); pp.learn._scripts.OnClick(pp.learn); assert(PT.showLearnable)
  pp.learn:SetChecked(false); pp.learn._scripts.OnClick(pp.learn); assert(not PT.showLearnable)
  ns2.UI:Refresh()

  -- 9. /capital debug records the modern API set
  env.SlashCmdList.PHYZANCAPITAL("debug")
  local dbg = DB.debug
  assert(dbg.backend == "modern" and dbg.C_MerchantFrame and dbg.C_TradeSkillUI and dbg.C_ItemGetItemInfo and not dbg.GetItemInfo
    and not dbg.GetMerchantItemInfo and dbg.projectID == 18, "Forever: debug flags")
  fire("AUCTION_HOUSE_CLOSED")

  assert(#protectedCalls == 0, "Forever: protected calls made: " .. table.concat(protectedCalls, ", "))
  for ci, m in ipairs(chat) do
    local low = m:lower()
    assert(not low:find("error", 1, true) and not low:find("not available", 1, true), "Forever: chat reported a problem: " .. m)
  end
  local probed = {}
  for k in pairs(legacyProbed) do probed[#probed + 1] = k end
  table.sort(probed)
  print("Forever: classic globals only probed as guarded fallbacks: " .. (#probed > 0 and table.concat(probed, ", ") or "none"))
  -- 12. offline price lookup (1.2.7): /capital anywhere, search saved prices, /capital price, buttons off, /reload
  local LK = ns2.Lookup
  local lkKey = ns2.Ledger:LatestAHKey()
  local A = ns2.AH(lkKey)
  assert(A.lastKnown[2589] and A.lastKnown[2589].u and A.lastKnown[2589].u > 0 and A.lastKnown[2589].t, "Lookup: scan recorded a last known price")
  local linenUnit = A.lastKnown[2589].u
  -- a later scan without Linen Cloth keeps its last known price; history gets one entry per market day
  local now = time()
  local function aggScan(ts, list)
    local rows = {}
    for _, r in ipairs(list) do rows[#rows + 1] = { itemID = r[1], name = ITEMS[r[1]][1], quality = 1, count = r[3] or 1,
      minBid = r[2], buyout = r[2] * (r[3] or 1), unit = r[2], tl = 3, seller = "", bid = 0 } end
    return ns2.Ledger:IngestScan("browse", ts, rows, true, 0, lkKey, true)
  end
  aggScan(now - 2 * 86400, { { 2321, 45 } })
  aggScan(now - 86400, { { 2321, 40 } })
  aggScan(now, { { 2321, 35 }, { 2320, 9 } })
  assert(A.current[2589] == nil and A.lastKnown[2589].u == linenUnit, "Lookup: item missing from the newest scan keeps its last known price")
  local h2321 = ns2.Ledger.DecodeHistory(A.history[2321])
  assert(#h2321 == 3 and h2321[3].low == 35 and h2321[2].low == 40 and h2321[1].low == 45, "Lookup: one history entry per market day")
  -- away from the AH: /capital opens, on the Price Lookup page
  fire("AUCTION_HOUSE_CLOSED"); flush()
  assert(not ns2.ahOpen)
  if F:IsShown() then F:Hide() end
  ns2.UI.tab = "search"
  env.SlashCmdList.PHYZANCAPITAL("")
  assert(F:IsShown() and ns2.UI.tab == "prices", "Lookup: /capital away from the AH opens the price lookup")
  env.SlashCmdList.PHYZANCAPITAL("search")
  assert(ns2.UI.tab == "prices" and ns2.UI.panels.prices:IsShown(), "Lookup: /capital search away from the AH = price lookup")
  local lp = ns2.UI.panels.prices
  assert(lp.status:GetText():find("Buying requires being at the auction house", 1, true), "Lookup: offline note")
  -- typing a partial name, any case
  lp.q:SetText("LINEN c"); lp.q._scripts.OnEnterPressed(lp.q)
  local lrows = lp.list.data
  assert(#lrows >= 2 and lrows[1].itemID == 2589, "Lookup: Linen Cloth first for 'LINEN c'")
  local names = {}
  for _, r in ipairs(lrows) do
    names[r[1]] = true
    assert(not r[1]:match("^%d+$") and not r[1]:find("Item #", 1, true), "Lookup: names, not IDs")
  end
  assert(names["Bolt of Linen Cloth"], "Lookup: partial match finds Bolt of Linen Cloth")
  -- 1.4.0: clicking a result selects it and asks "Add <item> to crafting list?" (works away from the AH too)
  local function plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local boltRow
  for i, r in ipairs(lrows) do if r[1] == "Bolt of Linen Cloth" then boltRow = i end end
  fpopup = nil
  lp.list.onSelect(boltRow, lrows[boltRow])
  assert(LK.selected == 2996 and fpopup and plain(fpopup.text):find("Add Bolt of Linen Cloth to crafting list?", 1, true)
    and fpopup.dialog.yes:IsShown() and fpopup.dialog.no:IsShown(), "Lookup: click asks to add: " .. tostring(fpopup and fpopup.text))
  assert(ns2.Shop:List()[2996] == nil, "Lookup: nothing added before Yes")
  fpopup.dialog.edit:SetText("3"); fpopup.dialog.yes._scripts.OnClick(fpopup.dialog.yes)
  assert(ns2.Shop:List()[2996] and ns2.Shop:List()[2996].qty == 3 and not fpopup.dialog:IsShown(), "Lookup: Yes adds to the crafting list")
  assert(chat[#chat]:find("Crafting list: added Bolt of Linen Cloth x3", 1, true), "Lookup: chat says Crafting list: " .. chat[#chat])
  lp.list.onSelect(boltRow, lrows[boltRow])
  assert(plain(fpopup.text):find("Bolt of Linen Cloth is already on your crafting list", 1, true) and fpopup.opts.edit.label == "Add:",
    "Lookup: already listed -> offers more, no second entry")
  fpopup.dialog.no._scripts.OnClick(fpopup.dialog.no)
  assert(ns2.Shop:List()[2996].qty == 3, "Lookup: No changes nothing")
  ns2.Shop:Remove(2996, "test")
  lp.list.onSelect(1, lrows[1]) -- back to Linen Cloth for the checks below
  fpopup.dialog.no._scripts.OnClick(fpopup.dialog.no)
  assert(lrows[1][2] == ns2.Money(linenUnit), "Lookup: last known lowest per unit")
  assert(lp.head:GetText():find("Last known price (scanned", 1, true) and lp.head:GetText():find("ago)", 1, true), "Lookup: headline: " .. lp.head:GetText())
  local det = lp.detail:GetText()
  assert(det:find("Lowest buyout: " .. ns2.Money(linenUnit) .. " each", 1, true), "Lookup: lowest buyout")
  assert(det:find("market day", 1, true) and det:find("7:00 AM - 6:59 AM next day", 1, true), "Lookup: market day: " .. det)
  assert(det:find("buys it from you for 13c", 1, true), "Lookup: vendor sell price")
  for _, t in ipairs({ lp.detail:GetText(), lp.hist:GetText(), lp.head:GetText() }) do
    assert(not t:lower():find("listing", 1, true) and not t:lower():find("quantity", 1, true) and not t:lower():find("listed", 1, true),
      "Lookup: no volume shown: " .. t)
  end
  for _, col in ipairs(lp.list.cols) do assert(not col[1]:lower():find("quantity") and not col[1]:lower():find("listing"), "Lookup: no volume column") end
  -- an item known only from the bundled names (no scan data) is found too
  LK:Run("stringy wolf")
  assert(lp.list.data[1] and lp.list.data[1][1] == "Stringy Wolf Meat" and lp.list.data[1][2]:find("no scan price", 1, true), "Lookup: bundled names")
  assert(lp.head:GetText():find("No auction house price saved yet", 1, true), "Lookup: no price message")
  -- price history and typical price
  LK:Run("fine thread")
  assert(lp.hist:GetText():find("Price history", 1, true) and lp.hist:GetText():find("35c", 1, true) and lp.hist:GetText():find("40c", 1, true),
    "Lookup: history: " .. lp.hist:GetText())
  assert(lp.detail:GetText():find("Typical price: ", 1, true), "Lookup: typical price line")
  -- the buy button is disabled away from the AH, with the message instead of an error; no Sell / Post button any more
  assert(lp.buy.pcDisabled and lp.sell == nil and lp.btnNote:GetText():find("requires being at the auction house", 1, true), "Lookup: buttons off")
  local browseCalls = 0
  env.C_AuctionHouse.SendBrowseQuery = function() browseCalls = browseCalls + 1 end
  local nChat = #chat
  lp.buy._scripts.OnClick(lp.buy)
  assert(browseCalls == 0 and #postCalls == 0 and chat[#chat]:find("requires being at the auction house", 1, true) and #chat == nChat + 1,
    "Lookup: offline buy only explains")
  env.SlashCmdList.PHYZANCAPITAL("buy")
  assert(F.closedMsg:IsShown() and F.closedMsg:GetText():find("Buying requires being at the auction house", 1, true), "Lookup: Buy tab offline")
  -- /capital price <name>
  env.SlashCmdList.PHYZANCAPITAL("price linen cloth")
  local function chatFind(t, from) for i = from or 1, #chat do if chat[i]:find(t, 1, true) then return i end end end
  local ci = chatFind("Linen Cloth|r: last known price " .. ns2.Money(linenUnit) .. " each", nChat)
  assert(ci and chat[ci]:find("scanned", 1, true) and chat[ci]:find("market day", 1, true), "Lookup: /capital price line")
  assert(chatFind("vendor buys it for 13c", ci) and chatFind("requires being at the auction house", ci), "Lookup: /capital price details")
  env.SlashCmdList.PHYZANCAPITAL("price FINE thr")
  assert(chatFind("Fine Thread|r: last known price 35c each", ci), "Lookup: /capital price partial, any case")
  env.SlashCmdList.PHYZANCAPITAL("price zzzqqq")
  assert(chat[#chat]:find("no item called 'zzzqqq'", 1, true), "Lookup: unknown item")
  -- the AH opening again leaves the data alone; closing does not wipe it
  fire("AUCTION_HOUSE_SHOW"); flush(); fire("AUCTION_HOUSE_CLOSED"); flush()
  assert(A.lastKnown[2589].u == linenUnit and A.history[2321], "Lookup: AH close keeps the data")

  -- /reload (or logout + login): SavedVariables written to text and read back into a fresh copy of the add-on
  local function serialize(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    assert(t == "table", "SavedVariables can only hold plain data, found " .. t)
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(x) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  -- 1.4.1: live class data is cached in db.items; the client's AuctionCategories is saved as plain data when the AH
  -- UI is there (functions / mixins dropped, the WoW Token category skipped)
  local realGIIx = env.C_Item.GetItemInfoInstant
  env.C_Item.GetItemInfoInstant = function(id) if id == 2589 then return id, "Trade Goods", "Cloth", "", 1000 + id, 7, 5 end; return realGIIx(id) end
  DB.items[2589].classID = nil
  assert(select(4, ns2.Categories:Classify(2589)) == "live" and DB.items[2589].classID == 7 and DB.items[2589].subClassID == 5, "Forever: live class cached")
  env.C_Item.GetItemInfoInstant = realGIIx
  local mixin = { CreateSubCategory = function() end }
  local function cat(name, filters, subs, flags) return setmetatable({ name = name, filters = filters, subCategories = subs, flags = flags }, { __index = mixin }) end
  env.AuctionCategories = {
    cat("Weapons", { { classID = 2 } }, { cat("Daggers", { { classID = 2, subClassID = 15 } }) }),
    cat("Armor", { { classID = 4 } }),
    cat("Containers", { { classID = 1 } }),
    cat("Consumables", { { classID = 0 } }),
    cat("Trade Goods", { { classID = 7, subClassID = 5 }, { classID = 7 } }, { cat("Cloth", { { classID = 7, subClassID = 5 } }) }),
    cat("WoW Token", {}, nil, { WOW_TOKEN_FLAG = true }),
  }
  fire("AUCTION_HOUSE_SHOW"); flush()
  if ns2.UI.confirmOpts then ns2.UI:ConfirmAnswer(false) end
  local ctree = DB.categoryTree
  assert(ctree and #ctree.tree.sub == 5 and ctree.tree.sub[5].name == "Trade Goods" and ctree.tree.sub[5].sub[1].name == "Cloth", "Forever: client categories saved")
  assert(ns2.Categories:Root().source == "client" and DB.debug.categoryDiff > 0, "Forever: client tree in use, differences noted")
  DB.settings.marketCategory, DB.settings.marketOpen = "Trade Goods/Cloth", true
  fire("AUCTION_HOUSE_CLOSED")
  env.AuctionCategories = nil
  local svText = "return " .. serialize(env.PhyzanCapitalDB)
  print(string.format("Lookup: SavedVariables size after these scans: %d bytes", #svText))
  env.PhyzanCapitalDB = assert(loadstring(svText))()
  registry = {} -- the old copy's frames get no more events
  for k in pairs(env) do if type(k) == "string" and k:find("^PhyzanCapital") and k ~= "PhyzanCapitalDB" then env[k] = nil end end
  env.SlashCmdList.PHYZANCAPITAL = nil
  local ns3 = {}
  for line in io.lines("PhyzanCapital.toc") do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^##") then
      local chunk = assert(loadfile((line:gsub("\\", "/"))))
      setfenv(chunk, env)
      chunk("PhyzanCapital", ns3)
    end
  end
  fire("ADDON_LOADED", "PhyzanCapital"); fire("PLAYER_LOGIN"); flush()
  local A3 = ns3.AH(lkKey)
  assert(A3.lastKnown[2589].u == linenUnit and #ns3.Ledger.DecodeHistory(A3.history[2321]) == 3, "Lookup: data survives /reload")
  env.SlashCmdList.PHYZANCAPITAL("")
  assert(env.PhyzanCapitalFrame:IsShown() and ns3.UI.tab == "prices", "Lookup: after /reload /capital opens the lookup away from the AH")
  ns3.Lookup:Run("linen cloth")
  assert(ns3.UI.panels.prices.list.data[1].itemID == 2589 and ns3.UI.panels.prices.list.data[1][2] == ns3.Money(linenUnit), "Lookup: search after /reload")
  local before3 = #chat
  env.SlashCmdList.PHYZANCAPITAL("price linen cloth")
  assert(chatFind("last known price " .. ns3.Money(linenUnit), before3 + 1), "Lookup: /capital price after /reload")
  -- 1.4.1 after /reload, away from the AH: cached classes, the saved client tree and the selected category are back
  assert(select(4, ns3.Categories:Classify(2589)) == "cache", "Forever: class from SavedVariables after /reload")
  assert(ns3.Categories:Root().source == "client" and ns3.Categories:Find("Trade Goods/Cloth"), "Forever: saved client tree after /reload")
  ns3.UI:Show("market")
  local mp = ns3.UI.panels.market
  assert(mp:IsShown() and env.PhyzanCapitalDB.settings.marketCategory == "Trade Goods/Cloth" and #mp.list.data >= 1, "Forever: market tab with the saved category")
  for _, r in ipairs(mp.list.data) do local c5, s5 = ns3.Categories:Classify(r.itemID); assert(c5 == 7 and s5 == 5, "Forever: only cloth listed") end
  local seen
  for _, r in ipairs(mp.tree.data) do if r.path == "Trade Goods/Cloth" then seen = true end end
  assert(seen and mp.tree.data[1].path == "", "Forever: tree after /reload")
  ns3.UI.frame:Hide()
  env.PhyzanCapitalDB.categoryTree = nil
  -- data from an older version (no lastKnown/history yet) is filled in once from current prices + daily stats
  local old = assert(loadstring(svText))()
  for _, ah in pairs(old.ah) do ah.lastKnown, ah.history, ah.lookupSeeded = nil, nil, nil end
  old.schemaVersion = 5
  old.recipes["Fishing:2996"] = { prof = "Fishing", product = 2996, name = "Bolt of Linen Cloth", reagents = "2589:2" }
  old.recipes["Tailoring:2996"] = { prof = "Tailoring", product = 2996, name = "Bolt of Linen Cloth", reagents = "2589:2" }
  env.PhyzanCapitalDB = old
  ns3.InitDB(); ns3.Ledger:SeedLookup()
  assert(old.recipes["Fishing:2996"] == nil and old.recipes["Tailoring:2996"] and old.debug.recipesDropped.n >= 1,
    "1.3.0 migration: recipes under Fishing dropped, Tailoring kept")
  assert(old.schemaVersion == 8 and ns3.AH(lkKey).lastKnown[2321] and ns3.AH(lkKey).lastKnown[2321].u == 35, "Lookup: seeded from 1.2.6 data")
  print("offline price lookup tests ok")

  -- 1.4.2 public release: a first run with empty SavedVariables for any character, faction, level, professions and
  -- client language works (nothing about the author's character is built in)
  local saved = { UnitName = env.UnitName, GetRealmName = env.GetRealmName, UnitFactionGroup = env.UnitFactionGroup, UnitLevel = env.UnitLevel,
    GetProfessions = env.GetProfessions, GetProfessionInfo = env.GetProfessionInfo, GetLocale = env.GetLocale, GetRealZoneText = env.GetRealZoneText, C_Map = env.C_Map, C_Spell = env.C_Spell }
  local CASES = {
    { name = "Grukk", realm = "Some Realm", faction = "Horde", level = 60, locale = "deDE", zone = "Orgrimmar", map = 1454, profs = {} },
    { name = "Élodie", realm = "Royaume", faction = "Alliance", level = 1, locale = "frFR", zone = "Tanaris", map = 1446, sub = true,
      profs = { { "Couture", 5, 75, 197 }, { "Dépeçage", 1, 75, 393 } } },
    { name = "Neu", realm = "Realm", faction = "Horde", level = 33, locale = "enUS", zone = "Elwynn Forest", map = 1429, profs = { { "Mining", 120, 150, 186 } } },
  }
  for ci, c in ipairs(CASES) do
    env.PhyzanCapitalDB = nil
    env.UnitName = function(u) if u == "npc" then return nil end return c.name end
    env.GetRealmName = function() return c.realm end
    env.UnitFactionGroup = function() return c.faction, c.faction end
    env.UnitLevel = function() return c.level end
    env.GetLocale = function() return c.locale end
    env.GetRealZoneText = function() return c.locale == "enUS" and c.zone or ("Zone " .. ci) end -- localized: no English names
    env.C_Spell = { GetSpellName = function() return nil end }
    env.GetProfessions = function() local t = {}; for i = 1, #c.profs do t[i] = i end; return t[1], t[2], nil, nil, nil end
    env.GetProfessionInfo = function(i) local pp = c.profs[i]; return pp[1], 136000 + i, pp[2], pp[3], 2, 0, pp[4] end
    local base = saved.C_Map
    env.C_Map = setmetatable({ GetBestMapForUnit = function() return c.sub and 99001 or c.map end,
      GetMapInfo = function(id) if id == 99001 then return { mapType = 5, parentMapID = c.map } end; return { mapType = 3, parentMapID = 1414 } end },
      { __index = base })
    registry = {}
    for k in pairs(env) do if type(k) == "string" and k:find("^PhyzanCapital") and k ~= "PhyzanCapitalDB" then env[k] = nil end end
    env.SlashCmdList.PHYZANCAPITAL = nil
    local ns4 = {}
    for line in io.lines("PhyzanCapital.toc") do
      line = line:gsub("\r", "")
      if line ~= "" and not line:match("^##") then
        local chunk = assert(loadfile((line:gsub("\\", "/"))))
        setfenv(chunk, env)
        chunk("PhyzanCapital", ns4)
      end
    end
    local ctx = "fresh install " .. c.locale .. " " .. c.faction .. " " .. c.level
    local chat0 = #chat
    fire("ADDON_LOADED", "PhyzanCapital"); fire("PLAYER_LOGIN"); flush()
    local D = env.PhyzanCapitalDB
    assert(D and D.schemaVersion == 8 and D.addonVersion == "1.4.2", ctx .. ": SavedVariables created")
    assert(D.settings.textScale == 1.0 and ns4.UI.scale == 1.0 and D.settings.showCommands == true and D.settings.autoOpen == true, ctx .. ": public defaults (text 1x)")
    local key = c.name .. "-" .. c.realm
    local rec = D.chars[key]
    assert(rec and rec.level == c.level and ns4.CharKey() == key, ctx .. ": character detected")
    local np = 0; for _ in pairs(rec.professions or {}) do np = np + 1 end
    assert(np == #c.profs, ctx .. ": professions by skill line (" .. np .. ")")
    local want = c.realm .. "-" .. ((c.map == 1446) and "Neutral" or c.faction)
    assert(ns4.CurrentAHKey() == want, ctx .. ": auction house " .. ns4.CurrentAHKey() .. " (wanted " .. want .. ")")
    -- every tab opens without data, at the AH and away from it
    fire("AUCTION_HOUSE_SHOW"); flush()
    assert(env.PhyzanCapitalFrame:IsShown() and ns4.UI.tab == "search", ctx .. ": opens on Search")
    assert(ns4.UI.confirmOpts and ns4.UI.confirmOpts.which == "commands", ctx .. ": command list on the first visit")
    ns4.UI:ConfirmAnswer(true)
    assert(env.PhyzanCapitalFrame.feedback:IsShown(), ctx .. ": Feedback button")
    for _, t in ipairs({ "search", "buy", "market", "shopping", "crafts", "settings" }) do ns4.UI:Show(t); assert(ns4.UI.tab == t, ctx .. ": tab " .. t) end
    fire("AUCTION_HOUSE_CLOSED"); flush()
    for _, t in ipairs({ "prices", "market", "shopping", "crafts", "settings" }) do ns4.UI:Show(t) end
    env.SlashCmdList.PHYZANCAPITAL("feedback"); ns4.UI:ConfirmAnswer(true)
    env.SlashCmdList.PHYZANCAPITAL("status")
    env.SlashCmdList.PHYZANCAPITAL("price linen")
    for i = chat0 + 1, #chat do
      assert(not chat[i]:lower():find("error", 1, true) and not chat[i]:find("Fredrick", 1, true), ctx .. ": chat " .. chat[i])
    end
    assert(not (D.debug and D.debug.lastError), ctx .. ": no recorded errors")
    env.PhyzanCapitalFrame:Hide()
  end
  for k, v in pairs(saved) do env[k] = v end
  print("fresh install tests ok (deDE Horde 60 / frFR Alliance 1 in a neutral sub-zone / enUS Horde 33)")
  print("WoW Forever (modern-only API) tests ok")
end
print("ALL ADDON TESTS PASSED; SavedVariables written to " .. OUT)
