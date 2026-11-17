-- 恩惠：神话时代各族共用的英雄特长风格（大西洲版）。
-- 挂法：英雄特长里的 COMBAT_EVENT_TRIGGER（整支军队都继承），addInfo：
--   creatures  这位英雄的特长兵（各形态的标识符）
--   patron     守护神（6 点的小神神恩用），可不写
--   god        英雄职业对应的主神："kronos"、"oranos"、"gaia"（10 点的主神神力用）
-- val = 每回合开始加几点恩惠。
--
-- 恩惠值按“一方”计：脚本对每个单位各触发一次，所以用两个隐藏计数分辨“这一回合这一方算过没有”——
--   AOM_FAVOR_SEEN  这个单位经历过的回合数；AOM_FAVOR_TICK  这一方已经结算到第几回合。
-- 一方里第一个发现“自己的回合数 > 已结算回合数”的单位负责结算，其余跳过。
-- 恩惠值、已触发的档位记在这一方所有带脚本的单位上（特长兵身上的那份可见），谁阵亡都不会丢。
--
-- 三档神恩（每场各一次，自动触发，玩家和电脑一样）：
--   3 点  赐神性：特长兵 2 回合内攻击无视目标 15% 防御
--   6 点  小神神恩：按 patron（现在只有勒托：特长兵修复到满血）
--   10 点 主神神力：按 god（克洛诺斯：全场敌军时滞 +1 层；盖亚：本方脚下全部长出繁茂地面；乌拉诺斯的冲击波还没接）
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local FAVOR, SEEN, TICK, TIER, DIVINE = "AOM_FAVOR", "AOM_FAVOR_SEEN", "AOM_FAVOR_TICK", "AOM_FAVOR_TIER", "AOM_DIVINITY"
local FAVOR_FX = "aom/atlantean/fx/favor.json"      -- 神恩降下的金色光柱（原来借用祝福术、祈祷的动画）
local THRESHOLD = { 2, 4, 7 }      -- 3/6/10 before the 2026-11-14 audit: the later two rarely came up in a normal battle

-- 动画只在真打的时候放：电脑试算（describeChanges 为假）时发动画包，引擎每次报 "BattleAnimationPlayed is not allowed in battle evaluation"
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

local function setValue(server, battle, unit, bonusType, value, hidden)
	local old = unit:getBonuses({ type = bonusType })
	if old:size() > 0 then server:removeUnitBonuses(battle, unit, old) end
	if value > 0 then
		server:addUnitBonus(battle, unit, {
			type       = bonusType,
			sourceType = ENUM.BonusSource.other,
			val        = value,
			valueType  = ENUM.BonusValueType.baseNumber,
			duration   = ENUM.BonusDuration.oneBattle,
			hidden     = hidden
		}, false)
	end
end

local function shortKey(unit)
	local key = unit:getCreature():getJsonKey()
	key = key:match("([^:]+)$") or key
	-- kad 的缩小态、降级态（kadMini_aom_atlantean_<兵> 等）按原兵算
	return key:match("^kad%a+_aom_atlantean_(.+)$") or key
end

function Script:isFavored(unit)
	local key = shortKey(unit)
	for _, id in ipairs(self.creatures or {}) do
		if id == key then return true end
	end
	return false
end

--- 这一方所有活着、带本脚本的单位
local function sideUnits(battle, unit)
	local side = unit:getSide()
	return battle:getUnitsIf(function(u)
		return u:isAlive() and u:getSide() == side and u:getBonusesValue({ type = SEEN }) > 0
	end)
end

local function sideMax(units, bonusType)
	local best = 0
	for _, u in ipairs(units) do
		best = math.max(best, u:getBonusesValue({ type = bonusType }))
	end
	return best
end

local function buff(server, battle, u, bonus)      -- [town_design2]
	bonus.sourceType = ENUM.BonusSource.other
	bonus.valueType = bonus.valueType or ENUM.BonusValueType.additiveValue
	server:addUnitBonus(battle, u, bonus, false)
