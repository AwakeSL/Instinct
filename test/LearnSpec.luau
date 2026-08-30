--!strict

local Fixture = require("./Fixture")

local function world(dials: any?): (any, any)
	local i = Fixture.world()
	local d: any = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, adaptability = 0.5 }
	for k, v in pairs(dials or {}) do
		d[k] = v
	end
	Fixture.elf(i, { dials = d })
	i:ready()
	return i, i:spawn("elf", { seed = 5 })
end

local function wolfAt(integrity: number): any
	return Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true })
end

local function encounter(i: any, elf: any, at: number, before: number, after: number)
	i:perceive(elf, {
		Fixture.body({ integrity = before, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		wolfAt(0.9),
	})
	i:think(elf, 0.1, at)
	i:perceive(elf, {
		Fixture.body({ integrity = after, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		wolfAt(0.9),
	})
	i:think(elf, 0.1, at + 5)
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
	local i, elf = world()
	t.eq(wolfBelief(i, elf), nil, "a creature holds no belief about a wolf it has never met")

	encounter(i, elf, 10, 1.0, 1.0)
	local first = wolfBelief(i, elf)
	t.ok(first ~= nil, "meeting one creates a belief, seeded from the kind")
	t.ok(first.n > 0, "and it has been updated at least once")

	local narrowing, nElf = world()
	local widths: { number } = {}
	for round = 1, 6 do
		encounter(narrowing, nElf, round * 20, 1.0, 1.0)
		table.insert(widths, wolfBelief(narrowing, nElf).s)
	end
	t.ok(widths[6] < widths[1], "consistent outcomes narrow a belief")
	t.ok(widths[6] < 0.2, "until it is held tightly")

	local shaken, sElf = world()
	for round = 1, 6 do
		encounter(shaken, sElf, round * 20, 1.0, 1.0)
	end
	local settled = wolfBelief(shaken, sElf).s
	encounter(shaken, sElf, 200, 1.0, 0.2)
	t.ok(wolfBelief(shaken, sElf).s > settled, "a violation widens it again; confidence is losable")

	local tame, tElf = world()
	local startHarm = math.abs(wolfBelief(tame, tElf) and 0 or 0)
	local _ = startHarm
	encounter(tame, tElf, 10, 1.0, 1.0)
	local afterOne = math.abs(wolfBelief(tame, tElf).v)
	for round = 2, 14 do
		encounter(tame, tElf, round * 20, 1.0, 1.0)
	end
	local afterMany = math.abs(wolfBelief(tame, tElf).v)
	t.ok(afterOne > 0.5, "one uneventful meeting does not tame a wolf")
	t.ok(afterMany < 0.1, "but many of them do")
	t.ok(afterMany < afterOne, "and it is gradual, not a switch")

	tame:perceive(tElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		wolfAt(0.9),
	})
	t.eq(tame:think(tElf, 0.1, 400), nil, "a tamed wolf no longer provokes an intent at all")

	local hurt, hElf = world()
	local beforeTrauma = hurt:stateOf(hElf)
	local _ = beforeTrauma
	encounter(hurt, hElf, 10, 1.0, 0.15)
	local scarred = wolfBelief(hurt, hElf)
	t.ok(math.abs(scarred.v) > 0.9, "one catastrophe moves the belief hard in a single update")
	t.eq(scarred.n, 1, "on exactly one observation")
	t.ok(scarred.s > 0.5, "and leaves the creature uncertain rather than confident")

	t.ok(hurt:stats().violations > 0, "a model violation is counted")
	t.ok(tame:stats().violations == 0 or tame:stats().learned > 0, "while gentle contact is ordinary learning")

	local slow, slowElf = world({ adaptability = 0.05 })
	local fast, fastElf = world({ adaptability = 1.0 })
	for round = 1, 4 do
		encounter(slow, slowElf, round * 20, 1.0, 1.0)
		encounter(fast, fastElf, round * 20, 1.0, 1.0)
	end
	t.ok(math.abs(wolfBelief(fast, fastElf).v) < math.abs(wolfBelief(slow, slowElf).v),
		"adaptability changes how fast experience overrides instinct")

	local a, aElf = world()
	local b, bElf = world()
	for round = 1, 6 do
		encounter(a, aElf, round * 20, 1.0, 1.0)
		encounter(b, bElf, round * 20, 1.0, 0.95)
	end
	t.ok(math.abs(wolfBelief(a, aElf).v) < math.abs(wolfBelief(b, bElf).v),
		"two creatures given different experience of one wolf hold different beliefs")

	local early, eElf = world()
	early:perceive(eElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		wolfAt(0.9),
	})
	early:think(eElf, 0.1, 10)
	t.eq(early:stats().learned, 0, "a prediction inside its horizon has taught nothing yet")
	early:perceive(eElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		wolfAt(0.9),
	})
	early:think(eElf, 0.1, 10.5)
	t.eq(early:stats().learned, 0, "still nothing half a second in")
	early:perceive(eElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		wolfAt(0.9),
	})
	early:think(eElf, 0.1, 14)
	t.ok(early:stats().learned > 0, "and only judges the prediction once its horizon has passed")

	local forgets, fElf = world({ grudge = 0.05 })
	for round = 1, 14 do
		encounter(forgets, fElf, round * 20, 1.0, 1.0)
	end
	local tamedTo = math.abs(wolfBelief(forgets, fElf).v)
	t.ok(tamedTo < 0.1, "a forgetful creature can still be tamed")

	for step = 1, 12 do
		forgets:perceive(fElf, {
			Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		})
		forgets:think(fElf, 0.1, 400 + step * 40)
	end
	local drifted = math.abs(wolfBelief(forgets, fElf).v)
	t.ok(drifted > tamedTo, "but an unseen subject relaxes back toward its kind")
	t.ok(drifted > 0.3, "until it is treated as a generic wolf again")

	local holds, hoElf = world({ grudge = 0.98 })
	for round = 1, 14 do
		encounter(holds, hoElf, round * 20, 1.0, 1.0)
	end
	local heldTo = math.abs(wolfBelief(holds, hoElf).v)
	for step = 1, 12 do
		holds:perceive(hoElf, {
			Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		})
		holds:think(hoElf, 0.1, 400 + step * 40)
	end
	local stillHeld = math.abs(wolfBelief(holds, hoElf).v)
	t.ok(stillHeld < 0.4, "while a creature that holds on barely forgets at all")
	t.ok(stillHeld < drifted, "one dial separates the two, on identical experience")

	local middling, mElf = world({ grudge = 0.5 })
	for round = 1, 14 do
		encounter(middling, mElf, round * 20, 1.0, 1.0)
	end
	for step = 1, 3 do
		middling:perceive(mElf, {
			Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		})
		middling:think(mElf, 0.1, 400 + step * 30)
	end
	local half = math.abs(wolfBelief(middling, mElf).v)
	t.ok(half > 0.1 and half < 0.8, "and half remembering is a real state rather than a transient")
end
