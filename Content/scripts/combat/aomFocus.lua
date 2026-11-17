-- 聚光（指挥官召唤物“聚光镜塔”）：连续照同一个目标，光越聚越强。
-- 第一次照到某个目标不加成，之后每连续再照一次伤害 +val%（addInfo.max 层封顶）；换目标从头开始。
-- 记在镜塔自己身上：AOM_FOCUS 层数（看得见）、AOM_FOCUS_ID 正在照的部队编号 + 1（隐藏）。
-- 加成在出手前按“这一下打的是不是同一个目标”现挂（untilOwnAttack），所以换目标的那一下拿不到旧目标攒的层数。
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
		if now > old and (not server.describeChanges or server:describeChanges()) then      -- 战报：聚光叠了一层
			server:appendLog(battle, { append = { "core.bonus." .. FOCUS .. ".description.900001" }, replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }, replaceNumbers = { now, (self.val or 25) * now } })
		end
	else
		set(server, battle, unit, FOCUS_ID, id, true)
		set(server, battle, unit, FOCUS, 1, false)
	end
end

return Script
