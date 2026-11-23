-- PotionOrFood: one button each from Auto Potion's macros, rewritten whenever Auto Potion rewrites its own.
-- HealthOrFood: AutoPotion in combat, AutoFood out of it. ManaOrDrink: AutoManaPotion in combat, AutoDrink out.
local P = {}
P.MERGED = {
	{ name = "HealthOrFood", combat = "AutoPotion", rest = "AutoFood" },
	{ name = "ManaOrDrink", combat = "AutoManaPotion", rest = "AutoDrink" },
}

-- Every command line of body, only when cond ("combat" or "nocombat") holds. Lines already tied to
-- the other state (Recuperate's [nocombat]) are dropped: that state belongs to the other macro.
function P.Only(body, cond)
	local other = cond == "combat" and "nocombat" or "combat"
	local out = {}
	for line in (body or ""):gmatch("[^\n]+") do
		line = line:gsub("%s+$", "")
		local cmd, rest = line:match("^(/%S+)%s*(.*)$")
		if cmd then
			local opts, tail = rest:match("^%[([^%]]*)%]%s*(.*)$")
			local words = {}
			for w in (opts or ""):gmatch("[^,]+") do words[w:match("^%s*(.-)%s*$")] = true end
			if not words[other] then
				if not words[cond] then
					opts = opts and opts ~= "" and opts .. "," .. cond or cond
				end
				out[#out + 1] = cmd .. " [" .. opts .. "]" .. ((tail or rest) ~= "" and " " .. (tail or rest) or "")
			end
		end
	end
	return out
end

function P.Merge(combatBody, restBody)
	local lines = P.Only(restBody, "nocombat")
	for _, l in ipairs(P.Only(combatBody, "combat")) do lines[#lines + 1] = l end
	return "#showtooltip" .. (#lines > 0 and "\n" .. table.concat(lines, "\n") or "")
end

local writing, pending, told = false, false, {}
local function Write()
	if InCombatLockdown() then pending = true return end
	pending = false
	local max = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACROS
	writing = true
	for _, m in ipairs(P.MERGED) do
		local text = P.Merge(GetMacroBody(m.combat), GetMacroBody(m.rest))
		if #text > 255 then
			if not told[m.name] then print("PotionOrFood: " .. m.name .. " would be too long, left as it was") end
			told[m.name] = true
		elseif GetMacroInfo(m.name) then
			if GetMacroBody(m.name) ~= text then EditMacro(m.name, m.name, nil, text) end
		elseif GetNumMacros() < max then
			CreateMacro(m.name, "INV_Misc_QuestionMark", text)
		elseif not told[m.name] then
			told[m.name] = true
			print("PotionOrFood: general macros are full, free one for " .. m.name)
		end
	end
	writing = false
end

local sources = {}
for _, m in ipairs(P.MERGED) do sources[m.combat], sources[m.rest] = true, true end
local function OnMacroWrite(name)
	if not writing and sources[name] then Write() end
end
hooksecurefunc("EditMacro", OnMacroWrite)
hooksecurefunc("CreateMacro", OnMacroWrite)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" or pending then Write() end
end)

PotionOrFood = P
