--!strict

local Fixture = require("./Fixture")

local function world(): (any, any)
	local i = Fixture.world()
	Fixture.elf(i, {
		feels = { "fear", "anger" },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, adaptability = 0.6, grudge = 0.9 },
	})
	i:ready()
	return i, i:spawn("elf", { seed = 111 })
end

local function meet(i: any, elf: any, at: number, hurtBy: number)
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
	})
	i:think(elf, 0.5, at)
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0 - hurtBy, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
	})
	i:think(elf, 0.5, at + 5)
end

local function wolfPrior(model: any): number
	for _, entry in model.instinct do
		if entry.about == "wolf" then
			for _, predicted in entry.predicts do
				if predicted.integrity ~= nil then
					return predicted.integrity[1]
				end
			end
		end
	end
	return 0
end

return function(t: any)
	local i, elf = world()
	local fresh = i:extract(elf)
	t.ok(fresh ~= nil, "a creature can be extracted the moment it is born")
	t.ok(math.abs(wolfPrior(fresh) + 0.9) < 0.01, "and carries the priors it was authored with")

	for round = 1, 14 do
		meet(i, elf, round * 20, 0)
	end
	local veteran = i:extract(elf)
	t.ok(math.abs(wolfPrior(veteran)) < math.abs(wolfPrior(fresh)),
		"a lifetime of harmless wolves shows up in what it would pass on")

	i:species("veteran_elf", veteran)
	i:ready()
	local child = i:spawn("veteran_elf", { seed = 222 })
	t.ok(child ~= nil, "an extracted model is a species declaration and spawns")

	i:perceive(child, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
	})
	t.eq(i:think(child, 0.5, 1), nil, "a child of a tamed lineage is born unbothered by wolves")

	local plain = i:spawn("elf", { seed = 333 })
	i:perceive(plain, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
	})
	t.ok(i:think(plain, 0.5, 1) ~= nil, "while one of the original stock still reacts")

	local scarred, sElf = world()
	meet(scarred, sElf, 10, 0.85)
	local subjectBeliefs = 0
	for key in pairs(scarred:stateOf(sElf).beliefs) do
		if key:find("subject|wolf1", 1, true) then
			subjectBeliefs += 1
		end
	end
	t.ok(subjectBeliefs > 0, "it holds a belief about the particular wolf that hurt it")
	local passed = scarred:extract(sElf)
	local carried = false
	for _, entry in passed.instinct do
		if tostring(entry.about):find("wolf1", 1, true) then
			carried = true
		end
	end
	t.eq(carried, false, "but a lineage inherits dispositions, not memories of individuals")

	local exact = i:extract(elf, nil, { as = "individual" })
	t.eq(type(exact.dials.caution), "number", "extracting an individual pins its dials exactly")
	t.eq(type(veteran.dials.caution), "table", "while extracting a species widens them back into ranges")

	local partial = i:extract(elf, { "believes", "skills" })
	t.eq(partial.expects, nil, "selective extraction leaves out what it was not asked for")
	t.ok(partial.skills ~= nil, "and keeps what it was")
end
