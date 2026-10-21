-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital item names: never show a bare itemID.
-- Order: names cached in PhyzanCapitalDB.items -> live client data (C_Item.GetItemNameByID / C_Item.GetItemInfo) ->
-- bundled English names (Data/ItemNames.lua, Classic Era ItemSparse) -> "Item #<id> (loading…)".
-- Unknown items are requested from the server (C_Item.RequestLoadItemDataByID or Item:ContinueOnItemLoad);
-- GET_ITEM_INFO_RECEIVED / ITEM_DATA_LOAD_RESULT then cache the name, quality and icon and refresh the window.
local _, ns = ...
local I = {}
ns.Items = I

local QUALITY_COLOR = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee",
  [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff", [8] = "ff00ccff" }
I.QUALITY_COLOR = QUALITY_COLOR
local LOADING = "(loading\226\128\166)"
local REQUEST_AGAIN = 30 -- seconds before re-requesting the same item
local requested = {}

local function call(f, ...)
  if type(f) ~= "function" then return nil end
  local r = { pcall(f, ...) }
  if not r[1] then return nil end
  return select(2, unpack(r))
end

-- Live client data; any part can be nil while the item is not cached yet.
local function live(id)
  local name, quality, icon
  if type(C_Item) == "table" then
    name = call(C_Item.GetItemNameByID, id)
    quality = call(C_Item.GetItemQualityByID, id)
    icon = call(C_Item.GetItemIconByID, id)
  end
  if not name then -- C_Item.GetItemInfo on modern clients (WoW Forever has no GetItemInfo global)
    local n, _, q, _, _, _, _, _, _, tex = ns.GetItemInfo(id)
    if n then name, quality, icon = n, quality or q, icon or tex end
  end
  if not icon then icon = ns.ItemIcon(id) end
  if type(name) ~= "string" or name == "" then name = nil end
  if type(quality) ~= "number" or quality < 0 then quality = nil end
  return name, quality, icon
end

function I:Request(id)
  local now = time()
  if requested[id] and now - requested[id] < REQUEST_AGAIN then return end
  requested[id] = now
  if type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
    pcall(C_Item.RequestLoadItemDataByID, id)
  elseif type(Item) == "table" and type(Item.CreateFromItemID) == "function" then
    pcall(function() Item:CreateFromItemID(id):ContinueOnItemLoad(function() I:OnLoaded(id) end) end)
  else
    ns.GetItemInfo(id) -- old clients: the call itself queues the request, GET_ITEM_INFO_RECEIVED follows
  end
end

-- Save whatever the client knows now into db.items. Returns true if a name is known.
function I:Store(id)
  if not ns.db then return false end
  local name, quality, icon = live(id)
  if not (name or quality or icon) then return false end
  local it = ns.db.items[id]
  if not it then it = {}; ns.db.items[id] = it end
  if name then it.name = name end
  if quality then it.quality = quality end
  if icon then it.icon = icon end
  return name ~= nil
end

-- name (or nil), quality (or nil), icon (or nil), source ("cache", "live", "bundled", nil)
function I:Info(id)
  id = tonumber(id)
  if not id then return nil end
  local it = ns.db and ns.db.items[id]
  local name, quality, icon = it and it.name, it and it.quality, it and it.icon
  if type(quality) == "number" and quality < 0 then quality = nil end
  local src = name and "cache"
  if not name or not quality or not icon then
    local ln, lq, li = live(id)
    if ln or lq or li then
      self:Store(id)
      if not name and ln then src = "live" end
      name, quality, icon = name or ln, quality or lq, icon or li
    end
  end
  if not name then
    local b = ns.ItemNames and ns.ItemNames[id]
    if b then name, quality, src = b[1], quality or b[2], "bundled" end
    self:Request(id)
  end
  return name, quality, icon, src
end

function I:Name(id)
  local name = self:Info(id)
  return name or ("Item #" .. tostring(id) .. " " .. LOADING)
end

-- "|T icon|t |cffRRGGBBName|r"
function I:Label(id, noIcon)
  local name, quality, icon = self:Info(id)
  local text = name or ("Item #" .. tostring(id) .. " " .. LOADING)
  local color = name and QUALITY_COLOR[quality or 1] or "ff9d9d9d"
  text = "|c" .. color .. text .. "|r"
  if icon and not noIcon then local sz = math.floor(14 * ((ns.UI and ns.UI.scale) or 1) + 0.5) -- icon follows the text size
    text = "|T" .. tostring(icon) .. ":" .. sz .. ":" .. sz .. "|t " .. text end
  return text
end

function I:SetTooltip(tt, id)
  if not tt or not id then return false end
  if tt.SetItemByID and pcall(tt.SetItemByID, tt, id) then return true end
  if tt.SetHyperlink and pcall(tt.SetHyperlink, tt, "item:" .. id) then return true end
  tt:AddLine(self:Label(id, true))
  return false
end

-- Debounced refresh of the visible window when item data arrives (names stream in after a big scan).
function I:OnLoaded(id)
  id = tonumber(id)
  if not id then return end
  self:Store(id)
  if ns.Categories then ns.Categories:Classify(id) end -- class / subclass / slot for the Market category tree
  local it = ns.db and ns.db.items[id]
  if it and it.sellPrice == nil then ns.TouchItem(id, it.name) end -- vendor sell price + stack size arrive too
  if self.refreshPending then return end
  self.refreshPending = true
  ns.After(1, function()
    self.refreshPending = false
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.UI:Refresh() end
  end)
end

ns.On("GET_ITEM_INFO_RECEIVED", function(_, id, ok) if ok ~= false then I:OnLoaded(id) end end)
ns.On("ITEM_DATA_LOAD_RESULT", function(_, id, ok) if ok ~= false then I:OnLoaded(id) end end)
