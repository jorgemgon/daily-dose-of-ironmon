-- Base ROM registration, local generation and identity checks.
-- Nothing here ever uploads or downloads a ROM.

local Rom = {}

function Rom.romDir(extDir)
	return extDir .. "/roms"
end

function Rom.romPath(extDir, date, attempt)
	local suffix = attempt and tonumber(attempt) and tonumber(attempt) > 1 and ("-a" .. tostring(attempt)) or ""
	return Rom.romDir(extDir) .. "/" .. date .. suffix .. ".gba"
end

function Rom.logPath(extDir, date, attempt)
	return Rom.romPath(extDir, date, attempt) .. ".log"
end

function Rom.basePath(extDir)
	return extDir .. "/base/vanilla.gba"
end

function Rom.ipsPath(extDir)
	return extDir .. "/assets/faster-firered-1.2.ips"
end

---Registers the currently loaded vanilla ROM by dumping it to disk.
---@param deps table {extDir, util, memory, gameSettings, config}
---@return boolean ok, string? err
function Rom.dumpBase(deps)
	local config = deps.config
	local util = deps.util
	local gameSettings = deps.gameSettings or _G.GameSettings
	local memory = deps.memory or _G.memory
	if not gameSettings or not memory then
		return false, "tracker memory API unavailable"
	end
	local expected = config.SUPPORTED_BASE_SHA1
	local current = gameSettings.getRomHash and gameSettings.getRomHash() or nil
	if not current or current:lower() ~= expected then
		return false, "the loaded ROM is not a supported FireRed 1.1 image"
	end

	local basePath = Rom.basePath(deps.extDir)
	if not util.ensureDir(basePath:match("^(.*)[/\\][^/\\]+$") or deps.extDir) then
		return false, "cannot create base directory"
	end

	local fh = io.open(basePath, "wb")
	if not fh then
		return false, "cannot write " .. basePath
	end
	local total = config.BASE_ROM_SIZE
	local chunkSize = 65536
	local written = 0
	local ok = true
	while written < total do
		local remaining = total - written
		local size = remaining < chunkSize and remaining or chunkSize
		local bytes = memory.read_bytes_as_array(0x08000000 + written, size)
		if not bytes or #bytes ~= size then
			ok = false
			break
		end
		local chars = {}
		for i = 1, size do
			chars[i] = string.char(bytes[i])
		end
		fh:write(table.concat(chars))
		written = written + size
	end
	fh:close()
	if not ok then
		util.removeFile(basePath)
		return false, "ROM dump failed"
	end
	local sha, err = util.sha1File(basePath)
	if not sha then
		return false, "could not hash dumped ROM: " .. tostring(err)
	end
	if sha ~= expected then
		util.removeFile(basePath)
		return false, "dumped ROM hash mismatch"
	end
	return true
end

---Looks for a vanilla FireRed 1.1 ROM in the Tracker's New Run profiles (or the ROMs folder) and
---copies it to the extension's base folder. Nothing is uploaded.
---@param deps table {extDir, util, config, fileManager, quickload, options}
---@return boolean ok, string? err
function Rom.importBaseFromProfiles(deps)
	local config = deps.config
	local util = deps.util
	local fileManager = deps.fileManager or _G.FileManager
	local quickload = deps.quickload or _G.QuickloadScreen
	local options = deps.options or _G.Options
	if not fileManager or type(fileManager.getFilesFromDirectory) ~= "function" then
		return false, "the tracker file API is unavailable"
	end

	local folders, seen = {}, {}
	local function addFolder(raw)
		if type(raw) ~= "string" or raw == "" then
			return
		end
		local folder = raw:gsub("\\", "/")
		if folder:sub(-1) ~= "/" then
			folder = folder .. "/"
		end
		if not seen[folder] then
			seen[folder] = true
			table.insert(folders, folder)
		end
	end

	addFolder(options and options.FILES and options.FILES["ROMs Folder"])
	if quickload and quickload.Profiles then
		for _, profile in pairs(quickload.Profiles) do
			if profile and profile.Paths then
				addFolder(profile.Paths.RomsFolder)
			end
		end
	end

	for _, folder in ipairs(folders) do
		local files = fileManager.getFilesFromDirectory(folder) or {}
		for _, name in ipairs(files) do
			if tostring(name):lower():match("%.gba$") then
				local path = folder .. name
				local sha = util.sha1File(path)
				if sha == config.SUPPORTED_BASE_SHA1 then
					local dest = Rom.basePath(deps.extDir)
					util.ensureDir(dest:match("^(.*)[/\\][^/\\]+$") or deps.extDir)
					if not util.copyFile(path, dest) then
						return false, "could not copy " .. path
					end
					if util.sha1File(dest) ~= config.SUPPORTED_BASE_SHA1 then
						util.removeFile(dest)
						return false, "copied ROM hash mismatch"
					end
					return true, path
				end
			end
		end
	end

	return false, "no FireRed 1.1 ROM found in the New Run profiles"