end

function Script:grant(server, battle, units, tier, favor)
	local favored = {}
	for _, u in ipairs(units) do
		if self:isFavored(u) then favored[#favored + 1] = u end
	end
	-- 特长兵全部阵亡后神恩照常触发（Yu 2026-11-14）：只作用在特长兵身上的那几种这时没有对象，自然落空；
	-- 作用在全军或敌军身上的（俄刻阿诺斯的潮涌、三位主神的神力）照常生效。
	if #units == 0 then return end
	local wholeArmy = tier == 3 or (tier == 2 and self.patron == "oceanus")
	-- 特长兵不在场（没带或全部阵亡）：只给特长兵的那两档落在本方总生命最高的一队身上（Yu 2026-11-14，审计 P2）
	if #favored == 0 and not wholeArmy then
		local best, bestHp
		for _, u in ipairs(units) do
			if not u:hasBonuses({ type = "SIEGE_WEAPON" }) then
				local hp = (u:getCount() - 1) * u:getMaxHealth() + u:getFirstHPleft()
				if not best or hp > bestHp then best, bestHp = u, hp end
			end
		end
		if not best then return end
		favored[1] = best
	end

	local targets = {}
	for _, u in ipairs(favored) do targets[#targets + 1] = { unit = u } end

	if tier == 1 then
		for _, u in ipairs(favored) do
			server:addUnitBonus(battle, u, {
				type = "ENEMY_DEFENCE_REDUCTION", val = 15, valueType = ENUM.BonusValueType.additiveValue,
				duration = ENUM.BonusDuration.nTurns, turns = 2, sourceType = ENUM.BonusSource.other, hidden = true
			}, false)
			server:addUnitBonus(battle, u, {
				type = DIVINE, val = 1, valueType = ENUM.BonusValueType.baseNumber,
				duration = ENUM.BonusDuration.nTurns, turns = 2, sourceType = ENUM.BonusSource.other
			}, false)
		end
		showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
	elseif tier == 2 then
		if self.patron == "leto" then
			for _, u in ipairs(favored) do
				local missing = u:getMaxHealth() - u:getFirstHPleft()
				if missing > 0 then server:healUnit(battle, u, missing, ENUM.HealLevel.heal, ENUM.HealPower.permanent) end
			end
			showAnim(server, battle, targets, "C06SPW", "CURE", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "atlas" then          -- 擎天：这一回合受到的伤害 -50%
			for _, u in ipairs(favored) do buff(server, battle, u, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 50, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true }) end
			showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "krios" then          -- 星引：这一回合多攻击一次
			for _, u in ipairs(favored) do buff(server, battle, u, { type = "ADDITIONAL_ATTACK", val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true }) end
			showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "hyperion" then       -- 光耀：蓄力立刻蓄满（和 aomCharge.lua 蓄满时挂的两条一样）
			for _, u in ipairs(favored) do
				if not u:hasBonuses({ type = "AOM_CHARGE_READY" }) then
					buff(server, battle, u, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeMelee", val = 200, duration = ENUM.BonusDuration.untilOwnAttack, hidden = true })
					buff(server, battle, u, { type = "AOM_CHARGE_READY", val = 200, valueType = ENUM.BonusValueType.baseNumber, duration = ENUM.BonusDuration.untilOwnAttack })
				end
			end
			showAnim(server, battle, targets, FAVOR_FX, "PRAYER", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "helios" then         -- 烈日：2 回合内伤害 +25%
			for _, u in ipairs(favored) do buff(server, battle, u, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeAll", val = 25, duration = ENUM.BonusDuration.nTurns, turns = 2, hidden = true }) end
			showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "oceanus" then        -- 潮涌：己方全体活物恢复 20% 生命
			local healed = {}
			for _, u in ipairs(units) do
				if not u:hasBonuses({ type = "NON_LIVING" }) and not u:hasBonuses({ type = "MECHANICAL" }) and not u:hasBonuses({ type = "UNDEAD" }) and not u:hasBonuses({ type = "SIEGE_WEAPON" }) then
					local missing = u:getMaxHealth() - u:getFirstHPleft()
					local amount = math.min(missing, math.ceil(u:getMaxHealth() * 20 / 100))
					if amount > 0 then server:healUnit(battle, u, amount, ENUM.HealLevel.heal, ENUM.HealPower.permanent) healed[#healed + 1] = { unit = u } end
				end
			end
			if #healed > 0 then showAnim(server, battle, healed, "C06SPW", "CURE", 1.0, true) end
			server:refreshBattleUnits(battle)
		elseif self.patron == "kastor" then         -- 英雄之志：2 回合内攻击和防御 +4
			for _, u in ipairs(favored) do
				buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "attack", val = 4, duration = ENUM.BonusDuration.nTurns, turns = 2, hidden = true })
				buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "defence", val = 4, duration = ENUM.BonusDuration.nTurns, turns = 2, hidden = true })
			end
			showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
		else
			return
		end
	else
		-- 主神神力（每场一次）：克洛诺斯 = 全场敌军时滞 +1 层；盖亚 = 本方所有部队脚下长出繁茂地面；乌拉诺斯的冲击波等第 8 步的神力法术
		local Aspect = require("combat/aomAspect")
		local side = units[1]:getSide()
		if self.god == "kronos" then
			for _, enemy in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() ~= side end)) do
				Aspect.addLag(Aspect, server, battle, enemy)
			end
			server:refreshBattleUnits(battle)
		elseif self.god == "gaia" then
			for _, own in ipairs(units) do
				Aspect.lush(Aspect, server, battle, own)
			end
			server:refreshBattleUnits(battle)
		elseif self.god == "oranos" then            -- 冲击波：全场敌军速度 -2，持续 2 回合 [town_design2]
			for _, enemy in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() ~= side end)) do
				buff(server, battle, enemy, { type = "STACKS_SPEED", val = -2, duration = ENUM.BonusDuration.nTurns, turns = 2 })
			end
			server:refreshBattleUnits(battle)
		else
			return
		end
	end

	server:appendLog(battle, {
		append         = { "core.bonus." .. FAVOR .. ".description." .. (900000 + tier) },
		replaceStrings = { (favored[1] or units[1]):getCreature():getNameTextID((favored[1] or units[1]):getCount()) },
		replaceNumbers = { favor }
	})
