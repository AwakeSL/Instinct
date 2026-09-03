--!strict

local Instinct = require("../../next")

-- A creature that can be hungry and can eat.
local function fed(extra: any?): (any, any)
	local i = Instinct.new():defaults()
	i:sense("body", {})
	i:reading("fullness", { from = "body" })
	i:action("eat", {})
	i:action("loiter", {})

	local decl: any = {
		senses = { body = {} },
		forms = { "fullness" },
		wants = { fullness = { 0.90, spread = 0.05 } },
		predicts = {
			{ doing = "eat", of = "self", changes = { fullness = { 0.40, spread = 0.10 } }, after = 1 },
		},
		dials = { adaptability = 0.7, commitment = 0.01, caution = 0.1 },
	}
	for key, value in pairs(extra or {}) do
		decl[key] = value
	end
	i:species("creature", decl)
	return i, i:spawn("creature")
end

local function body(i: any, who: any, fullness: number, clock: number): string?
	i:perceive(who, { { via = "body", raw = { fullness = fullness } } })
	return i:tick(who, 0.5, clock)
end

return function(t: any)
	-- Short of what it wants, with something that helps.
	do
		local i, who = fed()
		t.eq(body(i, who, 0.30, 1), "eat", "being short of what it wants, it does the thing that helps")
	end

	-- At its prior, it does nothing. An error inside its own spread is not evidence, and a creature
	-- with nothing wrong with it is not supposed to invent something to do.
	do
		local i, who = fed()
		t.eq(body(i, who, 0.90, 1), nil, "wanting nothing, it does nothing")
	end

	-- Only a preference moves it. The same creature, same action, with nothing it would rather.
	do
		local i, who = fed({ wants = {} })
		t.eq(body(i, who, 0.10, 1), nil, "with no preference, an empty creature still does nothing")
	end

	-- An action's predictions are checked like anything else, so it learns what its own moves do --
	-- with no mechanism for that beyond `doing` being a condition.
	do
		local i, who = fed()
		local clock = 1
		for _ = 1, 14 do
			clock += 1
			body(i, who, 0.30, clock) -- it eats, and nothing whatsoever happens
		end
		local held = i:believes(who, 1, "self")
		t.ok(held ~= nil, "doing something creates a belief about what it does")
		t.ok(held.n > 1, "checked against the world more than once")
		t.ok(held.v < 0.25, "an action that never delivers loses the belief that it does")
	end

	-- And when it does deliver, the belief holds up.
	--
	-- The world has to be honestly consistent for this to mean anything. A prediction is checked
	-- across the interval between two ticks, so a scenario that lets fullness drop back between
	-- meals is one where eating really is followed by a loss half the time -- and a creature that
	-- concluded otherwise would be the broken one. Fullness only ever rises here.
	do
		local i, who = fed({
			predicts = {
				{ doing = "eat", of = "self", changes = { fullness = { 0.10, spread = 0.05 } }, after = 1 },
			},
		})
		local clock, fullness = 1, 0.10
		for _ = 1, 7 do
			clock += 1
			body(i, who, fullness, clock)
			fullness += 0.10
		end
		local held = i:believes(who, 1, "self")
		t.ok(held ~= nil, "it holds a belief about what eating does")
		t.ok(math.abs(held.v - 0.10) < 0.06, "an action that keeps delivering keeps its reputation")
		t.ok(held.n > 2, "having been checked repeatedly rather than taken on faith")
	end

	-- It does not want food. It wants a number to be at a value, and holds beliefs about what moves
	-- that number -- so when the world changes which action feeds it, it follows the number rather
	-- than the habit. There is no concept of food anywhere in a creature.
	do
		local i = Instinct.new():defaults()
		i:sense("body", {})
		i:reading("fullness", { from = "body" })
		i:action("eat", {})
		i:action("lick", {})
		i:species("creature", {
			senses = { body = {} },
			forms = { "fullness" },
			wants = { fullness = { 0.90, spread = 0.05 } },
			predicts = {
				-- Held loosely enough to be worth an experiment: below the uncertainty floor there is
				-- nothing to find out, so the creature would take the first and never try the other.
				{ doing = "eat", of = "self", changes = { fullness = { 0.10, spread = 0.16 } }, after = 1 },
				{ doing = "lick", of = "self", changes = { fullness = { 0.10, spread = 0.16 } }, after = 1 },
			},
			dials = { adaptability = 0.85, commitment = 0.005, caution = 0.1, venture = 0.5, grudge = 0.4 },
		})
		local who = i:spawn("creature")

		-- Counted rather than read off a belief: what it does is the claim, and a belief that is
		-- exactly right sits at the same number as one that has merely been forgotten back to it.
		local function live(rounds: number, feeder: string): (number, number)
			local ate, licked = 0, 0
			local fullness = 0.10
			for _ = 1, rounds do
				i.clock = (i.clock or 1) + 1
				i:perceive(who, { { via = "body", raw = { fullness = fullness } } }, i.clock)
				local doing = i:tick(who, 0.5, i.clock)
				if doing == "eat" then
					ate += 1
				elseif doing == "lick" then
					licked += 1
				end
				if doing == feeder then
					fullness = math.min(0.80, fullness + 0.10)
				end
			end
			return ate, licked
		end

		live(40, "eat")
		local ate, licked = live(40, "eat")
		t.ok(ate > licked, "it works out which of the two actually feeds it")

		-- Now licking feeds it and eating does not. Nobody tells it; the food simply changed.
		live(60, "lick")
		local ate2, licked2 = live(40, "lick")
		t.ok(licked2 > ate2, "and when the world swaps them over, it follows the number, not the habit")
	end

	-- `why` answers the question.
	do
		local i, who = fed()
		body(i, who, 0.30, 1)
		local why = i:why(who)
		t.eq(why.doing, "eat", "it says what it is doing")
		t.ok(why.because ~= nil, "and what drove it")
		t.eq(why.because.reading, "fullness", "named")
		t.ok(why.because.spreads > 1, "in spreads, which is the number that matters")
		t.ok(#why.considered > 0, "and what else was weighed")
	end

	-- The black room. One action, no preference about the colour, and a creature that presses the
	-- button only because it does not know what the button does.
	do
		local i = Instinct.new():defaults()
		i:sense("sight", {})
		i:sense("body", {})
		i:reading("colour", { from = "sight" })
		i:reading("bother", { from = "body" })
		i:action("press", {})
		i:species("prodder", {
			senses = { sight = {}, body = {} },
			forms = { "colour" },
			-- Something to be short of, so there is a reason to do anything at all. What it does not
			-- have is any idea that pressing helps.
			wants = { bother = { 0.00, spread = 0.05 } },
			predicts = {
				{ doing = "press", of = "self", changes = { bother = { 0.0, spread = 0.5 } }, after = 1 },
			},
			dials = { venture = 0.6, caution = 0.1, commitment = 0.01, adaptability = 0.7 },
		})
		local who = i:spawn("prodder")

		i:perceive(who, {
			{ via = "body", raw = { bother = 0.8 } },
			{ subject = "room", kind = nil, via = "sight", raw = { colour = 0.0 } },
		})
		local doing = i:tick(who, 0.5, 1)
		t.eq(doing, "press", "it presses the button because it does not know what the button does")

		local i2 = Instinct.new():defaults()
		i2:sense("body", {})
		i2:reading("bother", { from = "body" })
		i2:action("press", {})
		i2:species("dull", {
			senses = { body = {} },
			forms = {},
			wants = { bother = { 0.00, spread = 0.05 } },
			predicts = {
				{ doing = "press", of = "self", changes = { bother = { 0.0, spread = 0.5 } }, after = 1 },
			},
			dials = { venture = 0, caution = 0.1, commitment = 0.01 },
		})
		local dull = i2:spawn("dull")
		i2:perceive(dull, { { via = "body", raw = { bother = 0.8 } } })
		t.eq(i2:tick(dull, 0.5, 1), nil, "a creature with no venture never finds out")
	end
end
