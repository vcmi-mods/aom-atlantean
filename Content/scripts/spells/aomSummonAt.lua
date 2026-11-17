-- Summon next to the target hex: like core summon, but the new stack lands on the free hex nearest the target instead of the default spot on own half.
-- With summonSameUnit and an existing summoned stack of the same kind it merges into that stack as usual.
local Base = require("spells/summon")
local God = require("spells/aomGod")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local found = Base.transformTarget(self, mechanics, aimPoint, spellTarget)
	if #found == 0 or found[1].unit ~= nil or #aimPoint == 0 or not aimPoint[1].hex then return found end
	local battle, creature, side = mechanics:getBattle(), LIBRARY:getCreatureByName(self.id), mechanics:getCasterSide()
	local skip = {}
	for _, s in ipairs(self.keepFree or {}) do skip[s] = true end
	for _, cand in ipairs(God.hexesByDistance(battle, aimPoint[1].hex)) do
		if cand.d >= (self.minDistance or 1) and battle:isAccessibleForNewUnit(cand.hex, creature, side) then
			return { { hex = cand.hex, unit = nil } }
		end
	end
	return found
end

return Script
