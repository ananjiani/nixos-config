-- CenterTip: tooltips at the default spot are centred sideways on Edit Mode's tooltip box.
-- In the lower half of the screen they grow up from the box's bottom, in the upper half down from its top.
hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip)
	local box = GameTooltipDefaultContainer
	if not box or tip:IsForbidden() then return end
	local _, y = box:GetCenter()
	if not y then return end
	local edge = y < UIParent:GetHeight() / 2 and "BOTTOM" or "TOP"
	tip:ClearAllPoints()
	tip:SetPoint(edge, box, edge)
end)
