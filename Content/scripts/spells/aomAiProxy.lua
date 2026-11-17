-- Proxy value for AI evaluation: god powers that only place obstacles (Gaia's Forest, Spider Lair)
-- show no value change when the AI (BattleAI) tries them on its imaginary battlefield, are valued at 0 and never cast.
-- This effect sits next to the real effects in the spell's battleEffects ("optional": true):
--   real casts (server:describeChanges() true) do nothing here, so what players and AI actually get is unchanged;
--   only in AI evaluation (false) is "what this is worth" reported as equivalent damage to enemies; evaluation changes never reach the real battlefield.
-- Config:
--   {"type": "aomAiProxy", "optional": true, "mode": "wall", "radius": 3, "ratio": 0.06, "max": 2}
--       blocking obstacle (Gaia's Forest): for enemy ground melee units within radius of the target hex that are moving toward us, report remaining health x ratio each (about half of delaying them a round),
--       at most max stacks. Nothing is reported if we have no shooters, an own melee unit is next to the target hex (it would block our own), or this spell's obstacle is already on the battlefield.
--   {"type": "aomAiProxy", "optional": true, "mode": "trap", "bite": "aom-atlantean:aomSpiderBite", "factor": 0.5, "max": 2}
--       random traps (Spider Lair): report trap damage x factor for up to max enemy ground stacks; nothing if this spell's trap is already on the battlefield, so it is not laid every round.
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
	-- don't cast if own units must pass here too (melee, ground, right next to it)
	if #own(battle, side, function(u) return not u:isShooter() and walker(u) and P.unitDistance(u, hex) <= radius end) > 0 then return end
	-- which side our shooters are on: the obstacle should fall between enemies and shooters
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
	if not P.trial(server) then return end      -- real cast: do nothing
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	if alreadyThere(mechanics, battle) then return end
	if self.mode == "wall" then
		self:wall(mechanics, server, battle, side, target[1] and target[1].hex)
	elseif self.mode == "trap" then
		self:trap(mechanics, server, battle, side)
	end
end

return Script
