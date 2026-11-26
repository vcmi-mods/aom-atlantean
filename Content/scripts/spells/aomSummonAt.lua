-- Summon next to the target hex: like core summon, but the new stack lands on the free hex nearest the target instead of the default spot on own half.
-- With summonSameUnit and an existing summoned stack of the same kind it merges into that stack as usual.
local Base = require("spells/summon")
local God = require("spells/aomGod")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local found = Base.transformTarget(self, mechanics, aimPoint, spellTarget)
	if #found == 0 or found[1].unit ~= nil or #aimPoint == 0 or not aimPoint[1].hex then return found end
	local battle, creature, side = mechanics:getBattle(), LIBRARY:getCreatureByName(self.id), mechanics:getCasterSide()
	local skip = {}
	for _, s in ipairs(self.keepFree or {}) do skip[s] = true end
	for _, cand in ipairs(God.hexesByDistance(battle, aimPoint[1].hex)) do
		if cand.d >= (self.minDistance or 1) and battle:isAccessibleForNewUnit(cand.hex, creature, side) then
			return { { hex = cand.hex, unit = nil } }
		end
	end
	return found
end

--- Cursor and status bar text while choosing a target: only the cursor changes (cursor proxy cursor_map.json): Golden Apple Tree and Underworld Passage summon next to the target hex (in Golden Apple Tree the dryads key comes before tree, so it decides the cursor)
--- The text copies the engine default (BattleSpellMechanics::describeTargetStep): on a unit "Cast X on Y" (core.genrltxt.27, Y singular or plural by count),
--- when it cannot be cast "Select a target for the spell" (23); on a hex "Cast X" (26); with clearAffected at this level a blocked hex shows "X cannot be placed here" (181) without an estimate; damage and healing estimates are appended as usual.
--- Steps (or modes) not listed in the table return nil and fall back to the engine default.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	local CURSORS = { [1] = "kadCursorSummon" } -- step number -> cursor
	local AIM = { ["*"] = "location" } -- target type of the first step (spell targetType)
	local CLEAR = { -- clearAffected of the spell at the current level (none/basic/advanced/expert)
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

--- Hover estimate: same formula as the core summon apply. A new stack shows "+ summoned count creatures"; when merging into an existing summoned stack of the same kind,
--- the total summoned health is added to that stack with overheal, and the number of extra creatures is shown
function Script:getHealthChange(mechanics, spellTarget)
	local zero = { hpDelta = 0, unitsDelta = 0 }
	local ok, result = pcall(function()
		local creature = LIBRARY:getCreatureByName(self.id)
		if creature == nil then return zero end
		local dest = spellTarget and spellTarget[1]
		if dest == nil then return zero end
		if dest.unit ~= nil then
			local healed, raised = dest.unit:copy():heal(math.floor(self:summonedCreatureHealth(mechanics)), ENUM.HealLevel.overheal,
				self.permanent and ENUM.HealPower.permanent or ENUM.HealPower.oneBattle)
			return { hpDelta = healed or 0, unitsDelta = raised or 0, unitType = creature }
		end
		local n = math.floor(self:summonedCreatureAmount(mechanics))
		if n <= 0 then return zero end
		return { hpDelta = n * creature:getMaxHealth(), unitsDelta = n, unitType = creature }
	end)
	if ok and result then return result end
	return zero
end

return Script
