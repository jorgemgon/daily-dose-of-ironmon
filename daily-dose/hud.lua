-- Compact overlay line drawn over the tracker UI (afterRedraw).

local Hud = {}

---@param ctx table
---@return string?
function Hud.line(ctx)
	local state = ctx.state
	if not state then
		return nil
	end
	if state.phase == ctx.session.PHASES.INTENT then
		return "DDI: waiting for starter"
	end
	if state.phase == ctx.session.PHASES.VOID then
		return "DDI: void (" .. tostring(state.voidReason) .. ")"
	end
	if state.phase == ctx.session.PHASES.FINISHED then
		return "DDI: attempt finished"
	end
	local igt = ctx.session.igtSeconds(state, ctx.frames())
	local rta = ctx.session.rtaSeconds(state, ctx.now())
	return string.format("DDI %s  IGT %s  RTA %s", tostring(state.date), ctx.util.formatClock(igt), ctx.util.formatClock(rta))
end

---@param ctx table
function Hud.draw(ctx)
	if not ctx.state or ctx.state.phase ~= ctx.session.PHASES.ACTIVE then
		return
	end
	local text = Hud.line(ctx)
	if not text then
		return
	end
	local x = Constants.SCREEN.MARGIN
	local y = Constants.SCREEN.HEIGHT - 12
	Drawing.drawText(x, y, text, Theme.COLORS["Default text"])
end



return Hud
