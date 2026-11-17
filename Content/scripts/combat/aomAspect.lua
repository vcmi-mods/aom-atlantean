-- 泰坦三相（大西洲的种族系统）。每个兵种带一份，addInfo.aspect = "sky"（天）、"time"（时）、"earth"（地）或 "man"（人，英雄形态）。
--
-- 天：攻击后给目标挂“天眼”2 回合。带三相脚本的部队攻击带天眼的目标：无距离、无城墙惩罚，幸运 +1。
-- 时：攻击后给目标叠一层“时滞”（速度 -1，3 回合），叠到 3 层时目标“定格”一回合（不能行动），层数清空。
-- 地：每回合开始在脚下留下“繁茂地面”3 回合（可通行的战场障碍物，两方各用一个标记法术区分是谁的）。
--     本方部队站在上面：这一回合回血 10%、防御 +2，并免疫时滞和定格（地利）；敌人站在上面：这一回合速度 -2。
--     人（英雄形态）站在繁茂地面上攻击 +3。
-- 人：借势——攻击带天眼的目标伤害 +100%；攻击带时滞的目标多叠一层。
-- 天时：目标同时带天眼和时滞时，攻击无视其 30% 防御。
-- 四者齐备：军中同时有天、时、地、人，英雄形态每场一次在一回合里多攻击一次。克洛诺斯泰坦（addInfo.surgeOnce）第一次当令时同样多攻击一次。
-- 神代轮转：每回合一相当令，顺序天 → 时 → 地；当令的兵这一回合速度 +2、伤害 +15%。
-- 主神：英雄特长里带隐藏的 AOM_GOD（1 克洛诺斯、2 乌拉诺斯、3 盖亚，全军继承），主神对应的那一相加强一档——
--     乌拉诺斯：天眼持续 3 回合；克洛诺斯：时滞 2 层即定格；盖亚：繁茂回血 15%。
-- 停转：英雄带 AOM_SEASON_HOLD（克洛诺斯本人）时，“时”连续当令两回合，轮转变成天 → 时 → 时 → 地。
-- 三相御令（种族二级技能，英雄带隐藏的 AOM_SEASON_CMD = 1／2／3，全军继承）：当令伤害 +30%／45%／60%（0.0.52 前是 25／35／50），另由技能配置给英雄攻击 +1／2／3；
--     高级起轮转从英雄主神之相开始；专家时英雄形态（人）在主神之相当令的回合也算当令。
--     主神神殿（城镇建筑，守城部队带隐藏的 AOM_SEASON_TEMPLE）：守城战里轮转同样从守城英雄主神之相开始。
--     泰坦遗宝（AOM_RELIC）：当令伤害再 +10%，第一回合三相同时当令。
--     联动：战术（AOM_SEASON_SPD）当令速度再 +1；领导术（AOM_SEASON_MORALE）当令的兵士气 +1。
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local ROUND, SEASON, SKYEYE, TIMELAG, FROZEN = "AOM_ASPECT_ROUND", "AOM_INSEASON", "AOM_SKYEYE", "AOM_TIMELAG", "AOM_FROZEN"
local ORDER = { sky = 0, time = 1, earth = 2 }
local MAX_LAG = 3
local CMD_BOOST = { [0] = 15, 30, 45, 60 }      -- 当令伤害：没有三相御令 15%，初级／中级／高级 30／45／60%
local GOD, HOLD = "AOM_GOD", "AOM_SEASON_HOLD"
local KRONOS, ORANOS, GAIA = 1, 2, 3
local CMD, CMD_SPD, CMD_MORALE = "AOM_SEASON_CMD", "AOM_SEASON_SPD", "AOM_SEASON_MORALE"
local GOD_PHASE = { [1] = 1, [2] = 0, [3] = 2 }      -- 主神 → 它那一相在轮转里的序号（克洛诺斯 = 时，乌拉诺斯 = 天，盖亚 = 地）
local HELD = { [0] = 0, [1] = 1, [2] = 1, [3] = 2 }

