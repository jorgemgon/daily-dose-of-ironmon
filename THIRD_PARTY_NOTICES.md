# Third-party notices

## UPR-FVX randomizer jar

The pinned `ddoz-randomizer` jar bundled under `daily-dose/jars/` (and fetched by hash at
runtime) is a fork of **Universal Pokemon Randomizer FVX**:

- Upstream: https://github.com/upr-fvx/universal-pokemon-randomizer-fvx
- Base lineage: Universal Pokemon Randomizer ZX by Ajarmar,
  https://github.com/Ajarmar/universal-pokemon-randomizer-zx
- Licence: **GNU General Public License v3.0**
- Our fork (source): https://github.com/&lt;owner&gt;/ddoz-randomizer

The jar is a separate program invoked by the extension via `java -jar`; the extension's Lua code
is not a derivative work of it.

Because the tracker strips files named `LICENSE` when installing an extension, the GPL text lives
in the fork repository's `LICENSE.txt`; the source link above is also kept in the extension's
About text and in `docs/install.md`.

## Faster-FireRed patch

**Faster FireRed 1.2** by DrMaple is applied to the player's own FireRed (U) 1.1 before
randomization:

- Source: https://github.com/DrMaple/Faster-FireRed
- Release asset: https://github.com/DrMaple/Faster-FireRed/releases/tag/1.2
- The patch is downloaded on first use by the extension and hash-verified; it is not redistributed
  in this repository.
- The patch is distributed as an IPS diff; it contains no ROM data.

## Ironmon Tracker

The extension targets the Ironmon Tracker (MIT) extension API:
https://github.com/besteon/Ironmon-Tracker
