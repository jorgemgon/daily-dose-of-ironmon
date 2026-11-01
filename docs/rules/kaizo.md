# Rules — Daily Dose Kaizo (v1)

The daily mode is **Kaizo Ironmon** on FireRed (U) 1.1, with the modifications below. Everything
from the standard, Ultimate and Kaizo rulesets applies unless a daily override says otherwise
[Original Kaizo / Ironmon rules](https://gist.github.com/valiant-code/adb18d248fa0fae7da6b639e2ee8f9c1).

## Setup

1. Install the Ironmon Tracker (9.3+) in BizHawk.
2. Copy the Daily Dose extension folder into `<tracker>/extensions` and enable it in
   Tracker Settings.
3. Open the DDI screen, log in with Twitch, and register your own clean FireRed (U) 1.1 ROM when
   prompted. No ROMs are hosted here.
4. Java 8+ is required; the extension uses the Tracker’s Java path or finds a compatible JDK.
5. Press **Start attempt**: the extension runs the pinned randomizer and opens today’s ROM. When
   the challenge publishes Faster FireRed it applies that patch first; otherwise it runs without it.
6. Keep the generated `.gba` and `.log` together. The extension enables Open Book play mode
   automatically when the attempt starts or resumes; manually it lives under tracker gear →
   **Gameplay** → **Other**.
7. Closing BizHawk is fine — use **Resume attempt**.

See [install.md](../install.md) for the full walkthrough.
## Daily overrides

| Rule | Detail |
|---|---|
| Fewer trainers = more points | The total score is multiplied by `1 + 0.5 × (100 − trainers defeated)/100`, up to 1.5× at zero trainers. Less EXP means a harder run. |
| Unlimited attempts before Brock | A void or restart before the Boulder Badge opens a new attempt for the same day; the best score of those attempts is kept. Once Brock is beaten the run is final — no new attempt, even if it later voids. |
| Today's ROM only | The run must use the ROM generated from today's published seed, settings string, pinned jar and base patch; the extension verifies its SHA-1. |
| 100 % catch rate | Guaranteed catch is part of the pinned settings (no failed balls). |
| Weighted species | The lab and the routes up to Viridian Forest favour stronger, better-spread, better-moved Pokémon; later areas use a lighter BST weighting. Event days may bias types (published with the seed). |
| Lab level 6 | Both the player and the rival start the lab battle at level 6 instead of level 5. |
| Starter choice | You may choose any of the three lab starters. |
| Open book | The day's randomizer log is public before anyone starts. The extension enables Open Book mode automatically when the attempt opens, so trainer teams, encounters and movesets are visible. |
| Faster FireRed 1.2 (standard) | The QoL patch is applied before randomization: hidden items are visibly marked, the Viridian Forest nurse exists, the Oak parcel quest is shortened, repels prompt reuse, instant PC heal, renamers everywhere, PC item in the lab, and the one-time friendship NPC. These are part of the daily ruleset; everyone plays the same ROM. |
| Save states | A load that erases progress already submitted to the leaderboard voids the run. Loads before the first milestone (lab resets) are allowed. In-game saves are the supported resume point. |
| Close and reopen | BizHawk may be closed and reopened at any time. The run resumes from the in-game save; time with the emulator closed is not counted toward real time. |
| Turbo | Allowed. The in-game-time board is unaffected; the real-time board flags runs that used turbo. |
| Day window | The challenge opens at 00:00 UTC and closes at the next 00:00 UTC, with a 6-hour grace window for runs that started on the day. |
| Alt identities | Second accounts are not blocked; shared device/IP/cadence evidence is queued for admin review. |

## Still in force from Kaizo

- One Pokémon at a time (HM friends only otherwise); no random TMs; no 599+ BST Pokémon; stay
  within 4 levels when catching; banned moves (healing moves, Spore, Assist); banned abilities
  (Huge/Pure Power physical, etc.); catch only (no killing wild Pokémon); Nemesis clause; no
  healing items outside battle; held-item restrictions; no dungeon healing stations; no flutes;
  no relearner Sketch abuse; no shops except balls/repels; no VS Seeker; one catch/kill per route.

## Conduct

The leaderboard is honour-system for gameplay rules and machine-checked for ROM identity, clocks,
progress, restarts and rewinds. Mistakes should be reported; deliberate abuse is handled through
the admin review queue.
