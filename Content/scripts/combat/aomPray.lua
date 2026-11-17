-- 祈神（指挥官“神谕长”，魔法强化后）：先知是大西洲恩惠的来源。
-- 神谕长活着时，本方英雄每回合多得 val 点恩惠：这里只在神谕长身上挂隐藏的 AOM_FAVOR_PRAY，由恩惠脚本 aomFavor.lua 结算时读。
-- 英雄没有恩惠特长（十位国王）时没有恩惠可加，改成开战给本方全体士气 +1（整场）。
-- 判断有没有恩惠特长：看本方有没有部队带 aomFavor 的战斗脚本（英雄特长全军继承）。
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local PRAY = "AOM_FAVOR_PRAY"

function Script:onBattleStart(server, battle, unit, other)
	local side = unit:getSide()
	local own = battle:getUnitsIf(function(x) return x:isAlive() and x:getSide() == side and not x:isTurret() end)
	local favour = false
	for _, u in ipairs(own) do
		if u:hasBonuses({ type = "COMBAT_EVENT_TRIGGER", subtype = "aom-atlantean:aomFavor" }) or u:hasBonuses({ type = "COMBAT_EVENT_TRIGGER", subtype = "aomFavor" }) then favour = true break end
	end
	if favour then
		server:addUnitBonus(battle, unit, { type = PRAY, val = self.val or 1, valueType = ENUM.BonusValueType.baseNumber,
			duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, hidden = true }, false)
	else
		for _, u in ipairs(own) do
			if not u:hasBonuses({ type = "SIEGE_WEAPON" }) then
				server:addUnitBonus(battle, u, { type = "MORALE", val = 1, valueType = ENUM.BonusValueType.additiveValue,
					duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, stacking = "aomPray", hidden = true }, false)
			end
		end
	end
end

return Script
