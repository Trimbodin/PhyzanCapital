-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital character detection: level and professions/skill ranks, stored per character ("Name-Realm").
-- Sources, in order of preference:
--   1. GetProfessions()/GetProfessionInfo() if this client has them (later-expansion API, includes skillLineID)
--   2. The classic skills pane: GetNumSkillLines()/GetSkillLineInfo(); collapsed headers are expanded
--      temporarily and collapsed again afterwards
--   3. Open profession windows: C_TradeSkillUI.GetBaseProfessionInfo() on WoW Forever / modern clients, else
--      GetTradeSkillLine() / GetCraftDisplaySkillLine() (see Professions.lua)
-- Manual overrides (/capital setlevel, /capital setprof) are hidden and win over detection until cleared.
local _, ns = ...
local C = {}
ns.Char = C

-- Canonical (English) names with Blizzard skillLineIDs and a profession spell whose localized name usually
-- equals the localized skill name (used to map non-English clients).
C.SKILLS = {
  { "Alchemy", 171, 2259, "primary" }, { "Blacksmithing", 164, 2018, "primary" }, { "Enchanting", 333, 7411, "primary" },
  { "Engineering", 202, 4036, "primary" }, { "Leatherworking", 165, 2108, "primary" }, { "Tailoring", 197, 3908, "primary" },
  { "Herbalism", 182, nil, "primary" }, { "Mining", 186, 2575, "primary" }, { "Skinning", 393, 8613, "primary" },
  { "Cooking", 185, 2550, "secondary" }, { "First Aid", 129, 3273, "secondary" }, { "Fishing", 356, 7620, "secondary" },
}
local byLine, byName = {}, {}
for _, s in ipairs(C.SKILLS) do
  byLine[s[2]] = s[1]
  byName[s[1]:lower()] = s[1]
  byName[s[1]:lower():gsub(" ", "")] = s[1]
end
local localizedBuilt = false
local function buildLocalized()
  if localizedBuilt then return end
  localizedBuilt = true
  for _, s in ipairs(C.SKILLS) do
    if s[3] then
      local name = ns.SpellName(s[3]) -- C_Spell.GetSpellName on WoW Forever (no GetSpellInfo global)
      if type(name) == "string" and name ~= "" then byName[name:lower()] = s[1] end
    end
  end
end

-- Map a (possibly localized) skill name or skillLineID to the canonical English name, or nil.
function C:Canonical(name, skillLine)
  if skillLine and byLine[skillLine] then return byLine[skillLine] end
  if type(name) ~= "string" then return nil end
  buildLocalized()
  local l = name:lower()
  return byName[l] or byName[l:gsub(" ", "")]
end

function C:Record()
  local db = ns.db
  local key = ns.CharKey()
  local r = db.chars[key]
  if not r then r = { professions = {} }; db.chars[key] = r end
  if type(r.professions) ~= "table" then r.professions = {} end
  return r, key
end

function C:SetSkill(name, rank, maxRank, skillLine, source)
  local prof = self:Canonical(name, skillLine)
  if not prof or not rank then return nil end
  local r = self:Record()
  r.professions[prof] = { rank = rank, max = maxRank, source = source, ts = time() }
  return prof
end

function C:DetectLevel(level)
  local r = self:Record()
  local lvl = level
  if not lvl and type(UnitLevel) == "function" then
    local ok, v = pcall(UnitLevel, "player")
    if ok then lvl = v end
  end
  if type(lvl) == "number" and lvl > 0 then r.level = lvl end
end

local function fromProfessionAPI()
  if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return false end
  local ok, a, b, c, d, e, f = pcall(GetProfessions)
  if not ok then return false end
  local found = {}
  for _, idx in pairs({ a, b, c, d, e, f }) do
    if idx then
      local ok2, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx)
      if ok2 and name then
        local prof = C:SetSkill(name, rank, maxRank, skillLine, "GetProfessionInfo")
        if prof then found[prof] = true end
      end
    end
  end
  return true, found
end

