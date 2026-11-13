-- QuestChain: Questie's chain details, with saved Campfire dialogue.
local _, Q = ...
Q = Q or {}

local function Questie()
	if not QuestieLoader then return end
	local ok, db = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
	if ok and db and db.QuestPointers and db.QueryQuestSingle then return db end
end

function Q.Build(questID, showNext)
	local db = Questie()
	if not db then return nil, "Questie still loading (or not installed)" end
	local ok, result = pcall(function()
		local rows, seen, visits = {}, {}, 0
		local _, _, race = UnitRace("player")
		local _, _, class = UnitClass("player")
		local function Get(id, field) return db.QueryQuestSingle(id, field) end
		local function ForYou(id)
			local races, classes = Get(id, "requiredRaces") or 0, Get(id, "requiredClasses") or 0
			return not (race and races ~= 0 and bit.band(races, 2 ^ (race - 1)) == 0)
				and not (class and classes ~= 0 and bit.band(classes, 2 ^ (class - 1)) == 0)
		end
		local function Query(fn, ...)
			if type(fn) ~= "function" then return end
			local success, value = pcall(fn, ...)
			if success then return value end
		end
		local function Contact(ids)
			if type(ids) ~= "table" then return end
			local queries = { db.QueryNPCSingle, db.QueryObjectSingle, db.QueryItemSingle }
			for kind = 1, 3 do
				local id = type(ids[kind]) == "table" and ids[kind][1]
				if type(id) == "number" then
					local name = Query(queries[kind], id, "name")
					if type(name) ~= "string" or name == "" then return end
					local zoneID = kind ~= 3 and Query(queries[kind], id, "zoneID")
					local zone = type(zoneID) == "number" and zoneID > 0
						and Query(C_Map and C_Map.GetAreaInfo, zoneID)
					return { name = kind == 3 and ("item: " .. name) or name,
						zone = type(zone) == "string" and zone or nil }
				end
			end
		end
		local function Add(id, kind)
			local index = C_QuestLog.GetLogIndexForQuestID(id)
			local texts, objectives = Query(db.QueryQuestSingle, id, "objectivesText"), {}
			if type(texts) == "table" then
				for _, text in ipairs(texts) do
					if type(text) == "string" then objectives[#objectives + 1] = text end
				end
			end
			rows[#rows + 1] = { id = id, kind = kind, name = Get(id, "name") or ("Quest #" .. id),
				level = Get(id, "questLevel"), done = C_QuestLog.IsQuestFlaggedCompleted(id) or false,
				inLog = index ~= nil and index > 0,
				giver = Contact(Query(db.QueryQuestSingle, id, "startedBy")),
				turnIn = Contact(Query(db.QueryQuestSingle, id, "finishedBy")),
				objectives = #objectives > 0 and objectives or nil }
		end
		seen[questID] = true
		local function Before(id, depth)
			-- Bound wide prerequisite trees too, not just deep chains.
			if type(id) ~= "number" or id <= 0 or seen[id] or depth > 30 or visits >= 200 then return end
			seen[id], visits = true, visits + 1
			if not ForYou(id) then return end
			for _, field in ipairs({ "preQuestSingle", "preQuestGroup" }) do
				for _, pre in ipairs(Get(id, field) or {}) do Before(pre, depth + 1) end
			end
			Add(id, "earlier")
		end
		for _, field in ipairs({ "preQuestSingle", "preQuestGroup" }) do
			for _, pre in ipairs(Get(questID, field) or {}) do Before(pre, 1) end
		end
		if ForYou(questID) then Add(questID, "current") end
		if showNext ~= false then
			local id = questID
			for _ = 1, 30 do
				id = Get(id, "nextQuestInChain")
				if type(id) ~= "number" or id <= 0 or seen[id] then break end
				seen[id] = true
				if ForYou(id) then Add(id, "next") end
			end
		end
		local counts, parts = {}, {}
		for _, row in ipairs(rows) do counts[row.name] = (counts[row.name] or 0) + 1 end
		for _, row in ipairs(rows) do
			if counts[row.name] > 1 then
				parts[row.name] = (parts[row.name] or 0) + 1
				row.part = parts[row.name]
			end
		end
		return rows
	end)
	if not ok then return nil, "Questie still loading" end
	return result
end

-- Wowhead's Forever news links quests at /forever/quest=ID.
local WOWHEAD_URL = "https://www.wowhead.com/forever/quest="
local PHASES = { "Quest", "Progress", "Completion" }

local function RowTitle(row)
	return row.name .. (row.part and (" (part " .. row.part .. ")") or "")
end

local function ContactText(prefix, who)
	return prefix .. who.name .. (who.zone and (" – " .. who.zone) or "")
end

function Q.CampfirePages(questID)
	local entries = CampfireDB and CampfireDB.lexicon and CampfireDB.lexicon.entries
	for _, entry in pairs(entries or {}) do
		if entry.kind == "quest" and entry.questID == questID then
			local pages = {}
			-- Quest pages can be sparse: description, progress, completion.
			for page = 1, 3 do
				local text = (entry.pages or {})[page]
				if type(text) == "table" then
					local lib = LibStub and LibStub("LibDeflate", true)
					local ok, value
					if lib and lib.DecompressDeflate and type(text.deflate) == "string" then
						ok, value = pcall(lib.DecompressDeflate, lib, text.deflate)
					end
					text = ok and value or nil
				end
				if type(text) == "string" and text ~= "" then
					pages[#pages + 1] = { phase = page, text = text }
				end
			end
			if #pages > 0 then return pages end
		end
	end
	return {}
end

function Q.WindowLines(row)
	local lines = {}
	local function Add(kind, text) lines[#lines + 1] = { kind = kind, text = text } end
	Add("title", RowTitle(row))
	Add("meta", "[" .. (row.level or "?") .. "] "
		.. (row.done and "Completed" or row.inLog and "In your log" or "Not done"))
	if row.giver then Add("fact", ContactText("From: ", row.giver)) end
	if row.turnIn then Add("fact", ContactText("Turn in: ", row.turnIn)) end
	local pages = Q.CampfirePages(row.id)
	if #pages == 0 then Add("muted", "Campfire has no saved text for this quest.") end
	for _, page in ipairs(pages) do
		Add("header", PHASES[page.phase])
		Add("text", page.text)
	end
	if row.objectives and #row.objectives > 0 then
		Add("header", "Objectives")
		for _, text in ipairs(row.objectives) do Add("text", text) end
	end
	Add("link", WOWHEAD_URL .. row.id)
	return lines
end

function Q.Click(row)
	if row.inLog then
		if type(QuestMapFrame_OpenToQuestDetails) == "function"
			and not (InCombatLockdown and InCombatLockdown()) then
			QuestMapFrame_OpenToQuestDetails(row.id)
		end
		return "details"
	end
	if row.kind ~= "next" then return "window" end
end

if not CreateFrame then return Q end
local panel = CreateFrame("Frame", "QuestChainFrame", UIParent, "BackdropTemplate")
panel:SetSize(300, 300)
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	-- Saved in UIParent units: the panel's parent (and scale) changes between the map and UIParent.
	local ratio = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
	QuestChainDB = QuestChainDB or {}
	QuestChainDB.pos = { x = self:GetLeft() * ratio, y = self:GetTop() * ratio }
end)
panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 } })
panel:Hide()
local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -12)
title:SetText("Quest chain")
local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -36)
scroll:SetPoint("BOTTOMRIGHT", -30, 12)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(258, 1)
scroll:SetScrollChild(content)
local buttons, selected, elapsed = {}, nil, 0
local status = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("TOPLEFT")
status:SetWidth(258)
status:SetJustifyH("LEFT")