end

---Registers a ROM the player picked manually (file prompt). Verifies and copies it locally.
---@param deps table {extDir, util, config, path}
---@return boolean ok, string? err
function Rom.registerFromFile(deps)
	local config = deps.config
	local util = deps.util
	local path = deps.path
	if type(path) ~= "string" or path == "" then
		return false, "no file selected"
	end
	if not util.fileExists(path) then
		return false, "file not found"
	end
	local sha = util.sha1File(path)
	if sha ~= config.SUPPORTED_BASE_SHA1 then
		return false, "not a FireRed (U) 1.1 ROM"
	end
	local dest = Rom.basePath(deps.extDir)
	util.ensureDir(dest:match("^(.*)[/\\][^/\\]+$") or deps.extDir)
	if not util.copyFile(path, dest) then
		return false, "could not copy the ROM"
	end
	if util.sha1File(dest) ~= config.SUPPORTED_BASE_SHA1 then
		util.removeFile(dest)
		return false, "copied ROM hash mismatch"
	end
	return true
end

---Ensures the pinned Faster FireRed patch is available, downloading it from the official
---release asset when it is missing or stale. The patch is public and hash-checked; no ROM
---is ever downloaded.
---@param deps table {extDir, util, config}
---@return string? path, string? err
function Rom.ensureIps(deps)
	local util = deps.util
	local config = deps.config
	local path = Rom.ipsPath(deps.extDir)

	local cachedValid = util.fileExists(path) and util.sha256File(path) == config.IPS_SHA256

	local dir = deps.extDir .. "/assets"
	if not util.ensureDir(dir) then
		return nil, "cannot create assets directory"
	end
	local tmp = path .. ".download"
	local command = string.format(
		"curl --ssl-no-revoke -sS -L -o %s %s",
		util.quote(tmp),
		util.quote(config.IPS_URL)
	)
	local ok, output = util.run(command)
	if not ok or not util.fileExists(tmp) then
		util.removeFile(tmp)
		if cachedValid then
			return path
		end
		return nil, "Faster FireRed patch download failed: " .. tostring(output)
	end
	local sha = util.sha256File(tmp)
	if sha ~= config.IPS_SHA256 then
		util.removeFile(tmp)
		if cachedValid then
			return path
		end
		return nil, "downloaded Faster FireRed patch hash mismatch"
	end
	if not util.copyFile(tmp, path) then
		util.removeFile(tmp)
		return nil, "could not store Faster FireRed patch"
	end
	util.removeFile(tmp)
	return path
end

---Checks the local assets against the manifest before generating.
---@param deps table {extDir, util, manifest, config}
---@return boolean ok, string? err, table info
function Rom.preflight(deps)
	local config = deps.config
	local util = deps.util
	local manifest = deps.manifest
	local info = {}

	if not util.fileExists(Rom.basePath(deps.extDir)) then
		return false, "base ROM not registered", info
	end
	local baseSha = util.sha1File(Rom.basePath(deps.extDir))
	info.baseSha = baseSha
	if baseSha ~= config.SUPPORTED_BASE_SHA1 then
		return false, "base ROM hash does not match FireRed 1.1", info
	end

	if manifest.ips_sha256 then
		if deps.useIps == false then
			return false, "this challenge requires the Faster FireRed patch", info
		end
		local ips, ipsErr = Rom.ensureIps({ extDir = deps.extDir, util = util, config = config })
		if not ips then
			return false, ipsErr or "Faster FireRed patch is unavailable", info
		end
		local ipsSha = util.sha256File(ips)
		info.ipsSha = ipsSha
		if ipsSha ~= manifest.ips_sha256 then
			return false, "Faster FireRed patch hash does not match the manifest", info
		end
	end

	local settingsFile = deps.extDir .. "/state/.settings.tmp"
	if not util.ensureDir(deps.extDir .. "/state") then
		return false, "cannot create state directory", info
	end
	if not util.writeFile(settingsFile, manifest.settings_string) then
		return false, "cannot stage settings string for hashing", info
	end
	local settingsSha = util.sha256File(settingsFile)
	util.removeFile(settingsFile)
	info.settingsSha = settingsSha
	if settingsSha ~= manifest.settings_sha256 then
		return false, "settings string hash does not match the manifest", info
	end

	return true, nil, info
