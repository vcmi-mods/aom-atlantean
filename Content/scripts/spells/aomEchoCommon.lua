-- 神力回响（种族二级技能 aomEcho）的公用部分。
-- 技能给英雄一条隐藏的 AOM_ECHO（回响几率，百分数；魔力术联动再 +10），全军继承；幸运术联动是 AOM_ECHO_LUCK。
-- 每个神力法术在自己的效果后面带一个“回响”效果（aomEchoDamage／aomEchoTimed／aomEchoSummon），效果触发时先来这里掷骰。
-- 只有英雄施放才回响；AI 试算（describeChanges 为假）时不掷，免得白白消耗随机数。
local M = {}

local function own(battle, side)
	return battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side end)
end

--- 掷回响。成功返回 true，并写一行战斗记录、结算幸运术联动。
local BOOST = { [0] = 15, 30, 45, 60 }      -- 和 aomAspect.lua 的 CMD_BOOST 一致
M.FX = "aom/atlantean/fx/echo.json"

function M.roll(mechanics, server)
	if not server:describeChanges() then return false end
	if not mechanics:getHeroCaster() then return false end
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	local units, chance, luck = own(battle, side), 0, false
	for _, u in ipairs(units) do
		chance = math.max(chance, u:getBonusesValue({ type = "AOM_ECHO" }))
		if u:getBonusesValue({ type = "AOM_ECHO_LUCK" }) > 0 then luck = true end
	end
	if chance <= 0 or server:rngInt(1, 100) > chance then return false end
	server:appendLog(battle, { append = { "core.bonus.AOM_ECHO.description.1" }, replaceStrings = { mechanics:getSpell():getNameTextID() }, replaceNumbers = { chance } })
	if luck then
		for _, u in ipairs(units) do
			server:addUnitBonus(battle, u, { type = "LUCK", val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true,
				sourceType = ENUM.BonusSource.other, valueType = ENUM.BonusValueType.additiveValue }, false)
		end
	end
	-- 三相御令联动（AOM_ECHO_SEASON）：回响触发的这一回合，英雄主神之相的部队当令（数值和 aomAspect.lua 的当令一致；已经当令的不重复加）
	local cmd, godAspect = 0, { [1] = 2, [2] = 1, [3] = 3 }      -- 主神 → AOM_ASPECT（克洛诺斯 = 时 2，乌拉诺斯 = 天 1，盖亚 = 地 3）
	for _, u in ipairs(units) do
		if u:getBonusesValue({ type = "AOM_ECHO_SEASON" }) > 0 then cmd = math.max(cmd, u:getBonusesValue({ type = "AOM_SEASON_CMD" })) end
	end
	if cmd > 0 then
		local turn = ENUM.BonusDuration.nTurns
		local function add(u, bonus)
			bonus.sourceType = ENUM.BonusSource.other
			bonus.valueType = bonus.valueType or ENUM.BonusValueType.additiveValue
			bonus.duration, bonus.turns = turn, 1
			server:addUnitBonus(battle, u, bonus, false)
		end
		for _, u in ipairs(units) do
			local want = godAspect[u:getBonusesValue({ type = "AOM_GOD" })]
			if want and u:getBonusesValue({ type = "AOM_ASPECT" }) == want and not u:hasBonuses({ type = "AOM_INSEASON" }) then
				add(u, { type = "STACKS_SPEED", val = 2 + u:getBonusesValue({ type = "AOM_SEASON_SPD" }), hidden = true })
				add(u, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeAll", val = BOOST[cmd] or 15, hidden = true })
				if u:getBonusesValue({ type = "AOM_SEASON_MORALE" }) > 0 then add(u, { type = "MORALE", val = 1, hidden = true }) end
				add(u, { type = "AOM_INSEASON", val = BOOST[cmd] or 15, valueType = ENUM.BonusValueType.baseNumber })
			end
		end
	end
	return true
end

--- 回响落在谁身上：法术本来能作用的部队里随机挑一支不在原目标里的；没有别的就落回原目标的第一支。
function M.pick(effect, mechanics, server, target)
	local hit = {}
	for _, dest in ipairs(target) do
		if dest.unit then hit[dest.unit:unitID()] = true end
	end
	-- 回响不误伤：负面神力只落在敌方，正面神力只落在己方（动荡之乱这类不分敌我的范围法术，原目标可以有己方，回响不会）
	local side = mechanics:getCasterSide()
	local pool = mechanics:getBattle():getUnitsIf(function(u)
		if not u:isAlive() or hit[u:unitID()] then return false end
		if mechanics:isNegative() and u:getSide() == side then return false end
		if mechanics:isPositive() and u:getSide() ~= side then return false end
		return effect:isValidTarget(mechanics, u) and effect:isReceptive(mechanics, u)
	end)
	if #pool > 0 then
		local u = pool[server:rngInt(1, #pool)]
		return { unit = u, hex = u:getPosition() }
	end
	for _, dest in ipairs(target) do
		if dest.unit and dest.unit:isAlive() and not (mechanics:isNegative() and dest.unit:getSide() == side) then return dest end
	end
	return nil
end

return M
