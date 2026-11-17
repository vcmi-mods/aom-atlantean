--- kadAiProxy：电脑试算分支共用的小工具（第344轮，ai-skills-design）
---
--- 电脑（BattleAI / MMAI，也包括野怪和玩家的自动战斗）决定要不要放技能时，会在假想战场上把法术效果执行一遍
--- （这时 server:describeChanges() 为假），再比较前后各部队的战斗价值。挪位置、障碍物、自定义标记、战斗脚本
--- 在那里都值 0，伤到己方一票否决。试算分支：describeChanges() 为假时不走原效果，改成“对敌扣血 / 原生加成”
--- 这类电脑认得的等效变化（代理价值），然后 return。正式施放（describeChanges() 为真）照旧走原效果，
--- 玩家看到的效果、说明都不变。
---
--- 代理价值统一折成“对目标的等效扣血（生命点）”：对一支部队扣 D 点，电脑眼里的价值约降 单只价值 × D / 单只生命，
--- 和它给普通攻击打分的量纲相同，所以能直接和“直接打”比较。
---
--- 同名文件放在每个用到它的 mod 里（scripts/lib/kadAiProxy.lua），全合集内容必须逐字一致（同名脚本规矩），
--- 不新增依赖。只能在主动技能法术的 apply 里用试算分支；障碍物触发法术、战斗脚本里不要用
--- （电脑估算障碍物伤害时也会试算触发法术）。P.isAi 可以在战斗脚本里用。

local P = {}
P.VERSION = 1

--- 是不是电脑试算
function P.trial(server)
	return not server:describeChanges()
end

--- 单只价值：兵种 json 的 aiValue（只读来做比例，不改它），最少 1
function P.value(u)
	local ok, v = pcall(function() return u:getCreature():getAIValue() end)
	if ok and type(v) == "number" and v > 0 then return v end
	return 1
end

--- 价值 → 目标 t 的生命点
function P.hpOf(value, t)
	return value / P.value(t) * t:getMaxHealth()
end

--- 失去 count 只 lost 兵种的价值，折成目标 t 的生命点（伤己方的代价）
function P.costHp(lost, count, t)
	return P.hpOf(P.value(lost) * count, t)
end

--- 免疫（四种：法术、学派、负面、等级）；无敌也算。o = { spell = "mod:key", school = "water", negative = true, level = 1..5 }
function P.immune(u, o)
	o = o or {}
	if u:isInvincible() then return true end
	if o.spell then
		local short = string.gsub(o.spell, "^.*:", "")
		if u:hasBonuses({ type = "SPELL_IMMUNITY", subtype = short }) then return true end
		local ok, r = pcall(function() return u:hasBonuses({ type = "SPELL_IMMUNITY", subtype = o.spell }) end)
		if ok and r then return true end
	end
	if o.school then
		if u:hasBonuses({ type = "SPELL_SCHOOL_IMMUNITY", subtype = o.school }) then return true end
		if u:hasBonuses({ type = "SPELL_SCHOOL_IMMUNITY", subtype = "any" }) then return true end
		if o.negative and u:hasBonuses({ type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = o.school }) then return true end
	end
	if o.negative and u:hasBonuses({ type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "any" }) then return true end
	if o.level and u:getBonusesValue({ type = "LEVEL_SPELL_IMMUNITY" }) >= o.level then return true end
	return false
end

--- actor 眼中能挨打的敌军
function P.hostile(battle, actor, u)
	return u ~= nil and u:isAlive() and not u:isGhost() and not u:isTurret() and battle:isHostile(actor, u)
end

--- 代理扣血：免疫或不足 1 点不扣，不超过剩余生命。返回扣了多少
function P.damage(server, battle, t, hp, o)
	hp = math.floor(hp or 0)
	if t == nil or not t:isAlive() or t:isGhost() or hp < 1 or P.immune(t, o) then return 0 end
	hp = math.min(hp, t:getAvailableHealth())
	server:damageUnit(battle, t, hp)
	return hp
