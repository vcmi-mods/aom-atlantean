-- Giant Slayer (Katapeltes): bonus damage against two-hex units.
-- The engine's per-trait damage bonus (HATES_TRAIT) only knows bonus markers and has no "two-hex" marker, so units with this ability, at battle start and each round start,
-- mark living enemy two-hex units with a hidden AOM_BIG (lasts the battle; units summoned later are marked next round); the unit itself has HATES_TRAIT -> AOM_BIG.
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
