-- 重返大西洲（圣杯法术）的施法效果：立刻空降一队，并让本方之后每回合开始再空降一队，直到战斗结束。
-- 每回合的生命预算 = 力量 × 本级 power（和核心召唤法术同一算法，吃魔力术等加成），记在本方部队身上（AOM_RETURN）。
-- 每回合结算在 combat/aomReturn.lua（法术另一个 timed 效果把那个战斗事件挂给本方部队）。一场战斗只能放一次。
local Base = require("spells/summon")
local L = require("lib/aomReturnLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function own(battle, side)
	return battle:getUnitsIf(function(u) return u:isAlive() and not u:isGhost() and u:getSide() == side end)
end

function Script:applicableGeneral(mechanics, problem)
	for _, u in ipairs(own(mechanics:getBattle(), mechanics:getCasterSide())) do
		if u:getBonusesValue({ type = L.BUDGET }) > 0 then
			problem:addGeneric(mechanics)
			return false
		end
	end
	return true
end

function Script:applicableTarget(mechanics, problem, target) return true end

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	if #aimPoint > 0 then return { aimPoint[1] } end
	return spellTarget
end

function Script:apply(mechanics, server, target)
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	local budget = math.floor(self:summonedEffectValue(mechanics))
	if budget <= 0 then return end
	for _, u in ipairs(own(battle, side)) do
		L.setValue(server, battle, u, L.BUDGET, budget)
		L.setValue(server, battle, u, L.SEEN, 1)
	end
	-- 电脑试算（describeChanges 为假）只看得到这一下：按 6 队报，代表之后每回合还会再来（整合检查清单“AI 与战力数值”的代理价值）；
	-- 试算里的改动不会留到真战场，正式施放照常只降一队。
	local trial = server.describeChanges and not server:describeChanges()
	if not trial then      -- 全场动画，播完再落兵（不 deferred）
		local hex = L.screenHex(battle)
		if hex ~= nil then server:showBattleAnimation(battle, { { hex = hex } }, L.SCREEN_FX, "", 1.0, false) end
	end
	L.drop(server, battle, side, trial and budget * 6 or budget)
end

return Script
