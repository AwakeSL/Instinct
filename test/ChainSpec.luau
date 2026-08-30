--!strict

local Fixture = require("./Fixture")

return function(t: any)
	local i = Fixture.world()
	Fixture.elf(i)
	i:ready()
	local elf = i:spawn("elf", { seed = 11 })

	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.2, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 40 }),
	})
	t.eq(i:think(elf, 0.1, 1), "walk_to", "an unmet requirement recruits a settler")

	local state = i:stateOf(elf)
	t.eq(#state.chain, 2, "and the chain has two links")
	t.eq(state.chain[2], "drink", "ending in the action that wanted the requirement")
	t.ok(i:stats().chainsFormed > 0, "a formed chain is counted")

	local why = i:why(elf)
	t.eq(why.doing.action, "walk_to", "why reports the head of the chain")
	t.eq(why.chain[2], "drink", "and the whole chain")
	t.ok(#why.considered > 0, "and what it considered")

	local reachable = Fixture.world()
	Fixture.elf(reachable)
	reachable:ready()
	local near = reachable:spawn("elf", { seed = 12 })
	reachable:perceive(near, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.2, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 1, at = true }),
	})
	t.eq(reachable:think(near, 0.1, 1), "drink", "a met requirement needs no settler")
	t.eq(#reachable:stateOf(near).chain, 1, "and the chain is one link")

	local stuck = Fixture.world()
	Fixture.elf(stuck)
	stuck:ready()
	local sElf = stuck:spawn("elf", { seed = 13 })
	stuck:perceive(sElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }),
		Fixture.seen("wolf1", "wolf", { distance = 4, approachRate = -6, size = 1, integrity = 0.9 }),
	})
	local ok = pcall(function()
		stuck:think(sElf, 0.1, 1)
	end)
	t.ok(ok, "an unsatisfiable requirement terminates rather than looping")

	local hasty = Fixture.world()
	Fixture.elf(hasty, { dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, patience = 0.0 } })
	hasty:ready()
	local hElf = hasty:spawn("elf", { seed = 21 })
	hasty:perceive(hElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.2, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 40 }),
	})
	t.eq(hasty:think(hElf, 0.1, 1), nil, "no patience means no chain is extended at all")

	local patient = Fixture.world()
	Fixture.elf(patient, { dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, patience = 1.0 } })
	patient:ready()
	local pElf = patient:spawn("elf", { seed = 22 })
	patient:perceive(pElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.2, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 40 }),
	})
	t.eq(patient:think(pElf, 0.1, 1), "walk_to", "while patience extends it, same world")

	local held = Fixture.world()
	Fixture.elf(held, { dials = { tempo = 1.0, caution = 0.1, attention = 2.0, commitment = 0.9, patience = 1.0 } })
	held:ready()
	local dElf = held:spawn("elf", { seed = 23 })
	held:perceive(dElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.2, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 1, at = true }),
	})
	t.eq(held:think(dElf, 0.1, 1), "drink", "it starts drinking")
	local abandonedBefore = held:stats().chainsAbandoned
	held:perceive(dElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.45, safety = 1.0 }, { blade = true }),
		Fixture.seen("pond", "water", { distance = 1, at = true }),
		Fixture.seen("wolf1", "wolf", { distance = 40, approachRate = -1, size = 1, integrity = 0.9, at = true }),
	})
	t.eq(held:think(dElf, 0.1, 2), "drink", "a distant wolf is not worth abandoning a drink for")
	t.eq(held:stats().chainsAbandoned, abandonedBefore, "and nothing was abandoned")

	held:perceive(dElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.45, safety = 1.0 }, { blade = true }),
		Fixture.seen("pond", "water", { distance = 1, at = true }),
		Fixture.seen("wolf1", "wolf", { distance = 3, approachRate = -8, size = 1, integrity = 0.9, at = true }),
	})
	t.eq(held:think(dElf, 0.1, 3), "stab", "a wolf at three studs is")
	t.ok(held:stats().chainsAbandoned > abandonedBefore, "and abandoning the chain is counted")

	local steep = Fixture.world()
	Fixture.elf(steep, {
		dials = {
			tempo = 1.0,
			attention = 1.0,
			commitment = 0.1,
			patience = 1.0,
			caution = { 0.1, { "downside", times = 1.6 } },
		},
	})
	steep:ready()
	local stElf = steep:spawn("elf", { seed = 24 })
	steep:perceive(stElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.55, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 1, at = true }),
	})
	t.eq(steep:think(stElf, 0.1, 1), "drink", "a small shortfall clears a stakes-scaled threshold")
	local shallowState = steep:stateOf(stElf)
	shallowState.doing = nil
	steep:perceive(stElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.05, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 1, at = true }),
	})
	local big = steep:think(stElf, 0.1, 2)
	t.eq(big, nil, "while a large one raises the bar past what it can be sure of")
	t.ok(steep:stats().belowThreshold > 0, "an expression-shaped dial resolves against what it governs")
end
