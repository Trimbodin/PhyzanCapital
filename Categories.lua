-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital auction categories (1.4.1): the Browse category list of WoW Forever's own auction house, used to
-- segment the Market tab. Mirrors Blizzard_AuctionHouseUI/Camelot/Blizzard_AuctionData.lua (Gethe/wow-ui-source,
-- branch "forever", 1.60.1.70450 - the file the Forever client loads) built with the same AuctionCategoryMixin rules
-- as Shared/Blizzard_AuctionData.lua: a category matches an item when any of its filters does
-- ({classID, subClassID?, inventoryType?}), and every filter added to a sub-category is added to its parents too.
-- English names come from the Forever client's GlobalStrings (AUCTION_CATEGORY_*, AUCTION_SUBCATEGORY_*, INVTYPE_*)
-- and ItemSubClass tables (wago.tools, wowf 1.60.1.70245); the live client's names are used when it has them.
-- When Blizzard's auction window has been loaded, its AuctionCategories table is read once (read only) and saved,
-- so the tree is then exactly the client's.
-- Items are classified by C_Item.GetItemInfoInstant (classID, subClassID, equip slot), cached per item in
-- PhyzanCapitalDB.items[id] (classID, subClassID, invType), else the bundled Data/ItemClasses.lua.
local _, ns = ...
local C = {}
ns.Categories = C

-- Enum values (Blizzard_APIDocumentationGenerated/ItemConstantsDocumentation.lua, forever branch)
local CLS = { Consumable = 0, Container = 1, Weapon = 2, Armor = 4, Projectile = 6, Tradegoods = 7, Recipe = 9,
  Quiver = 11, Questitem = 12, Miscellaneous = 15 }
local W = { Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5, Polearm = 6, Sword1H = 7, Sword2H = 8,
  Staff = 10, Unarmed = 13, Generic = 14, Dagger = 15, Thrown = 16, Crossbow = 18, Wand = 19, Fishingpole = 20 }
local A = { Generic = 0, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Shield = 6, Libram = 7, Idol = 8, Totem = 9 }
local INV = { Head = 1, Neck = 2, Shoulder = 3, Body = 4, Chest = 5, Waist = 6, Legs = 7, Feet = 8, Wrist = 9, Hand = 10,
  Finger = 11, Trinket = 12, Cloak = 16, Robe = 20, Holdable = 23, Relic = 28 }
local CONS = { Itemenhancement = 6, Bandage = 7, ItemenhancementTemporary = 15 }
local CONT = { Bag = 0, Soul = 1, Herb = 2, Enchanting = 3, Engineering = 4, Mining = 6, Leatherworking = 7, Tacklebox = 9,
  Cooking = 10, Reagent = 11 }
local QUIV = { Quiver = 2, Ammopouch = 3 }
local RECIPE_BOOK = 0

-- GlobalStrings (enUS, Forever)
local STR = {
  AUCTION_CATEGORY_WEAPONS = "Weapons", AUCTION_CATEGORY_ARMOR = "Armor", AUCTION_CATEGORY_CONTAINERS = "Containers",
  AUCTION_CATEGORY_CONSUMABLES = "Consumables", AUCTION_CATEGORY_TRADE_GOODS = "Trade Goods",
  AUCTION_CATEGORY_PROJECTILE = "Ammo", AUCTION_CATEGORY_RECIPES = "Recipes", AUCTION_CATEGORY_QUEST_ITEMS = "Quest Items",
  AUCTION_CATEGORY_MISCELLANEOUS = "Miscellaneous", AUCTION_SUBCATEGORY_ONE_HANDED = "One-Handed",
  AUCTION_SUBCATEGORY_TWO_HANDED = "Two-Handed", AUCTION_SUBCATEGORY_RANGED = "Ranged",
  AUCTION_SUBCATEGORY_MISCELLANEOUS = "Miscellaneous", AUCTION_SUBCATEGORY_OTHER = "Other", AUCTION_SUBCATEGORY_RELIC = "Relic",
  AUCTION_SUBCATEGORY_CLOAK = "Cloak", AUCTION_SUBCATEGORY_STANDARD_CONTAINER = "Regular Bags",
  AUCTION_SUBCATEGORY_AMMO_CONTAINER = "Ammo", AUCTION_SUBCATEGORY_REAGENT_CONTAINER = "Trade Bags",
  AUCTION_SUBCATEGORY_ITEM_ENHANCEMENT = "Item Enhancements",
}
local function S(key) local v = _G[key]; if type(v) == "string" and v ~= "" then return v end; return STR[key] end

local SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs",
  [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger", [12] = "Trinket", [16] = "Back", [20] = "Chest",
  [23] = "Held In Off-hand", [28] = "Relic" }
-- ItemSubClass names (VerboseName, else DisplayName) and the AH subclass order (DisplayFlags without 0x2, sorted by
-- AuctionHouseSortOrder, then subclass), i.e. what C_AuctionHouse.GetAuctionItemSubClasses returns on Forever
local SUB_NAME = {
  [0] = { [0] = "Explosives", [1] = "Potions", [2] = "Elixirs", [3] = "Flasks", [4] = "Scrolls", [5] = "Food & Drink", [6] = "Permanent",
    [7] = "Bandages", [8] = "Other", [13] = "Draughts", [14] = "Devices", [15] = "Temporary" },
  [1] = { [0] = "Bag", [1] = "Soul Bag", [2] = "Herb Bag", [3] = "Enchanting Bag", [4] = "Engineering Bag", [6] = "Mining Bag",
    [7] = "Leatherworking Bag", [9] = "Tackle Box", [10] = "Cooking Bag", [11] = "Reagent Bag", [12] = "Trinket Bag" },
  [2] = { [0] = "One-Handed Axes", [1] = "Two-Handed Axes", [2] = "Bows", [3] = "Guns", [4] = "One-Handed Maces", [5] = "Two-Handed Maces",
    [6] = "Polearms", [7] = "One-Handed Swords", [8] = "Two-Handed Swords", [10] = "Staves", [13] = "Fist Weapons", [14] = "Miscellaneous",
    [15] = "Daggers", [16] = "Thrown", [18] = "Crossbows", [19] = "Wands", [20] = "Fishing Pole" },
  [4] = { [0] = "Miscellaneous", [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [5] = "Cosmetic", [6] = "Shields",
    [7] = "Librams", [8] = "Idols", [9] = "Totems" },
  [6] = { [2] = "Arrow", [3] = "Bullet" },
  [7] = { [1] = "Parts", [5] = "Cloth", [6] = "Leather", [7] = "Metal & Stone", [8] = "Cooking", [9] = "Herb", [10] = "Elemental",
    [11] = "Other", [12] = "Enchanting" },
  [9] = { [0] = "Book", [1] = "Leatherworking", [2] = "Tailoring", [3] = "Engineering", [4] = "Blacksmithing", [5] = "Cooking",
    [6] = "Alchemy", [7] = "First Aid", [8] = "Enchanting" },
  [11] = { [2] = "Quiver", [3] = "Ammo Pouch" },
  [15] = { [0] = "Junk", [1] = "Reagent", [2] = "Pet", [3] = "Holiday", [4] = "Other", [5] = "Mount" },
}
local AH_SUBCLASSES = { [0] = { 0, 1, 2, 3, 4, 5, 6, 7, 13, 14, 15, 8 }, [6] = { 2, 3 }, [7] = { 1, 5, 6, 7, 8, 9, 12, 10, 11 },
  [9] = { 0, 1, 2, 3, 4, 5, 6, 7, 8 }, [15] = { 0, 1, 2, 3, 4, 5 } }
C.SUB_NAME, C.SLOT_NAME = SUB_NAME, SLOT_NAME

local function clientName(fn, ...)
  local f = ns.Fn(C_Item, fn)
  if not f then return nil end
  local ok, n = pcall(f, ...)
  if ok and type(n) == "string" and n ~= "" then return n end
end
local function subClassName(c, s) return clientName("GetItemSubClassInfo", c, s) or (SUB_NAME[c] and SUB_NAME[c][s]) end
local function slotName(inv) return clientName("GetItemInventorySlotInfo", inv) or SLOT_NAME[inv] end
local function auctionSubClasses(c)
  local f = ns.Fn(C_AuctionHouse, "GetAuctionItemSubClasses")
  if f then
    local ok, t = pcall(f, c)
    if ok and type(t) == "table" and #t > 0 then return t end
  end
  return AH_SUBCLASSES[c] or {}
end

---------------------------------------------------------------------------
-- AuctionCategoryMixin, same rules as Blizzard's
---------------------------------------------------------------------------
local Node = {}
Node.__index = Node
local function newNode(name, parent)
  return setmetatable({ name = name, parent = parent, sortIndex = 0 }, Node)
end
function Node:CreateNamedSubCategory(name)
  assert(name and #name > 0, "category without a name")
  self.sub = self.sub or {}
  local n = newNode(name, self)
  self.sub[#self.sub + 1] = n
  n.sortIndex = #self.sub
  return n
end
function Node:CreateSubCategory(classID, subClassID, inventoryType)
  local name
  if inventoryType then name = slotName(inventoryType)
  elseif classID and subClassID then name = subClassName(classID, subClassID)
  else name = clientName("GetItemClassInfo", classID) end
  return self:CreateNamedSubCategory(name or "?")
end
function Node:AddFilter(classID, subClassID, inventoryType)
  if not classID and not subClassID and not inventoryType then return end
  self.filters = self.filters or {}
  self.filters[#self.filters + 1] = { classID = classID, subClassID = subClassID, inventoryType = inventoryType }
  if self.parent then self.parent:AddFilter(classID, subClassID, inventoryType) end
end
function Node:CreateSubCategoryAndFilter(classID, subClassID, inventoryType)
  local n = self:CreateSubCategory(classID, subClassID, inventoryType)
  n:AddFilter(classID, subClassID, inventoryType)
  return n
end
function Node:CreateNamedSubCategoryAndFilter(name, classID, subClassID, inventoryType)
  local n = self:CreateNamedSubCategory(name)
  n:AddFilter(classID, subClassID, inventoryType)
  return n
end
function Node:FindSubCategoryByName(name)
  for _, n in ipairs(self.sub or {}) do if n.name == name then return n end end
end
function Node:GenerateSubCategoriesAndFiltersFromSubClass(classID)
  for _, s in ipairs(auctionSubClasses(classID)) do self:CreateSubCategoryAndFilter(classID, s) end
end
function Node:AddBulkInventoryTypeCategories(classID, subClassID, inventoryTypes) -- Camelot version: no "all" entry
  for _, inv in ipairs(inventoryTypes) do self:CreateSubCategoryAndFilter(classID, subClassID, inv) end
end

-- Blizzard_AuctionHouseUI/Camelot/Blizzard_AuctionData.lua, line by line (the WoW Token category is left out:
-- it can never hold a scanned item)
function C.BuildBundled()
  local root = newNode("All")
  local function category(name) return root:CreateNamedSubCategory(name) end

  do -- Weapons
    local weapons = category(S("AUCTION_CATEGORY_WEAPONS"))
    local one = weapons:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_ONE_HANDED"))
    for _, s in ipairs({ W.Axe1H, W.Mace1H, W.Sword1H, W.Dagger, W.Unarmed, W.Wand }) do one:CreateSubCategoryAndFilter(CLS.Weapon, s) end
    local two = weapons:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_TWO_HANDED"))
    for _, s in ipairs({ W.Axe2H, W.Mace2H, W.Sword2H, W.Polearm, W.Staff }) do two:CreateSubCategoryAndFilter(CLS.Weapon, s) end
    local ranged = weapons:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_RANGED"))
    for _, s in ipairs({ W.Bows, W.Crossbow, W.Guns, W.Thrown }) do ranged:CreateSubCategoryAndFilter(CLS.Weapon, s) end
    local misc = weapons:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_MISCELLANEOUS"))
    misc:CreateSubCategoryAndFilter(CLS.Weapon, W.Fishingpole)
    local other = misc:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_OTHER"))
    other:AddFilter(CLS.Weapon, W.Generic)
  end

  do -- Armor
    local slots = { INV.Head, INV.Shoulder, INV.Chest, INV.Waist, INV.Legs, INV.Feet, INV.Wrist, INV.Hand, INV.Relic }
    local armor = category(S("AUCTION_CATEGORY_ARMOR"))
    for _, sub in ipairs({ A.Plate, A.Mail, A.Leather, A.Cloth }) do
      local n = armor:CreateSubCategoryAndFilter(CLS.Armor, sub)
      n:AddBulkInventoryTypeCategories(CLS.Armor, sub, slots)
      local chest = n:FindSubCategoryByName(slotName(INV.Chest))
      chest:AddFilter(CLS.Armor, sub, INV.Robe)
    end
    local relic = armor:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_RELIC"))
    for _, sub in ipairs({ A.Idol, A.Libram, A.Totem }) do relic:CreateSubCategoryAndFilter(CLS.Armor, sub) end
    local misc = armor:CreateSubCategory(CLS.Armor, A.Generic)
    misc:CreateSubCategoryAndFilter(CLS.Armor, A.Generic, INV.Neck)
    misc:CreateNamedSubCategoryAndFilter(S("AUCTION_SUBCATEGORY_CLOAK"), CLS.Armor, A.Cloth, INV.Cloak)
    misc:CreateSubCategoryAndFilter(CLS.Armor, A.Generic, INV.Finger)
    misc:CreateSubCategoryAndFilter(CLS.Armor, A.Generic, INV.Trinket)
    misc:CreateSubCategoryAndFilter(CLS.Armor, A.Generic, INV.Holdable)
    misc:CreateSubCategoryAndFilter(CLS.Armor, A.Shield)
    misc:CreateSubCategoryAndFilter(CLS.Armor, A.Generic, INV.Body)
  end

  do -- Containers
    local containers = category(S("AUCTION_CATEGORY_CONTAINERS"))
    local std = containers:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_STANDARD_CONTAINER"))
    for _, s in ipairs({ CONT.Bag, CONT.Soul }) do std:CreateSubCategoryAndFilter(CLS.Container, s) end
    local ammo = containers:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_AMMO_CONTAINER"))
    for _, s in ipairs({ QUIV.Quiver, QUIV.Ammopouch }) do ammo:CreateSubCategoryAndFilter(CLS.Quiver, s) end
    local reagent = containers:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_REAGENT_CONTAINER"))
    for _, s in ipairs({ CONT.Herb, CONT.Enchanting, CONT.Engineering, CONT.Mining, CONT.Leatherworking, CONT.Tacklebox,
      CONT.Cooking, CONT.Reagent }) do reagent:CreateSubCategoryAndFilter(CLS.Container, s) end
  end

  do -- Consumables: item enhancements are grouped right after bandages
    local cons = category(S("AUCTION_CATEGORY_CONSUMABLES"))
    for _, v in ipairs(auctionSubClasses(CLS.Consumable)) do
      if not (v == CONS.Itemenhancement or v == CONS.ItemenhancementTemporary) then cons:CreateSubCategoryAndFilter(CLS.Consumable, v) end
      if v == CONS.Bandage then
        local enh = cons:CreateNamedSubCategory(S("AUCTION_SUBCATEGORY_ITEM_ENHANCEMENT"))
        enh:CreateSubCategoryAndFilter(CLS.Consumable, CONS.Itemenhancement)
        enh:CreateSubCategoryAndFilter(CLS.Consumable, CONS.ItemenhancementTemporary)
      end
    end
  end

  category(S("AUCTION_CATEGORY_TRADE_GOODS")):GenerateSubCategoriesAndFiltersFromSubClass(CLS.Tradegoods)
  category(S("AUCTION_CATEGORY_PROJECTILE")):GenerateSubCategoriesAndFiltersFromSubClass(CLS.Projectile)

  do -- Recipes: Book last
    local recipes = category(S("AUCTION_CATEGORY_RECIPES"))
    recipes:GenerateSubCategoriesAndFiltersFromSubClass(CLS.Recipe)
    local book = recipes:FindSubCategoryByName(subClassName(CLS.Recipe, RECIPE_BOOK))
    if book then book.sortIndex = 100 end
    table.sort(recipes.sub, function(a, b) return a.sortIndex < b.sortIndex end)
  end

  category(S("AUCTION_CATEGORY_QUEST_ITEMS")):AddFilter(CLS.Questitem)

  do -- Miscellaneous
    local misc = category(S("AUCTION_CATEGORY_MISCELLANEOUS"))
    misc:AddFilter(CLS.Miscellaneous)
    misc:GenerateSubCategoriesAndFiltersFromSubClass(CLS.Miscellaneous)
  end
  root.source = "bundled"
  return root
end

---------------------------------------------------------------------------
-- The client's own AuctionCategories (Blizzard_AuctionHouseUI, load-on-demand): read once, saved as plain data
---------------------------------------------------------------------------
local function plainCopy(cat, depth)
  if type(cat) ~= "table" or type(cat.name) ~= "string" or cat.name == "" or depth > 4 then return nil end
  if type(cat.flags) == "table" and cat.flags.WOW_TOKEN_FLAG then return nil end
  local out = { name = cat.name }
  if type(cat.filters) == "table" then
    out.filters = {}
    for _, f in ipairs(cat.filters) do
      if type(f) == "table" and type(f.classID) == "number" then
        out.filters[#out.filters + 1] = { classID = f.classID, subClassID = tonumber(f.subClassID), inventoryType = tonumber(f.inventoryType) }
      end
    end
  end
  if type(cat.subCategories) == "table" then
    out.sub = {}
    for _, s in ipairs(cat.subCategories) do
      local c = plainCopy(s, depth + 1)
      if c then out.sub[#out.sub + 1] = c end
    end
  end
  return out
end

function C:ReadClient()
  local cats = rawget(_G, "AuctionCategories")
  if type(cats) ~= "table" or #cats < 5 or not ns.db then return false end
  local ok, tree = pcall(function()
    local t = { name = "All", sub = {} }
    for _, cat in ipairs(cats) do local c = plainCopy(cat, 1); if c then t.sub[#t.sub + 1] = c end end
    return t
  end)
  if not ok or not tree or #tree.sub < 5 then return false end
  local _, build = nil, nil
  if type(GetBuildInfo) == "function" then _, build = GetBuildInfo() end
  ns.db.categoryTree = { ts = time(), build = build, tree = tree }
  -- note where the bundled copy differs (diagnostics; /capital debug shows it)
  local function names(n, prefix, out)
    for _, s in ipairs(n.sub or {}) do out[#out + 1] = prefix .. s.name; names(s, prefix .. s.name .. " > ", out) end
    return out
  end
  local a, b = names(tree, "", {}), names(C.BuildBundled(), "", {})
  local diff = (#a ~= #b) and 1 or 0
  for i = 1, math.max(#a, #b) do if a[i] ~= b[i] then diff = diff + 1 end end
  ns.db.debug = type(ns.db.debug) == "table" and ns.db.debug or {}
  ns.db.debug.categoryDiff = diff
  self.root = nil
  return true
end

local function adopt(t, parent)
  local n = newNode(t.name, parent)
  n.filters = t.filters
  for i, s in ipairs(t.sub or {}) do
    n.sub = n.sub or {}
    local c = adopt(s, n)
    c.sortIndex = i
    n.sub[#n.sub + 1] = c
  end
  return n
end

-- The tree in use: the client's saved one when there is one, else the bundled copy.
function C:Root()
  if self.root then return self.root end
  local saved = ns.db and ns.db.categoryTree
  if type(saved) == "table" and type(saved.tree) == "table" and type(saved.tree.sub) == "table" and #saved.tree.sub >= 5 then
    self.root = adopt(saved.tree, nil)
    self.root.source = "client"
  else
    self.root = C.BuildBundled()
  end
  -- stable paths ("Weapons/One-Handed/Daggers") for selection and expansion
  local function walk(n, path, depth)
    n.path, n.depth = path, depth
    for _, s in ipairs(n.sub or {}) do walk(s, (path == "" and "" or (path .. "/")) .. s.name, depth + 1) end
  end
  walk(self.root, "", 0)
  return self.root
end

---------------------------------------------------------------------------
-- Item classification
---------------------------------------------------------------------------
local EQUIP_LOC = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4, INVTYPE_CHEST = 5,
  INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
  INVTYPE_TRINKET = 12, INVTYPE_WEAPON = 13, INVTYPE_SHIELD = 14, INVTYPE_RANGED = 15, INVTYPE_CLOAK = 16,
  INVTYPE_2HWEAPON = 17, INVTYPE_BAG = 18, INVTYPE_TABARD = 19, INVTYPE_ROBE = 20, INVTYPE_WEAPONMAINHAND = 21,
  INVTYPE_WEAPONOFFHAND = 22, INVTYPE_HOLDABLE = 23, INVTYPE_AMMO = 24, INVTYPE_THROWN = 25, INVTYPE_RANGEDRIGHT = 26,
  INVTYPE_QUIVER = 27, INVTYPE_RELIC = 28 }
C.EQUIP_LOC = EQUIP_LOC

local bundled
local function bundledClass(id)
  if not bundled then
    bundled = {}
    for _, g in ipairs(ns.ItemClassGroups or {}) do
      local code = g[1] * 10000 + g[2] * 100 + g[3]
      local cur = 0
      for d in g[4]:gmatch("%d+") do cur = cur + tonumber(d); bundled[cur] = code end
    end
  end
  local code = bundled[id]
  if not code then return nil end
  return math.floor(code / 10000), math.floor(code / 100) % 100, code % 100
end
C.BundledClass = bundledClass

-- classID, subClassID, inventoryType of an item from the live client (nil while unknown)
local function liveClass(id)
  local f = ns.Fn(C_Item, "GetItemInfoInstant") or (type(GetItemInfoInstant) == "function" and GetItemInfoInstant) or nil
  if not f then return nil end
  local ok, iid, _, _, equipLoc, _, classID, subClassID = pcall(f, id)
  if not ok or not iid then return nil end
  classID, subClassID = ns.Plain(classID), ns.Plain(subClassID)
  if type(classID) ~= "number" or type(subClassID) ~= "number" then return nil end
  local inv
  local g = ns.Fn(C_Item, "GetItemInventoryTypeByID")
  if g then local ok2, v = pcall(g, id); if ok2 and type(ns.Plain(v)) == "number" then inv = v end end
  equipLoc = ns.Plain(equipLoc)
  if inv == nil then inv = EQUIP_LOC[equipLoc] or 0 end
  return classID, subClassID, inv, type(equipLoc) == "string" and equipLoc or nil
end

-- classID, subClassID, inventoryType, source ("cache", "live", "bundled") or nil when not known yet (then requested)
function C:Classify(id)
  id = tonumber(id)
  if not id then return nil end
  local it = ns.db and ns.db.items[id]
  if it and type(it.classID) == "number" then return it.classID, it.subClassID or 0, it.invType or 0, "cache" end
  local c, s, inv, loc = liveClass(id)
  if c then
    if ns.db then
      it = it or {}
      ns.db.items[id] = it
      it.classID, it.subClassID, it.invType, it.equipLoc = c, s, inv, loc
    end
    return c, s, inv, "live"
  end
  c, s, inv = bundledClass(id)
  if c then return c, s, inv, "bundled" end
  if ns.Items then ns.Items:Request(id) end
  return nil
end

local function matches(node, c, s, inv)
  for _, f in ipairs(node.filters or {}) do
    if f.classID == c and (f.subClassID == nil or f.subClassID == s) and (f.inventoryType == nil or f.inventoryType == inv) then return true end
  end
  return false
end
C.Matches = matches

-- Paths of every category an item belongs to (parents included). Unknown items: { "?" }; known items outside every
-- category: { "~" }.
function C:PathsFor(id)
  local c, s, inv = self:Classify(id)
  if not c then return { ["?"] = true }, false end
  local out, any = {}, false
  local function walk(n)
    for _, sub in ipairs(n.sub or {}) do
      if matches(sub, c, s, inv) then out[sub.path] = true; any = true; walk(sub) end
    end
  end
  walk(self:Root())
  if not any then out["~"] = true end
  return out, true
end

C.UNKNOWN_NAME = "Not classified yet"
C.OTHER_NAME = "Not in the auction house list"

-- counts[path] for a list of itemIDs ("" = All, "?" = unknown, "~" = outside every category); paths[id] per item
function C:Count(ids)
  local counts, paths = { [""] = 0 }, {}
  for _, id in ipairs(ids) do
    counts[""] = counts[""] + 1
    local p = self:PathsFor(id)
    paths[id] = p
    for k in pairs(p) do counts[k] = (counts[k] or 0) + 1 end
  end
  return counts, paths
end

function C:Find(path)
  if path == nil or path == "" then return self:Root() end
  local function walk(n)
    if n.path == path then return n end
    for _, s in ipairs(n.sub or {}) do local r = walk(s); if r then return r end end
  end
  return walk(self:Root())
end

-- Visible tree rows (Blizzard style: the selected category's branch is open, everything else collapsed).
-- sel = selected path, open = whether the selected category shows its children. Returns { {node|special, depth} ... }
function C:Rows(sel, open, counts)
  local root = self:Root()
  local rows = { { path = "", name = "All", depth = 0 } }
  local function onBranch(path) -- path is the selection or one of its ancestors
    return sel and sel ~= "" and (sel == path or sel:sub(1, #path + 1) == path .. "/")
  end
  local function walk(n)
    for _, s in ipairs(n.sub or {}) do
      rows[#rows + 1] = { path = s.path, name = s.name, depth = s.depth, node = s, hasSub = s.sub and #s.sub > 0 }
      local expand = onBranch(s.path) and (s.path ~= sel or open)
      if expand then walk(s) end
    end
  end
  walk(root)
  if counts and (counts["~"] or 0) > 0 then rows[#rows + 1] = { path = "~", name = C.OTHER_NAME, depth = 1, special = true } end
  if counts and (counts["?"] or 0) > 0 then rows[#rows + 1] = { path = "?", name = C.UNKNOWN_NAME, depth = 1, special = true } end
  return rows
end

-- Blizzard's window was opened: its category table exists now
ns.On("AUCTION_HOUSE_SHOW", function()
  ns.After(1, function() if C:ReadClient() and ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.UI:Refresh() end end)
end)
