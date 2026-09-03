--!strict
-- Does a predicted GAIN about a kind create any drive, the way a predicted HARM does?
-- Both creatures are sitting exactly at their prior, so any error must come from the instinct.
local Instinct = require("../src")

local function trial(label: string, about: string, quantity: string, amount: number)
	local i = Instinct.new({ seed = 1 }):defaults()
	i:quantity("hydration")
	i:quantity("integrity")
	i:role("self")
	i:part("eyes")
	i:sense("sight", { needs = "eyes" })
	i:sense("body", {})
	i:feature("proximity", { from = "sight" })
	i:kind("thing")
	i:kind("water", { is = { "thing" } })
	i:kind("wolf", { is = { "thing" } })
	i:action("flee", {
		predicts = { { of = "self", integrity = { 0.3, spread = 0.2 }, after = 1 } },
	})
	i:species("elf", {
		parts = { eyes = 2 },
		senses = { sight = {}, body = {} },
		forms = { "proximity" },
		expects = {
			hydration = { 0.90, spread = 0.10 },
			integrity = { 1.00, spread = 0.05 },
		},
		instinct = {
			{
				about = about,
				predicts = {
					{ of = "self", [quantity] = { amount, by = { "proximity" }, spread = 0.2 }, after = 2 },
				},
			},
		},
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0 },
	})
	i:ready()
	local elf = i:spawn("elf", { seed = 2 })

	-- Sitting exactly at both priors: nothing is currently wrong with it.
	i:perceive(elf, {
		{ via = "body", raw = { hydration = 0.90, integrity = 1.00 } },
		{ subject = "it", kind = about, via = "sight", raw = { proximity = 0.9 } },
	})
	i:think(elf, 0.5, 1)
	local why = i:why(elf)
	local because = why.because
	print(("%-34s -> %s"):format(
		label,
		if because ~= nil
			then ("error on %s of %.3f (%.1f spreads)"):format(because.quantity, because.error, because.spreads)
			else "NO ERROR AT ALL - it is not moved by this"))
end

print("A creature already at its prior, looking at something:\n")
trial("wolf predicts -0.9 integrity", "wolf", "integrity", -0.9)
trial("water predicts +0.9 hydration", "water", "hydration", 0.9)
