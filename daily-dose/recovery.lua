-- Handle recovery: the admin issues a one-time code out of band, the player redeems it here.

local Recovery = {}

---@param api table
---@param handle string
---@param code string
---@return boolean ok, table|string result
function Recovery.redeem(api, handle, code)
	if type(handle) ~= "string" or handle == "" then
		return false, "enter your handle"
	end
	if type(code) ~= "string" or #code < 4 then
		return false, "enter the recovery code from the admin"
	end
	local response = api:recover(handle, code:upper():gsub("%s", ""))
	if not response or response.err then
		return false, response and response.err or "network request failed"
	end
	if response.status ~= 200 or type(response.data) ~= "table" then
		local message = response.data and response.data.message or ("server returned " .. tostring(response.status))
		return false, message
	end
	if type(response.data.token) ~= "string" or response.data.token == "" then
		return false, "server response did not include a token"
	end
	return true, {
		handle = response.data.handle or handle,
		token = response.data.token,
	}
end

return Recovery
