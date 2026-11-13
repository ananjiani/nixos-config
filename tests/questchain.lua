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
local db = { QueryQuestSingle = function(id, field) return (quests[id] or {})[field] end }
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
for id = 100, 180 do quests[id] = { preQuestSingle = { id - 1 }, nextQuestInChain = id + 1 } end
rows = Q.Build(140)
assert(#rows == 61 and rows[1].id == 110 and rows[31].id == 140 and rows[61].id == 170, "30 steps each way")
assert(#Q.Build(140, false) == 31)
local query = db.QueryQuestSingle
db.QueryQuestSingle = function() error("still loading") end
assert(Q.Build(4) == nil)
db.QueryQuestSingle = query

assert(Q.CampfireText(1) == nil)
CampfireDB = { lexicon = { entries = {
	other = { kind = "npc", questID = 1, pages = { "Not quest text" } },
	quest = { kind = "quest", questID = 1, title = "First", pages = { [1] = "Plain page", [3] = { deflate = "packed" } } },
} } }
local title, text = Q.CampfireText(1)
assert(title == "First" and text == "Plain page", "skip compressed pages without LibDeflate")
LibStub = function(name, silent)
	assert(name == "LibDeflate" and silent)
	return { DecompressDeflate = function(_, packed) assert(packed == "packed") return "Unpacked page" end }
end
title, text = Q.CampfireText(1)
assert(title == "First" and text == "Plain page\n\nUnpacked page")
LibStub = function() return { DecompressDeflate = function() error("corrupt") end } end
assert(select(2, Q.CampfireText(1)) == "Plain page")
LibStub = function() return { DecompressDeflate = function() return nil end } end
assert(select(2, Q.CampfireText(1)) == "Plain page")
assert(Q.CampfireText(2) == nil)

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
local function frame(name, parent)
	local f = setmetatable({ name = name, parent = parent or false, scripts = {}, shown = true }, { __index = function(_, key)
		return methods[key] or function() end
	end })
	if name then frames[name] = f end
	return f
end
function methods:CreateFontString() return frame() end
CreateFrame = function(_, name, parent) return frame(name, parent) end
UIParent = frame()
SlashCmdList = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
hooksecurefunc = function(name, fn) assert(not hooks[name]) hooks[name] = fn end
Q = dofile(addon) -- The quest UI can load after this addon.
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
Q = dofile(addon)
local panel = frames.QuestChainFrame
assert(hooks.QuestMapFrame_ShowQuestDetails)
events.scripts.OnEvent(nil, "ADDON_LOADED") -- No duplicate hooks.
hooks.QuestMapFrame_ShowQuestDetails(4)
assert(panel:IsShown() and panel:GetParent() == QuestMapFrame.DetailsFrame)
assert(QuestChainDB.showNext)
SlashCmdList.QUESTCHAIN("next")
assert(QuestChainDB.showNext == false)
QuestMapFrame.DetailsFrame.scripts.OnHide()
assert(not panel:IsShown())
QuestMapFrame:Hide()
assert(QuestMapFrame.DetailsFrame:IsShown() and not QuestMapFrame.DetailsFrame:IsVisible())
SlashCmdList.QUESTCHAIN("")
assert(panel:IsVisible() and panel:GetParent() == UIParent, "a hidden map must not swallow the panel")
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
print("QuestChain tests passed (chains, Campfire, UI hooks, packaged quest menu)")
