-- QuestTimers: a small box listing running quest timers, shown only while one runs.
-- Drag it to move it (the spot is saved).
local f = CreateFrame("Frame", "QuestTimersFrame", UIParent)
f:SetSize(220, 20)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetClampedToScreen(true)
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local x, y = self:GetCenter()
	QuestTimersDB = { x = x, y = y }
end)
local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetPoint("TOP")
text:SetJustifyH("CENTER")
f:Hide()

local function Clock(s)
	s = math.max(0, math.floor(s))
	return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- {title, seconds} for each running timer
local function Timers()
	local out = {}
	if C_QuestLog.GetQuestTimers then
		for _, t in ipairs(C_QuestLog.GetQuestTimers() or {}) do
			local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(t.questID)
			out[#out + 1] = { title or "Quest", t.questTimer }
		end
	elseif GetQuestTimers then
		for _, s in ipairs({ GetQuestTimers() }) do out[#out + 1] = { "Quest timer", s } end
	end
	return out
end

local elapsed = 1
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.5 then return end
	elapsed = 0
	local timers = Timers()
	if #timers == 0 then f:Hide() return end
	local lines = {}
	for _, t in ipairs(timers) do lines[#lines + 1] = ("%s  |cffffd100%s|r"):format(t[1], Clock(t[2])) end
	text:SetText(table.concat(lines, "\n"))
	f:SetHeight(text:GetStringHeight() + 4)
	f:Show()
end)

ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function()
	f:ClearAllPoints()
	if QuestTimersDB then
		f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", QuestTimersDB.x, QuestTimersDB.y)
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -160)
	end
end)
