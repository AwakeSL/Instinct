--!strict

local Instinct = require("../../next")

-- A creature that is hurt by something approaching it, and has been born believing that the *nearness*
-- of the thing is what costs it -- which is wrong. What actually costs it is how fast the thing is
-- closing. Nobody tells it that; it has `delta` and a great many moments it got wrong.
local function bitten(dials: any): (any, any)
	local i = Instinct.new():defaults()
	i:sense("sight", {})
	i:sense("body", {})
	i:reading("distance", { from = "sight" })
	i:reading("integrity", { from = "body" })
	i:kind("thing")
	i:action("flinch", {})
	i:species("prey", {
		senses = { sight = {}, body = {} },
		forms = { "distance", "integrity" },
		wants = { integrity = { 1.0, spread = 0.05 } },
		predicts = {
			-- Scaled by how near it is. Held loosely, because the creature is not sure.
			{
				about = "thing",
				of = "self",
				changes = { integrity = { -0.30, spread = 0.20 } },
				by = { { "distance", inverted = 1 } },
				after = 1,
			},
		},
		dials = dials,
	})
	return i, i:spawn("prey")
end

-- Run the world. The beast paces toward the creature and away again, at a speed that keeps changing,
-- and the creature is hurt exactly as fast as the beast closes -- and mends exactly as fast as it
-- withdraws. Nothing here resets and nothing clamps: the relationship holds on every single tick, so a
-- creature that failed to find it would be the one at fault.
local function chased(i: any, who: any)
	local clock = 0
	local integrity = 0.7
	local distance = 0.5
	local speeds = { 0.12, 0.05, 0.15, 0.08, 0.11, 0.04, 0.14, 0.07, 0.13, 0.06, 0.15, 0.09 }
	local way = -1
	for _, speed in speeds do
		for _ = 1, 5 do
			clock += 1
			i:perceive(who, {
				{ via = "body", raw = { integrity = integrity } },
				{ subject = "beast", kind = "thing", via = "sight", raw = { distance = distance } },
			}, clock)
			i:tick(who, 1, clock)
			local step = speed * way
			if distance + step < 0.10 or distance + step > 0.90 then
				way = -way
				step = speed * way
			end
			distance += step
			integrity += 0.8 * step
		end
		way = -way
	end
end

