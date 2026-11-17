-- Return to Atlantis (Grail spell), cast effect: one stack lands at once, and another lands at the start of every following round until the battle ends.
-- Per-round health budget = power x this level's power (same as core summon spells, so Sorcery etc. apply), stored on own units (AOM_RETURN).
-- Per-round landing is in combat/aomReturn.lua (the spell's other timed effect gives that combat event to own units). Castable once per battle.
local Base = require("spells/summon")
local L = require("lib/aomReturnLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function own(battle, side)
	return battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() and u:getSide() == side end)
end

function Script:applicableGeneral(mechanics, problem)
	for _, u in ipairs(own(mechanics:getBattle(), mechanics:getCasterSide())) do
		if u:getBonusesValue({ type = L.BUDGET }) > 0 then
			problem:addGeneric(mechanics)
			return false
		end
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target) return true end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	if #aimPoint > 0 then return { aimPoint[1] } end
	return spellTarget
end

function Script:apply(mechanics, server, target)
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	local budget = math.floor(self:summonedEffectValue(mechanics))
	if budget <= 0 then return end
	for _, u in ipairs(own(battle, side)) do
		L.setValue(server, battle, u, L.BUDGET, budget)
		L.setValue(server, battle, u, L.SEEN, 1)
	end
	-- AI evaluation (describeChanges false) only sees this one cast: report it as 6 stacks to stand for the ones landing later (proxy value);
	-- evaluation changes never reach the real battlefield; real casts land one stack as usual.
	local trial = server.describeChanges and not server:describeChanges()
	if not trial then      -- full-battlefield animation, then land the stack (not deferred)
		local hex = L.screenHex(battle)
		if hex ~= nil then server:showBattleAnimation(battle, { { hex = hex } }, L.SCREEN_FX, "", 1.0, false) end
	end
	L.drop(server, battle, side, trial and budget * 6 or budget)
end

return Script
