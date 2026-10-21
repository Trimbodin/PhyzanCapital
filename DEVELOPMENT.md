# Phyzan Capital - developer notes

This file is for development and is **not** shipped in the CurseForge release zip (see *Release build (1.4.2)*). Players read `README.md`; the version history is in `CHANGELOG.md`.

Auction house ledger and trading window for the **WoW Forever** client (1.60.1, `## Interface: 16001`; classic game content on the modern Mainline client and API).

* Scans the auction house. It supports both auction APIs and picks one at runtime: the modern retail-style `C_AuctionHouse` (full scan via `ReplicateItems`, or a browse scan) and the legacy `QueryAuctionItems` (getAll, or paged).
* Keeps per-item, per-**market-day** stats. A market day runs **07:00 to 06:59** the next morning, local time.
* Keeps the raw scan history (and a scan-to-scan sales estimate) in SavedVariables for offline analysis. No volume is shown in game.
* Ships a world vendor database (every vendor-sold vanilla item, price per unit, who sells it and where they stand on the map) and uses it for vendor prices, the **closest friendly vendor** and a one-click map pin (Crafting List, Professions, Price Lookup).
* Shows item names everywhere, coloured by quality with icons and item tooltips. It never shows a bare itemID.
* Detects your character level and professions automatically (per character), records your recipes and shows every known recipe with its reagent costs and profit (Professions tab).
* Full-screen trading window with tabs for search, bid and buyout. Selling is done in Blizzard's own auction house window (1.4.0).
* A per-character **Crafting List** of items to buy for your crafts.

Every query, bid and buyout is triggered by your own click, and bids and buyouts ask you to confirm first. Nothing is automated: no loops, no auto-buying. The add-on never posts auctions.

## Install

