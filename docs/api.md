# API contract (extension ⇄ service)

The extension speaks JSON over HTTPS to the service base URL configured in the tracker
(Settings → Extensions → Daily Dose → Options). All requests use `Authorization: Bearer <token>`
unless noted. Errors are `{ "message": "..." }` with a non-2xx status.

## Twitch login

The extension logs in with Twitch instead of typing a handle.

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/api/auth/twitch/session` | – | `{ "session_id", "poll_token", "login_url", "expires_at" }` |
| GET | `/api/auth/twitch/start?session=…` | – | redirect to Twitch |
| GET | `/api/auth/twitch/callback` | – | Twitch OAuth callback |
| POST | `/api/auth/twitch/session/:id/poll` | `{ "poll_token" }` | `202 { "status": "pending" }` or `200 { "status": "complete", "token", "handle" }` |

The browser session lasts 10 minutes. The player handle is the Twitch login. The service needs
`TWITCH_CLIENT_ID`, `TWITCH_CLIENT_SECRET` and `PUBLIC_BASE_URL`; the Twitch app redirect URL must
be `<PUBLIC_BASE_URL>/api/auth/twitch/callback`.
## Player

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/api/players` | – | `410 { "message": "Twitch login is required" }` |
| POST | `/api/players/recover` | `{ "handle", "code" }` | `{ "handle", "token" }` |
| GET | `/api/me` | – | `{ "handle", "runs": [...] }` |

Handles are 2–20 characters, start with a letter/digit, and may contain letters, digits, `_`, `.`,
`-`. Registration is open; duplicate-device and IP evidence is queued for admin review, not blocked.

## Daily challenge

`GET /api/daily?date=YYYY-MM-DD` (public) returns the manifest for that UTC date (today by
default). Dates after the **server's** current UTC day return `404` even when a challenge has
already been generated, and the public log/leaderboard endpoints apply the same gate. The
extension rejects a manifest that fails validation or is for a different mode.

```json
{
  "date": "2026-11-01",
  "mode": "kaizo",
  "seed": 123456789,
  "base_sha1": "dd5945…",
  "rom_sha1": "…40 hex…",
  "jar_sha256": "…64 hex…",
  "jar_url": "https://github.com/<owner>/ddoz-randomizer/releases/download/v1/ddoz-zx.jar",
  "settings_string": "…",
  "settings_sha256": "…64 hex…",
  // optional; omitted when the challenge is generated without a base patch
  "ips_sha256": "…64 hex…",
  "weights_preset": "daily-v1",
  "score_version": 1,
  "published_at": 1761955200,
  "reset_at": 1762041600,
  "grace_seconds": 21600,
  "log_url": "https://…/api/logs/2026-11-01",
  "log_sha256": "…64 hex…",
  "event": { "id": "halloween", "name": "Halloween", "type_biases": { "ghost": 4 }, "scope": "early" },
  "milestones": [
    { "id": "b1", "points": 15, "par_igt": 2700, "par_rta": 3240 }
  ]
}
```

Rules enforced by validation: a non-empty `mode`, 13 milestones in the published order, points sum
to 1000, hashes have the right lengths, `reset_at` is a number. The extension additionally
requires the manifest mode to match its configured challenge mode.

`GET /api/logs/:date?mode=kaizo` (public) returns the canonical ZX-format log as text (gzip is fine; the
client sends `--compressed`). It contains no ROM data.

## Attempt lifecycle

### 1. Intent (opens an attempt)

`POST /api/runs/intent`

```json
{ "date": "2026-11-01", "mode": "kaizo", "rom_sha1": "…", "device_id": "…" }
```

`201` → `{ "run_id", "run_token", "expires_at" }`.
`409` → `{ "message": "attempt_used" }` if the run is active or Brock (`b1`) has already been reached.

Re-issuing while an unconfirmed intent exists returns the same run. An intent older than
`expires_at` (2 h) expires and releases the day (no gameplay happened).

### 2. Confirm (starter joins the party)

`POST /api/runs/:id/confirm` with the run token:

```json
{ "started_at": 1761958800, "start_frames": 51234, "save_id": "trainer-1" }
```

`200/201/204` → the run is active and the day is locked. `409/410` → the run is not confirmable
(void/expired); the extension marks the attempt unranked.

Progress patches also accept `trainers_defeated` (integer, unique trainers beaten); it scales the
score by up to 1.5x when few trainers were fought.

### 3. Resume (after closing BizHawk)

`POST /api/runs/:id/resume` with the run token:

```json
{ "at": 1761970000, "frames_base": 81234, "state_loads": 0 }
```

`200` → `{ "ok": true }`, increments `resumes` and refreshes `last_seen_at`.

### 4. Progress / finish / void

`PATCH /api/runs/:id` with the run token:

```json
{
  "status": "active | finished | void",
  "score_version": 1,
  "igt_seconds": 3600,
  "rta_seconds": 3900,
  "state_loads": 0,
  "restarts": 0,
  "resumes": 1,
  "rollbacks": 0,
  "void_reason": "rewind_past_progress",
  "milestones": [ { "id": "b1", "igt_seconds": 2500, "rta_seconds": 2700 } ]
}
```

The server validates ordering, monotonic clocks, per-milestone floors and the ROM hash, recomputes
both scores and rejects writes to void/expired runs. Rollbacks are only accepted with a
`rollback` reason and can only lower progress.

## Diagnostics

`POST /api/diagnostics` (public, rate-limited) accepts a hashes-only report:

```json
{
  "date": "2026-11-01", "mode": "kaizo",
  "expected_sha1": "…", "actual_sha1": "…", "stage": "final ROM hash",
  "base_sha1": "…", "ips_sha256": "…", "settings_sha256": "…", "jar_sha256": "…",
  "java": "17.0.12", "os": "Windows 11", "extension_version": "0.1.0", "note": "…"
}
```

No ROM bytes, no saves, no tokens.

## Public leaderboards (read-only)

`GET /api/leaderboard?date=YYYY-MM-DD&mode=kaizo&timebase=igt|rta&scope=daily|month|alltime`

Rows: `{ "handle", "score", "progress", "milestone", "time_seconds", "status", "flags" }`, sorted
by score, then time, then submission.

## Admin (not used by the extension)

Admin endpoints live under `/api/admin/*` (Cloudflare Access in front): challenges, jobs, events,
seed overrides, scoring versions, players, flags, diagnostics. The generator agent uses
`/api/admin/agent/*` and `/api/admin/challenges` with a separate agent token.
