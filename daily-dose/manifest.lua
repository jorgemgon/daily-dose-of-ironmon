-- Validation and normalisation of the daily challenge manifest.
-- The manifest is the wire contract with the service; see docs/api.md.

local Manifest = {}

local DATE_PATTERN = "^%d%d%d%d%-%d%d%-%d%d$"
local function isHex(value, length)
	return type(value) == "string" and #value == length and value:match("^%x+$") ~= nil
end

local function isPositiveInteger(value)
	return type(value) == "number" and value > 0 and value % 1 == 0
end

---@param manifest table
---@param opts table? {mode = string, milestones = table}
---@return boolean ok, string? err
function Manifest.validate(manifest, opts)
	opts = opts or {}
	local order = opts.milestones
	if type(manifest) ~= "table" then
		return false, "manifest is not an object"
	end
	if type(manifest.date) ~= "string" or not manifest.date:match(DATE_PATTERN) then
		return false, "invalid date"
	end
	if opts.mode and manifest.mode ~= opts.mode then
		return false, "unexpected mode " .. tostring(manifest.mode)
	end
	if not isPositiveInteger(tonumber(manifest.seed)) then
		return false, "invalid seed"
	end
	if not isHex(manifest.base_sha1, 40) then
		return false, "invalid base_sha1"
	end
	if not isHex(manifest.rom_sha1, 40) then
		return false, "invalid rom_sha1"
	end
	if not isHex(manifest.jar_sha256, 64) then
		return false, "invalid jar_sha256"
	end
	if type(manifest.jar_url) ~= "string" or not manifest.jar_url:match("^https://") then
		return false, "invalid jar_url"
	end
	if type(manifest.settings_string) ~= "string" or manifest.settings_string == "" then
		return false, "missing settings_string"
	end
	if not isHex(manifest.settings_sha256, 64) then
		return false, "invalid settings_sha256"
	end
	if not isHex(manifest.ips_sha256, 64) then
		return false, "invalid ips_sha256"
	end
	if type(manifest.weights_preset) ~= "string" or manifest.weights_preset == "" then
		return false, "missing weights_preset"
	end
	if not isPositiveInteger(tonumber(manifest.score_version)) then
		return false, "invalid score_version"
	end
	if type(manifest.reset_at) ~= "number" then
		return false, "invalid reset_at"
	end
	if type(manifest.milestones) ~= "table" or #manifest.milestones == 0 then
		return false, "missing milestones"
	end
	if order then
		if #manifest.milestones ~= #order then
			return false, "milestone count does not match the published order"
		end
		for i, id in ipairs(order) do
			local entry = manifest.milestones[i]
			if type(entry) ~= "table" or entry.id ~= id then
				return false, "milestone order mismatch at " .. id
			end
			if not isPositiveInteger(tonumber(entry.points)) then
				return false, "invalid points for " .. tostring(id)
			end
			if not isPositiveInteger(tonumber(entry.par_igt)) then
				return false, "invalid par_igt for " .. tostring(id)
			end
			if not isPositiveInteger(tonumber(entry.par_rta)) then
				return false, "invalid par_rta for " .. tostring(id)
			end
		end
	end
	local totals = Manifest.totals(manifest)
	if totals.points ~= 1000 then
		return false, "points do not sum to 1000"
	end
	return true
end

---@param manifest table
---@return table {points = number, parIgt = number, parRta = number}
function Manifest.totals(manifest)
	local total = { points = 0, parIgt = 0, parRta = 0 }
	for _, entry in ipairs(manifest.milestones or {}) do
		total.points = total.points + (tonumber(entry.points) or 0)
		total.parIgt = total.parIgt + (tonumber(entry.par_igt) or 0)
		total.parRta = total.parRta + (tonumber(entry.par_rta) or 0)
	end
	return total
end

---Builds scoring tables for a timebase ("igt" or "rta").
---@param manifest table
---@param timebase string
---@return table {order = table, points = table, par = table}
function Manifest.scoringTables(manifest, timebase)
	local order, points, par = {}, {}, {}
	local key = timebase == "rta" and "par_rta" or "par_igt"
	for _, entry in ipairs(manifest.milestones or {}) do
		order[#order + 1] = entry.id
		points[entry.id] = tonumber(entry.points)
		par[entry.id] = tonumber(entry[key])
	end
	return { order = order, points = points, par = par }
end

---@param manifest table
---@param now number? unix seconds
---@return string state "upcoming"|"open"|"grace"|"closed"
function Manifest.window(manifest, now)
	now = now or os.time()
	local resetAt = tonumber(manifest.reset_at) or 0
	local graceUntil = resetAt + (tonumber(manifest.grace_seconds) or 6 * 3600)
	if now >= graceUntil then
		return "closed"
	elseif now >= resetAt then
		return "grace"
	end
	return "open"
end

---@param manifest table
---@param date string YYYY-MM-DD
---@return boolean
function Manifest.isForDate(manifest, date)
	return manifest.date == date
end

---Builds the generation arguments for the pinned jar.
---@param manifest table
---@param baseRomPath string
---@param ipsPath string
---@param outputPath string
---@param withLog boolean?
---@return table<string>
function Manifest.generationArgs(manifest, baseRomPath, ipsPath, outputPath, withLog)
	local args = {
		"-i",
		baseRomPath,
		"-o",
		outputPath,
		"-z",
		tostring(manifest.seed),
		"-S",
		manifest.settings_string,
		"--base-ips",
		ipsPath,
		"--weights-preset",
		manifest.weights_preset or "daily-v1",
		"--guaranteed-catch",
	}
	if withLog ~= false then
		args[#args + 1] = "-l"
		args[#args + 1] = "--log-format"
		args[#args + 1] = "zx"
	end
	if manifest.event and type(manifest.event.type_biases) == "table" then
		local types = {}
		for key in pairs(manifest.event.type_biases) do
			types[#types + 1] = tostring(key)
		end
		table.sort(types)
		for _, key in ipairs(types) do
			args[#args + 1] = "--type-bias"
			args[#args + 1] = string.format("%s=%s", key, tostring(manifest.event.type_biases[key]))
		end
		if manifest.event.scope then
			args[#args + 1] = "--type-bias-scope"
			args[#args + 1] = tostring(manifest.event.scope)
		end
	end
	return args
end

return Manifest
