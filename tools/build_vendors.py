#!/usr/bin/env python3
"""Generate Data/Vendors.lua: every vendor-sold vanilla item with per-unit buy price and the NPCs that sell it.

Sources
  * Vendor lists, limited-stock flag, NPC names, main zone and faction: pfQuest database (https://github.com/shagu/pfQuest,
    db/items.lua "V" entries, db/units.lua coords/fac, db/enUS/units.lua, db/enUS/zones.lua), extracted with
    tools/extract_pfquest.lua into a TSV. pfQuest's data is derived from the VMaNGOS vanilla world database.
  * Prices: Blizzard Classic Era client table ItemSparse (BuyPrice, VendorStackCount) from
    https://wago.tools/db2/ItemSparse/csv?branch=wow_classic_era. BuyPrice is the price of one vendor pack of
    VendorStackCount items, so the per-unit price is BuyPrice / VendorStackCount.
  * NPC map position: pfQuest db/units.lua coords {x, y, zoneAreaID} (first spawn in the NPC's main zone), and
    zone AreaID -> uiMapID from Blizzard Classic Era UiMapAssignment.csv / UiMap.csv
    (https://wago.tools/db2/UiMapAssignment/csv?branch=wow_classic_era, .../UiMap/csv?branch=wow_classic_era).
  * Optional cross-check: cmangos classic-db npc_vendor / npc_vendor_template (Full_DB/ClassicDB_1_12_1_*.sql).
  * Seasonal vendors (same cmangos dump): an NPC is seasonal when every one of its spawns (`creature`, plus
    `creature_spawn_entry` for random-entry spawns) is listed in `game_event_creature` with a positive
    (spawn-during-event) event, or when it only appears through `game_event_creature_data` (an event that turns
    another spawn into this NPC); the event name comes from `game_event`. An NPC with no spawn at all is tagged
    "<subname> (holiday only, no permanent spawn)" when its creature_template subname says Holiday / Festival / ...
    (e.g. 8117 Wizbang Booms <Holiday Fireworks Vendor>), else "no world spawn known".
    Darkmoon Faire events (Elwynn / Mulgore) are all reported as "Darkmoon Faire".

Usage: python3 build_vendors.py <pfquest_vendors.tsv> <ItemSparse.csv> <addon_dir> [cmangos.sql]
  (UiMap.csv and UiMapAssignment.csv are read from the same directory as ItemSparse.csv)
"""
import csv, sys, os, re, datetime, collections

tsv, sparse, out = sys.argv[1], sys.argv[2], sys.argv[3]
cm = sys.argv[4] if len(sys.argv) > 4 else None

