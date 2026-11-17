-- Focus (Mirror Tower, a commander summon): keeps shining on the same target and the light grows stronger.
-- No bonus the first time a target is hit; each consecutive hit on it adds +val% damage (capped at addInfo.max stacks); switching targets starts over.
-- Stored on the tower: AOM_FOCUS stacks (visible), AOM_FOCUS_ID id of the current target + 1 (hidden).
-- The bonus is added right before the attack depending on whether it is the same target (untilOwnAttack), so the hit that switches targets gets none of the old stacks.
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local FOCUS, FOCUS_ID = "AOM_FOCUS", "AOM_FOCUS_ID"

local function set(server, battle, unit, bonusType, value, hidden)
	local old = unit:getBonuses({ type = bonusType })
	if old:size() > 0 then server:removeUnitBonuses(battle, unit, old) end
	if value > 0 then
		server:addUnitBonus(battle, unit, { type = bonusType, val = value, valueType = ENUM.BonusValueType.baseNumber,
			duration = ENUM.BonusDuration.oneBattle, sourceType = ENUM.BonusSource.other, hidden = hidden }, false)
	end
end

local function mainTarget(unit, payload)
	for _, entry in ipairs(payload and payload.targets or {}) do
		if entry.unit and entry.unit:getSide() ~= unit:getSide() then return entry.unit end
	end
	return nil
end

function Script:onBeforeAttack(server, battle, unit, other, payload)
	if payload and payload.isCounter then return end
	local target = mainTarget(unit, payload)
	if target == nil then return end
	local layers = unit:getBonusesValue({ type = FOCUS })
	if layers > 0 and unit:getBonusesValue({ type = FOCUS_ID }) == target:unitID() + 1 then
		server:addUnitBonus(battle, unit, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeRanged", val = (self.val or 25) * layers,
			valueType = ENUM.BonusValueType.additiveValue, duration = ENUM.BonusDuration.untilOwnAttack, sourceType = ENUM.BonusSource.other, hidden = true }, false)
	end
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload and payload.isCounter then return end
	if not unit:isAlive() then return end
	local target = mainTarget(unit, payload)
	if target == nil or not target:isAlive() then
		set(server, battle, unit, FOCUS, 0, false) set(server, battle, unit, FOCUS_ID, 0, true)
		return
	end
	local id = target:unitID() + 1
	if unit:getBonusesValue({ type = FOCUS_ID }) == id then
		local old = unit:getBonusesValue({ type = FOCUS }); local now = math.min(self.max or 3, old + 1)
		set(server, battle, unit, FOCUS, now, false)
		if now > old and (not server.describeChanges or server:describeChanges()) then      -- battle log: Focus gained a stack
			server:appendLog(battle, { append = { "core.bonus." .. FOCUS .. ".description.900001" }, replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }, replaceNumbers = { now, (self.val or 25) * now } })
		end
	else
		set(server, battle, unit, FOCUS_ID, id, true)
		set(server, battle, unit, FOCUS, 1, false)
	end
end

return Script