end

--- 给己方的代理增益（F5）：挂原生加成，引擎自己估值。d 是加成描述，缺省来源 other、隐藏
function P.buff(server, battle, u, d)
	if u == nil or not u:isAlive() then return end
	d.sourceType = d.sourceType or ENUM.BonusSource.other
	if d.hidden == nil then d.hidden = true end
	if d.turns and not d.duration then d.duration = ENUM.BonusDuration.nTurns end
	server:addUnitBonus(battle, u, d, true)
end

--- 控制类（F4）：废掉 turns 个回合计数，折成目标总生命的比例 min(turns, 8)/8 × 严重度
function P.controlRatio(turns, severity)
	return math.min(math.max(turns or 1, 0), 8) / 8 * (severity or 1)
end

--- 一次普通攻击的期望伤害（不掷骰）：兵数 × 平均伤害 × 攻防系数（3 代公式）× pct%
function P.attackEstimate(attacker, target, pct, ranged)
	if attacker == nil or target == nil then return 0 end
	ranged = ranged or false
	local lo = attacker:getMinDamage(ranged)
	local hi = math.max(lo, attacker:getMaxDamage(ranged))
	local diff = attacker:getAttack(ranged) - target:getDefense(ranged)
	local f
	if diff > 0 then f = 1 + 0.05 * math.min(diff, 60) else f = 1 - 0.025 * math.min(-diff, 28) end
	return attacker:getCount() * (lo + hi) / 2 * f * (pct or 100) / 100
end

--- 两格距离（六边形）
function P.hexDistance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1 = a:getX() + math.floor(y1 / 2)
	local x2 = b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then return math.max(math.abs(dx), math.abs(dy)) end
	return math.abs(dx) + math.abs(dy)
end

--- 部队任一格到 hex 的最近距离
function P.unitDistance(u, hex)
	local best = 99
	local hs = u:getHexes()
	for i = 1, hs:size() do best = math.min(best, P.hexDistance(hs:at(i), hex)) end
	return best
end

--- 两支部队之间的最近距离（1 = 相邻）
function P.unitsDistance(a, b)
	local best = 99
	local hs = a:getHexes()
	for i = 1, hs:size() do best = math.min(best, P.unitDistance(b, hs:at(i))) end
	return best
end

--- 中心格 radius 以内的敌军（相对 actor）
function P.hostilesNear(battle, actor, center, radius)
	return battle:getUnitsIf(function(u)
		return P.hostile(battle, actor, u) and P.unitDistance(u, center) <= radius
	end)
end

--- 和 unit 相邻、满足 pred 的部队
function P.adjacent(battle, unit, pred)
	return battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and u:unitID() ~= unit:unitID() and P.unitsDistance(u, unit) == 1
			and (pred == nil or pred(u))
	end)
end

--- 射手（有弹药）
function P.shooter(u)
	return u:isShooter()
end

--- 离 unit 最近的敌军
function P.nearestHostile(battle, unit)
	local best, bd = nil, 99
	for _, u in ipairs(battle:getUnitsIf(function(x) return P.hostile(battle, unit, x) end)) do
		local d = P.unitsDistance(unit, u)
		if d < bd then best, bd = u, d end
	end
	return best, bd
end

--- 一方的总价值（Σ 单只价值 × 只数）
function P.armyValue(battle, pred)
	local total = 0
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isTurret() and pred(x) end)) do
		total = total + P.value(u) * u:getCount()
	end
	return total
end

--- actor 一方是否胜势：己方 / 敌方价值 ≥ ratio（默认 1.5）
function P.winning(battle, actor, ratio)
	local own = P.armyValue(battle, function(x) return not battle:isHostile(actor, x) end)
	local foe = P.armyValue(battle, function(x) return battle:isHostile(actor, x) end)
	return foe <= 0 or own >= foe * (ratio or 1.5)
end

