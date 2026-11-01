# Daily Dose of Ironmon — agent notes

This repo is the **public Ironmon Tracker extension**. It is installed by copying this whole
repository tarball into `<tracker>/extensions/`, so the repo root *is* the extension root.

Related repos (not inside this one):

- `daily-dose-of-ironmon-leaderboard` — private service (Cloudflare Worker, D1, R2, Vue board,
  generator agent, pipeline). Never add service code here.
- `ddoz-zx-randomizer` — public GPL-3 fork of UPR-ZX 4.6.1 that builds the pinned jar and the
  Tracker-compatible log writer.

## Hard rules

- **No ROMs, saves, save states or ROM-derived binaries** in this repo or its tests.
  `.gitignore` blocks the usual extensions; `npm run check` fails if one is tracked.
- **Lua 5.1 *and* 5.4 compatible.** No `goto`, no `//`, no bitwise operators (`& | ~ << >>`),
  no `utf8`. The lint script enforces syntax with `luaparse` 5.1 and rejects those tokens.
- **No secrets.** The player token and device id live in the tracker's `Settings.ini` and in
  `daily-dose/state/` at runtime; never print them (except the explicit "Copy token" action),
  never commit them.
- **The service is the source of truth for scoring.** `daily-dose/score.lua` mirrors the formula
  for display only; par/points arrive in the daily manifest. Do not hardcode new tables here
  without updating the private repo and the mirrored fixtures.
- **Tracker API contract**: see `docs/api.md` (HTTP) and the Ironmon Tracker's
  `CodeExtensionTemplate.lua.txt`. Hooks run on the emulator thread — never block in
  `afterEachFrame`; use `Program.addFrameCounter` or the 30-frame `afterProgramDataUpdate`.

## Structure

```
DailyDoseIronmon.lua        extension entry, hooks, wiring (tracker contract)
daily-dose/config.lua       constants (API base, fps, hashes, paths)
daily-dose/json.lua         minimal JSON codec (no tracker dependency)
daily-dose/util.lua         files, hashes (shell), time, paths
daily-dose/score.lua        progress/speed/score (mirror of service)
daily-dose/milestones.lua   milestone order and detection helpers
daily-dose/manifest.lua     daily manifest validation
daily-dose/session.lua      run state machine and clocks
daily-dose/http.lua         curl transport
daily-dose/api.lua          endpoint wrappers
daily-dose/identity.lua     handle/token/device id
daily-dose/rom.lua          base ROM registration, generation, hashes
daily-dose/jars.lua         pinned jar resolution
daily-dose/submit.lua       persisted upload queue
daily-dose/run.lua          orchestration against tracker state
daily-dose/screen.lua       custom screen
daily-dose/hud.lua          overlay line
daily-dose/diagnostics.lua  mismatch report
daily-dose/recovery.lua     handle recovery
daily-dose/log.lua          ZX log presence / Log Overlay hook
docs/                       player rules, API contract, scoring, determinism, attempts
tests/                      wasmoon tests + fixtures
scripts/                    lint, checks
```

Modules must be loadable without the tracker (`local M = {} ... return M`); the pure modules are
the ones under test. Tracker globals may only be touched inside functions, never at load time.

There is no `.cursor/maps` atlas for this repo: agent-atlas scans TypeScript/Java/Kotlin/Python
and cannot see Lua. This file and `docs/` are the routing documents; keep them current.

## Verify

```
npm install
npm run verify   # lint (Lua 5.1 parse + forbidden tokens) -> vitest (wasmoon) -> extension checks
```

`npm test` runs the Lua logic under wasmoon (Lua 5.4) with tracker globals absent; integration
with the real Tracker is a manual smoke test described in `docs/install.md`.

## Working agreements

- Read this file and `docs/` before changing behaviour; keep docs current in the same change.
- Prefer extending existing modules over adding new ones; delete code you orphan.
- Do not commit, push or deploy unless asked.
- Windows/PowerShell 7 for commands; native paths.
