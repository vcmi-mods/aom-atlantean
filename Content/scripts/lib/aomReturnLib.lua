-- Return to Atlantis (Grail spell), shared: land one random out-of-town myth creature stack.
-- On casting (spells/aomReturn.lua) one stack lands at once and own troops get the per-round health budget (AOM_RETURN);
-- then at each round start (combat/aomReturn.lua) another stack lands, until the battle ends.
local M = {}

M.BUDGET, M.SEEN, M.TICK = "AOM_RETURN", "AOM_RETURN_SEEN", "AOM_RETURN_TICK"
M.FX = "aom/atlantean/fx/favor.json"
-- Full-battlefield cast animation: waves sweep the field, the city of nine rings rises in golden light and dissolves into sparks (OpenArt PixVerse V6 text-to-video, keyed by brightness, 38 frames, 1x only).
-- The image is 820x1012 with the battlefield view (800x556) in the top-left corner: the engine centres the image on the top edge middle of the hex it plays on; played on hex (8,10) in the bottom row,
-- its centre lands on (410,506) so the whole image lines up with the battlefield; the bottom row is drawn last, so it covers every unit.
M.SCREEN_FX = "aom/atlantean/fx/returnAtl.json"
-- out-of-town myth creatures (human units excluded: Oracle Priest, Katapeltes, Wall Breaker, Fanatic, cavalry, Fire Siphon)
M.POOL = {
	"aom-atlantean:aomPromethean", "aom-atlantean:aomPrometheanLava", "aom-atlantean:aomPrometheanOffspring",
	"aom-atlantean:aomStymphalian", "aom-atlantean:aomTartarian", "aom-atlantean:aomArgus",
	"aom-atlantean:aomServant", "aom-atlantean:aomSatyr", "aom-atlantean:aomSatyrGold",
	"aom-atlantean:aomDryad", "aom-atlantean:aomLampades", "aom-atlantean:aomLampadesStar",
	"aom-atlantean:aomManOWar", "aom-atlantean:aomCarnivora", "aom-atlantean:aomBehemoth"
}
M.TRIAL = "aom-atlantean:aomTartarian"      -- AI evaluation always assumes the Tartarian Spawn (no dice rolls in evaluation)

local function real(server)
	return not server.describeChanges or server:describeChanges()
end

--- hex for the full-battlefield animation: 8th hex of the bottom row (y = 10)
function M.screenHex(battle)
	local arr = battle:getAllPossibleHexes()
	for i = 1, arr:size() do
		local h = arr:at(i)
		if h:getY() == 10 and h:getX() == 8 then return h end
	end
	return nil
end

--- write one numeric marker on a unit (removing the old one first)
function M.setValue(server, battle, unit, bonusType, value)
	local old = unit:getBonuses({ type = bonusType })
	if old:size() > 0 then server:removeUnitBonuses(battle, unit, old) end
	if value > 0 then
		server:addUnitBonus(battle, unit, {
			type = bonusType, sourceType = ENUM.BonusSource.other, val = value,
			valueType = ENUM.BonusValueType.baseNumber, duration = ENUM.BonusDuration.oneBattle, hidden = true
		}, false)
	end
end

--- land one stack: total health `budget`, at least 1 creature. Merges into an existing summoned stack of the same kind. No landing this round if there is no free hex.
function M.drop(server, battle, side, budget)
	if budget <= 0 then return false end
	local name = M.TRIAL
	if real(server) then name = M.POOL[server:rngInt(1, #M.POOL)] end
	local creature = LIBRARY:getCreatureByName(name)
	if creature == nil then return false end
	local count = math.max(1, math.floor(budget / creature:getMaxHealth()))
	local key = creature:getJsonKey()
	local same = battle:getUnitsIf(function(u)
		return u:isAlive() and u:getSide() == side and u:isSummoned() and not u:isClone() and u:getCreature():getJsonKey() == key
	end)[1]
	local where
	if same ~= nil then
		server:healUnit(battle, same, count * creature:getMaxHealth(), ENUM.HealLevel.overheal, ENUM.HealPower.oneBattle)
		where = same
	else
		local hex = battle:getAvailableHex(creature, side)
		if not hex:isValid() then return false end
		server:addUnit(battle, { count = count, type = creature, side = side, position = hex, summoned = true })
	end
	if real(server) then
		server:appendLog(battle, {
			append = { "core.bonus." .. M.BUDGET .. ".description.1" },
			replaceStrings = { creature:getNameTextID(count) }, replaceNumbers = { count }
		})
		if where ~= nil then
			server:showBattleAnimation(battle, { { unit = where } }, M.FX, "BLESS", 1.0, true)
			server:refreshBattleUnits(battle)
		end
	end
	return true
end

return M
