--!strict

local Instinct = require("../../next")

-- A creature with two channels that both report a direction, so a sound and a sight have something
-- to be judged the same thing on.
local function looker(): (any, any)
	local i = Instinct.new():defaults()
	i:sense("sight", {})
	i:sense("hearing", {})
	i:reading("direction", { from = { "sight", "hearing" } })
	i:reading("size", { from = "sight" })
	i:reading("pitch", { from = "hearing" })
	i:kind("thing")
	i:species("watcher", {
		senses = { sight = {}, hearing = {} },
		forms = { "direction", "size", "pitch" },
		dials = { adaptability = 0.6, grudge = 0.95 },
	})
	return i, i:spawn("watcher")
end

local function sees(i: any, who: any, returns: { any }, clock: number)
	i:perceive(who, { { via = "sight", returns = returns } }, clock)
	i:tick(who, 0.5, clock)
end

return function(t: any)
	-- Two things in different places are two things, with nobody having said so.
	do
		local i, who = looker()
		sees(i, who, { { direction = 0.2, size = 0.5 }, { direction = 0.8, size = 0.3 } }, 1)
		t.eq(#i:tracking(who), 2, "two returns far apart become two things")
	end

	-- And the same two, seen again where they were, are still those two rather than two more.
	do
		local i, who = looker()
		local clock = 1
		for _ = 1, 6 do
			clock += 1
			sees(i, who, { { direction = 0.2, size = 0.5 }, { direction = 0.8, size = 0.3 } }, clock)
		end
		t.eq(#i:tracking(who), 2, "seeing them again does not invent new ones")
		t.eq(i:stats().born, 2, "only two things were ever born")
	end

	-- Something that moves is followed, because the match is against where it was predicted to be
	-- rather than where it was last seen.
	do
		local i, who = looker()
		local clock, where = 1, 0.10
		for _ = 1, 6 do
			clock += 1
			where += 0.08
			sees(i, who, { { direction = where, size = 0.5 } }, clock)
		end
		t.eq(#i:tracking(who), 1, "a thing that moves is still one thing")
	end

	-- Colour-style readings that every candidate shares cannot decide between them. Both things are
	-- exactly the same size; only direction tells them apart, and it does.
	do
		local i, who = looker()
		local clock = 1
		for _ = 1, 5 do
			clock += 1
			sees(i, who, { { direction = 0.15, size = 0.5 }, { direction = 0.85, size = 0.5 } }, clock)
		end
		t.eq(#i:tracking(who), 2, "identical in every way but one, and that one is enough")
	end

	-- Two channels, one thing. The sound and the sight agree about direction, so they are judged the
	-- same thing -- and the creature ends up holding a pitch and a size for one subject.
	do
		local i, who = looker()
		i:perceive(who, {
			{ via = "sight", returns = { { direction = 0.4, size = 0.6 } } },
			{ via = "hearing", returns = { { direction = 0.41, pitch = 0.7 } } },
		})
		i:tick(who, 0.5, 1)
		local tracking = i:tracking(who)
		t.eq(#tracking, 1, "a sound and a sight agreeing on direction are one thing")
		local size = i:estimate(who, tracking[1], "size")
		local pitch = i:estimate(who, tracking[1], "pitch")
		t.ok(size ~= nil and pitch ~= nil, "and it holds what each channel told it about that thing")
	end

	-- A sound from somewhere else is not that thing.
	do
		local i, who = looker()
		i:perceive(who, {
			{ via = "sight", returns = { { direction = 0.2, size = 0.6 } } },
			{ via = "hearing", returns = { { direction = 0.9, pitch = 0.7 } } },
		})
		i:tick(who, 0.5, 1)
		t.eq(#i:tracking(who), 2, "a sound from the other side is something else")
	end

	-- Five noises, each nearer than the last, become one thing approaching -- not five events.
	do
		local i, who = looker()
		local clock, near = 1, 0.90
		for _ = 1, 5 do
			clock += 1
			near -= 0.06
			i:perceive(who, { { via = "hearing", returns = { { direction = near, pitch = 0.5 } } } }, clock)
			i:tick(who, 0.5, clock)
		end
		t.eq(#i:tracking(who), 1, "five nearing noises are one thing coming closer")
	end

	-- Supplying the identity skips all of it, which is what most games will do.
	do
		local i, who = looker()
		i:perceive(who, {
			{ subject = "wolf7", kind = "thing", via = "sight", raw = { direction = 0.2, size = 0.5 } },
		})
		i:tick(who, 0.5, 1)
		t.eq(i:stats().born, 0, "told which thing it is, it works nothing out")
		t.eq(i:tracking(who)[1], "wolf7", "and uses the name it was given")
	end
end
