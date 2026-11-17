-- Prayer (commander Chief Oracle, after Magic upgrade): the seer is the source of Atlantean Favor.
-- While the Chief Oracle lives, the hero gains val extra Favor each round: only a hidden AOM_FAVOR_PRAY is put on the Chief Oracle, read by aomFavor.lua when settling.
-- If the hero has no Favor specialty (the ten kings) there is no Favor to add; instead all own troops get +1 Morale for the battle.
-- Favor specialty check: whether any own unit carries the aomFavor combat script (hero specialties are inherited by the army).
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
