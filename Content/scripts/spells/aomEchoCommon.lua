-- Divine Echo (racial secondary skill aomEcho), shared part.
-- The skill gives the hero a hidden AOM_ECHO (echo chance in percent; +10 with the Sorcery synergy), inherited by the army; the Luck synergy is AOM_ECHO_LUCK.
-- Every god power has an "echo" effect after its own effects (aomEchoDamage / aomEchoTimed / aomEchoSummon), which rolls here first.
-- Only hero casts echo; no roll in AI evaluation (describeChanges false) so random numbers are not wasted.
local M = {}

local function own(battle, side)
	return battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side end)
end

--- Roll the echo. Returns true on success, writes a battle log line and applies the Luck synergy.
local BOOST = { [0] = 15, 30, 45, 60 }      -- same as CMD_BOOST in aomAspect.lua
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
	-- Triune Order synergy (AOM_ECHO_SEASON): in the round an echo triggers, troops of the hero's patron aspect are ascendant (same values as aomAspect.lua; no double bonus if already ascendant)
	local cmd, godAspect = 0, { [1] = 2, [2] = 1, [3] = 3 }      -- patron god -> AOM_ASPECT (Kronos = Time 2, Oranos = Sky 1, Gaia = Earth 3)
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

--- Who the echo lands on: a random unit the spell can affect that was not an original target; if none, the first original target.
function M.pick(effect, mechanics, server, target)
	local hit = {}
	for _, dest in ipairs(target) do
		if dest.unit then hit[dest.unit:unitID()] = true end
	end
	-- echoes never hit the wrong side: negative powers only land on enemies, positive ones only on allies (area spells like Chaos may hit own units originally, the echo will not)
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
