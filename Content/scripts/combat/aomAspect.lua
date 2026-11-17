-- Titan Aspects (the Atlantean faction system). Every creature carries one; addInfo.aspect = "sky", "time", "earth" or "man" (hero forms).
--
-- Sky: after attacking, marks the target with Sky Eye for 2 rounds. Units with this script attacking a Sky Eye target: no range or wall penalty, +1 Luck.
-- Time: each attack adds one Time Lag stack (-1 Speed, 3 rounds); at 3 stacks the target is Frozen for one round (cannot act) and the stacks reset.
-- Earth: at the start of each round leaves Lush Ground underfoot for 3 rounds (a passable battlefield obstacle; each side uses its own marker spell).
--     Allied troops standing on it: this round regain 10% health, +2 Defense, immune to Time Lag and Freeze; enemies on it: -2 Speed this round.
--     Man (hero forms) standing on Lush Ground get +3 Attack.
-- Man: Seize the moment - +100% damage against Sky Eye targets; adds one extra Time Lag stack to lagged targets.
-- Sky + Time: attacks against a target with both Sky Eye and Time Lag ignore 30% of its Defense.
-- All four: with Sky, Time, Earth and Man in the army, hero forms attack one extra time in one round per battle. The Kronos Titan (addInfo.surgeOnce) also attacks one extra time the first time it is ascendant.
-- Aspect rotation: one aspect is ascendant each round, in the order Sky -> Time -> Earth; ascendant troops get +2 Speed and +15% damage this round.
-- Patron god: hero specialties carry a hidden AOM_GOD (1 Kronos, 2 Oranos, 3 Gaia, inherited by the army); the patron's aspect is one step stronger -
--     Oranos: Sky Eye lasts 3 rounds; Kronos: 2 Time Lag stacks freeze; Gaia: Lush Ground heals 15%.
-- Hold: when the hero has AOM_SEASON_HOLD (Kronos himself), Time stays ascendant for two rounds, rotation Sky -> Time -> Time -> Earth.
-- Triune Order (racial secondary skill, hidden AOM_SEASON_CMD = 1/2/3 on the hero, inherited by the army): ascendant damage +30%/45%/60% (25/35/50 before 0.0.52); the skill also gives the hero +1/2/3 Attack;
--     from Advanced the rotation starts at the hero's patron aspect; at Expert hero forms (Man) are also ascendant in the patron aspect's round.
--     Patron Temple (town building, hidden AOM_SEASON_TEMPLE on defending troops): in sieges the rotation also starts at the defending hero's patron aspect.
--     Titan Legacy (AOM_RELIC): ascendant damage another +10%, all three aspects ascendant in the first round.
--     Synergies: Tactics (AOM_SEASON_SPD) ascendant Speed another +1; Leadership (AOM_SEASON_MORALE) ascendant troops +1 Morale.
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local ROUND, SEASON, SKYEYE, TIMELAG, FROZEN = "AOM_ASPECT_ROUND", "AOM_INSEASON", "AOM_SKYEYE", "AOM_TIMELAG", "AOM_FROZEN"
local ORDER = { sky = 0, time = 1, earth = 2 }
local MAX_LAG = 3
local CMD_BOOST = { [0] = 15, 30, 45, 60 }      -- ascendant damage: 15% without Triune Order, Basic/Advanced/Expert 30/45/60%
local GOD, HOLD = "AOM_GOD", "AOM_SEASON_HOLD"
local KRONOS, ORANOS, GAIA = 1, 2, 3
local CMD, CMD_SPD, CMD_MORALE = "AOM_SEASON_CMD", "AOM_SEASON_SPD", "AOM_SEASON_MORALE"
local GOD_PHASE = { [1] = 1, [2] = 0, [3] = 2 }      -- patron god -> index of its aspect in the rotation (Kronos = Time, Oranos = Sky, Gaia = Earth)
local HELD = { [0] = 0, [1] = 1, [2] = 1, [3] = 2 }

