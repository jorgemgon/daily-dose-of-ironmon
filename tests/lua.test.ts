import { describe, expect, it } from "vitest";
import { fixtureManifestJson, runLua } from "./helpers";

describe("json", () => {
  it("encodes objects with sorted keys and arrays in order", async () => {
    const result = await runLua(`
      local encoded = M.json.encode({ b = "x", a = 1, c = {1, 2, 3}, d = true })
      assert(encoded == '{"a":1,"b":"x","c":[1,2,3],"d":true}', encoded)
      local value = M.json.decode(encoded)
      assert(value.a == 1 and value.c[3] == 3 and value.d == true)
      return encoded
    `);
    expect(result).toContain('"c":[1,2,3]');
  });

  it("decodes escapes and numbers", async () => {
    const result = await runLua(`
      local value = M.json.decode([[{"q":"he said \\"hi\\"","n":-2.5,"arr":[true,null]}]])
      assert(value.q == 'he said "hi"', tostring(value.q))
      assert(value.n == -2.5)
      assert(value.arr[1] == true)
      return value.n
    `);
    expect(result).toBe(-2.5);
  });

  it("returns an error instead of throwing on malformed input", async () => {
    const result = await runLua(`
      local value, err = M.json.decode("{")
      assert(value == nil)
      assert(type(err) == "string")
      return err
    `);
    expect(String(result)).toContain("json.decode");
  });
});

describe("score", () => {
  it("computes depth-first progress and a bounded speed term", async () => {
    const result = await runLua(`
      local tables = {
        order = {"b1", "b2", "champion"},
        points = { b1 = 15, b2 = 20, champion = 280 },
        par = { b1 = 2700, b2 = 4500, champion = 43200 },
      }
      local r = M.score.compute({ b1 = true }, tables, 2700)
      assert(r.progress == 15 and r.speed == 499 and r.score == 15499, M.json.encode(r))

      local slow = M.score.compute({ b1 = true, b2 = true }, tables, 9000)
      assert(slow.progress == 35 and slow.speed == 0, M.json.encode(slow))

      local fast = M.score.compute({ champion = true }, tables, 21600)
      assert(fast.progress == 315 and fast.speed == 999, M.json.encode(fast))
      assert(fast.score == 315999)
      return r.score
    `);
    expect(result).toBe(15499);
  });

  it("never lets speed cross a milestone", async () => {
    const result = await runLua(`
      local tables = {
        order = {"b1", "b2"},
        points = { b1 = 15, b2 = 20 },
        par = { b1 = 2700, b2 = 4500 },
      }
      local shallowFast = M.score.compute({ b1 = true }, tables, 1350)
      local deepSlow = M.score.compute({ b1 = true, b2 = true }, tables, 9000)
      assert(deepSlow.score > shallowFast.score, shallowFast.score .. " vs " .. deepSlow.score)
      return deepSlow.score - shallowFast.score
    `);
    expect(Number(result)).toBeGreaterThan(0);
  });

  it("rejects malformed scoring tables", async () => {
    const result = await runLua(`
      local ok, err = M.score.validateTables({ order = {"b1"}, points = {}, par = {} })
      assert(ok == false and type(err) == "string")
      return err
    `);
    expect(String(result)).toContain("invalid points");
  });
});

describe("milestones", () => {
  it("applies badge and champion closure", async () => {
    const result = await runLua(`
      local twoBadges = M.milestones.fromObservation({ badges = { true, true } })
      assert(twoBadges.b1 and twoBadges.b2 and not twoBadges.b3)

      local champion = M.milestones.fromObservation({ champion = true })
      for _, id in ipairs(M.milestones.ORDER) do
        assert(champion[id], "missing " .. id)
      end

      local lorelei = M.milestones.fromObservation({ defeated = { [410] = true } })
      assert(lorelei.e4_lorelei and lorelei.b8)
      assert(not lorelei.e4_bruno)
      return M.milestones.deepest(champion)
    `);
    expect(result).toBe("champion");
  });

  it("reports submitted milestones missing from an observation", async () => {
    const result = await runLua(`
      local missing = M.milestones.missing({ b1 = true, b2 = true }, { b1 = true })
      assert(#missing == 1 and missing[1] == "b2")
      return missing[1]
    `);
    expect(result).toBe("b2");
  });
});

