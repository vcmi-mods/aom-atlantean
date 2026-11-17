-- Return to Atlantis (Grail spell), per-round part: after casting, a random out-of-town myth creature stack lands on your side at the start of every round.
-- This combat event is given by the spell's timed effect to own units present at casting; the budget (AOM_RETURN) is written by spells/aomReturn.lua.
-- Settled once per side per round, like aomFavor.lua: every unit counts its own rounds (AOM_RETURN_SEEN),
-- the first unit of a side that finds "own round count > settled round (AOM_RETURN_TICK)" does the landing.
local Base = require("combat/combatScript")
local L = require("lib/aomReturnLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit, other)
	if not unit:isAlive() then return end
	local budget = unit:getBonusesValue({ type = L.BUDGET })
	if budget <= 0 then return end

	local seen = unit:getBonusesValue({ type = L.SEEN }) + 1
	L.setValue(server, battle, unit, L.SEEN, seen)

	local side = unit:getSide()
	local units = battle:getUnitsIf(function(u)
		return u:isAlive() and u:getSide() == side and u:getBonusesValue({ type = L.BUDGET }) > 0
	end)
	local done = 0
	for _, u in ipairs(units) do done = math.max(done, u:getBonusesValue({ type = L.TICK })) end
	if done >= seen then return end

	L.drop(server, battle, side, budget)
	for _, u in ipairs(units) do L.setValue(server, battle, u, L.TICK, seen) end
end

return Script
