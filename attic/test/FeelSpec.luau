--!strict

local Fixture = require("./Fixture")

local function world(extra: any?): (any, any)
	local i = Fixture.world()
	local d: any = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.6, adaptability = 0.5 }
	for k, v in pairs((extra or {}).dials or {}) do
		d[k] = v
	end
	local decl: any = { dials = d }
	if (extra or {}).skills ~= nil then
		decl.skills = extra.skills
	end
	Fixture.elf(i, decl)
	i:ready()
	return i, i:spawn("elf", { seed = 51 })
end

local function facedWith(i: any, elf: any, at: number, holding: any): string?
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, holding),
		Fixture.seen("wolf1", "wolf", { distance = 5, approachRate = -5, size = 1, integrity = 0.9, at = true }),
	})
	return i:think(elf, 0.5, at)
end

local function feeling(i: any, elf: any, name: string): number
	return i:stateOf(elf).level[name] or 0
end

return function(t: any)
	local armed, aElf = world()
	facedWith(armed, aElf, 10, { blade = true })
	t.ok(feeling(armed, aElf, "anger") > 0, "a threat it can act on makes it angry")
	t.ok(feeling(armed, aElf, "fear") == 0, "and not afraid")

	local bare, bElf = world()
	facedWith(bare, bElf, 10, {})
	t.ok(feeling(bare, bElf, "fear") > 0, "the same wolf with nothing to fight it with is frightening")
	t.ok(feeling(bare, bElf, "anger") == 0, "and not infuriating")

	t.ok(armed:stateOf(aElf).efficacy > 0.33, "efficacy is high when it can act on the cause")
	t.ok(bare:stateOf(bElf).efficacy < 0.33, "and low when it cannot")

	local calm, cElf = world()
	local restTempo = calm:stateOf(cElf).dial("tempo")
	facedWith(calm, cElf, 10, {})
	local alarmedTempo = calm:stateOf(cElf).dial("tempo")
	t.ok(alarmedTempo > restTempo, "fear makes a creature deliberate more often")

	local grip, gElf = world()
	local restHold = grip:stateOf(gElf).dial("commitment")
	facedWith(grip, gElf, 10, {})
	t.ok(grip:stateOf(gElf).dial("commitment") < restHold, "and loosens its grip on whatever it was doing")

	local bold, boElf = world()
	local restCaution = bold:stateOf(boElf).dial("caution")
	facedWith(bold, boElf, 10, { blade = true })
	t.ok(bold:stateOf(boElf).dial("caution") < restCaution, "while anger makes it reckless")

	local raw = bold:stateOf(boElf).dial("caution", { raw = true })
	t.ok(raw > bold:stateOf(boElf).dial("caution"), "authored and effective are different numbers")

	local fades, fElf = world()
	facedWith(fades, fElf, 10, {})
	local peak = feeling(fades, fElf, "fear")
	for step = 1, 6 do
		fades:perceive(fElf, { Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }) })
		fades:think(fElf, 0.5, 10 + step)
	end
	t.ok(feeling(fades, fElf, "fear") < peak, "fear decays once the wolf is gone")

	local slime = Fixture.world()
	slime:species("slime", {
		kind = "slime",
		parts = { mass = 1 },
		senses = { body = {} },
		forms = {},
		expects = { integrity = { 1.0, spread = 0.3 } },
		dials = { tempo = 1.0 },
	})
	slime:ready()
	local sId = slime:spawn("slime", { seed = 9 })
	slime:perceive(sId, { Fixture.body({ integrity = 0.2 }) })
	slime:think(sId, 0.5, 1)
	t.eq(slime:stateOf(sId).level.fear, nil, "a slime cannot be afraid, whatever happens to it")
	t.eq(#slime:stateOf(sId).feels, 0, "because absence in `feels` is structural")

	local frozen = Fixture.world()
	Fixture.elf(frozen, {
		skills = { blade = 0.05, unarmed = 0.05 },
		expects = {
			integrity = { 1.00, spread = 0.05 },
			energy = { 0.70, spread = 0.20 },
			hydration = { 0.90, spread = 0.15 },
			safety = { 1.00, spread = 0.10 },
		},
		dials = { tempo = 1.0, attention = 1.0, commitment = 0.1, caution = 0.95 },
	})
	frozen:ready()
	local frElf = frozen:spawn("elf", { seed = 61 })
	frozen:perceive(frElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 4, approachRate = -6, size = 1, integrity = 0.9, at = true }),
	})
	t.eq(frozen:think(frElf, 0.5, 1), nil, "a steep caution and wide spreads produce a creature that acts on nothing")
	t.ok(frozen:stats().belowThreshold > 0, "and freezing is counted, so it is not mistaken for having nothing to do")

	local sure = Fixture.world()
	Fixture.elf(sure, {
		skills = { blade = 0.15, unarmed = 0.3 },
		dials = { tempo = 1.0, attention = 1.0, commitment = 0.1, caution = 0.2 },
	})
	sure:ready()
	local braggart = sure:spawn("elf", { seed = 71, selfImage = { skill = { 0.95, spread = 0.04 } } })
	local honest = sure:spawn("elf", { seed = 72 })
	local function meetWolf(who: any)
		sure:perceive(who, {
			Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
			Fixture.seen("wolf1", "wolf", { distance = 5, approachRate = -5, size = 1, integrity = 0.9, at = true }),
		})
		return sure:think(who, 0.5, 1)
	end
	meetWolf(braggart)
	meetWolf(honest)
	local function stabConfidence(who: any): number
		for _, row in sure:why(who).considered do
			if row.action == "stab" then
				return row.confidence
			end
		end
		return 0
	end
	t.ok(stabConfidence(braggart) > stabConfidence(honest) * 2,
		"a false self image makes a creature certain of a blade it is bad with")
	t.eq(sure:stateOf(braggart).skills.blade, sure:stateOf(honest).skills.blade,
		"while they are exactly as competent as each other")

	local curious = Fixture.world()
	Fixture.elf(curious, {
		feels = { "fear", "anger", "curiosity" },
		expects = {
			integrity = { 1.00, spread = 0.05 },
			energy = { 0.70, spread = 0.20 },
			hydration = { 0.90, spread = 0.15 },
			safety = { 1.00, spread = 0.10 },
			curiosity = { 0.00, spread = 0.45 },
		},
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.6, adaptability = 0.5 },
	})
	curious:ready()
	local nosy, nElf = curious, curious:spawn("elf", { seed = 81 })
	nosy:perceive(nElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }),
		Fixture.seen("oddity", "thing", { distance = 3, at = true }),
	})
	local drawn = nosy:think(nElf, 0.5, 1)
	t.ok(feeling(nosy, nElf, "curiosity") > 0, "an unfamiliar harmless thing raises curiosity")
	t.eq(drawn, "watch", "and the creature goes and looks at it")

	local torn, tElf = nosy, nosy:spawn("elf", { seed = 82 })
	torn:perceive(tElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("oddity", "thing", { distance = 3, at = true }),
		Fixture.seen("wolf1", "wolf", { distance = 4, approachRate = -6, size = 1, integrity = 0.9, at = true }),
	})
	local chose = torn:think(tElf, 0.5, 1)
	t.ok(chose ~= "watch", "real stakes stop it investigating")
	t.eq(chose, "stab", "and it attends to the wolf instead")

	local why = torn:why(tElf)
	t.eq(why.because.quantity, "integrity", "salience decides what it thinks about, not surprise")
end
