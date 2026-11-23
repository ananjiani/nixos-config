local addon = assert(arg[1], "addon path required")
local macros, hooks, events = {}, {}, nil
local combat, created = false, 0
function GetMacroBody(name) return macros[name] end
function GetMacroInfo(name) return macros[name] and name end
function GetNumMacros() return 0 end
MAX_ACCOUNT_MACROS = 120
function InCombatLockdown() return combat end
function EditMacro(name, _, _, text) macros[name] = text; for _, h in ipairs(hooks.EditMacro or {}) do h(name) end end
function CreateMacro(name, _, text) created = created + 1; macros[name] = text; for _, h in ipairs(hooks.CreateMacro or {}) do h(name) end end
function hooksecurefunc(name, fn) hooks[name] = hooks[name] or {}; table.insert(hooks[name], fn) end
function CreateFrame() events = { RegisterEvent = function() end, SetScript = function(self, _, fn) self.fn = fn end }; return events end
dofile(addon)
local P = PotionOrFood

-- Auto Potion's own shapes (code.lua): heal with stopcasting and Recuperate, food, mana castsequence.
local heal = "#showtooltip \n/stopcasting \n/cast [nocombat] Recuperate\n/castsequence [@player,combat] reset=combat item:5512, item:929"
local food = "#showtooltip\n/use [@player] item:4599"
assert(P.Merge(heal, food) == "#showtooltip\n/use [@player,nocombat] item:4599\n/stopcasting [combat]\n/castsequence [@player,combat] reset=combat item:5512, item:929")
assert(P.Merge("#showtooltip\n/castsequence reset=120 item:5513, item:3827", "#showtooltip\n/use [@player] item:1179")
	== "#showtooltip\n/use [@player,nocombat] item:1179\n/castsequence [combat] reset=120 item:5513, item:3827")
assert(P.Merge("#showtooltip", "#showtooltip") == "#showtooltip", "nothing in the bags")
assert(P.Merge(nil, food) == "#showtooltip\n/use [@player,nocombat] item:4599", "a missing source macro")

-- Writes after Auto Potion writes, and waits out combat.
macros.AutoPotion, macros.AutoFood = heal, food
events.fn(nil, "PLAYER_ENTERING_WORLD")
assert(macros.HealthOrFood:find("item:4599") and macros.ManaOrDrink == "#showtooltip" and created == 2)
combat = true
EditMacro("AutoFood", "AutoFood", nil, "#showtooltip\n/use [@player] item:8932")
assert(not macros.HealthOrFood:find("8932"), "no macro writes in combat")
combat = false
events.fn(nil, "PLAYER_REGEN_ENABLED")
assert(macros.HealthOrFood:find("8932"), "written once combat ends")
print("PotionOrFood tests passed")