describe("manifest", () => {
  const globals = { __manifest_json: fixtureManifestJson() };

  it("accepts the shipped fixture and exposes per-timebase tables", async () => {
    const result = await runLua(
      `
      local manifest = assert(M.json.decode(__manifest_json))
      local ok, err = M.manifest.validate(manifest, { mode = "kaizo", milestones = M.milestones.ORDER })
      assert(ok, tostring(err))

      local igt = M.manifest.scoringTables(manifest, "igt")
      local rta = M.manifest.scoringTables(manifest, "rta")
      assert(igt.par.b1 == 2700)
      assert(rta.par.b1 == 3240)
      assert(#igt.order == 13)

      local totals = M.manifest.totals(manifest)
      assert(totals.points == 1000)
      return totals.points
    `,
      globals,
    );
    expect(result).toBe(1000);
  });

  it("rejects the wrong mode or a broken points total", async () => {
    const result = await runLua(
      `
      local manifest = assert(M.json.decode(__manifest_json))
      local ok = M.manifest.validate(manifest, { mode = "survival" })
      assert(ok == false)

      manifest.milestones[1].points = 16
      local ok2, err2 = M.manifest.validate(manifest, { mode = "kaizo", milestones = M.milestones.ORDER })
      assert(ok2 == false and err2:find("sum", 1, true))
      return err2
    `,
      globals,
    );
    expect(String(result)).toContain("sum");
  });

  it("classifies the day window", async () => {
    const result = await runLua(
      `
      local manifest = assert(M.json.decode(__manifest_json))
      assert(M.manifest.window(manifest, manifest.reset_at - 60) == "open")
      assert(M.manifest.window(manifest, manifest.reset_at + 60) == "grace")
      assert(M.manifest.window(manifest, manifest.reset_at + manifest.grace_seconds + 1) == "closed")
      return M.manifest.window(manifest, manifest.reset_at + 60)
    `,
      globals,
    );
    expect(result).toBe("grace");
  });

  it("omits the base patch when no IPS is published", async () => {
    const result = await runLua(`
      local manifest = assert(M.json.decode(__manifest_json))
      manifest.ips_sha256 = nil
      local ok, err = M.manifest.validate(manifest)
      assert(ok, err)
      local args = M.manifest.generationArgs(manifest, "base.gba", nil, "out.gba", true)
      local joined = table.concat(args, " ")
      assert(not joined:find("--base-ips", 1, true))
      return joined
    `, globals);
    expect(String(result)).toContain("--guaranteed-catch");
  });
  it("builds pinned generation arguments", async () => {
    const result = await runLua(
      `
      local manifest = assert(M.json.decode(__manifest_json))
      local args = M.manifest.generationArgs(manifest, "base.gba", "faster.ips", "out.gba", true)
      local joined = table.concat(args, " ")
      assert(joined:find("-z 123456789", 1, true))
      assert(joined:find("--guaranteed-catch", 1, true))
      assert(joined:find("--log-format zx", 1, true))
      assert(joined:find(manifest.settings_string, 1, true))
      return #args
    `,
      globals,
    );
    expect(Number(result)).toBeGreaterThan(10);
  });
});

describe("session", () => {
  it("runs the intent -> active -> clocks state machine", async () => {
    const result = await runLua(`
      local s = M.session.new("2026-11-01", "kaizo", 1000)
      assert(s.phase == "intent")

      M.session.bindIntent(s, "run-1", "token-1", 8200)
      assert(M.session.confirm(s, 5000, 1010, "save-1"))
      assert(s.phase == "active")

      local minute = math.floor(59.7275 * 60)
      local added = M.session.addMilestones(s, { b1 = true }, M.milestones.ORDER, 5000 + minute, 1070)
      assert(#added == 1 and added[1] == "b1")
      assert(math.abs(M.session.igtSeconds(s, 5000 + minute) - 60) < 0.2)
      assert(M.session.rtaSeconds(s, 1070) == 60)

      M.session.suspend(s, 5000 + 2 * minute, 1130)
      assert(math.abs(M.session.igtSeconds(s) - 120) < 0.2)
      assert(M.session.rtaSeconds(s, 1130) == 120)
      assert(s.phase == "active")

      M.session.resume(s, 0, 2000)
      assert(s.resumes == 1)
      assert(math.abs(M.session.igtSeconds(s, 1000) - (120 + 1000 / 59.7275)) < 0.2)
      assert(M.session.rtaSeconds(s, 2000) == 120)
      return s.resumes
    `);
    expect(result).toBe(1);
  });

  it("prunes a save rollback and records it", async () => {
    const result = await runLua(`
      local s = M.session.new("2026-11-01", "kaizo", 1000)
      M.session.confirm(s, 0, 1000, "save-1")
      M.session.addMilestones(s, { b1 = true, b2 = true }, M.milestones.ORDER, 6000, 1100)
      M.session.markSubmitted(s, { b1 = true, b2 = true })

      local removed = M.session.rollback(s, { b1 = true })
      assert(#removed == 1 and removed[1] == "b2", M.json.encode(removed))
      assert(s.milestones.b1 and not s.milestones.b2)
      assert(s.rollbacks == 1)
      return removed[1]
    `);
    expect(result).toBe("b2");
  });

  it("finishes and voids with reasons, and validates persisted state", async () => {
    const result = await runLua(`
      local s = M.session.new("2026-11-01", "kaizo", 1000)
      M.session.confirm(s, 0, 1000, "save-1")
      M.session.finish(s, 12000, 1300, "wiped")
      assert(s.phase == "finished" and s.finishReason == "wiped")
      assert(M.session.validate(s))
      assert(M.session.igtSeconds(s) > 0)

      local v = M.session.new("2026-11-01", "kaizo", 1000)
      M.session.void(v, "restart", 1500)
      assert(v.phase == "void" and v.voidReason == "restart")

      local bad = M.session.new("2026-11-01", "kaizo", 1000)
      bad.version = 99
      local ok, err = M.session.validate(bad)
      assert(ok == false and err:find("version", 1, true))
      return s.phase
    `);
    expect(result).toBe("finished");
  });
});

