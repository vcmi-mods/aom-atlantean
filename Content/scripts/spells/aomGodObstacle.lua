-- 障碍类神力（盖亚之林、金苹果树）的效果本体：和核心的 obstacle 一样；施法英雄的主神在 gods 名单里时，障碍多留 extraTurns 回合。
-- 配置：核心 obstacle 的全部字段 + {"gods": [3], "extraTurns": 1}
local Base = require("spells/obstacle")
local God = require("spells/aomGod")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

-- 图片靠西对齐的障碍，定位格在占用格西边；目标太靠左时定位格会出界，这种目标不让放。
function Script:applicableTarget(mechanics, problem, target)
	for _, dest in ipairs(target) do
		if not dest.hex or not dest.hex:isValid() then
			problem:addStandard(mechanics, ENUM.SpellCastProblem.noAppropriateTarget)
			return false
		end
	end
	return Base.applicableTarget(self, mechanics, problem, target)
end

function Script:apply(mechanics, server, target)
	local plain = self.turnsRemaining
	if plain and plain > 0 and God.favoured(self, mechanics) then self.turnsRemaining = plain + (self.extraTurns or 1) end
	Base.apply(self, mechanics, server, target)
	self.turnsRemaining = plain
end

return Script