1. Exit the game (or plan to `/reload` afterwards).
2. Copy the **`PhyzanCapital`** folder (the one that contains `PhyzanCapital.toc`) into
   `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\`
   so that you end up with `...\Interface\AddOns\PhyzanCapital\PhyzanCapital.toc`.
   Create the `AddOns` folder if it doesn't exist.
3. Start the game. On the character screen, open **AddOns** and make sure **Phyzan Capital** is enabled.
   If it shows as "out of date", tick **Load out of date AddOns**.

## Usage

| Command | What it does |
|---|---|
| `/capital` | Open or close the window (aliases: `/pc`, `/ahl`) |
| `/capital help` | Show the command list in a window (and in chat) |
| `/capital feedback` | Show where to send suggestions and bug reports (1.4.2), with a line to paste into reports |
| `/capital search\|prices\|buy\|market\|craftlist\|professions\|settings` | Open a tab (`crafts` still works for Professions; away from the AH `search` opens Price Lookup) |
| `/capital price <item name>` | Print the last known auction price of an item in chat, anywhere (part of the name is enough, any case) |
| `/capital profs` | Show the detected level and professions |
| `/capital refresh` | Detect level and professions again right now |
| `/capital status` | Show a summary of scans and data |
| `/capital debug` | Print which auction API this client has and which backend is in use. Also saved to `PhyzanCapitalDB.debug` (`/reload` writes it to disk) |
| `/capital backend auto\|modern\|legacy` | Force an auction API backend (default `auto`) |
| `/capital craftlist` (or `/capital list`) / `/capital list clear` | Open the Crafting List / clear it (asks Yes/No). The old `/capital shopping` still works |
| `/capital vendors` / `/capital vendors reset` | List vendors seen in game and those marked "not here" / clear all "not here" marks |
| `/capital textsize <1-3>` | Set the size of all Phyzan Capital text, e.g. `1.5` or `2` (default 1 for new installs since 1.4.2, 2 before; steps of 0.25). Applied immediately |
| `/capital autoopen on\|off` | Open the window automatically when the auction house opens (default on) |
| `/capital hideblizzard on\|off` | Make Blizzard's auction window invisible while ours is open (default on) |
| `/capital setcap N` | Set the maximum number of raw listing rows kept (default 250000) |
| `/capital reset` | Wipe scans, stats, vendor prices and recipes after a Yes/No (settings, characters, the Crafting List, vendors seen in game and "not here" marks are kept) |

The window fills the screen. Close it with the **X** in the top-right corner or with **Escape**. Escape also closes the auction house, the same way it closes other game windows.

**Tabs**
* **Search / Browse**: name, level range, quality and usable filters, with Prev/Next paging. Each result shows bid, buyout, per-unit price, how it compares with the market, time left and seller. Click a row to select it (on the modern auction house this opens its auctions on Buy), then use **Bid (minimum)…** or **Buy out…**. A confirmation dialog shows the total cost. Since 1.4.0 the click also asks **"Add <item> to crafting list?"** (see Crafting List).
* **Buy**: details of the selected auction, a custom bid amount (for example `1g20s`), market comparisons, and other listings of the same item.
* **Market**: every item in your latest complete scan, with listings, quantity, lowest per-unit buyout, today's median and average, vendor sell price and vendor buy price. Click a column header to sort. Since 1.4.1 a category tree on the left (the auction house's Browse categories, see *Market categories*) filters the list, and clicking an item asks "Add <item> to crafting list?".
* **Crafting List**: see below.
* **Professions** (1.2.6, replaces Profitable Crafts): the recipes you know, per profession. Each recipe shows the reagent cost, what the product sells for after the AH cut, profit and margin; profitable recipes come first and are highlighted green. Click a recipe to see each reagent with quantity, the cheapest current price (lower of the latest AH price and the vendor price, and which one), AH and vendor prices; click a reagent for "Add <item> to crafting list?". Recipes come from your profession window (recorded when you open it). Until a profession has been opened, the bundled trainer recipes up to your skill are shown as "probably known - open your profession window to confirm". Gathering skills (Skinning, Fishing, Herbalism, Mining without smelting) are listed as a note. The header shows the scan age, a warning when prices are old, and how many recipes miss a price. **Also show profitable recipes you could learn** adds the old Profitable Crafts list (recipe items / trainer recipes you don't know yet). **Available on AH** (1.3.1, the one place the add-on shows auction volume) is the total quantity of the product listed on this auction house in the latest complete scan: every listing's quantity added up, so a commodity counts units and gear counts one per item, each item being its own auction. The detail line adds the number of listings when that differs. Each reagent has the same column. "0" means the item was scanned and nothing is listed; "no scan" means this auction house hasn't been scanned yet. The numbers come from the saved scan summary (`ah[realm-faction].current[item].qty`), so they also show away from the auction house. The header gives the scan age and type: a full scan adds up all listings, while a browse scan uses the server's total per item. It also mentions a newer scan that didn't finish, because unfinished scans are never used. The recipe and reagent lists sort by any column when you click its header, including Available (click again to reverse). When "Available on AH" doesn't fit the column at large text sizes, the header reads "On AH", with the full title in its tooltip.
* **Settings**: the detected level and professions with a **Refresh** button (and **Clear manual overrides** when any are set), plus options (including **Hide seasonal vendors**), data status, and the most-used views. The window header always shows the detected character, level and professions.

* **Price Lookup** (1.2.7, works anywhere): `/capital` away from the auction house opens it (it sits under the Search tab button; at the AH, use **Price lookup (saved scans)** on the Search tab or `/capital prices`). Type part of an item name, any case, and press Enter (it also searches as you type from 3 letters). Every item with a saved price or a known name (client cache, bundled item names) is found; priced items come first. The selected item shows **"Last known price (scanned <age> ago)"**, the lowest buyout per unit, the scan date and time with its market day (7:00 AM - 6:59 AM next day) and auction house, a typical price (today's median, else the latest daily median, else the median of the daily lows), the vendor buy and sell prices and a short history (lowest buyout per market day, last 14 days). Listing counts are kept internally but not shown. Clicking a result also asks "Add <item> to crafting list?". **Search at the AH** is disabled away from the AH and explains "Buying requires being at the auction house."

The Search and Buy tabs show "Buying requires being at the auction house" (with a pointer to Price Lookup) when you are away from an auctioneer. The analysis tabs always work.

**Scanning.** Open the auction house and click **Scan Auction House**, in the window's top bar or on Blizzard's AH frame.
* The status panel under the tabs shows idle, scanning (rows read of total and %, or page N of M), *Scan complete* with time, rows and unique items, or *incomplete/failed* with the reason. A sound plays and a chat line is printed when a scan ends.
* The header always shows "Last scan: <time ago>, N items". Analysis tabs warn when there is no scan yet or the last one is more than 2 hours old.
* Left-click: full scan if allowed, otherwise the first page of a paged scan. Keep clicking to read each further page.
* Shift-click: force a paged scan.
* Right-click: abort. Partial scans are saved raw but are not used for stats.
* A scan never fails silently. Every chunk of rows and the final save are protected: an error marks the scan *failed* with the row index and message, and the scanner returns to idle instead of staying in "reading". It also prints `Scan complete: N auctions, M unique items` on success. If no auction API is usable, or a call errors or times out, the status panel shows *failed* with the reason, a chat line explains it, and the failure sound plays. Run `/capital debug` to see what the client offers.

**Auction API backends** (`ns.Backend()`, picked each time it's used):
* **modern**: used when `C_AuctionHouse.ReplicateItems` or `C_AuctionHouse.SendBrowseQuery` exists, which is the case for WoW Forever's retail-based UI (`AuctionHouseFrame`).
  * *Full scan*: a click calls `ReplicateItems()`. On `REPLICATE_ITEM_LIST_UPDATE` the addon reads `GetReplicateItemInfo(0..n-1)` plus `GetReplicateItemTimeLeft` and `GetReplicateItemLink` in chunks across frames. Rows whose item data isn't loaded yet (`hasAllInfo=false`) are still recorded by itemID, and their item data is requested. The server throttles full scans to about one per 15 minutes. `REPLICATE_ITEM_LIST_UPDATE` can fire before the data is there. The addon re-checks the count on every update and polls every 2 s (a read, not a query) for up to 60 s. Reading starts once the count is above 0 and steady. A count that stays 0 is reported as *failed: server returned 0 auctions*, and no update at all as *throttled?*. A scan is never marked complete with 0 rows.
  * *Browse scan*: used within 15 minutes of the last full scan, on Shift-click, or when `ReplicateItems` is missing. It runs `SendBrowseQuery` with an empty search and stores one row per item: the lowest unit price and the total quantity. Click **Scan more** for the next batch (`RequestMoreBrowseResults`) until `HasFullBrowseResults()`. These scans are flagged `aggregated=true`, update current prices only, and are left out of daily stats and the sales estimate.
  * *Search / Buy*: the Search tab uses `SendBrowseQuery`, with one row per item and **Next >** loading more. Clicking an item runs `SendSearchQuery` and opens its auctions on the Buy tab.
    * Items: bid and buyout go through `PlaceBid(auctionID, amount)`.
    * Commodities: enter a quantity and click **Buy quantity…**. `StartCommoditiesPurchase` gets a server price quote, and a confirmation dialog then calls `ConfirmCommoditiesPurchase`, or `CancelCommoditiesPurchase` if you cancel.
* **legacy**: used when `QueryAuctionItems` exists and there's no modern API. Full "getAll" scan when the server allows it, otherwise one page per click, plus the classic search and bid calls.



## Crafting List (1.2.2; called "Shopping List" before 1.4.0)

This is a per-character list of items to buy for your crafts. Open it from the **Crafting List** tab (short name "List"), with `/capital craftlist` (`/capital list` and the old `/capital shopping` also work), or with **Open Crafting List** in the top bar. That button and **Clear Crafting List** appear while the auction house is open (at large text sizes they read "Crafting List" / "Clear List"). Two smaller copies sit on Blizzard's auction frame when that frame is visible. Clearing always asks Yes/No first, including `/capital list clear`.

* **Adding an item.** Every add asks a Yes/No question in our own dialog (large text, sized to its content) with a quantity box:
  * Professions tab: click a reagent ("Add <item> to crafting list?", quantity = the amount per craft);
  * Search / Browse results and Price Lookup results (1.4.0): clicking a result does what it always did (select it, open its auctions on Buy) and also asks "Add <item> to crafting list?" (quantity 1). It shows the closest vendor and price, or "not sold by a known vendor - buy it on the auction house", and the AH price.
  * An item that's already on the list doesn't get a second entry: the question says "<item> is already on your crafting list (N of M bought). Add more?" and Yes adds the typed amount to its quantity.
  * The question never gets in the way of buying: it is not shown while a bid/buyout/purchase question is open, and a buy question replaces it (= No).
* **An entry saves:**
  * the closest friendly vendor at that moment (NPC, name, zone, map coordinates);
  * the vendor unit price, the AH lowest price and the margin at that time;
  * the time it was added and the quantity (minimum 1).
* **List columns:**
  * item (icon, quality colour);
  * quantity bought / quantity to buy;
  * the stored vendor, with zone and current distance (re-read when you open the tab or change zone, at most once every 3 s);
  * vendor price, current AH lowest price (latest scan), and current margin after the cut;
  * **Map** ("See vendor on map?": **Yes** pins that vendor and opens the map; a vendor without coordinates gets an OK-only message), **Not here** and **Remove** buttons.
* The bottom line shows the **total vendor cost** for what's left to buy and the **estimated profit** at current AH prices.
* To change a quantity, click a row, type the new number and click **Set**. It must be 1 or more.
* **Buying counts down automatically.** While a merchant window is open, bag-count increases of a listed item (`GetItemCount`, checked on `BAG_UPDATE`) are counted. They only count if they come right after a `BuyMerchantItem` call for that item, which is watched with a post-hook (`hooksecurefunc`). Loot and mail don't count. A chat line shows progress. When the bought quantity reaches the listed quantity, the item is marked purchased, removed, and a chat line is printed. If the hook API is missing, any increase while the merchant is open counts.
* When a merchant that sells a listed item opens, chat shows `Crafting list: this vendor sells X (need N)`.
* Nothing is ever bought for you. The hook only records which listed item *you* bought.
* **Closest vendor**: your position (`C_Map.GetBestMapForUnit` + `GetPlayerMapPosition`) and each vendor's spawn are converted to world yards the same way. Vendors hostile to your faction are never picked. Ranking is same zone, then same continent by distance, then other continents, then vendors without coordinates. A regular vendor is preferred over a seasonal one; **Hide seasonal vendors** (Settings) ignores seasonal ones entirely. The map pin is a single game waypoint (`C_Map.SetUserWaypoint`; the protected `C_SuperTrack` call is not used); another vendor replaces it, and a waypoint you placed yourself is never removed.
* Saved data: the key is still `PhyzanCapitalDB.shopping` / `shoppingLog`, so lists from earlier versions carry over unchanged.

## Vendors seen in game and "Vendor not here" (1.2.3)

The bundled vendor data comes from server databases, which can disagree with this client. Phyzan Capital corrects it from what you see in game:

* **Seen in game.** When a merchant window opens (`MERCHANT_SHOW`, read 0.5 s later), the addon records:
  * the NPC id from `UnitGUID("npc")` (`Creature-0-…-<npcID>-…`) and its name;
  * your `uiMapID` and position as the vendor's location;
  * every item it sells, with the per-unit price.
* **Seen data wins.** For that vendor, the observed location and inventory replace the bundled ones.
  * The map pin, distances and "closest" use where you actually saw it.
  * Items it sells that the bundle doesn't know are added.
  * Items the bundle says it sells but it didn't sell when you visited are flagged "[not sold here when you visited]" and never picked as closest. Chat shows how many there were.
  * The flag is only set from a complete read (every item link loaded).
* **Vendor not here.** If a vendor isn't where the addon says, mark it. The mark is saved per client (`vendorMissing`). You can do this from:
  * the third button on the "See vendor on map?" dialog (and the no-coordinates dialog);
  * the **Not here** button on Crafting List rows.
* **What a mark does.** Each mark asks Yes/No first. The vendor is then tagged "[marked not here]" and dropped from "closest", and the next closest vendor is picked:
  * the map dialog asks again for the new vendor;
  * Crafting List entries that used the vendor are moved to the new vendor.
* **Undoing marks.** `/capital vendors reset` clears all marks, and `/capital vendors` lists them.
* **Seen vendors are never "missing".** A vendor seen at a merchant window can't be marked; the addon says when you saw it, and none of the "not here" options are offered for it. Opening a marked vendor's merchant window removes its mark.

## Text size (1.2.2)

All Phyzan Capital text is 1x by default for new installs since 1.4.2 (it was **2x** before; a saved setting is kept). You can change this from 1.0x to 3.0x in steps of 0.25, using the *Text size* slider on Settings (applied when you release it, or use the − / + buttons) or with `/capital textsize <n>`.

* The addon creates its own font objects (`PhyzanCapitalFont_<BlizzardFont>`, via `CreateFont`). Each one copies the Blizzard font (file, outline flags and colour) and sets its size to the original size times the scale. Every label, list cell, edit box, button and our confirmation dialog uses these fonts.
* **Confirmation dialog (1.2.3).** Blizzard's StaticPopup sizes itself from its own font, so it can't hold our larger text. Every question therefore uses Phyzan Capital's own dialog: map, crafting list add/clear, bid, buyout, commodity purchase, reset, and the OK-only "no coordinates" message.
  * The dialog measures its text. Width is the widest line plus padding, clamped between 320 × scale and 80% of the screen width. The message word-wraps at that width and is measured again.
  * Height is title + message + quantity box (if any) + button row + padding. If that would be taller than the screen, the message drops one font size.
  * Buttons are sized to their labels.
  * Enter = Yes and Escape = No. Asking a new question cancels the open one (= No).
  * Bids, buyouts and commodity purchases are called directly inside the Yes click (or the Enter key), so they keep the hardware event.
  * "Add <item> to crafting list?" shows an editable quantity box in the dialog.
* The window is never `SetScale`d, so it stays exactly full-screen. Row heights, button, check box and icon sizes, offsets and scroll steps scale with the text. When the text size changes, the window is rebuilt.
* Layout adapts to the space available:
  * List columns stretch to the full window width. Text that doesn't fit ends in "…", and hovering the row shows the full text (headers too).
  * Controls wrap onto extra lines.
  * Tabs use short names ("Search", "List", "Profs") when the full names don't fit on one line.
  * Long forms scroll with the mouse wheel: Settings and the top of the Search and Buy tabs.
  * Notes are one line, with the full text on hover.
* Checked off-game: `tools/test_addon.lua` builds every tab at 1x, 2x and 3x on 1365×768 and 1920×1080 UI sizes. The test fails if any element goes off screen or outside its scroll area, overlaps another control or label, uses a font that isn't ours or is smaller than base × scale, or has a button label wider than its button. It also fails if a list's columns are wider than the list, rows are shorter than their font, fewer than 2 rows are visible, or the tab buttons are not evenly spaced (1.4.0).
* Blizzard's own frames (the auction house, the game tooltip, the extra Scan button on Blizzard's AH frame) keep their normal size.

## Character detection

Level and professions are detected per character (key `Name-Realm`), with no manual entry:

* **Level** comes from `UnitLevel("player")`. It's refreshed on login, on entering the world, and on `PLAYER_LEVEL_UP`, using the new level from the event.
* **Professions and skill ranks** are read from `GetProfessions()`/`GetProfessionInfo()` if the client has them, matched by skillLineID. Otherwise they come from the classic skills pane (`GetNumSkillLines`/`GetSkillLineInfo`): collapsed headers are expanded for the read and collapsed again afterwards. Rank and max rank are stored for primary professions, gathering skills, Cooking, First Aid and Fishing.
* Detection runs again on `SKILL_LINES_CHANGED`, `CHAT_MSG_SKILL` (skill-ups), `TRADE_SKILL_SHOW/UPDATE/LIST_UPDATE` and `CRAFT_SHOW`. An open profession window also updates its own rank directly: `C_TradeSkillUI.GetBaseProfessionInfo` on WoW Forever, `GetTradeSkillLine`/`GetCraftDisplaySkillLine` on old clients. Recipes are recorded from `C_TradeSkillUI.GetAllRecipeIDs`/`GetRecipeSchematic` (learned recipes, basic reagents; linked or guild windows are ignored).
* **Name matching**: skillLineID where the client provides it, otherwise English names. On other client languages, the localized names of the profession spells (`C_Spell.GetSpellName`, or `GetSpellInfo` on old clients) are used too.
* Recipe tiers follow the level: Journeyman needs 10, Expert 20, Artisan 35.

Hidden manual overrides still exist for unusual cases: `/capital setlevel N` and `/capital setprof <profession> <skill>` (a skill of 0 removes it). They apply to the current character only and win over detection until you run `/capital clearoverride` or press **Clear manual overrides** on the Settings tab.

## How the numbers work

* **Daily stats.** The first complete scan of a market day counts every listing. Later scans that day add only listings that weren't in the previous scan. That gives "listings seen" and "quantity seen", plus per-unit buyout min, median, average and max, and a time-left distribution. The median comes from up to 200 unique listings per item per day.
* **Estimated sales (SavedVariables only, not shown in game; an estimate, not real data).** An auction in the previous complete scan that is missing from the next one counts as:
  * a **probable sale** if less time passed between the scans than the minimum it had left (Short < 30m, Medium 30m–2h, Long 2–8h, Very Long 8–24h);
  * **won by a bid** if it vanished inside its expiry window while carrying a bid;
  * **expired** otherwise.

  Cancelled auctions look like sales. Auctions are identified by item, stack, bid, buyout and seller, since the client gives no auction ID. Scans more than 48h apart aren't compared.
* **Vendor buy prices** come from the bundled vendor database. They are replaced by what you record when you open a merchant (that price includes your reputation discount).
* **Craft cost** uses the cheaper of the AH price and the vendor price for each reagent. The product's value is its lowest current AH buyout (or today's median) after the AH cut. The deposit isn't included.

## Bundled data and sources

* `Data/Recipes.lua`: 1,133 vanilla profession recipes (Alchemy, Blacksmithing, Enchanting items, Engineering, Leatherworking, Tailoring, Cooking, First Aid, Smelting). Each has its product, yield, reagents, yellow and grey skill levels, and the required skill and recipe item when learned from a recipe item (728 recipes). Generated by `tools/build_data.py` from Blizzard's own Classic Era client tables (SkillLineAbility, SpellEffect, SpellReagents, SpellName, ItemSparse, ItemEffect) as CSV from wago.tools (`https://wago.tools/db2/<Table>/csv?branch=wow_classic_era`). Season of Discovery content is excluded by ID range.
  * Trainer recipes don't store their required skill in the client data. For those, the window uses the recipe's yellow level, which is a conservative cutoff, and marks it `~`.