sells = collections.defaultdict(dict)  # item -> {npc: maxcount}
units = {}
for line in open(tsv, encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    if p[0] == 'V':
        sells[int(p[1])][int(p[2])] = int(float(p[3]))
    elif p[0] == 'U':
        units[int(p[1])] = (p[2], int(p[3]), p[4], p[5], p[6] if len(p) > 6 else '', p[7] if len(p) > 7 else '')

ddir = os.path.dirname(os.path.abspath(sparse))
uimap_name = {int(r['ID']): (r['Name_lang'], int(r['Type'])) for r in csv.DictReader(open(os.path.join(ddir, 'UiMap.csv'), encoding='utf-8'))}
area_uimap = {}
uimap_bounds = {}  # uiMapID -> (continent MapID, minX, minY, maxX, maxY) in world yards
for r in csv.DictReader(open(os.path.join(ddir, 'UiMapAssignment.csv'), encoding='utf-8')):
    u, a = int(r['UiMapID']), int(r['AreaID'])
    if a and uimap_name.get(u, ('', 0))[1] == 3:  # zone-level maps only
        area_uimap.setdefault(a, u)
        if u not in uimap_bounds and float(r['UiMin_0']) == 0 and float(r['UiMax_0']) == 1:
            uimap_bounds[u] = (int(r['MapID']), float(r['Region_0']), float(r['Region_1']), float(r['Region_3']), float(r['Region_4']))
for area, ui, name in ((1519, 1453, 'Stormwind City'), (1537, 1455, 'Ironforge'), (1637, 1454, 'Orgrimmar'), (12, 1429, 'Elwynn Forest')):
    assert area_uimap.get(area) == ui and uimap_name[ui][0] == name, (area, ui, name)

price = {}
for r in csv.DictReader(open(sparse, newline='', encoding='utf-8')):
    i = int(r['ID'])
    if i in sells:
        bp, vsc = int(r['BuyPrice']), max(1, int(r['VendorStackCount'] or 1))
        if bp > 0:
            price[i] = (bp / vsc, vsc, r['Display_lang'])

zones, zidx, zone_uimap = [], {}, {}
npcs_used = {}
items_out = {}
for item in sorted(sells):
    if item not in price:
        continue
    lst = []
    for npc, mx in sorted(sells[item].items()):
        u = units.get(npc)
        if not u or not u[0]:
            continue
        lst.append(-npc if mx > 0 else npc)
        if npc not in npcs_used:
            zn = u[2] or ''
            if zn and zn not in zidx:
                zidx[zn] = len(zones) + 1
                zones.append(zn)
                if u[1] in area_uimap:
                    zone_uimap[zidx[zn]] = area_uimap[u[1]]
            npcs_used[npc] = (u[0], zidx.get(zn, 0), u[3], u[4], u[5])
    if lst:
        items_out[item] = lst

seasonal = {}
if cm:
    sqltext = open(cm, encoding='utf-8', errors='replace').read()
    def allrows(table):
        return ''.join(m.group(1) for m in re.finditer(r"INSERT INTO `%s` VALUES (.*?);\n" % table, sqltext, re.S))
    evname = {}
    for m in re.finditer(r"\((\d+),(-?\d+),(\d+),(\d+),(\d+),(\d+),'((?:[^'\\]|\\.)*)'\)", allrows('game_event')):
        d = m.group(7).replace("\\'", "'").strip()
        evname[int(m.group(1))] = 'Darkmoon Faire' if 'Darkmoon Faire' in d else d
    gec = collections.defaultdict(set)
    for m in re.finditer(r"\((\d+),(-?\d+)\)", allrows('game_event_creature')):
        gec[int(m.group(1))].add(int(m.group(2)))
    # spawn guid -> entries: creature.id, plus creature_spawn_entry for spawns with a random entry (creature.id = 0)
    spawns = collections.defaultdict(list)
    for m in re.finditer(r"\((\d+),(\d+),(\d+),", allrows('creature')):
        if int(m.group(2)):
            spawns[int(m.group(2))].append(int(m.group(1)))
    for m in re.finditer(r"\((\d+),(\d+)\)", allrows('creature_spawn_entry')):
        spawns[int(m.group(2))].append(int(m.group(1)))
    # game_event_creature_data(guid, entry_id, ..., event): during the event that spawn becomes entry_id
    event_entry = collections.defaultdict(set)  # npc -> events in which some spawn turns into it
    for m in re.finditer(r"\((\d+),(\d+),\d+,\d+,\d+,\d+,(\d+)\)", allrows('game_event_creature_data')):
        if int(m.group(2)):
            event_entry[int(m.group(2))].add(int(m.group(3)))
    # creature_template(entry, name, subname, ...) for the "Holiday ..." subnames
    subname = {}
    for m in re.finditer(r"\((\d+),'((?:[^'\\]|\\.)*)',(NULL|'((?:[^'\\]|\\.)*)')", allrows('creature_template')):
        subname[int(m.group(1))] = (m.group(4) or '').replace("\\'", "'")
    unspawned_list = []
    for npc in npcs_used:
        gs = spawns.get(npc)
        if gs and all(any(e > 0 for e in gec.get(g, ())) for g in gs):
            # every spawn is an event spawn
            evs = sorted({e for g in gs for e in gec.get(g, ()) if e > 0})
            names = sorted({evname.get(e, 'seasonal event') for e in evs})
            seasonal[npc] = ' / '.join(names)
        elif not gs and event_entry.get(npc):
            # only exists as an event replacement of another spawn
            seasonal[npc] = ' / '.join(sorted({evname.get(e, 'seasonal event') for e in event_entry[npc]}))
        elif not gs:
            # no world spawn at all in the reference core: holiday vendors spawned by event scripts, or removed NPCs.
            # pfQuest still lists a position, so without this the map pin points at an empty spot.
            sub = subname.get(npc, '')
            seasonal[npc] = ('%s (holiday only, no permanent spawn)' % sub) if re.search(r'holiday|festival|fireworks|lunar|midsummer|winter veil|hallow|smokywood', sub, re.I) \
                else 'no world spawn known (may not exist on this server)'
            unspawned_list.append((npc, npcs_used[npc][0], sub))
    print('vendors without any cmangos spawn: %d' % len(unspawned_list))
    for npc, n, sub in sorted(unspawned_list):
        print('  %d %s <%s>' % (npc, n, sub))

def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def num(x):
    return ('%d' % x) if x == int(x) else ('%.4g' % x)

stamp = datetime.date.today().isoformat()
L = ['-- AUTO-GENERATED by tools/build_vendors.py on %s. Do not edit by hand.' % stamp,
     '-- Vendor lists / NPC names / zones / factions: pfQuest database (github.com/shagu/pfQuest, VMaNGOS-derived).',
     '-- Prices: Blizzard Classic Era ItemSparse BuyPrice / VendorStackCount (per unit, copper) via wago.tools.',
     '-- VendorDB[itemID] = { unitPrice, npcID, npcID, ... }  (negative npcID = limited stock at that vendor)',
     '-- VendorNPCs[npcID] = { name, zoneIndex, faction ("A", "H", "AH" or ""), x, y }   VendorZones[zoneIndex] = zone name',
     '-- x, y: main spawn in percent of the zone map (pfQuest). VendorZoneUiMap[zoneIndex] = uiMapID (Blizzard UiMapAssignment).',
     'local _, ns = ...',
     'ns.VendorDataInfo = { generated = "%s", items = %d, vendors = %d }' % (stamp, len(items_out), len(npcs_used)),
     'ns.VendorZones = {' + ','.join(q(z) for z in zones) + '}',
     'ns.VendorZoneUiMap = {' + ','.join('[%d]=%d' % (k, zone_uimap[k]) for k in sorted(zone_uimap)) + '}',
     '-- UiMapBounds[uiMapID] = { continentMapID, minX, minY, maxX, maxY } (world yards, Blizzard UiMapAssignment Region).',
     '-- worldX = maxX - mapY * (maxX - minX), worldY = maxY - mapX * (maxY - minY), mapX/mapY in 0..1.',
     'ns.UiMapBounds = {' + ','.join('[%d]={%d,%.1f,%.1f,%.1f,%.1f}' % ((k,) + uimap_bounds[k]) for k in sorted(uimap_bounds)) + '}',
     '-- VendorSeasonal[npcID] = event name: NPC only spawns during that world event (cmangos game_event_creature / _data),',
     '-- or "... no permanent spawn" / "no world spawn known" when cmangos has no spawn for it at all.',
     'ns.VendorSeasonal = {' + ','.join('[%d]=%s' % (k, q(seasonal[k])) for k in sorted(seasonal)) + '}',
     'ns.VendorNPCs = {']
for npc in sorted(npcs_used):
    n, z, f, x, y = npcs_used[npc]
    if x != '' and y != '':
        L.append('[%d]={%s,%d,%s,%s,%s},' % (npc, q(n), z, q(f), num(float(x)), num(float(y))))
    else:
        L.append('[%d]={%s,%d,%s},' % (npc, q(n), z, q(f)))
L.append('}')
L.append('ns.VendorDB = {')
for item in sorted(items_out):
    L.append('[%d]={%s,%s},' % (item, num(price[item][0]), ','.join(str(x) for x in items_out[item])))
L.append('}')
os.makedirs(os.path.join(out, 'Data'), exist_ok=True)
path = os.path.join(out, 'Data', 'Vendors.lua')
open(path, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print('items %d, vendors %d, zones %d, size %d bytes, vendor-pack items %d' % (len(items_out), len(npcs_used), len(zones),
      os.path.getsize(path), sum(1 for i in items_out if price[i][1] > 1)))
print('zones with a uiMapID: %d of %d; vendors with coordinates: %d' % (len(zone_uimap), len(zones),
      sum(1 for v in npcs_used.values() if v[3] != '')))
print('seasonal vendors: %d (%s)' % (len(seasonal), ', '.join(sorted(set(seasonal.values())))))
print('dropped: %d listed items without a Blizzard BuyPrice' % (len(sells) - len([i for i in sells if i in price])))

if cm:  # cross-check against cmangos
    cmv = collections.defaultdict(set)
    tmpl = collections.defaultdict(set)
    ct_tmpl = {}
    for line in open(cm, encoding='utf-8', errors='replace'):
        if line.startswith('INSERT INTO `npc_vendor` ') or line.startswith('INSERT INTO `npc_vendor_template` '):
            target = cmv if '`npc_vendor`' in line else tmpl
            for m in re.finditer(r'\((\d+),(\d+),', line):
                target[int(m.group(2))].add(int(m.group(1)))
    both = set(cmv) | set(tmpl)
    common = set(items_out) & both
    print('cross-check cmangos: %d items sold by vendors (direct+templates); %d of our %d items also in cmangos' % (len(both), len(common), len(items_out)))
