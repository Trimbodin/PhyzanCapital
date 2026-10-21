-- SPDX-License-Identifier: GPL-3.0-or-later
-- Phyzan Capital - Copyright (C) 2026 Fredrick. Licensed under the GNU GPL v3 or later; see LICENSE.
-- Phyzan Capital: "See vendor on map". Exactly one pin at a time, only for the vendor you picked.
-- Preferred: the game's own user waypoint (C_Map.SetUserWaypoint with a UiMapPoint). Fallback when that API is
-- missing: a single texture drawn on WorldMapFrame's canvas, shown only while that vendor's map is displayed.
-- Coordinates: bundled VendorNPCs[npc] x, y (pfQuest main spawn, percent of the zone map) and
-- VendorZoneUiMap[zoneIndex] (Blizzard UiMapAssignment), or the position recorded when you visited the merchant.
local _, ns = ...
local UI = ns.UI
local M = { current = nil }
ns.MapPin = M

local function has(t, k) return type(t) == "table" and type(t[k]) == "function" end

-- WoW Forever's Stormwind City map (uiMapID 1453) is laid out differently from the one pfQuest's coordinates were
-- taken on. Fit from 12 merchants (Innkeeper Allison and Gunther Weller recorded in game on Oct 17, 2026, plus 10
-- published WoW Forever map positions): x' = 0.7724 x + 19.84, y' = 0.776 y + 24.35, within 0.4 map % of each.
-- Ironforge positions recorded in game match the bundle (within 0.4), so no other zone is changed.
M.ZONE_FIX = { ["Stormwind City"] = { 0.7724, 19.84, 0.776, 24.35 } }

function M.FixCoords(zone, x, y)
  local f = zone and M.ZONE_FIX[zone]
  if not f or not x or not y then return x, y end
  return math.floor((f[1] * x + f[2]) * 10 + 0.5) / 10, math.floor((f[3] * y + f[4]) * 10 + 0.5) / 10
end

-- Bundled location of a vendor NPC: { npc, name, zone, uiMapID, x, y } (x, y in 0-100) or nil.
function M:NPCLocation(npc)
  local n = ns.VendorNPCs and ns.VendorNPCs[npc]
  if not n then return nil end
  local zone = ns.VendorZones and ns.VendorZones[n[2]] or "?"
  local x, y = M.FixCoords(zone, n[4], n[5])
  return { npc = npc, name = n[1], zone = zone, uiMapID = ns.VendorZoneUiMap and ns.VendorZoneUiMap[n[2]], x = x, y = y }
end

-- Location for an entry of ns.Vendor:Vendors(itemID).
function M:VendorLocation(v)
  if not v then return nil end
  if v.uiMapID and v.x and v.y then return { npc = v.npc, name = v.name, zone = v.zone, uiMapID = v.uiMapID, x = v.x, y = v.y } end
  if v.npc then return self:NPCLocation(v.npc) end
  return { name = v.name, zone = v.zone }
end

-- Player position as { uiMapID, x, y } (0-100), used when recording a merchant.
function M:PlayerPosition()
  if not (has(C_Map, "GetBestMapForUnit") and has(C_Map, "GetPlayerMapPosition")) then return nil end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or not map then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not ok2 or not pos then return nil end
  local x, y
  if type(pos.GetXY) == "function" then x, y = pos:GetXY() else x, y = pos.x, pos.y end
  if not x or not y or (x == 0 and y == 0) then return nil end
  return { uiMapID = map, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }
end

---------------------------------------------------------------------------
-- Fallback pin on the world map canvas
---------------------------------------------------------------------------
function M:FallbackPin()
  if self.pin or not WorldMapFrame or not has(WorldMapFrame, "GetCanvas") then return self.pin end
  local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
  if not ok or not canvas then return nil end
  local pin = CreateFrame("Frame", "PhyzanCapitalMapPin", canvas)
  pin:SetSize(32, 32)
  if pin.SetFrameStrata then pin:SetFrameStrata("TOOLTIP") end
  pin.tex = pin:CreateTexture(nil, "OVERLAY")
  pin.tex:SetAllPoints()
  pin.tex:SetTexture("Interface\\Minimap\\ObjectIcons")
  if pin.tex.SetTexCoord then pin.tex:SetTexCoord(0.5, 0.625, 0, 0.125) end -- generic vendor-style marker
  pin:Hide()
  pin.elapsed = 0
  pin.canvas = canvas
  -- keep it on the right map and position while the world map is open (cheap check, 5x per second)
  local driver = CreateFrame("Frame", nil, WorldMapFrame)
  driver:SetScript("OnUpdate", function(_, dt)
    pin.elapsed = pin.elapsed + (dt or 0)
    if pin.elapsed < 0.2 then return end
    pin.elapsed = 0
    M:UpdateFallbackPin()
  end)
  self.pin = pin
  return pin