* `Data/Vendors.lua` (generated 2026-10-17, about 148 KB): **1,895 vendor-sold items and 953 vendors** across 44 zones. For each item it stores the per-unit buy price and every NPC that sells it, with a limited-stock flag. For each NPC it stores the name, main zone, faction (A, H or AH) and **main spawn coordinates** (896 of 953 vendors have them).
  * Coordinates: pfQuest `db/units.lua` coords (the first spawn in the NPC's main zone, in percent of the zone map).
  * Zone → uiMapID (all 44 zones) and the zone's world bounds come from Blizzard's Classic Era **UiMapAssignment** / **UiMap** tables (wago.tools). The build checks Stormwind 1453, Ironforge 1455, Orgrimmar 1454 and Elwynn Forest 1429. Spot checks: Tharynn Bouden, Elwynn Forest 41.8, 67.2 (Goldshire); Amy Davenport, Redridge 29.1, 47.3 (Lakeshire).
  * Vendor lists, NPC names, zones, factions and limited stock come from the **pfQuest** database (github.com/shagu/pfQuest, `db/items.lua` "V" entries, `db/units.lua`, `db/enUS/*`), which is derived from the VMaNGOS vanilla world database. They're extracted by `tools/extract_pfquest.lua`.
  * Prices come from Blizzard's Classic Era **ItemSparse** table (wago.tools). The per-unit price is `BuyPrice / VendorStackCount`, so packs are handled: Empty Vial is 20c per 5, so 4c each. 133 items are sold in packs.
  * 36 items pfQuest lists without a Blizzard buy price were dropped. As a cross-check, 1,744 of the 1,895 items are also vendor items in the cmangos classic-db `npc_vendor`/`npc_vendor_template` tables.
  * Seasonal tags (`ns.VendorSeasonal`, 70 vendors, rebuilt 2026-10-17) come from the cmangos classic-db dump (`Full_DB/ClassicDB_1_12_1_*.sql`). A vendor is tagged in three cases:
    1. every one of its spawns is in `game_event_creature` for a positive event (spawns come from `creature`, plus `creature_spawn_entry` for random-entry spawns); the name comes from `game_event`;
    2. it only exists through `game_event_creature_data` (an event that turns another spawn into this NPC);
    3. it has **no spawn at all**. If its `creature_template` subname mentions a holiday it is tagged "<subname> (holiday only, no permanent spawn)", otherwise "no world spawn known (may not exist on this server)". Case 3 covers 47 vendors, e.g. `[UNUSED]` NPCs, test vendors, Vendor-Tron 1000 and Field Repair Bot.
  * **Fix in 1.2.3.** The old rule only looked at spawns linked to events, so a vendor with no spawns at all was never tagged. That is why the Red Fireworks Rocket pin pointed at Wizbang Booms (8117, `<Holiday Fireworks Vendor>`). cmangos has no spawn for him, and neither for 8116 Ziggle Sparks, 8118 Lillian Singh, 8121 Jaxxil Sparks or 8122 Kizzak Sparks. pfQuest (VMaNGOS) still gives them a position. All five are now tagged.
    * Red Fireworks Rocket (5740) is also sold by regular vendors (1304 Darian Singh, 2838, 3180, and 5569 Fizzlebang Booms in Ironforge, who has a permanent spawn), so one of those is now the closest.
    * The cmangos dump doesn't say which holiday the fireworks vendors belong to, so the tag doesn't name one.
  * Vendors whose pfQuest faction is empty (Darkmoon Faire, some neutral NPCs) count as friendly.
  * Built by `tools/build_vendors.py` (pass the cmangos `.sql` as the 4th argument to get the seasonal tags).
* `Data/ItemNames.lua` (generated 2026-10-17, about 134 KB): English name and quality for **all 3,666 items** referenced by the vendor and recipe data, from Blizzard Classic Era **ItemSparse** (`Display_lang`, `OverallQualityID`). These names are used only until the client sends live item info. Built by `tools/build_itemnames.py`.

**Item names.** Names come from `PhyzanCapitalDB.items`, then live client data (`C_Item.GetItemNameByID` / `C_Item.GetItemInfo`), then the bundled names. If none of those has it, the item shows as `Item #<id> (loading…)`. Unknown items are requested with `C_Item.RequestLoadItemDataByID` (or `Item:ContinueOnItemLoad`). When `GET_ITEM_INFO_RECEIVED` / `ITEM_DATA_LOAD_RESULT` arrives, the name, quality and icon are cached and the open window refreshes, at most once per second. Replicate rows report quality -1 for unloaded items, and that value is ignored.

## Analysing the data off-game

The game writes `World of Warcraft\_classic_beta_\WTF\Account\<ACCOUNT>\SavedVariables\PhyzanCapital.lua` on `/reload`, logout or exit.

```
python3 tools/parse_sv.py PhyzanCapital.lua --sqlite capital.db --csv capital_csv
python3 tools/parse_sv.py --self-test            # built-in test with a synthetic sample
```

Output tables: `scans`, `listings`, `daily_item_stats`, `est_sales`, `current_prices`, `vendor_prices`, `recipes`, `recipe_reagents`, `items`, `usage`, `characters`, `char_professions`, `overrides`, `shopping_list` (the Crafting List), `shopping_log`, `observed_vendors`, `observed_vendor_items`, `vendor_missing`, `debug`, `meta`. The script uses only the Python standard library.

## SavedVariables schema (`PhyzanCapitalDB`, schemaVersion 8)

v8 changes (1.4.0) drop `postLog` and the settings `undercut`, `durationMode`, `defaultDuration`, `swapsOnlyProfitable` and `postMode` (plus `debug.directPostBlocked` / `debug.postMode`). The Crafting List keeps the `shopping` / `shoppingLog` keys, so every entry survives unchanged. Old `usage` keys such as `tab:sell` / `tab:swaps` stay as history.

v5 changes (1.2.3) add two new tables, `observedVendors` and `vendorMissing`, and an `npc` field in `vendorPrices`. Nothing is converted.

v4 changes (1.2.2) add two new tables, `shopping` and `shoppingLog`, and the `settings.textScale` setting. Nothing is converted.

v3 changes: `scans[].aggregated`, `scans[].mode` can be `replicate`/`browse`, plus `lastReplicateTs`, `debug` and `settings.backend`. The usage key `tab:flips` was renamed to `tab:swaps` (old counts are merged).

All money values are in copper. Times are Unix seconds from the game's `time()`. A market day is `"YYYY-MM-DD"`, the date the 07:00 window started. `ahKey` is `"<realm>-<Alliance|Horde|Neutral>"`.

| Field | Shape | Meaning |
|---|---|---|
| `schemaVersion` | number | Bumped on any breaking change. Migrations live in `ns.InitDB` |
| `addonVersion`, `createdAt` | string, number | |
| `settings` | table | `backend("auto"/"modern"/"legacy"), textScale(1.0 for new installs since 1.4.2, 2.0 before; 1.0-3.0, added in 1.2.2, no schema change), hideSeasonalVendors, dayStartHour(7), keepSnapshotDays(14), maxSnapshotRows(250000), keepStatsDays(120), autoOpen, hideBlizzardAH`; 1.4.1 (no schema change): `marketCategory` (selected Market category path such as `"Armor/Cloth/Chest"`, `""` = All), `marketOpen` (whether it shows its subcategories), `showCommands` (command list when the AH opens, default on) |
| `chars["Name-Realm"]` | `{level, lastDetect, lastReason, professions = {[prof] = {rank, max, source, ts}}}` | Detected per character. `prof` is the English name, `source` is `GetProfessionInfo`, `skills pane`, `tradeskill window` or `craft window` |
| `overrides["Name-Realm"]` | `{level, professions = {[prof] = skill}}` | Hidden manual overrides (v1's global `professions` is migrated here for the first character that logs in) |
| `items` | `[itemID] = {name, quality, icon, sellPrice, stack, classID, subClassID, invType, equipLoc}` | Item cache. Names, quality and icon are filled in as the client loads item data. 1.4.1: `classID`, `subClassID`, `invType` (inventory type 0-28) and `equipLoc` (`INVTYPE_*`) from `C_Item.GetItemInfoInstant`, for the Market categories (items classified from the bundled map are not stored) |
| `categoryTree` | `{ts, build, tree = {name, filters = {{classID, subClassID, inventoryType}}, sub = {...}}}` | 1.4.1. Plain copy of the client's `AuctionCategories` (Browse list), taken when Blizzard's auction house UI is loaded; used for the Market tree from then on, also away from the AH. `debug.categoryDiff` counts the names that differ from the bundled copy |
| `scans` | array of `{id, ts, endTs, day, ahKey, char, mode("getAll"/"paged"/"replicate"/"browse"), complete, rows, items (unique), skipped, reason (if incomplete), pruned, comparedTo, estSold, estExpired, estSkipped, aggregated}` | One per scan. `aggregated=true` (browse scans): each snapshot row is one item with `count` = total quantity, `buyout`/`unitBuyout` = lowest unit price, `timeLeft` 1 and an empty seller |
| `snapshots` | `[scanID] = { "itemID\|count\|minBid\|buyout\|unitBuyout\|timeLeft\|seller\|bidAmount", ... }` | Raw listings, one string each. `timeLeft` is 1–4 (Short/Medium/Long/Very Long) and `buyout` 0 means none. Kept for the last 14 market days, and at most `maxSnapshotRows` rows in total (oldest scans dropped first; scan metadata stays with `pruned=true`) |
| `ah[ahKey].dailyStats[day][itemID]` | `{listings, quantity, pricedListings, noBuyout, minUnit, maxUnit, avgUnit, medianUnit, sumUnit, tl1, tl2, tl3, tl4, scans}` | Per item per market day |
| `ah[ahKey].estSales[day][itemID]` | `{sold, soldQty, soldValue, bidWon, bidWonQty, expired, expiredQty}` | **Estimated**, see above |
| `ah[ahKey].current[itemID]` | `{minUnit, n, qty, scanID, ts, cheapest="unit:count,..."}` | Latest complete scan (10 cheapest listings) |
| `ah[ahKey].priceSamples[day][itemID]` | array of unit prices | Used for the median. Only today and yesterday are kept |
| `ah[ahKey].lastKnown[itemID]` | `{u = lowest unit buyout, t = scan time, n = listings, q = quantity}` | 1.2.7, schema 6. Last known price for the offline lookup; updated by every complete scan (full or browse), and an item missing from the newest scan keeps its last price. One small row per item, never pruned |
| `ah[ahKey].history[itemID]` | `"YYYY-MM-DD:low:median;..."` | 1.2.7. One entry per market day (lowest buyout that day, and the median for full scans), last 14 market days. Filled once from older `dailyStats` / `current` data when 1.2.7 first loads |
| `vendorPrices[itemID]` | `{unit, stackPrice, stack, name, merchant, npc (1.2.3), zone, limited, ts, uiMapID, x, y}` (x, y = your position when you recorded the merchant, 0–100) | Recorded at merchants (overrides the bundled database) |
| `recipes["Prof:productItemID"]` | `{prof, product, name, minMade, maxMade, reagents="id:count;id:count", difficulty, knownBy="Char-Realm,...", incomplete, ts}` | Recorded from profession windows |
| `usage[key]`, `usageLast[key]` | count, last time | Query log. Keys are `tab:<name>`, `cmd:<subcommand>`, `action:search/bid/buyout` (`post` in versions before 1.4.0), `scan:click`, `settings:*` |
| `shopping["Name-Realm"][itemID]` | `{itemID, name, qty, bought, vendorNpc, vendorName, vendorZone, vendorFaction, vendorLimited, vendorSeasonal, uiMapID, x, y, vendorUnit, vendorSrc("recorded"/"bundled"), ahUnit, margin, ahKey, added, updated}` | Crafting List (key name kept from when it was the Shopping List). `ahUnit`/`margin` are the values when added. `x`, `y` are 0–100 on `uiMapID` |
| `shoppingLog` | array of `{char, itemID, qty, bought, vendorUnit, ahUnit, margin, added, removed, reason("purchased"/"removed by you"/...)}` | Entries taken off the Crafting List (last 500) |
| `observedVendors[key]` | `{npc, name, zone, uiMapID, x, y, firstSeen, seen, complete, itemCount, bundledNotSold, items = {[itemID] = unitPrice (0 = not for gold)}}` | Merchants seen in game. `key` is the NPC id (or `"name:<name>"` if the GUID couldn't be read). Overrides bundled location and inventory |
| `vendorMissing[key]` | `{npc, name, zone, itemID, ts}` | "Vendor not here" marks (same key). Cleared by `/capital vendors reset` or by seeing the vendor |
| `nextScanID` | number | |
| `lastReplicateTs` | number | Time of the last `ReplicateItems` request (modern backend), used to respect the ~15 min throttle |
| `debug` | table | Diagnostics that survive `/reload`. `lastScan = {ts, startTs, mode, result(complete/incomplete/failed), reason, total, rows, missing, items, backend}`, `lastScanID`, `lastError = {ts, where, msg, index (row), mode, total}`, `errorCount`, and `replicate = {requestTs, events, lastCount, checks}` are updated automatically. The last `/capital debug` output is merged in: `ts, addonVersion, backend, backendSetting, ahOpen, build, buildNumber, interface`, and a true/false for each API (`QueryAuctionItems, CanSendAuctionQuery, C_AuctionHouse, ReplicateItems, SendBrowseQuery, PlaceBid, PostItem, PostCommodity, GetProfessions, AuctionHouseFrame, ...`), plus `scannerState, lastScanResult`. `blocked` (last 20) records `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` / `MACRO_ACTION_*` events |

## Files

```
PhyzanCapital.toc      Interface 16001, SavedVariables PhyzanCapitalDB
Core.lua               namespace, SavedVariables init/migration, helpers, events, /capital commands
Character.lua          level/profession detection per character, hidden overrides
Ledger.lua             snapshots, daily stats, sales estimate, pruning
Scanner.lua            Scan button/status, chunked reader, legacy getAll/paged scan, backend dispatch
VendorPrices.lua       merchant price recording, vendor lookup
Professions.lua        tradeskill/craft recording, recipe book with reagent costs and profit
ProfessionsTab.lua     Professions tab (known recipes, reagents, crafting list)
UI.lua                 full-screen window, status panel, sortable list widget, Market/Settings tabs
Trade.lua              Search/Browse and Buy tabs, confirmation dialogs
Data/Recipes.lua       bundled recipes (generated)
Data/Vendors.lua       bundled world vendor database (generated)
ShoppingList.lua       Crafting List tab, "Add to crafting list?" questions, purchase tracking at merchants
Items.lua              item names/quality/icons: cache, live lookup, bundled fallback, load requests
LICENSE, CHANGELOG.md, README.md, THIRD_PARTY_NOTICES.md   shipped in the release zip
DEVELOPMENT.md         these notes (dev only)
Categories.lua         Market categories: copy of the AH Browse tree (Camelot/Forever), item classification, counts
Data/ItemClasses.lua   bundled class / subclass / inventory type of all 31,824 Forever items (generated)
Map.lua                closest-vendor ranking, "See vendor on map?" question, single map pin (waypoint or fallback texture)
Data/ItemNames.lua     bundled item names (generated)
Lookup.lua             offline Price Lookup page and /capital price
ModernAH.lua           modern C_AuctionHouse backend: ReplicateItems/browse scans, search, drill-down, bids, commodity purchases
tools/extract_pfquest.lua, tools/build_vendors.py   regenerate Data/Vendors.lua
tools/build_itemnames.py                            regenerate Data/ItemNames.lua
tools/build_itemclasses.py                          regenerate Data/ItemClasses.lua from wago.tools Item.csv (wowf)
tools/parse_sv.py      SavedVariables -> SQLite/CSV
tools/build_data.py    regenerates Data/*.lua from the wago.tools CSV exports
tools/build_release.sh builds release/PhyzanCapital-<version>.zip (player files only) and checks it
tools/test_addon.lua   off-game smoke test with a mocked WoW API (lua5.1 tools/test_addon.lua)
tools/mock_geometry.lua  anchors, sizes and text metrics for the mock (layout audit at 1x/2x/3x)
```

## WoW Forever API (1.2.5)

WoW Forever runs the modern (Mainline) client API. The classic globals `GetItemInfo`, `GetItemIcon`, `GetItemInfoInstant`, `GetItemCount`, `GetSpellInfo`, `GetContainer*`, `GetMerchantItemInfo`, `GetTradeSkill*`, `GetCraft*` and `GetSkillLineInfo` don't exist there. All calls go through wrappers in Core.lua (`ns.GetItemInfo`, `ns.ItemIcon`, `ns.ItemCount`, `ns.SpellName`, `ns.BagItem`, ...) that use `C_Item`, `C_Spell`, `C_Container`, `C_MerchantFrame` and `C_TradeSkillUI` first and the old global only if it exists. Secret values (`issecretvalue`) are never stored. `SetPropagateKeyboardInput` is not called in combat, and the protected `C_SuperTrack.SetSuperTrackedUserWaypoint` is not called at all. `tools/test_addon.lua` loads a second copy of the add-on in an environment with only the modern API to check this.

## Blizzard's auction house frame (1.2.6)

Phyzan Capital changes only two things on Blizzard's `AuctionHouseFrame` / `AuctionFrame`: its alpha (0 while our window is open with *Hide Blizzard's auction window* on; it is never hidden, because hiding it closes the AH) and three buttons parented to it (**Scan Auction House**, **Crafting List**, **Clear List**). It adds no tabs, hides no Blizzard panel and never changes Blizzard's tab or display mode. When our window closes (X, Escape or `/capital`), the alpha goes back to 1 and our three buttons are hidden, so the default AH looks and works as usual. An open auction confirmation is cancelled at the same time. The buttons are created once and reused, so reopening never duplicates them. They are only visible while our window is open with *Hide Blizzard's auction window* off.

## Selling (1.4.0)

The add-on no longer posts auctions. On WoW Forever 1.60.1 the game ignores `C_AuctionHouse.PostItem` / `PostCommodity` from add-on code (1.2.8 and 1.2.9 logged it), so the Sell / Post tab, the Blizzard handoff panel, the post log and `/capital postmode`, `undercut` and `durationmode` were removed. Sell in Blizzard's own auction house window: close ours with the X or `/capital` (Blizzard's window is restored; Escape closes the auction house too), or turn off *Hide Blizzard's auction window*. Phyzan Capital never touches Blizzard's sell frames (`SetPostItem`, `SetItem`, `SetDisplayMode`), so its Post button stays untainted.

`ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN` and `MACRO_ACTION_*` are still recorded in `PhyzanCapitalDB.debug.blocked` (last 20); a chat line is printed only when the game blames Phyzan Capital. `debug.addonVersion` is refreshed on every load, and `debug.scannerState` at logout.

## 1.4.2: Feedback and public release

* **Feedback button** in the top bar, left of *Scan Auction House*, on every tab (also the Search / Browse landing page and away from the AH). At very large text on a narrow screen (3x at 1365 wide) it moves to the right end of the status line under the title, so the tabs keep their space. It opens our dialog: "Send suggestions and bug reports to:", a read-only EditBox with `kingofthefallllc@gmail.com` already selected (typing puts it back and selects it again), "Press Ctrl+C to copy", and a report line `Phyzan Capital <version>, client <version> (build <n>), interface <n>, <locale>` (`ns.ReportLine()`), plus **Close** (Enter and Escape close it too). `/capital feedback` (also `bug`, `contact`) shows the same dialog and prints the address in chat. The game cannot open mail or web pages, so nothing is launched.
* The confirmation dialog learned `okText`, `edit.readOnly` and `footer` (text under the edit box) for this.
* **Command list popup**: lists `/capital feedback`. `/capital backend` and `/capital setcap` are troubleshooting commands and are only listed by `/capital help` in chat (`chatOnly`), so the popup fits at 2x on 1365x768.
* **Generalized for everyone**: nothing about the author's character is built in (the code never names a character, realm, account or path; tests use mock characters). New installs start at **1x** text (`textScale = 1.0`); a saved value is kept, so existing users keep their size. Neutral auction houses (Booty Bay, Gadgetzan, Everlook) are found by uiMapID (Stranglethorn Vale 1434, Tanaris 1446, Winterspring 1452, walking up from sub-maps with `C_Map.GetMapInfo`), so they also work on non-English clients; the English zone names remain a fallback.
* **First-run test**: the Forever test loads the add-on three more times with empty SavedVariables (deDE Horde level 60 without professions, frFR Alliance level 1 inside a neutral sub-zone, enUS Horde 33 with Mining). Each run checks the character, professions, AH key, defaults, the command list, every tab at and away from the AH, `/capital feedback`, `status`, `price`, and that no error reaches chat or `debug.lastError`.
* **Locale notes**: item names come from the client (any language) with English bundled names as a fallback; professions are matched by skill line ID; Market category names come from the client's own category list once Blizzard's AH UI has loaded (localized), else English. Bundled vendor names and zones are English. Text of the add-on itself is English only.

### Licence (1.4.2)

GPL-3.0-or-later (`LICENSE` = copyright header + standard notice + the official text from gnu.org). Chosen because the vendor data derives from VMaNGOS (GPL-2.0-or-later) and CMaNGOS classic-db (GPL-3.0); pfQuest's MIT notice is kept in `THIRD_PARTY_NOTICES.md`. Every add-on `.lua` file starts with `-- SPDX-License-Identifier: GPL-3.0-or-later`; the generated `Data/` files are covered by `LICENSE` and the notices.

### Release build (1.4.2)

`tools/build_release.sh` writes `/workspace/release/PhyzanCapital-<version>.zip` with one top-level folder `PhyzanCapital` and only what players need: the `.toc`, the Lua files the toc lists, `Data/*.lua`, `LICENSE`, `CHANGELOG.md`, `README.md` and `THIRD_PARTY_NOTICES.md`. Left out: `tools/` (tests, mocks, data builders), `.luacheckrc`, `DEVELOPMENT.md` and backups. The script fails if a toc file is missing, if anything else slips in, or if the versions in the toc, `Core.lua` and `CHANGELOG.md` differ. The developer zip (`/workspace/PhyzanCapital.zip`, everything) is still built with the usual command.

## 1.4.1: Market categories and the command list

**Market categories.** The Market tab has a category tree on the left, the same as the Browse list of the auction house. It is copied from the client's own `Blizzard_AuctionData.lua`: WoW Forever loads the *Camelot* version (`Interface/AddOns/Blizzard_AuctionHouseUI/Camelot/Blizzard_AuctionData.lua`, wow-ui-source branch for Forever 1.60.1) on top of the shared category code. Order, names and filters (class, subclass, inventory type) are the same. A category matches an item when any of its filters matches, and a parent has all its children's filters, as in Blizzard's code.

* **All** (every scanned item)
* **Weapons**: One-Handed (One-Handed Axes, One-Handed Maces, One-Handed Swords, Daggers, Fist Weapons, Wands), Two-Handed (Two-Handed Axes, Two-Handed Maces, Two-Handed Swords, Polearms, Staves), Ranged (Bows, Crossbows, Guns, Thrown), Miscellaneous (Fishing Pole, Other)
* **Armor**: Plate, Mail, Leather, Cloth (each: Head, Shoulder, Chest (robes included), Waist, Legs, Feet, Wrist, Hands, Relic), Relic (Idols, Librams, Totems), Miscellaneous (Neck, Cloak, Finger, Trinket, Held In Off-hand, Shields, Shirt)
* **Containers**: Regular Bags (Bag, Soul Bag), Ammo (Quiver, Ammo Pouch), Trade Bags (Herb Bag, Enchanting Bag, Engineering Bag, Mining Bag, Leatherworking Bag, Tackle Box, Cooking Bag, Reagent Bag)
* **Consumables**: Explosives, Potions, Elixirs, Flasks, Scrolls, Food & Drink, Bandages, Item Enhancements (Permanent, Temporary), Draughts, Devices, Other
* **Trade Goods**: Parts, Cloth, Leather, Metal & Stone, Cooking, Herb, Enchanting, Elemental, Other
* **Ammo**: Arrow, Bullet
* **Recipes**: Leatherworking, Tailoring, Engineering, Blacksmithing, Cooking, Alchemy, First Aid, Enchanting, Book
* **Quest Items**
* **Miscellaneous**: Junk, Reagent, Pet, Holiday, Other, Mount
* Only when needed: **Not in the auction house list** (items no category covers, e.g. keys) and **Not classified yet** (class data still loading).

Click a category to filter the list and open it, click it again to close it. Every row shows how many scanned items it holds (an item is counted once per row; a parent counts each item once). The selection is saved. The Market list keeps its columns and sorting; clicking an item asks "Add <item> to crafting list?" with a quantity, or "already on your crafting list, add more?".

Classification: the item cache (`items[id].classID`, ...), else `C_Item.GetItemInfoInstant` (class, subclass, equip slot, `C_Item.GetItemInventoryTypeByID`; saved in the cache), else the bundled map `Data/ItemClasses.lua` (wago.tools Item table for wowf 1.60.1.70245), else the item is requested and moves into its category on `GET_ITEM_INFO_RECEIVED`. Until Blizzard's auction UI has been loaded once, the bundled copy of the tree is used; afterwards the client's own `AuctionCategories` (saved in `categoryTree`). The WoW Token category is left out.

**Command list.** The first time Phyzan Capital opens on Search / Browse during an auction house visit, a window lists the slash commands with one line each. It closes with **OK**, Enter or Escape, and the keyboard goes back to the search box. A buy question replaces it; it never covers one. Tick **Don't show this when the auction house opens** to stop it (turn it back on in Settings, which also has a **Show commands** button). `/capital help` shows it any time. At 3x text on small screens the list scrolls with the mouse wheel.

## 1.4.0: removals and the Crafting List

* **Removed:** the Sell / Post tab (bag list, sell slot, Max button, price suggestions, deposit, post confirmations), the Blizzard handoff panel (`Handoff.lua`), post logging (`postLog`, `/capital debug post`), `/capital sell`, `postmode`, `undercut`, `durationmode`; the Vendor Swaps tab (`Swaps.lua`, its click/right-click vendor menu, the reverse list, `/capital swaps`). These commands now only print that they were removed.
* **Kept:** the bundled vendor database and vendor prices (Market's vendor columns, Professions' cheapest reagent, Price Lookup, Crafting List), closest-vendor ranking, the map pin, "Vendor not here", seasonal tags and **Hide seasonal vendors**.
* **Tabs now:** Search / Browse (Price Lookup away from the auction house), Buy, Market, Crafting List, Professions, Settings.
* **Shopping List → Crafting List** everywhere you see it (tab, buttons, questions, chat, tooltips). `/capital craftlist` opens it; `/capital list` and the old `/capital shopping` still work.
* **Search and Price Lookup clicks** also ask "Add <item> to crafting list?" (see Crafting List).
* **Schema 8:** see SavedVariables schema. Crafting List entries are kept as they were.

## 1.3.0: fixes from the Oct 17, 2026 game data

* **Recipes recorded under Fishing.** At 7:06 PM CDT on Oct 17, the profession window reported Fishing, but its recipe list was still Tailoring's. 1.2.9 stored all 29 Tailoring recipes a second time as `Fishing:<item>`, plus Fish Bowl. In 1.3.0:
  * Each recipe is stored under the profession the game reports for it (`C_TradeSkillUI.GetProfessionInfoByRecipeID`). If the client can't say, `IsRecipeInSkillLine` is used.
  * Nothing is read between `TRADE_SKILL_DATA_SOURCE_CHANGING` and `..._CHANGED`.
  * The window is read 0.5 s after it opens, not at `TRADE_SKILL_SHOW`.
  * Fishing, Herbalism and Skinning never get recipes.
  * Mismatches are noted in `debug.recipeMismatch`.
  * The schema 7 migration deletes the bad entries and notes how many in `debug.recipesDropped`.
* **Stormwind vendor positions.** The bundled (pfQuest) Stormwind coordinates don't match WoW Forever's Stormwind map. For example, Gunther Weller is bundled at 57.5, 57.1 but was recorded in game at 64.1, 68.7. Bundled Stormwind positions are now converted with `x' = 0.7724 x + 19.84`, `y' = 0.776 y + 24.35`. The fit uses 12 merchants (2 recorded in game, 10 published positions) and is within 0.4 map % of each. Ironforge positions recorded in game already matched and are unchanged. A merchant you have visited still uses its recorded position.

## Known limitations

* The sales estimate in SavedVariables is only an estimate (cancellations count as sales, identical stacks from one seller can't be told apart), and it is meaningless with infrequent on-demand scans.
* Distances are straight lines in world yards. They don't account for paths, flight points or boats, and they need your map position, so in instances or with no position no distance is shown and vendors are listed by zone. Vendor coordinates are pfQuest's first spawn in the main zone; wandering or event NPCs may be elsewhere. Items added by WoW Forever (IDs beyond vanilla, e.g. 279276) have no bundled name and show "loading…" until the server sends them.
* Vendor zones are each NPC's main spawn zone from pfQuest. Faction is A/H/AH from pfQuest. Seasonal vendors are tagged from cmangos `game_event_creature` / `game_event_creature_data` and missing spawns (see Bundled data). A vendor the server places differently is fixed once you open its merchant window, or by marking it "not here". Prices in game can be lower with reputation discounts until you record them.
* The legacy API needs a full scan to see everything. Full scans are throttled by the server (about 15 min), and a paged scan of a big AH takes many clicks.
* The modern backend follows the retail `C_AuctionHouse` API (Dragonflight/TWW signatures). It is tested against mocks only and has not been run on this client. If a call has a different signature, the error shows in chat and the status panel. Then try `/capital backend legacy` and send the `/capital debug` output.
* Money values above 2^31 copper (seen on this server, e.g. a 53,939,928g buyout) are stored exactly. Integers are formatted with `%.0f` rather than `%d`, because WoW's `%d` raises "integer overflow attempting to store".
* Browse scans only see each item's lowest price and total quantity, not individual auctions. For full history, run a `ReplicateItems` scan at least 15 minutes apart. Time-left bands from `GetReplicateItemTimeLeft` are normalised to 1–4 (0-based values are shifted).
* The legacy API assumptions come from Blizzard Classic Era (1.15) and have not been tested on this client. If something misbehaves, the chat error messages and `/capital debug` are the first things to check.
* Escape closes the window and the auction house together, which is how the game handles Escape.
* Recipe requirements for trainer recipes are estimated, and some bundled recipes may be unobtainable on this server.
* Profession names are matched by skillLineID when available, otherwise by English name or the localized profession spell name. Gathering skills whose spell name differs from the skill name (Herbalism) only match in English.
* Text metrics in the layout test are estimates (average glyph width 0.55 em), not the client's real font rendering. At 3x on a small UI (768 units tall), lists show only a few rows; scroll with the mouse wheel. If anything is cut off in game, try 2.5x.
* Neutral AH detection uses the English zone names Tanaris, Stranglethorn Vale and Winterspring.
* Market categories (1.4.1): the bundled tree and class map are English and come from the wowf 1.60.1.70245 tables (the client is 70450); once Blizzard's auction UI has loaded, the client's own category list replaces the bundled tree. Items Blizzard puts in two categories show in both (a cloak is in Armor > Cloth and Armor > Miscellaneous > Cloak, as in the client). Not tested in game yet.
