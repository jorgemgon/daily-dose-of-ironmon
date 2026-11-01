import { readFileSync } from "node:fs";
import { join } from "node:path";
import { LuaFactory } from "wasmoon";

const ROOT = process.cwd();

export const MODULES = [
  "json",
  "util",
  "score",
  "milestones",
  "manifest",
  "session",
  "http",
  "identity",
  "submit",
  "diagnostics",
  "recovery",
] as const;

let sourceCache: Map<string, string> | null = null;

function sources(): Map<string, string> {
  if (sourceCache) return sourceCache;
  sourceCache = new Map();
  for (const name of MODULES) {
    sourceCache.set(name, readFileSync(join(ROOT, "daily-dose", `${name}.lua`), "utf8"));
  }
  return sourceCache;
}

function preload(): string {
  const lines = ["local M = {}"];
  for (const name of MODULES) {
    lines.push(`M.${name} = assert(load(__src_${name}, "@${name}"))()`);
  }
  return lines.join("\n") + "\n";
}

/**
 * Runs a Lua snippet with every module preloaded into `M` and returns the chunk's value.
 * Extra globals (strings) are exposed by name, e.g. `__manifest_json`.
 */
export async function runLua(body: string, globals: Record<string, string> = {}): Promise<unknown> {
  const factory = new LuaFactory();
  const lua = await factory.createEngine();
  try {
    for (const [name, source] of sources()) {
      lua.global.set(`__src_${name}`, source);
    }
    for (const [name, value] of Object.entries(globals)) {
      lua.global.set(name, value);
    }
    return await lua.doString(preload() + body);
  } finally {
    lua.global.close();
  }
}

export function fixtureManifestJson(): string {
  return readFileSync(join(ROOT, "tests", "fixtures", "manifest.json"), "utf8");
}
