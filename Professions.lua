-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital professions: records recipes from open tradeskill/craft windows and computes craft profit.
local _, ns = ...
local P = {}
ns.Prof = P

local function reagString(list) -- {{id,count},...} -> "id:count;id:count"
  local parts = {}
  for i, r in ipairs(list) do parts[i] = r[1] .. ":" .. r[2] end
  return table.concat(parts, ";")
end

local function store(prof, productID, name, minMade, maxMade, reag, incomplete, difficulty)
  local key = prof .. ":" .. (productID and tostring(productID) or ("name:" .. tostring(name)))
  local rec = ns.db.recipes[key] or {}
  rec.prof, rec.product, rec.name = prof, productID, name
  rec.minMade, rec.maxMade = minMade or 1, maxMade or minMade or 1
  rec.reagents = reagString(reag)
  rec.incomplete = incomplete or nil
  rec.difficulty = difficulty
  rec.ts = time()
  local ck = ns.CharKey()
  rec.knownBy = rec.knownBy or ""
  if not (("," .. rec.knownBy .. ","):find("," .. ck .. ",", 1, true)) then
    rec.knownBy = (rec.knownBy == "") and ck or (rec.knownBy .. "," .. ck)
  end
  ns.db.recipes[key] = rec
end

-- WoW Forever / modern clients: the profession window is read through C_TradeSkillUI (the GetTradeSkill* globals
-- do not exist). Only learned recipes of your own profession window are recorded (not a linked/guild window).
local DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" } -- Enum.TradeskillRelativeDifficulty
function P.HasModernTradeSkill()
  return ns.Fn(C_TradeSkillUI, "GetAllRecipeIDs") ~= nil and ns.Fn(C_TradeSkillUI, "GetRecipeSchematic") ~= nil
end

local function tsCall(name, ...)
  local f = ns.Fn(C_TradeSkillUI, name)
  if not f then return nil end
  local r = { pcall(f, ...) }
  if not r[1] then return nil end
  return unpack(r, 2, table.maxn(r))
end

-- No craftable recipes in these skills on this client (Mining is not here: it has smelting).
P.NO_RECIPES = { Fishing = true, Herbalism = true, Skinning = true }

-- The profession a recipe belongs to, as the game reports it: canonical name, or nil when the client cannot say.
-- 1.2.9 data (Oct 17, 7:06 PM CDT): with the Fishing window reported as open, GetAllRecipeIDs still returned the
-- Tailoring list, and every Tailoring recipe was stored a second time as "Fishing:<item>".
local function recipeProfession(rid)
  local pi = tsCall("GetProfessionInfoByRecipeID", rid)
  if type(pi) ~= "table" then return nil end
  return ns.Char:Canonical(pi.parentProfessionName, pi.parentProfessionID)
    or ns.Char:Canonical(pi.professionName, pi.professionID)
end

