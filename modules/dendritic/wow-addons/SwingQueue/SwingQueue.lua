-- SwingQueue: the game's main-hand swing bar turns red while Heroic Strike is queued, green while Cleave is.
local QUEUED = {
	{ color = { 1, 0.1, 0.1 }, ids = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 } }, -- Heroic Strike
	{ color = { 0.1, 1, 0.1 }, ids = { 845, 7369, 11608, 11609, 20569 } }, -- Cleave
}
local IsCurrent = C_Spell and C_Spell.IsCurrentSpell or IsCurrentSpell
local bar, base, ours, painting

local function Find(f, depth)
	if not f or f:IsObjectType("StatusBar") then return f end
	if depth == 0 then return end
	for _, child in ipairs({ f:GetChildren() }) do
		local found = Find(child, depth - 1)
		if found then return found end
	end
end

local function Queued()
	for _, q in ipairs(QUEUED) do
		for _, id in ipairs(q.ids) do
			if IsCurrent(id) then return q.color end
		end
	end
end

local function Set(color)
	painting = true
	bar:SetStatusBarColor(unpack(color))
	painting = false
end

local function Paint()
	if not bar then
		bar = Find(SwingTimerMainHandFrame, 2)
		if not bar then return end
		base = { bar:GetStatusBarColor() }
		-- the game recolouring its bar mid-queue: remember its colour, keep ours on top
		hooksecurefunc(bar, "SetStatusBarColor", function(_, ...)
			if painting then return end
			base = { ... }
			if ours then Set(ours) end
		end)
	end
	local color = Queued()
	if color == ours then return end
	ours = color
	Set(color or base)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "CURRENT_SPELL_CAST_CHANGED", "ACTIONBAR_UPDATE_STATE" }) do
	f:RegisterEvent(e)
end
f:SetScript("OnEvent", Paint)

SLASH_SWINGQUEUE1 = "/swingqueue"
SlashCmdList.SWINGQUEUE = function()
	Paint()
	print("SwingQueue: bar " .. (bar and (bar:GetName() or "found (no name)") or "not found")
		.. (ours and ", strike queued" or ", nothing queued"))
end
