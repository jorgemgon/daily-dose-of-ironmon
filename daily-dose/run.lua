-- Run orchestration: manifest -> intent -> generation -> confirm -> milestones -> submit.
-- Tracker access is injected through `ctx` (see DailyDoseIronmon.lua); this module never reads
-- game memory or global tracker state directly.

local Run = {}

Run.STATE_VERSION = 1

function Run.today(now)
	return os.date("!%Y-%m-%d", now or os.time())
end

function Run.paths(ctx)
	local base = ctx.extDir .. "/state"
	return {
		dir = base,
		current = base .. "/current.json",
		queue = base .. "/queue.json",
		player = base .. "/player.json",
		manifest = function(date)
			return base .. "/manifest-" .. date .. ".json"
		end,
	}
end

local function ensureStateDir(ctx)
	return ctx.util.ensureDir(Run.paths(ctx).dir)
end

---@return table? state, string? err
function Run.load(ctx)
	local text = ctx.util.readFile(Run.paths(ctx).current)
	if not text or text == "" then
		return nil, nil
	end
	local decoded, err = ctx.json.decode(text)
	if not decoded then
		return nil, "state file is corrupt: " .. tostring(err)
	end
	local state, stateErr = ctx.session.fromTable(decoded)
	if not state then
		return nil, stateErr
	end
	return state
end

---@param ctx table
---@param state table
---@return boolean
function Run.save(ctx, state)
	if not ensureStateDir(ctx) then
		return false
	end
	state.lastSavedAt = ctx.now()
	return ctx.util.writeFile(Run.paths(ctx).current, ctx.json.encode(state))
end

function Run.clear(ctx)
	ctx.util.removeFile(Run.paths(ctx).current)
end

---@param ctx table
---@param date string
---@return table? manifest
function Run.loadCachedManifest(ctx, date)
	local text = ctx.util.readFile(Run.paths(ctx).manifest(date))
	if not text then
		return nil
	end
	local decoded = ctx.json.decode(text)
	if type(decoded) ~= "table" then
		return nil
	end
	return decoded
end

---@param ctx table
---@param date string
---@return table? manifest, string? err
function Run.fetchManifest(ctx, date)
	if ctx.manifest and ctx.manifest.date == date then
		return ctx.manifest
	end
	local cached = Run.loadCachedManifest(ctx, date)
	if cached then
		ctx.manifest = cached
	end

	local response = ctx.api:getDaily(date)
	if response and response.data and type(response.data) == "table" then
		local candidate = response.data
		local ok, err = ctx.manifestModule.validate(candidate, {
			mode = ctx.config.MODE,
			milestones = ctx.milestones.ORDER,
		})
		if ok then
			ctx.manifest = candidate
			ctx.util.writeFile(Run.paths(ctx).manifest(date), ctx.json.encode(candidate))
			return candidate
		end
		return nil, err
	end
	if cached then
		return cached
	end
	return nil, (response and response.err) or "could not load the daily challenge"
end

---@param ctx table
---@return table? session, string? err
function Run.beginTwitchLogin(ctx)
	local response = ctx.api:createTwitchSession()
	if not response or response.err then
		return nil, response and response.err or "network request failed"
	end
	if response.status ~= 201 or not response.data then
		local message = response.data and response.data.message or ("server returned " .. tostring(response.status))
		return nil, message
	end
	return response.data
end

---@param ctx table
---@param sessionId string
---@param pollToken string
---@return boolean ok, string? err
function Run.completeTwitchLogin(ctx, sessionId, pollToken)
	local response = ctx.api:pollTwitchSession(sessionId, pollToken)
	if not response or response.err then
		return false, response and response.err or "network request failed"
	end
	if response.status == 202 then
		return false, "Twitch login is still pending"
	end
	if response.status ~= 200 or not response.data or type(response.data.token) ~= "string" then
		local message = response.data and response.data.message or ("server returned " .. tostring(response.status))
		return false, message
	end
	ctx.player.handle = response.data.handle
	ctx.player.token = response.data.token
	ctx.identity.save(ctx.identityDeps, ctx.player)
	return true
