-- 神力回响，伤害类：回响触发时，对另一支可作用的部队再造成一次伤害，数值是原来的 echoFactor（默认一半）。
-- 配置：{"type": "aomEchoDamage", "echoFactor": 0.5, "animation": "回响时播的动画"}
local Base = require("spells/damage")
local Echo = require("spells/aomEchoCommon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- 动画只在真打的时候放：电脑试算（describeChanges 为假）时发动画包，引擎每次报 "BattleAnimationPlayed is not allowed in battle evaluation"
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

function Script:damageForTarget(targetIndex, mechanics, unit)
	return math.floor(Base.damageForTarget(self, 0, mechanics, unit) * (self.echoFactor or 0.5))
end

-- 回响不一定发生，悬停提示和 AI 估值里不算它
function Script:getHealthChange(mechanics, spellTarget)
	return { hpDelta = 0, unitsDelta = 0 }
end

function Script:apply(mechanics, server, target)
	if not Echo.roll(mechanics, server) then return end
	local dest = Echo.pick(self, mechanics, server, target)
	if not dest then return end
	showAnim(server, mechanics:getBattle(), { { unit = dest.unit } }, Echo.FX, "", 1.0, true)      -- 回响落在这支部队身上
	if self.animation then showAnim(server, mechanics:getBattle(), { { unit = dest.unit } }, self.animation, "", 1.0, true) end
	Base.apply(self, mechanics, server, { dest })
end

return Script
