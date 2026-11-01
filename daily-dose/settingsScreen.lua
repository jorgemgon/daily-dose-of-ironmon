-- Tracker-styled settings screen for Daily Dose (opened from the extension's Options button).

local SettingsScreen = {}

SettingsScreen.Buttons = {}
SettingsScreen.deps = nil
SettingsScreen.ctx = nil
SettingsScreen.pendingTwitch = nil
SettingsScreen.status = ""

local COLORS = {
	header = "Header text",
	text = "Default text",
	muted = "Intermediate text",
	positive = "Positive text",
	negative = "Negative text",
}

local function truncate(value, maxChars)
	local text = tostring(value or "")
	if #text <= maxChars then
		return text
	end
	return text:sub(1, maxChars - 1) .. "…"
end

local function addButton(key, x, y, width, label, onClick)
	SettingsScreen.Buttons[key] = {
		type = Constants.ButtonTypes.FULL_BORDER,
		box = { x, y, width, 12 },
		getText = function()
			return label()
		end,
		onClick = function()
			if onClick then
				onClick()
			end
			Program.redraw(true)
		end,
	}
end

local function currentHandle()
	local deps = SettingsScreen.deps
	return (deps and deps.handle and deps.handle()) or ""
end

local function layout()
	local deps = SettingsScreen.deps
	if not deps then
		return
	end
	local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 5
	SettingsScreen.Buttons = {}

	local function loginWithTwitch()
		if not deps.twitchBegin then
			SettingsScreen.status = "Twitch login is not available in this build."
			return
		end
		local session, err = deps.twitchBegin()
		if not session then
			SettingsScreen.status = "Twitch login failed: " .. tostring(err)
			return
		end
		SettingsScreen.pendingTwitch = session
		if deps.openBrowser and session.login_url then
			deps.openBrowser(session.login_url)
		end
		SettingsScreen.status = "Browser opened. Finish Twitch login, then Check."
	end

	local function checkTwitch()
		local pending = SettingsScreen.pendingTwitch
		if not pending then
			SettingsScreen.status = "Press Login with Twitch first."
			return
		end
		if not deps.twitchCheck then
			SettingsScreen.status = "Twitch login is not available in this build."
			return
		end
		local ok, err = deps.twitchCheck(pending.session_id, pending.poll_token)
		if ok then
			SettingsScreen.status = "Logged in as @" .. tostring(deps.handle and deps.handle() or "")
		else
			SettingsScreen.status = tostring(err)
		end
	end

	local function copyToken()
		SettingsScreen.status = deps.copyToken() or "No token yet."
	end

	addButton("TwitchLogin", x, 42, 96, function()
		return "Login with Twitch"
	end, loginWithTwitch)
	addButton("TwitchCheck", x, 58, 96, function()
		return "Check login"
	end, checkTwitch)
	addButton("IpsToggle", x, 74, 96, function()
		if deps.useIps and deps.useIps() then
			return "Patch: ON"
		end
		return "Patch: OFF"
	end, function()
		if not deps.toggleIps then
			return
		end
		local enabled = deps.toggleIps()
		SettingsScreen.status = enabled and "Faster FireRed patch enabled." or "Faster FireRed patch disabled."
	end)
	if deps.hasToken and deps.hasToken() then
		addButton("CopyToken", x, 90, 64, function()
			return "Copy token"
		end, copyToken)
	end

	SettingsScreen.Buttons.Back = Drawing.createUIElementBackButton(function()
		if deps.back then
			deps.back()
		else
			Program.changeScreenView(TrackerScreen)
		end
	end)
end

---@param ctx table
---@param deps table {handle, twitchBegin, twitchCheck, openBrowser, copyToken, back}
function SettingsScreen.attach(ctx, deps)
	SettingsScreen.ctx = ctx
	SettingsScreen.deps = deps
	SettingsScreen.pendingTwitch = nil
	SettingsScreen.status = ""
	layout()
end

function SettingsScreen.checkInput(xmouse, ymouse)
	Input.checkButtonsClicked(xmouse, ymouse, SettingsScreen.Buttons)
end

function SettingsScreen.drawScreen()
	local deps = SettingsScreen.deps
	if not deps then
		return
	end
	Drawing.drawBackgroundAndMargins()
	local theme = Theme.COLORS
	local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 5

	Drawing.drawText(x, 8, "Daily Dose settings", theme[COLORS.header])
	local handle = currentHandle()
	Drawing.drawText(x, 24, "Account: " .. truncate(handle ~= "" and ("@" .. handle) or "not logged in", 16), theme[COLORS.text])

	for _, button in pairs(SettingsScreen.Buttons) do
		if button == SettingsScreen.Buttons.Back then
			Drawing.drawButton(button)
		else
			local bx, by, bw, bh = button.box[1], button.box[2], button.box[3], button.box[4]
			local label = button:getText() or ""
			gui.drawRectangle(bx, by, bw, bh, Theme.COLORS["Upper box border"], Theme.COLORS["Upper box background"])
			local textX = bx + math.max(1, math.floor((bw - Utils.calcWordPixelLength(label)) / 2))
			Drawing.drawText(textX, by, label, Theme.COLORS["Default text"])
		end
	end

	local status = SettingsScreen.status or ""
	if status ~= "" then
		local positive = status:find("Logged in") or status:find("saved") or status:find("enabled")
		Drawing.drawText(x, Constants.SCREEN.HEIGHT - 12, truncate(status, 31), theme[positive and COLORS.positive or COLORS.text])
	end
end

return SettingsScreen