end

---Builds the generation command line from manifest-provided arguments.
---@param javaPath string
---@param jarPath string
---@param args table<string>
---@return string
function Rom.buildGenerationCommand(javaPath, jarPath, args)
	local quoted = {}
	for _, arg in ipairs(args) do
		arg = tostring(arg)
		if arg:sub(1, 1) == "-" then
			quoted[#quoted + 1] = arg
		else
			quoted[#quoted + 1] = '"' .. arg:gsub('"', '\\"') .. '"'
		end
	end
	return string.format(
		'"%s" -Xmx2G -jar %s cli %s',
		javaPath:gsub('"', ''),
		'"' .. jarPath:gsub('"', '\\"') .. '"',
		table.concat(quoted, " ")
	)
end

---Reads a Java executable's major version, or nil when it cannot be determined.
---@param util table
---@param javaPath string
---@return number? major
---Runs a command with explicit stdout/stderr files; returns success, stdout, stderr.
---@param util table
---@param command string
---@param outFile string
---@param errFile string
---@return boolean ok, string stdout, string stderr
function Rom.exec(util, command, outFile, errFile)
	util.removeFile(outFile)
	util.removeFile(errFile)

	-- Prefer io.popen: it captures both streams without depending on shell redirection order.
	local windows = package.config:sub(1, 1) == "\\"
	local shellCommand = command
	if windows then
		-- cmd pairs the first and last quote when a command starts and ends with quotes;
		-- wrap the whole line so the executable path stays intact.
		shellCommand = '"' .. command .. '"'
	end

	if io and type(io.popen) == "function" then
		local handle, popenErr = io.popen(shellCommand .. " 2>&1")
		if handle then
			local output = handle:read("*a") or ""
			handle:close()
			print(string.format("[DDI] exec captured %d bytes", #output))
			return true, output, ""
		end
		print("[DDI] io.popen unavailable: " .. tostring(popenErr))
	end

	local redirectedCommand = string.format('%s >"%s" 2>"%s"', shellCommand, outFile, errFile)
	print("[DDI] exec: " .. redirectedCommand)
	local ok = os.execute(redirectedCommand)
	local stdout = util.readFile(outFile) or ""
	local stderr = util.readFile(errFile) or ""
	print(string.format(
		"[DDI] exec result=%s stdout=%d stderr=%d outExists=%s errExists=%s",
		tostring(ok), #stdout, #stderr,
		tostring(util.fileExists(outFile)), tostring(util.fileExists(errFile))
	))
	util.removeFile(outFile)
	util.removeFile(errFile)
	return ok == true or ok == 0, stdout, stderr
end

function Rom.javaMajor(util, javaPath, extDir)
	local text = ""
	if extDir then
		util.ensureDir(extDir .. "/state")
		local ok, stdout, stderr = Rom.exec(
			util,
			string.format('%s -version', javaPath),
			extDir .. "/state/.java.out",
			extDir .. "/state/.java.err"
		)
		text = (stdout or "") .. (stderr or "")
	else
		local ok, output = util.run(string.format('%s -version 2>&1', javaPath))
		text = tostring(output or "")
	end
	return tonumber(text:match('version "(%d+)'))
end

---Picks a Java 21+ executable: the configured one, else JAVA_HOME, else Gradle-provisioned JDKs.
---@param deps table {util, javaPath, fileManager}
---@return string? javaPath, number? major
function Rom.resolveJava(deps)
	local util = deps.util
	local configured = deps.javaPath
	if configured and util.fileExists(configured) then
		local major = Rom.javaMajor(util, configured, deps.extDir)
		if major and major >= 21 then
			print(string.format("[DDI] java: %s (major %s)", tostring(configured), tostring(major)))
			return configured, major
		end
	end

	local candidates = {}
	local home = os.getenv("JAVA_HOME")
	if home and home ~= "" then
		table.insert(candidates, home .. "\\bin\\java.exe")
	end
	local user = os.getenv("USERPROFILE") or os.getenv("HOME")
	local fileManager = deps.fileManager or _G.FileManager
	if user and user ~= "" and fileManager and type(fileManager.getFilesFromDirectory) == "function" then
		local jdks = user .. "\\.gradle\\jdks"
		for _, name in ipairs(fileManager.getFilesFromDirectory(jdks) or {}) do
			table.insert(candidates, jdks .. "\\" .. name .. "\\bin\\java.exe")
			table.insert(candidates, jdks .. "\\" .. name .. "/bin/java.exe")
		end
	end

	for _, path in ipairs(candidates) do
		if util.fileExists(path) then
			local major = Rom.javaMajor(util, path, deps.extDir)
			if major and major >= 21 then
				print(string.format("[DDI] java: %s (major %s)", tostring(path), tostring(major)))
				return path, major
			end
		end
	end

	local fallbackMajor = configured and Rom.javaMajor(util, configured, deps.extDir) or nil
	print("[DDI] no Java 21 found (configured major " .. tostring(fallbackMajor) .. ")")
	return configured, fallbackMajor
end

---Generates the day's ROM locally and verifies its hash.
---@param deps table {extDir, util, manifest, javaPath, jarPath, args, outputPath}
---@return table {ok, path, sha, log, output, err}
function Rom.generate(deps)
	local util = deps.util
	local manifest = deps.manifest
	local outDir = Rom.romDir(deps.extDir)
	if not util.ensureDir(outDir) then
		return { ok = false, err = "cannot create ROM directory" }
	end
	local outputPath = deps.outputPath or Rom.romPath(deps.extDir, manifest.date)
	if type(deps.args) ~= "table" then
		return { ok = false, err = "generation arguments missing" }
	end
	util.removeFile(outputPath)
	util.removeFile(outputPath .. ".log")

	local javaPath = deps.javaPath or "java"
	local major = Rom.javaMajor(util, javaPath, deps.extDir)
	if major and major < 21 then
		return {
			ok = false,
			err = string.format("Java 21 is required (found Java %d). Set the tracker's Java_Path to a Java 21 executable.", major),
		}
	end

	local command = Rom.buildGenerationCommand(javaPath, deps.jarPath, deps.args)
	print("[DDI] generate: " .. command)

	local ok, stdout, stderr = Rom.exec(util, command, outputPath .. ".stdout", outputPath .. ".stderr")
	local output = tostring(stdout or "")
	if stderr and stderr ~= "" then
		print("[DDI] stderr: " .. stderr)
		output = output .. "\n" .. stderr
	end

	if not ok or not util.fileExists(outputPath) then
		local detail = tostring(output or ""):gsub("%s+$", "")
		if #detail > 800 then
			detail = detail:sub(-800)
		end
		print("[DDI] randomizer failed: " .. detail)
		return { ok = false, err = "randomizer failed: " .. detail, output = tostring(output) }
	end
	print("[DDI] generated " .. tostring(outputPath))
	local sha, hashErr = util.sha1File(outputPath)
	if not sha then
		return { ok = false, err = "could not hash generated ROM: " .. tostring(hashErr), output = tostring(output) }
	end
	if sha ~= manifest.rom_sha1 then
		return {
			ok = false,
			err = "generated ROM hash mismatch",
			sha = sha,
			path = outputPath,
			log = outputPath .. ".log",
			output = tostring(output),
		}
	end
	return {
		ok = true,
		path = outputPath,
		sha = sha,
		log = outputPath .. ".log",
		output = tostring(output),
	}
end

---Opens a ROM in the emulator and lets the tracker restart against it.
---@param path string
---@param deps table {client, main}
---@return boolean
function Rom.open(path, deps)
	local main = deps.main or _G.Main
	print("[DDI] open " .. tostring(path))
	if main and type(main.LoadRom) == "function" then
		local ok = main.LoadRom(path)
		return ok ~= false
	end
	local client = deps.client or _G.client
	if not client or type(client.openrom) ~= "function" then
		print("[DDI] no client.openrom available")
		return false
	end
	client.openrom(path)
	if main then
		main.forceRestart = true
	end
	return true
end

return Rom