end

function M:UpdateFallbackPin()
  local pin, c = self.pin, self.current
  if not pin then return end
  local mapID = WorldMapFrame and has(WorldMapFrame, "GetMapID") and WorldMapFrame:GetMapID()
  if not c or c.method ~= "pin" or mapID ~= c.uiMapID then pin:Hide(); return end
  local w, h = pin.canvas:GetWidth(), pin.canvas:GetHeight()
  pin:ClearAllPoints()
  pin:SetPoint("CENTER", pin.canvas, "TOPLEFT", w * c.x / 100, -h * c.y / 100)
  pin:Show()
end

---------------------------------------------------------------------------
function M:Clear(silent)
  local c = self.current
  self.current = nil
  if c and c.method == "waypoint" and has(C_Map, "ClearUserWaypoint") then
    -- only remove the waypoint if it is still the one we placed
    local mine = true
    if has(C_Map, "GetUserWaypoint") then
      local ok, pt = pcall(C_Map.GetUserWaypoint)
      if ok and pt then
        local px = pt.position and (pt.position.x or (pt.position.GetXY and pt.position:GetXY()))
        mine = pt.uiMapID == c.uiMapID and px and math.abs(px - c.x / 100) < 0.002
      elseif ok then mine = false end
    end
    if mine then pcall(C_Map.ClearUserWaypoint) else c.foreign = true end
  end
  if self.pin then self.pin:Hide() end
  if not silent and c then
    ns.Print(c.foreign and "map pin forgotten (the current waypoint was set by someone else and is left alone)."
      or ("map pin cleared (" .. tostring(c.name) .. ")."))
  end
end

function M:Show(loc)
  if not loc then return end
  if not (loc.uiMapID and loc.x and loc.y) then
    ns.Print(string.format("%s - %s: no map coordinates known for this vendor.", tostring(loc.name), tostring(loc.zone or "?")))
    return
  end
  self:Clear(true) -- one pin only: replace the previous one
  local c = { name = loc.name, zone = loc.zone, uiMapID = loc.uiMapID, x = loc.x, y = loc.y, npc = loc.npc }
  local placed = false
  if has(C_Map, "SetUserWaypoint") and type(UiMapPoint) == "table" and has(UiMapPoint, "CreateFromCoordinates") then
    local ok, pt = pcall(UiMapPoint.CreateFromCoordinates, c.uiMapID, c.x / 100, c.y / 100)
    local allowed = true
    if has(C_Map, "CanSetUserWaypointOnMap") then
      local ok2, can = pcall(C_Map.CanSetUserWaypointOnMap, c.uiMapID)
      if ok2 and can == false then allowed = false end
    end
    if ok and pt and allowed then placed = pcall(C_Map.SetUserWaypoint, pt) end
    -- No C_SuperTrack.SetSuperTrackedUserWaypoint: it is protected on WoW Forever (pcall cannot catch it; the
    -- client shows "Interface action failed because of an AddOn"). The pin is on the map; clicking it tracks it.
  end
  c.method = placed and "waypoint" or "pin"
  self.current = c
  -- open the world map on that zone (our full-screen window would cover it)
  if UI and UI.frame and UI.frame:IsShown() then UI.frame:Hide() end
  local opened = false
  if type(OpenWorldMap) == "function" then opened = pcall(OpenWorldMap, c.uiMapID) end
  if not opened and WorldMapFrame then
    if type(ShowUIPanel) == "function" then pcall(ShowUIPanel, WorldMapFrame) elseif WorldMapFrame.Show then WorldMapFrame:Show() end
    if has(WorldMapFrame, "SetMapID") then pcall(WorldMapFrame.SetMapID, WorldMapFrame, c.uiMapID) end
  end
  if c.method == "pin" then
    if self:FallbackPin() then self:UpdateFallbackPin() else ns.Print("could not place a map pin on this client (no C_Map waypoint or world map canvas).") end
  end
  ns.Print(string.format("%s \226\128\148 %s (%.1f, %.1f)", c.name or "?", c.zone or "?", c.x, c.y))
  ns.CountUsage("action:mappin")
