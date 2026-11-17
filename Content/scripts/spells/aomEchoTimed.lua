-- 神力回响，状态类：回响触发时，把配置里的 bonus（写的是减半后的数值）加给另一支可作用的部队。
-- 配置：{"type": "aomEchoTimed", "bonus": {...}, "animation": "回响时播的动画"}
local Base = require("spells/timed")
local Echo = require("spells/aomEchoCommon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- 动画只在真打的时候放：电脑试算（describeChanges 为假）时发动画包，引擎每次报 "BattleAnimationPlayed is not allowed in battle evaluation"
local function showAnim(server, ...)
	if server.describeChanges and not server:describeChanges() then return end
	server:showBattleAnimation(...)
end

function Script:apply(mechanics, server, target)
	if not Echo.roll(mechanics, server) then return end
	local dest = Echo.pick(self, mechanics, server, target)
	if not dest then return end
	showAnim(server, mechanics:getBattle(), { { unit = dest.unit } }, Echo.FX, "", 1.0, true)      -- 回响落在这支部队身上
	if self.animation then showAnim(server, mechanics:getBattle(), { { unit = dest.unit } }, self.animation, "", 1.0, true) end
	Base.apply(self, mechanics, server, { dest })
end

-- noCommander：这个效果不能落在指挥官身上（指挥官的战斗格编号是 -2，和 kad 的招降、缩小同一种判法）。
function Script:isValidTarget(mechanics, unit)
	if self.noCommander and unit:getSlot() == -2 then return false end
	return Base.isValidTarget(self, mechanics, unit)
end

return Script
