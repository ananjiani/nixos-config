local addon = assert(arg[1], "addon path required")
Syndicator = nil
dofile(addon)
Syndicator = {}
dofile(addon)
Syndicator.Search = {}
dofile(addon)

local keywords, readyCallback, changeCallback = {}, nil, nil
local clears, refreshes = 0, 0
Syndicator.Search = {
	AddKeyword = function(word, check, group)
		assert(word:match("^it%-") and group == "ItemTree")
		assert(not keywords[word])
		keywords[word] = check
	end,
	ClearCache = function() clears = clears + 1 end,
}
ItemTreeAPI = nil
dofile(addon)
local details = { itemID = 123, itemLink = "|cffaaaaaa|Hitem:123:0|h[Grey Sword]|h|r" }
assert(keywords["it-keep"](details) == nil)
ItemTreeAPI = {}
assert(keywords["it-keep"](details) == nil)

local tags, seenId, seenLink
ItemTreeAPI = {
	GetItemFacts = function(id, link)
		seenId, seenLink = id, link
		if tags then return { keep = { tags = tags } } end
	end,
	RegisterReadyCallback = function(callback) readyCallback = callback end,
	RegisterChangeCallback = function(callback) changeCallback = callback end,
}
Baganator = { API = { RequestItemButtonsRefresh = function() refreshes = refreshes + 1 end } }
keywords = {}
dofile(addon)
local count = 0
for _ in pairs(keywords) do count = count + 1 end
assert(count == 5)
for _, verdict in ipairs({ "keep", "auction", "vendor", "disenchant", "worthless" }) do
	assert(keywords[verdict] == nil)
	local check = assert(keywords["it-" .. verdict])
	assert(check(details) == nil, "not ready must stay pending")
	tags = { verdict }
	local result, doNotCache = check(details)
	assert(result == true and doNotCache == true)
	assert(seenId == details.itemID and seenLink == details.itemLink)
	tags = { "other" }
	result, doNotCache = check(details)
	assert(result == false and doNotCache == true)
	tags = nil
end
tags = { "keep", "auction" }
assert(keywords["it-keep"](details) and keywords["it-auction"](details))
ItemTreeAPI.GetItemFacts = function() return {} end
local result, doNotCache = keywords["it-keep"](details)
assert(result == false and doNotCache == true)
assert(not keywords["it-keep"]({}))
assert(not keywords["it-keep"](nil))
assert(readyCallback and changeCallback)
readyCallback()
changeCallback("setting")
assert(clears == 2 and refreshes == 2)
Baganator = nil
changeCallback("demo")
Baganator = { API = {} }
readyCallback()
assert(clears == 4 and refreshes == 2)
ItemTreeAPI = { GetItemFacts = function() return nil end }
keywords = {}
dofile(addon) -- Older ItemTree without callbacks is safe too.

-- Execute the shipped patch with the upstream keyword, prefix, and cache code.
-- Only the unrelated tooltip/pattern matching and full initialization need stubs.
local syndicator = assert(arg[2], "patched Syndicator path required")
local file = assert(io.open(syndicator))
local source = file:read("*a")
file:close()
local function between(first, last)
	local start = assert(source:find(first, 1, true), first)
	local finish = assert(source:find(last, start + #first, true), last)
	return source:sub(start, finish - 1)
end
local patchStart = assert(source:find("-- local patch (nix):", 1, true))
local run = assert(loadstring(table.concat({
	"local addonTable = { Search = {} }; Syndicator = { Search = {} }",
	"local MatchesText = function() return false end",
	"local MatchesTextExclusive = MatchesText",
	"local EXCLUSIVE_KEYWORDS_NO_TOOLTIP_TEXT = {}",
	"local PatternSearch = function() return nil end",
	between("local KEYWORDS_TO_CHECK = {}", "local function AddKeywordLocalised"),
	between("local sortedKeywords = {}", "local GetItemLevel"),
	between("local savedMatches = {}", "local function BlendOperations"),
	"local ProcessTerms = ApplyKeyword",
	between("function addonTable.Search.CheckItem(details, searchString)", "function addonTable.Search.InitializeSearchEngine()"),
	between("function addonTable.Search.RebuildKeywordList()", "function addonTable.Search.GetKeywords()"),
	"Syndicator.Search.ClearCache = addonTable.Search.ClearCache",
	source:sub(patchStart),
	"return addonTable.Search, BinarySmartSearch, KEYWORD_AND_CATEGORY, KEYWORD_AND_CATEGORY_ENGLISH",
}, "\n")))
local internal, prefix, categories, englishCategories = run()
local search = Syndicator.Search
assert(not internal.CheckItem({}, "it-keep")) -- Seed both negative caches.
assert(not internal.CheckItem({}, "it-vendor"))
local keep = true
search.AddKeyword("it-keep", function() return keep, true end, "ItemTree")
assert(internal.CheckItem({}, "it-keep"), "registration must clear rejected searches")
internal.RebuildKeywordList() -- This is the final call in InitializeSearchEngine.
local item = {}
assert(internal.CheckItem(item, "it-keep"))
keep = false
assert(not internal.CheckItem(item, "it-keep"), "positive verdicts must not cache")
keep = true
assert(internal.CheckItem(item, "it-keep"), "negative verdicts must not cache")
search.AddKeyword("it-vendor", function() return true, true end, "ItemTree")
assert(internal.CheckItem({}, "it-vendor"), "registration after init must clear rejects")
assert(internal.CheckItem({}, "it-vend"), "new keywords must support prefix searches")
internal.RebuildKeywordList()
local all = prefix("")
assert(#all == 4, "each keyword and its underscore alias must appear once")
for index = 2, #all do assert(all[index - 1] < all[index], "keywords must stay sorted and unique") end
assert(#categories == 2 and #englishCategories == 2)
assert(categories[1].keyword == "it-keep" and categories[1].group == "ItemTree")

-- Run the bridge through Syndicator's real ApplyKeyword and item-result caches.
internal = run()
ItemTreeAPI = { GetItemFacts = function()
	if tags then return { keep = { tags = tags } } end
end }
tags = nil
dofile(addon)
local fresh = { itemID = details.itemID, itemLink = details.itemLink }
assert(internal.CheckItem(fresh, "it-auction") == nil)
tags = { "auction" }
assert(internal.CheckItem(fresh, "it-auction"))
tags = { "vendor" }
assert(not internal.CheckItem(fresh, "it-auction"))
assert(internal.CheckItem(fresh, "it-vendor"))
print("ItemTreeSearch tests passed (including shipped Syndicator patch and caches)")
