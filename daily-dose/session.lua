-- Run state machine and clocks. Pure: caller supplies frame counts, timestamps and fps.
-- Phases: intent -> active -> finished | void.

local Session = {}

Session.VERSION = 1
Session.FPS = 59.7275
Session.PHASES = {
	INTENT = "intent",
	ACTIVE = "active",
	FINISHED = "finished",
	VOID = "void",
}

local function isPhase(value)
	return value == Session.PHASES.INTENT
		or value == Session.PHASES.ACTIVE
		or value == Session.PHASES.FINISHED
		or value == Session.PHASES.VOID
end

---@param date string YYYY-MM-DD
---@param mode string
---@param now number? unix seconds
---@return table
function Session.new(date, mode, now)
	return {
		version = Session.VERSION,
		date = date,
		mode = mode,
		phase = Session.PHASES.INTENT,
		createdAt = now or 0,
		runId = nil,
		runToken = nil,
		expiresAt = nil,
		startedAt = nil,
		confirmedAt = nil,
		finishedAt = nil,
		voidReason = nil,
		frames = 0,
		rtaSeconds = 0,
		sessionStartFrame = nil,
		sessionStartAt = nil,
		attempt = 1,
		trainersDefeated = 0,
		milestones = {},
		igt = {},
		rta = {},
		submitted = {},
		stateLoads = 0,
		restarts = 0,
		resumes = 0,
		rollbacks = 0,
		saveId = nil,
		lastSavedAt = 0,
		fps = Session.FPS,
	}
end

---@param state table
---@param runId string
---@param runToken string
---@param expiresAt number
function Session.bindIntent(state, runId, runToken, expiresAt)
	state.runId = runId
	state.runToken = runToken
	state.expiresAt = expiresAt
end

---@param state table
---@param now number
---@return boolean expired
function Session.intentExpired(state, now)
	return state.phase == Session.PHASES.INTENT
		and state.expiresAt ~= nil
		and now >= state.expiresAt
end

---@param state table
---@param framesNow number
---@param now number
---@param saveId string?
---@return boolean ok, string? err
function Session.confirm(state, framesNow, now, saveId)
	if state.phase ~= Session.PHASES.INTENT then
		return false, "run is not waiting for confirmation"
	end
	state.phase = Session.PHASES.ACTIVE
	state.startedAt = now
	state.confirmedAt = now
	state.sessionStartFrame = framesNow
	state.sessionStartAt = now
	state.saveId = saveId or state.saveId
	return true
end

---Commits the current session's elapsed frames and wall time, then stops both clocks.
---@param state table
---@param framesNow number
---@param now number
function Session.suspend(state, framesNow, now)
	if state.sessionStartFrame ~= nil and framesNow ~= nil then
		local delta = framesNow - state.sessionStartFrame
		if delta > 0 then
			state.frames = (state.frames or 0) + delta
		end
	end
	if state.sessionStartAt ~= nil and now ~= nil then
		local delta = now - state.sessionStartAt
		if delta > 0 then
			state.rtaSeconds = (state.rtaSeconds or 0) + delta
		end
	end
	state.sessionStartFrame = nil
	state.sessionStartAt = nil
end

---Restarts the clocks for a new emulator session.
---@param state table
---@param framesNow number
---@param now number
---@return boolean ok, string? err
function Session.resume(state, framesNow, now)
	if state.phase ~= Session.PHASES.ACTIVE then
		return false, "run is not active"
	end
	if state.sessionStartFrame ~= nil then
		return true
	end
	state.sessionStartFrame = framesNow
	state.sessionStartAt = now
	state.resumes = (state.resumes or 0) + 1
	return true
end

---In-game seconds, including the current session's uncommitted frames.
---@param state table
---@param framesNow number?
---@return number
function Session.igtSeconds(state, framesNow)
	local frames = state.frames or 0
	if state.sessionStartFrame ~= nil and framesNow ~= nil then
		local delta = framesNow - state.sessionStartFrame
		if delta > 0 then
			frames = frames + delta
		end
	end
	local fps = state.fps or Session.FPS
	return frames / fps
end

---Real seconds, including the current session's uncommitted wall time.
---@param state table
---@param now number?
---@return number
function Session.rtaSeconds(state, now)
	local seconds = state.rtaSeconds or 0
	if state.sessionStartAt ~= nil and now ~= nil then
		local delta = now - state.sessionStartAt
		if delta > 0 then
			seconds = seconds + delta
		end
	end
	return seconds
end

---Records newly observed milestones with their clocks. Returns the ids that were added.
---@param state table
---@param observed table<string, boolean>
---@param order table<string>
---@param framesNow number
---@param now number
---@return table<string>
function Session.addMilestones(state, observed, order, framesNow, now)
	local added = {}
	if state.phase ~= Session.PHASES.ACTIVE then
		return added
	end
	local igt = Session.igtSeconds(state, framesNow)
	local rta = Session.rtaSeconds(state, now)
	for _, id in ipairs(order) do
		if observed and observed[id] and not state.milestones[id] then
			state.milestones[id] = true
			state.igt[id] = math.floor(igt)
			state.rta[id] = math.floor(rta)
			added[#added + 1] = id
		end
	end
	return added
end

---Marks the given milestones as submitted to the service.
---@param state table
---@param observed table<string, boolean>
function Session.markSubmitted(state, observed)
	for id, reached in pairs(observed or {}) do
		if reached then
			state.submitted[id] = true
		end
	end
end

---Prunes milestones that the current save no longer contains (save rollback).
---@param state table
---@param observed table<string, boolean>
---@return table<string> removed
function Session.rollback(state, observed)
	local removed = {}
	for id in pairs(state.milestones) do
		if not (observed and observed[id]) then
			removed[#removed + 1] = id
			state.milestones[id] = nil
			state.igt[id] = nil
			state.rta[id] = nil
			state.submitted[id] = nil
		end
	end
	if #removed > 0 then
		state.rollbacks = (state.rollbacks or 0) + 1
	end
	table.sort(removed)
	return removed
end

---@param state table
---@param framesNow number
---@param now number
---@param reason string?
function Session.finish(state, framesNow, now, reason)
	Session.suspend(state, framesNow, now)
	state.phase = Session.PHASES.FINISHED
	state.finishedAt = now
	state.finishReason = reason or "finished"
end

---@param state table
---@param reason string
---@param now number?
function Session.void(state, reason, now)
	state.phase = Session.PHASES.VOID
	state.voidReason = reason or "voided"
	state.finishedAt = now or state.finishedAt
end

---@param state table
---@return boolean
function Session.isActive(state)
	return type(state) == "table" and state.phase == Session.PHASES.ACTIVE
end

---Validates a deserialised state.
---@param state table
---@return boolean ok, string? err
function Session.validate(state)
	if type(state) ~= "table" then
		return false, "state is not an object"
	end
	if state.version ~= Session.VERSION then
		return false, "unsupported state version"
	end
	if type(state.date) ~= "string" or type(state.mode) ~= "string" then
		return false, "state missing date/mode"
	end
	if not isPhase(state.phase) then
		return false, "state has an unknown phase"
	end
	if type(state.milestones) ~= "table" or type(state.igt) ~= "table" or type(state.rta) ~= "table" then
		return false, "state milestones malformed"
	end
	return true
end

---Returns a plain table (the state itself is already JSON-friendly).
---@param state table
---@return table
function Session.toTable(state)
	return state
end

---@param tableValue table
---@return table? state, string? err
function Session.fromTable(tableValue)
	local ok, err = Session.validate(tableValue)
	if not ok then
		return nil, err
	end
	return tableValue
end

return Session
