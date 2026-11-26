-- Divine Echo, status: when the echo triggers, adds the configured bonus (written at halved values) to another valid unit.
-- Config: {"type": "aomEchoTimed", "bonus": {...}, "animation": "animation played on echo"}
local Base = require("spells/timed")
local Echo = require("spells/aomEchoCommon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- Animations only in real battles: sending animation packs during AI evaluation (describeChanges false) makes the engine log "BattleAnimationPlayed is not allowed in battle evaluation" every time
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

function Script:apply(mechanics, server, target)
	if not Echo.roll(mechanics, server) then return end
	local dest = Echo.pick(self, mechanics, server, target)
	if not dest then return end
	showAnim(server, mechanics:getBattle(), { { unit = dest.unit } }, Echo.FX, "", 1.0, true)      -- the echo lands on this unit
	if self.animation then showAnim(server, mechanics:getBattle(), { { unit = dest.unit } }, self.animation, "", 1.0, true) end
	Base.apply(self, mechanics, server, { dest })
end

-- noCommander: this effect cannot land on commanders (a commander's battle slot is -2).
function Script:isValidTarget(mechanics, unit)
	if self.noCommander and unit:getSlot() == -2 then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
