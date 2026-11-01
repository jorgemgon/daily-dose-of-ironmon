#!/usr/bin/env node
// Lints the extension Lua: parse as Lua 5.1 (the tracker supports BizHawk 2.8) and reject syntax
// that only exists in later Lua versions, plus indentation style.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import luaparse from "luaparse";

const ROOT = process.cwd();
const SKIP_DIRS = new Set(["node_modules", ".git", ".vitest", "coverage"]);

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const path = join(dir, entry);
    const info = statSync(path);
    if (info.isDirectory()) {
      walk(path, out);
    } else if (entry.endsWith(".lua")) {
      out.push(path);
    }
  }
  return out;
}

const LUA_FILES = walk(ROOT);
const errors = [];

for (const file of LUA_FILES) {
  const display = relative(ROOT, file);
  const source = readFileSync(file, "utf8");

  try {
    luaparse.parse(source, { luaVersion: "5.1", locations: true });
  } catch (error) {
    errors.push(`${display}: ${error.message}`);
    continue;
  }

  const lines = source.split(/\r?\n/);
  lines.forEach((line, index) => {
    if (/^ +\S/.test(line)) {
      errors.push(`${display}:${index + 1}: indent with tabs, not spaces`);
    }
    if (/^\s*goto\s/.test(line)) {
      errors.push(`${display}:${index + 1}: goto is not Lua 5.1`);
    }
    if (/::\w+::/.test(line)) {
      errors.push(`${display}:${index + 1}: labels are not Lua 5.1`);
    }
  });

  if (!source.endsWith("\n")) {
    errors.push(`${display}: file must end with a newline`);
  }
}

if (errors.length > 0) {
  console.error(`Lua lint failed (${errors.length}):`);
  for (const error of errors) console.error(`  ${error}`);
  process.exit(1);
}

console.log(`Lua lint passed: ${LUA_FILES.length} files parsed as Lua 5.1.`);
