-- 克制巨物（长锤步兵）：对双格部队伤害加成。
-- 引擎的按标记加伤（HATES_TRAIT）只认加成标记，没有“双格”这个标记，所以由带这个能力的兵在战斗开始和每回合开始时，
-- 给敌方还活着的双格部队挂一个隐藏标记 AOM_BIG（整场有效；后来召唤出来的下一回合补上），兵自己带 HATES_TRAIT → AOM_BIG。
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local BIG = "AOM_BIG"

function Script:mark(server, battle, unit)
	if not unit:isAlive() then return end
	local side = unit:getSide()
	for _, other in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() ~= side end)) do
		if other:getCreature():isDoubleWide() and not other:hasBonuses({ type = BIG }) then
			server:addUnitBonus(battle, other, { type = BIG, val = 1, valueType = ENUM.BonusValueType.baseNumber,
				duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, hidden = true }, false)
		end
	end
end

function Script:onBattleStart(server, battle, unit, other)
	self:mark(server, battle, unit)
end

function Script:onRoundStart(server, battle, unit, other)
	self:mark(server, battle, unit)
end

return Script
