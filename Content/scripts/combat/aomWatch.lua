-- 观象（指挥官“神谕长”）：先知站定不动，看得越来越远。
-- 回合开始时，神谕长上一回合没有挪过位置就叠一层（addInfo.max 层封顶），挪过就清零；
-- 每层让本方全体射手（含聚光镜塔）这一回合远程伤害 +val%。层数记在神谕长身上（AOM_WATCH，看得见），上回合站的格子记在 AOM_WATCH_POS（格子编号 + 1，隐藏）。
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
	if layers > before and (not server.describeChanges or server:describeChanges()) then      -- 战报：观象叠了一层
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
