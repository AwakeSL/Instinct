--!strict

local Fixture = require("./Fixture")

local function world(insight: number): (any, any)
	local i = Fixture.world()
	Fixture.elf(i, {
		feels = { "fear", "anger" },
		expects = {
			integrity = { 1.00, spread = 0.05 },
			energy = { 0.70, spread = 0.20 },
			hydration = { 0.90, spread = 0.15 },
			safety = { 1.00, spread = 0.10 },
			wealth = { 0.90, spread = 0.10 },
		},
		dials = {
			tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1,
			adaptability = 0.5, capacity = 0.9, grudge = 0.97, attribution = 0.9, insight = insight,
		},
	})
	i:ready()
	return i, i:spawn("elf", { seed = 161 })
end

local function body(wealth: number): any
	return Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0, wealth = wealth })
end

local function flare(bright: number): any
	return Fixture.seen("flare1", "flare", { distance = 20, at = true, density = bright, count = 0.5 })
end

local function robbery(i: any, elf: any, at: number, bright: number)
	i:perceive(elf, { body(0.9), flare(bright) })
	i:think(elf, 0.5, at)
	i:perceive(elf, { body(0.3) })
	i:think(elf, 0.5, at + 10)
end

local function association(i: any, elf: any): any
	for _, entry in i:stateOf(elf).learned do
		if entry.about == "flare" then
			return entry
		end
	end
	return nil
end

return function(t: any)
	local i, elf = world(0.6)

	robbery(i, elf, 10, 0.95)
	local first = association(i, elf)
	t.ok(first ~= nil, "one theft after a flare forms a plain association")
	t.eq(first.refined, nil, "with nothing more specific than the flare itself")

	robbery(i, elf, 200, 0.92)
	local refined = association(i, elf)
	t.ok(refined.refined ~= nil, "a second theft lets it find what the two had in common")
	t.eq(refined.refined, "density", "and it settles on the feature that was high both times")
	t.ok(i:stats().acquired > 0, "acquiring a sharper predictor is counted")

	i:perceive(elf, { body(0.9), flare(0.95) })
	local alarmed = i:think(elf, 0.5, 400)
	t.ok(alarmed ~= nil, "a bright flare still worries it")

	i:perceive(elf, { body(0.9), flare(0.02) })
	local calm = i:think(elf, 0.5, 500)
	t.eq(calm, nil, "while a dim one no longer does, which nobody authored")

	local blunt, bElf = world(0.0)
	robbery(blunt, bElf, 10, 0.95)
	robbery(blunt, bElf, 200, 0.92)
	t.eq(association(blunt, bElf).refined, nil,
		"a creature with no insight never looks for a sharper way of seeing")
	blunt:perceive(bElf, { body(0.9), flare(0.02) })
	t.ok(blunt:think(bElf, 0.5, 400) ~= nil, "so a dim flare frightens it exactly as much")

	local fickle, fElf = world(0.6)
	robbery(fickle, fElf, 10, 0.95)
	robbery(fickle, fElf, 200, 0.10)
	local nothingCommon = association(fickle, fElf)
	t.eq(nothingCommon.refined, nil,
		"two thefts with nothing in common yield no conjunction, because there was none to find")
end
