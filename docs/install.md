# Install and first run

## Prerequisites

- **BizHawk 2.8–2.10** with the **Ironmon Tracker 9.3 or newer** installed.
- **Java 8+** on `PATH` (the pinned jar targets Java 8; Java 21/19 both work). The
  pinned randomizer targets Java 8.
  `UnsupportedClassVersionError`.
- Your own **Pokémon FireRed (U) 1.1** ROM. The only accepted base is SHA-1
  `dd5945db9b930750cb39d00c84da8571feebf417` (16 777 216 bytes). The extension never downloads a
  ROM and never uploads one.

## Install

1. Copy this repository into `<BizHawk>/IronMon Tracker/extensions/` (the tracker's Extensions
   screen installs it from the repository URL; the repo root is the extension root).
2. Tracker Settings → Extensions: enable **Daily Dose of Ironmon**. The extension enables
   **Open Book play mode** automatically when an attempt is started or resumed; you can also turn
   it on manually under the tracker gear → **Gameplay** → **Other**.
3. Open the Daily Dose screen (the `[DDI]` chip at the bottom-right of the tracker panel, or it
   opens automatically when a Daily Dose ROM is loaded).
4. **Register / recover** → pick a handle. The token is stored in the tracker's `Settings.ini`
   and `extensions/daily-dose/state/player.json`; use **Copy token** to back it up.
5. Load your vanilla FireRed 1.1 ROM once. The extension offers to register it: it dumps the
   loaded image to `extensions/daily-dose/base/vanilla.gba` and verifies its SHA-1 locally.
6. Open Daily Dose → **Start attempt**:
   - the extension requests today's start ticket (this consumes the day);
   - it downloads the pinned randomizer jar if needed (hash-verified);
   - it generates the day's ROM from your base, the Faster-FireRed patch and the published
     settings string;
   - it compares the generated SHA-1 with the manifest and opens the ROM in BizHawk.

## Downloaded assets

The Faster FireRed 1.2 patch is not bundled. On first generation the extension downloads the
official release asset from [DrMaple/Faster-FireRed](https://github.com/DrMaple/Faster-FireRed/releases/tag/1.2):

`https://github.com/DrMaple/Faster-FireRed/releases/download/1.2/Faster.FireRed.1.2.ips`

and verifies SHA-256 `c23fca99d6f0ab0ad107f0d8a7ceee7e8b2cde0c7bcf54ccbdca66ead77035c9`
before caching it at `daily-dose/assets/faster-firered-1.2.ips`.

The randomizer jar is not committed: the extension fetches the exact jar pinned in the day's
manifest into `daily-dose/jars/<sha8>.jar` and verifies its hash. The jar is GPL-3.0; its source
lives in the `ddoz-zx-randomizer` fork.

## What lives where

```
extensions/daily-dose/
  assets/faster-firered-1.2.ips   downloaded Faster FireRed patch (hash-verified)
  base/vanilla.gba                your base ROM dump (never leaves your machine)
  jars/<sha8>.jar                 pinned randomizer jars
  roms/<date>.gba (+ .log)        generated daily ROM and its ZX-format log
  state/current.json              the active attempt
  state/queue.json                pending uploads
  state/player.json               handle + device id
```

## First-run smoke test

1. Confirm the tracker shows today's date and seed on the Daily Dose screen.
2. Confirm the ROM loads with the tracker (game detected as FireRed) and the Log Overlay lists
   starters, encounters and trainer teams.
3. Pick the starter; the screen switches to `active` and both clocks start.
4. Reload BizHawk: the screen offers **Resume attempt** and the clocks continue.
5. Check today's leaderboard on the web board; your handle should appear after the first badge.

## Updating

Replace the repository contents with a newer release (or reinstall from the tracker). The
extension checks the local jar against each day's manifest and fetches the pinned version instead
of failing a generation because of a version skew.
