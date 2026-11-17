-- 每回合开始治疗相邻的友军（机械战士的互相修复、鹰身女祭司的治疗）。
-- val = 治疗量（每个治疗者；整队治疗量 = val × 队伍数量）
-- addInfo（只用于说明和校验，实际按兵身上的隐藏标记结算，见 Script:mend）：
--   mechanicalOnly  只修非生命单位（机关武士）
--   resurrect       治疗量有富余时复苏阵亡的（翠羽神谕者）
local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- 动画只在真打的时候放：电脑试算（describeChanges 为假）时发动画包，引擎每次报 "BattleAnimationPlayed is not allowed in battle evaluation"
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

local function oblivion(unit)
	local ok, has = pcall(function() return unit:hasBonuses({ type = "HOTA_RING_OF_OBLIVION" }) end)
	return ok and has
end

local MENDER, KIND = "AOM_MENDER", "AOM_MEND_KIND"
local ANIMATION = { "aom/atlantean/fx/heal.json", "aom/atlantean/fx/repair.json", "aom/atlantean/fx/revive.json" }

--- 一个治疗者给它相邻的友军治疗；治好的目标记进 shown（按部队编号，每个目标一种画面）
local function mendOne(server, battle, healer, shown)
	local side = healer:getSide()
	local kind = healer:getBonusesValue({ type = KIND })          -- 1 治疗，2 只修机械，3 带复活
	local power = healer:getBonusesValue({ type = MENDER }) * healer:getCount()
	local seen = {}

	local hexes = healer:getSurroundingHexes()
	for i = 1, hexes:size() do
		local other = battle:getUnitByPos(hexes:at(i), true)
		if other and other:isAlive() and other:getSide() == side and other:unitID() ~= healer:unitID() and not seen[other:unitID()] then
			seen[other:unitID()] = true
			local wanted = kind ~= 2 or other:hasBonuses({ type = "NON_LIVING" }) or other:hasBonuses({ type = "MECHANICAL" })
			-- 湮灭之戒（HotA）在场时不能复活：改成普通治疗，只回最上面那个生物（合集规矩，照 hota 的 ringOfOblivionPatch.lua；没装 HotA 时这个加成类型不存在，所以用 pcall）
			local revive = kind == 3 and not oblivion(other)
			local hurt = other:getFirstHPleft() < other:getMaxHealth() or (revive and other:getCount() < other:getBaseAmount())
			if wanted and hurt then
				local amount = power
				if not revive then amount = math.min(power, other:getMaxHealth() - other:getFirstHPleft()) end
				if amount > 0 then
					-- 引擎不接受“只治疗 + 仅本场”的组合（Heal for one battle does not make sense），治疗用 permanent，复活的兵战后消失
					server:healUnit(battle, other, amount, revive and ENUM.HealLevel.resurrect or ENUM.HealLevel.heal, revive and ENUM.HealPower.oneBattle or ENUM.HealPower.permanent)
					-- 一个目标只记一种画面：同一回合被几个治疗者治到时取最重的那种（复活 > 治疗 > 修复），免得两种画面叠在同一个兵身上，或同一种画面叠两遍
					local id, what = other:unitID(), revive and 3 or kind
					local rank = { [2] = 1, [1] = 2, [3] = 3 }
					if shown[id] == nil or rank[what] > rank[shown[id].kind] then shown[id] = { unit = other, kind = what } end
				end
			end
		end
	end
end

--- 每回合开始，一方所有治疗者的治疗由编号最小的那个一次结算，画面每种只播一次、同时播（每个治疗者各播一次会一个接一个排队，治疗的队伍多了每回合要等好几秒）。
--- 别的治疗者的治疗量和种类读它们身上的隐藏标记 AOM_MENDER（治疗量）、AOM_MEND_KIND（种类），所以带这个脚本的兵都要挂这两个标记（tools/abilities.py 自动加）。
function Script:mend(server, battle, unit)
	if not unit:isAlive() then return end
	local side = unit:getSide()
	local healers = battle:getUnitsIf(function(u) return u:isAlive() and u:getSide() == side and u:getBonusesValue({ type = MENDER }) > 0 end)
	for _, healer in ipairs(healers) do
		if healer:unitID() < unit:unitID() then return end          -- 不是领头的
	end
	table.sort(healers, function(a, b) return a:unitID() < b:unitID() end)

	local shown = {}
	for _, healer in ipairs(healers) do mendOne(server, battle, healer, shown) end
	local lists = { {}, {}, {} }
	for _, entry in pairs(shown) do
		local list = lists[entry.kind]
		list[#list + 1] = { unit = entry.unit }
	end

	-- 画面用游戏原版特效：治疗 = Caladria_healing（青色光柱），修复 = automaton_heal（电火花），带复活的 = Caladria_burst_healing（白光柱加光环）
	local any = false
	for kind = 1, 3 do
		if #lists[kind] > 0 then
			showAnim(server, battle, lists[kind], ANIMATION[kind], any and "" or "CURE", 1.0, true)
			any = true
		end
	end
	if any then server:refreshBattleUnits(battle) end
end

function Script:onRoundStart(server, battle, unit, other)
	self:mend(server, battle, unit)
end

return Script
