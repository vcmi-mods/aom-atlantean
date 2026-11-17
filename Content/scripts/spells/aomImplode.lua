-- Implode: area damage that grows with the number of stacks caught - +perUnit% (default 10) per extra stack, up to +maxBonus% (default 50).
-- Level 7+ giants (Titans) cannot be pulled in and are unaffected; flying units are excluded by the spell's targetCondition.
-- Config: {"type": "aomImplode", "perUnit": 10, "maxBonus": 50}
local Base = require("spells/damage")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit)
	if unit:getCreature():getLevel() >= 7 then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

local function count(target)
	local n = 0
	for _, dest in ipairs(target) do
		if dest.unit and dest.unit:isAlive() then n = n + 1 end
	end
	return n
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	local extra = math.min(self.maxBonus or 50, (self.perUnit or 10) * math.max(0, (self.caught or 1) - 1))
	return math.floor(Base.damageForTarget(self, targetIndex, mechanics, unit) * (100 + extra) / 100)
end

function Script:getHealthChange(mechanics, spellTarget)
	self.caught = count(spellTarget)
	return Base.getHealthChange(self, mechanics, spellTarget)
end

function Script:apply(mechanics, server, target)
	self.caught = count(target)
	Base.apply(self, mechanics, server, target)
end

return Script
