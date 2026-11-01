-- Player identity: handle validation, device id and token storage glue.
-- Storage is injected (TrackerAPI + state file) so this module stays testable.

local Identity = {}

Identity.MIN_HANDLE = 2
Identity.MAX_HANDLE = 20

---@param handle string
---@return boolean ok, string? err
function Identity.validateHandle(handle)
	if type(handle) ~= "string" then
		return false, "handle must be text"
	end
	handle = handle:gsub("^%s+", ""):gsub("%s+$", "")
	local length = #handle
	if length < Identity.MIN_HANDLE or length > Identity.MAX_HANDLE then
		return false, string.format("handle must be %d-%d characters", Identity.MIN_HANDLE, Identity.MAX_HANDLE)
	end
	if not handle:match("^[%w]") then
		return false, "handle must start with a letter or digit"
	end
	if not handle:match("^[%w_%.%-]+$") then
		return false, "handle may only contain letters, digits, underscore, dot and dash"
	end
	return true
end

---@param randomHex function
---@return string
function Identity.newDeviceId(randomHex)
	return randomHex(16)
end

---@param token string?
---@return table<string, string>
function Identity.authHeaders(token)
	if not token or token == "" then
		return {}
	end
	return { ["Authorization"] = "Bearer " .. token }
end

---Loads identity from injected storage.
---@param deps table {getSetting = function, readState = function}
---@return table {handle = string?, token = string?, deviceId = string?}
function Identity.load(deps)
	local player = { handle = nil, token = nil, deviceId = nil }
	if deps and deps.readState then
		local stored = deps.readState()
		if type(stored) == "table" then
			player.handle = stored.handle
			player.token = stored.token
			player.deviceId = stored.device_id
		end
	end
	if deps and deps.getSetting then
		player.token = player.token or deps.getSetting("token")
		player.handle = player.handle or deps.getSetting("handle")
		player.deviceId = player.deviceId or deps.getSetting("device_id")
	end
	return player
end

---Persists identity through injected storage.
---@param deps table {setSetting = function, writeState = function}
---@param player table {handle, token, deviceId}
---@return boolean
function Identity.save(deps, player)
	local ok = true
	if deps.setSetting then
		ok = deps.setSetting("token", player.token or "") and ok
		ok = deps.setSetting("handle", player.handle or "") and ok
		ok = deps.setSetting("device_id", player.deviceId or "") and ok
	end
	if deps.writeState then
		ok = deps.writeState({
			handle = player.handle,
			token = player.token,
			device_id = player.deviceId,
		}) and ok
	end
	return ok
end

return Identity
