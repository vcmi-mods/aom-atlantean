-- 重返大西洲（圣杯法术）的每回合结算：施法之后，每回合开始本方空降一队随机的城外神话生物。
-- 这个战斗事件由法术的 timed 效果挂给施法时在场的本方部队；预算（AOM_RETURN）由 spells/aomReturn.lua 写。
-- 按“一方每回合一次”结算，写法和 aomFavor.lua 一样：每个单位数自己经历的回合（AOM_RETURN_SEEN），
-- 一方里第一个发现“自己的回合数 > 已结算回合数（AOM_RETURN_TICK）”的单位负责空降。
local Base = require("combat/combatScript")
local L = require("lib/aomReturnLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:onRoundStart(server, battle, unit, other)
	if not unit:isAlive() then return end
	local budget = unit:getBonusesValue({ type = L.BUDGET })
	if budget <= 0 then return end

	local seen = unit:getBonusesValue({ type = L.SEEN }) + 1
	L.setValue(server, battle, unit, L.SEEN, seen)

	local side = unit:getSide()
	local units = battle:getUnitsIf(function(u)
		return u:isAlive() and u:getSide() == side and u:getBonusesValue({ type = L.BUDGET }) > 0
	end)
	local done = 0
	for _, u in ipairs(units) do done = math.max(done, u:getBonusesValue({ type = L.TICK })) end
	if done >= seen then return end

	L.drop(server, battle, side, budget)
	for _, u in ipairs(units) do L.setValue(server, battle, u, L.TICK, seen) end
end

return Script
