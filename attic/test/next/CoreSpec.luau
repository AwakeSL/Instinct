--!strict

local Instinct = require("../../next")

-- A creature with eyes, in a room. It has no preferences at all -- nothing it wants, nothing it can
-- do. Everything it learns here it learns for no reason beyond having been wrong.
local function world(predicts: any?): (any, any)
	local i = Instinct.new({ seed = 1 }):defaults()
	i:sense("sight", {})
	i:sense("body", {})
	i:reading("colour", { from = "sight" })
	i:reading("size", { from = "sight" })
	i:reading("fullness", { from = "body" })
	i:kind("thing")
	i:kind("room", { is = { "thing" } })
	i:species("watcher", {
		kind = "watcher",
		senses = { sight = {}, body = {} },
		forms = { "colour", "size" },
		predicts = predicts or {},
		dials = { adaptability = 0.7, grudge = 0.9 },
	})
	return i, i:spawn("watcher")
end

local function look(i: any, who: any, colour: number, clock: number)
	i:perceive(who, { { subject = "theRoom", kind = "room", via = "sight", raw = { colour = colour } } })
	i:tick(who, 0.5, clock)
end

return function(t: any)
	-- Perception makes an estimate, and it is held rather than passed through.
	do
		local i, who = world()
		look(i, who, 0.2, 1)
		local value = i:estimate(who, "theRoom", "colour")
		t.near(value, 0.2, "what a sense reports becomes what the creature holds", 0.01)
	end

	-- The point of the rebuild: it learns about something it has no preference about. There is no
	-- `wants` here at all, so under the old design nothing could have produced an error and nothing
	-- could have been learned.
	do
		local i, who = world({
			{ about = "room", reads = { colour = { 0.2, spread = 0.15 } }, after = 1 },
		})
		local clock = 1
		for _ = 1, 10 do
			clock += 1
			look(i, who, 0.8, clock) -- it is red, and the creature expected blue
		end
		local held = i:believes(who, 1, "theRoom")
		t.ok(held ~= nil, "predicting something creates a belief about it")
		t.ok(held.n > 1, "which is checked against the world more than once")
		t.ok(held.v > 0.5, "and moves toward what the world actually keeps reporting")
		t.ok(i:stats().learned > 1, "with nothing wanted, nothing needed, and nothing to gain")
	end

	-- A prediction that keeps being right is held more tightly.
	do
		local i, who = world({
			{ about = "room", reads = { colour = { 0.8, spread = 0.25 } }, after = 1 },
		})
		local clock = 1
		look(i, who, 0.8, clock)
		clock += 1
		look(i, who, 0.8, clock)
		local early = i:believes(who, 1, "theRoom").s
		for _ = 1, 10 do
			clock += 1
			look(i, who, 0.8, clock)
		end
		t.ok(i:believes(who, 1, "theRoom").s < early, "being right repeatedly narrows a belief")
	end

	-- Absence widens. Object permanence, without anything arranged for it.
	do
		local i, who = world()
		look(i, who, 0.2, 1)
		local _, before = i:estimate(who, "theRoom", "colour")
		for step = 1, 12 do
			i:perceive(who, {})
			i:tick(who, 0.5, 1 + step * 0.5)
		end
		local value, after = i:estimate(who, "theRoom", "colour")
		t.ok(value ~= nil, "what it cannot see it still holds")
		t.ok(after > before * 1.5, "less and less certainly, the longer it goes unseen")
	end

	-- A derived reading is an idea built out of other readings.
	do
		local i = Instinct.new():defaults()
		i:sense("sight", {})
		i:reading("distance", { from = "sight" })
		i:reading("size", { from = "sight" })
		i:reading("looming", { is = { "distance", times = "size" } })
		i:kind("thing")
		i:species("watcher", { senses = { sight = {} }, forms = { "looming" } })
		local who = i:spawn("watcher")
		i:perceive(who, {
			{ subject = "it", kind = "thing", via = "sight", raw = { distance = 0.5, size = 0.4 } },
		})
		i:tick(who, 0.5, 1)
		local value = i:estimate(who, "it", "looming")
		t.near(value, 0.2, "a reading may be built from other readings", 0.01)
	end

	-- Temporal operators: change-over-time is expressible at all, which it was not before.
	do
		local i = Instinct.new():defaults()
		i:sense("sight", {})
		i:reading("distance", { from = "sight" })
		i:reading("closing", { is = { "distance", delta = 0 } })
		i:kind("thing")
		i:species("watcher", { senses = { sight = {} }, forms = { "closing" } })
		local who = i:spawn("watcher")

		i:perceive(who, { { subject = "it", kind = "thing", via = "sight", raw = { distance = 1.0 } } })
		i:tick(who, 0.5, 1)
		t.eq(i:estimate(who, "it", "closing"), nil, "change is not something a single moment has")

		i:perceive(who, { { subject = "it", kind = "thing", via = "sight", raw = { distance = 0.5 } } })
		i:tick(who, 0.5, 2)
		local rate = i:estimate(who, "it", "closing")
		t.ok(rate ~= nil, "but two moments have it")
		t.ok(rate < 0, "and it is closing, which is what the sign means")
	end

	-- A condition may be a pattern of readings, with no kind declared for it.
	do
		local i, who = world({
			{ about = { colour = "high" }, reads = { size = { 0.9, spread = 0.2 } }, after = 1 },
		})
		i:perceive(who, {
			{ subject = "bright", kind = "room", via = "sight", raw = { colour = 0.9, size = 0.5 } },
			{ subject = "dark", kind = "room", via = "sight", raw = { colour = 0.05, size = 0.5 } },
		})
		i:tick(who, 0.5, 1)
		local bright = i:expects(who, "bright", "size")
		local dark = i:expects(who, "dark", "size")
		t.ok(bright > dark, "a pattern of readings conditions a prediction with no kind involved")
	end

	-- One prediction, scaled by what is read off the thing that triggered it. *A wolf costs me health
	-- in proportion to how near it is* is a single claim, not one claim per distance -- and two wolves
	-- cost twice, because both bear on the same reading and changes add.
	do
		local function watching(): (any, any)
			local i = Instinct.new():defaults()
			i:sense("sight", {})
			i:sense("body", {})
			i:reading("distance", { from = "sight" })
			i:reading("integrity", { from = "body" })
			i:kind("wolf")
			i:species("elk", {
				senses = { sight = {}, body = {} },
				forms = { "distance", "integrity" },
				predicts = {
					{
						about = "wolf",
						of = "self",
						changes = { integrity = { -0.40, spread = 0.10 } },
						by = { { "distance", inverted = 1 } },
						after = 1,
					},
				},
			})
			return i, i:spawn("elk")
		end

		local near, whoNear = watching()
		near:perceive(whoNear, {
			{ via = "body", raw = { integrity = 1.0 } },
			{ subject = "a", kind = "wolf", via = "sight", raw = { distance = 0.1 } },
		})
		near:tick(whoNear, 0.5, 1)

		local far, whoFar = watching()
		far:perceive(whoFar, {
			{ via = "body", raw = { integrity = 1.0 } },
			{ subject = "a", kind = "wolf", via = "sight", raw = { distance = 0.9 } },
		})
		far:tick(whoFar, 0.5, 1)

		local close = near:expects(whoNear, "self", "integrity")
		local away = far:expects(whoFar, "self", "integrity")
		t.ok(close ~= nil and away ~= nil, "it expects something about itself on account of the wolf")
		t.ok((close :: number) < (away :: number), "a wolf close by is expected to cost more than one far off")

		local two, whoTwo = watching()
		two:perceive(whoTwo, {
			{ via = "body", raw = { integrity = 1.0 } },
			{ subject = "a", kind = "wolf", via = "sight", raw = { distance = 0.1 } },
			{ subject = "b", kind = "wolf", via = "sight", raw = { distance = 0.1 } },
		})
		two:tick(whoTwo, 0.5, 1)
		local pair = two:expects(whoTwo, "self", "integrity")
		t.ok((pair :: number) < (close :: number), "and two of them cost more than one, with nothing said about pairs")
	end

end
