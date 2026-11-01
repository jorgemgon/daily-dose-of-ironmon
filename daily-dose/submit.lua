-- Persisted upload queue. One request is attempted per flush; failures back off exponentially.
-- The queue lives in daily-dose/state/queue.json so a tracker/emulator restart never loses progress.

local Submit = {}

Submit.MAX_ATTEMPTS = 8
Submit.BACKOFF_SECONDS = 15

---@param json table Json module
---@param util table Util module
---@param path string
---@return table entries
function Submit.load(json, util, path)
	local text = util.readFile(path)
	if not text or text == "" then
		return {}
	end
	local decoded = json.decode(text)
	return type(decoded) == "table" and decoded or {}
end

function Submit.save(json, util, path, entries)
	return util.writeFile(path, json.encode(entries or {}))
end

---@param json table
---@param util table
---@param path string
---@param entry table {kind, runId, token, payload}
---@param now number
---@return boolean
function Submit.enqueue(json, util, path, entry, now)
	local entries = Submit.load(json, util, path)
	entry.attempts = 0
	entry.nextAt = now or os.time()
	entries[#entries + 1] = entry
	return Submit.save(json, util, path, entries)
end

local function applyResponse(api, entry)
	if entry.kind == "progress" then
		return api:progress(entry.runId, entry.token, entry.payload)
	elseif entry.kind == "confirm" then
		return api:confirm(entry.runId, entry.token, entry.payload)
	elseif entry.kind == "resume" then
		return api:resume(entry.runId, entry.token, entry.payload)
	elseif entry.kind == "diagnostics" then
		return api:diagnostics(entry.payload)
	end
	return { err = "unknown queue entry kind" }
end

---Processes at most one due entry.
---@param deps table {json, util, path, api, now}
---@return table {processed = boolean, dropped = number, authError = boolean?, conflict = boolean?}
function Submit.flush(deps)
	local util = deps.util
	local json = deps.json
	local now = deps.now or os.time()
	local entries = Submit.load(json, util, deps.path)
	local result = { processed = false, dropped = 0 }

	local index = nil
	for i, entry in ipairs(entries) do
		if (entry.nextAt or 0) <= now then
			index = i
			break
		end
	end
	if not index then
		return result
	end

	local entry = entries[index]
	local response = applyResponse(deps.api, entry)
	result.processed = true
	local status = response and response.status

	if response and response.err then
		entry.attempts = (entry.attempts or 0) + 1
		if entry.attempts >= Submit.MAX_ATTEMPTS then
			table.remove(entries, index)
			result.dropped = result.dropped + 1
		else
			entry.nextAt = now + Submit.BACKOFF_SECONDS * (2 ^ (entry.attempts - 1))
			entry.lastError = response.err
		end
	elseif status == 401 or status == 403 then
		table.remove(entries, index)
		result.dropped = result.dropped + 1
		result.authError = true
	elseif status == 409 or status == 410 then
		table.remove(entries, index)
		result.dropped = result.dropped + 1
		result.conflict = true
	elseif status and status >= 500 then
		entry.attempts = (entry.attempts or 0) + 1
		if entry.attempts >= Submit.MAX_ATTEMPTS then
			table.remove(entries, index)
			result.dropped = result.dropped + 1
		else
			entry.nextAt = now + Submit.BACKOFF_SECONDS * (2 ^ (entry.attempts - 1))
		end
	else
		table.remove(entries, index)
		result.lastResponse = response
	end

	Submit.save(json, util, deps.path, entries)
	return result
end

return Submit
