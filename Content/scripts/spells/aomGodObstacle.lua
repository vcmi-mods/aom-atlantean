-- Effect of obstacle god powers (Gaia's Forest, Golden Apple Tree): like core obstacle; if the caster's patron god is in `gods`, the obstacle stays extraTurns rounds longer.
-- Config: all fields of core obstacle + {"gods": [3], "extraTurns": 1}
local Base = require("spells/obstacle")
local God = require("spells/aomGod")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- for obstacles whose image aligns west, the anchor hex is west of the occupied hex; targets too far left would put the anchor off the field, so they are not allowed.
function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if not dest.hex or not dest.hex:isValid() then
			problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
			return false
		end
	end
	return Base.applicableTarget(self, mechanics, problem, target)
end

function Script:apply(mechanics, server, target)
	local plain = self.turnsRemaining
	if plain and plain > 0 and God.favoured(self, mechanics) then self.turnsRemaining = plain + (self.extraTurns or 1) end
	Base.apply(self, mechanics, server, target)
	self.turnsRemaining = plain
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Gaia's Forest (inside Golden Apple Tree aomSummonAt takes precedence and shows the summon cursor)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); with clearAffected at this level a blocked hex shows "X cannot be placed here" (181) without an estimate; damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorPlace" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
	local CLEAR = { -- clearAffected of the spell at the current level (none/basic/advanced/expert)
		["aom-atlantean:aomGaiaForest"] = { true, true, true, true },
		["aom-atlantean:aomHesperides"] = { true, true, true, true },
	}
	if hoveredHex == nil or not hoveredHex:isValid() or mechanics:isMassive() then return nil end
	local step = #partialTarget + 1
	local cursor = CURSORS[step]
	if cursor == nil then return nil end
	local spell = mechanics:getSpell()
	if step ~= 1 then return nil end
	local aim = AIM[spell:getJsonKey()] or AIM["*"]
	if aim ~= "creature" and aim ~= "location" then return nil end
	local spellName = spell:getNameTextID()
	if aim == "creature" then
		local battle = mechanics:getBattle()
		local unit = battle:getUnitByPos(hoveredHex, true) or battle:getUnitByPos(hoveredHex, false)
		local names = { spellName }
		if unit ~= nil then table.insert(names, unit:getCreature():getNameTextID(unit:getCount())) end
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.27" }, replaceStrings = names }, -- Cast %s on %s
			blockedText = { append = { "core.genrltxt.23" } },                  -- Select a target for the spell
			healthGainTextID = "vcmi.battleWindow.healValuePreview"
		}
	end
	local levels = CLEAR[spell:getJsonKey()]
	if step == 1 and levels ~= nil and levels[mechanics:getRangeLevel() + 1] then
		return {
			cursor = cursor,
			text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } },        -- Cast %s
			blockedText = { append = { "core.genrltxt.181" }, replaceStrings = { spellName } } -- %s cannot be placed here
		}
	end
	return {
		cursor = cursor,
		text = { append = { "core.genrltxt.26" }, replaceStrings = { spellName } }, -- Cast %s
		healthGainTextID = "vcmi.battleWindow.healValuePreview"
	}
end

return Script