end

function Script:onBattleStart(server, battle, unit, other)
	setValue(server, battle, unit, SEEN, 1, true)
end

function Script:onRoundStart(server, battle, unit, other)
	if not unit:isAlive() then return end

	local seen = unit:getBonusesValue({ type = SEEN }) + 1
	setValue(server, battle, unit, SEEN, seen, true)

	local units = sideUnits(battle, unit)
	if sideMax(units, TICK) >= seen then return end

	-- 祈神（指挥官神谕长，aomPray.lua）：神谕长活着时每回合多得它身上 AOM_FAVOR_PRAY 那么多点
	local side = unit:getSide()
	local pray = sideMax(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side end), "AOM_FAVOR_PRAY")
	local favor = sideMax(units, FAVOR) + (self.val or 1) + pray
	local tier  = sideMax(units, TIER)
	local reached = tier
	for i, need in ipairs(THRESHOLD) do
		if favor >= need then reached = math.max(reached, i) end
	end

	for _, u in ipairs(units) do
		setValue(server, battle, u, TICK, seen, true)
		setValue(server, battle, u, FAVOR, favor, not self:isFavored(u))
		setValue(server, battle, u, TIER, reached, true)
	end

	for t = tier + 1, reached do
		self:grant(server, battle, units, t, favor)
	end
end

return Script
