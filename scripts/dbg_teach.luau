--!nonstrict
local process = require("@lune/process")
local Instinct = require("../src")
local Mind, Senses = Instinct.Mind, Instinct.Senses
local SLOTS = { "host", "item", "haz", "ally" }
local NAMES = Senses.layout(SLOTS, { "timeLeft", "armed" })
local CHOICES = { { name = "target", options = { "keep", "hostile" } }, { name = "move", options = { "hold", "forward" } } }
for _, effin in { "all", "trend", "raw" } do
	local m = Mind.new(#NAMES, CHOICES, { set = "OMECA", code = 16, readings = { "eaten" }, pref = { eaten = 1 }, effectsInputs = effin })
	print(("%s: nXE %d, effects F %d, phiE length %d"):format(effin, m.nXE, m.E[1].F, #m:phiE(m:extend(m:encode(table.create(#NAMES, 0.5))))))
end
