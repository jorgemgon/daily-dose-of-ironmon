#!/usr/bin/env node
// Structural checks for the installable extension: required files, no ROM/save artefacts,
// metadata consistency. Runs after lint and tests in `npm run verify`.

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = process.cwd();
const errors = [];
const SKIP_DIRS = new Set(["node_modules", ".git", ".vitest", "coverage"]);

const REQUIRED = [
  "DailyDoseIronmon.lua",
  "daily-dose/config.lua",
  "daily-dose/json.lua",
  "daily-dose/util.lua",
  "daily-dose/score.lua",
  "daily-dose/milestones.lua",
  "daily-dose/manifest.lua",
  "daily-dose/session.lua",
  "daily-dose/http.lua",
  "daily-dose/api.lua",
  "daily-dose/identity.lua",
  "daily-dose/rom.lua",
  "daily-dose/jars.lua",
  "daily-dose/log.lua",
  "daily-dose/submit.lua",
  "daily-dose/run.lua",
  "daily-dose/screen.lua",
  "daily-dose/hud.lua",
  "daily-dose/diagnostics.lua",
  "daily-dose/recovery.lua",
  "daily-dose/assets/faster-firered-1.2.ips",
  "docs/rules.md",
  "docs/api.md",
  "docs/scoring.md",
  "docs/attempt.md",
  "docs/install.md",
  "docs/determinism.md",
  "docs/troubleshooting.md",
  "tests/fixtures/manifest.json",
  "THIRD_PARTY_NOTICES.md",
  "LICENSE",
];

const FORBIDDEN_EXTENSIONS = [".gba", ".gbc", ".nds", ".3ds", ".cia", ".sav", ".srm", ".saveram", ".state", ".bps"];

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const path = join(dir, entry);
    const info = statSync(path);
    if (info.isDirectory()) {
      walk(path, out);
    } else {
      out.push(path);
    }
  }
  return out;
}

for (const path of REQUIRED) {
  if (!existsSync(join(ROOT, path))) {
    errors.push(`missing required file: ${path}`);
  }
}

for (const file of walk(ROOT)) {
  const lower = file.toLowerCase();
  if (FORBIDDEN_EXTENSIONS.some((ext) => lower.endsWith(ext))) {
    errors.push(`forbidden ROM/save artefact in repo: ${relative(ROOT, file)}`);
  }
  const rel = relative(ROOT, file).replace(/\\/g, "/");
  if (/^daily-dose\/(state|base|roms)\//.test(rel)) {
    errors.push(`runtime state must not be committed: ${rel}`);
  }
}

const pkg = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8"));
const entry = readFileSync(join(ROOT, "DailyDoseIronmon.lua"), "utf8");
const versionMatch = entry.match(/version = "([^"]+)"/);
if (!versionMatch) {
  errors.push("entry point does not declare self.version");
} else if (versionMatch[1] !== pkg.version) {
  errors.push(`entry version ${versionMatch[1]} does not match package.json ${pkg.version}`);
}

for (const needle of ["Daily Dose of Ironmon", "requiredExtKeys", "return DailyDoseIronmon"]) {
  if (!entry.includes(needle)) {
    errors.push(`entry point missing "${needle}"`);
  }
}

const fixture = JSON.parse(readFileSync(join(ROOT, "tests/fixtures/manifest.json"), "utf8"));
const points = fixture.milestones.reduce((sum, m) => sum + m.points, 0);
if (points !== 1000) {
  errors.push(`fixture manifest points sum to ${points}, expected 1000`);
}
if (fixture.milestones.length !== 13) {
  errors.push(`fixture manifest has ${fixture.milestones.length} milestones, expected 13`);
}

if (errors.length > 0) {
  console.error(`Extension check failed (${errors.length}):`);
  for (const error of errors) console.error(`  ${error}`);
  process.exit(1);
}

console.log("Extension check passed: layout, metadata and fixture are consistent.");