describe("http", () => {
  it("builds a curl command with headers and status capture", async () => {
    const result = await runLua(`
      local cmd = M.http.buildCurl({
        url = "https://api.test/api/daily",
        method = "POST",
        bodyFile = "C:/tmp/body.json",
        outputFile = "C:/tmp/out.json",
        headers = { Authorization = "Bearer abc" },
        timeout = 5,
      })
      assert(cmd:find("curl", 1, true))
      assert(cmd:find("https://api.test/api/daily", 1, true))
      assert(cmd:find("Authorization: Bearer abc", 1, true))
      assert(cmd:find("--data-binary @", 1, true))
      assert(cmd:find("-m 5", 1, true))
      return cmd
    `);
    expect(String(result)).toContain("https://api.test/api/daily");
  });

  it("parses the status trailer", async () => {
    const result = await runLua(`
      assert(M.http.parseStatus(string.char(10) .. "204") == 204)
      assert(M.http.parseStatus("200") == 200)
      assert(M.http.parseStatus("") == nil)
      return M.http.parseStatus("429")
    `);
    expect(result).toBe(429);
  });

  it("performs a request through injected io", async () => {
    const result = await runLua(`
      local io = {
        writeFile = function(path, data) return true end,
        readFile = function(path)
          if path:find("response", 1, true) then
            return '{"ok":true}'
          end
          return nil
        end,
        run = function(command) return true, string.char(10) .. "200" end,
        remove = function() end,
      }
      local response = M.http.request({ url = "https://api.test/x", method = "GET", workDir = "." }, io)
      assert(response.status == 200 and response.body == '{"ok":true}')
      return response.status
    `);
    expect(result).toBe(200);
  });

  it("reports transport failures", async () => {
    const result = await runLua(`
      local io = {
        writeFile = function() return true end,
        readFile = function() return nil end,
        run = function() return false, "" end,
        remove = function() end,
      }
      local response = M.http.request({ url = "https://api.test/x", method = "GET" }, io)
      assert(response.err ~= nil)
      return response.err
    `);
    expect(String(result)).toContain("network");
  });
});

describe("identity", () => {
  it("accepts sensible handles and rejects bad ones", async () => {
    const result = await runLua(`
      assert(M.identity.validateHandle("Ash"))
      assert(M.identity.validateHandle("misty_99"))
      assert(not M.identity.validateHandle("a"))
      assert(not M.identity.validateHandle("-lead"))
      assert(not M.identity.validateHandle("has space"))
      assert(not M.identity.validateHandle(string.rep("x", 21)))
      return "ok"
    `);
    expect(result).toBe("ok");
  });
});

