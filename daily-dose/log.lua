-- Open-book log handling: the Tracker parses a ZX-format log next to the ROM.
-- If local generation did not leave one, the canonical text log is fetched (text only).

local Log = {}

---@param deps table {util, sha256File, logPath, manifest, curlPath}
---@return boolean ok, string? err
function Log.ensure(deps)
	local util = deps.util
	local manifest = deps.manifest
	local logPath = deps.logPath

	if util.fileExists(logPath) then
		if manifest.log_sha256 then
			local sha = util.sha256File(logPath)
			if sha == manifest.log_sha256 then
				return true
			end
		else
			return true
		end
	end

	if type(manifest.log_url) ~= "string" or manifest.log_url == "" then
		return false, "no log next to the ROM and no published log URL"
	end

	local tmp = logPath .. ".download"
	local command = string.format('curl --ssl-no-revoke -sS -L -o %s %s', util.quote(tmp), util.quote(manifest.log_url))
	local ok = util.run(command)
	if not ok or not util.fileExists(tmp) then
		util.removeFile(tmp)
		return false, "log download failed"
	end
	if manifest.log_sha256 then
		local sha = util.sha256File(tmp)
		if sha ~= manifest.log_sha256 then
			util.removeFile(tmp)
			return false, "downloaded log hash mismatch"
		end
	end
	if not util.copyFile(tmp, logPath) then
		util.removeFile(tmp)
		return false, "could not store log"
	end
	util.removeFile(tmp)
	return true
end

---Enables the tracker's open-book mode so the log is preloaded.
---@param deps table {trackerApi}
---@return boolean
function Log.enableOpenBook(deps)
	local trackerApi = deps.trackerApi or _G.TrackerAPI
	if not trackerApi or type(trackerApi.setOption) ~= "function" then
		return false
	end
	return trackerApi.setOption("Open Book Play Mode", true) == true
end

---Opens the Tracker's own current-log viewer (same action as Extras -> View Logs -> View Current
---Log), which autodetects the log next to the loaded ROM. Falls back to the warning screen, then
---to the bare LogOverlay screen.
---@param deps table {program, logOverlay, viewLogWarning}
---@return boolean
function Log.openOverlay(deps)
	local overlay = deps.logOverlay or _G.LogOverlay
	local fileManager = _G.FileManager
	if overlay and fileManager and fileManager.PostFixes and type(overlay.viewLogFile) == "function" then
		overlay.viewLogFile(fileManager.PostFixes.AUTORANDOMIZED)
		return true
	end

	local program = deps.program or _G.Program
	local warning = deps.viewLogWarning or _G.ViewLogWarningScreen
	if program and type(program.changeScreenView) == "function" then
		if warning then
			program.changeScreenView(warning)
			return true
		end
		if overlay then
			program.changeScreenView(overlay)
			return true
		end
	end
	return false
end

return Log
