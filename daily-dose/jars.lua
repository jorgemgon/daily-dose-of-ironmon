-- Pinned randomizer jars: use the bundled jar when its hash matches the manifest, otherwise
-- fetch that exact jar (public, hash-verified) into daily-dose/jars/<sha8>.jar.

local Jars = {}

function Jars.pathFor(dir, sha256)
	return dir .. "/" .. tostring(sha256):sub(1, 8) .. ".jar"
end

function Jars.bundledPath(extDir)
	return extDir .. "/jars/ddoz-randomizer.jar"
end

---Ensures a jar matching the manifest is available.
---@param deps table {extDir, util, http, manifest}
---@return string? path, string? err
function Jars.ensure(deps)
	local util = deps.util
	local manifest = deps.manifest
	local dir = deps.extDir .. "/jars"
	if not util.ensureDir(dir) then
		return nil, "cannot create jar directory"
	end

	local candidates = {
		Jars.pathFor(dir, manifest.jar_sha256),
		Jars.bundledPath(deps.extDir),
	}
	for _, path in ipairs(candidates) do
		if util.fileExists(path) then
			local sha, err = util.sha256File(path)
			if not sha then
				return nil, "could not hash " .. path .. ": " .. tostring(err)
			end
			if sha == manifest.jar_sha256 then
				return path
			end
		end
	end

	-- Download the pinned jar (never a ROM).
	local target = Jars.pathFor(dir, manifest.jar_sha256)
	local tmp = target .. ".download"
	local command = string.format('curl --ssl-no-revoke -sS -L -o %s %s', util.quote(tmp), util.quote(manifest.jar_url))
	local ok, output = util.run(command)
	if not ok or not util.fileExists(tmp) then
		return nil, "jar download failed: " .. tostring(output)
	end
	local sha = util.sha256File(tmp)
	if sha ~= manifest.jar_sha256 then
		util.removeFile(tmp)
		return nil, "downloaded jar hash mismatch"
	end
	if not util.copyFile(tmp, target) then
		return nil, "could not store jar"
	end
	util.removeFile(tmp)
	return target
end

return Jars
