--!strict
-- Probe: do ACTION beliefs update from outcome, the way KIND beliefs do?
-- Control group is the kind belief, which the demo already shows learning.

local Instinct = require("../src")

local function build(withInstinct: boolean): (any, any)
	local i = Instinct.new({ seed = 0x5E1F }):defaults()
	i:quantity("hydration")
	i:role("self")
	i:part("head")
	i:part("eyes")
	i:sense("sight", { needs = "eyes" })
	i:sense("body", {})
	i:feature("distance", { from = "sight" })
	i:kind("thing")
	i:kind("water", { is = { "thing" } })

	i:action("drink", {
		requires = { at = "water" },
		occupies = { head = 1 },
		-- Claims a big hydration win. The world below will refuse to deliver it.
		predicts = { { of = "self", hydration = { 0.80, spread = 0.10 }, after = 1.0 } },
	})

	local species: any = {
		parts = { head = 1, eyes = 2 },
		senses = { sight = {}, body = {} },
		forms = { "distance" },
		expects = { hydration = { 0.90, spread = 0.05 } },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.3, adaptability = 0.9 },
	}
	if withInstinct then
		species.instinct = {
			{
				about = "water",
				predicts = { { of = "self", hydration = { 0.80, spread = 0.10 }, after = 1.0 } },
			},
		}
	end
	i:species("elf", species)
	return i, i:spawn("elf", { seed = 0x11 })
end

local function run(label: string, withInstinct: boolean, key: string)
	local i, elf = build(withInstinct)
	local clock = 0
	-- Hydration never rises: every prediction of +0.80 is contradicted, every time.
	for _ = 1, 60 do
		clock += 0.5
		i:perceive(elf, {
			{ via = "body", raw = { hydration = 0.20 } },
			{ subject = "pond", kind = "water", via = "sight", raw = { distance = 1, at = true } },
		})
		i:think(elf, 0.5, clock)
	end
	local held = i:stateOf(elf).beliefs[key]
	local stats = i:stats()
	if held == nil then
		print(("%-26s belief %s was never even created"):format(label, key))
	else
		print(("%-26s %s = %+.5f (spread %.5f, n=%d)  authored +0.80000"):format(
			label, key, held.v, held.s, held.n or 0))
	end
	print(("%-26s stats: learned=%d violations=%d associations=%d actionsChosen=%d"):format(
		"", stats.learned, stats.violations, stats.associations or 0, stats.actionsChosen))
end

print("60 ticks, each one contradicting a +0.80 hydration prediction:\n")
run("ACTION prediction", false, "action|drink|self|hydration")
print("")
run("KIND prediction (control)", true, "kind|water|self|hydration")
