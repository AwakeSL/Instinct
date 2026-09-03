--!strict

local Instinct = require("../src")

local i = Instinct.new({ seed = 0x5E1F }):defaults()

i:quantity("integrity")
i:quantity("energy")
i:quantity("hydration")
i:quantity("menace")

i:role("self")
i:role("target")

i:part("arms")
i:part("legs")
i:part("head")
i:part("eyes")

i:sense("sight", { needs = "eyes" })
i:sense("body", {})

i:feature("distance", { from = "sight" })
i:feature("menace", { from = "sight" })
i:feature("proximity", { from = "sight", is = { "distance", inverted = { 40, spread = 4 } } })

i:kind("thing")
i:kind("threat", { is = { "thing" }, stage = 1 })
i:kind("drinkable", { is = { "thing" }, stage = 2 })
i:kind("wolf", { is = { "threat" } })
i:kind("water", { is = { "drinkable" } })

i:skill("blade")

i:emotion("fear", {
	from = { of = "self", quantity = "integrity", falling = true, efficacy = "low" },
	decays = 0.8,
	modulates = { precision = { integrity = 1.6 }, commitment = 0.5, tempo = 1.8 },
})

i:emotion("anger", {
	from = { of = "self", quantity = "integrity", falling = true, efficacy = "high" },
	decays = 0.3,
	modulates = { caution = 0.4 },
})

i:action("walk_to", { occupies = { legs = 2 }, settles = { "at" }, costs = { energy = 0.004 } })

i:action("drink", {
	requires = { at = "drinkable" },
	occupies = { head = 1 },
	predicts = { { of = "self", hydration = { 0.8, spread = 0.1 }, after = { 4, spread = 2 } } },
	costs = { energy = 0.01 },
})

i:action("flee", {
	occupies = { legs = 2 },
	predicts = { { of = "self", integrity = { 0.35, spread = 0.3 }, after = { 1, spread = 0.5 } } },
	costs = { energy = 0.08 },
})

i:action("stab", {
	requires = { holding = "blade", at = "threat" },
	occupies = { arms = 1 },
	skill = "blade",
	predicts = { { of = "target", menace = { -0.7, spread = 0.2 }, after = { 0.4, spread = 0.1 } } },
	costs = { energy = 0.05 },
})

i:species("elf", {
	kind = "thing",
	parts = { arms = 2, legs = 2, head = 1, eyes = 2 },
	senses = { sight = { range = 40 }, body = {} },
	forms = { "distance", "menace", "proximity" },
	skills = { blade = 0.7 },
	feels = { "fear", "anger" },
	expects = {
		integrity = { 1.00, spread = 0.05 },
		energy = { 0.70, spread = 0.20 },
		hydration = { 0.90, spread = 0.15 },
	},
	instinct = {
		{
			about = "wolf",
			predicts = {
				{
					of = "self",
					integrity = { -0.9, by = { "proximity", "menace" }, spread = 0.2 },
					after = { 3, spread = 2 },
				},
			},
		},
	},
	dials = { tempo = 1.0, caution = 0.15, attention = 1.0, commitment = 0.3, adaptability = 0.5, grudge = 0.95 },
})

local elf = i:spawn("elf", { seed = 0x11 })

local function body(hydration: number, holding: any?): any
	return { via = "body", raw = { integrity = 1.0, energy = 0.7, hydration = hydration }, holding = holding }
end

local function pond(distance: number): any
	return {
		subject = "pond",
		kind = "water",
		via = "sight",
		raw = { distance = distance, at = distance < 3 },
	}
end

local function wolf(distance: number, menace: number): any
	return {
		subject = "grey",
		kind = "wolf",
		via = "sight",
		raw = { distance = distance, menace = menace, at = distance < 8 },
	}
end

local clock = 0
local function tick(what: { any }): string?
	clock += 1
	i:perceive(elf, what)
	return i:think(elf, 0.5, clock)
end

