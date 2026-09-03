--!strict
-- Does the "water plus green" refinement actually fire?
local Instinct = require("../src")

local i = Instinct.new({ seed = 0x5E1F }):defaults()
i:quantity("integrity")
i:role("self")
i:part("eyes")
i:sense("sight", { needs = "eyes" })
i:sense("body", {})
i:feature("green", { from = "sight" })
i:feature("distance", { from = "sight" })
i:kind("thing")
i:kind("water", { is = { "thing" } })
i:species("elf", {
	parts = { eyes = 2 },
	senses = { sight = {}, body = {} },
	forms = { "green", "distance" },
	expects = { integrity = { 1.00, spread = 0.05 } },
	dials = { tempo = 1.0, insight = 0.6, attribution = 0.9, capacity = 0.5, adaptability = 0.6 },
})
local elf = i:spawn("elf", { seed = 0x11 })

local clock = 0
local function tick(integrity: number)
	clock += 1
	i:perceive(elf, {
		{ via = "body", raw = { integrity = integrity } },
		-- a green pond, always green
		{ subject = "pond", kind = "water", via = "sight", raw = { green = 0.9, distance = 2 } },
	})
	i:think(elf, 1.0, clock)
end

for round = 1, 6 do
	tick(1.0)   -- healthy
	tick(0.55)  -- something hurt it, and nothing predicted that
	local st = i:stateOf(elf)
	local line = ("round %d: learned=%d"):format(round, #st.learned)
	for _, entry in st.learned do
		line ..= (" | about=%s times=%s refined=%s"):format(
			tostring(entry.about), tostring(entry.times), tostring(entry.refined))
	end
	print(line)
end

local stats = i:stats()
print(("\nassociations=%d acquired=%d unexplained=%d"):format(
	stats.associations or 0, stats.acquired or 0, stats.unexplained or 0))
