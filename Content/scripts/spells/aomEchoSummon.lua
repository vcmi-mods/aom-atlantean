-- Divine Echo, summoning: when the echo triggers, summons again, at echoFactor of the original amount (half by default).
-- Config as core summon plus "echoFactor". It never blocks casting (the spell's own summon effect decides whether it can be cast).
local Base = require("spells/summon")
local Echo = require("spells/aomEchoCommon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:summonedEffectValue(mechanics)
	return math.floor(Base.summonedEffectValue(self, mechanics) * (self.echoFactor or 0.5))
end

function Script:applicableGeneral(mechanics, problem)
	return true
end

function Script:apply(mechanics, server, target)
	if self:summonedCreatureAmount(mechanics) <= 0 then return end
	if not Echo.roll(mechanics, server) then return end
	-- find the target again now: the engine picked a free hex for this effect before the original summon happened, and that hex now holds the stack just summoned;
	-- searching again finds that stack (summonSameUnit) and the echo amount is merged into it
	Base.apply(self, mechanics, server, Base.transformTarget(self, mechanics, {}, {}))
end

return Script