local function Settings()
	QuestChainDB = QuestChainDB or {}
	if QuestChainDB.showNext == nil then QuestChainDB.showNext = true end
	return QuestChainDB
end

local function DetailLines(row)
	local lines = { RowTitle(row) }
	for _, contact in ipairs({ { "From: ", row.giver }, { "Turn in: ", row.turnIn } }) do
		local who = contact[2]
		if who then lines[#lines + 1] = ContactText(contact[1], who) end
	end
	for _, text in ipairs(row.objectives or {}) do lines[#lines + 1] = text end
	for _, page in ipairs(Q.CampfirePages(row.id)) do lines[#lines + 1] = page.text end
	return lines
end

local window = CreateFrame("Frame", "QuestChainQuestFrame", panel, "BackdropTemplate")
window:SetSize(360, 460)
window:SetClampedToScreen(true)
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 } })
local parchment = window:CreateTexture(nil, "BACKGROUND")
parchment:SetPoint("TOPLEFT", 4, -4)
parchment:SetPoint("BOTTOMRIGHT", -4, 4)
local paper
if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
	parchment:SetAtlas("QuestBG-Parchment")
	paper = true
else
	paper = parchment:SetTexture("Interface\\QuestFrame\\QuestBG")
end
if not paper then parchment:Hide() end
local windowClose = CreateFrame("Button", nil, window, "UIPanelCloseButton")
windowClose:SetPoint("TOPRIGHT", 2, 2)
table.insert(UISpecialFrames, "QuestChainQuestFrame")
local windowScroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
windowScroll:SetPoint("TOPLEFT", 20, -32)
windowScroll:SetPoint("BOTTOMRIGHT", -32, 18)
local body = CreateFrame("Frame", nil, windowScroll)
body:SetSize(300, 1)
windowScroll:SetScrollChild(body)
local textLines = {}
local link = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
link:SetSize(288, 22)
link:SetAutoFocus(false)
link:SetScript("OnTextChanged", function(self, user)
	if user then self:SetText(self.url) self:HighlightText() end
end)
link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
link:SetScript("OnEscapePressed", function(self) self:ClearFocus() window:Hide() end)
local hint = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("TOPLEFT", link, "BOTTOMLEFT", 0, -4)
hint:SetText("Ctrl+C to copy")
window:Hide()

