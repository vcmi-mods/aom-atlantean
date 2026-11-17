-- 蓄力一击（涅瑞伊得斯）：每 every 回合蓄满一次，蓄满后的下一次近战攻击伤害 +val%。
-- 计数用隐藏加成 AOM_CHARGE_COUNT；蓄满时挂可见的 AOM_CHARGE_READY 和同样时效的伤害加成（自己攻击一次后失效）。
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local COUNT, READY = "AOM_CHARGE_COUNT", "AOM_CHARGE_READY"

-- 动画只在真打的时候放：电脑试算（describeChanges 为假）时发动画包，引擎每次报 "BattleAnimationPlayed is not allowed in battle evaluation"
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

local function setCount(server, battle, unit, value)
	local old = unit:getBonuses({ type = COUNT })
	if old:size() > 0 then server:removeUnitBonuses(battle, unit, old) end
	if value > 0 then
		server:addUnitBonus(battle, unit, { type = COUNT, val = value, valueType = ENUM.BonusValueType.baseNumber,
			duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, hidden = true }, false)
	end
end

function Script:tick(server, battle, unit)
	if not unit:isAlive() or unit:hasBonuses({ type = READY }) then return end

	local count = unit:getBonusesValue({ type = COUNT }) + 1
	if count < (self.every or 3) then
		setCount(server, battle, unit, count)
		return
	end

	setCount(server, battle, unit, 0)
	server:addUnitBonus(battle, unit, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeMelee", val = self.val or 200,
		valueType = ENUM.BonusValueType.additiveValue, duration = ENUM.BonusDuration.untilOwnAttack, sourceType = ENUM.BonusSource.other, hidden = true }, false)
	server:addUnitBonus(battle, unit, { type = READY, val = self.val or 200, valueType = ENUM.BonusValueType.baseNumber,
		duration = ENUM.BonusDuration.untilOwnAttack, sourceType = ENUM.BonusSource.other }, false)
	showAnim(server, battle, { { unit = unit } }, "C01SPW0", "PRAYER", 1.0, true) server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append         = { "core.bonus." .. READY .. ".description.900001" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { self.val or 200 }
	})
end

function Script:onBattleStart(server, battle, unit, other)
	self:tick(server, battle, unit)
end

function Script:onRoundStart(server, battle, unit, other)
	self:tick(server, battle, unit)
end

return Script
