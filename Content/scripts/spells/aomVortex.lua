-- Vortex: instantly moves the count own stacks nearest the target hex to around it (each on the free hex nearest the target).
-- Patron affinity (gods) moves 1 more stack; a Divine Echo moves 1 more. War machines and arrow towers are not moved.
-- Config: {"type": "aomVortex", "count": 2, "gods": [1, 2], "animation": "landing animation"}
local Base = require("spells/spellEffect")
local God = require("spells/aomGod")
local Echo = require("spells/aomEchoCommon")
local P = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- Animations only in real battles: sending animation packs during AI evaluation (describeChanges false) makes the engine log "BattleAnimationPlayed is not allowed in battle evaluation" every time
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
	-- AI evaluation (spells that move units only report an equivalent value in evaluation and never change the battlefield):
	-- for each moved melee stack that could not reach an enemy next to the target hex this round, book "one extra hit x 0.6" on that enemy;
	-- nothing is reported if a shooter with ammo would be dropped in front of enemies, or no enemy is next to the target hex.
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
			if cand.d >= here then break end      -- already closer than any reachable free hex, don't move
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

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Vortex teleports friendly units around the target hex
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "combatTeleport" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
