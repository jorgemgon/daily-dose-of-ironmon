-- Custom tracker screen: compact daily status, account state and attempt actions.

local Screen = {}

Screen.Buttons = {}
Screen.Colors = {
	text = "Default text",
	highlight = "Intermediate text",
	header = "Header text",
	muted = "Intermediate text",
}

local function panel()
	local constants = Constants
	local margin = constants.SCREEN.MARGIN
	return {
		x = constants.SCREEN.WIDTH + margin,
		y = margin,
		width = constants.SCREEN.RIGHT_GAP - (margin * 2),
		height = constants.SCREEN.HEIGHT - (margin * 2),
	}
end

local function splitWords(text)
	local words = {}
	for word in tostring(text or ""):gmatch("%S+") do
		words[#words + 1] = word
	end
	return words
end

local function wrapText(text, maxWidth)
	local lines = {}
	local current = ""
	for _, word in ipairs(splitWords(text)) do
		local candidate = current == "" and word or (current .. " " .. word)
		if current ~= "" and Utils.calcWordPixelLength(candidate) > maxWidth then
			lines[#lines + 1] = current
			current = word
		else
			current = candidate
		end
	end
	if current ~= "" then
		lines[#lines + 1] = current
	end
	return lines
end

local function addButton(key, label, y, onClick, isVisible)
	Screen.Buttons[key] = {
		type = Constants.ButtonTypes.FULL_BORDER,
		box = { Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 6, y, 128, 14 },
		label = label,
		getText = function()
			-- Text is drawn separately, centered; the button itself only draws the box.
			return ""
		end,
		onClick = function()
			onClick()
			Program.redraw(true)
		end,
		isVisible = isVisible or function()
			return true
		end,
	}
	return y + 17
end

---@param ctx table
function Screen.attach(ctx)
	Screen.ctx = ctx
	Screen.Buttons = {}

	local panelBox = panel()
	local y = panelBox.y + 39

	y = addButton("Primary", "Start attempt", y, function()
		ctx.actions.startOrResume()
	end, function()
		local state = ctx.state
		if not state then
			return true
		end
		if state.phase == ctx.session.PHASES.INTENT then
			return true
		end
		if state.phase == ctx.session.PHASES.VOID or state.phase == ctx.session.PHASES.FINISHED then
			return not ctx.run.hasBrock(state)
		end
		return false
	end)

	y = addButton("Resume", "Resume attempt", y, function()
		ctx.actions.resume()
	end, function()
		return ctx.state and ctx.state.phase == ctx.session.PHASES.ACTIVE
	end)

	Screen.Buttons.Back = Drawing.createUIElementBackButton(function()
		Program.changeScreenView(ctx.returnScreen or TrackerScreen)
	end)
end

function Screen.checkInput(xmouse, ymouse)
	Input.checkButtonsClicked(xmouse, ymouse, Screen.Buttons)
end

local function drawStatusLines(ctx, x, y, maxWidth)
	local lines = ctx.run.statusLines(ctx)
	for _, line in ipairs(lines) do
		for _, wrapped in ipairs(wrapText(line, maxWidth)) do
			Drawing.drawText(x, y, wrapped, Theme.COLORS[Screen.Colors.text])
			y = y + 9
		end
	end
	return y
end

local function fitText(text, maxWidth)
	local value = tostring(text or "")
	if Utils.calcWordPixelLength(value) <= maxWidth then
		return value
	end
	local out = value
	while #out > 0 and Utils.calcWordPixelLength(out .. "…") > maxWidth do
		out = out:sub(1, #out - 1)
	end
	return out .. "…"
end

local function drawInfoRow(label, value, x, y, maxWidth)
	Drawing.drawText(x, y, label, Theme.COLORS[Screen.Colors.muted])
	local valueX = x + 38
	Drawing.drawText(valueX, y, fitText(value, maxWidth - (valueX - x)), Theme.COLORS[Screen.Colors.text])
	return y + 9
end

function Screen.drawScreen()
	local ctx = Screen.ctx
	Drawing.drawBackgroundAndMargins()

	local box = panel()
	local theme = Theme.COLORS
	local x = box.x + 6
	local y = box.y + 8
	local maxWidth = box.width - 10
	local state = ctx.state

	local header = "Daily Dose of Ironmon"
	if ctx.manifest and ctx.manifest.event and ctx.manifest.event.name then
		header = "Daily Dose — " .. tostring(ctx.manifest.event.name)
	end
	for _, line in ipairs(wrapText(header, maxWidth)) do
		Drawing.drawText(x, y, line, theme[Screen.Colors.header])
		y = y + 9
	end
	Drawing.drawText(x, y, "Daily Ironmon challenge", theme[Screen.Colors.muted])
	y = y + 13

	y = drawInfoRow("Date", state and state.date or "—", x, y, maxWidth)
	y = drawInfoRow("Phase", state and string.upper(tostring(state.phase)) or "—", x, y, maxWidth)
	local handle = ctx.player and ctx.player.handle or nil
	y = drawInfoRow("Account", handle and ("@" .. handle) or "not registered", x, y, maxWidth)
	local seed = ctx.manifest and ctx.manifest.seed
	if seed then
		y = drawInfoRow("Seed", tostring(seed), x, y, maxWidth)
	end

	gui.drawLine(x, y + 2, x + maxWidth, y + 2, theme[Screen.Colors.muted])
	y = y + 6

	y = drawStatusLines(ctx, x, y, maxWidth)

	local ordered = {}
	for _, button in pairs(Screen.Buttons) do
		if button ~= Screen.Buttons.Back then
			table.insert(ordered, button)
		end
	end
	table.sort(ordered, function(a, b) return a.box[2] < b.box[2] end)
	local buttonY = math.max(y + 4, box.y + 39)
	for _, button in ipairs(ordered) do
		button.box[2] = buttonY
		buttonY = buttonY + 17
	end

	for _, button in pairs(Screen.Buttons) do
		if button == Screen.Buttons.Back then
			Drawing.drawButton(button)
		elseif not (button.isVisible and not button:isVisible()) then
			Drawing.drawButton(button)
			local label = button.label or ""
			local textX = button.box[1] + math.floor((button.box[3] - Utils.calcWordPixelLength(label)) / 2)
			Drawing.drawText(textX, button.box[2] + 3, label, theme["Default text"])
		end
	end
end

return Screen
