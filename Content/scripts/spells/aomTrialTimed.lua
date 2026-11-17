-- 减速类附带效果（震地冲击的减速）用：正式施放和核心的 timed 完全一样。
-- 电脑试算（server:describeChanges() 为假）时不真的挂减速，改成对每支中招的敌方地面近战部队报 剩余总生命 × trialRatio 的等效扣血。
-- 为什么：BattleAI 一看到速度变了就整盘重估行动顺序，估出来的分比任何伤害都高，结果电脑手里有天穹内爆、冥界之门也只会每回合放震地冲击
-- （云端模拟器：12 种神力全在书里时 150 次施法里 129 次是震地冲击，而且大多打输；按伤害估值后 6 种神力轮着用，胜负反过来）。
-- 配置：核心 timed 的全部字段 + {"trialRatio": 0.04}
local Base = require("spells/timed")
local P = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:apply(mechanics, server, target)
	if not P.trial(server) then return Base.apply(self, mechanics, server, target) end
	local battle, side = mechanics:getBattle(), mechanics:getCasterSide()
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() and u:getSide() ~= side and not u:isShooter() and not u:hasBonuses({ type = "FLYING" }) then
			P.damage(server, battle, u, u:getAvailableHealth() * (self.trialRatio or 0.04))
		end
	end
end

return Script