end

---Requests the single start intent for today. Consumes the day server-side.
---@param ctx table
---@return boolean ok, string? err
function Run.startIntent(ctx)
	local date = Run.today(ctx.now())
	local manifest, err = Run.fetchManifest(ctx, date)
	if not manifest then
		return false, err or "no challenge published for today"
	end
	local window = ctx.manifestModule.window(manifest, ctx.now())
	if window ~= "open" and window ~= "grace" then
		return false, "today's challenge is closed"
	end
	if not ctx.player.token then
		return false, "register a handle first"
	end
	local existing = Run.load(ctx)
	if existing and existing.date == date and Run.hasBrock(existing)
		and existing.phase ~= ctx.session.PHASES.INTENT and existing.phase ~= ctx.session.PHASES.ACTIVE then
		return false, "Brock is already beaten; today's run is final."
	end
	if existing and existing.date == date and existing.phase ~= ctx.session.PHASES.VOID then
		ctx.state = existing
		-- Refresh the manifest so a republished day (new jar/settings) is picked up.
		local refreshed = Run.fetchManifest(ctx, date)
		if refreshed then
			ctx.manifest = refreshed
		end
		return true, nil
	end

	local response = ctx.api:intent(date, manifest.rom_sha1, ctx.player.deviceId, ctx.player.token)
	if not response or response.err then
		return false, response and response.err or "network request failed"
	end
	if response.status == 409 then
		return false, "that attempt is no longer available (run active or Brock already beaten)"
	end
	if response.status ~= 200 and response.status ~= 201 then
		local message = response.data and response.data.message or ("server returned " .. tostring(response.status))
		return false, message
	end
	local data = response.data or {}
	if type(data.run_id) ~= "string" or type(data.run_token) ~= "string" then
		return false, "server response did not include a run"
	end

	local state = ctx.session.new(date, ctx.config.MODE, ctx.now())
	state.attempt = tonumber(data.attempt) or 1
	ctx.session.bindIntent(state, data.run_id, data.run_token, data.expires_at or 0)
	if not Run.save(ctx, state) then
		return false, "could not persist run state"
	end
	ctx.state = state
	ctx.manifest = manifest
	return true
end

