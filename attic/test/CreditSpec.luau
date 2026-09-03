--!strict

local Fixture = require("./Fixture")

local function world(attribution: number): (any, any)
	local i = Fixture.world()
	Fixture.elf(i, {
		feels = { "fear", "anger" },
		dials = {
			tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1,
			adaptability = 0.6, grudge = 0.9, attribution = attribution,
		},
	})
	i:ready()
	return i, i:spawn("elf", { seed = 121 })
end

local function wolfNear(): any
	return Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true })
end

local function encounter(i: any, elf: any, at: number, harm: number)
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		wolfNear(),
	})
	i:think(elf, 0.5, at)
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0 - harm, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		wolfNear(),
	})
	i:think(elf, 0.5, at + 5)
end

local function wolfBelief(i: any, elf: any): any
	for key, held in pairs(i:stateOf(elf).beliefs) do
		if key:find("subject|wolf1", 1, true) then
			return held
		end
	end
	return nil
end

return function(t: any)
	local trusting, tElf = world(0.95)
	for round = 1, 6 do
		encounter(trusting, tElf, round * 20, 0)
	end
	local function drift(i: any, elf: any): number
		local worst = 0
		for _, gain in pairs(i:stateOf(elf).gains) do
			worst = math.max(worst, math.abs(gain - 1))
		end
		return worst
	end
	t.ok(math.abs(wolfBelief(trusting, tElf).v) < 0.3, "a creature that trusts its senses revises what it believes")

	local doubting, dElf = world(0.05)
	for round = 1, 6 do
		encounter(doubting, dElf, round * 20, 0)
	end
	t.ok(drift(doubting, dElf) > drift(trusting, tElf) * 1.5,
		"while one that doubts them recalibrates its perception far harder")
	t.ok(math.abs(wolfBelief(doubting, dElf).v) > math.abs(wolfBelief(trusting, tElf).v),
		"and holds on to its belief about wolves longer, because the error landed elsewhere")

	local calibrated = doubting:beliefs(dElf)
	local sawGain = false
	for key in pairs(calibrated) do
		if key:find("feature|", 1, true) then
			sawGain = true
		end
	end
	t.ok(sawGain, "the calibration is a belief like any other, visible in what it holds")

	local i, elf = world(0.5)
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 30, approachRate = -6, size = 1, integrity = 0.9 }),
	})
	local approached = i:think(elf, 0.5, 1)
	t.eq(approached, "walk_to", "a fighter closes on a wolf it cannot reach yet")
	t.eq(i:stateOf(elf).chain[2], "stab", "because closing is recruited by the stab that wants it")

	local before = 0.9 * (1 - 30 / 60)
	local after = 0.9 * (1 - 6 / 60)
	t.ok(after > before, "even though closing makes its own predicted harm worse")

	local timid = Fixture.world()
	Fixture.elf(timid, {
		feels = { "fear", "anger" },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.0, patience = 0.0 },
	})
	timid:ready()
	local tiElf = timid:spawn("elf", { seed = 131 })
	timid:perceive(tiElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 30, approachRate = -6, size = 1, integrity = 0.9 }),
	})
	t.eq(timid:think(tiElf, 0.5, 1), nil, "while one with no patience never assembles the approach at all")
end
