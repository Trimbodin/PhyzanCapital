#!/usr/bin/env python3
"""Convert Phyzan Capital SavedVariables (PhyzanCapital.lua) into SQLite and/or CSV for analysis.

The file is written by the game at:
  World of Warcraft\\_classic_beta_\\WTF\\Account\\<ACCOUNT>\\SavedVariables\\PhyzanCapital.lua
(after /reload, logout or exit).

Usage:
  python3 parse_sv.py PhyzanCapital.lua --sqlite capital.db --csv out_dir
  python3 parse_sv.py --self-test

Tables produced (see README "SavedVariables schema"):
  scans, listings, daily_item_stats, est_sales, current_prices, vendor_prices, recipes, recipe_reagents,
  items, usage, characters, char_professions, overrides, shopping_list, shopping_log,
  observed_vendors, observed_vendor_items, vendor_missing (schema 5), debug, meta
Only the Python standard library is used.
"""
import argparse, csv, os, re, sqlite3, sys, tempfile

SUPPORTED_SCHEMA = (1, 2, 3, 4, 5)


# --------------------------------------------------------------------------- Lua table parser
class LuaParseError(Exception):
    pass


_TOKEN = re.compile(r"""
    (?P<ws>\s+|--\[\[.*?\]\]|--[^\n]*) |
    (?P<str>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*') |
    (?P<num>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<op>[{}\[\]=,;])
""", re.S | re.X)

_ESC = {'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v', '\\': '\\', '"': '"', "'": "'", '\n': '\n'}


