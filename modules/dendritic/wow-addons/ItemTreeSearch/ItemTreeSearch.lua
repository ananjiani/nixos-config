-- ItemTreeSearch: ItemTree verdicts as Baganator search words, never cached per item.
local search = Syndicator and Syndicator.Search
if not search or type(search.AddKeyword) ~= "function" then return end

for _, verdict in ipairs({ "keep", "auction", "vendor", "disenchant", "worthless" }) do
	search.AddKeyword("it-" .. verdict, function(details)
		local api = ItemTreeAPI
		if not api or type(api.GetItemFacts) ~= "function" then return nil end
		if not details or not details.itemID then return false, true end
		local facts = api.GetItemFacts(details.itemID, details.itemLink)
		if not facts then return nil end
		for _, tag in ipairs(facts.keep and facts.keep.tags or {}) do
			if tag == verdict then return true, true end
		end
		return false, true
	end, "ItemTree")
end

local function refresh()
	if type(search.ClearCache) == "function" then search.ClearCache() end
	if Baganator and Baganator.API and type(Baganator.API.RequestItemButtonsRefresh) == "function" then
		Baganator.API.RequestItemButtonsRefresh()
	end
end

local api = ItemTreeAPI
if api then
	if type(api.RegisterReadyCallback) == "function" then api.RegisterReadyCallback(refresh) end
	if type(api.RegisterChangeCallback) == "function" then api.RegisterChangeCallback(refresh) end
end