local function report(label: string)
	local why = i:why(elf)
	local doing = if why.doing.action ~= nil then why.doing.action else "nothing"
	local target = if why.doing.target ~= nil then (" -> " .. tostring(why.doing.target)) else ""
	print(("  %-22s %s%s"):format(label, doing, target))
	if why.because ~= nil then
		print(("  %-22s %s off by %.2f (%.1f spreads)"):format(
			"", why.because.quantity, why.because.error, why.because.spreads))
	end
	if #why.chain > 1 then
		print(("  %-22s plan: %s"):format("", table.concat(why.chain, " then ")))
	end
	local feelings = {}
	for _, name in { "fear", "anger" } do
		local level = i:stateOf(elf).level[name] or 0
		if level > 0.01 then
			table.insert(feelings, ("%s %.2f"):format(name, level))
		end
	end
	if #feelings > 0 then
		print(("  %-22s feeling: %s"):format("", table.concat(feelings, ", ")))
	end
end

local function rule(title: string)
	print("")
	print(title)
	print(("-"):rep(66))
end

rule("1. An elf that wants for nothing")
tick({ body(0.9) })
report("content")

rule("2. It gets thirsty, and the water is across the clearing")
tick({ body(0.25), pond(30) })
report("thirsty")
print("")
print("  It cannot drink from thirty studs away, so walking is recruited by the")
print("  drink that wants it. Nobody wrote that plan down.")

rule("3. It arrives")
tick({ body(0.25), pond(1) })
report("at the water")

local function meetsWolf(label: string, holding: any?)
	local who = i:spawn("elf", { seed = 0x22 })
	i:perceive(who, { body(0.9, holding), wolf(6, 0.9) })
	local chose = i:think(who, 0.5, 1)
	print(("  %-22s %s"):format(label, tostring(chose)))
	print(("  %-22s feeling: fear %.2f, anger %.2f"):format("",
		i:stateOf(who).level.fear or 0, i:stateOf(who).level.anger or 0))
	i:remove(who)
end

rule("4. A wolf. The same wolf, twice")
meetsWolf("empty handed", nil)
meetsWolf("with a blade", { blade = true })
print("")
print("  Identical animal at an identical distance. What changed is whether anything")
print("  it owns acts on the cause, and that is the whole of fight against flight.")

rule("5. Fourteen quiet meetings with the same wolf")
local function belief(): any
	for key, held in pairs(i:stateOf(elf).beliefs) do
		if key:find("subject|grey", 1, true) then
			return held
		end
	end
	return nil
end

for round = 1, 14 do
	tick({ body(0.9), wolf(6, 0.9) })
	tick({ body(0.9), wolf(6, 0.9) })
	if round == 1 or round == 3 or round == 7 or round == 14 then
		local held = belief()
		print(("  after %2d meetings   expects %+.3f harm, held to +/- %.3f"):format(round, held.v, held.s))
	end
end
print("")
local settled = tick({ body(0.9), wolf(6, 0.9) })
print(("  the wolf appears again -> %s"):format(if settled == nil then "it does not react at all" else settled))
print("")
print("  Nothing was reset. The belief simply moved until the predicted harm fell")
print("  inside the range its own model already allows, and stopped being evidence.")

rule("6. What it is holding, in its own words")
local held = belief()
print(("  about that particular wolf   %+.3f harm, spread %.3f, from %d observations"):format(
	held.v, held.s, held.n))
local kindHeld = i:stateOf(elf).beliefs["kind|wolf|self|integrity"]
print(("  about wolves in general      %+.3f harm, spread %.3f"):format(kindHeld.v, kindHeld.s))
print("")
print("  It generalised, but far more slowly than it learned the individual.")
print("  A wolf it has never met is still dangerous.")

rule("counters")
local stats = i:stats()
for _, name in { "thinks", "actionsChosen", "chainsFormed", "learned", "violations", "belowThreshold", "released" } do
	print(("  %-16s %d"):format(name, stats[name]))
end
print("")