C.busy = false
local function fromSkillPane()
  if type(GetNumSkillLines) ~= "function" or type(GetSkillLineInfo) ~= "function" then return false end
  C.busy = true -- expanding headers fires SKILL_LINES_CHANGED; ignore our own changes
  local expanded = {}
  local okAll = pcall(function()
    -- expand collapsed headers (back to front so indices of unvisited rows don't shift)
    if type(ExpandSkillHeader) == "function" then
      for i = GetNumSkillLines(), 1, -1 do
        local name, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and not isExpanded then
          expanded[#expanded + 1] = name
          ExpandSkillHeader(i)
        end
      end
    end
  end)
  local found = {}
  local ok = pcall(function()
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if name and not isHeader then
        local prof = C:SetSkill(name, rank, maxRank, nil, "skills pane")
        if prof then found[prof] = true end
      end
    end
  end)
  -- restore the user's collapsed headers
  if #expanded > 0 and type(CollapseSkillHeader) == "function" then
    pcall(function()
      local want = {}
      for _, n in ipairs(expanded) do want[n] = true end
      for i = GetNumSkillLines(), 1, -1 do
        local name, isHeader, isExpanded = GetSkillLineInfo(i)
        if isHeader and isExpanded and want[name] then CollapseSkillHeader(i) end
      end
    end)
  end
  C.busy = false
  return ok and okAll, found
end

-- Full refresh: level + professions. Professions that are no longer present (unlearned) are removed when a
-- complete source (profession API or skills pane) answered.
function C:Refresh(reason)
  if not ns.db then return end
  self:DetectLevel()
  local ok, found = fromProfessionAPI()
  if not ok then ok, found = fromSkillPane() end
  local r = self:Record()
  if ok and found and next(found) ~= nil then
    for prof in pairs(r.professions) do if not found[prof] then r.professions[prof] = nil end end
  end
  r.lastDetect, r.lastReason = time(), reason
  if ns.UI then ns.UI:Refresh() end
end

-- Effective values (override > detected)
function C:Level()
  local key = ns.CharKey()
  local o = ns.db.overrides[key]
  if o and o.level then return o.level, true end
  local r = ns.db.chars[key]
  if r and r.level then return r.level, false end
  local lvl = (type(UnitLevel) == "function") and UnitLevel("player") or nil
  return lvl or 60, false
end

function C:Skill(prof)
  local key = ns.CharKey()
  local o = ns.db.overrides[key]
  if o and o.professions and o.professions[prof] then return o.professions[prof], true end
  local r = ns.db.chars[key]
  local p = r and r.professions and r.professions[prof]
  if p then return p.rank, false, p.max end
  return nil
end

-- "Tailoring 150/150, Cooking 75/150" for the current character (with * for overridden values)
function C:Summary()
  local parts = {}
  for _, s in ipairs(self.SKILLS) do
    local rank, over, max = self:Skill(s[1])
    if rank then parts[#parts + 1] = s[1] .. " " .. rank .. (max and ("/" .. max) or "") .. (over and "*" or "") end
  end
  local lvl, lo = self:Level()
  return string.format("%s, level %d%s", (UnitName and UnitName("player")) or "?", lvl, lo and "*" or ""),
    (#parts > 0) and table.concat(parts, ", ") or "no professions detected"
end

function C:HasOverrides()
  local o = ns.db.overrides[ns.CharKey()]
  return o and (o.level or (o.professions and next(o.professions))) and true or false
end

function C:ClearOverrides()
  ns.db.overrides[ns.CharKey()] = nil
end

function C:SetOverride(kind, prof, value)
  local key = ns.CharKey()
  local o = ns.db.overrides[key] or { professions = {} }
  ns.db.overrides[key] = o
  if kind == "level" then o.level = value else o.professions[prof] = value end
end

local pending = false
local function soon(reason)
  if pending then return end
  pending = true
  ns.After(1, function() pending = false; C:Refresh(reason) end)
end
ns.On("PLAYER_LOGIN", function()
  if type(ns.db.pendingV1Overrides) == "table" then -- schema v1 manual skills -> overrides of the first character
    for prof, v in pairs(ns.db.pendingV1Overrides) do C:SetOverride("prof", prof, v) end
    ns.db.pendingV1Overrides = nil
  end
  C:Refresh("login")
end)
ns.On("PLAYER_ENTERING_WORLD", function() soon("entering world") end)
ns.On("PLAYER_LEVEL_UP", function(_, level) C:DetectLevel(level); if ns.UI then ns.UI:Refresh() end end)
ns.On("SKILL_LINES_CHANGED", function() if not C.busy then soon("skill lines changed") end end)
ns.On("CHAT_MSG_SKILL", function() soon("skill up") end)
ns.On("TRADE_SKILL_SHOW", function() soon("tradeskill window") end)
ns.On("TRADE_SKILL_UPDATE", function() soon("tradeskill window") end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() soon("tradeskill window") end) -- modern profession window
ns.On("CRAFT_SHOW", function() soon("craft window") end)
