-- Charged Strike (Nereids): charges up every `every` rounds; the next melee attack after charging deals +val% damage.
-- Counting uses the hidden AOM_CHARGE_COUNT; when charged, the visible AOM_CHARGE_READY and a damage bonus of the same duration are added (they end after the unit's own attack).
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local COUNT, READY = "AOM_CHARGE_COUNT", "AOM_CHARGE_READY"

-- Animations only in real battles: sending animation packs during AI evaluation (describeChanges false) makes the engine log "BattleAnimationPlayed is not allowed in battle evaluation" every time
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