end

---------------------------------------------------------------------------
-- Closest vendor: rank an item's vendors by distance from the player.
-- Same zone first, then same continent by world distance (yards), then other continents; hostile vendors last
-- (never "closest"). World positions use the bundled UiMapBounds (Blizzard UiMapAssignment) when both maps are
-- known, otherwise C_Map.GetWorldPosFromMapPos for both points, so the two are always converted the same way.
---------------------------------------------------------------------------
local POS_THROTTLE = 3 -- seconds between player-position reads

local function bundledWorld(uiMapID, x, y)
  local b = ns.UiMapBounds and ns.UiMapBounds[uiMapID]
  if not b then return nil end
  return b[1], b[4] - (y / 100) * (b[4] - b[2]), b[5] - (x / 100) * (b[5] - b[3])
end

local function apiWorld(uiMapID, x, y)
  if not has(C_Map, "GetWorldPosFromMapPos") then return nil end
  local vec = (type(CreateVector2D) == "function" and CreateVector2D(x / 100, y / 100)) or { x = x / 100, y = y / 100 }
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, uiMapID, vec)
  if not ok or not cont or type(pos) ~= "table" then return nil end
  local wx, wy = pos.x, pos.y
  if type(pos.GetXY) == "function" then wx, wy = pos:GetXY() end
  if not wx or not wy then return nil end
  return cont, wx, wy
end

-- continent, distance (yards) between two {uiMapID, x, y} points; distance nil if on different continents
function M:Distance(a, b)
  local ca, ax, ay = bundledWorld(a.uiMapID, a.x, a.y)
  local cb, bx, by = bundledWorld(b.uiMapID, b.x, b.y)
  if not (ca and cb) then
    ca, ax, ay = apiWorld(a.uiMapID, a.x, a.y)
    cb, bx, by = apiWorld(b.uiMapID, b.x, b.y)
  end
  if not (ca and cb) then return nil, nil, false end
  if ca ~= cb then return nil, nil, true end
  return ca, math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2), true
end

-- Player position, re-read at most every POS_THROTTLE seconds (force = zone changed / tab opened).
function M:PlayerSpot(force)
  local now = time()
  local maxAge = force and 0 or POS_THROTTLE
  if self.spotTs and now - self.spotTs < math.max(maxAge, 1) then return self.spot or nil end
  self.spotTs = now
  self.spot = self:PlayerPosition() or false
  return self.spot or nil
end

-- vendors = ns.Vendor:Vendors(id). Returns ranked list of { v, loc, tier, dist, text } and the closest friendly entry.
-- Seasonal note shown in rows, tooltips and popups.
function M.SeasonalNote(v)
  if not v or not v.seasonal then return nil end
  if v.seasonal:find("Darkmoon Faire", 1, true) then return "Darkmoon Faire (only when the faire is in town)" end
  if v.seasonal:find("(", 1, true) then return v.seasonal end -- already explained ("... no permanent spawn")
  return v.seasonal .. " (seasonal, only during the event)"
end

-- " [not here]" etc. for menus and tooltips
function M.StateTag(v)
  if not v then return "" end
  if v.missing then return " [marked not here]" end
  if v.notSold then return " [not sold here when you visited]" end
  if v.observed and v.seen then return " [seen " .. date("%Y-%m-%d", v.seen) .. "]" end
  return ""
end

-- "Vendor not here": mark it missing (persisted), then offer the next closest vendor for the same item.
function M:AskNotHere(s, v)
  ns.Vendor:AskMissing(v, s and s.id, function()
    if not s then return end
    s.vendors = ns.Vendor:Vendors(s.id)
    local _, c = M:RankVendors(s.vendors, M:PlayerSpot())
    s.closest = c
    if M.current and M.current.npc and M.current.npc == v.npc then M:Clear(true) end
    M:AskShow(s)
  end)
end

