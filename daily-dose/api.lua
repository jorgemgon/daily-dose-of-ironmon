-- HTTP API wrappers. All calls are explicit and rate-limited by the caller.

local Api = {}
Api.__index = Api

---@param baseUrl string
---@param http table Http module
---@param json table Json module
---@param workDir string
function Api.new(baseUrl, http, json, workDir)
	return setmetatable({
		baseUrl = (baseUrl or ""):gsub("/+$", ""),
		http = http,
		json = json,
		workDir = workDir or ".",
	}, Api)
end

function Api:url(path)
	return self.baseUrl .. path
end

function Api:request(method, path, body, token)
	local headers = {}
	if token and token ~= "" then
		headers["Authorization"] = "Bearer " .. token
	end
	local payload
	if body ~= nil then
		payload = self.json.encode(body)
	end
	local response = self.http.request({
		url = self:url(path),
		method = method,
		body = payload,
		headers = headers,
		workDir = self.workDir,
	})
	if response.err then
		return { err = response.err }
	end
	local data
	if response.body and response.body ~= "" then
		local decoded, decodeErr = self.json.decode(response.body)
		if decodeErr then
			return { status = response.status, err = "invalid JSON: " .. decodeErr, body = response.body }
		end
		data = decoded
	end
	return { status = response.status, data = data, body = response.body }
end

function Api:getDaily(date)
	local path = "/api/daily"
	if date and date ~= "" then
		path = path .. "?date=" .. date
	end
	return self:request("GET", path)
end

function Api:createTwitchSession()
	return self:request("POST", "/api/auth/twitch/session", {})
end

function Api:pollTwitchSession(sessionId, pollToken)
	return self:request("POST", "/api/auth/twitch/session/" .. sessionId .. "/poll", { poll_token = pollToken })
end

function Api:register(handle, deviceId)
	return self:request("POST", "/api/players", { handle = handle, device_id = deviceId })
end

function Api:recover(handle, code)
	return self:request("POST", "/api/players/recover", { handle = handle, code = code })
end

function Api:intent(date, romSha1, deviceId, token)
	return self:request("POST", "/api/runs/intent", {
		date = date,
		mode = "kaizo",
		rom_sha1 = romSha1,
		device_id = deviceId,
	}, token)
end

function Api:confirm(runId, runToken, payload)
	return self:request("POST", "/api/runs/" .. runId .. "/confirm", payload, runToken)
end

function Api:resume(runId, runToken, payload)
	return self:request("POST", "/api/runs/" .. runId .. "/resume", payload, runToken)
end

function Api:progress(runId, runToken, payload)
	return self:request("PATCH", "/api/runs/" .. runId, payload, runToken)
end

function Api:diagnostics(payload)
	return self:request("POST", "/api/diagnostics", payload)
end

return Api