--- 按战场一方（英雄施法没有施法部队时用）：side 一方是否胜势（己方 / 对方价值 ≥ ratio，默认 1.5）
function P.winningSide(battle, side, ratio)
	local own = P.armyValue(battle, function(x) return x:getSide() == side end)
	local foe = P.armyValue(battle, function(x) return x:getSide() ~= side end)
	return foe <= 0 or own >= foe * (ratio or 1.5)
end

--- 按战场一方记账：价值记到 side 对面生命最多的一支上
function P.creditSide(server, battle, side, value)
	if value == nil or value <= 0 then return 0 end
	local best = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isGhost() and not x:isTurret() and x:getSide() ~= side end)) do
		if best == nil or u:getAvailableHealth() > best:getAvailableHealth() then best = u end
	end
	if best == nil then return 0 end
	return P.damage(server, battle, best, math.min(P.hpOf(value, best), best:getAvailableHealth() * 0.5))
end

--- 记账（F10）：价值 value 记到 actor 的敌军里总生命最多的一支上（不会被打死，不扭曲别的判断）
function P.credit(server, battle, actor, value)
	if value == nil or value <= 0 then return 0 end
	local best = nil
	for _, u in ipairs(battle:getUnitsIf(function(x) return P.hostile(battle, actor, x) end)) do
		if best == nil or u:getAvailableHealth() > best:getAvailableHealth() then best = u end
	end
	if best == nil then return 0 end
	return P.damage(server, battle, best, math.min(P.hpOf(value, best), best:getAvailableHealth() * 0.5))
end

--- 弱技能上限：不超过 0.8 × 施法者对最近敌军一次攻击的期望伤害（折成目标 t 的生命）。打得到敌人时永远选攻击
function P.capWeak(hp, battle, caster, t)
	local e = P.nearestHostile(battle, caster)
	if e == nil then return hp end
	local atk = P.attackEstimate(caster, e, 100, caster:isShooter())
	local capHp = P.hpOf(atk / e:getMaxHealth() * P.value(e), t) * 0.8
	return math.min(hp, capHp)
end

--- 本回合能打到 unit 的敌军对它的期望伤害之和（射手全算，近战按“距离 - 1 ≤ 速度”算）
function P.threat(battle, unit)
	local total = 0
	for _, e in ipairs(battle:getUnitsIf(function(x) return P.hostile(battle, unit, x) end)) do
		local ok, speed = pcall(function() return e:getBonusesValue({ type = "STACKS_SPEED" }) end)
		if not ok or type(speed) ~= "number" then speed = 0 end
		if e:isShooter() then
			total = total + P.attackEstimate(e, unit, 100, true)
		elseif P.unitsDistance(e, unit) - 1 <= speed then
			total = total + P.attackEstimate(e, unit, 100, false)
		end
	end
	return total
end

--- 控制方是不是电脑：人类控制返回假；中立（无玩家）按电脑；接口出错一律按人类（什么都不做，对玩家无影响）
local function notHuman(color)
	local ok, r = pcall(function() return GAME:playerIsHuman(color) end)
	return ok and r == false
end

--- 部队当前控制方是不是电脑（考虑催眠）
function P.isAi(battle, unit)
	local ok, color = pcall(function() return battle:getUnitController(unit) end)
	return ok and notHuman(color)
end

--- 施法方是不是电脑
function P.aiCaster(mechanics)
	local ok, color = pcall(function() return mechanics:getCasterColor() end)
	return ok and notHuman(color)
end