return function(t: any)
	-- Given the means to compose one, it finds the reading that actually explains what happens to it.
	do
		local i, who = bitten({
			adaptability = 0.7,
			ingenuity = 0.3, -- one operator deep, which is all `delta(distance)` needs
			insight = 0.9,
			retention = 0.8,
			attribution = 0.2,
			grudge = 0.9,
			caution = 0.1,
			commitment = 0.01,
		})
		chased(i, who)
		local found = i:acquired(who)
		t.ok(#found > 0, "kept being wrong, it works out a new way of seeing")
		local hit = false
		for _, name in found do
			if name:find("delta(distance)", 1, true) then
				hit = true
			end
		end
		t.ok(hit, "and what it works out is the change in distance, which is what was hurting it")
	end

	-- The same creature, unable to compose anything, stays wrong. `ingenuity` is the whole difference:
	-- what it can sense, what it wants, and what happens to it are identical.
	do
		local i, who = bitten({
			adaptability = 0.7,
			ingenuity = 0,
			insight = 0.9,
			retention = 0.8,
			attribution = 0.2,
			grudge = 0.9,
			caution = 0.1,
			commitment = 0.01,
		})
		chased(i, who)
		t.eq(#i:acquired(who), 0, "a creature with no ingenuity is stuck with the senses it was born with")
	end

	-- And it does not reach for a new idea when the one it has is working. A creature whose authored
	-- prediction is simply correct has no residual to explain, so nothing is adopted -- otherwise
	-- every creature would end up encrusted with spurious readings that fit noise.
	do
		local i = Instinct.new():defaults()
		i:sense("body", {})
		i:sense("sight", {})
		i:reading("integrity", { from = "body" })
		i:reading("distance", { from = "sight" })
		i:kind("thing")
		i:species("calm", {
			senses = { body = {}, sight = {} },
			forms = { "distance", "integrity" },
			wants = { integrity = { 1.0, spread = 0.05 } },
			predicts = {
				{ about = "thing", of = "self", changes = { integrity = { -0.10, spread = 0.05 } }, after = 1 },
			},
			dials = { ingenuity = 0.8, insight = 0.9, retention = 0.8, adaptability = 0.6 },
		})
		local who = i:spawn("calm")
		local integrity, distance = 1.0, 0.5
		for clock = 1, 24 do
			i:perceive(who, {
				{ via = "body", raw = { integrity = integrity } },
				{ subject = "beast", kind = "thing", via = "sight", raw = { distance = distance } },
			}, clock)
			i:tick(who, 1, clock)
			integrity = math.clamp(integrity - 0.10, 0, 1)
			distance = math.clamp(distance + 0.03, 0, 1)
			if integrity <= 0.2 then
				integrity = 1.0
			end
		end
		t.eq(#i:acquired(who), 0, "a prediction that is working is not rewritten")
	end

	-- How deep an idea it can hold together is `ingenuity`, and here the truth needs two operators: the
	-- creature is hurt as fast as the beast closes, *scaled by how big the beast is*. Neither
	-- change-in-distance nor size explains that on its own, and no single operator reaches it.
	do
		local function harried(ingenuity: number, retention: number): (any, any)
			local i = Instinct.new():defaults()
			i:sense("sight", {})
			i:sense("body", {})
			i:reading("distance", { from = "sight" })
			i:reading("size", { from = "sight" })
			i:reading("integrity", { from = "body" })
			i:kind("thing")
			i:species("prey", {
				senses = { sight = {}, body = {} },
				forms = { "distance", "size", "integrity" },
				wants = { integrity = { 1.0, spread = 0.05 } },
				predicts = {
					{ about = "thing", of = "self", changes = { integrity = { -0.30, spread = 0.20 } }, after = 1 },
				},
				dials = {
					-- Steady enough that a wrong idea shows up as a standing error rather than being
					-- chased away every tick. A creature that believes whatever it last saw is never
					-- surprised for long enough to wonder why.
					adaptability = 0.4,
					ingenuity = ingenuity,
					insight = 1.0,
					retention = retention,
					attribution = 0.2,
					grudge = 0.9,
				},
			})
			return i, i:spawn("prey")
		end

		local function hunted(i: any, who: any)
			local clock, integrity, distance, way = 0, 0.7, 0.5, -1
			local size = 0.3
			local speeds = { 0.12, 0.05, 0.15, 0.08, 0.11, 0.04, 0.14, 0.07, 0.13, 0.06, 0.15, 0.09 }
			for pass = 1, 30 do
				local round, speed = pass, speeds[(pass - 1) % #speeds + 1]
				size = 0.25 + ((round * 7) % 5) * 0.15 -- a different beast each pass
				for _ = 1, 6 do
					clock += 1
					i:perceive(who, {
						{ via = "body", raw = { integrity = integrity } },
						{
							subject = "beast",
							kind = "thing",
							via = "sight",
							raw = { distance = distance, size = size },
						},
					}, clock)
					i:tick(who, 1, clock)
					local step = speed * way
					if distance + step < 0.10 or distance + step > 0.90 then
						way = -way
						step = speed * way
					end
					distance += step
					-- Hurt as fast as it closes, and a big one hurts more.
					integrity += 0.8 * step * size
				end
				way = -way
			end
		end

		local function reaches(i: any, who: any): boolean
			for _, name in i:acquired(who) do
				if name:find("delta(distance)", 1, true) and name:find("size", 1, true) then
					return true
				end
			end
			return false
		end

		local deep, bold = harried(1.0, 0.9)
		hunted(deep, bold)
		t.ok(reaches(deep, bold), "given the depth, it composes the two operators the world actually needs")

		-- The same creature in the same world, able to hold only one operator together at a time --
		-- and it gets there anyway, because an idea it has already committed to is something it may
		-- build on. It works out that harm goes with how fast the thing is closing, and later that a
		-- big one hurts more, which is two thoughts where the other creature had one.
		--
		-- So `ingenuity` is not a ceiling on what a creature can end up believing. It is how much of an
		-- idea it can reach in a single step, and a shallow creature arrives at the same place by a
		-- longer road -- provided every step of that road earns its keep on its own.
		--
		-- Both take the road, as it happens. Preferring the simpler explanation means the one-operator
		-- idea wins the first search even for a creature that could have reached the whole thing at
		-- once, so depth only decides what is reachable when no single step would do.
		local shallow, timid = harried(0.3, 0.9)
		hunted(shallow, timid)
		t.ok(reaches(shallow, timid), "and one operator at a time, it arrives at the same place")

		-- Reaching further is paid for in memory. A creature that can think of hundreds of ideas and
		-- remembers a dozen moments cannot tell a real one from a lucky one, so it settles for nothing
		-- rather than adopting a coincidence.
		local forgetful, hasty = harried(1.0, 0.05)
		hunted(forgetful, hasty)
		t.eq(#forgetful:acquired(hasty), 0, "an ambitious creature with no memory works nothing out at all")
	end

end
