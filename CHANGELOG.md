# Changelog

## 1.4.2
* New **Feedback** button in the top bar and `/capital feedback`: shows the address for suggestions and bug reports (selected, ready to copy with Ctrl+C) and a version line to include.
* The command list shown on the first auction house visit includes `/capital feedback`.
* Ready for public release: new installs start at normal (1x) text size (saved sizes are kept); neutral auction houses are recognized on every client language; tested from a fresh install with any character, faction, level and professions.
* Release zip contains only the add-on files; added README, CHANGELOG and third-party notices.
* Licensed under the GNU GPL v3.0 or later (full text in LICENSE; SPDX header in every source file).

## 1.4.1
* Market tab: category tree on the left, the same as the auction house's Browse categories, with item counts; click a category to filter.
* A list of commands is shown when the auction house opens (once per visit; can be turned off) and with `/capital help`.

## 1.4.0
* Removed the Sell / Post tab and the Vendor Swaps tab. The game ignores add-on posting on WoW Forever, so posting is done in Blizzard's window.
* Shopping List renamed to Crafting List (`/capital craftlist`).
* Clicking a search or price lookup result also asks to add the item to the crafting list.

## 1.3.1
* Professions tab: "Available on AH" column with the quantity listed in the latest scan.

## 1.3.0
* Fixed recipes being recorded under the wrong profession when switching profession windows.
* Corrected bundled Stormwind vendor positions.

## 1.2.9 and earlier
* 1.2.7: Price Lookup that works away from the auction house, `/capital price`.
* 1.2.6: Professions tab with reagent costs and profit; Blizzard's auction frame is only made invisible, never changed.
* 1.2.5: support for the WoW Forever (modern) client API.
* 1.2.3: vendors seen in game, "Vendor not here", seasonal vendor tags.
* 1.2.2: adjustable text size, Shopping List.
