# Third-party notices

Phyzan Capital is licensed under the GNU GPL v3.0 or later (see `LICENSE`). It bundles data from the sources below (files in `Data/`); their licences are compatible with GPL-3.0 and their notices are kept here. Thanks to their authors.

## pfQuest (vendor list and vendor positions in `Data/Vendors.lua`)

Vendor names, the items they sell and their map positions were taken from pfQuest's database (https://github.com/shagu/pfQuest) and then converted, filtered and partly corrected.

```
MIT License

Copyright (c) 2017-2021 Eric Mauser (Shagu)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## VMaNGOS and CMaNGOS (origin of the vendor data; seasonal vendor tags)

pfQuest's vanilla database is generated from the VMaNGOS world database (https://github.com/vmangos/core, GNU GPL v2). The seasonal / event vendor tags in `Data/Vendors.lua` and a cross-check of vendor items come from the CMaNGOS classic-db world database (https://github.com/cmangos/classic-db, GNU GPL v3). Those projects' licences apply to the data derived from them: VMaNGOS is licensed under the GNU General Public License version 2 or later, CMaNGOS classic-db under the GNU General Public License version 3; Phyzan Capital, including this data, is distributed under GPL-3.0, with the full licence text in `LICENSE`.

## Blizzard Entertainment game data

Item names, item prices and classes, recipes and map information in `Data/` were extracted from World of Warcraft client data tables (DB2) of WoW Forever 1.60.1 and Classic Era, read through wago.tools (https://wago.tools). This data is the property of Blizzard Entertainment, Inc. Item names and details shown in game come from your own client whenever it has them.
