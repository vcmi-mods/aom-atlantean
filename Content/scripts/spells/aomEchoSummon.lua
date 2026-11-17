-- 神力回响，召唤类：回响触发时再召唤一次，数量是原来的 echoFactor（默认一半）。
-- 配置同核心 summon，再加 "echoFactor"。它不拦施法（原法术自己的 summon 效果负责判断能不能放）。
local Base = require("spells/summon")
local Echo = require("spells/aomEchoCommon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:summonedEffectValue(mechanics)
	return math.floor(Base.summonedEffectValue(self, mechanics) * (self.echoFactor or 0.5))
end

function Script:applicableGeneral(mechanics, problem)
	return true
end

function Script:apply(mechanics, server, target)
	if self:summonedCreatureAmount(mechanics) <= 0 then return end
	if not Echo.roll(mechanics, server) then return end
	-- 目标要现在重新找：引擎在原法术的召唤生效之前就替本效果选好了空格，那一格现在已经站着刚召出来的那队；
	-- 重新找会找到那一队（summonSameUnit），回响的数量并进去
	Base.apply(self, mechanics, server, Base.transformTarget(self, mechanics, {}, {}))
end

return Script
