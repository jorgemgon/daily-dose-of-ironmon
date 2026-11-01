-- curl-based HTTP transport. The tracker has no usable HTTP client: outbound calls are made by
-- shelling out to curl, which must only happen off the per-frame path.

local Http = {}

Http.DEFAULT_TIMEOUT = 20

local function quote(value)
	return '"' .. tostring(value):gsub('"', '\\"') .. '"'
end

---Builds the curl command line.
---@param opts table {url, method, bodyFile, outputFile, headers, timeout}
---@return string
function Http.buildCurl(opts)
	local parts = { "curl --ssl-no-revoke -sS --compressed" }
	parts[#parts + 1] = "-m " .. tostring(opts.timeout or Http.DEFAULT_TIMEOUT)
	parts[#parts + 1] = "-X " .. tostring(opts.method or "GET")
	for name, value in pairs(opts.headers or {}) do
		parts[#parts + 1] = string.format("-H %s", quote(string.format("%s: %s", name, value)))
	end
	if opts.bodyFile then
		parts[#parts + 1] = '-H "Content-Type: application/json"'
		parts[#parts + 1] = "--data-binary @" .. quote(opts.bodyFile)
	end
	if opts.outputFile then
		parts[#parts + 1] = "-o " .. quote(opts.outputFile)
	end
	-- The status code is the last line on stdout; FileManager.tryOsExecute captures stdout.
	parts[#parts + 1] = '-w "\\n%{http_code}"'
	parts[#parts + 1] = quote(opts.url)
	return table.concat(parts, " ")
end

---Extracts the HTTP status from captured curl stdout (the `-w` trailer).
---@param captured string
---@return number? status
function Http.parseStatus(captured)
	local last
	for line in tostring(captured or ""):gmatch("[^\r\n]+") do
		last = line
	end
	local status = tonumber((last or ""):match("^%s*(%d%d%d)%s*$"))
	return status
end

---Performs a request.
---@param opts table {url, method, body, headers, timeout, workDir}
---@param io table {writeFile, readFile, run, remove} file/shell adapter
---@return table {status = number?, body = string?, err = string?}
function Http.request(opts, io)
	if type(io) ~= "table" or type(io.run) ~= "function" then
		return { err = "http transport not configured" }
	end
	local dir = opts.workDir or "."
	local tag = tostring(math.random(100000, 999999))
	local bodyFile = dir .. "/request-" .. tag .. ".json"
	local outputFile = dir .. "/response-" .. tag .. ".json"

	if opts.body ~= nil then
		if not io.writeFile(bodyFile, opts.body) then
			return { err = "could not write request body" }
		end
	else
		bodyFile = nil
	end

	local command = Http.buildCurl({
		url = opts.url,
		method = opts.method,
		bodyFile = bodyFile,
		outputFile = outputFile,
		headers = opts.headers,
		timeout = opts.timeout,
	})
	local ok, captured = io.run(command)
	local status = Http.parseStatus(captured)
	local body = io.readFile(outputFile)

	if bodyFile then
		io.remove(bodyFile)
	end
	io.remove(outputFile)

	if not ok and not status then
		return { err = "network request failed" }
	end
	if not status then
		return { err = "no HTTP status in response" }
	end
	return { status = status, body = body or "" }
end

return Http
