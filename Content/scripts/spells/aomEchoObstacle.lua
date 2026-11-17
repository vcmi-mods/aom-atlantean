-- Divine Echo, obstacles: when the echo triggers, places one more one-hex obstacle.
-- With radius: a random free hex within radius of the target hex (one more tree for Gaia's Forest); without: a random free hex anywhere (one more Spider Lair trap).
-- anchorWest: true when the image is wider than a hex and aligns one hex to the left (the anchor hex is west of the occupied hex, the occupied hex is east of it).
-- Config: {"type": "aomEchoObstacle", "radius": 2, "anchorWest": true, "hidden": false, "passable": false, "trap": false, "triggerAbility": "", "removeOnTrigger": false,
--        "turnsRemaining": 2, "animation": "…", "appearAnimation": "…", "appearSound": "…", "removalAnimation": "…"}
local Base = require("spells/spellEffect")
local God = require("spells/aomGod")
local Echo = require("spells/aomEchoCommon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function free(battle, hex)
	if not hex:isValid() or not hex:isAvailable() then return false end
	if battle:getUnitByPos(hex, false) ~= nil then return false end
	if #battle:getObstaclesOnPos(hex, false) > 0 then return false end
	if battle:hasFortifications() and battle:hexToWallPart(hex) ~= ENUM.WallPart.invalid then return false end
	return true
end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	if #aimPoint > 0 then return { aimPoint[1] } end
	return {}
end

function Script:apply(mechanics, server, target)
	if not Echo.roll(mechanics, server) then return end
	local battle, pool = mechanics:getBattle(), {}
	local arr = battle:getAllPossibleHexes()
	for i = 1, arr:size() do
		local h = arr:at(i)
		if free(battle, h) then
			if self.radius and target[1] and target[1].hex then
				local d = God.distance(target[1].hex, h)
				if d >= 1 and d <= self.radius then pool[#pool + 1] = h end
			elseif not self.radius then
				pool[#pool + 1] = h
			end
		end
	end
	if #pool == 0 then return end
	local hex = pool[server:rngInt(1, #pool)]
	server:addObstacle(battle, {
		pos              = self.anchorWest and hex:copyToWest() or hex,
		obstacleType     = ENUM.ObstacleType.spellCreated,
		spell            = mechanics:getSpell(),
		casterSpellPower = mechanics:getEffectPower(),
		spellLevel       = mechanics:getEffectLevel(),
		casterSide       = mechanics:getCasterSide(),
		turnsRemaining   = self.turnsRemaining or -1,
		hidden           = self.hidden or false,
		passable         = self.passable or false,
		nativeVisible    = true,
		trap             = self.trap or false,
		removeOnTrigger  = self.removeOnTrigger or false,
		trigger          = self.triggerAbility or "",
		appearSound      = self.appearSound or "",
		appearAnimation  = self.appearAnimation or "",
		animation        = self.animation or "",
		removalAnimation = self.removalAnimation or "",
		customSize       = { hex },
	})
end

return Script
