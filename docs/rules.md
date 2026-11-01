# Rules by game

Each challenge mode has its own rules file. The board picks the matching file by the manifest’s
`mode`, so adding a game means adding a rules page and a mode entry — not editing one shared list.

| Game / mode | Rules |
|---|---|
| Kaizo Ironmon (`kaizo`) | [Kaizo rules](rules/kaizo.md) |

## Shared mechanics

These apply across games unless the game page overrides them:

- One seed per UTC day; the manifest publishes the ROM, jar, settings and IPS hashes.
- Two scores from the same run: **IGT** (in-game clock) and **RTA** (real time), depth first and
  speed second.
- The server is authoritative for the UTC day: future days are not public until the server reaches
  them, regardless of the player’s clock.
- No ROMs are hosted here; players supply their own FireRed 1.1 base.
