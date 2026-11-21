local addon = assert(arg[1], "addon path required")
local function Frame(kind)
	local f = { kind = kind, color = { 1, 0.7, 0 }, kids = {}, sets = 0 }
	function f:IsObjectType(t) return self.kind == t end
	function f:GetChildren() return unpack(self.kids) end
	function f:GetStatusBarColor() return unpack(self.color) end
	function f:SetStatusBarColor(...) self.color = { ... }; self.sets = self.sets + 1 end
	function f:GetName() return nil end
	function f:RegisterEvent() end
	function f:SetScript(_, fn) self.onEvent = fn end
	return f
end
local events
function CreateFrame() events = Frame("Frame"); return events end
function hooksecurefunc(t, name, post)
	local orig = t[name]
	t[name] = function(...) orig(...); post(...) end
end
local current = {}
C_Spell = { IsCurrentSpell = function(id) return current[id] end }
SlashCmdList, unpack = {}, unpack or table.unpack
print = function() end

dofile(addon)
events.onEvent() -- no swing frame yet: must not error
local bar = Frame("StatusBar")
SwingTimerMainHandFrame = Frame("Frame")
SwingTimerMainHandFrame.kids = { Frame("Frame"), bar }

events.onEvent()
assert(bar.color[1] == 1 and bar.color[2] == 0.7, "nothing queued keeps the game's colour")
current[11567] = true
events.onEvent()
assert(bar.color[1] == 1 and bar.color[2] == 0.1, "Heroic Strike: red")
bar:SetStatusBarColor(0.5, 0.5, 0.5) -- the game recolours mid-queue
assert(bar.color[2] == 0.1, "red stays on top")
current[11567], current[845] = nil, true
events.onEvent()
assert(bar.color[1] == 0.1 and bar.color[2] == 1, "Cleave: green")
current[845] = nil
events.onEvent()
assert(bar.color[1] == 0.5 and bar.color[2] == 0.5, "back to the game's latest colour")
local sets = bar.sets
events.onEvent()
assert(bar.sets == sets, "no repaint without a change")
SlashCmdList.SWINGQUEUE()
print = _G.io and function(...) io.write(table.concat({ ... }, " "), "\n") end
print("SwingQueue tests passed")
