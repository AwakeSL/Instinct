--!strict

local Instinct = require("../src")

-- A small world of its own rather than the shared Fixture, because these cases turn on which
-- action gets chosen and how often, and that is easier to state than to arrange around a world
-- built for something else.
local function world(species: any?, gain: number?): (any, any)
	local i = Instinct.new({ seed = 0x5E1F }):defaults()

	i:quantity("hydration", { range = { 0, 1 } })
	i:quantity("anger", { range = { 0, 1 } })

	i:role("self")
	i:role("target")

	i:part("head")
	i:part("eyes")

	i:sense("sight", { needs = "eyes" })
	i:sense("body", {})

	i:feature("distance", { from = "sight" })

	i:kind("thing")
	i:kind("drinkable", { is = { "thing" } })
	i:kind("water", { is = { "drinkable" } })

	i:action("drink", {
		requires = { at = "drinkable" },
		occupies = { head = 1 },
		predicts = { { of = "self", hydration = { gain or 0.40, spread = 0.20 }, after = 1.0 } },
	})

	-- Predicts nothing on its own. What it does is a species opinion, not a property of the act.
	i:action("mutter", { occupies = { head = 1 } })

	local decl: any = {
		parts = { head = 1, eyes = 2 },
		senses = { sight = {}, body = {} },
		forms = { "distance" },
		expects = { hydration = { 0.90, spread = 0.05 } },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, adaptability = 0.6 },
	}
	for key, value in pairs(species or {}) do
		decl[key] = value
	end
	i:species("elf", decl)
	i:ready()
	return i, i:spawn("elf", { seed = 0x11 })
end

local function pond(): any
	return { subject = "pond", kind = "water", via = "sight", raw = { distance = 1, at = true } }
end

local function body(raw: any): any
	return { via = "body", raw = raw }
end

local function belief(i: any, elf: any, key: string): any
	return i:stateOf(elf).beliefs[key]
end

-- One round: the creature acts, then the horizon passes and the world reports what happened.
local function round(i: any, elf: any, clock: number, before: any, after: any): number
	i:perceive(elf, { body(before), pond() })
	i:think(elf, 1.0, clock)
	i:perceive(elf, { body(after), pond() })
	i:think(elf, 1.0, clock + 1.0)
	return clock + 2.0
end

return function(t: any)
	local DRINK = "action|drink|self|hydration"

	-- The wire itself: a prediction an action made is checked against what followed.
	do
		local i, elf = world()
		local clock = 1
		for _ = 1, 12 do
			clock = round(i, elf, clock, { hydration = 0.20 }, { hydration = 0.20 })
		end
		local held = belief(i, elf, DRINK)
		t.ok(held ~= nil, "using an action creates a belief about what it does")
		t.ok(held.n > 1, "and that belief is checked against what followed, more than once")
		t.ok(i:stats().learned > 1, "so `learned` counts action outcomes, not only instinct ones")
	end

	-- Drinking that never hydrates is a belief that has to come down.
	do
		local i, elf = world()
		local clock = 1
		for _ = 1, 12 do
			clock = round(i, elf, clock, { hydration = 0.20 }, { hydration = 0.20 })
		end
		local held = belief(i, elf, DRINK)
		t.ok(held.v < 0.15, "an action that never delivers loses the belief that it does")
		t.ok(held.v < 0.40, "which is a move away from the authored prior, not a reset to it")
	end

	-- Competence is earned: an action that keeps doing what it said narrows.
	--
	-- The world has to be honestly consistent for this to mean anything. A prediction is checked
	-- across the interval between two thinks, so a scenario that lets the quantity fall back
	-- between rounds is one where drinking really is followed by a loss half the time, and a
	-- creature that concluded otherwise would be the broken one. Hydration only ever rises here.
	do
		local i, elf = world(nil, 0.05)
		local hydration = 0.20
		local early = nil
		for step = 1, 11 do
			hydration += 0.05
			i:perceive(elf, { body({ hydration = hydration }), pond() })
			i:think(elf, 1.0, step)
			if step == 2 then
				early = belief(i, elf, DRINK).s
			end
		end
		local late = belief(i, elf, DRINK)
		t.ok(early ~= nil, "the belief exists to be narrowed")
		t.ok(late.s < early, "a prediction that keeps being right gets held more tightly")
		t.ok(math.abs(late.v - 0.05) < 0.05, "and stays near the value the world keeps reporting")
	end

	-- Same evidence, one dial.
	do
		local function drift(adaptability: number): number
			local i, elf = world({
				dials = {
					tempo = 1.0,
					caution = 0.1,
					attention = 1.0,
					commitment = 0.1,
					adaptability = adaptability,
				},
			})
			local clock = 1
			for _ = 1, 8 do
				clock = round(i, elf, clock, { hydration = 0.20 }, { hydration = 0.20 })
			end
			return belief(i, elf, DRINK).v
		end
		t.ok(drift(0.9) < drift(0.1), "adaptability decides how fast an action belief is revised")
	end

	-- §09: `believes` is what this species holds about its own actions.
	do
		local i, elf = world({
			believes = {
				drink = { { of = "self", hydration = { 0.05, spread = 0.02 }, after = 1.0 } },
			},
		})
		i:perceive(elf, { body({ hydration = 0.20 }), pond() })
		i:think(elf, 1.0, 1)
		local held = belief(i, elf, DRINK)
		t.ok(held ~= nil, "a believes entry seeds the belief for that action")
		t.near(held.v, 0.05, "and overrides the generic prior the action carries", 1e-6)
	end

	-- The vocalise case: an action with no prediction of its own, given one by the species.
	do
		local i, elf = world({
			expects = { hydration = { 0.90, spread = 0.05 }, anger = { 0.00, spread = 0.05 } },
			believes = {
				mutter = { { of = "self", anger = { -0.50, spread = 0.20 }, after = 1.0 } },
			},
		})
		i:perceive(elf, { body({ hydration = 0.95, anger = 0.90 }) })
		local doing = i:think(elf, 1.0, 1)
		t.eq(doing, "mutter", "an action that predicts nothing can still be chosen on a believes entry")
		t.ok(belief(i, elf, "action|mutter|self|anger") ~= nil, "and it holds a belief about doing so")
	end

	-- A condition the package cannot evaluate must not quietly apply.
	do
		local i, elf = world({
			expects = { hydration = { 0.90, spread = 0.05 }, anger = { 0.00, spread = 0.05 } },
			believes = {
				mutter = {
					{ of = "self", anger = { -0.50, spread = 0.20 }, after = 1.0, when = { target = "blamed" } },
				},
			},
		})
		i:perceive(elf, { body({ hydration = 0.95, anger = 0.90 }) })
		local doing = i:think(elf, 1.0, 1)
		t.ok(doing ~= "mutter", "a belief conditioned on `when` does not apply when the condition fails")
	end
end
