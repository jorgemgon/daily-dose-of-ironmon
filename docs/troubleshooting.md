# Troubleshooting

**"Configure the API base URL"**
The extension ships with a placeholder service URL. Set the real URL in Tracker Settings →
Extensions → Daily Dose → Options. Nothing is sent until it starts with `https://`.

**"Base ROM not registered"**
Load your vanilla FireRed (U) 1.1 in BizHawk and accept the registration prompt. The extension
dumps the loaded image to `daily-dose/base/vanilla.gba` and checks its SHA-1. The only accepted
hash is `dd5945db9b930750cb39d00c84da8571feebf417`.

**"randomizer failed" / "Java not found"**
Install Java 17 or newer and set Tracker Settings → Paths → Java Path. The extension runs
`java -Xmx2G -jar <pinned jar> cli …`.

**"generated ROM hash mismatch"**
The extension re-tries once, then shows the diverging stage. Send the report (hashes only) and
check that the base ROM, IPS and jar are the ones listed in the manifest. The attempt is not
consumed if it was never confirmed.

**The Log Overlay is empty**
The tracker needs `<rom>.gba.log` next to the ROM. The extension writes it during generation and
falls back to downloading the canonical log text. If it is still empty, check that Open Book Play
Mode is enabled and that the tracker is 9.3+.

**"that attempt is no longer available"**
The run is active, or Brock has already been beaten and the day is locked server-side. Closing and
reopening BizHawk is fine — use **Resume attempt**. Before Brock, a void/restart starts a new
attempt automatically; after Brock the run is final.

**"I closed BizHawk and lost progress"**
Resume from your last in-game save. If the save is behind the leaderboard, the extension rolls
progress back (recorded) rather than voiding the run; save in-game before closing next time.

**"Rewind/restart void"**
A save state that erased submitted milestones, or a new game, voids the attempt. Loads before the
first milestone are fine.

**No internet at start**
Without a start ticket there is no ranked attempt; the extension refuses to begin rather than
waste the day. Once a run is confirmed, progress queues locally and uploads when the network
returns.

**Recovering a lost token**
Ask the admin for a one-time recovery code, then use **Register / recover** → Recover with your
handle and the code.

**Reporting a bug**
Include the diagnostics screen output (hashes, Java, OS, extension version) and the tracker's
`errorlog.txt` lines that start with `[DailyDoseIronmon`. Never paste your token.
