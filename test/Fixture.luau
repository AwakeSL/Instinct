--!strict

local Instinct = require("../src")

local Fixture = {}

function Fixture.world(): any
	local i = Instinct.new({ seed = 4242 }):defaults()

	i:quantity("integrity", { range = { 0, 1 } })
	i:quantity("energy", { range = { 0, 1 } })
	i:quantity("hydration", { range = { 0, 1 } })
	i:quantity("safety", { range = { 0, 1 } })
	i:quantity("wealth", { range = { 0, 1 } })
	i:quantity("boldness", { range = { 0, 1 } })

	i:role("self")
	i:role("target")
	i:role("other")

	i:part("arms")
	i:part("legs")
	i:part("head")
	i:part("eyes")
	i:part("mass")

	i:sense("sight", { needs = "eyes", reliable = { by = { "light" } } })
	i:sense("touch", {})
	i:sense("body", {})

	i:feature("distance", { from = "sight" })
	i:feature("size", { from = "sight" })
	i:feature("guardDown", { from = "sight" })
	i:feature("integrity", { from = "sight" })
	i:feature("count", { from = "sight" })
	i:feature("density", { from = "sight" })
	i:feature("boldness", { from = "sight" })
	i:feature("proximity", { from = "sight", is = { "distance", inverted = { 60, spread = 6 } } })
	i:feature("closing", { from = "sight", is = { "approachRate", times = { -0.125, spread = 0.02 } } })
	i:feature("looming", { is = { "proximity", times = "size" } })

	i:kind("thing")
	i:kind("animal", { is = { "thing" } })
	i:kind("threat", { is = { "thing" }, stage = 1 })
	i:kind("drinkable", { is = { "thing" }, stage = 2 })
	i:kind("wolf", { is = { "animal", "threat" } })
	i:kind("water", { is = { "drinkable" } })
	i:kind("flare", { is = { "thing" } })
	i:kind("bucket", { is = { "thing" } })
	i:kind("hound", { is = { "animal", "threat" } })
	i:kind("smoke", { is = { "thing" } })
	i:kind("fire", { is = { "threat" } })
	i:kind("elf", { is = { "animal" } })
	i:kind("slime", { is = { "animal" } })

	i:skill("blade")
	i:skill("unarmed")
	i:skill("archery")

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

	i:emotion("curiosity", {
		from = { spread = "high", salience = "low" },
		decays = 0.4,
		modulates = { patience = 1.3 },
	})

	i:action("watch", {
		requires = { at = "thing" },
		occupies = { eyes = 2 },
		predicts = { { of = "self", curiosity = { -0.60, spread = 0.10 }, after = { 1.0, spread = 0.5 } } },
		costs = { energy = 0.001 },
	})

	i:action("walk_to", {
		occupies = { legs = 2 },
		settles = { "at" },
		costs = { energy = 0.004 },
	})

	i:action("drink", {
		requires = { at = "drinkable" },
		occupies = { head = 1 },
		predicts = { { of = "self", hydration = { 0.80, spread = 0.10 }, after = { 4.0, spread = 2.0 } } },
		costs = { energy = 0.010 },
	})

	i:action("stab", {
		requires = { holding = "blade", at = "threat" },
		occupies = { arms = 1 },
		skill = "blade",
		predicts = { { of = "target", integrity = { -0.70, spread = 0.20 }, after = { 0.4, spread = 0.1 } } },
		costs = { energy = 0.050 },
	})

	i:action("punch", {
		requires = { at = "threat" },
		occupies = { arms = 1 },
		skill = "unarmed",
		predicts = { { of = "target", integrity = { -0.20, spread = 0.15 }, after = { 0.3, spread = 0.1 } } },
		costs = { energy = 0.040 },
	})

	i:action("shoot", {
		requires = { holding = "bow", at = "threat" },
		occupies = { arms = 2, eyes = 1 },
		skill = "archery",
		predicts = { { of = "target", integrity = { -0.55, spread = 0.20 }, after = { 0.6, spread = 0.2 } } },
		costs = { energy = 0.030 },
	})

	i:sign("tally", {
		seeing = { kind = "bucket", feature = "count" },
		tells = { subject = "village", quantity = "population" },
	})

	i:sign("smokeMeansFire", {
		seeing = { kind = "smoke", feature = "density" },
		tells = { kind = "fire", quantity = "proximity" },
	})

	i:action("feint", {
		requires = { at = "threat" },
		occupies = { arms = 1 },
		skill = "blade",
		predicts = { { of = "target", boldness = { -0.60, spread = 0.15 }, after = { 0.5, spread = 0.2 } } },
		costs = { energy = 0.010 },
	})

	i:action("hoard", {
		occupies = { arms = 2 },
		predicts = { { of = "self", wealth = { 0.30, spread = 0.08 }, after = { 1.0, spread = 0.5 } } },
		costs = { energy = 0.004 },
	})

	i:action("guard", {
		occupies = { arms = 2 },
		predicts = { { of = "self", safety = { 0.20, spread = 0.05 } } },
		costs = { energy = 0.002 },
	})

	return i
end

function Fixture.elf(i: any, extra: any?)
	local decl: any = {
		kind = "elf",
		parts = { arms = 2, legs = 2, head = 1, eyes = 2 },
		senses = { sight = { range = 60 }, body = {} },
		forms = { "distance", "size", "guardDown", "integrity", "count", "density", "boldness", "proximity", "closing", "looming" },
		skills = { blade = 0.6, unarmed = 0.3 },
		feels = { "fear", "anger" },
		expects = {
			integrity = { 1.00, spread = 0.05 },
			energy = { 0.70, spread = 0.20 },
			hydration = { 0.90, spread = 0.15 },
			safety = { 1.00, spread = 0.10 },
		},
		instinct = {
			{
				about = "wolf",
				predicts = {
					{
						of = "self",
						integrity = { -0.90, by = { "proximity", "closing", "integrity" }, spread = 0.20 },
						after = { 3.0, spread = 2.0 },
					},
				},
			},
		},
		dials = {
			tempo = 1.0,
			caution = 0.1,
			attention = 1.0,
			commitment = 0.1,
		},
	}
	for key, value in pairs(extra or {}) do
		decl[key] = value
	end
	i:species("elf", decl)
	return i
end

function Fixture.body(raw: any, holding: any?): any
	return { via = "body", raw = raw, holding = holding }
end

function Fixture.seen(subject: any, kind: string, raw: any, confidence: number?): any
	return { subject = subject, kind = kind, confidence = confidence or 1, via = "sight", raw = raw }
end

return Fixture
