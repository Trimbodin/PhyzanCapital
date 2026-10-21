# Phyzan Capital

An auction house add-on for **World of Warcraft: Forever** (client 1.60.1, interface 16001). Scan the auction house, see market prices by auction category, look up saved prices anywhere, plan purchases on a crafting list and check which of your recipes make a profit.

## Install

1. Close the game.
2. Unzip so that you get `Interface\AddOns\PhyzanCapital\PhyzanCapital.toc` inside your WoW Forever client folder (beta: `World of Warcraft\_classic_beta_\Interface\AddOns\`; the folder name of the released client may differ).
3. Start the game and make sure **Phyzan Capital** is enabled in the AddOns list on the character screen.

## Using it

* Open the auction house: the Phyzan Capital window opens on **Search / Browse**. Click **Scan Auction House** to record prices (a full scan is allowed about every 15 minutes by the server; otherwise a quicker browse scan runs).
* **Search / Browse** and **Buy**: search, compare with the market price, bid or buy out. Every bid and buyout asks you to confirm first.
* **Market**: every scanned item with the lowest price and today's median and average, filtered by the auction house's own categories (Weapons, Armor, Containers, Consumables, Trade Goods, ...).
* **Price Lookup** (anywhere, also away from the AH): type part of an item name to see its last known price and a short price history. `/capital price <item>` prints it in chat.
* **Crafting List**: click a search or price lookup result, or a reagent on the Professions tab, to add it. The list shows the closest vendor that sells it (with a map pin) or the auction house price.
* **Professions**: your known recipes with reagent cost, sale value after the AH cut, profit and margin.
* **Settings**: text size (1x to 3x), auto-open, hiding Blizzard's window while ours is open, and more.

Selling is done in Blizzard's own auction house window: close Phyzan Capital with the X (or `/capital`) and post as usual.

Nothing is automated. Every search, bid and purchase needs your click.

## Commands

`/capital help` shows all commands. The main ones: `/capital` (open/close, also `/pc`), `/capital prices`, `/capital price <item>`, `/capital market`, `/capital craftlist`, `/capital professions`, `/capital settings`, `/capital textsize <1-3>`, `/capital feedback`.

## Feedback

Suggestions and bug reports: **kingofthefallllc@gmail.com**. In game, click **Feedback** in the window's top bar (or type `/capital feedback`) to copy the address and the version line to include in your report.

## License

Phyzan Capital - Copyright (C) 2026 Fredrick. Free software under the **GNU General Public License v3.0 or later** (`LICENSE`). The add-on is plain, readable Lua: the files in this folder are its complete source code. Bundled data and its credits: `THIRD_PARTY_NOTICES.md`.
