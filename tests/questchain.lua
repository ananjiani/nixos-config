local addon = assert(arg[1], "addon path required")
local Q = dofile(addon)
assert(Q.Build(4) == nil)
QuestieLoader = { ImportModule = function() error("not ready") end }
assert(Q.Build(4) == nil)
local quests = {
	[1] = { name = "First", questLevel = 10 },
	[2] = { name = "Second", preQuestSingle = { 1 } },
	[3] = { name = "Branch", preQuestSingle = { 1 } },
	[4] = { name = "Current", preQuestGroup = { 2, 3, 8, 9 }, nextQuestInChain = 5 },
	[5] = { name = "Next", nextQuestInChain = 6 },
	[6] = { name = "Last", nextQuestInChain = 4 },
	[8] = { requiredRaces = 2 },
	[9] = { requiredClasses = 2 },
}
local npcs = { [10] = { name = "Apothecary Lydon", zoneID = 267 }, [11] = { name = "Turn-in NPC", zoneID = 85 } }
local objects = { [20] = { name = "Wanted Board", zoneID = 267 } }
local items = { [30] = { name = "A Letter" } }
local db = {
	QueryQuestSingle = function(id, field) return (quests[id] or {})[field] end,
	QueryNPCSingle = function(id, field) return (npcs[id] or {})[field] end,
	QueryObjectSingle = function(id, field) return (objects[id] or {})[field] end,
	QueryItemSingle = function(id, field) return (items[id] or {})[field] end,
}
C_Map = { GetAreaInfo = function(id) return ({ [267] = "Hillsbrad Foothills", [85] = "Tirisfal Glades" })[id] end }
QuestieLoader = { ImportModule = function(_, name) assert(name == "QuestieDB") return db end }
assert(Q.Build(4) == nil, "must wait for Questie initialization")
db.QuestPointers = {}
UnitRace = function() return "Human", "Human", 1 end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
bit = { band = function(a, b) return math.floor(a / b) % 2 == 1 and b or 0 end }
C_QuestLog = {
	IsQuestFlaggedCompleted = function(id) return id == 1 or id == 2 end,
	GetLogIndexForQuestID = function(id) return id == 4 and 7 or 0 end,
	GetSelectedQuest = function() return 4 end,
}
local function IDs(rows)
	local ids = {}
	for _, row in ipairs(rows) do ids[#ids + 1] = row.id end
	return table.concat(ids, ",")
end
local rows = assert(Q.Build(4))
assert(IDs(rows) == "1,2,3,4,5,6", "branches must appear once, before current; filter race and class")
assert(rows[1].done and rows[2].done and not rows[3].done)
assert(rows[1].level == 10 and rows[1].name == "First")
assert(rows[4].kind == "current" and rows[4].inLog and not rows[3].inLog)
assert(rows[5].kind == "next")
assert(IDs(Q.Build(4, false)) == "1,2,3,4")
quests[1].preQuestSingle = { 2, 4 }
assert(IDs(Q.Build(4)) == "1,2,3,4,5,6", "backward and forward cycles must stop")
quests[5].requiredRaces = 2
assert(IDs(Q.Build(4)) == "1,2,3,4,6", "a filtered successor must not hide later eligible quests")
assert(IDs(Q.Build(8)) == "", "filter a wrong-race root too")
assert(IDs(Q.Build(999)) == "999", "missing quest data must keep the selected quest")
quests[1].startedBy, quests[1].finishedBy = { { 10 }, { 20 }, { 30 } }, { { 11 }, { 20 } }
quests[1].objectivesText = { "Collect ten samples.", "Return to Lydon." }
quests[2].startedBy, quests[2].finishedBy = { {}, { 20 }, { 30 } }, { {}, { 20 } }
quests[3].startedBy = { {}, {}, { 30 } }
quests[4].name, quests[6].name = "Elixir of Pain", "Elixir of Pain"
rows = assert(Q.Build(4))
assert(rows[1].giver.name == "Apothecary Lydon" and rows[1].giver.zone == "Hillsbrad Foothills")
assert(rows[1].turnIn.name == "Turn-in NPC" and rows[1].turnIn.zone == "Tirisfal Glades")
assert(table.concat(rows[1].objectives, "|") == "Collect ten samples.|Return to Lydon.")
assert(rows[2].giver.name == "Wanted Board" and rows[2].giver.zone == "Hillsbrad Foothills")
assert(rows[2].turnIn.name == "Wanted Board" and rows[2].turnIn.zone == "Hillsbrad Foothills")
assert(rows[3].giver.name == "item: A Letter" and rows[3].giver.zone == nil)
assert(rows[3].turnIn == nil and rows[3].objectives == nil)
assert(rows[4].part == 1 and rows[5].part == 2 and rows[1].part == nil, "number repeated names in chain order")
assert(Q.Build(4, false)[4].part == nil, "hidden successors do not add parts")
local missing = assert(Q.Build(999))[1]
assert(missing.giver == nil and missing.turnIn == nil and missing.objectives == nil and missing.part == nil)
local npcQuery, areaQuery, questQuery = db.QueryNPCSingle, C_Map.GetAreaInfo, db.QueryQuestSingle
db.QueryNPCSingle = function() error("NPC unavailable") end
assert(Q.Build(4)[1].giver == nil, "optional lookup errors must not discard the chain")
db.QueryNPCSingle = npcQuery
C_Map.GetAreaInfo = function() error("zone unavailable") end
assert(Q.Build(4)[1].giver.zone == nil)
C_Map.GetAreaInfo = nil
assert(Q.Build(4)[1].giver.zone == nil)
C_Map.GetAreaInfo = areaQuery
db.QueryQuestSingle = function(id, field)
	if field == "startedBy" or field == "finishedBy" or field == "objectivesText" then error("detail unavailable") end
	return questQuery(id, field)
end
missing = assert(Q.Build(4))[1]
assert(missing.giver == nil and missing.turnIn == nil and missing.objectives == nil)
db.QueryQuestSingle = questQuery
npcs[10].zoneID = nil
assert(Q.Build(4)[1].giver.name == "Apothecary Lydon" and Q.Build(4)[1].giver.zone == nil)
npcs[10].zoneID = 267
local objectQuery, itemQuery = db.QueryObjectSingle, db.QueryItemSingle
db.QueryObjectSingle, db.QueryItemSingle = nil, nil
rows = assert(Q.Build(4))
assert(rows[2].giver == nil and rows[2].turnIn == nil and rows[3].giver == nil)
db.QueryObjectSingle, db.QueryItemSingle = objectQuery, itemQuery
quests[3].startedBy, quests[3].objectivesText = { { 999 } }, "not a list"
assert(Q.Build(4)[3].giver == nil and Q.Build(4)[3].objectives == nil)
quests[3].startedBy, quests[3].objectivesText = { {}, {}, { 30 } }, { 123, "A valid objective." }
assert(Q.Build(4)[3].objectives[1] == "A valid objective.")
for id = 100, 180 do quests[id] = { preQuestSingle = { id - 1 }, nextQuestInChain = id + 1 } end
rows = Q.Build(140)
assert(#rows == 61 and rows[1].id == 110 and rows[31].id == 140 and rows[61].id == 170, "30 steps each way")
assert(#Q.Build(140, false) == 31)
local query = db.QueryQuestSingle
db.QueryQuestSingle = function() error("still loading") end
assert(Q.Build(4) == nil)
db.QueryQuestSingle = query

assert(#Q.CampfirePages(1) == 0)
CampfireDB = { lexicon = { entries = {
	other = { kind = "npc", questID = 1, pages = { "Not quest text" } },
	quest = { kind = "quest", questID = 1, title = "First", pages = { [1] = "Plain page", [3] = { deflate = "packed" } } },
} } }
local pages = Q.CampfirePages(1)
assert(#pages == 1 and pages[1].phase == 1 and pages[1].text == "Plain page", "skip compressed pages without LibDeflate")
LibStub = function(name, silent)
	assert(name == "LibDeflate" and silent)
	return { DecompressDeflate = function(_, packed) assert(packed == "packed") return "Unpacked page" end }
end
pages = Q.CampfirePages(1)
assert(#pages == 2 and pages[1].phase == 1 and pages[1].text == "Plain page")
assert(pages[2].phase == 3 and pages[2].text == "Unpacked page", "sparse pages keep their phase")
local lines = Q.WindowLines(Q.Build(4)[1])
local function Line(kind, text)
	for _, line in ipairs(lines) do if line.kind == kind and line.text == text then return true end end
end
assert(lines[1].kind == "title" and lines[1].text == "First")
assert(lines[2].kind == "meta" and lines[2].text == "[10] Completed")
assert(lines[3].kind == "fact" and lines[3].text == "From: Apothecary Lydon – Hillsbrad Foothills")
assert(lines[4].kind == "fact" and lines[4].text == "Turn in: Turn-in NPC – Tirisfal Glades")
assert(lines[5].kind == "header" and lines[5].text == "Quest")
assert(lines[6].kind == "text" and lines[6].text == "Plain page")
assert(lines[7].kind == "header" and lines[7].text == "Completion")
assert(lines[8].text == "Unpacked page" and lines[9].text == "Objectives")
assert(lines[10].text == "Collect ten samples." and lines[11].text == "Return to Lydon.")
assert(lines[#lines].kind == "link" and lines[#lines].text == "https://www.wowhead.com/forever/quest=1")
for _, line in ipairs(lines) do assert(line.kind ~= "muted") end
CampfireDB.lexicon.entries.progress = { kind = "quest", questID = 2, pages = { [2] = "Still at work." } }
pages = Q.CampfirePages(2)
assert(#pages == 1 and pages[1].phase == 2 and pages[1].text == "Still at work.")
lines = Q.WindowLines({ id = 2, name = "Second", kind = "earlier" })
assert(Line("header", "Progress"))
lines = Q.WindowLines(Q.Build(4)[4])
assert(lines[1].text == "Elixir of Pain (part 1)" and lines[2].text == "[?] In your log")
assert(Line("muted", "Campfire has no saved text for this quest."))
assert(lines[#lines].kind == "link" and lines[#lines].text == "https://www.wowhead.com/forever/quest=4")
lines = Q.WindowLines({ id = 999, name = "Missing" })
assert(lines[2].text == "[?] Not done")
LibStub = function() return { DecompressDeflate = function() error("corrupt") end } end
assert(#Q.CampfirePages(1) == 1)
LibStub = function() return { DecompressDeflate = function() return nil end } end
assert(#Q.CampfirePages(1) == 1)
assert(#Q.CampfirePages(999) == 0)

local opened
QuestMapFrame_OpenToQuestDetails = function(id) opened = id end
assert(Q.Click({ id = 4, kind = "current", inLog = true }) == "details" and opened == 4)
assert(Q.Click({ id = 6, kind = "next", inLog = true }) == "details" and opened == 6)
opened = nil
assert(Q.Click({ id = 1, kind = "earlier", done = true }) == "window")
assert(Q.Click({ id = 4, kind = "current" }) == "window")
assert(Q.Click({ id = 6, kind = "next" }) == nil and opened == nil)
InCombatLockdown = function() return true end
assert(Q.Click({ id = 4, inLog = true }) == "details" and opened == nil)
InCombatLockdown = nil
QuestMapFrame_OpenToQuestDetails = nil
assert(Q.Click({ id = 4, inLog = true }) == "details", "missing details API must not error")
QuestMapFrame_OpenToQuestDetails = function(id) opened = id end

-- Run the UI with small frame stubs: hook setup, selection, retry, and the saved toggle.
local frames, hooks, timers = {}, {}, {}
local methods = {}
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:HookScript(event, fn) self.scripts[event] = fn end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function methods:SetParent(parent) self.parent = parent end
function methods:GetParent() return self.parent end
function methods:SetText(text) self.textValue = text end
function methods:SetPoint(...) self.point = { ... } end
function methods:SetHeight(height) self.height = height end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:GetWidth() return self.width end
function methods:GetLeft() return rawget(self, "left") or 800 end
function methods:GetTop() return rawget(self, "top") or 600 end
function methods:GetEffectiveScale() return rawget(self, "scale") or 1 end
function methods:SetTexture(path) self.texture = path return true end
function methods:SetAtlas(name) self.atlas = name end
function methods:HighlightText() self.highlighted = true end
function methods:SetScrollChild(child) self.child = child end
function methods:GetStringHeight()
	local _, lines = (self.textValue or ""):gsub("\n", "")
	return (lines + 1) * 14
end
local function frame(name, parent)
	local f = setmetatable({ name = name, parent = parent or false, scripts = {}, children = {}, shown = true }, { __index = function(_, key)
		return methods[key] or function() end
	end })
	if parent then parent.children[#parent.children + 1] = f end
	if name then frames[name] = f end
	return f
end
function methods:CreateFontString() return frame(nil, self) end
function methods:CreateTexture() return frame(nil, self) end
UISpecialFrames = {}
CreateFrame = function(_, name, parent) return frame(name, parent) end
UIParent = frame()
SlashCmdList = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
hooksecurefunc = function(name, fn) assert(not hooks[name]) hooks[name] = fn end
Q = dofile(addon) -- The quest UI can load after this addon.
assert(frames.QuestChainQuestFrame.children[1].texture == "Interface\\QuestFrame\\QuestBG", "parchment path fallback")
QuestMapFrame = frame(nil, UIParent)
QuestMapFrame.DetailsFrame = frame(nil, QuestMapFrame)
QuestMapFrame_ShowQuestDetails = function() end
local events
-- The event frame is unnamed; capture it on the next load instead.
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
	local f = create(kind, name, parent, template)
	if not name and not parent then events = f end
	return f
end
C_Texture = { GetAtlasInfo = function(name) assert(name == "QuestBG-Parchment") return {} end }
Q = dofile(addon)
local panel = frames.QuestChainFrame
assert(hooks.QuestMapFrame_ShowQuestDetails)
events.scripts.OnEvent(nil, "ADDON_LOADED") -- No duplicate hooks.
hooks.QuestMapFrame_ShowQuestDetails(4)
assert(panel:IsShown() and panel:GetParent() == QuestMapFrame.DetailsFrame)
assert(QuestChainDB.showNext)
local content
for _, child in ipairs(panel.children) do if rawget(child, "child") then content = child.child end end
assert(content)
local buttons = {}
for _, child in ipairs(content.children) do
	if rawget(child, "quest") then buttons[#buttons + 1] = child end
end
assert(#buttons == 5 and #content.children == 6, "no pinned detail fontstring")
assert(buttons[4].text.textValue:find("Elixir of Pain (part 1)", 1, true))
assert(buttons[5].text.textValue:find("Elixir of Pain (part 2)", 1, true))
GameTooltip = frame()
function GameTooltip:SetText(text) self.lines = { text } end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
CampfireDB.lexicon.entries.current = { kind = "quest", questID = 4, pages = { "Current saved text" } }
CampfireDB.lexicon.entries.next = { kind = "quest", questID = 6, pages = { "Next saved text" } }
for _, i in ipairs({ 1, 4, 5 }) do
	buttons[i].scripts.OnEnter(buttons[i])
	local saved = Q.CampfirePages(buttons[i].quest.id)
	assert(GameTooltip.lines[#GameTooltip.lines] == saved[#saved].text, "every row kind shows saved text")
	if i == 1 then
		assert(GameTooltip.lines[2] == "From: Apothecary Lydon – Hillsbrad Foothills")
		assert(GameTooltip.lines[3] == "Turn in: Turn-in NPC – Tirisfal Glades")
		assert(GameTooltip.lines[4] == "Collect ten samples." and GameTooltip.lines[5] == "Return to Lydon.")
	end
	local before = buttons[i + 1] and buttons[i + 1].point[3]
	buttons[i].scripts.OnClick(buttons[i])
	panel.scripts.OnUpdate(nil, 2)
	if before then assert(buttons[i + 1].point[3] == before, "clicks keep fixed row offsets") end
end
local window = frames.QuestChainQuestFrame
assert(window:IsShown() and window.point[1] == "TOPRIGHT" and window.point[2] == panel)
assert(window.children[1].atlas == "QuestBG-Parchment", "use the atlas only when this client has it")
assert(UISpecialFrames[#UISpecialFrames] == "QuestChainQuestFrame")
window:Hide()
buttons[5].scripts.OnClick(buttons[5])
assert(not window:IsShown(), "next quests do not open a window")
opened = nil
buttons[4].scripts.OnClick(buttons[4])
assert(opened == 4 and not window:IsShown(), "in-log click opens game details")
panel.left = 100
buttons[1].scripts.OnClick(buttons[1])
assert(window:IsShown() and window.point[1] == "TOPLEFT", "dock on the other side near the screen edge")
local body
for _, child in ipairs(window.children) do if rawget(child, "child") then body = child.child end end
local link = body.children[1]
assert(link.textValue == "https://www.wowhead.com/forever/quest=1")
link:SetText("edited")
link.scripts.OnTextChanged(link, true)
assert(link.textValue == link.url, "copy box restores the URL after user edits")
link.highlighted = false
link.scripts.OnEditFocusGained(link)
assert(link.highlighted, "focus selects the URL for copy")
link.scripts.OnEscapePressed(link)
assert(not window:IsShown())
SlashCmdList.QUESTCHAIN("next")
assert(not buttons[5]:IsShown())
assert(QuestChainDB.showNext == false)
QuestMapFrame.DetailsFrame.scripts.OnHide()
assert(not panel:IsShown())
QuestMapFrame:Hide()
assert(QuestMapFrame.DetailsFrame:IsShown() and not QuestMapFrame.DetailsFrame:IsVisible())
SlashCmdList.QUESTCHAIN("")
assert(panel:IsVisible() and panel:GetParent() == UIParent, "a hidden map must not swallow the panel")
-- A dragged panel stays where it was left, in UIParent units, until /questchain reset.
panel.left, panel.top, panel.scale = 120, 500, 2
panel.scripts.OnDragStop(panel)
assert(QuestChainDB.pos.x == 240 and QuestChainDB.pos.y == 1000)
QuestMapFrame:Show()
QuestChain_Show(4)
assert(panel.point[1] == "TOPLEFT" and panel.point[2] == UIParent and panel.point[4] == 120 and panel.point[5] == 500)
SlashCmdList.QUESTCHAIN("reset")
assert(QuestChainDB.pos == nil and panel.point[2] == QuestMapFrame.DetailsFrame, "reset docks again")
panel.scale = nil
QuestieLoader = nil
panel.scripts.OnUpdate(nil, 2) -- Missing DB must not error, and the next refresh must retry.
QuestieLoader = { ImportModule = function() return db end }
panel.scripts.OnUpdate(nil, 2)
QuestChain_Show(0)

-- Exercise the patched packaged menu, with and without QuestChain.
local actions = assert(arg[2], "patched ForeverQuestLog Actions.lua required")
local entries = {}
local root = { CreateTitle = function() end, CreateButton = function(_, name, fn) entries[name] = fn end }
MenuUtil = { CreateContextMenu = function(_, build) build(nil, root) end }
C_SuperTrack = { GetSuperTrackedQuestID = function() return 0 end }
C_QuestLog.GetTitleForQuestID = function() return "Current" end
C_QuestLog.IsPushableQuest = function() return false end
ABANDON_QUEST_ABBREV, SUPER_TRACK_QUEST = "Abandon", "Track"
OBJECTIVES_VIEW_IN_QUESTLOG, OBJECTIVES_SHOW_QUEST_MAP, OBJECTIVES_STOP_TRACKING = "View", "Map", "Untrack"
local ns = { L = {}, Tasks = { Lists = function() return {} end } }
assert(loadfile(actions))("ForeverQuestLog", ns)
QuestChain_Show = nil
ns.Actions.QuestClick({}, { id = 4 }, "RightButton")
assert(not entries["Quest chain"])
local shown
QuestChain_Show = function(id) shown = id end
ns.Actions.QuestClick({}, { id = 4 }, "RightButton")
assert(entries["Quest chain"])
entries["Quest chain"]()
assert(shown == 4)
hooks, C_Texture = {}, nil
function methods:SetTexture() return false end
Q = dofile(addon)
assert(not frames.QuestChainQuestFrame.children[1]:IsShown(), "missing parchment leaves the dark backdrop")
print("QuestChain tests passed (chains, details, parts, Campfire pages, window lines, clicks, hover, quest window, UI hooks, packaged quest menu)")
