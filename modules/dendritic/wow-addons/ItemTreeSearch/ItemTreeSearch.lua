-- ItemTreeSearch: expose ItemTree verdict words to Bagnon's public ItemSearch filters.
local search = LibStub and LibStub("ItemSearch-1.3", true)
if not search or not search.Filters then return end

local verdicts = { keep = true, auction = true, vendor = true, disenchant = true, worthless = true }
search.Filters.itemtree = {
	tags = { "itemtree", "it" },
	onlyTags = false,
	canSearch = function(self, operator, word)
		return not operator and verdicts[word] and word
	end,
	match = function(self, item, operator, word)
		local api = ItemTreeAPI
		if not api or type(api.GetItemFacts) ~= "function" or not item then return false end
		local link = item.link
		local id = tonumber(item.id) or tonumber(link) or
			(type(link) == "string" and tonumber(link:match("item:(%d+)")))
		if not id then return false end
		local facts = api.GetItemFacts(id, link)
		for _, tag in ipairs(facts and facts.keep and facts.keep.tags or {}) do
			if tag == word then return true end
		end
		return false
	end,
}
