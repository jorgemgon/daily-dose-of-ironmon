-- Daily Dose of Ironmon — Ironmon Tracker extension entry point.
-- Loaded by the tracker from <tracker>/extensions/DailyDoseIronmon.lua.

local function DailyDoseIronmon()
	local self = {
		version = "0.1.0",
		name = "Daily Dose of Ironmon",
		author = "Daily Dose of Ironmon",
		description = "Daily seed-shared Kaizo Ironmon with a leaderboard, open-book logs and one attempt per day.",
		requiredExtKeys = {},
	}

	local EXT_KEY = "DailyDoseIronmon"
	local modules = nil
	local ctx = nil
	local championSeen = false
	local lastBattleTrainerId = nil
	local chipRect = nil
	local chipWasDown = false
	local lastScreen = nil
	local hooksRegistered = false
	local hookTicks = 0

	local function trackerReady()
		return Main ~= nil
			and type(Main.IsOnBizhawk) == "function"
			and Main.IsOnBizhawk()
			and GameSettings ~= nil
			and GameSettings.game == 3
	end

	local function loadModules()
		local extensionsDir = FileManager.getExtensionsFolderPath()
		local sep = FileManager.slash or "/"
		local dir = extensionsDir .. "daily-dose"
		local function load(name)
			local path = dir .. sep .. name .. ".lua"
			local module = dofile(path)
			if type(module) ~= "table" then
				error("Daily Dose: could not load " .. path)
			end
			return module
		end
		local loaded = {
			config = load("config"),
			util = load("util"),
			json = load("json"),
			score = load("score"),
			milestones = load("milestones"),
			manifest = load("manifest"),
			session = load("session"),
			http = load("http"),
			api = load("api"),
			identity = load("identity"),
			rom = load("rom"),
			jars = load("jars"),
			log = load("log"),
			submit = load("submit"),
			run = load("run"),
			screen = load("screen"),
			hud = load("hud"),
			diagnostics = load("diagnostics"),
			profile = load("profile"),
			settingsScreen = load("settingsScreen"),
		}
		return dir, loaded
	end

	local function getSetting(key)
		if not TrackerAPI or type(TrackerAPI.getExtensionSetting) ~= "function" then
			return nil
		end
		return TrackerAPI.getExtensionSetting(EXT_KEY, key)
	end

	local function setSetting(key, value)
		if not TrackerAPI or type(TrackerAPI.saveExtensionSetting) ~= "function" then
			return false
		end
		TrackerAPI.saveExtensionSetting(EXT_KEY, key, value)
		return true
	end

	local function readPlayerFile()
		if not ctx then
			return nil
		end
		local text = ctx.util.readFile(ctx.extDir .. "/state/player.json")
		if not text or text == "" then
			return nil
		end
		return ctx.json.decode(text)
	end

	local function writePlayerFile(value)
		if not ctx then
			return false
		end
		ctx.util.ensureDir(ctx.extDir .. "/state")
		return ctx.util.writeFile(ctx.extDir .. "/state/player.json", ctx.json.encode(value))
	end

	local function apiBase()
		local configured = getSetting("api_base")
		if configured and configured ~= "" then
			return configured
		end
		return ctx.config.DEFAULT_API_BASE
	end

	local function rebuildApi()
		ctx.util.ensureDir(ctx.extDir .. "/state")
		local io = {
			writeFile = ctx.util.writeFile,
			readFile = ctx.util.readFile,
			run = ctx.util.run,
			remove = ctx.util.removeFile,
		}
		ctx.httpIo = io
		local apiModule = ctx.apiModule
		ctx.api = apiModule.new(apiBase(), {
			request = function(opts)
				local http = ctx.http
				return http.request(opts, io)
			end,
		}, ctx.json, ctx.extDir .. "/state")
	end

	local function showMessage(title, text, buttonLabel, onClick)
		print(string.format("[DDI] %s: %s", tostring(title), tostring(text)))
		if not Main.IsOnBizhawk() or not ExternalUI then
			print(string.format("> %s: %s", title, text))
			return
		end
		local form = ExternalUI.BizForms.createForm(title, 420, 200, 100, 20)
		form:createTextBox(text, 12, 12, 390, 110, "", true, true, "Vertical")
		form:createButton(buttonLabel or "OK", 160, 140, function()
			form:destroy()
			if onClick then
				onClick()
			end
		end, 90, 24)
	end

	local function requirePlayer()
		if ctx.player.token and ctx.player.token ~= "" then
			return true
		end
		showMessage("Daily Dose", "Log in with Twitch first (Settings → Login with Twitch).")
		return false
	end

	local function openScreen()
		if not ctx then
			return
		end
		if Program.currentScreen ~= ctx.screen then
			ctx.returnScreen = Program.currentScreen
		end
		Program.changeScreenView(ctx.screen)
		Program.redraw(true)
	end

	local function startOrResume()
		if not requirePlayer() then
			return
		end
		local state = ctx.state
		if state and state.phase == ctx.session.PHASES.ACTIVE then
			local ok, err = ctx.run.resumeAttempt(ctx)
			if not ok then
				showMessage("Daily Dose", err or "could not resume")
			end
			return
		end
		local ok, err = ctx.run.startIntent(ctx)
		if not ok then
			showMessage("Daily Dose", err or "could not start today's attempt")
			return
		end
		ok, err = ctx.run.prepareRom(ctx)
		if not ok and type(err) == "string" and err:find("base ROM not registered", 1, true) then
			local filepath, picked = ExternalUI.BizForms.openFilePrompt(
				ctx.config.BASE_ROM_NAME,
				FileManager.dir,
				"GBA ROM (*.gba)|*.gba|All files (*.*)|*.*"
			)
			if picked and filepath then
				local registered, registerErr = ctx.rom.registerFromFile({
					extDir = ctx.extDir,
					util = ctx.util,
					config = ctx.config,
					path = filepath,
				})
				if not registered then
					showMessage("Daily Dose", "That ROM could not be registered: " .. tostring(registerErr))
					return
				end
				ok, err = ctx.run.prepareRom(ctx)
			end
		end
		if not ok then
			showMessage("Daily Dose", err or "could not prepare today's ROM")
			return
		end
		if not ctx.run.openRom(ctx) then
			showMessage("Daily Dose", "Could not open the ROM in BizHawk.")
			return
		end
		-- Leave the custom screen so the Tracker/game is visible while the ROM loads.
		if Program and TrackerScreen then
			Program.changeScreenView(TrackerScreen)
		end
	end

	local function resume()
		if not requirePlayer() then
			return
		end
		local ok, err = ctx.run.resumeAttempt(ctx)
		if not ok then
			showMessage("Daily Dose", err or "could not resume")
		end
	end

	local function copyToken()
		if not ctx.player.token or ctx.player.token == "" then
			return "No token yet."
		end
		if gui and type(gui.setclipboard) == "function" then
			gui.setclipboard(ctx.player.token)
			return "Token copied to the clipboard."
		end
		return "Clipboard unavailable; token is in Settings.ini."
	end

	local function observe()
		if not trackerReady() then
			return { partySize = 0 }
		end
		local badges = TrackerAPI.getBadgeList()
		local defeated = {}
		for _, trainerId in ipairs({ 410, 411, 412, 413 }) do
			defeated[trainerId] = TrackerAPI.hasDefeatedTrainer(trainerId)
		end
		local team = (Program.GameData and Program.GameData.PlayerTeam) or {}
		local partySize, alive = 0, 0
		for i = 1, 6 do
			local mon = team[i]
			if mon and not mon.isEgg then
				partySize = partySize + 1
				if (tonumber(mon.curHP) or 0) > 0 then
					alive = alive + 1
				end
			end
		end
		local saveId = Tracker.Data and Tracker.Data.trainerID
		local trainersDefeated = 0
		if _G.GameOverScreen and type(_G.GameOverScreen.updateDefeatedTrainersCount) == "function" then
			_G.GameOverScreen.updateDefeatedTrainersCount()
			trainersDefeated = tonumber(_G.GameOverScreen.numDefeatedTrainers) or 0
		elseif _G.GachaMonData and type(_G.GachaMonData.getDefeatedCommonTrainers) == "function" then
			trainersDefeated = #(_G.GachaMonData.getDefeatedCommonTrainers() or {})
		end
		return {
			badges = badges,
			defeated = defeated,
			champion = championSeen,
			partySize = partySize,
			partyWiped = partySize > 0 and alive == 0,
			saveId = saveId and tostring(saveId) or nil,
			trainersDefeated = trainersDefeated,
		}
	end

	local function buildContext(dir, loaded)
		local c = {
			extDir = dir,
			config = loaded.config,
			util = loaded.util,
			json = loaded.json,
			score = loaded.score,
			milestones = loaded.milestones,
			manifestModule = loaded.manifest,
			session = loaded.session,
			http = loaded.http,
			apiModule = loaded.api,
			identity = loaded.identity,
			rom = loaded.rom,
			jars = loaded.jars,
			log = loaded.log,
			submit = loaded.submit,
			run = loaded.run,
			screen = loaded.screen,
			hud = loaded.hud,
			diagnostics = loaded.diagnostics,
			profile = loaded.profile,
			useIps = true,
			now = function()
				return os.time()
			end,
			frames = function()
				return emu.framecount()
			end,
			romHash = function()
				return GameSettings.getRomHash()
			end,
			javaPath = (Options.PATHS and Options.PATHS["Java Path"]) or "java",
			javaVersion = "unknown",
			osName = (Main.OS or "unknown") .. " / " .. tostring(Main.OSVersion or ""),
			player = { handle = nil, token = nil, deviceId = nil },
			client = client,
			main = Main,
		}
		c.identityDeps = {
			getSetting = getSetting,
			setSetting = setSetting,
			readState = readPlayerFile,
			writeState = writePlayerFile,
		}
		c.actions = {
			startOrResume = startOrResume,
			resume = resume,
		}
		return c
	end

	local function registerEventHooks()
		if hooksRegistered then
			return
		end
		hooksRegistered = true
		if event and type(event.onloadstate) == "function" then
			event.onloadstate(function()
				if ctx and ctx.state then
					ctx.run.loadState(ctx)
				end
			end)
		end
	end

	-- Tracker hooks ----------------------------------------------------------

	function self.startup()
		local dir, loaded = loadModules()
		modules = loaded
		ctx = buildContext(dir, loaded)

		ctx.player.deviceId = ctx.identity.newDeviceId(ctx.util.randomHex)
		local stored = ctx.identity.load(ctx.identityDeps)
		if stored.handle then
			ctx.player.handle = stored.handle
		end
		if stored.deviceId then
			ctx.player.deviceId = stored.deviceId
		end
		if stored.token then
			ctx.player.token = stored.token
		end

		ctx.useIps = getSetting("use_ips") ~= "false"
		rebuildApi()
		ctx.state = ctx.run.load(ctx)
		ctx.manifest = ctx.run.loadCachedManifest(ctx, ctx.run.today(ctx.now()))
		ctx.screen.attach(ctx)
		registerEventHooks()
	end

	function self.unload()
		if ctx and ctx.state then
			ctx.run.save(ctx, ctx.state)
		end
		ctx = nil
	end

	function self.afterProgramDataUpdate()
		if not trackerReady() or not ctx then
			return
		end
		hookTicks = hookTicks + 1
		local observation = observe()
		if ctx.state and ctx.state.phase == ctx.session.PHASES.ACTIVE
			and observation.saveId and ctx.state.saveId
			and observation.saveId ~= ctx.state.saveId then
			ctx.run.restartDetected(ctx)
		end
		ctx.run.tick(ctx, observation)

		if hookTicks % 20 == 0 then
			ctx.run.flushQueue(ctx)
		end

	end

	function self.afterBattleBegins()
		if not trackerReady() then
			return
		end
		lastBattleTrainerId = TrackerAPI.getOpponentTrainerId()
	end

	function self.afterBattleEnds()
		if not trackerReady() or not ctx then
			return
		end
		local outcome = TrackerAPI.getBattleOutcome()
		if outcome == 1 and ctx.milestones.isFinalTrainer(lastBattleTrainerId) then
			championSeen = true
		end
	end

	function self.afterRedraw()
		if not trackerReady() or not ctx then
			return
		end
		ctx.hud.draw(ctx)
		chipRect = nil
		-- Entry point: a small DDI button in the Tracker Settings header, after the title.
		-- Only show it once Twitch login has produced a player token.
		if
			Program.currentScreen == NavigationMenu
			and ctx.player.token
			and ctx.player.token ~= ""
		then
			local title = Utils.toUpperUTF8(Resources.NavigationMenu.Title)
			local version = "v" .. tostring(Main.TrackerVersion)
			local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + Utils.calcWordPixelLength(title) + 6
			local versionX = Constants.SCREEN.WIDTH + Constants.SCREEN.RIGHT_GAP - Constants.SCREEN.MARGIN - Utils.calcWordPixelLength(version) - 3
			x = math.min(x, versionX - 28)
			local y = Constants.SCREEN.MARGIN - 3
			local width, height = 24, 11
			local label = "DDI"
			gui.drawRectangle(x, y, width, height, Theme.COLORS["Upper box border"], Theme.COLORS["Upper box background"])
			local textX = x + math.max(1, math.floor((width - Utils.calcWordPixelLength(label)) / 2))
			Drawing.drawText(textX, y, label, Theme.COLORS["Default text"])
			chipRect = { x = x, y = y, width = width, height = height }
		end
	end

	function self.inputCheckBizhawk()
		local mouse = input.getmouse()
		local down = mouse["Left"] == true
		if Program.currentScreen ~= lastScreen then
			-- Swallow the click that navigated to this screen.
			lastScreen = Program.currentScreen
			chipWasDown = true
		end
		if not trackerReady() or not chipRect then
			chipWasDown = down
			return
		end
		local x = mouse["X"] or -1
		local y = (mouse["Y"] or -1) + Constants.SCREEN.UP_GAP
		local inside = x >= chipRect.x and x <= chipRect.x + chipRect.width
			and y >= chipRect.y and y <= chipRect.y + chipRect.height
		if down and not chipWasDown and inside then
			openScreen()
		end
		chipWasDown = down
	end

	function self.configureOptions()
		if not ctx or not Main.IsOnBizhawk() or not ExternalUI then
			return
		end
		local screen = modules and modules.settingsScreen
		if not screen then
			return
		end
		screen.attach(ctx, {
			handle = function()
				return ctx.player.handle
			end,
			hasToken = function()
				return ctx.player.token ~= nil and ctx.player.token ~= ""
			end,
			useIps = function()
				return ctx.useIps ~= false
			end,
			toggleIps = function()
				ctx.useIps = not (ctx.useIps ~= false)
				setSetting("use_ips", tostring(ctx.useIps))
				return ctx.useIps
			end,
			twitchBegin = function()
				return ctx.run.beginTwitchLogin(ctx)
			end,
			twitchCheck = function(sessionId, pollToken)
				return ctx.run.completeTwitchLogin(ctx, sessionId, pollToken)
			end,
			openBrowser = function(url)
				if _G.Utils and type(_G.Utils.openBrowserWindow) == "function" then
					_G.Utils.openBrowserWindow(url, true)
				else
					print("> " .. tostring(url))
				end
			end,
			copyToken = copyToken,
			back = function()
				Program.changeScreenView(SingleExtensionScreen or CustomExtensionsScreen or TrackerScreen)
			end,
		})
		Program.changeScreenView(screen)
	end

	return self
end

return DailyDoseIronmon
