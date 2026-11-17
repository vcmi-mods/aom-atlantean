-- 神力法术公用：施法英雄的主神（隐藏的 AOM_GOD，全军继承；1 克洛诺斯 2 乌拉诺斯 3 盖亚）、主神亲和判断、格子距离。
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

--- effect.gods 名单里有施法英雄的主神
function M.favoured(effect, mechanics)
	local g = M.casterGod(mechanics)
	for _, want in ipairs(effect.gods or {}) do
		if want == g then return true end
	end
	return false
end

--- 两格之间的步数（和引擎 BattleHex::getDistance 同一算法）
function M.distance(a, b)
	local y1, y2 = a:getY(), b:getY()
	local x1, x2 = a:getX() + math.floor(y1 / 2), b:getX() + math.floor(y2 / 2)
	local dx, dy = x2 - x1, y2 - y1
	if (dx >= 0 and dy >= 0) or (dx < 0 and dy < 0) then return math.max(math.abs(dx), math.abs(dy)) end
	return math.abs(dx) + math.abs(dy)
end

--- 战场上全部可站的格子，按离 centre 从近到远排好
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