local function ShowWindow(row)
	for _, line in ipairs(textLines) do line:Hide() end
	local offset, used = 0, 0
	for _, line in ipairs(Q.WindowLines(row)) do
		if line.kind == "link" then
			link.url = line.text
			link:SetText(line.text)
			link:ClearFocus()
			link:ClearAllPoints()
			link:SetPoint("TOPLEFT", 6, -offset - 8)
			offset = offset + 54
		else
			used = used + 1
			local text = textLines[used]
			if not text then
				text = body:CreateFontString(nil, "OVERLAY")
				text:SetWidth(300)
				text:SetJustifyH("LEFT")
				text:SetWordWrap(true)
				textLines[used] = text
			end
			local heading = line.kind == "title" or line.kind == "header"
			text:SetFontObject(line.kind == "title" and (QuestTitleFont or GameFontNormalLarge)
				or line.kind == "header" and GameFontNormal or (QuestFont or GameFontHighlight))
			local shade = line.kind == "muted" and (paper and 0.4 or 0.6) or (paper and 0.15 or 1)
			text:SetTextColor(shade, shade, shade)
			text:ClearAllPoints()
			text:SetPoint("TOPLEFT", 0, -offset)
			text:SetText(line.text)
			text:Show()
			offset = offset + text:GetStringHeight() + (heading and 10 or 8)
		end
	end
	hint:SetTextColor(paper and 0.4 or 0.6, paper and 0.4 or 0.6, paper and 0.4 or 0.6)
	body:SetHeight(offset)
	windowScroll:SetVerticalScroll(0)
	window:ClearAllPoints()
	if panel:GetLeft() < window:GetWidth() + 8 then
		window:SetPoint("TOPLEFT", panel, "TOPRIGHT", 8, 0)
	else
		window:SetPoint("TOPRIGHT", panel, "TOPLEFT", -8, 0)
	end
	window:Show()
