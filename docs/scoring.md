# Scoring

Two scores are produced from the same attempt:

- **IGT** — in-game time, derived from emulated frames since the starter joined the party.
- **RTA** — real time while BizHawk had the ROM open (time with the emulator closed is excluded;
  pauses count).

Both use the same depth-first formula; only the time base (and therefore the speed term) differs.

```
progress = sum of points for every milestone up to and including the deepest one reached
speed    = clamp(floor(((par / time) - 0.5) * 999), 0, 999)
score    = progress * 1000 + speed
```

`par` is the published par for the deepest milestone and the relevant time base. RTA par is
`round(IGT par * 1.2)` in v1 and is published in the manifest.

## Why this shape

- Max speed is 999, one milestone is worth at least 15 × 1000 = 15 000, so **a deeper run always
  outranks a shallower one**; speed only decides between runs at the same depth.
- At par, speed is 499; 50 % faster gives 999; 50 % slower gives 0.
- Maximum score is 1 000 999 (champion at or above par speed).

## Milestones (v1, Kaizo)

| id | label | points | par IGT | par RTA |
|---|---|---|---|---|
| b1 | Boulder Badge | 15 | 45:00 | 54:00 |
| b2 | Cascade Badge | 20 | 1:15:00 | 1:30:00 |
| b3 | Thunder Badge | 25 | 1:45:00 | 2:06:00 |
| b4 | Rainbow Badge | 30 | 2:30:00 | 3:00:00 |
| b5 | Soul Badge | 35 | 3:15:00 | 3:54:00 |
| b6 | Marsh Badge | 45 | 4:00:00 | 4:48:00 |
| b7 | Volcano Badge | 55 | 4:45:00 | 5:42:00 |
| b8 | Earth Badge | 75 | 5:30:00 | 6:36:00 |
| e4_lorelei | Lorelei | 90 | 6:30:00 | 7:48:00 |
| e4_bruno | Bruno | 100 | 7:00:00 | 8:24:00 |
| e4_agatha | Agatha | 110 | 7:30:00 | 9:00:00 |
| e4_lance | Lance | 120 | 8:00:00 | 9:36:00 |
| champion | Champion | 280 | 12:00:00 | 14:24:00 |

Points sum to 1000. The service is authoritative: tables are versioned (`score_version`), shipped
in each manifest, and the extension only mirrors the arithmetic for on-screen projections.

## Tuning and versions

- A new table or formula is published as a new `score_version`; runs keep the version they were
  played under, boards filter by version, and a version change starts a new season.
- Before publishing, the admin simulates the change on the last 30 days of runs and reviews the
  diffs. Historical runs are never re-scored.

## Ties

Higher score, then smaller final time, then earlier submission.


## Best attempt before Brock

Attempts that void before the Boulder Badge are retryable; the leaderboard ranks the best score
kept across those attempts. Once Brock is beaten the run is final and its score competes with that
best.

## Trainer multiplier

Fewer defeated trainers means less EXP, so the run is harder. The total score (progress x 1000 + speed)
for both timebases is multiplied by:

    1 + 0.5 * (100 - trainers_defeated) / 100

Trainer counts are clamped to 0..100, so the multiplier ranges from 1.5x (0 trainers) to 1.0x
(100+ trainers). The count is the tracker's unique defeated trainers.
