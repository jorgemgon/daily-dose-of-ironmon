# Daily Dose of Ironmon (extension)

A daily, seed-shared **Kaizo Ironmon** run for FireRed on the
[Ironmon Tracker](https://github.com/besteon/Ironmon-Tracker): everyone plays the same
randomized game on a given UTC day, gets **one attempt**, and posts two scores — one ranked by
in-game time, one by real time. Seeds are **open book**: the day's randomizer log is public
before anyone starts.

This repository is the tracker extension. It generates the day's ROM locally from your own
FireRed (U) 1.1, verifies it against the day's published hash, tracks the run, and submits
progress. It never downloads a ROM.

## Install

1. Copy this repository into `<BizHawk>/IronMon Tracker/extensions/` (or install it from the
   tracker's Extensions screen by URL).
2. Enable **Daily Dose of Ironmon** in Tracker Settings → Extensions.
3. Open your own vanilla FireRed (U) 1.1 ROM once so the extension can register it locally.
4. Open the Daily Dose screen (hotkey, default `D` while the tracker is focused) and register a
   handle.

Full setup, including Java and the pinned randomizer jar, is in [docs/install.md](docs/install.md).

## What it does

- **One ROM per UTC day**, generated from a pinned randomizer jar, the Kaizo settings string, a
  deterministic seed and a fixed base patch. Same inputs → same SHA-1 everywhere.
- **Quality-weighted species**: the lab and the routes up to Viridian Forest favour stronger,
  better-spread, better-moved Pokémon; later areas use a lighter BST weighting.
- **100 % catch rate** (guaranteed catch, part of the pinned settings).
- **One attempt**, enforced by a server ticket before generation, plus restart/rewind detection.
  Closing and reopening BizHawk is supported — resume from your in-game save.
- **Two scores** per run: depth-first progress points, speed as the tiebreak, computed twice —
  in-game clock and real clock.
- **Open book**: the day's log is public; the tracker runs with Open Book mode enabled.

Rules by game: [docs/rules.md](docs/rules.md) · Scoring: [docs/scoring.md](docs/scoring.md) ·
Attempt and resume rules: [docs/attempt.md](docs/attempt.md) · API: [docs/api.md](docs/api.md).

## Development

```
npm install
npm run verify
```

The Lua logic is tested headlessly with [wasmoon](https://github.com/ceifa/wasmoon); linting
parses every file as Lua 5.1 and rejects 5.2+ syntax. See [AGENTS.md](AGENTS.md).

## Licence

Extension code: MIT. The pinned randomizer jar is GPL-3.0 (UPR-ZX 4.6.1 fork); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
