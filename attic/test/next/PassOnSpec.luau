--!strict

local Instinct = require("../../next")

-- The world from LearnSpec: something paces toward the creature and away again, and the creature is
-- hurt exactly as fast as it closes.
local SPEEDS = { 0.12, 0.05, 0.15, 0.08, 0.11, 0.04, 0.14, 0.07 }

local DIALS = {
	adaptability = 0.7,
	ingenuity = 0.8,
	insight = 0.9,
	retention = 0.8,
	attribution = 0.2,
	grudge = 0.9,
	caution = 0.1,
	commitment = 0.01,
}

local function world(): any
	local i = Instinct.new():defaults()
	i:sense("sight", {})
	i:sense("body", {})
	i:reading("distance", { from = "sight" })
	i:reading("integrity", { from = "body" })
	i:kind("thing")
	i:action("flinch", {})
	return i
end

local function born(i: any, name: string): any
	i:species(name, {
		senses = { sight = {}, body = {} },
		forms = { "distance", "integrity" },
		wants = { integrity = { 1.0, spread = 0.05 } },
		predicts = {
			{ about = "thing", of = "self", changes = { integrity = { -0.30, spread = 0.20 } }, after = 1 },
		},
		dials = DIALS,
	})
	return i:spawn(name)
end

-- `hurts = false` is the same world with the beast standing perfectly still: it costs the creature the
-- same steady amount whatever happens, and change-in-distance -- which is now always zero -- explains
-- none of it, and worse, says nothing at all.
local function live(i: any, who: any, from: number, rounds: number, hurts: boolean): number
	local clock = from
	local integrity, distance, way = 0.7, 0.5, -1
	for at = 1, rounds do
		for _ = 1, 5 do
			i:perceive(who, {
				{ via = "body", raw = { integrity = integrity } },
				{ subject = "beast", kind = "thing", via = "sight", raw = { distance = distance } },
			}, clock)
			i:tick(who, 1, clock)
			clock += 1
			local step = SPEEDS[(at - 1) % #SPEEDS + 1] * way
			if distance + step < 0.10 or distance + step > 0.90 then
				way = -way
				step = SPEEDS[(at - 1) % #SPEEDS + 1] * way
			end
			if hurts then
				distance += step
				integrity += 0.8 * step
			else
				integrity -= 0.05
			end
		end
		way = -way
	end
	return clock
end

local function has(list: { string }, want: string): boolean
	for _, name in list do
		if name == want then
			return true
		end
	end
	return false
end

return function(t: any)
	-- An idea that stops earning its keep is given up, and the reading it was built on goes with it,
	-- because nothing is using it any more.
	do
		local i = world()
		local who = born(i, "prey")
		local clock = live(i, who, 1, 8, true)
		t.ok(has(i:acquired(who), "delta(distance)"), "it works out what is hurting it")

		-- The world changes. Now it is worn down at a flat rate whatever the beast does, and
		-- change-in-distance explains nothing at all.
		live(i, who, clock, 14, false)
		t.ok(not has(i:acquired(who), "delta(distance)"), "and gives the idea up once it explains nothing")
		t.eq(#i:acquired(who), 0, "leaving it with no private notions it cannot be rid of")
	end

	-- What one creature worked out can be written down, and the next is born with it.
	do
		local i = world()
		local who = born(i, "prey")
		live(i, who, 1, 8, true)
		t.ok(has(i:acquired(who), "delta(distance)"), "the first works it out for itself")

		local got = i:extract(who)
		t.ok(got.readings["delta(distance)"] ~= nil, "and it comes back out as something declarable")

		for name, decl in got.readings do
			i:reading(name, decl)
		end
		i:species("prey2", got.species)
		local child = i:spawn("prey2")

		t.ok(has(i:tracking(child) and got.species.forms, "delta(distance)"), "the next is born able to form it")
		local scaled = false
		for _, row in got.species.predicts do
			for _, one in (row.by or {}) do
				if one[1] == "delta(distance)" then
					scaled = true
				end
			end
		end
		t.ok(scaled, "and born predicting harm in proportion to it, having never met the beast")
		t.eq(#i:acquired(child), 0, "though it worked nothing out itself -- it was simply told")
	end

	-- What it came to believe travels too, in place of what it was born believing.
	do
		local i = world()
		local who = born(i, "prey")
		live(i, who, 1, 8, true)
		local got = i:extract(who)
		local learned = got.species.predicts[1].changes.integrity[1]
		t.ok(math.abs(learned - (-0.30)) > 1e-6, "the prior it hands on is what it learned, not what it was given")
	end

	-- Nothing travels on its own. Two creatures of the same species, one of which has had a life.
	do
		local i = world()
		local one = born(i, "prey")
		local other = i:spawn("prey")
		live(i, one, 1, 8, true)
		t.ok(has(i:acquired(one), "delta(distance)"), "one of them worked it out")
		t.eq(#i:acquired(other), 0, "and the other, its own kind, is none the wiser")
	end
end
