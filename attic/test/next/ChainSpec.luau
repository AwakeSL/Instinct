--!strict

local Instinct = require("../../next")

-- A creature that wants to be full, can eat, and can only eat what it is holding. Nothing tells it
-- that grabbing leads to eating: it holds an ordinary prediction that grabbing raises `holding`, and
-- that is enough, because a chain here is only a want that another want created.
local function forager(dials: any): (any, any)
	local i = Instinct.new():defaults()
	i:sense("body", {})
	i:reading("fullness", { from = "body" })
	i:reading("holding", { from = "body" })
	i:reading("near", { from = "body" })
	i:action("eat", { requires = { holding = "high" } })
	i:action("grab", { requires = { near = "high" } })
	i:action("approach", {})
	i:species("forager", {
		senses = { body = {} },
		forms = { "fullness", "holding", "near" },
		wants = { fullness = { 0.90, spread = 0.05 } },
		predicts = {
			{ doing = "eat", of = "self", changes = { fullness = { 0.40, spread = 0.05 } }, after = 1 },
			{ doing = "grab", of = "self", changes = { holding = { 0.80, spread = 0.05 } }, after = 1 },
			{ doing = "approach", of = "self", changes = { near = { 0.80, spread = 0.05 } }, after = 1 },
		},
		dials = dials,
	})
	return i, i:spawn("forager")
end

local function at(i: any, who: any, fullness: number, holding: number, near: number): string?
	i:perceive(who, { { via = "body", raw = { fullness = fullness, holding = holding, near = near } } })
	return i:tick(who, 0.5, 1)
end

local PATIENT = { caution = 0.1, commitment = 0.01, patience = 1.0, venture = 0 }

return function(t: any)
	-- Holding something, it simply eats.
	do
		local i, who = forager(PATIENT)
		t.eq(at(i, who, 0.20, 1.0, 1.0), "eat", "with the food in hand it eats")
	end

	-- Not holding anything, it grabs -- though nothing it wants is called `holding`, and no
	-- declaration anywhere says that grabbing is how you come to eat.
	do
		local i, who = forager(PATIENT)
		t.eq(at(i, who, 0.20, 0.0, 1.0), "grab", "unable to eat, it wants what eating needs")
	end

	-- Two links. It cannot grab either, so it wants to be near, and approaches.
	do
		local i, who = forager(PATIENT)
		t.eq(at(i, who, 0.20, 0.0, 0.0), "approach", "and follows the chain back a second time")
	end

	-- `patience` is how far back it will follow. One link is within reach of a creature that will not
	-- follow a second, and it is left with nothing to do rather than approaching.
	do
		local short = { caution = 0.1, commitment = 0.01, patience = 0.34, venture = 0 }
		local i, who = forager(short)
		t.eq(at(i, who, 0.20, 0.0, 1.0), "grab", "one link is within an impatient creature's reach")

		local j, other = forager(short)
		t.eq(at(j, other, 0.20, 0.0, 0.0), nil, "two is not, and it does nothing rather than set out")
	end

	-- A creature with no patience at all never chains: it wants what it wants, and if nothing to hand
	-- serves it directly, it stands there.
	do
		local i, who = forager({ caution = 0.1, commitment = 0.01, patience = 0, venture = 0 })
		t.eq(at(i, who, 0.20, 0.0, 1.0), nil, "no patience, no means to an end")
	end

	-- It does not chain when it does not need to. Full, there is nothing to serve, so it does not go
	-- around picking things up for their own sake.
	do
		local i, who = forager(PATIENT)
		t.eq(at(i, who, 0.90, 0.0, 0.0), nil, "wanting nothing, it fetches nothing")
	end

	-- `why` says which link it is on: the action it took, and the reading it took it for, which is not
	-- the thing it actually wants.
	do
		local i, who = forager(PATIENT)
		at(i, who, 0.20, 0.0, 1.0)
		local why = i:why(who)
		t.eq(why.doing, "grab", "it is grabbing")
		t.eq(why.because.reading, "fullness", "because it is hungry")
		local serving: string? = nil
		for _, row in why.considered do
			if row.chosen then
				serving = row.forKey
			end
		end
		t.eq(serving, "holding", "by way of wanting to be holding something")
	end
end
