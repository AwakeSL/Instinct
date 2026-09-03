--!strict

local Fixture = require("./Fixture")

local function world(grudge: number): (any, any)
	local i = Fixture.world()
	Fixture.elf(i, {
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, adaptability = 0.5, grudge = grudge },
	})
	i:ready()
	return i, i:spawn("elf", { seed = 41 })
end

local function idle(i: any, elf: any, at: number)
	i:perceive(elf, { Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }) })
	i:think(elf, 0.1, at)
end

local function look(i: any, elf: any, at: number)
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }),
		Fixture.seen("cube", "thing", { distance = 3 }),
	})
	i:think(elf, 0.1, at)
end

local function gone(i: any, elf: any, at: number): number
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }),
		{ subject = "cube", absent = true },
	})
	i:think(elf, 0.1, at)
	return i:surprise(elf)
end

local function presence(i: any, elf: any): any
	return i:beliefs(elf, "cube")["presence|cube"]
end

return function(t: any)
	local i, elf = world(0.9)
	t.eq(presence(i, elf), nil, "a creature holds no belief about a cube it has never seen")

	look(i, elf, 10)
	local seen = presence(i, elf)
	t.ok(seen ~= nil, "seeing one creates a belief that it is there")
	t.ok(seen.value > 0.9, "held confidently")
	t.ok(seen.spread < 0.1, "and tightly")

	idle(i, elf, 20)
	idle(i, elf, 30)
	local unwatched = presence(i, elf)
	t.ok(unwatched.value > 0.8, "the belief keeps running while the door is shut")

	local shock = gone(i, elf, 40)
	t.ok(shock > 5, "opening the door on an empty room is a large surprise")
	t.ok(presence(i, elf).value < 0.5, "and the creature stops believing the cube is there")

	local forgetful, fElf = world(0.05)
	look(forgetful, fElf, 10)
	for step = 1, 8 do
		idle(forgetful, fElf, 10 + step * 30)
	end
	local faded = presence(forgetful, fElf)
	t.ok(faded.value < 0.75, "a forgetful creature has already let the cube go")
	t.ok(faded.spread > 0.2, "and is no longer sure either way")
	local mildShock = gone(forgetful, fElf, 400)
	t.ok(mildShock < shock, "so the empty room barely surprises it")

	local holds, hElf = world(0.98)
	look(holds, hElf, 10)
	for step = 1, 8 do
		idle(holds, hElf, 10 + step * 30)
	end
	local kept = presence(holds, hElf)
	t.ok(kept.value > 0.85, "while a creature that holds on still expects it")
	local bigShock = gone(holds, hElf, 400)
	t.ok(bigShock > mildShock, "and is properly shocked to find it gone")

	t.ok(holds:stats().violations > 0, "a model violation is counted")
	t.ok(forgetful:stats().violations <= holds:stats().violations,
		"object permanence is not a switch; it is how long a belief survives without evidence")
end
