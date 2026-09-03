--!strict

local Fixture = require("./Fixture")

local function watcher(capacity: number, extra: any?): (any, any)
	local i = Fixture.world()
	local d: any = {
		tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1,
		adaptability = 0.6, grudge = 0.9, capacity = capacity,
	}
	for k, v in pairs(extra or {}) do
		d[k] = v
	end
	Fixture.elf(i, { feels = { "fear", "anger" }, dials = d })
	i:ready()
	return i, i:spawn("elf", { seed = 141 })
end

local function body(): any
	return Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true })
end

local function seesFleeing(i: any, elf: any, at: number, strength: number)
	i:perceive(elf, {
		body(),
		Fixture.seen("hound1", "hound", { distance = 20, approachRate = 0, size = 1, integrity = 0.9 }),
		{
			subject = "friend",
			kind = "elf",
			via = "sight",
			raw = { distance = 8, integrity = 1.0, size = 1, approachRate = 0 },
			reacting = { to = "hound1", kind = "hound", as = strength },
		},
	})
	i:think(elf, 0.5, at)
end

local function houndBelief(i: any, elf: any): any
	for key, held in pairs(i:stateOf(elf).beliefs) do
		if key:find("subject|hound1", 1, true) then
			return held
		end
	end
	return nil
end

return function(t: any)
	local i, elf = watcher(0.8)
	t.eq(houndBelief(i, elf), nil, "a creature has no opinion about a hound it has never met")

	seesFleeing(i, elf, 10, 0.8)
	local learned = houndBelief(i, elf)
	t.ok(learned ~= nil, "watching a companion bolt from something teaches it about that thing")
	t.ok(learned.v < -0.3, "and what it learned is that the hound is dangerous")
	t.ok(i:stats().learnedSocially > 0, "learning from another creature is counted")

	local kindLevel = i:stateOf(elf).beliefs["kind|hound|self|integrity"]
	t.ok(kindLevel ~= nil and kindLevel.v < 0, "it generalises to hounds, not only to that hound")
	t.ok(math.abs(kindLevel.v) < math.abs(learned.v), "but far more slowly than it learns the individual")

	local slime = Fixture.world()
	slime:species("slime", {
		kind = "slime",
		parts = { mass = 1 },
		senses = { body = {}, sight = {} },
		forms = {},
		expects = { integrity = { 1.0, spread = 0.3 } },
		dials = { tempo = 1.0, capacity = 0.0 },
	})
	slime:ready()
	local sId = slime:spawn("slime", { seed = 9 })
	slime:perceive(sId, {
		Fixture.body({ integrity = 1.0 }),
		{
			subject = "friend",
			kind = "slime",
			via = "sight",
			raw = { distance = 8 },
			reacting = { to = "hound1", kind = "hound", as = 0.8 },
		},
	})
	slime:think(sId, 0.5, 1)
	t.eq(slime:stats().learnedSocially, 0, "a creature with no capacity models no minds at all")

	local wary, wElf = watcher(0.8)
	for round = 1, 4 do
		wary:perceive(wElf, {
			body(),
			Fixture.seen("friend", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
		})
		wary:think(wElf, 0.5, round * 20)
		wary:perceive(wElf, {
			Fixture.body({ integrity = 0.6, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
			Fixture.seen("friend", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
		})
		wary:think(wElf, 0.5, round * 20 + 5)
	end
	seesFleeing(wary, wElf, 200, 0.8)
	local fromEnemy = houndBelief(wary, wElf)
	local fromFriend = houndBelief(i, elf)
	t.ok(fromEnemy == nil or math.abs(fromEnemy.v) < math.abs(fromFriend.v),
		"a creature takes less from something it has learned to dread")

	local wrong, wrElf = watcher(0.8)
	seesFleeing(wrong, wrElf, 10, 0.9)
	t.ok(houndBelief(wrong, wrElf).v < -0.3,
		"a companion panicking at nothing propagates a belief that is simply false")

	local scene = Fixture.world()
	Fixture.elf(scene, {
		feels = { "fear", "anger" },
		instinct = {
			{
				about = "hound",
				predicts = {
					{
						of = "self",
						integrity = { -0.90, by = { "proximity", "boldness", "integrity" }, spread = 0.20 },
						after = { 2.0, spread = 1.0 },
					},
				},
			},
		},
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, capacity = 0.8 },
	})
	scene:ready()
	local trickster, trElf = scene, scene:spawn("elf", { seed = 151 })
	trickster:perceive(trElf, {
		body(),
		Fixture.seen("hound1", "hound", { distance = 5, boldness = 0.9, integrity = 0.9, size = 1, at = true }),
	})
	trickster:think(trElf, 0.5, 1)
	local sawFeint = false
	for _, row in trickster:why(trElf).considered do
		if row.action == "feint" then
			sawFeint = true
		end
	end
	t.ok(sawFeint, "an action that works on another creature's mind is weighed like any other")

	local feintRow, stabRow = nil, nil
	for _, row in trickster:why(trElf).considered do
		if row.action == "feint" then
			feintRow = row
		elseif row.action == "stab" then
			stabRow = row
		end
	end
	t.ok(feintRow.cancels > 0, "frightening a hound out of its boldness genuinely reduces the threat")
	t.ok(stabRow ~= nil, "and it is weighed against simply hurting it")
	t.ok(trickster:think(trElf, 0.5, 2) ~= nil, "the creature picks one of them on the same terms")
end
