local addon = assert(arg[1], "addon path required")
LibStub = nil
dofile(addon)
LibStub = function(name, silent)
	assert(name == "ItemSearch-1.3" and silent)
end
dofile(addon)
local lib = {}
LibStub = function() return lib end
dofile(addon)
lib.Filters = {}
dofile(addon)
local filter = assert(lib.Filters.itemtree)
assert(not filter.onlyTags)
assert(filter.tags[1] == "itemtree")
assert(not filter:canSearch(nil, "vend"))
assert(not filter:canSearch(nil, "sword"))
assert(not filter:canSearch(">", "vendor"))
assert(not filter:match({ link = "item:123" }, nil, "vendor"))
ItemTreeAPI = {}
assert(not filter:match({ link = "item:123" }, nil, "vendor"))

local tags, seenId, seenLink
ItemTreeAPI.GetItemFacts = function(id, link)
	seenId, seenLink = id, link
	if tags then return { keep = { tags = tags } } end
end
local link = "|cffaaaaaa|Hitem:123:0|h[Grey Sword]|h|r"
for _, word in ipairs({ "keep", "auction", "vendor", "disenchant", "worthless" }) do
	assert(filter:canSearch(nil, word) == word)
	tags = { word }
	assert(filter:match({ link = link }, nil, word))
	assert(seenId == 123 and seenLink == link)
	assert(not filter:match({ link = link }, nil, "other"))
end
tags = { "keep", "auction" }
assert(filter:match({ id = 456 }, nil, "auction") and seenId == 456)
assert(filter:match({ link = 789 }, nil, "keep") and seenId == 789)
assert(not filter:match({ link = "battlepet:123" }, nil, "keep"))
assert(not filter:match(nil, nil, "keep"))
tags = nil
assert(not filter:match({ link = link }, nil, "keep"))
ItemTreeAPI.GetItemFacts = function() return {} end
assert(not filter:match({ link = link }, nil, "keep"))
-- Exercise the actual parser shipped by Bagnon, including plain words and combinations.
local parser = {}
LibStub = { NewLibrary = function() return parser end }
format, tinsert = string.format, table.insert
QUEST_LOGIC_AND, QUEST_LOGIC_OR, NO = "and", "or", "not"
GetLocale = function() return "enUS" end
dofile(assert(arg[2], "Bagnon parser path required"))
ItemTreeAPI.GetItemFacts = function() return { keep = { tags = { "vendor" } } } end
lib.Filters.name = {
	canSearch = function(self, operator, word) return not operator and word end,
	match = function(self, item, operator, word) return item.link:lower():find(word, 1, true) end,
}
local item = { link = link }
local function matches(text) return parser:Compile(text, lib.Filters)(item) end
assert(matches("vendor"))
assert(matches("vendor sword"))
assert(not matches("vendor shield"))
assert(matches("vendor and sword"))
assert(matches("keep or vendor"))
assert(matches("vendor !keep"))
assert(not matches("!vendor"))
assert(matches("itemtree:vendor"))
assert(not matches("itemtree:auction"))
print("ItemTreeSearch tests passed (including Bagnon's parser)")
