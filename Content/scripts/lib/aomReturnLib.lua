-- 重返大西洲（圣杯法术）公用：空降一队随机的城外神话生物。
-- 施法时（spells/aomReturn.lua）立刻空降一队，并给本方部队记下每回合的生命预算（AOM_RETURN）；
-- 之后每回合开始（combat/aomReturn.lua）再空降一队，直到战斗结束。
local M = {}

M.BUDGET, M.SEEN, M.TICK = "AOM_RETURN", "AOM_RETURN_SEEN", "AOM_RETURN_TICK"
M.FX = "aom/atlantean/fx/favor.json"
-- 施法时的全场动画：海浪卷过战场、九环之城在金光里升起又散成光点（OpenArt PixVerse V6 文生视频，按亮度抠底，38 帧，只做 1x）。
-- 图是 820×1012，战场画面（800×556）放在左上角：引擎把图片中心对在所播格子的上边中点，播在最下一行的 (8,10) 格，
-- 中心正好落在战场的 (410,506)，整幅对齐战场；最下一行最后画，所以盖在所有部队上面。
M.SCREEN_FX = "aom/atlantean/fx/returnAtl.json"
-- 城外的神话生物（人类兵种不算：神谕祭司、长锤步兵、破城兵、双刃狂徒、骑兵、喷火战车）
M.POOL = {
	"aom-atlantean:aomPromethean", "aom-atlantean:aomPrometheanLava", "aom-atlantean:aomPrometheanOffspring",
	"aom-atlantean:aomStymphalian", "aom-atlantean:aomTartarian", "aom-atlantean:aomArgus",
	"aom-atlantean:aomServant", "aom-atlantean:aomSatyr", "aom-atlantean:aomSatyrGold",
	"aom-atlantean:aomDryad", "aom-atlantean:aomLampades", "aom-atlantean:aomLampadesStar",
	"aom-atlantean:aomManOWar", "aom-atlantean:aomCarnivora", "aom-atlantean:aomBehemoth"
}
M.TRIAL = "aom-atlantean:aomTartarian"      -- 电脑试算时固定按冥渊恶兽估（试算里不掷骰）

local function real(server)
	return not server.describeChanges or server:describeChanges()
end

--- 全场动画要播的那一格：最下一行（y = 10）的第 8 格
function M.screenHex(battle)
	local arr = battle:getAllPossibleHexes()
	for i = 1, arr:size() do
		local h = arr:at(i)
		if h:getY() == 10 and h:getX() == 8 then return h end
	end
	return nil
end

--- 给一个单位写一个数值标记（先撤旧的）
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

--- 空降一队：总生命 budget，至少 1 只。场上已有同种召唤物就并进那一队。没有空位时这一回合不降。
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