-- 动画只在真打的时候放：电脑试算（describeChanges 为假）时发动画包，引擎每次报 "BattleAnimationPlayed is not allowed in battle evaluation"
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

local function god(unit)
	return unit:getBonusesValue({ type = GOD })
end

local function add(server, battle, unit, bonus, cumulative)
	bonus.sourceType = bonus.sourceType or ENUM.BonusSource.other
	bonus.valueType = bonus.valueType or ENUM.BonusValueType.additiveValue
	server:addUnitBonus(battle, unit, bonus, cumulative or false)
end

local function clear(server, battle, unit, bonusType)
	local old = unit:getBonuses({ type = bonusType })
	if old:size() > 0 then server:removeUnitBonuses(battle, unit, old) end
end

local LUSH, MIRED = "AOM_LUSH", "AOM_MIRED"
local LUSH_SPELL = { [0] = "aomLushGround0", [1] = "aomLushGround1" }
local LUSH_ANIMATION = "aom/atlantean/fx/lush.json"
-- 消散：引擎把消散动画倒着播，所以帧序是从淡到实；不写的话 Yu 的引擎每块报一次 "I don't know how to animate removal of this obstacle"
local LUSH_FADE = "aom/atlantean/fx/lushOut.json"
-- 状态挂上时的画面，都是游戏原版特效（tools/fx_spell.py、fx_cut.py）：天眼 = skypassage_symbol_glow，时滞和定格 = kronos_glow（小、大），天相当令 = sky_passage_glow
local FX = { eye = "aom/atlantean/fx/skyeye.json", lag = "aom/atlantean/fx/timelag.json", frozen = "aom/atlantean/fx/frozen.json", seasonSky = "aom/atlantean/fx/seasonSky.json",
	seasonEarth = "aom/atlantean/fx/seasonEarth.json", seasonCmd = "aom/atlantean/fx/seasonCmd.json" }
local SEASON_FX = { sky = FX.seasonSky, time = FX.lag, earth = FX.seasonEarth }

-- 天眼的地面光盘要压在目标脚下：引擎按“行在先、层在后”画，特效总画在同一行部队的上面。
-- 所以光盘播在目标上一行的格子上（先于目标那一行画出来），图片事先按“脚底在图片中心下方 83 像素、左右偏 22 像素”裁好：
--   单格目标：左上格用 skyeyeGL，右上格用 skyeyeGR；双格目标：身体正中上方那一格用 skyeyeG0。
-- 头顶的光环（skyeyeTop）照常播在目标身上。上一行没有可用的格子（目标在最上一行，或那一格站着双格部队，引擎会把图横移半格）时退回整幅的 skyeye。
local EYE_GROUND = { G0 = "aom/atlantean/fx/skyeyeG0.json", GL = "aom/atlantean/fx/skyeyeGL.json", GR = "aom/atlantean/fx/skyeyeGR.json" }
local EYE_TOP = "aom/atlantean/fx/skyeyeTop.json"

local function hexAbove(battle, target)
	local pos = target:getPosition()
	local options
	if target:getHexes():size() > 1 then
		if target:getSide() == ENUM.BattleSide.attacker then options = { { pos:copyToNorthWest(), "G0" } } else options = { { pos:copyToNorthEast(), "G0" } } end
	else
		options = { { pos:copyToNorthWest(), "GL" }, { pos:copyToNorthEast(), "GR" } }
	end
	for _, option in ipairs(options) do
		local hex = option[1]
		if hex:isValid() and hex:getY() == pos:getY() - 1 then
			local occupant = battle:getUnitByPos(hex, false)
			if occupant == nil or occupant:getHexes():size() == 1 then return hex, option[2] end
		end
	end
	return nil
end