---Prepares (or verifies) today's local ROM.
---@param ctx table
---@return boolean ok, string? err
function Run.prepareRom(ctx)
	local state = ctx.state
	local manifest = ctx.manifest
	if not state or not manifest then
		return false, "start the attempt first"
	end
	local function preflight()
		return ctx.rom.preflight({
			extDir = ctx.extDir,
			util = ctx.util,
			manifest = manifest,
			config = ctx.config,
			useIps = ctx.useIps,
		})
	end

	local preflightOk, preflightErr, info = preflight()
	if not preflightOk and preflightErr == "base ROM not registered" then
		-- First run with a supported ROM loaded: dump it once, locally. It is never uploaded.
		local dumped, dumpErr = ctx.rom.dumpBase({
			extDir = ctx.extDir,
			util = ctx.util,
			config = ctx.config,
			memory = _G.memory,
			gameSettings = _G.GameSettings,
		})
		if dumped then
			preflightOk, preflightErr, info = preflight()
		else
			local imported, importErr = ctx.rom.importBaseFromProfiles({
				extDir = ctx.extDir,
				util = ctx.util,
				config = ctx.config,
				fileManager = _G.FileManager,
				quickload = _G.QuickloadScreen,
				options = _G.Options,
			})
			if imported then
				preflightOk, preflightErr, info = preflight()
			else
				return false, "base ROM not registered: " .. tostring(dumpErr) .. "; " .. tostring(importErr)
			end
		end
	end
	if not preflightOk then
		return false, preflightErr
	end

	local jarPath, jarErr = ctx.jars.ensure({
		extDir = ctx.extDir,
		util = ctx.util,
		manifest = manifest,
	})
	if not jarPath then
		return false, jarErr
	end
	state.jarPath = jarPath
	Run.save(ctx, state)

	local outputPath = ctx.rom.romPath(ctx.extDir, manifest.date, state.attempt)
	local ipsPath = nil
	if manifest.ips_sha256 and ctx.useIps ~= false then
		ipsPath = ctx.rom.ipsPath(ctx.extDir)
	end
	local args = ctx.manifestModule.generationArgs(
		manifest,
		ctx.rom.basePath(ctx.extDir),
		ipsPath,
		outputPath,
		true
	)
	local resolvedJava = ctx.rom.resolveJava({
		util = ctx.util,
		javaPath = ctx.javaPath,
		fileManager = _G.FileManager,
		extDir = ctx.extDir,
	})
	if resolvedJava then
		ctx.javaPath = resolvedJava
	end

	local result = ctx.rom.generate({
		extDir = ctx.extDir,
		util = ctx.util,
		manifest = manifest,
		javaPath = ctx.javaPath,
		jarPath = jarPath,
		args = args,
		outputPath = outputPath,
	})
	if result.ok then
		state.romPath = result.path
		state.logPath = result.log
		Run.save(ctx, state)
		ctx.log.ensure({
			util = ctx.util,
			manifest = manifest,
			logPath = result.log,
		})
		return true
	end

	-- Localised diagnostics for a hash mismatch; nothing is uploaded but hashes.
	if result.sha then
		local report = ctx.diagnostics.build({
			date = manifest.date,
			mode = manifest.mode,
			expectedSha1 = manifest.rom_sha1,
			actualSha1 = result.sha,
			stage = "final ROM hash",
			baseSha1 = info and info.baseSha or ctx.util.sha1File(ctx.rom.basePath(ctx.extDir)),
			ipsSha = info and info.ipsSha,
			settingsSha = info and info.settingsSha,
			jarSha = manifest.jar_sha256,
			javaVersion = ctx.javaVersion,
			os = ctx.osName,
			extensionVersion = ctx.config.VERSION,
			note = "two local generations disagree with the published hash",
		})
		Run.enqueue(ctx, "diagnostics", report)
	end
	return false, result.err or "generation failed"
end

function Run.openRom(ctx)
	if _G.Options then
		if type(_G.Options.addUpdateSetting) == "function" then
			_G.Options.addUpdateSetting("Game Over condition", "LeadPokemonFaints")
		else
			_G.Options["Game Over condition"] = "LeadPokemonFaints"
		end
	end
	if ctx.profile and type(ctx.profile.ensure) == "function" then
		pcall(ctx.profile.ensure, { extDir = ctx.extDir, romPath = ctx.state and ctx.state.romPath, date = ctx.state and ctx.state.date })
	end
	if ctx.log and type(ctx.log.enableOpenBook) == "function" then
		ctx.log.enableOpenBook({ trackerApi = _G.TrackerAPI })
	end
	local state = ctx.state
	if not state or not state.romPath then
		return false
	end
	return ctx.rom.open(state.romPath, { client = ctx.client, main = ctx.main })
end

---Reopens today's ROM without consuming anything.
---@param ctx table
---@return boolean ok, string? err
function Run.resumeAttempt(ctx)
	local state = ctx.state
	if not state then
		local loaded = Run.load(ctx)
		state = loaded
		ctx.state = state
	end
	if not state or state.phase ~= ctx.session.PHASES.ACTIVE then
		return false, "no active attempt to resume"
	end
	if not state.romPath or not ctx.util.fileExists(state.romPath) then
		return false, "today's ROM is missing; prepare it again"
	end
	local manifest = Run.fetchManifest(ctx, state.date)
	if not manifest then
		return false, "today's challenge is not available"
	end
	if not Run.openRom(ctx) then
		return false, "could not reopen the ROM"
	end
	return true
end