function P:RecordTradeSkillModern()
  if P.switching then return end -- TRADE_SKILL_DATA_SOURCE_CHANGING: the recipe list still belongs to the old window
  if tsCall("IsTradeSkillReady") == false then return end
  if tsCall("IsTradeSkillLinked") or tsCall("IsTradeSkillGuild") or tsCall("IsNPCCrafting") then return end -- not yours
  local info = tsCall("GetChildProfessionInfo")
  if type(info) ~= "table" or not info.professionName or (info.skillLevel or 0) <= 0 then
    local base = tsCall("GetBaseProfessionInfo")
    if type(base) == "table" and base.professionName then info = base end
  end
  if type(info) ~= "table" or not info.professionName then return end
  local rank, maxRank = info.skillLevel, info.maxSkillLevel
  local line = info.parentProfessionID or info.professionID
  local prof = (rank and rank > 0 and ns.Char:SetSkill(info.professionName, rank, maxRank, line, "tradeskill window"))
    or ns.Char:Canonical(info.professionName, line) or info.parentProfessionName or info.professionName
  local ids = tsCall("GetAllRecipeIDs")
  if type(ids) ~= "table" then return end
  local canCheck = ns.Fn(C_TradeSkillUI, "GetProfessionInfoByRecipeID") ~= nil
  local inLine = ns.Fn(C_TradeSkillUI, "IsRecipeInSkillLine") ~= nil and type(line) == "number" and line > 0
  local moved, skipped, sample = 0, 0, nil
  for _, rid in ipairs(ids) do
    local r = tsCall("GetRecipeInfo", rid)
    -- which profession this recipe is stored under: the game's own answer per recipe, else the window's
    local rprof = prof
    if type(r) == "table" and r.learned and r.name and not r.isRecraft then
      local own = canCheck and recipeProfession(rid) or nil
      if own then
        if own ~= prof then moved = moved + 1; sample = sample or r.name end
        rprof = own
      elseif inLine and tsCall("IsRecipeInSkillLine", rid, line) == false then
        rprof = nil
      end
      if rprof and P.NO_RECIPES[rprof] then rprof = nil end
      if not rprof then skipped = skipped + 1; sample = sample or r.name end
    end
    if rprof and type(r) == "table" and r.learned and r.name and not r.isRecraft then
      local sc = tsCall("GetRecipeSchematic", rid, false)
      if type(sc) == "table" then
        local reag, incomplete = {}, false
        for _, slot in ipairs(sc.reagentSlotSchematics or {}) do
          -- basic (required) reagents only; optional / finishing reagents are not part of the cost
          local basic = (slot.reagentType == nil) or (slot.reagentType == 1) or slot.required == true
          if basic then
            local first = slot.reagents and slot.reagents[1]
            local itemID = first and first.itemID
            local cnt = slot.quantityRequired
            if itemID and cnt then reag[#reag + 1] = { itemID, cnt } elseif not (first and first.currencyID) then incomplete = true end
          end
        end
        local mn = tonumber(sc.quantityMin) or 1
        local mx = tonumber(sc.quantityMax) or mn
        store(rprof, sc.outputItemID, r.name, mn, mx, reag, incomplete, DIFFICULTY[r.relativeDifficulty])
      end
    end
  end
  if moved > 0 or skipped > 0 then
    ns.DebugSet("recipeMismatch", { ts = time(), window = prof, line = line, total = #ids, moved = moved,
      skipped = skipped, sample = sample })
  end
end

function P:RecordTradeSkill()
  if P.HasModernTradeSkill() then return self:RecordTradeSkillModern() end
  if type(GetTradeSkillLine) ~= "function" or type(GetNumTradeSkills) ~= "function" then return end
  local ok, prof, rank, maxRank = pcall(GetTradeSkillLine)
  if not ok or not prof or prof == "UNKNOWN" then return end
  -- also updates the detected skill for this character; prof becomes the canonical English name
  prof = (rank and rank > 0 and ns.Char:SetSkill(prof, rank, maxRank, nil, "tradeskill window"))
    or ns.Char:Canonical(prof) or prof
  local n = GetNumTradeSkills() or 0
  for i = 1, n do
    local ok2, name, sType = pcall(GetTradeSkillInfo, i)
    if ok2 and name and sType ~= "header" then
      local pid = ns.ItemIDFromLink(GetTradeSkillItemLink and GetTradeSkillItemLink(i))
      local mn, mx = 1, 1
      if GetTradeSkillNumMade then mn, mx = GetTradeSkillNumMade(i) end
      local reag, incomplete = {}, false
      local nr = (GetTradeSkillNumReagents and GetTradeSkillNumReagents(i)) or 0
      for j = 1, nr do
        local _, _, cnt = GetTradeSkillReagentInfo(i, j)
        local rid = ns.ItemIDFromLink(GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j))
        if rid and cnt then reag[#reag + 1] = { rid, cnt } else incomplete = true end
      end
      store(prof, pid, name, mn, mx, reag, incomplete, sType)
    end
  end
end

-- Enchanting (and other Craft-frame skills) in the vanilla client use the GetCraft* API (absent on WoW Forever,
-- where enchanting is part of the C_TradeSkillUI profession window above).
function P:RecordCraft()
  if type(GetNumCrafts) ~= "function" then return end
  local prof, rank, maxRank
  if type(GetCraftDisplaySkillLine) == "function" then
    local ok, a, b, c = pcall(GetCraftDisplaySkillLine)
    if ok then prof, rank, maxRank = a, b, c end
  end
  if not prof and type(GetCraftSkillLine) == "function" then
    local ok, a, b = pcall(GetCraftSkillLine, 1)
    if ok then prof, rank = a, b end
  end
  if not prof then return end -- e.g. hunter Beast Training
  prof = (rank and rank > 0 and ns.Char:SetSkill(prof, rank, maxRank, nil, "craft window")) or ns.Char:Canonical(prof) or prof
  for i = 1, (GetNumCrafts() or 0) do
    local ok, name, _, cType = pcall(GetCraftInfo, i)
    if ok and name and cType ~= "header" then
      local pid = ns.ItemIDFromLink(GetCraftItemLink and GetCraftItemLink(i)) -- nil for enchants (no item made)
      local reag, incomplete = {}, false
      for j = 1, ((GetCraftNumReagents and GetCraftNumReagents(i)) or 0) do
        local _, _, cnt = GetCraftReagentInfo(i, j)
        local rid = ns.ItemIDFromLink(GetCraftReagentItemLink and GetCraftReagentItemLink(i, j))
        if rid and cnt then reag[#reag + 1] = { rid, cnt } else incomplete = true end
      end
      store(prof, pid, name, 1, 1, reag, incomplete, cType)
    end
  end
end

-- Vanilla tier gates: Journeyman (to 150) needs level 10, Expert (to 225) level 20, Artisan (to 300) level 35.
local function levelOK(skillNeeded, level)
  if skillNeeded > 225 then return level >= 35 end
  if skillNeeded > 150 then return level >= 20 end
  if skillNeeded > 75 then return level >= 10 end
  return true
end

-- Candidate recipes: bundled data + recorded ones (recorded reagents win; they come from this client).
function P:Candidates()
  local byKey = {}
  for spell, d in pairs(ns.RecipeData or {}) do
    local prof, pid, mn, mx, yellow, gray, req, recipeItem, reag, name =
      d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9], d[10]
    local list = {}
    for k = 1, #reag, 2 do list[#list + 1] = { reag[k], reag[k + 1] } end
    byKey[prof .. ":" .. pid] = { prof = prof, product = pid, minMade = mn, maxMade = mx, yellow = yellow,
      gray = gray, req = req, recipeItem = recipeItem, reagents = list, name = name, spell = spell, known = false }
  end
  local me = ns.CharKey()
  for key, r in pairs(ns.db.recipes) do
    if r.product and not r.incomplete then
      local c = byKey[key] or { prof = r.prof, product = r.product }
      c.name = r.name or c.name
      c.minMade, c.maxMade = r.minMade, r.maxMade
      local list = {}
      for id, cnt in (r.reagents or ""):gmatch("(%d+):(%d+)") do list[#list + 1] = { tonumber(id), tonumber(cnt) } end
      c.reagents = list
      c.known = (("," .. (r.knownBy or "") .. ","):find("," .. me .. ",", 1, true)) and true or false
      c.recorded = true
      byKey[key] = c
    end
  end
  return byKey
end

-- Profitable crafts for the given AH at the user's professions/skills.
-- Eligible when: the recipe is known by this character, or skill >= required skill (from the recipe item),
-- or, for trainer recipes with no recorded requirement, skill >= the recipe's yellow threshold (conservative).
function P:GetProfitable(ahKey)
  local cut = ns.CutFor(ahKey)
  local level = ns.GetCharLevel()
  local out, missing = {}, 0
  for _, c in pairs(self:Candidates()) do
    local skill = ns.GetProfSkill(c.prof)
    if skill then
      local need = c.req or c.yellow or 0
      local eligible = c.known or (skill >= need and levelOK(need, level))
      if eligible then
        local value = ns.Ledger:AHPrice(ahKey, c.product)
        local cost, ok = 0, true
        for _, rg in ipairs(c.reagents or {}) do
          local ahp = ns.Ledger:AHPrice(ahKey, rg[1])
          local vp = ns.Vendor:BuyPrice(rg[1])
          local p = (ahp and vp) and math.min(ahp, vp) or ahp or vp
          if not p then ok = false; break end
          cost = cost + p * rg[2]
        end
        if not ok or not value then
          missing = missing + 1
        else
          local made = ((c.minMade or 1) + (c.maxMade or c.minMade or 1)) / 2
          local revenue = value * made * (1 - cut)
          local profit = revenue - cost
          if profit > 0 then
            out[#out + 1] = { prof = c.prof, id = c.product, name = c.name, cost = cost, revenue = revenue,
              profit = profit, need = need, needIsEstimate = (c.req == nil and not c.known),
              src = c.known and "known" or (c.recipeItem and ("recipe item " .. c.recipeItem) or "trainer?"),
              margin = cost > 0 and profit / cost or nil }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.profit > b.profit end)
  return out, missing
end

---------------------------------------------------------------------------
-- Recipe book for the Professions tab: every recipe this character knows, with per-reagent cost
---------------------------------------------------------------------------
-- Gathering skills have nothing to craft (Mining has smelting recipes, so it is listed when it has any).
P.GATHERING = { Herbalism = true, Skinning = true, Fishing = true, Mining = true }

-- Cheapest current price of one reagent: the lower of the AH price (latest scan, else today's / yesterday's median)
-- and the vendor price. Returns unit, where ("AH" | "vendor"), ahUnit, ahWhen, vendorUnit.
function P:ReagentPrice(ahKey, id)
  local ahp, when = ns.Ledger:AHPrice(ahKey, id)
  local vp = ns.Vendor:BuyPrice(id)
  if vp and (not ahp or vp <= ahp) then return vp, "vendor", ahp, when, vp end
  if ahp then return ahp, "AH", ahp, when, vp end
  return nil, nil, nil, nil, nil
end

-- One recipe priced: reagents with cost, total cost, AH value after the cut, profit (nil when a price is missing).
function P:PriceRecipe(c, ahKey)
  local cut = ns.CutFor(ahKey)
  local r = { prof = c.prof, id = c.product, name = c.name, spell = c.spell, reagents = {}, missing = {},
    made = ((c.minMade or 1) + (c.maxMade or c.minMade or 1)) / 2, minMade = c.minMade or 1, maxMade = c.maxMade or c.minMade or 1 }
  local cost = 0
  for _, rg in ipairs(c.reagents or {}) do
    local unit, where, ahp, when, vp = self:ReagentPrice(ahKey, rg[1])
    r.reagents[#r.reagents + 1] = { id = rg[1], qty = rg[2], unit = unit, where = where, ahUnit = ahp, ahWhen = when,
      vendorUnit = vp, cost = unit and unit * rg[2] or nil }
    if unit then cost = cost + unit * rg[2] else r.missing[#r.missing + 1] = rg[1] end
  end
  r.knownCost = cost
  local value, when = ns.Ledger:AHPrice(ahKey, c.product)
  r.value, r.valueWhen = value, when
  if not value then r.missing[#r.missing + 1] = c.product; r.productMissing = true end
  if value then r.revenue = value * r.made * (1 - cut) end
  if #r.missing == 0 then
    r.cost = cost
    r.profit = r.revenue - cost
    r.margin = cost > 0 and r.profit / cost or nil
  end
  return r
end

local function sortRecipes(list)
  table.sort(list, function(a, b)
    local ga = a.profit and (a.profit > 0 and 1 or 2) or 3 -- profitable, then priced, then missing prices
    local gb = b.profit and (b.profit > 0 and 1 or 2) or 3
    if ga ~= gb then return ga < gb end
    if a.profit and b.profit and a.profit ~= b.profit then return a.profit > b.profit end
    return (ns.ItemName(a.id) or "") < (ns.ItemName(b.id) or "")
  end)
end

-- { { name, skill, max, gathering, source = "recorded" | "bundled" | nil, recipes = {priced...}, learnable = {...} }, ... }
-- recorded = read from your profession window (C_TradeSkillUI); bundled = not recorded yet, so the bundled
-- trainer recipes at or below your skill ("probably known"). learnable = profitable recipes you do not know yet.
function P:RecipeBook(ahKey)
  local level = ns.GetCharLevel()
  local cands = self:Candidates()
  local book = {}
  for _, sk in ipairs(ns.Char.SKILLS) do
    local name = sk[1]
    local skill, _, max = ns.Char:Skill(name)
    if skill then
      local e = { name = name, skill = skill, max = max, recipes = {}, learnable = {} }
      local known, probable, other = {}, {}, {}
      for _, c in pairs(cands) do
        if c.prof == name and c.product then
          if c.known then known[#known + 1] = c
          else
            local need = c.req or c.yellow or 0
            -- trainer recipes: the learn level is not in the client data; recipes are usually learnable ~25 points
            -- before they turn yellow (Charred Wolf Meat: learned at 1, yellow at 45), so that is the estimate
            local learn = c.req or math.max(1, (c.yellow or 0) - 25)
            if not c.recipeItem and learn <= skill and levelOK(learn, level) then probable[#probable + 1] = c
            elseif need <= skill and levelOK(need, level) then other[#other + 1] = c end
          end
        end
      end
      local list
      if #known > 0 then
        list, e.source = known, "recorded"
        for _, c in ipairs(probable) do other[#other + 1] = c end
      elseif #probable > 0 then list, e.source = probable, "bundled" end
      for _, c in ipairs(list or {}) do
        local r = self:PriceRecipe(c, ahKey)
        r.status = (e.source == "recorded") and "known" or "probably known"
        e.recipes[#e.recipes + 1] = r
      end
      for _, c in ipairs(other) do
        local r = self:PriceRecipe(c, ahKey)
        if r.profit and r.profit > 0 then
          r.status = c.recipeItem and "learnable (recipe item)" or "learnable (trainer?)"
          r.recipeItem = c.recipeItem
          e.learnable[#e.learnable + 1] = r
        end
      end
      sortRecipes(e.recipes); sortRecipes(e.learnable)
      e.gathering = (#e.recipes == 0 and P.GATHERING[name]) and true or false
      book[#book + 1] = e
    end
  end
  return book
end

local pendingT, pendingC = false, false
local function tradeSkillChanged()
  if pendingT then return end
  pendingT = true
  ns.After(0.5, function() pendingT = false; P:RecordTradeSkill() end)
end
-- read half a second after the window opens (on WoW Forever the list can still be the previous window's at SHOW)
ns.On("TRADE_SKILL_SHOW", function()
  if P.HasModernTradeSkill() then tradeSkillChanged() else P:RecordTradeSkill() end
end)
ns.On("TRADE_SKILL_UPDATE", tradeSkillChanged)
-- modern profession window (C_TradeSkillUI): recipes arrive after TRADE_SKILL_SHOW
ns.On("TRADE_SKILL_LIST_UPDATE", tradeSkillChanged)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGING", function() P.switching = true end)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() P.switching = nil; tradeSkillChanged() end)
ns.On("TRADE_SKILL_CLOSE", function() P.switching = nil end)
ns.On("CRAFT_SHOW", function() P:RecordCraft() end)
ns.On("CRAFT_UPDATE", function()
  if pendingC then return end
  pendingC = true
  ns.After(0.5, function() pendingC = false; P:RecordCraft() end)
end)