local function showEye(server, battle, targets)
	local ground, top, whole = { G0 = {}, GL = {}, GR = {} }, {}, {}
	for _, target in ipairs(targets) do
		local hex, kind = hexAbove(battle, target)
		if hex then
			ground[kind][#ground[kind] + 1] = { hex = hex }
			top[#top + 1] = { unit = target }
		else
			whole[#whole + 1] = { unit = target }
		end
	end
	for kind, list in pairs(ground) do
		if #list > 0 then showAnim(server, battle, list, EYE_GROUND[kind], "", 1.0, true) end
	end
	if #top > 0 then showAnim(server, battle, top, EYE_TOP, "", 1.0, true) end
	if #whole > 0 then showAnim(server, battle, whole, FX.eye, "", 1.0, true) end
end

local function sideIndex(unit)
	return unit:getSide() == ENUM.BattleSide.attacker and 0 or 1
end

local function onLush(battle, unit, key)
	local hexes = unit:getHexes()
	for i = 1, hexes:size() do
		for _, obstacle in ipairs(battle:getObstaclesOnPos(hexes:at(i), false)) do
			local spell = obstacle:getSpell()
			if spell then
				local name = spell:getJsonKey()
				if (name:match("([^:]+)$") or name) == key then return true end
			end
		end
	end
	return false
end

--- 地：留下繁茂地面，并结算站在本方繁茂地面上的部队
function Script:lush(server, battle, unit)
	local key = LUSH_SPELL[sideIndex(unit)]
	local turn = ENUM.BonusDuration.nTurns

	-- 每格一块（引擎只在障碍物的锚点格画一张图，双格单位要放两块）
	local hexes = unit:getHexes()
	for i = 1, hexes:size() do
		local hex = hexes:at(i)
		local covered = false
		for _, obstacle in ipairs(battle:getObstaclesOnPos(hex, false)) do
			local spell = obstacle:getSpell()
			if spell then
				local name = spell:getJsonKey()
				if (name:match("([^:]+)$") or name) == key then covered = true end
			end
		end
		if not covered then
			server:addObstacle(battle, {
				pos = hex, obstacleType = ENUM.ObstacleType.spellCreated, spell = LIBRARY:getSpellByName(key),
				casterSpellPower = 0, spellLevel = 0, casterSide = unit:getSide(), turnsRemaining = 3,
				hidden = false, passable = true, nativeVisible = true, trap = false, removeOnTrigger = false, trigger = "",
				appearSound = "", appearAnimation = LUSH_ANIMATION, animation = LUSH_ANIMATION, removalAnimation = LUSH_FADE, customSize = { hex }
			})
		end
	end

	local side = unit:getSide()
	local percent = god(unit) == GAIA and 15 or 10
	for _, other in ipairs(battle:getUnitsIf(function(u) return u:isAlive() end)) do
		if onLush(battle, other, key) then
			if other:getSide() == side then
				if not other:hasBonuses({ type = LUSH }) then
					local missing = other:getMaxHealth() - other:getFirstHPleft()
					local amount = math.min(missing, math.ceil(other:getMaxHealth() * percent / 100))
					if amount > 0 then server:healUnit(battle, other, amount, ENUM.HealLevel.heal, ENUM.HealPower.permanent) end
					add(server, battle, other, { type = "PRIMARY_SKILL", subtype = "defence", val = 2, duration = turn, turns = 1, hidden = true })
					add(server, battle, other, { type = LUSH, val = 1, valueType = ENUM.BonusValueType.baseNumber, duration = turn, turns = 1 })
				end
			elseif not other:hasBonuses({ type = MIRED }) then
				add(server, battle, other, { type = "STACKS_SPEED", val = -2, duration = turn, turns = 1, hidden = true })
				add(server, battle, other, { type = MIRED, val = 1, valueType = ENUM.BonusValueType.baseNumber, duration = turn, turns = 1 })
			end
		end
	end
end

local USED, SURGE = "AOM_SURGE_USED", "AOM_SURGE"

--- 这一回合多攻击一次，每场一次
function Script:extraAttack(server, battle, unit)
	local turn = ENUM.BonusDuration.nTurns
	add(server, battle, unit, { type = USED, val = 1, valueType = ENUM.BonusValueType.baseNumber, duration = ENUM.BonusDuration.oneBattle, hidden = true })
	add(server, battle, unit, { type = "ADDITIONAL_ATTACK", val = 1, duration = turn, turns = 1, hidden = true })
	add(server, battle, unit, { type = SURGE, val = 1, valueType = ENUM.BonusValueType.baseNumber, duration = turn, turns = 1 })
	server:appendLog(battle, { append = { "core.bonus." .. SURGE .. ".description.900001" }, replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }, replaceNumbers = { 1 } })
end

--- 神代轮转
function Script:season(server, battle, unit, round)
	clear(server, battle, unit, ROUND)
	add(server, battle, unit, { type = ROUND, val = round, valueType = ENUM.BonusValueType.baseNumber, duration = ENUM.BonusDuration.oneBattle, hidden = true })

	if self.aspect == "earth" and unit:isAlive() then self:lush(server, battle, unit) end

	-- 守城提示：第一回合，守城一方带三相脚本的部队里编号最小的那支写一次战报（主神神殿、神话／奇迹时代的守城加成）
	if round == 1 and unit:isAlive() and (not server.describeChanges or server:describeChanges()) then
		local temple, age = unit:hasBonuses({ type = "AOM_SEASON_TEMPLE" }), unit:getBonusesValue({ type = "AOM_AGE_SIEGE" })
		if temple or age > 0 then
			local side, first = unit:getSide(), unit:unitID()
			for _, o in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side and u:getBonusesValue({ type = "AOM_ASPECT" }) > 0 end)) do first = math.min(first, o:unitID()) end
			if first == unit:unitID() then
				if temple then server:appendLog(battle, { append = { "core.bonus.AOM_SEASON_TEMPLE.description.1" } }) end
				if age > 0 then server:appendLog(battle, { append = { "core.bonus.AOM_AGE_SIEGE.description." .. math.min(age, 2) } }) end
			end
		end
	end

	-- 人：军中天、时、地、人四者齐备，每场一次，这一回合多攻击一次（原设计是额外行动，引擎没有这个手段）
	if self.aspect == "man" and unit:isAlive() and not unit:hasBonuses({ type = USED }) then
		local side, seen = unit:getSide(), {}
		for _, other in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side end)) do
			seen[other:getBonusesValue({ type = "AOM_ASPECT" })] = true
		end
		if seen[1] and seen[2] and seen[3] then self:extraAttack(server, battle, unit) end
	end

	local index = ORDER[self.aspect or ""]
	local cmd, own = unit:getBonusesValue({ type = CMD }), GOD_PHASE[god(unit)]
	local lead = cmd >= 2 or unit:hasBonuses({ type = "AOM_SEASON_TEMPLE" })      -- 三相御令高级，或在有主神神殿的城里守城：从主神之相开始
	local start = (lead and own) or 0
	local phase = (round - 1 + start) % 3
	if unit:hasBonuses({ type = HOLD }) then phase = HELD[(round - 1 + (lead and 1 or 0)) % 4] end      -- 停转：天 时 时 地；御令高级从第一个“时”开始
	-- 天穹之父／大地之母（乌拉诺斯、盖亚本人的特长：英雄带隐藏的 AOM_PARENT = 2／3，全军继承）[town_design2]
	-- “天”（或“地”）当令的回合，所有带三相脚本的部队不论哪一相：天 = 幸运 +1、速度 +1；地 = 防御 +2、恢复 5% 生命
	local parent = unit:getBonusesValue({ type = "AOM_PARENT" })
	if unit:isAlive() and parent == 2 and phase == 0 then
		add(server, battle, unit, { type = "LUCK", val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true })
		add(server, battle, unit, { type = "STACKS_SPEED", val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true })
	elseif unit:isAlive() and parent == 3 and phase == 2 then
		add(server, battle, unit, { type = "PRIMARY_SKILL", subtype = "defence", val = 2, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true })
		local missing = unit:getMaxHealth() - unit:getFirstHPleft()
		local amount = math.min(missing, math.ceil(unit:getMaxHealth() * 5 / 100))
		if amount > 0 then server:healUnit(battle, unit, amount, ENUM.HealLevel.heal, ENUM.HealPower.permanent) end
	end
	if self.aspect == "man" and cmd >= 3 then index = own end -- 三相御令专家：英雄形态在主神之相当令时也算当令
	-- 泰坦遗宝（组合宝物，英雄带隐藏的 AOM_RELIC，全军继承）：第一回合天、时、地三相同时当令；当令伤害加成再 +10
	if self.always then index = phase end      -- 三相一体（首都守护者）：每回合都当令
	local relic = unit:getBonusesValue({ type = "AOM_RELIC" }) > 0
	if index == nil or not unit:isAlive() then return end
	if phase ~= index and not (relic and round == 1) then return end

	-- 克洛诺斯泰坦：第一次当令的那一回合多攻击一次（每场一次；原设计是额外行动）
	if self.surgeOnce and not unit:hasBonuses({ type = USED }) then self:extraAttack(server, battle, unit) end

	local turn = ENUM.BonusDuration.nTurns
	add(server, battle, unit, { type = "STACKS_SPEED", val = 2 + unit:getBonusesValue({ type = CMD_SPD }), duration = turn, turns = 1, hidden = true })
	add(server, battle, unit, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeAll", val = (CMD_BOOST[cmd] or 15) + (relic and 10 or 0), duration = turn, turns = 1, hidden = true })
	if unit:getBonusesValue({ type = CMD_MORALE }) > 0 then add(server, battle, unit, { type = "MORALE", val = 1, duration = turn, turns = 1, hidden = true }) end
	add(server, battle, unit, { type = SEASON, val = (CMD_BOOST[cmd] or 15) + (relic and 10 or 0), valueType = ENUM.BonusValueType.baseNumber, duration = turn, turns = 1 })

	-- 当令的画面：这一方同一相的部队里编号最小的那支替大家播一次（每支各播一次会一个接一个排队）
	local animation = SEASON_FX[self.aspect]
	if animation then
		local side, mine, shown, leader = unit:getSide(), unit:getBonusesValue({ type = "AOM_ASPECT" }), {}, unit:unitID()
		for _, other in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side end)) do
			if other:getBonusesValue({ type = "AOM_ASPECT" }) == mine then
				shown[#shown + 1] = { unit = other }
				leader = math.min(leader, other:unitID())
			end
		end
		if leader == unit:unitID() then
			local note = ({ sky = 1, time = 2, earth = 3 })[self.aspect]      -- 战报：本回合哪一相当令
			if note and (not server.describeChanges or server:describeChanges()) then
				server:appendLog(battle, { append = { "core.bonus." .. SEASON .. ".description." .. (900000 + note) }, replaceNumbers = { (CMD_BOOST[cmd] or 15) + (relic and 10 or 0) } })
			end
			showAnim(server, battle, shown, animation, "", 1.0, true)
			if cmd > 0 then showAnim(server, battle, shown, FX.seasonCmd, "", 1.0, true) end      -- 三相御令：当令时再落一道时光光柱
			server:refreshBattleUnits(battle)
		end
	end
end

function Script:onBattleStart(server, battle, unit, other)
	self:season(server, battle, unit, 1)
end

function Script:onRoundStart(server, battle, unit, other)
	self:season(server, battle, unit, unit:getBonusesValue({ type = ROUND }) + 1)
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

	local once = ENUM.BonusDuration.untilOwnAttack
	local eye = target:hasBonuses({ type = SKYEYE })
	local lag = target:hasBonuses({ type = TIMELAG })

	if eye then
		add(server, battle, unit, { type = "NO_DISTANCE_PENALTY", duration = once, hidden = true })
		add(server, battle, unit, { type = "NO_WALL_PENALTY", duration = once, hidden = true })
		add(server, battle, unit, { type = "LUCK", val = 1, duration = once, hidden = true })
		if self.aspect == "man" then
			add(server, battle, unit, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeAll", val = 100, duration = once, hidden = true })
		end
	end
	if self.aspect == "man" and unit:hasBonuses({ type = LUSH }) then
		add(server, battle, unit, { type = "PRIMARY_SKILL", subtype = "attack", val = 3, duration = once, hidden = true })
	end
	if eye and lag then
		add(server, battle, unit, { type = "ENEMY_DEFENCE_REDUCTION", val = 30, duration = once, hidden = true })
		if (not server.describeChanges or server:describeChanges()) then      -- 战报：天时
			server:appendLog(battle, { append = { "core.bonus." .. SKYEYE .. ".description.900001" }, replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }, replaceNumbers = { 30 } })
		end
	end
end

local function logLine(server, battle, key, unit, number)
	server:appendLog(battle, {
		append         = { key },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) },
		replaceNumbers = { number or 0 }
	})