local function enqueueProgress(ctx, status)
	local state = ctx.state
	local manifest = ctx.manifest
	if not state or not manifest then
		return
	end
	local milestones = {}
	for _, id in ipairs(ctx.milestones.ORDER) do
		if state.milestones[id] then
			milestones[#milestones + 1] = {
				id = id,
				igt_seconds = state.igt[id] or 0,
				rta_seconds = state.rta[id] or 0,
			}
		end
	end
	local payload = {
		status = status,
		score_version = manifest.score_version,
		igt_seconds = math.floor(ctx.session.igtSeconds(state, ctx.frames())),
		rta_seconds = math.floor(ctx.session.rtaSeconds(state, ctx.now())),
		state_loads = state.stateLoads or 0,
		restarts = state.restarts or 0,
		resumes = state.resumes or 0,
		rollbacks = state.rollbacks or 0,
		milestones = milestones,
		trainers_defeated = state.trainersDefeated or 0,
	}
	if state.voidReason then
		payload.void_reason = state.voidReason
	end
	ctx.submit.enqueue(ctx.json, ctx.util, Run.paths(ctx).queue, {
		kind = "progress",
		runId = state.runId,
		token = state.runToken,
		payload = payload,
	}, ctx.now())
end

function Run.enqueue(ctx, kind, payload)
	ctx.submit.enqueue(ctx.json, ctx.util, Run.paths(ctx).queue, {
		kind = kind,
		runId = ctx.state and ctx.state.runId,
		token = ctx.state and ctx.state.runToken,
		payload = payload,
	}, ctx.now())
end

function Run.flushQueue(ctx)
	return ctx.submit.flush({
		json = ctx.json,
		util = ctx.util,
		path = Run.paths(ctx).queue,
		api = ctx.api,
		now = ctx.now(),
	})
end

---Confirms the intent once the starter is in the party.
---@param ctx table
---@param observation table
---@return boolean
function Run.confirmIfReady(ctx, observation)
	local state = ctx.state
	if not state or state.phase ~= ctx.session.PHASES.INTENT then
		return false
	end
	if not ctx.player.token then
		return false
	end
	local partySize = observation.partySize or 0
	if partySize < 1 then
		return false
	end
	if not ctx.manifest or tostring(ctx.romHash() or ""):lower() ~= tostring(ctx.manifest.rom_sha1 or ""):lower() then
		return false
	end

	local frames = ctx.frames()
	local now = ctx.now()
	local payload = {
		started_at = now,
		start_frames = frames,
		save_id = observation.saveId,
	}
	local response = ctx.api:confirm(state.runId, state.runToken, payload)
	if response and not response.err and (response.status == 200 or response.status == 201 or response.status == 204) then
		local ok = ctx.session.confirm(state, frames, now, observation.saveId)
		if ok then
			Run.save(ctx, state)
		end
		return ok
	end
	-- Offline or transient: queue the confirmation; play continues locally.
	if response and response.status and response.status >= 400 and response.status ~= 408 and response.status ~= 429 then
		ctx.session.void(state, "confirm_rejected", now)
		Run.save(ctx, state)
		return false
	end
	ctx.submit.enqueue(ctx.json, ctx.util, Run.paths(ctx).queue, {
		kind = "confirm",
		runId = state.runId,
		token = state.runToken,
		payload = payload,
	}, now)
	ctx.session.confirm(state, frames, now, observation.saveId)
	Run.save(ctx, state)
	return true
end

---Per-tick work. Called every 30 frames from the extension hook.
---@param ctx table
---@param observation table {partySize, badges, defeated, champion, partyWiped, saveId}
function Run.tick(ctx, observation)
	local state = ctx.state
	if not state then
		return
	end
	local now = ctx.now()
	local frames = ctx.frames()
	if type(observation.trainersDefeated) == "number" then
		state.trainersDefeated = observation.trainersDefeated
	end

	if state.phase == ctx.session.PHASES.INTENT then
		Run.confirmIfReady(ctx, observation)
		return
	end
	if state.phase ~= ctx.session.PHASES.ACTIVE then
		return
	end

	if state.date ~= Run.today(now) then
		local window = ctx.manifest and ctx.manifestModule.window(ctx.manifest, now) or "closed"
		if window == "closed" then
			Run.finish(ctx, "day_closed")
			return
		end
	end

	-- New emulator session (BizHawk was closed or the tracker reloaded).
	if state.sessionStartFrame == nil then
		ctx.session.resume(state, frames, now)
	end
	if state.lastFrame and frames < state.lastFrame then
		ctx.session.suspend(state, state.lastFrame, now)
		ctx.session.resume(state, frames, now)
	end
	state.lastFrame = frames

	local observedSet = ctx.milestones.fromObservation({
		badges = observation.badges,
		defeated = observation.defeated,
		champion = observation.champion,
	})

	if state.pendingRewindCheck then
		state.pendingRewindCheck = false
		local missing = ctx.milestones.missing(state.submitted, observedSet)
		if #missing > 0 then
			Run.void(ctx, "rewind_past_progress")
			return
		end
	end

	local added = ctx.session.addMilestones(state, observedSet, ctx.milestones.ORDER, frames, now)
	if #added > 0 then
		ctx.session.markSubmitted(state, observedSet)
		enqueueProgress(ctx, "active")
	end

	if observation.partyWiped then
		Run.finish(ctx, "wiped")
		return
	end

	if frames % ctx.config.PERSIST_INTERVAL_FRAMES == 0 then
		Run.save(ctx, state)
	end
