-- Extract vendor lists, NPC zones/factions and names from pfQuest's database (https://github.com/shagu/pfQuest, db/).
-- Usage: lua5.1 extract_pfquest.lua <pfquest_db_dir> > pfquest_vendors.tsv
local dir = arg[1]
pfDB = { items = {}, units = {}, zones = {} }
for _, f in ipairs({ "items.lua", "units.lua", "enUS/units.lua", "enUS/zones.lua" }) do
  assert(loadfile(dir .. "/" .. f))()
end
local units, names, zones = pfDB.units.data, pfDB.units.enUS, pfDB.zones.enUS
local function clean(s) return (tostring(s or ""):gsub("[\t\n]", " ")) end
for id, it in pairs(pfDB.items.data) do
  if it.V then for npc, max in pairs(it.V) do io.write("V\t", id, "\t", npc, "\t", max, "\n") end end
end
for npc, u in pairs(units) do
  local count, best, bestN = {}, nil, 0
  for _, c in ipairs(u.coords or {}) do
    local z = c[3]
    count[z] = (count[z] or 0) + 1
    if count[z] > bestN then best, bestN = z, count[z] end
  end
  -- main spawn: the first listed spawn point in the zone with the most spawns (x, y are 0-100 zone map percent)
  local x, y = "", ""
  for _, c in ipairs(u.coords or {}) do
    if c[3] == best then x, y = c[1], c[2]; break end
  end
  io.write("U\t", npc, "\t", clean(names[npc]), "\t", best or 0, "\t", clean(best and zones[best]), "\t", clean(u.fac),
    "\t", x, "\t", y, "\n")
end