function M:RankVendors(vendors, spot)
  local out = {}
  local hideSeasonal = ns.db and ns.db.settings and ns.db.settings.hideSeasonalVendors
  for i, v in ipairs(vendors or {}) do
   if not (hideSeasonal and v.seasonal) then
    local loc = self:VendorLocation(v)
    local e = { v = v, loc = loc, idx = i, tier = 5 }
    local hasXY = loc and loc.uiMapID and loc.x and loc.y
    if spot and hasXY then
      if loc.uiMapID == spot.uiMapID then
        e.tier = 1
        local _, d = self:Distance(spot, loc)
        e.dist = d -- same map: never "other continent"; without world bounds sort by map distance
        e.sortDist = d or math.sqrt((spot.x - loc.x) ^ 2 + (spot.y - loc.y) ^ 2)
      else
        local cont, d, known = self:Distance(spot, loc)
        if cont and d then e.tier, e.dist, e.sortDist = 2, d, d
        elseif known then e.tier, e.other = 3, true
        else e.tier = 4 end
      end
    elseif hasXY then e.tier = 4 end
    if v.seasonal then e.tier = e.tier + 5 end -- seasonal: only "closest" when no regular vendor exists
    if not v.usable then e.tier = e.tier + 10 end -- hostile: listed last, never the closest
    if v.missing or v.notSold then e.tier = e.tier + 20 end -- "not here" / live merchant does not sell it: never closest
    out[#out + 1] = e
   end
  end
  table.sort(out, function(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    if a.sortDist and b.sortDist and a.sortDist ~= b.sortDist then return a.sortDist < b.sortDist end
    return a.idx < b.idx
  end)
  local closest
  for _, e in ipairs(out) do if e.v.usable and not e.v.missing and not e.v.notSold then closest = e; break end end
  return out, closest
end

function M:DistanceText(e)
  if not e then return "" end
  if e.dist then return ns.IntStr(e.dist) .. " yd" end
  if e.other then return "other continent" end
  return ""
end

function M:VendorText(e)
  if not e then return "|cffff6060no friendly vendor|r" end
  local v = e.v
  local d = self:DistanceText(e)
  local note = M.SeasonalNote(v)
  return string.format("%s - %s%s%s%s", v.name or "?", v.zone or "?", d ~= "" and (" (" .. d .. ")") or "", v.limited and " [limited]" or "",
    note and ("  |cffffd100[" .. note .. "]|r") or "")
end

-- Zone changes: re-read the position (throttled) and refresh the Crafting List tab (distances) if it is visible.
local function zoneChanged()
  M.spotTs = nil
  if M.zonePending then return end
  M.zonePending = true
  ns.After(POS_THROTTLE, function()
    M.zonePending = false
    if UI and UI.frame and UI.frame:IsShown() and UI.tab == "shopping" then UI:Refresh() end
  end)
end
ns.On("ZONE_CHANGED", zoneChanged)
ns.On("ZONE_CHANGED_NEW_AREA", zoneChanged)
ns.On("ZONE_CHANGED_INDOORS", zoneChanged)

---------------------------------------------------------------------------
-- "See vendor on map?" confirmation (row click / Map button). Yes = pin the row's closest vendor.
-- Questions use our own dialog (UI:Confirm, FULLSCREEN_DIALOG strata, above our window).
function M.Ask(which, text, onYes) ns.UI:Confirm({ which = which, text = text, onYes = onYes }) end
function M.Info(which, text) ns.UI:Confirm({ which = which, text = text, kind = "ok" }) end

function M:AskShow(s)
  if not s then return end
  local _, closest = self:RankVendors(s.vendors, self:PlayerSpot())
  local head = "Phyzan Capital\n\n" .. ns.ItemLabel(s.id, true) .. "\n\n"
  if not closest then
    M.Info("mapinfo", head .. "No friendly vendor is known for this item" ..
      ((s.vendors and #s.vendors > 0) and " (only vendors hostile to your faction, or hidden seasonal ones)." or "."))
    return
  end
  local loc = closest.loc
  local v = closest.v
  local d = self:DistanceText(closest)
  local note = M.SeasonalNote(v)
  local desc = string.format("%s\n%s%s%s%s", v.name or "?", v.zone or "?", d ~= "" and (", " .. d) or "",
    v.limited and "\n(limited stock)" or "", note and ("\n|cffffd100" .. note .. "|r") or "")
  if not (loc and loc.uiMapID and loc.x and loc.y) then
    ns.UI:Confirm({ which = "mapinfo", kind = "ok", text = head .. desc .. "\n\nNo map coordinates are known for this vendor.",
      alt = not v.observed and { text = "Vendor not here", fn = function() M:AskNotHere(s, v) end } or nil })
    return
  end
  ns.UI:Confirm({ which = "mappin", text = head .. "See vendor on map?\n\n" .. desc, onYes = function() M:Show(loc) end,
    alt = not v.observed and { text = "Vendor not here", fn = function() M:AskNotHere(s, v) end } or nil })
  ns.CountUsage("map:ask")
end