-- 第344轮：精确撤加成（mark-fix）。引擎撤加成（BattleInfo::removeUnitBonus）只比“持续方式、类型、子类型、来源、
-- 数值、来源编号、数值类型、作用范围”八项，不比叠加组（stacking）和剩余回合：撤一条会把部队身上八项都相同的
-- 其他加成（别的叠加组、别的脚本挂的）一起撤掉。来源是“其他”时来源编号一律为空（写了 sourceID 也被引擎丢掉）。
-- 这里先数一遍会被连带撤掉的加成，撤完把真的少了的按原样补回（叠加组、剩余回合、隐藏不变）。
-- 说明文字、图标、限制器引擎不给脚本读，补不回：带说明的显示加成要靠独有的来源 / 数值避开（见整合检查清单）。
-- 只补来源为“其他”或“生物能力”的加成；法术效果等别的来源同八项就是同一法术，照引擎原样撤。
-- 用法：把 server:removeUnitBonuses(battle, unit, list) 换成 P.removeExact(server, battle, unit, list)。
local function exactKey(b)
	local dur = 0
	for _, d in ipairs(b:getDuration() or {}) do dur = dur + d end
	return table.concat({ b:getType(), b:getSubtype(), tostring(b:getSource()), b:getSourceID(), b:getVal(),
		tostring(b:getValType()), tostring(b:getEffectRange()), dur }, "|"), dur
end

-- 补回时的子类型：引擎读出的名字（"fire"、"defence"、"any"）能原样写回；自定义子类型读出来是数字，
-- -1 就是“没有子类型”（= damageTypeAll），伤害类的 0 / 1 写回名字，其余数字原样写（引擎认数字，只在日志里提醒一句）
local DAMAGE_SUB = { ["0"] = "damageTypeMelee", ["1"] = "damageTypeRanged" }
local DAMAGE_TYPES = { GENERAL_DAMAGE_REDUCTION = true, PERCENTAGE_DAMAGE_BOOST = true, FIRST_STRIKE = true }
local function restoreSubtype(b)
	local sub = b:getSubtype()
	if sub == nil or sub == "" or sub == "none" or sub == "-1" then return nil end
	local n = tonumber(sub)
	if n == nil then return sub end
	if DAMAGE_TYPES[b:getType()] and DAMAGE_SUB[sub] then return DAMAGE_SUB[sub] end
	return n
end

local RESTORABLE = { [ENUM.BonusSource.other] = true, [ENUM.BonusSource.creatureAbility] = true }

-- 部队身上同八项、不在 list 里的加成（按 叠加组 + 剩余回合 计数）
local function bystanders(unit, list)
	local keys, types, inList = {}, {}, {}
	for i = 1, list:size() do
		local b = list:getBonus(i)
		local k = exactKey(b)
		keys[k] = true
		inList[k .. "#" .. b:getStacking()] = true
		types[b:getType()] = true
	end
	local found = {}
	for t in pairs(types) do
		local all = unit:getBonuses({ type = t })
		for i = 1, all:size() do
			local b = all:getBonus(i)
			local k, dur = exactKey(b)
			if keys[k] and not inList[k .. "#" .. b:getStacking()] and RESTORABLE[b:getSource()] then
				local id = k .. "#" .. b:getStacking() .. "#" .. b:getTurnsRemain()
				local e = found[id]
				if e == nil then
					e = { n = 0, d = {
						type = b:getType(), val = b:getVal(), valueType = b:getValType(), effectRange = b:getEffectRange(),
						duration = dur, sourceType = b:getSource(), stacking = b:getStacking(), hidden = b:isHidden() } }
					local sub = restoreSubtype(b)
					if sub ~= nil then e.d.subtype = sub end
					if b:getSource() == ENUM.BonusSource.creatureAbility then e.d.sourceID = b:getSourceID() end
					if b:getTurnsRemain() > 0 then e.d.turns = b:getTurnsRemain() end
					found[id] = e
				end
				e.n = e.n + 1
			end
		end
	end
	return found
end

function P.removeExact(server, battle, unit, list)
	if unit == nil or list == nil or list:size() == 0 then return end
	local before = bystanders(unit, list)
	server:removeUnitBonuses(battle, unit, list)
	if next(before) == nil then return end
	local after = bystanders(unit, list)
	for id, e in pairs(before) do
		local left = after[id] and after[id].n or 0
		for _ = left + 1, e.n do
			local d = {}
			for k, v in pairs(e.d) do d[k] = v end
			server:addUnitBonus(battle, unit, d, true)
		end
	end
end

return P
