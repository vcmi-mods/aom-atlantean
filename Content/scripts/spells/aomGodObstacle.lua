-- Effect of obstacle god powers (Gaia's Forest, Golden Apple Tree): like core obstacle; if the caster's patron god is in `gods`, the obstacle stays extraTurns rounds longer.
-- Config: all fields of core obstacle + {"gods": [3], "extraTurns": 1}
local Base = require("spells/obstacle")
local God = require("spells/aomGod")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- for obstacles whose image aligns west, the anchor hex is west of the occupied hex; targets too far left would put the anchor off the field, so they are not allowed.
function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if not dest.hex or not dest.hex:isValid() then
			problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
			return false
		end
	end
	return Base.applicableTarget(self, mechanics, problem, target)
end

function Script:apply(mechanics, server, target)
	local plain = self.turnsRemaining
	if plain and plain > 0 and God.favoured(self, mechanics) then self.turnsRemaining = plain + (self.extraTurns or 1) end
	Base.apply(self, mechanics, server, target)
	self.turnsRemaining = plain
end

return Script
