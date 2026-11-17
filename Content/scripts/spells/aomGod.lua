-- Shared by god powers: the caster's patron god (hidden AOM_GOD, inherited by the army; 1 Kronos 2 Oranos 3 Gaia), affinity check, hex distance.
local M = {}

function M.casterGod(mechanics)
	if not mechanics:getHeroCaster() then return 0 end
	local side = mechanics:getCasterSide()
	for _, u in ipairs(mechanics:getBattle():getUnitsIf(function(u) return u:getSide() == side end)) do
		local g = u:getBonusesValue({ type = "AOM_GOD" })
		if g > 0 then return g end
	end
	return 0
end

--- the caster's patron god is in effect.gods
function M.favoured(effect, mechanics)
	local g = M.casterGod(mechanics)
	for _, want in ipairs(effect.gods or {}) do
		if want == g then return true end
	end
	return false
end

--- steps between two hexes (same algorithm as the engine's BattleHex::getDistance)
function M.distance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1, x2 = a:getX() + math.floor(y1 / 2), b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then return math.max(math.abs(dx), math.abs(dy)) end
	return math.abs(dx) + math.abs(dy)
end

--- all standable hexes on the battlefield, sorted by distance from centre
function M.hexesByDistance(battle, centre)
	local arr, list = battle:getAllPossibleHexes(), {}
	for i = 1, arr:size() do
		local h = arr:at(i)
		list[#list + 1] = { hex = h, d = M.distance(centre, h), i = i }
	end
	table.sort(list, function(p, q) if p.d ~= q.d then return p.d < q.d end return p.i < q.i end)
	return list
end

return M
