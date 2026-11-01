-- Score arithmetic. The service is authoritative; this mirrors the published formula for
-- on-screen projections. Points and par values always come from the daily manifest.

local Score = {}

-- Speed is a within-tier tiebreak: 0..999, always smaller than one point of progress.
function Score.speed(parSeconds, seconds)
	parSeconds = tonumber(parSeconds)
	seconds = tonumber(seconds)
	if not parSeconds or not seconds or parSeconds <= 0 or seconds <= 0 then
		return 0
	end
	local ratio = parSeconds / seconds
	local value = math.floor((ratio - 0.5) * 999)
	return math.floor(math.max(0, math.min(999, value)))
end

---Validates a manifest-provided scoring table.
---@param tables table {order = {id...}, points = {[id]=n}, par = {[id]=s}}
---@return boolean ok, string? err
function Score.validateTables(tables)
	if type(tables) ~= "table" then
		return false, "scoring tables missing"
	end
	local order = tables.order
	local points = tables.points
	local par = tables.par
	if type(order) ~= "table" or #order == 0 then
		return false, "scoring order missing"
	end
	if type(points) ~= "table" or type(par) ~= "table" then
		return false, "scoring points/par missing"
	end
	for _, id in ipairs(order) do
		local p = tonumber(points[id])
		local t = tonumber(par[id])
		if not p or p <= 0 then
			return false, "invalid points for " .. tostring(id)
		end
		if not t or t <= 0 then
			return false, "invalid par for " .. tostring(id)
		end
	end
	return true
end

---Progress is the sum of points of every milestone up to and including the deepest reached.
---A gap in the reached set never reduces the score (depth is what matters).
---@param reached table<string, boolean>
---@param tables table
---@return number points, string? milestone
function Score.progress(reached, tables)
	reached = reached or {}
	local deepestIndex = 0
	for i, id in ipairs(tables.order) do
		if reached[id] and i > deepestIndex then
			deepestIndex = i
		end
	end
	if deepestIndex == 0 then
		return 0, nil
	end
	local total = 0
	for i = 1, deepestIndex do
		total = total + (tonumber(tables.points[tables.order[i]]) or 0)
	end
	return total, tables.order[deepestIndex]
end

---@param reached table<string, boolean>
---@param tables table
---@param seconds number
---@return table {milestone, progress, speed, score}
function Score.compute(reached, tables, seconds)
	local progress, deepest = Score.progress(reached, tables)
	local par = deepest and tonumber(tables.par[deepest]) or nil
	local speed = (par and seconds) and Score.speed(par, seconds) or 0
	return {
		milestone = deepest,
		progress = progress,
		speed = speed,
		score = progress * 1000 + speed,
	}
end

return Score
