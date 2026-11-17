-- 状态类神力的效果本体，带主神亲和：和核心的 timed 一样加 bonus；施法英雄的主神（隐藏的 AOM_GOD，全军继承）在 gods 名单里时，
-- 改用 affinityBonus（没写就还用 bonus），并且没写 turns 的加成多持续 extraTurns 回合。
-- 配置：{"type": "aomAffinityTimed", "gods": [1, 3], "extraTurns": 1, "bonus": {...}, "affinityBonus": {...}}
-- 为什么不另挂一个“亲和”效果：同一个法术的两个效果给同一种加成会互相顶替，而且先后顺序不固定。
-- 伤害、治疗、召唤类的亲和不走这里，用英雄特长里的 SPECIFIC_SPELL_DAMAGE +25%。
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

-- noCommander：这个效果不能落在指挥官身上（指挥官的战斗格编号是 -2，和 kad 的招降、缩小同一种判法）。
function Script:isValidTarget(mechanics, unit)
	if self.noCommander and unit:getSlot() == -2 then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

return Script
