-- 给己方全体合适的部队加状态，不看法术点的是哪一格（金苹果树的再生）。其余和核心的 timed 一样。
local Base = require("spells/timed")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local battle, side, out = mechanics:getBattle(), mechanics:getCasterSide(), {}
	for _, u in ipairs(battle:getUnitsIf(function(u)
		return u:isAlive() and u:getSide() == side and self:isValidTarget(mechanics, u) and self:isReceptive(mechanics, u)
	end)) do
		out[#out + 1] = { unit = u, hex = u:getPosition() }
	end
	return out
end

function Script:applicableGeneral(mechanics, problem) return true end
function Script:applicableTarget(mechanics, problem, target) return true end
function Script:adjustAffectedHexes(mechanics, hexes, spellTarget) return hexes end

return Script
