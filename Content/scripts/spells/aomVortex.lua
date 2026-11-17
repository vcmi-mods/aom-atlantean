-- 旋涡传送：把己方离目标格最近的 count 队部队瞬间传到目标格周围（各落在离目标格最近的空格）。
-- 主神亲和（gods）多传 1 队；神力回响触发时再多传 1 队。战争器械、箭塔不传。
-- 配置：{"type": "aomVortex", "count": 2, "gods": [1, 2], "animation": "落点动画"}
local Base = require("spells/spellEffect")
local God = require("spells/aomGod")
local Echo = require("spells/aomEchoCommon")
local P = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- 动画只在真打的时候放：电脑试算（describeChanges 为假）时发动画包，引擎每次报 "BattleAnimationPlayed is not allowed in battle evaluation"
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

local function movable(mechanics)
	local battle, side, color = mechanics:getBattle(), mechanics:getCasterSide(), mechanics:getCasterColor()
	return battle:getUnitsIf(function(u)
		if not u:isAlive() or u:getSide() ~= side or u:isTurret() or u:isGhost() then return false end
		if battle:getUnitController(u) ~= color then return false end
		if u:hasBonuses({ type = "SIEGE_WEAPON" }) then return false end
		return true
	end)
end

function Script:applicableGeneral(mechanics, problem)
	if #movable(mechanics) == 0 then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
		return false
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target)
	if #target == 0 or not target[1].hex or not target[1].hex:isValid() or not target[1].hex:isAvailable() then
		problem:addStandard(mechanics, ENUM.SpellCastProblem.wrongSpellTarget)
		return false
	end
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	if #aimPoint > 0 then return { aimPoint[1] } end
	return spellTarget
end

function Script:apply(mechanics, server, target)
	if #target == 0 or not target[1].hex then return end
	local battle, centre = mechanics:getBattle(), target[1].hex
	local n = self.count or 2
	if God.favoured(self, mechanics) then n = n + 1 end
	local units = movable(mechanics)
	table.sort(units, function(a, b)
		local da, db = God.distance(a:getPosition(), centre), God.distance(b:getPosition(), centre)
		if da ~= db then return da < db end
		return a:unitID() < b:unitID()
	end)
	-- 电脑试算（整合检查清单：会让部队换位的法术，试算时只报等效价值、不真改战场）：
	-- 被卷过去的近战部队里，原本这一回合走不到目标格旁边敌军的，每队按“多打出的一下 × 0.6”记到那支敌军上；
	-- 会把还有弹药的射手卷到敌人脸上、或者目标格旁边没有敌军时不报。
	if P.trial(server) then
		local near, nd = nil, 99
		for _, e in ipairs(battle:getUnitsIf(function(x) return x:isAlive() and not x:isGhost() and not x:isTurret() and x:getSide() ~= mechanics:getCasterSide() end)) do
			local d = P.unitDistance(e, centre)
			if d < nd then near, nd = e, d end
		end
		if near == nil or nd > 2 then return end
		local gain = 0
		for i = 1, math.min(n, #units) do
			local u = units[i]
			if u:isShooter() then return end
			if P.unitsDistance(u, near) - 1 > u:getBonusesValue({ type = "STACKS_SPEED" }) then
				gain = gain + P.attackEstimate(u, near, 100, false) * 0.6
			end
		end
		P.damage(server, battle, near, gain)
		return
	end
	if #units > n and Echo.roll(mechanics, server) then n = n + 1 end
	local order, moved = God.hexesByDistance(battle, centre), 0
	for i = 1, math.min(n, #units) do
		local unit, here = units[i], God.distance(units[i]:getPosition(), centre)
		for _, cand in ipairs(order) do
			if cand.d >= here then break end      -- 已经比能去的空格更近，就不动
			if battle:isAccessibleForUnit(unit, cand.hex) then
				server:moveUnit(battle, unit, cand.hex, true)
				if self.animation then showAnim(server, battle, { { unit = unit } }, self.animation, "", 1.0, true) end
				moved = moved + 1
				break
			end
		end
	end
	if moved > 0 then server:refreshBattleUnits(battle) end
end

return Script