-- Animations only in real battles: sending animation packs during AI evaluation (describeChanges false) makes the engine log "BattleAnimationPlayed is not allowed in battle evaluation" every time
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
-- Dissolve: the engine plays the removal animation backwards, so frames go from faint to solid; without it the engine logs "I don't know how to animate removal of this obstacle" for every obstacle
local LUSH_FADE = "aom/atlantean/fx/lushOut.json"
-- Effects when a status is applied, all original game effects (tools/fx_spell.py, fx_cut.py): Sky Eye = skypassage_symbol_glow, Time Lag and Freeze = kronos_glow (small, large), Sky ascendant = sky_passage_glow
local FX = { eye = "aom/atlantean/fx/skyeye.json", lag = "aom/atlantean/fx/timelag.json", frozen = "aom/atlantean/fx/frozen.json", seasonSky = "aom/atlantean/fx/seasonSky.json",
	seasonEarth = "aom/atlantean/fx/seasonEarth.json", seasonCmd = "aom/atlantean/fx/seasonCmd.json" }
local SEASON_FX = { sky = FX.seasonSky, time = FX.lag, earth = FX.seasonEarth }

-- The Sky Eye ground disc must be drawn under the target's feet: the engine draws by row first, then layer, so effects are always drawn above units in the same row.
-- So the disc is played on a hex in the row above the target (drawn before the target's row); the images are pre-cut with the feet 83 px below the image centre and offset 22 px sideways:
--   one-hex target: upper-left hex uses skyeyeGL, upper-right uses skyeyeGR; two-hex target: the hex above the body centre uses skyeyeG0.
-- The halo over the head (skyeyeTop) is played on the target as usual. If there is no usable hex above (top row, or a two-hex unit there, which makes the engine shift the image half a hex) the full skyeye is used instead.
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

--- Earth: leave Lush Ground and settle the troops standing on own Lush Ground
function Script:lush(server, battle, unit)
	local key = LUSH_SPELL[sideIndex(unit)]
	local turn = ENUM.BonusDuration.nTurns

	-- one per hex (the engine draws an obstacle image only at its anchor hex, so two-hex units need two)
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

--- one extra attack this round, once per battle
function Script:extraAttack(server, battle, unit)
	local turn = ENUM.BonusDuration.nTurns
	add(server, battle, unit, { type = USED, val = 1, valueType = ENUM.BonusValueType.baseNumber, duration = ENUM.BonusDuration.oneBattle, hidden = true })
	add(server, battle, unit, { type = "ADDITIONAL_ATTACK", val = 1, duration = turn, turns = 1, hidden = true })
	add(server, battle, unit, { type = SURGE, val = 1, valueType = ENUM.BonusValueType.baseNumber, duration = turn, turns = 1 })
	server:appendLog(battle, { append = { "core.bonus." .. SURGE .. ".description.900001" }, replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }, replaceNumbers = { 1 } })
end