describe("submit", () => {
  it("sends one queued request and drains on success", async () => {
    const result = await runLua(`
      local mem = {}
      local util = {
        readFile = function(path) return mem[path] end,
        writeFile = function(path, data) mem[path] = data; return true end,
      }
      local calls = 0
      local api = {
        progress = function(self, runId, token, payload) calls = calls + 1; return { status = 200 } end,
      }
      M.submit.enqueue(M.json, util, "q", { kind = "progress", runId = "r", token = "t", payload = { a = 1 } }, 100)
      local result = M.submit.flush({ json = M.json, util = util, path = "q", api = api, now = 101 })
      assert(result.processed and calls == 1)
      assert(#M.submit.load(M.json, util, "q") == 0)
      return calls
    `);
    expect(result).toBe(1);
  });

  it("backs off on 5xx and drops on conflicts", async () => {
    const result = await runLua(`
      local mem = {}
      local util = {
        readFile = function(path) return mem[path] end,
        writeFile = function(path, data) mem[path] = data; return true end,
      }
      local api = {
        progress = function() return { status = 500 } end,
        confirm = function() return { status = 409 } end,
      }
      M.submit.enqueue(M.json, util, "q", { kind = "progress", runId = "r", token = "t", payload = {} }, 100)
      local first = M.submit.flush({ json = M.json, util = util, path = "q", api = api, now = 101 })
      assert(first.processed)
      local remaining = M.submit.load(M.json, util, "q")
      assert(#remaining == 1 and remaining[1].attempts == 1)
      assert(remaining[1].nextAt == 116)

      util.writeFile("q2", "")
      M.submit.enqueue(M.json, util, "q2", { kind = "confirm", runId = "r", token = "t", payload = {} }, 0)
      local second = M.submit.flush({ json = M.json, util = util, path = "q2", api = api, now = 200 })
      assert(second.conflict == true)
      return #M.submit.load(M.json, util, "q")
    `);
    expect(result).toBe(1);
  });
});

describe("diagnostics and recovery", () => {
  it("formats a hash-only report", async () => {
    const result = await runLua(`
      local report = M.diagnostics.build({
        date = "2026-11-01",
        expectedSha1 = "aaa",
        actualSha1 = "bbb",
        jarSha = "ccc",
        os = "Windows",
        extensionVersion = "0.1.0",
      })
      local text = M.diagnostics.format(report)
      assert(text:find("expected ROM SHA-1", 1, true))
      assert(text:find("0.1.0", 1, true))
      return text
    `);
    expect(String(result)).toContain("expected ROM SHA-1");
  });

  it("redeems a recovery code", async () => {
    const result = await runLua(`
      local seen = nil
      local api = {
        recover = function(self, handle, code)
          seen = { handle = handle, code = code }
          return { status = 200, data = { handle = "Ash", token = "tok-1" } }
        end,
      }
      local ok, result = M.recovery.redeem(api, "Ash", " abcd ")
      assert(ok and result.token == "tok-1")
      assert(seen.code == "ABCD")
      return result.token
    `);
    expect(result).toBe("tok-1");
  });
});

describe("Rom.ensureIps", () => {
  it("preserves a stale patch when the download fails", async () => {
    const result = await runLua(`
      local removed = {}
      local util = {
        quote = function(value) return value end,
        fileExists = function(path) return path == "/ext/assets/faster-firered-1.2.ips" end,
        sha256File = function() return "stale" end,
        removeFile = function(path) table.insert(removed, path) end,
        ensureDir = function() return true end,
        run = function() return false, "network down" end,
        copyFile = function() return true end,
      }
      local path, err = M.rom.ensureIps({
        extDir = "/ext",
        util = util,
        config = { IPS_SHA256 = "pinned", IPS_URL = "https://example.test/patch.ips" },
      })
      assert(path == nil)
      assert(string.find(err, "download failed", 1, true))
      for _, value in ipairs(removed) do
        assert(value ~= "/ext/assets/faster-firered-1.2.ips")
      end
      return err
    `);
    expect(String(result)).toContain("download failed");
  });

  it("installs a verified download", async () => {
    const result = await runLua(`
      local wrote = false
      local copied = false
      local util = {
        quote = function(value) return value end,
        fileExists = function(path)
          if path == "/ext/assets/faster-firered-1.2.ips" then return false end
          if path == "/ext/assets/faster-firered-1.2.ips.download" then return wrote end
          return false
        end,
        sha256File = function(path)
          if path == "/ext/assets/faster-firered-1.2.ips.download" then return "pinned" end
          return "stale"
        end,
        removeFile = function() end,
        ensureDir = function() return true end,
        run = function() wrote = true; return true, "" end,
        copyFile = function(src, dst) copied = (src == "/ext/assets/faster-firered-1.2.ips.download" and dst == "/ext/assets/faster-firered-1.2.ips"); return copied end,
      }
      local path = M.rom.ensureIps({
        extDir = "/ext",
        util = util,
        config = { IPS_SHA256 = "pinned", IPS_URL = "https://example.test/patch.ips" },
      })
      assert(path == "/ext/assets/faster-firered-1.2.ips")
      assert(copied)
      return path
    `);
    expect(String(result)).toContain("faster-firered-1.2.ips");
  });
});