end

function Script:addLag(server, battle, target, limit)
	if target:hasBonuses({ type = "AOM_LAG_REST" }) then return nil end      -- 定格过的部队 2 回合内不再受时滞
	if target:hasBonuses({ type = LUSH }) then return nil end          -- 地利：站在本方繁茂地面上免疫时滞和定格
	local layers = target:getBonusesValue({ type = TIMELAG })
	local turn = ENUM.BonusDuration.nTurns

	limit = limit or MAX_LAG
	if layers + 1 >= limit then
		clear(server, battle, target, TIMELAG)
		add(server, battle, target, { type = "NOT_ACTIVE", duration = turn, turns = 1, hidden = true })
		add(server, battle, target, { type = FROZEN, val = 1, valueType = ENUM.BonusValueType.baseNumber, duration = turn, turns = 1 })
		add(server, battle, target, { type = "AOM_LAG_REST", val = 1, duration = turn, turns = 3, hidden = true })
		logLine(server, battle, "core.bonus." .. FROZEN .. ".description.900001", target, limit)
		return "frozen"
	end

	add(server, battle, target, { type = TIMELAG, val = 1, duration = turn, turns = 3 }, true)
	add(server, battle, target, { type = "STACKS_SPEED", val = -1, duration = turn, turns = 3, hidden = true }, true)
	return "lag"
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if payload and payload.isCounter then return end
	local side = unit:getSide()
	local changed = false
	local patron = god(unit)
	local limit = patron == KRONOS and 2 or MAX_LAG
	local shown = { eye = {}, lag = {}, frozen = {} }

	for _, entry in ipairs(payload and payload.targets or {}) do
		local target = entry.unit
		if target and target:isAlive() and target:getSide() ~= side and (entry.damage or 0) > 0 and not target:hasBonuses({ type = FROZEN }) then
			if self.aspect == "sky" then
				clear(server, battle, target, SKYEYE)
				add(server, battle, target, { type = SKYEYE, val = 1, valueType = ENUM.BonusValueType.baseNumber, duration = ENUM.BonusDuration.nTurns, turns = patron == ORANOS and 3 or 2 })
				shown.eye[#shown.eye + 1] = target
				changed = true
			elseif self.aspect == "time" or (self.aspect == "man" and target:hasBonuses({ type = TIMELAG })) then
				-- 时滞看分量：这一下的伤害不到目标整队生命（打之前）的 3% 就不叠层，免得 1 个兵也能定格一整队（审计 N6）
				local left = (target:getCount() - 1) * target:getMaxHealth() + target:getFirstHPleft()
				local what = (entry.damage * 100 >= (left + entry.damage) * 3) and self:addLag(server, battle, target, limit) or nil
				if what then
					shown[what][#shown[what] + 1] = { unit = target }
					changed = true
				end
			end
		end
	end

	-- 每种状态一次播给全部目标，最后刷新一次
	if changed then
		if #shown.eye > 0 then showEye(server, battle, shown.eye) end
		for _, what in ipairs({ "lag", "frozen" }) do
			if #shown[what] > 0 then showAnim(server, battle, shown[what], FX[what], "", 1.0, true) end
		end
		server:refreshBattleUnits(battle)
	end
end

return Script
