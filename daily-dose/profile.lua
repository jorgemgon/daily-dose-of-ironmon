-- Creates/updates the Tracker Quickload profile for today's Daily Dose ROM.
-- Tracker globals are only touched inside ensure(), never at load time.

local Profile = {}

---Creates or updates a premade profile named "Daily Dose <date>" with the Kaizo loss condition.
---@param deps table { extDir, romPath }
---@return boolean ok
function Profile.ensure(deps)
	local FileManager = _G.FileManager
	local Utils = _G.Utils
	if not FileManager or not Utils or not deps then
		return false
	end
	local path = FileManager.prependDir(FileManager.Files.NEWRUN_PROFILES)
	local profiles = FileManager.fileExists(path) and FileManager.decodeJsonFile(path) or {}
	if type(profiles) ~= "table" then
		profiles = {}
	end

	local name = "Daily Dose " .. (deps.date or os.date("%Y-%m-%d"))
	local guid = nil
	for key, value in pairs(profiles) do
		if type(value) == "table" and value.Name == name then
			guid = key
			break
		end
	end
	if not guid then
		guid = Utils.newGUID()
	end

	profiles[guid] = {
		GUID = guid,
		Name = name,
		Mode = "Premade",
		GameVersion = "firered",
		GameOverCondition = "LeadPokemonFaints",
		AttemptsCount = 0,
		LastUsedDate = os.time(),
		Paths = {
			RomsFolder = FileManager.tryAppendSlash(deps.extDir .. "/roms"),
			CurrentRom = deps.romPath or "",
		},
	}
	return FileManager.encodeToJsonFile(path, profiles) == true
end

return Profile
