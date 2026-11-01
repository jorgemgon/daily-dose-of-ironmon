# Determinism

Every player must generate the same ROM from the same day's manifest. The inputs are pinned:

- base ROM: FireRed (U) 1.1, SHA-1 `dd5945db9b930750cb39d00c84da8571feebf417`;
- base patch: Faster FireRed 1.2 standard when the manifest includes `ips_sha256`, SHA-256
  `C23FCA99D6F0AB0AD107F0D8A7CEEE7E8B2CDE0C7BCF54CCBDCA66EAD77035C9`;
- randomizer jar: `jar_sha256` in the manifest (fetched by hash if the local copy differs);
- settings string: `settings_string` (hash-verified locally before generation);
- weights preset and event biases: `weights_preset`, `event` in the manifest;
- seed: `seed` in the manifest.

The extension generates the ROM locally with those inputs and compares its SHA-1 with
`rom_sha1`. A match is the only way to start a ranked attempt.

## How the fork keeps it deterministic

- `-z <seed>` seeds the randomizer's single `RandomSource`; no other RNG is used.
- Collections that are iterated during randomization are insertion-ordered or sorted; a strict
  mode (`-Dddoz.strict=true`) fails if an unordered container is iterated.
- The pipeline generates every challenge **twice in separate JVM processes** and publishes only
  when both SHA-1 values agree; otherwise the day is not published and the admin is alerted.
- The fork's CI runs the same seed on Temurin 8/17/21 and compares hashes.

## When a hash does not match

The extension never downloads a replacement ROM. It:

1. retries generation once in a fresh process;
2. prints stage fingerprints (`--fingerprints`: starters, wild areas, trainer teams, items,
   movesets, final ROM) and compares them with the manifest;
3. shows which stage diverged plus the Java version, OS, jar/base/IPS/settings hashes;
4. offers **Send report** (`POST /api/diagnostics`, hashes only — never ROM data);
5. releases the attempt: the intent expires after 2 hours without a confirm, so no day is lost.

Common causes are a stale jar (the extension fetches the pinned one), a modified base ROM (hash
shown), a stale IPS (the downloaded patch is hash-checked), or a different Java runtime. If a whole
class of players diverges, the admin fixes the jar/settings and regenerates the day; the published
hash and log change together.