--- Aspect rotation
function Script:season(server, battle, unit, round)
	clear(server, battle, unit, ROUND)
	add(server, battle, unit, { type = ROUND, val = round, valueType = ENUM.BonusValueType.baseNumber, duration = ENUM.BonusDuration.oneBattle, hidden = true })

	if self.aspect == "earth" and unit:isAlive() then self:lush(server, battle, unit) end

	-- Siege note: in the first round, the defending unit with this script and the lowest id writes one battle log line (Patron Temple, Mythic/Wonder Age siege bonuses)
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

	-- Man: with Sky, Time, Earth and Man all in the army, one extra attack in one round per battle (the original design was an extra action, which the engine cannot do)
	if self.aspect == "man" and unit:isAlive() and not unit:hasBonuses({ type = USED }) then
		local side, seen = unit:getSide(), {}
		for _, other in ipairs(battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side end)) do
			seen[other:getBonusesValue({ type = "AOM_ASPECT" })] = true
		end
		if seen[1] and seen[2] and seen[3] then self:extraAttack(server, battle, unit) end
	end

	local index = ORDER[self.aspect or ""]
	local cmd, own = unit:getBonusesValue({ type = CMD }), GOD_PHASE[god(unit)]
	local lead = cmd >= 2 or unit:hasBonuses({ type = "AOM_SEASON_TEMPLE" })      -- Advanced Triune Order, or defending a town with a Patron Temple: start at the patron aspect
	local start = (lead and own) or 0
	local phase = (round - 1 + start) % 3
	if unit:hasBonuses({ type = HOLD }) then phase = HELD[(round - 1 + (lead and 1 or 0)) % 4] end      -- Hold: Sky Time Time Earth; Advanced Triune Order starts at the first Time
	-- Father of the Sky / Mother Earth (specialties of Oranos and Gaia themselves: hidden AOM_PARENT = 2/3 on the hero, inherited by the army) [town_design2]
	-- in Sky (or Earth) ascendant rounds, every unit with this script, whatever its aspect: Sky = +1 Luck, +1 Speed; Earth = +2 Defense, regain 5% health
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
	if self.aspect == "man" and cmd >= 3 then index = own end -- Expert Triune Order: hero forms are also ascendant when the patron aspect is
	-- Titan Legacy (combination artifact, hidden AOM_RELIC on the hero, inherited by the army): Sky, Time and Earth all ascendant in the first round; ascendant damage another +10
	if self.always then index = phase end      -- Triune Unity (capital guardian): ascendant every round
	local relic = unit:getBonusesValue({ type = "AOM_RELIC" }) > 0
	if index == nil or not unit:isAlive() then return end
	if phase ~= index and not (relic and round == 1) then return end

	-- Kronos Titan: one extra attack in the first round it is ascendant (once per battle; originally an extra action)
	if self.surgeOnce and not unit:hasBonuses({ type = USED }) then self:extraAttack(server, battle, unit) end

	local turn = ENUM.BonusDuration.nTurns
	add(server, battle, unit, { type = "STACKS_SPEED", val = 2 + unit:getBonusesValue({ type = CMD_SPD }), duration = turn, turns = 1, hidden = true })
	add(server, battle, unit, { type = "PERCENTAGE_DAMAGE_BOOST", subtype = "damageTypeAll", val = (CMD_BOOST[cmd] or 15) + (relic and 10 or 0), duration = turn, turns = 1, hidden = true })
	if unit:getBonusesValue({ type = CMD_MORALE }) > 0 then add(server, battle, unit, { type = "MORALE", val = 1, duration = turn, turns = 1, hidden = true }) end
	add(server, battle, unit, { type = SEASON, val = (CMD_BOOST[cmd] or 15) + (relic and 10 or 0), valueType = ENUM.BonusValueType.baseNumber, duration = turn, turns = 1 })

	-- ascendant visuals: the unit with the lowest id of each aspect on a side plays it once for all (one per unit would queue up one after another)
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
			local note = ({ sky = 1, time = 2, earth = 3 })[self.aspect]      -- battle log: which aspect is ascendant this round
			if note and (not server.describeChanges or server:describeChanges()) then
				server:appendLog(battle, { append = { "core.bonus." .. SEASON .. ".description." .. (900000 + note) }, replaceNumbers = { (CMD_BOOST[cmd] or 15) + (relic and 10 or 0) } })
			end
			showAnim(server, battle, shown, animation, "", 1.0, true)
			if cmd > 0 then showAnim(server, battle, shown, FX.seasonCmd, "", 1.0, true) end      -- Triune Order: an extra time light pillar when ascendant
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
		if (not server.describeChanges or server:describeChanges()) then      -- battle log: Sky + Time
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
	if target:hasBonuses({ type = "AOM_LAG_REST" }) then return nil end      -- a unit that was frozen is immune to Time Lag for 2 rounds
	if target:hasBonuses({ type = LUSH }) then return nil end          -- Earth advantage: standing on own Lush Ground gives immunity to Time Lag and Freeze
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
				-- Time Lag needs weight: a hit dealing less than 3% of the target stack's total health (before the hit) adds no stack, so a single unit cannot freeze a whole stack (audit N6)
				local left = (target:getCount() - 1) * target:getMaxHealth() + target:getFirstHPleft()
				local what = (entry.damage * 100 >= (left + entry.damage) * 3) and self:addLag(server, battle, target, limit) or nil
				if what then
					shown[what][#shown[what] + 1] = { unit = target }
					changed = true
				end
			end
		end
	end

	-- play each status once for all targets, refresh once at the end
	if changed then
		if #shown.eye > 0 then showEye(server, battle, shown.eye) end
		for _, what in ipairs({ "lag", "frozen" }) do
			if #shown[what] > 0 then showAnim(server, battle, shown[what], FX[what], "", 1.0, true) end
		end
		server:refreshBattleUnits(battle)
	end
end

return Script
