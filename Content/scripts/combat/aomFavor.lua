-- Favor: a hero specialty style shared by all Age of Mythology towns (Atlantean version).
-- Set up as a COMBAT_EVENT_TRIGGER in the hero specialty (inherited by the whole army), addInfo:
--   creatures  the hero's specialty creatures (identifiers of every form)
--   patron     minor god (for the 6-point minor blessing), optional
--   god        major god of the hero class: "kronos", "oranos", "gaia" (for the 10-point god power)
-- val = Favor gained at the start of each round.
--
-- Favor is counted per side: the script fires once per unit, so two hidden counters tell whether this side was already settled this round -
--   AOM_FAVOR_SEEN  rounds this unit has seen; AOM_FAVOR_TICK  round this side has been settled up to.
-- The first unit of a side that finds "own round count > settled round" settles; the rest skip.
-- Favor and the tiers already reached are stored on every unit of this side that has the script, so nothing is lost when a unit dies; the Favor value is visible on every non-war-machine stack
-- (earlier it was only on the specialty creatures). War machines do not get this script (limiter in the specialty).
-- Battle log: one line per round "Favor N, next tier at M" (stops once all three tiers are reached); when a blessing fires, the concrete effect of the patron or major god is written,
-- and army-wide effects are not described as given to one stack.
--
-- Three blessing tiers (once each per battle, automatic, same for players and AI):
--   3 points  Divinity: specialty creatures ignore 15% of the target's Defense for 2 rounds
--   6 points  minor blessing: by patron (e.g. Leto: specialty creatures repaired to full health)
--   10 points god power: by god (Kronos: +1 Time Lag on every enemy; Gaia: Lush Ground under all own troops; Oranos: shockwave)
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local FAVOR, SEEN, TICK, TIER, DIVINE = "AOM_FAVOR", "AOM_FAVOR_SEEN", "AOM_FAVOR_TICK", "AOM_FAVOR_TIER", "AOM_DIVINITY"
local FAVOR_FX = "aom/atlantean/fx/favor.json"      -- golden light pillar of a blessing (previously borrowed the Bless / Prayer animations)
local THRESHOLD = { 2, 4, 7 }      -- 3/6/10 before the 2026-11-14 audit: the later two rarely came up in a normal battle
local PATRON_LOG = { leto = 21, atlas = 22, krios = 23, hyperion = 24, helios = 25, oceanus = 26, kastor = 27 }
local GOD_LOG = { kronos = 31, oranos = 32, gaia = 33 }

-- Animations only in real battles: sending animation packs during AI evaluation (describeChanges false) makes the engine log "BattleAnimationPlayed is not allowed in battle evaluation" every time
local function real(server) return not server.describeChanges or server:describeChanges() end
local function showAnim(server, ...)
	if not real(server) then return end
	server:showBattleAnimation(...)
end
local function isSiege(u) return u:hasBonuses({ type = "SIEGE_WEAPON" }) end

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
	-- shrunk / downgraded copies from other mods (kadMini_aom_atlantean_<creature> etc.) count as the original creature
	return key:match("^kad%a+_aom_atlantean_(.+)$") or key
end

function Script:isFavored(unit)
	local key = shortKey(unit)
	for _, id in ipairs(self.creatures or {}) do
		if id == key then return true end
	end
	return false
end

--- all living units of this side that carry this script
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
	-- blessings still trigger after all specialty creatures are dead: the ones that only affect specialty creatures then have no target and do nothing;
	-- those affecting the whole army or the enemy (Oceanus' tide, the three god powers) still work.
	if #units == 0 then return end
	local wholeArmy = tier == 3 or (tier == 2 and self.patron == "oceanus")
	-- specialty creatures absent (not brought or all dead): the two specialty-only tiers go to the own stack with the most total health (audit P2)
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
		elseif self.patron == "atlas" then          -- Titan's Burden: -50% damage taken this round
			for _, u in ipairs(favored) do buff(server, battle, u, { type = "GENERAL_DAMAGE_REDUCTION", subtype = "damageTypeAll", val = 50, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true }) end
			showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "krios" then          -- Star Guide: one extra attack this round
			for _, u in ipairs(favored) do buff(server, battle, u, { type = "ADDITIONAL_ATTACK", val = 1, duration = ENUM.BonusDuration.nTurns, turns = 1, hidden = true }) end
			showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "hyperion" then       -- Radiance: charge filled at once (the same two bonuses aomCharge.lua adds when charged)
			for _, u in ipairs(favored) do
				if not u:hasBonuses({ type = "AOM_CHARGE_READY" }) then
					buff(server, battle, u, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeMelee", val = 200, duration = ENUM.BonusDuration.untilOwnAttack, hidden = true })
					buff(server, battle, u, { type = "AOM_CHARGE_READY", val = 200, valueType = ENUM.BonusValueType.baseNumber, duration = ENUM.BonusDuration.untilOwnAttack })
				end
			end
			showAnim(server, battle, targets, FAVOR_FX, "PRAYER", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "helios" then         -- Blazing Sun: +25% damage for 2 rounds
			for _, u in ipairs(favored) do buff(server, battle, u, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeAll", val = 25, duration = ENUM.BonusDuration.nTurns, turns = 2, hidden = true }) end
			showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
		elseif self.patron == "oceanus" then        -- Tide: all own living troops regain 20% health
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
		elseif self.patron == "kastor" then         -- Heroic Will: +4 Attack and Defense for 2 rounds
			for _, u in ipairs(favored) do
				buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "attack", val = 4, duration = ENUM.BonusDuration.nTurns, turns = 2, hidden = true })
				buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "defence", val = 4, duration = ENUM.BonusDuration.nTurns, turns = 2, hidden = true })
			end
			showAnim(server, battle, targets, FAVOR_FX, "BLESS", 1.0, true) server:refreshBattleUnits(battle)
		else
			return
		end
	else
		-- god power (once per battle): Kronos = +1 Time Lag on every enemy; Gaia = Lush Ground under all own troops; Oranos = shockwave
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
		elseif self.god == "oranos" then            -- Shockwave: all enemies -2 Speed for 2 rounds [town_design2]
			for _, enemy in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() ~= side end)) do
				buff(server, battle, enemy, { type = "STACKS_SPEED", val = -2, duration = ENUM.BonusDuration.nTurns, turns = 2 })
			end
			server:refreshBattleUnits(battle)
		else
			return
		end
	end

	if not real(server) then return end
	local key = tier == 1 and 1 or (tier == 2 and PATRON_LOG[self.patron] or GOD_LOG[self.god])
	if key == nil then return end
	local who = favored[1]
	local log = { append = { "core.bonus." .. FAVOR .. ".description." .. (900000 + key) }, replaceNumbers = { favor } }
	if who and (tier == 1 or (tier == 2 and self.patron ~= "oceanus")) then
		log.replaceStrings = { who:getCreature():getNameTextID(who:getCount()) }
	end
	server:appendLog(battle, log)
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

	-- Prayer (commander Chief Oracle, aomPray.lua): while the Chief Oracle lives, add its AOM_FAVOR_PRAY points each round
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
		setValue(server, battle, u, FAVOR, favor, isSiege(u))
		setValue(server, battle, u, TIER, reached, true)
	end

	for t = tier + 1, reached do
		self:grant(server, battle, units, t, favor)
	end
	if reached < #THRESHOLD and real(server) then
		server:appendLog(battle, { append = { "core.bonus." .. FAVOR .. ".description.900009" }, replaceNumbers = { favor, THRESHOLD[reached + 1] } })
	end
end

return Script
