-- Divine Echo, damage: when the echo triggers, deals the damage again to another valid unit, at echoFactor of the original (half by default).
-- Config: {"type": "aomEchoDamage", "echoFactor": 0.5, "animation": "animation played on echo"}
local Base = require("spells/damage")
local Echo = require("spells/aomEchoCommon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- Animations only in real battles: sending animation packs during AI evaluation (describeChanges false) makes the engine log "BattleAnimationPlayed is not allowed in battle evaluation" every time
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	return math.floor(Base.damageForTarget(self, 0, mechanics, unit) * (self.echoFactor or 0.5))
end

-- the echo may not happen, so it is left out of hover hints and AI value
function Script:getHealthChange(mechanics, spellTarget)
	return { hpDelta = 0, unitsDelta = 0 }
end

function Script:apply(mechanics, server, target)
	if not Echo.roll(mechanics, server) then return end
	local dest = Echo.pick(self, mechanics, server, target)
	if not dest then return end
	showAnim(server, mechanics:getBattle(), { { unit = dest.unit } }, Echo.FX, "", 1.0, true)      -- the echo lands on this unit
	if self.animation then showAnim(server, mechanics:getBattle(), { { unit = dest.unit } }, self.animation, "", 1.0, true) end
	Base.apply(self, mechanics, server, { dest })
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
