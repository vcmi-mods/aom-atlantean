-- Adds a status to every suitable own unit regardless of the hex clicked (Golden Apple Tree regeneration). Otherwise like core timed.
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
