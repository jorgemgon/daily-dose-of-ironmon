# Attempts, resume and identity

## Unlimited attempts until Brock

The extension asks the service for a **start intent** before it prepares a ROM.

- The intent is valid for 2 hours. If it is never confirmed (the player never reaches the starter),
  it expires and the attempt is released — no gameplay happened.
- Once the starter joins the party the extension **confirms** the attempt and the run becomes
  active.
- If the run ends before the **Boulder Badge (Brock, `b1`)** — void, restart or a new game — the
  service accepts a new intent for the same day. The best score of the ended attempt is kept, and
  the leaderboard ranks the best attempt.
- Once `b1` has been reached, the run is final for that player and day. No new attempt is issued,
  whether the run later finishes or voids.

There is no separate attempt counter on the board; only the best score is shown.

## Resume, not restart

Closing and reopening BizHawk is supported.

- On startup the extension finds the active run, offers **Resume attempt**, reopens today's ROM
  (with its `.SaveRAM`) and re-attaches both clocks.
- **IGT** continues from the persisted frame count; a new emulator session adds its frames instead
  of resetting the clock.
- **RTA** continues from the persisted wall time and only accrues while BizHawk has the ROM open.
  Time with the emulator closed is not counted; pauses with it open are.
- Save in-game before closing. If the save is behind the last submitted milestone, the extension
  warns you, rolls the leaderboard progress back to the save (recorded, clocks not refunded) and
  continues the same attempt.
- A changed save identity (a new game) voids the run; before Brock you can start again.

## Rewinds and restarts

- A save-state load that still contains every submitted milestone is a legitimate session resume.
- A load that erases submitted progress **voids** the run.
- A new game on the daily ROM (new trainer/save identity) **voids** the run.
- Loads before the first milestone are allowed (lab resets).
- The extension reports `state_loads`, `restarts`, `resumes` and `rollbacks` with every update; the
  board shows them.

## Second identities

Registration is open, and a second account is **not blocked**. Instead the service records the
evidence and queues it for admin review:

- `shared_device` — the same install id registered a second handle;
- `ip_cluster` — several new handles from one IP within 24 hours;
- `rapid_registration` — a new handle plus intent right after another new handle on the same
  device/IP;
- `duplicate_run` — a second run for a day (the ticket should prevent this; high priority);
- `suspicious_cadence` — implausible play patterns.

Flags are private to the admin. Nothing is voided automatically; the admin can dismiss, merge the
handles (moving runs and voiding duplicates), void runs, or ban a device/handle. Every action is
audited. The honest limit: a determined player can reinstall and register again — the queue makes
that visible and cheap to act on, not impossible.
