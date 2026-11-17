-- Stargazing (commander Chief Oracle): the seer stands still and sees ever farther.
-- At round start, if the Chief Oracle did not move last round it gains a stack (capped at addInfo.max), otherwise stacks reset;
-- each stack gives all own shooters (Mirror Tower included) +val% ranged damage this round. Stacks are on the Chief Oracle (AOM_WATCH, visible), last round's hex in AOM_WATCH_POS (hex + 1, hidden).
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local WATCH, POS = "AOM_WATCH", "AOM_WATCH_POS"

local function set(server, battle, unit, bonusType, value, hidden)
	local old = unit:getBonuses({ type = bonusType })
	if old:size() > 0 then server:removeUnitBonuses(battle, unit, old) end
	if value > 0 then
		server:addUnitBonus(battle, unit, { type = bonusType, val = value, valueType = ENUM.BonusValueType.baseNumber,
			duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, hidden = hidden }, false)
	end
end

local function hexId(unit)
	local h = unit:getPosition()
	return h:getY() * 17 + h:getX() + 1
end

function Script:onBattleStart(server, battle, unit, other)
	set(server, battle, unit, POS, hexId(unit), true)
end

function Script:onRoundStart(server, battle, unit, other)
	if not unit:isAlive() then return end
	local here, layers = hexId(unit), unit:getBonusesValue({ type = WATCH })
	local before = layers
	if unit:getBonusesValue({ type = POS }) == here then
		layers = math.min(self.max or 4, layers + 1)
	else
		layers = 0
	end
	set(server, battle, unit, POS, here, true)
	set(server, battle, unit, WATCH, layers, false)
	if layers <= 0 then return end
	if layers > before and (not server.describeChanges or server:describeChanges()) then      -- battle log: Stargazing gained a stack
		server:appendLog(battle, { append = { "core.bonus." .. WATCH .. ".description.900001" }, replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }, replaceNumbers = { layers, (self.val or 5) * layers } })
	end
	local side = unit:getSide()
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and x:getSide() == side and x:isShooter() and not x:isTurret() end)) do
		server:addUnitBonus(battle, u, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeRanged", val = (self.val or 5) * layers,
			valueType = ENUM.BonusValueType.additiveValue, duration = ENUM.BonusDuration.nTurns, turns = 1, sourceType = ENUM.BonusSource.other,
			stacking = "aomWatch", hidden = true }, false)
	end
	server:refreshBattleUnits(battle)
end

return Script
