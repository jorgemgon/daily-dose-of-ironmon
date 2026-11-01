-- Small utilities: paths, files, shell capture, hashing, time formatting.
-- Tracker globals are only consulted lazily inside functions, never at load time.

local Util = {}

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

function Util.isWindows()
	return IS_WINDOWS
end

function Util.trim(s)
	if type(s) ~= "string" then
		return ""
	end
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.clamp(n, lo, hi)
	if n < lo then
		return lo
	elseif n > hi then
		return hi
	end
	return n
end

function Util.round(n)
	if n >= 0 then
		return math.floor(n + 0.5)
	end
	return math.ceil(n - 0.5)
end

function Util.quote(path)
	return '"' .. tostring(path):gsub('"', '""') .. '"'
end

function Util.join(...)
	local parts = { ... }
	local out = {}
	for _, part in ipairs(parts) do
		part = tostring(part or "")
		if part ~= "" then
			out[#out + 1] = part:gsub("[/\\]+$", "")
		end
	end
	local sep = IS_WINDOWS and "\\" or "/"
	return table.concat(out, sep) .. (out[#out] and "" or "")
end

function Util.joinPath(base, ...)
	local parts = { ... }
	local out = tostring(base or ""):gsub("[/\\]+$", "")
	local sep = IS_WINDOWS and "\\" or "/"
	for _, part in ipairs(parts) do
		part = tostring(part or ""):gsub("^[/\\]+", ""):gsub("[/\\]+$", "")
		if part ~= "" then
			out = out .. sep .. part
		end
	end
	return out
end

function Util.basename(path)
	return (tostring(path):gsub("^.*[/\\]", ""))
end

function Util.readFile(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local data = fh:read("*a")
	fh:close()
	return data
end

function Util.writeFile(path, data)
	local fh = io.open(path, "wb")
	if not fh then
		return false
	end
	fh:write(data)
	fh:close()
	return true
end

function Util.fileExists(path)
	local fh = io.open(path, "rb")
	if fh then
		fh:close()
		return true
	end
	return false
end

function Util.fileSize(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local size = fh:seek("end")
	fh:close()
	return size
end

function Util.nativePath(path)
	if IS_WINDOWS then
		return tostring(path):gsub("/", "\\")
	end
	return tostring(path)
end

function Util.ensureDir(path)
	if not path or path == "" or Util.fileExists(path) then
		return true
	end
	path = Util.nativePath(path)
	local cmd
	if IS_WINDOWS then
		cmd = string.format('if not exist %s mkdir %s', Util.quote(path), Util.quote(path))
	else
		cmd = string.format('mkdir -p %s', Util.quote(path))
	end
	local ok = os.execute(cmd)
	return ok == true or ok == 0
end

function Util.copyFile(src, dst)
	if IS_WINDOWS then
		src = Util.nativePath(src)
		dst = Util.nativePath(dst)
		local ok = os.execute(string.format("copy /Y %s %s >NUL", Util.quote(src), Util.quote(dst)))
		return ok == true or ok == 0
	end
	local ok = os.execute(string.format("cp -f %s %s", Util.quote(src), Util.quote(dst)))
	return ok == true or ok == 0
end

function Util.removeFile(path)
	if Util.fileExists(path) then
		os.remove(path)
	end
end

-- Runs a shell command and returns success, captured text.
-- Prefers the tracker's helper (which handles quoting/redirects the same way the tracker does).
function Util.run(command)
	local fileManager = rawget(_G, "FileManager")
	if fileManager and type(fileManager.tryOsExecute) == "function" then
		local ok, lines = fileManager.tryOsExecute(command)
		if type(lines) == "table" then
			return ok, table.concat(lines, "\n")
		end
		return ok, tostring(lines or "")
	end

	local tmp = os.tmpname()
	local ok = os.execute(string.format('%s > "%s" 2>&1', command, tmp))
	local text = Util.readFile(tmp) or ""
	os.remove(tmp)
	return ok == true or ok == 0, text
end

local function firstHexLine(text, length)
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		local hex = line:gsub("%s", ""):lower()
		if #hex == length and hex:match("^%x+$") then
			return hex
		end
	end
	return nil
end

function Util.hashFile(path, algorithm)
	local algo = (algorithm or "SHA1"):upper()
	if not Util.fileExists(path) then
		return nil, "file not found"
	end
	local text
	if IS_WINDOWS then
		local ok
		ok, text = Util.run(string.format("certutil -hashfile %s %s", Util.quote(path), algo))
		if not ok then
			return nil, "certutil failed"
		end
	else
		local cmd
		if algo == "SHA1" then
			cmd = string.format("shasum -a 1 %s || sha1sum %s", Util.quote(path), Util.quote(path))
		elseif algo == "SHA256" then
			cmd = string.format("shasum -a 256 %s || sha256sum %s", Util.quote(path), Util.quote(path))
		else
			return nil, "unsupported algorithm"
		end
		local ok
		ok, text = Util.run(cmd)
		if not ok then
			return nil, "hash tool failed"
		end
	end
	local hex = firstHexLine(text, algo == "SHA1" and 40 or 64)
	if not hex then
		return nil, "hash not found in tool output"
	end
	return hex
end

function Util.sha1File(path)
	return Util.hashFile(path, "SHA1")
end

function Util.sha256File(path)
	return Util.hashFile(path, "SHA256")
end

function Util.randomHex(bytes)
	local chars = {}
	local alphabet = "0123456789abcdef"
	for _ = 1, (bytes or 16) do
		local hi = math.random(1, 16)
		local lo = math.random(1, 16)
		chars[#chars + 1] = alphabet:sub(hi, hi)
		chars[#chars + 1] = alphabet:sub(lo, lo)
	end
	return table.concat(chars)
end

function Util.seedRandom()
	local seed = os.time() + math.floor((os.clock() or 0) * 1000)
	math.randomseed(seed)
	math.random()
end

function Util.utcDate(timestamp)
	return os.date("!%Y-%m-%d", timestamp or os.time())
end

function Util.utcDateTime(timestamp)
	return os.date("!%Y-%m-%dT%H:%M:%SZ", timestamp or os.time())
end

function Util.secondsUntilUtcMidnight(timestamp)
	local t = os.date("!*t", timestamp or os.time())
	local secondsToday = (t.hour or 0) * 3600 + (t.min or 0) * 60 + (t.sec or 0)
	return 86400 - secondsToday
end

function Util.formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm %02ds", h, m, s)
	end
	return string.format("%dm %02ds", m, s)
end

function Util.formatClock(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	return string.format("%d:%02d:%02d", h, m, s)
end

function Util.startsWith(text, prefix)
	return tostring(text):sub(1, #prefix) == prefix
end

function Util.tableCount(t)
	local count = 0
	for _ in pairs(t or {}) do
		count = count + 1
	end
	return count
end

function Util.copyTable(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = Util.copyTable(v)
	end
	return copy
end

function Util.sortedKeys(t)
	local keys = {}
	for k in pairs(t or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

return Util