end

---@param ctx table
---@param reason string
function Run.finish(ctx, reason)
	local state = ctx.state
	if not state or state.phase ~= ctx.session.PHASES.ACTIVE then
		return
	end
	ctx.session.finish(state, ctx.frames(), ctx.now(), reason)
	enqueueProgress(ctx, state.phase)
	Run.save(ctx, state)
end

---@param ctx table
---@param reason string
function Run.void(ctx, reason)
	local state = ctx.state
	if not state then
		return
	end
	ctx.session.void(state, reason, ctx.now())
	enqueueProgress(ctx, "void")
	Run.save(ctx, state)
end

---A load-state event: rewind is only fatal if it erases submitted milestones.
function Run.loadState(ctx)
	local state = ctx.state
	if not state or state.phase ~= ctx.session.PHASES.ACTIVE then
		return
	end
	state.stateLoads = (state.stateLoads or 0) + 1
	state.pendingRewindCheck = true
	Run.save(ctx, state)
end

---A new game on the daily ROM.
function Run.restartDetected(ctx)
	local state = ctx.state
	if not state or state.phase ~= ctx.session.PHASES.ACTIVE then
		return
	end
	state.restarts = (state.restarts or 0) + 1
	Run.void(ctx, "restart")
end

---Human-readable status lines for the screen/HUD.
---@param ctx table
---@return table<string>
---True once the Boulder Badge (Brock) has been reached on this attempt.
---@param state table?
---@return boolean
function Run.hasBrock(state)
	return state ~= nil and type(state.milestones) == "table" and state.milestones.b1 == true
end

function Run.statusLines(ctx)
	local state = ctx.state
	local lines = {}
	if not state then
		lines[#lines + 1] = "No attempt yet today."
		return lines
	end
	local now = ctx.now()
	local frames = ctx.frames()
	if state.phase == ctx.session.PHASES.INTENT then
		lines[#lines + 1] = "Waiting for the starter to confirm the attempt."
		return lines
	end
	if state.phase == ctx.session.PHASES.VOID then
		local suffix = Run.hasBrock(state) and " Day over." or " New attempt allowed."
		lines[#lines + 1] = "Void: " .. tostring(state.voidReason) .. suffix
		return lines
	end

	local igt = ctx.session.igtSeconds(state, frames)
	local rta = ctx.session.rtaSeconds(state, now)
	lines[#lines + 1] = "IGT: " .. ctx.util.formatClock(igt) .. "   RTA: " .. ctx.util.formatClock(rta)

	local manifest = ctx.manifest
	if manifest then
		for _, timebase in ipairs({ "igt", "rta" }) do
			local tables = ctx.manifestModule.scoringTables(manifest, timebase)
			local score = ctx.score.compute(state.milestones, tables, timebase == "igt" and igt or rta)
			lines[#lines + 1] = string.format(
				"%s score: %d  (progress %d, speed %d)%s",
				timebase:upper(),
				score.score,
				score.progress,
				score.speed,
				score.milestone and ("  @ " .. score.milestone) or ""
			)
		end
	end
	return lines
end

return Run
