-- Tracker-styled settings screen for Daily Dose (opened from the extension's Options button).

local SettingsScreen = {}

SettingsScreen.Buttons = {}
SettingsScreen.deps = nil
SettingsScreen.ctx = nil
SettingsScreen.pendingHandle = nil
SettingsScreen.pendingCode = nil
SettingsScreen.recoveryMode = false
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

local function prompt(title, initial, onSave)
	local form = ExternalUI.BizForms.createForm(title, 380, 112, 100, 20)
	local box = form:createTextBox(initial or "", 12, 18, 350, 22)
	form:createButton("Save", 12, 60, function()
		onSave(ExternalUI.BizForms.getText(box))
		form:destroy()
	end, 90, 24)
	form:createButton("Cancel", 110, 60, function()
		form:destroy()
	end, 90, 24)
end

local function addButton(key, x, y, width, label, onClick)
	SettingsScreen.Buttons[key] = {
		type = Constants.ButtonTypes.FULL_BORDER,
		box = { x, y, width, 12 },
		getText = function()
			return label()
		end,
		onClick = function()
			onClick()
			Program.redraw(true)
		end,
	}
end

local function currentHandle()
	local deps = SettingsScreen.deps
	return SettingsScreen.pendingHandle or (deps and deps.handle()) or ""
end

local function doRegister()
	local deps = SettingsScreen.deps
	local handle = currentHandle()
	if handle == "" then
		SettingsScreen.status = "Set a handle first."
		return
	end
	local ok, err = deps.register(handle)
	SettingsScreen.status = ok and "Registered." or tostring(err)
end

local function doRecover()
	local deps = SettingsScreen.deps
	local handle = currentHandle()
	local code = SettingsScreen.pendingCode
	if handle == "" or not code or code == "" then
		SettingsScreen.status = "Set a handle and a recovery code first."
		return
	end
	local ok, err = deps.recover(handle, code)
	SettingsScreen.status = ok and "Recovered." or tostring(err)
end

local function layout()
	local deps = SettingsScreen.deps
	if not deps then
		return
	end
	local x = Constants.SCREEN.WIDTH + Constants.SCREEN.MARGIN + 5
	SettingsScreen.Buttons = {}

	local function copyToken()
		SettingsScreen.status = deps.copyToken() or "No token yet."
	end

	if SettingsScreen.recoveryMode then
		addButton("SetCode", x, 56, 64, function()
			return "Set code"
		end, function()
			prompt("Recovery code", "", function(value)
				SettingsScreen.pendingCode = value
				SettingsScreen.status = "Code set; press Recover."
			end)
		end)
		addButton("Recover", x, 72, 64, function()
			return "Recover"
		end, doRecover)
		addButton("CancelRecovery", x + 68, 72, 64, function()
			return "Cancel"
		end, function()
			SettingsScreen.recoveryMode = false
			SettingsScreen.status = "Recovery cancelled."
			layout()
		end)
		addButton("CopyToken", x, 88, 64, function()
			return "Copy token"
		end, copyToken)
	else
		addButton("SetHandle", x, 42, 72, function()
			return "Set handle"
		end, function()
			prompt("Handle (2-20 letters, digits, _ . -)", currentHandle(), function(value)
				SettingsScreen.pendingHandle = value
				if deps.hasToken and deps.hasToken() then
					SettingsScreen.status = "Already registered as " .. tostring(deps.handle() or "?")
					return
				end
				doRegister()
			end)
		end)
		addButton("RecoverAccount", x, 58, 96, function()
			return "Recover account"
		end, function()
			SettingsScreen.recoveryMode = true
			SettingsScreen.status = "Enter the admin-issued code."
			layout()
		end)
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
---@param deps table {handle, register, recover, copyToken, back}
function SettingsScreen.attach(ctx, deps)
	SettingsScreen.ctx = ctx
	SettingsScreen.deps = deps
	SettingsScreen.pendingHandle = nil
	SettingsScreen.pendingCode = nil
	SettingsScreen.recoveryMode = false
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
	Drawing.drawText(x, 24, "Handle: " .. truncate(handle ~= "" and handle or "—", 13), theme[COLORS.text])

	if SettingsScreen.recoveryMode then
		Drawing.drawText(x, 42, "Code: " .. (SettingsScreen.pendingCode and "set" or "—"), theme[COLORS.text])
	end

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
		local positive = status:find("Registered") or status:find("Recovered") or status:find("saved") or status:find("enabled")
		Drawing.drawText(x, Constants.SCREEN.HEIGHT - 12, truncate(status, 23), theme[positive and COLORS.positive or COLORS.text])
	end
end

return SettingsScreen
