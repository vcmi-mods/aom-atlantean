-- Effect of status god powers with patron affinity: adds bonus like core timed; if the caster's patron god (hidden AOM_GOD, inherited by the army) is in `gods`,
-- uses affinityBonus instead (bonus if not given), and bonuses without turns last extraTurns rounds longer.
-- Config: {"type": "aomAffinityTimed", "gods": [1, 3], "extraTurns": 1, "bonus": {...}, "affinityBonus": {...}}
-- Why not a separate "affinity" effect: two effects of one spell giving the same bonus replace each other, in no fixed order.
-- Affinity for damage, healing and summoning spells does not go through here; it is SPECIFIC_SPELL_DAMAGE +25% in the hero specialty.
local Base = require("spells/timed")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function casterGod(mechanics)
	if not mechanics:getHeroCaster() then return 0 end
	local side = mechanics:getCasterSide()
	for _, u in ipairs(mechanics:getBattle():getUnitsIf(function(u) return u:getSide() == side end)) do
		local g = u:getBonusesValue({ type = "AOM_GOD" })
		if g > 0 then return g end
	end
	return 0
end

local function favoured(self, mechanics)
	local g = casterGod(mechanics)
	for _, want in ipairs(self.gods or {}) do
		if want == g then return true end
	end
	return false
end

function Script:convertBonuses(mechanics)
	if not favoured(self, mechanics) then return Base.convertBonuses(self, mechanics) end
	local plain, fixed = self.bonus, {}
	self.bonus = self.affinityBonus or plain
	for name, b in pairs(self.bonus or {}) do fixed[name] = b.turns and b.turns > 0 end
	local converted = Base.convertBonuses(self, mechanics)
	self.bonus = plain
	for name, nb in pairs(converted) do
		if not fixed[name] then nb.turns = (nb.turns or 0) + (self.extraTurns or 0) end
	end
	return converted
end

-- noCommander: this effect cannot land on commanders (a commander's battle slot is -2).
function Script:isValidTarget(mechanics, unit)
	if self.noCommander and unit:getSlot() == -2 then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

return Script
