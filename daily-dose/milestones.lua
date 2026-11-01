-- Milestone order and detection helpers.
-- The order is the wire contract with the service; scoring tables must list these ids in order.

local Milestones = {}

Milestones.ORDER = {
	"b1",
	"b2",
	"b3",
	"b4",
	"b5",
	"b6",
	"b7",
	"b8",
	"e4_lorelei",
	"e4_bruno",
	"e4_agatha",
	"e4_lance",
	"champion",
}

Milestones.INDEX = {}
for i, id in ipairs(Milestones.ORDER) do
	Milestones.INDEX[id] = i
end

Milestones.BADGE_IDS = {
	"b1",
	"b2",
	"b3",
	"b4",
	"b5",
	"b6",
	"b7",
	"b8",
}

-- FireRed Elite Four trainer ids, in room order.
Milestones.E4_TRAINERS = {
	[410] = "e4_lorelei",
	[411] = "e4_bruno",
	[412] = "e4_agatha",
	[413] = "e4_lance",
}

-- FireRed champion trainer ids (the three rival variants), per TrainerData.FinalTrainer.
Milestones.FINAL_TRAINERS = {
	[438] = true,
	[439] = true,
	[440] = true,
}

function Milestones.isKnown(id)
	return Milestones.INDEX[id] ~= nil
end

function Milestones.isFinalTrainer(trainerId)
	return Milestones.FINAL_TRAINERS[tonumber(trainerId) or -1] == true
end

function Milestones.e4ForTrainer(trainerId)
	return Milestones.E4_TRAINERS[tonumber(trainerId) or -1]
end

-- A reached milestone implies everything before it (champion implies all of them).
local function applyClosure(set)
	local deepest = 0
	for id, reached in pairs(set) do
		if reached and Milestones.INDEX[id] and Milestones.INDEX[id] > deepest then
			deepest = Milestones.INDEX[id]
		end
	end
	for i = 1, deepest do
		set[Milestones.ORDER[i]] = true
	end
	return set
end

---Builds the reached set from a tracker observation.
---@param observation table {badges = {boolean...}, defeated = {[trainerId]=true}, champion = boolean}
---@return table<string, boolean>
function Milestones.fromObservation(observation)
	observation = observation or {}
	local set = {}
	local badges = observation.badges or {}
	for i = 1, math.min(8, #badges) do
		if badges[i] then
			set[Milestones.BADGE_IDS[i]] = true
		end
	end
	local defeated = observation.defeated or {}
	for trainerId, isDefeated in pairs(defeated) do
		if isDefeated then
			local id = Milestones.E4_TRAINERS[tonumber(trainerId) or -1]
			if id then
				set[id] = true
			end
		end
	end
	if observation.champion then
		set.champion = true
	end
	return applyClosure(set)
end

---@param set table<string, boolean>
---@return string? id
function Milestones.deepest(set)
	local bestId, bestIndex = nil, 0
	for id, reached in pairs(set or {}) do
		local index = Milestones.INDEX[id]
		if reached and index and index > bestIndex then
			bestId, bestIndex = id, index
		end
	end
	return bestId
end

---@param set table<string, boolean>
---@return table<string>
function Milestones.toOrderedList(set)
	local list = {}
	for _, id in ipairs(Milestones.ORDER) do
		if set and set[id] then
			list[#list + 1] = id
		end
	end
	return list
end

---Returns ids that were already submitted but are missing from the observation (a rewind).
---@param submitted table<string, boolean>
---@param observed table<string, boolean>
---@return table<string>
function Milestones.missing(submitted, observed)
	local missing = {}
	for _, id in ipairs(Milestones.ORDER) do
		if submitted and submitted[id] and not (observed and observed[id]) then
			missing[#missing + 1] = id
		end
	end
	return missing
end

---Prunes a set to the given observation (used for save rollbacks).
---@param set table<string, boolean>
---@param observed table<string, boolean>
---@return table<string, boolean>
function Milestones.intersect(set, observed)
	local out = {}
	for _, id in ipairs(Milestones.ORDER) do
		if set and set[id] and observed and observed[id] then
			out[id] = true
		end
	end
	return out
end

function Milestones.union(a, b)
	local out = {}
	for id, reached in pairs(a or {}) do
		if reached then
			out[id] = true
		end
	end
	for id, reached in pairs(b or {}) do
		if reached then
			out[id] = true
		end
	end
	return out
end

return Milestones