def _unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            if n.isdigit():
                m = re.match(r'\d{1,3}', s[i + 1:])
                out.append(chr(int(m.group(0))))
                i += 1 + len(m.group(0))
                continue
            out.append(_ESC.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def tokenize(text):
    pos, toks = 0, []
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise LuaParseError('unexpected character %r at offset %d' % (text[pos], pos))
        pos = m.end()
        kind = m.lastgroup
        if kind == 'ws':
            continue
        v = m.group(kind)
        if kind == 'str':
            toks.append(('str', _unescape(v[1:-1])))
        elif kind == 'num':
            toks.append(('num', int(v, 16) if v.lower().startswith(('0x', '-0x')) else (float(v) if re.search(r'[.eE]', v) else int(v))))
        else:
            toks.append((kind, v))
    return toks


class _P:
    def __init__(self, toks):
        self.t, self.i = toks, 0

    def peek(self, k=0):
        return self.t[self.i + k] if self.i + k < len(self.t) else (None, None)

    def take(self, kind=None, val=None):
        tok = self.peek()
        if (kind and tok[0] != kind) or (val is not None and tok[1] != val):
            raise LuaParseError('expected %s %s, got %r at token %d' % (kind, val, tok, self.i))
        self.i += 1
        return tok

    def value(self):
        k, v = self.peek()
        if k == 'str' or k == 'num':
            self.i += 1
            return v
        if k == 'name':
            self.i += 1
            if v == 'true': return True
            if v == 'false': return False
            if v == 'nil': return None
            raise LuaParseError('unexpected name %r' % v)
        if k == 'op' and v == '{':
            return self.table()
        raise LuaParseError('unexpected token %r' % ((k, v),))

    def table(self):
        self.take('op', '{')
        d, n = {}, 1
        while True:
            k, v = self.peek()
            if k == 'op' and v == '}':
                self.i += 1
                break
            if k == 'op' and v == '[':
                self.i += 1
                key = self.value()
                self.take('op', ']')
                self.take('op', '=')
                d[key] = self.value()
            elif k == 'name' and self.peek(1) == ('op', '='):
                self.i += 2
                d[v] = self.value()
            else:
                d[n] = self.value()
                n += 1
            k, v = self.peek()
            if k == 'op' and v in (',', ';'):
                self.i += 1
        # convert pure 1..n tables to lists
        if d and all(isinstance(x, int) and not isinstance(x, bool) for x in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[i] for i in range(1, len(d) + 1)]
        return d


def parse_saved_variables(text):
    """Returns {globalName: value} for every top-level assignment."""
    p = _P(tokenize(text))
    out = {}
    while p.peek()[0] is not None:
        name = p.take('name')[1]
        p.take('op', '=')
        out[name] = p.value()
    return out


# --------------------------------------------------------------------------- flattening
def _items(t):
    """Iterate a Lua table that may have become a list or a dict."""
    if isinstance(t, list):
        return list(enumerate(t, 1))
    if isinstance(t, dict):
        return list(t.items())
    return []


LISTING_FIELDS = ['item_id', 'count', 'min_bid', 'buyout', 'unit_buyout', 'time_left', 'seller', 'bid_amount']


def flatten(db):
    if not isinstance(db, dict):
        raise ValueError('PhyzanCapitalDB is not a table')
    ver = db.get('schemaVersion')
    if ver not in SUPPORTED_SCHEMA:
        print('warning: schemaVersion %r, parser written for %r' % (ver, SUPPORTED_SCHEMA), file=sys.stderr)
    items = dict(_items(db.get('items')))
    T = {k: [] for k in ('meta', 'scans', 'listings', 'daily_item_stats', 'est_sales', 'current_prices',
                         'vendor_prices', 'recipes', 'recipe_reagents', 'items', 'usage',
                         'characters', 'char_professions', 'overrides', 'shopping_list', 'shopping_log',
                         'observed_vendors', 'observed_vendor_items', 'vendor_missing', 'debug')}
    T['meta'].append({'schema_version': ver, 'addon_version': db.get('addonVersion'), 'created_at': db.get('createdAt'),
                      **{'setting_' + k: v for k, v in (db.get('settings') or {}).items()}})
    scans = {}
    for _, s in _items(db.get('scans')):
        row = {'scan_id': s.get('id'), 'ts': s.get('ts'), 'end_ts': s.get('endTs'), 'market_day': s.get('day'),
               'ah_key': s.get('ahKey'), 'char': s.get('char'), 'mode': s.get('mode'), 'complete': int(bool(s.get('complete'))),
               'rows': s.get('rows'), 'skipped': s.get('skipped'), 'pruned': int(bool(s.get('pruned'))),
               'compared_to': s.get('comparedTo'), 'est_sold': s.get('estSold'), 'est_expired': s.get('estExpired'),
               'est_skipped': int(bool(s.get('estSkipped'))),
               'unique_items': s.get('items'), 'reason': s.get('reason'),
               'aggregated': int(bool(s.get('aggregated')))}
        scans[row['scan_id']] = row
        T['scans'].append(row)
    for sid, snap in _items(db.get('snapshots')):
        sc = scans.get(sid, {})
        for line in (snap if isinstance(snap, list) else [v for _, v in _items(snap)]):
            parts = line.split('|')
            if len(parts) != 8:
                continue
            r = dict(zip(LISTING_FIELDS, parts))
            for k in LISTING_FIELDS:
                if k != 'seller':
                    r[k] = int(r[k])
            r.update({'scan_id': sid, 'ts': sc.get('ts'), 'market_day': sc.get('market_day'), 'ah_key': sc.get('ah_key'),
                      'item_name': (items.get(r['item_id']) or {}).get('name')})
            T['listings'].append(r)
    for ah_key, ah in _items(db.get('ah')):
        for day, per in _items(ah.get('dailyStats')):
            for iid, st in _items(per):
                T['daily_item_stats'].append({'ah_key': ah_key, 'market_day': day, 'item_id': iid,
                    'item_name': (items.get(iid) or {}).get('name'),
                    'listings': st.get('listings'), 'quantity': st.get('quantity'), 'priced_listings': st.get('pricedListings'),
                    'no_buyout': st.get('noBuyout'), 'min_unit': st.get('minUnit'), 'median_unit': st.get('medianUnit'),
                    'avg_unit': st.get('avgUnit'), 'max_unit': st.get('maxUnit'), 'tl_short': st.get('tl1'),
                    'tl_medium': st.get('tl2'), 'tl_long': st.get('tl3'), 'tl_very_long': st.get('tl4'), 'scans': st.get('scans')})
        for day, per in _items(ah.get('estSales')):
            for iid, e in _items(per):
                T['est_sales'].append({'ah_key': ah_key, 'market_day': day, 'item_id': iid,
                    'item_name': (items.get(iid) or {}).get('name'), 'est_sold': e.get('sold'), 'est_sold_qty': e.get('soldQty'),
                    'est_sold_value': e.get('soldValue'), 'bid_won': e.get('bidWon'), 'bid_won_qty': e.get('bidWonQty'),
                    'expired': e.get('expired'), 'expired_qty': e.get('expiredQty')})
        for iid, c in _items(ah.get('current')):
            T['current_prices'].append({'ah_key': ah_key, 'item_id': iid, 'item_name': (items.get(iid) or {}).get('name'),
                'min_unit': c.get('minUnit'), 'listings': c.get('n'), 'quantity': c.get('qty'), 'scan_id': c.get('scanID'),
                'ts': c.get('ts'), 'cheapest': c.get('cheapest')})
    for iid, v in _items(db.get('vendorPrices')):
        T['vendor_prices'].append({'item_id': iid, 'name': v.get('name'), 'unit_price': v.get('unit'), 'stack_price': v.get('stackPrice'),
            'stack': v.get('stack'), 'merchant': v.get('merchant'), 'zone': v.get('zone'), 'limited': int(bool(v.get('limited'))), 'ts': v.get('ts'),
            'ui_map_id': v.get('uiMapID'), 'x': v.get('x'), 'y': v.get('y'), 'npc_id': v.get('npc')})
    for key, o in _items(db.get('observedVendors')):
        T['observed_vendors'].append({'vendor_key': str(key), 'npc_id': o.get('npc'), 'name': o.get('name'), 'zone': o.get('zone'),
            'ui_map_id': o.get('uiMapID'), 'x': o.get('x'), 'y': o.get('y'), 'first_seen': o.get('firstSeen'), 'seen': o.get('seen'),
            'complete': int(bool(o.get('complete'))), 'item_count': o.get('itemCount'), 'bundled_not_sold': o.get('bundledNotSold')})
        for iid, unit in _items(o.get('items')):
            T['observed_vendor_items'].append({'vendor_key': str(key), 'npc_id': o.get('npc'), 'item_id': iid,
                'item_name': (items.get(iid) or {}).get('name'), 'unit_price': unit})
    for key, m in _items(db.get('vendorMissing')):
        T['vendor_missing'].append({'vendor_key': str(key), 'npc_id': m.get('npc'), 'name': m.get('name'), 'zone': m.get('zone'),
            'item_id': m.get('itemID'), 'ts': m.get('ts')})
    for key, r in _items(db.get('recipes')):
        T['recipes'].append({'recipe_key': key, 'profession': r.get('prof'), 'product_id': r.get('product'), 'name': r.get('name'),
            'min_made': r.get('minMade'), 'max_made': r.get('maxMade'), 'reagents': r.get('reagents'),
            'difficulty': r.get('difficulty'), 'known_by': r.get('knownBy'), 'incomplete': int(bool(r.get('incomplete'))), 'ts': r.get('ts')})
        for part in (r.get('reagents') or '').split(';'):
            if ':' in part:
                a, b = part.split(':')
                T['recipe_reagents'].append({'recipe_key': key, 'reagent_id': int(a), 'count': int(b)})
    for iid, it in items.items():
        T['items'].append({'item_id': iid, 'name': it.get('name'), 'quality': it.get('quality'), 'sell_price': it.get('sellPrice'), 'stack': it.get('stack'), 'icon': it.get('icon')})
    for ck, c in _items(db.get('chars')):
        T['characters'].append({'char_key': ck, 'level': c.get('level'), 'last_detect': c.get('lastDetect'), 'last_reason': c.get('lastReason')})
        for prof, p in _items(c.get('professions')):
            T['char_professions'].append({'char_key': ck, 'profession': prof, 'rank': p.get('rank'), 'max_rank': p.get('max'),
                                          'source': p.get('source'), 'ts': p.get('ts')})
    for ck, o in _items(db.get('overrides')):
        if o.get('level') is not None:
            T['overrides'].append({'char_key': ck, 'kind': 'level', 'profession': None, 'value': o.get('level')})
        for prof, v in _items(o.get('professions')):
            T['overrides'].append({'char_key': ck, 'kind': 'profession', 'profession': prof, 'value': v})
    dbg = db.get('debug')
    if isinstance(dbg, dict):
        def flat(prefix, d):
            for k, v in sorted(d.items(), key=lambda kv: str(kv[0])):
                key = '%s%s' % (prefix, k)
                if isinstance(v, dict):
                    flat(key + '.', v)
                else:
                    T['debug'].append({'key': key, 'value': int(v) if isinstance(v, bool) else v})
        flat('', dbg)
    # schema 4: shopping list per character, and the history of removed / purchased entries
    for ck, lst in _items(db.get('shopping')):
        for iid, e in _items(lst):
            iid = e.get('itemID', iid)
            T['shopping_list'].append({'char_key': ck, 'item_id': iid, 'item_name': e.get('name') or (items.get(iid) or {}).get('name'),
                'qty': e.get('qty'), 'bought': e.get('bought'), 'vendor_npc': e.get('vendorNpc'), 'vendor_name': e.get('vendorName'),
                'vendor_zone': e.get('vendorZone'), 'vendor_faction': e.get('vendorFaction'), 'ui_map_id': e.get('uiMapID'),
                'x': e.get('x'), 'y': e.get('y'), 'vendor_unit': e.get('vendorUnit'), 'vendor_src': e.get('vendorSrc'),
                'ah_unit_at_add': e.get('ahUnit'), 'margin_at_add': e.get('margin'), 'ah_key': e.get('ahKey'),
                'added': e.get('added'), 'updated': e.get('updated')})
    for _, e in _items(db.get('shoppingLog')):
        T['shopping_log'].append({'char_key': e.get('char'), 'item_id': e.get('itemID'), 'qty': e.get('qty'), 'bought': e.get('bought'),
            'vendor_unit': e.get('vendorUnit'), 'ah_unit_at_add': e.get('ahUnit'), 'margin_at_add': e.get('margin'),
            'added': e.get('added'), 'removed': e.get('removed'), 'reason': e.get('reason')})
    last = db.get('usageLast') or {}
    for k, c in _items(db.get('usage')):
        T['usage'].append({'key': k, 'count': c, 'last_used': last.get(k)})
    return T


def write_sqlite(T, path):
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    for name, rows in T.items():
        cols = []
        for r in rows:
            for k in r:
                if k not in cols:
                    cols.append(k)
        if not cols:
            continue
        con.execute('CREATE TABLE "%s" (%s)' % (name, ', '.join('"%s"' % c for c in cols)))
        con.executemany('INSERT INTO "%s" VALUES (%s)' % (name, ','.join('?' * len(cols))), [[r.get(c) for c in cols] for r in rows])
    for idx in ('listings(item_id)', 'listings(scan_id)', 'daily_item_stats(item_id)', 'est_sales(item_id)'):
        try:
            con.execute('CREATE INDEX IF NOT EXISTS "ix_%s" ON %s' % (re.sub(r'\W', '_', idx), idx))
        except sqlite3.OperationalError:
            pass
    con.commit()
    con.close()


def write_csv(T, outdir):
    os.makedirs(outdir, exist_ok=True)
    for name, rows in T.items():
        cols = []
        for r in rows:
            for k in r:
                if k not in cols:
                    cols.append(k)
        with open(os.path.join(outdir, name + '.csv'), 'w', newline='', encoding='utf-8') as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            w.writerows(rows)


def load(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        g = parse_saved_variables(f.read())
    if 'PhyzanCapitalDB' not in g:
        raise ValueError('PhyzanCapitalDB not found in %s' % path)
    return flatten(g['PhyzanCapitalDB'])


# --------------------------------------------------------------------------- self-test
SAMPLE = r'''
PhyzanCapitalDB = {
	["schemaVersion"] = 4,
	["addonVersion"] = "1.2.2",
	["createdAt"] = 1792245600,
	["settings"] = {
		["charLevel"] = 37,
		["dayStartHour"] = 7,
		["keepSnapshotDays"] = 14,
		["maxSnapshotRows"] = 250000,
		["undercut"] = "5%",
	},
	["chars"] = { ["Fredrick-Forever"] = { ["level"] = 37, ["lastDetect"] = 1792245600, ["lastReason"] = "login",
		["professions"] = { ["Tailoring"] = { ["rank"] = 142, ["max"] = 150, ["source"] = "skills pane", },
			["Cooking"] = { ["rank"] = 60, ["max"] = 75, ["source"] = "skills pane", }, }, }, },
	["overrides"] = { ["Fredrick-Forever"] = { ["level"] = 40, ["professions"] = { ["Tailoring"] = 150, }, }, },
	["items"] = {
		[2589] = { ["name"] = "Linen Cloth", ["quality"] = 1, ["sellPrice"] = 13, },
		[2572] = { ["name"] = "Red \"Linen\" Robe", ["quality"] = 2, ["sellPrice"] = 120, },
	},
	["scans"] = {
		{ ["id"] = 1, ["ts"] = 1792245600, ["day"] = "2026-10-17", ["mode"] = "getAll", ["complete"] = true,
		  ["rows"] = 3, ["skipped"] = 0, ["ahKey"] = "Forever-Alliance", ["char"] = "Fredrick-Forever", }, -- [1]
		{ ["id"] = 2, ["ts"] = 1792246800, ["day"] = "2026-10-17", ["mode"] = "paged", ["complete"] = false,
		  ["rows"] = 1, ["skipped"] = 2, ["ahKey"] = "Forever-Alliance", ["comparedTo"] = 1, ["estSold"] = 1, ["estExpired"] = 0, }, -- [2]
	},
	["snapshots"] = {
		[1] = { "2589|20|200|300|15|4|Bob|0", "2589|20|200|320|16|3|Ann|250", "2572|1|3000|6000|6000|2|Zed-Other|0", },
		[2] = { "2589|20|200|300|15|4|Bob|0", },
	},
	["ah"] = {
		["Forever-Alliance"] = {
			["dailyStats"] = { ["2026-10-17"] = { [2589] = { ["listings"] = 2, ["quantity"] = 40, ["pricedListings"] = 2,
				["noBuyout"] = 0, ["minUnit"] = 15, ["maxUnit"] = 16, ["medianUnit"] = 16, ["avgUnit"] = 16, ["sumUnit"] = 31,
				["tl1"] = 0, ["tl2"] = 0, ["tl3"] = 1, ["tl4"] = 1, ["scans"] = 1, }, }, },
			["estSales"] = { ["2026-10-17"] = { [2589] = { ["sold"] = 1, ["soldQty"] = 20, ["soldValue"] = 320, ["expired"] = 0,
				["expiredQty"] = 0, ["bidWon"] = 0, ["bidWonQty"] = 0, }, }, },
			["current"] = { [2589] = { ["minUnit"] = 15, ["n"] = 1, ["qty"] = 20, ["scanID"] = 1, ["cheapest"] = "15:20", }, },
			["priceSamples"] = { ["2026-10-17"] = { [2589] = { 15, 16, }, }, },
		},
	},
	["vendorPrices"] = { [2320] = { ["unit"] = 10, ["stackPrice"] = 10, ["stack"] = 1, ["name"] = "Coarse Thread",
		["merchant"] = "Tharynn Bouden", ["limited"] = false, ["ts"] = 1792245600, }, },
	["recipes"] = { ["Tailoring:2572"] = { ["prof"] = "Tailoring", ["product"] = 2572, ["name"] = "Red Linen Robe",
		["minMade"] = 1, ["maxMade"] = 1, ["reagents"] = "2996:3;2320:2;2604:2", ["knownBy"] = "Fredrick-Forever", }, },
	["usage"] = { ["tab:market"] = 4, ["cmd:help"] = 1, },
	["shopping"] = { ["Fredrick-Forever"] = { [2320] = { ["itemID"] = 2320, ["name"] = "Coarse Thread", ["qty"] = 20, ["bought"] = 5,
		["vendorName"] = "Tharynn Bouden", ["vendorZone"] = "Elwynn Forest", ["uiMapID"] = 1429, ["x"] = 41.8, ["y"] = 67.2,
		["vendorUnit"] = 10, ["ahUnit"] = 25, ["margin"] = 13.75, ["ahKey"] = "Forever-Alliance", ["added"] = 1792245600, }, }, },
	["shoppingLog"] = { { ["char"] = "Fredrick-Forever", ["itemID"] = 2604, ["qty"] = 2, ["bought"] = 2, ["reason"] = "purchased",
		["added"] = 1792245600, ["removed"] = 1792246800, }, },
	["usageLast"] = { ["tab:market"] = 1792246800, },
	["observedVendors"] = { [5569] = { ["npc"] = 5569, ["name"] = "Fizzlebang Booms", ["zone"] = "Ironforge", ["uiMapID"] = 1455,
		["x"] = 73.6, ["y"] = 53.3, ["seen"] = 1792246800, ["complete"] = true, ["itemCount"] = 2,
		["items"] = { [5740] = 100, [2320] = 10, }, }, },
	["vendorMissing"] = { [8117] = { ["npc"] = 8117, ["name"] = "Wizbang Booms", ["zone"] = "Ironforge", ["itemID"] = 5740, ["ts"] = 1792246800, }, },
	["nextScanID"] = 3,
}
'''


def self_test(extra=None):
    g = parse_saved_variables(SAMPLE)
    T = flatten(g['PhyzanCapitalDB'])
    assert len(T['scans']) == 2, T['scans']
    assert len(T['listings']) == 4
    assert T['listings'][2]['seller'] == 'Zed-Other' and T['listings'][2]['unit_buyout'] == 6000
    assert T['listings'][0]['item_name'] == 'Linen Cloth'
    assert [i['name'] for i in T['items'] if i['item_id'] == 2572] == ['Red "Linen" Robe']
    assert len(T['daily_item_stats']) == 1 and T['daily_item_stats'][0]['median_unit'] == 16
    assert T['est_sales'][0]['est_sold_qty'] == 20
    assert T['vendor_prices'][0]['unit_price'] == 10
    assert len(T['recipe_reagents']) == 3
    assert {u['key'] for u in T['usage']} == {'tab:market', 'cmd:help'}
    assert T['characters'][0]['level'] == 37 and len(T['char_professions']) == 2
    assert {(o['kind'], o['value']) for o in T['overrides']} == {('level', 40), ('profession', 150)}
    assert T['shopping_list'][0]['item_id'] == 2320 and T['shopping_list'][0]['bought'] == 5 and T['shopping_list'][0]['ui_map_id'] == 1429
    assert T['shopping_log'][0]['reason'] == 'purchased' and T['shopping_log'][0]['item_id'] == 2604
    assert T['observed_vendors'][0]['npc_id'] == 5569 and len(T['observed_vendor_items']) == 2
    assert T['vendor_missing'][0]['npc_id'] == 8117 and T['vendor_missing'][0]['item_id'] == 5740
    with tempfile.TemporaryDirectory() as d:
        dbp = os.path.join(d, 't.db')
        write_sqlite(T, dbp)
        write_csv(T, os.path.join(d, 'csv'))
        con = sqlite3.connect(dbp)
        n = con.execute('select count(*) from listings').fetchone()[0]
        top = con.execute('select item_name, est_sold_qty from est_sales order by est_sold_qty desc').fetchone()
        con.close()
        assert n == 4 and top == ('Linen Cloth', 20), (n, top)
        assert os.path.exists(os.path.join(d, 'csv', 'listings.csv'))
    print('self-test (synthetic sample): OK')
    if extra:
        T = load(extra)
        print('extra file %s: %s' % (extra, ', '.join('%s=%d' % (k, len(v)) for k, v in T.items())))
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('savedvariables', nargs='?', help='path to PhyzanCapital.lua')
    ap.add_argument('--sqlite', help='write an SQLite database here')
    ap.add_argument('--csv', help='write one CSV per table into this directory')
    ap.add_argument('--self-test', action='store_true', help='run the built-in test against a synthetic sample')
    a = ap.parse_args()
    if a.self_test:
        self_test(a.savedvariables)
        return
    if not a.savedvariables or not (a.sqlite or a.csv):
        ap.error('give the SavedVariables file and --sqlite and/or --csv')
    T = load(a.savedvariables)
    if a.sqlite:
        write_sqlite(T, a.sqlite)
    if a.csv:
        write_csv(T, a.csv)
    print(', '.join('%s=%d' % (k, len(v)) for k, v in T.items()))


if __name__ == '__main__':
    main()
