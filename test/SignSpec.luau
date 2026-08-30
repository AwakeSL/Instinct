--!strict

local Fixture = require("./Fixture")

local function reader(grudge: number): (any, any)
	local i = Fixture.world()
	Fixture.elf(i, {
		reads = { "tally", "smokeMeansFire" },
		feels = { "fear", "anger" },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, adaptability = 0.6, grudge = grudge },
	})
	i:ready()
	return i, i:spawn("elf", { seed = 101 })
end

local function body(): any
	return Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 })
end

local function idle(i: any, elf: any, at: number)
	i:perceive(elf, { body() })
	i:think(elf, 0.5, at)
end

local function readBucket(i: any, elf: any, at: number, count: number)
	i:perceive(elf, { body(), Fixture.seen("bucket1", "bucket", { distance = 2, count = count, at = true }) })
	i:think(elf, 0.5, at)
end

local function tally(i: any, elf: any): any
	return i:beliefs(elf)["sign|village|population"]
end

return function(t: any)
	local i, elf = reader(0.4)
	t.eq(tally(i, elf), nil, "a creature that has never looked knows nothing about the village")

	readBucket(i, elf, 10, 0.7)
	local fresh = tally(i, elf)
	t.ok(fresh ~= nil, "reading the bucket produces a belief about something it cannot see")
	t.ok(math.abs(fresh.value - 0.7) < 0.05, "carrying the count it read")
	t.ok(fresh.spread < 0.2, "held tightly, because it just looked")
	t.ok(i:stats().signsRead > 0, "reading a sign is counted")

	for step = 1, 10 do
		idle(i, elf, 10 + step * 40)
	end
	local faded = tally(i, elf)
	t.ok(faded.spread > fresh.spread, "the count decays out of its head while it is away")
	t.ok(math.abs(faded.value - 0.7) > 0.05, "and drifts off the number it read")

    readBucket(i, elf, 500, 0.7)
	local restored = tally(i, elf)
	t.ok(math.abs(restored.value - 0.7) < 0.05, "looking again restores the meaning")
	t.ok(restored.spread < faded.spread, "and the confidence with it")

	readBucket(i, elf, 520, 1.0)
	readBucket(i, elf, 540, 1.0)
	local lied = tally(i, elf)
	t.ok(lied.value > 0.85, "add stones to the bucket and the creature comes to believe the lie")
	t.ok(lied.spread < 0.2, "confidently, with nothing inside it that could tell")
	t.ok(lied.value > restored.value, "the tampered count overrides what it used to know")

	local blind = Fixture.world()
	Fixture.elf(blind, {
		feels = { "fear", "anger" },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1 },
	})
	blind:ready()
	local bElf = blind:spawn("elf", { seed = 102 })
	blind:perceive(bElf, { body(), Fixture.seen("bucket1", "bucket", { distance = 2, count = 0.7, at = true }) })
	blind:think(bElf, 0.5, 10)
	t.eq(blind:beliefs(bElf)["sign|village|population"], nil,
		"a creature that does not read the sign sees only a bucket")

	local unread = Fixture.world()
	Fixture.elf(unread, {
		reads = { "tally" },
		forms = { "distance", "size", "guardDown", "integrity", "proximity", "closing", "looming" },
		feels = { "fear", "anger" },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1 },
	})
	unread:ready()
	local uElf = unread:spawn("elf", { seed = 103 })
	unread:perceive(uElf, { body(), Fixture.seen("bucket1", "bucket", { distance = 2, count = 0.7, at = true }) })
	unread:think(uElf, 0.5, 10)
	t.eq(unread:beliefs(uElf)["sign|village|population"], nil,
		"and one that cannot form `count` cannot store a count, whatever it is told to read")

	local smoke, sElf = reader(0.9)
	smoke:perceive(sElf, { body(), Fixture.seen("plume", "smoke", { distance = 30, density = 0.8, at = true }) })
	smoke:think(sElf, 0.5, 10)
	local believedFire = smoke:beliefs(sElf)["sign|fire|proximity"]
	t.ok(believedFire ~= nil, "smoke produces a belief about a fire it has never seen")
	t.ok(believedFire.value > 0.7, "at a confidence the density earned")
end
