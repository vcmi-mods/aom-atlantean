-- 电脑试算用的“代理价值”（整合检查清单“AI 与战力数值”）：盖亚之林、蛛穴陷阱这类只放障碍物的神力，
-- 电脑（BattleAI）在假想战场上试一遍后前后价值没变，估值是 0，所以从来不放。
-- 本效果和原效果并列挂在法术的 battleEffects 里（"optional": true）：
--   正式施放（server:describeChanges() 为真）什么都不做，玩家和电脑实际得到的效果完全不变；
--   只在电脑试算时（为假）把“这一招大概值多少”折成对敌军的等效扣血报给电脑，试算里的改动不会留到真战场。
-- 配置：
--   {"type": "aomAiProxy", "optional": true, "mode": "wall", "radius": 3, "ratio": 0.06, "max": 2}
--       拦路的障碍（盖亚之林）：目标格 radius 步内、正朝我方走来的敌方地面近战部队，每队报 剩余总生命 × ratio（约等于耽误它一回合的一半），
--       最多 max 队。我方没有能射击的部队、目标格旁边有我方近战部队（会把自己人也挡住）、战场上已经有本法术的障碍时不报。
--   {"type": "aomAiProxy", "optional": true, "mode": "trap", "bite": "aom-atlantean:aomSpiderBite", "factor": 0.5, "max": 2}
--       随机埋的陷阱（蛛穴陷阱）：对最多 max 队敌方地面部队各报 陷阱伤害 × factor；战场上已经有本法术的陷阱时不报，免得每回合重复埋。
local Base = require("spells/spellEffect")
local P = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:applicableGeneral(mechanics, problem) return true end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	if #aimPoint > 0 then return { aimPoint[1] } end
	return spellTarget
end

local function alreadyThere(mechanics, battle)
	local key = mechanics:getSpell():getJsonKey()
	for _, o in ipairs(battle:getAllObstacles()) do
		local ok, sp = pcall(function() return o:getSpell():getJsonKey() end)
		if ok and sp == key then return true end
	end
	return false
end

local function walker(u)
	return not u:hasBonuses({ type = "FLYING" }) and not u:hasBonuses({ type = "SIEGE_WEAPON" })
end

local function foes(battle, side, pred)
	return battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and u:getSide() ~= side and (pred == nil or pred(u))
	end)
end

local function own(battle, side, pred)
	return battle:getUnitsIf(function(u)
		return u:isAlive() and not u:isGhost() and not u:isTurret() and u:getSide() == side and (pred == nil or pred(u))
	end)
end

function Script:wall(mechanics, server, battle, side, hex)
	if hex == nil or not hex:isValid() then return end
	local shooters = own(battle, side, function(u) return u:isShooter() and not u:hasBonuses({ type = "SIEGE_WEAPON" }) end)
	if #shooters == 0 then return end
	local radius = self.radius or 2
	-- 自己人也要从这里过（近战、地面、就在旁边）就不放
	if #own(battle, side, function(u) return not u:isShooter() and walker(u) and P.unitDistance(u, hex) <= radius end) > 0 then return end
	-- 我方射手在哪一边：障碍要落在敌人和射手之间
	local sx = 0
	for _, u in ipairs(shooters) do sx = sx + u:getPosition():getX() end
	sx = sx / #shooters
	local list = foes(battle, side, function(u)
		if u:isShooter() or not walker(u) then return false end
		local d = P.unitDistance(u, hex)
		if d < 1 or d > radius then return false end
		local ex, hx = u:getPosition():getX(), hex:getX()
		return (sx < ex and hx < ex and hx > sx) or (sx > ex and hx > ex and hx < sx)
	end)
	table.sort(list, function(a, b) return a:getAvailableHealth() * P.value(a) / a:getMaxHealth() > b:getAvailableHealth() * P.value(b) / b:getMaxHealth() end)
	for i = 1, math.min(self.max or 2, #list) do
		P.damage(server, battle, list[i], list[i]:getAvailableHealth() * (self.ratio or 0.06))
	end
end

function Script:trap(mechanics, server, battle, side)
	local ok, bite = pcall(function() return LIBRARY:getSpellByName(self.bite) end)
	if not ok or bite == nil then return end
	local raw = bite:getBasePower() * mechanics:getEffectPower() + bite:getLevelPower(mechanics:getEffectLevel())
	local hp = raw * (self.factor or 0.5)
	local list = foes(battle, side, function(u) return walker(u) and not u:isShooter() end)
	table.sort(list, function(a, b) return a:getAvailableHealth() > b:getAvailableHealth() end)
	for i = 1, math.min(self.max or 2, #list) do
		P.damage(server, battle, list[i], hp)
	end
end

function Script:apply(mechanics, server, target)
	if not P.trial(server) then return end      -- 正式施放：什么都不做
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	if alreadyThere(mechanics, battle) then return end
	if self.mode == "wall" then
		self:wall(mechanics, server, battle, side, target[1] and target[1].hex)
	elseif self.mode == "trap" then
		self:trap(mechanics, server, battle, side)
	end
end

return Script
