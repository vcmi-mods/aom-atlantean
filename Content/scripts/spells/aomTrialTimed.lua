-- For slowing side effects (the slow of Shockwave): real casts are exactly like core timed.
-- In AI evaluation (server:describeChanges() false) no slow is applied; instead every hit enemy ground melee stack reports remaining health x trialRatio as equivalent damage.
-- Why: BattleAI re-evaluates the whole turn order as soon as speed changes and scores that above any damage, so an AI with Implode and Tartarian Gate only ever cast Shockwave
-- (battle simulator: with all 12 god powers in the book, 129 of 150 casts were Shockwave, mostly lost; with damage-based values 6 powers were used in turn and results reversed).
-- Config: all fields of core timed + {"trialRatio": 0.04}
local Base = require("spells/timed")
local P = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:apply(mechanics, server, target)
	if not P.trial(server) then return Base.apply(self, mechanics, server, target) end
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() and u:getSide() ~= side and not u:isShooter() and not u:hasBonuses({ type = "FLYING" }) then
			P.damage(server, battle, u, u:getAvailableHealth() * (self.trialRatio or 0.04))
		end
	end
end

return Script