end

local function Refresh()
	local rows, message = Q.Build(selected, Settings().showNext)
	for i = #(rows or {}) + 1, #buttons do buttons[i]:Hide() end
	status:SetText(message or (#rows == 0 and "No quests for your race/class" or ""))
	for i, row in ipairs(rows or {}) do
		local button = buttons[i]
		if not button then
			button = CreateFrame("Button", nil, content)
			buttons[i] = button
			button:SetSize(258, 22)
			button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			button.text:SetAllPoints()
			button.text:SetJustifyH("LEFT")
			button.text:SetWordWrap(false)
			button:SetScript("OnEnter", function(self)
				local q = self.quest
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				local lines = DetailLines(q)
				GameTooltip:SetText(lines[1])
				for line = 2, #lines do GameTooltip:AddLine(lines[line], 1, 1, 1, true) end
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
			button:SetScript("OnClick", function(self)
				if Q.Click(self.quest) == "window" then ShowWindow(self.quest) end
			end)
		end
		button.quest = row
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
		local mark = row.done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t "
			or row.kind == "current" and "> " or row.inLog and "* " or "  "
		local color = row.kind == "current" and "|cffffd100" or row.kind == "next" and "|cff888888" or "|cffffffff"
		button.text:SetText(color .. mark .. "[" .. (row.level or "?") .. "] " .. RowTitle(row) .. "|r")
		button:Show()
	end
	content:SetHeight(math.max(40, #(rows or {}) * 22))
end

local function Show(questID, automatic)
	questID = tonumber(questID)
	if not questID or questID <= 0 then return end
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	local dock = details and details:IsVisible()
	if automatic and not dock then return end
	selected = questID
	panel:SetParent(dock and details or UIParent)
	panel:ClearAllPoints()
	local pos = Settings().pos
	if pos then
		local ratio = UIParent:GetEffectiveScale() / panel:GetEffectiveScale()
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x * ratio, pos.y * ratio)
	elseif dock then panel:SetPoint("TOPRIGHT", details, "TOPLEFT", -8, 0)
	else panel:SetPoint("CENTER") end
	panel:SetFrameStrata("DIALOG")
	scroll:SetVerticalScroll(0)
	Refresh()
	panel:Show()
end
QuestChain_Show = Show
SLASH_QUESTCHAIN1 = "/questchain"
SlashCmdList.QUESTCHAIN = function(command)
	if command:lower():match("^%s*reset%s*$") then
		Settings().pos = nil
		print("QuestChain: position reset")
		if selected and panel:IsShown() then Show(selected) end
	elseif command:lower():match("^%s*next%s*$") then
		local db = Settings()
		db.showNext = not db.showNext
		print("QuestChain: next quests " .. (db.showNext and "shown" or "hidden"))
		if selected and panel:IsShown() then Refresh() end
	else
		local id = C_QuestLog.GetSelectedQuest()
		if id and id > 0 then Show(id) else print("QuestChain: select a quest in the quest log") end
	end
end

local hooked, detailsHooked = false, false
local function Attach()
	if not hooked and type(QuestMapFrame_ShowQuestDetails) == "function" then
		hooked = true
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(id) Show(id, true) end)
	end
	local details = QuestMapFrame and QuestMapFrame.DetailsFrame
	if details and not detailsHooked then
		detailsHooked = true
		details:HookScript("OnShow", function()
			C_Timer.After(0, function()
				if details:IsVisible() then Show(C_QuestLog.GetSelectedQuest(), true) end
			end)
		end)
		details:HookScript("OnHide", function() if panel:GetParent() == details then panel:Hide() end end)
	end
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", Attach)
Attach()
panel:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 2 then return end
	elapsed = 0
	Refresh()
end)
return Q
