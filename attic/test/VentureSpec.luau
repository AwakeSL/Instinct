--!strict

local Instinct = require("../src")

-- A creature with two ways to fix one need. `sure` is known and useless; `unsure` is a mystery.
-- Which it picks is the whole question.
local function world(venture: number, unsureSpread: number): (any, any)
	local i = Instinct.new({ seed = 0x5E1F }):defaults()
	i:quantity("warmth")
	i:role("self")
	i:part("body")
	i:sense("body", {})

	-- Both are believed to do nothing, so neither cancels anything and the only thing separating
	-- them is how sure the creature is. `sure` is nailed down; `unsure` might be anything.
	i:action("sure", {
		occupies = { body = 1 },
		predicts = { { of = "self", warmth = { 0, spread = 0.001 } } },
	})
	i:action("unsure", {
		occupies = { body = 1 },
		predicts = { { of = "self", warmth = { 0, spread = unsureSpread } } },
	})

	i:species("creature", {
		parts = { body = 2 },
		senses = { body = {} },
		expects = { warmth = { 0.90, spread = 0.05 } },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.01, venture = venture },
	})
	i:ready()
	return i, i:spawn("creature", { seed = 0x11 })
end

local function chooseWith(venture: number, unsureSpread: number): string?
	local i, beast = world(venture, unsureSpread)
	i:perceive(beast, { { via = "body", raw = { warmth = 0.20 } } })
	return i:think(beast, 0.5, 1)
end

return function(t: any)
	-- A creature that only does what it trusts. Neither option promises anything, so it does
	-- nothing at all -- and stays that way, because the option it never tries is the option it can
	-- never learn about.
	do
		t.eq(chooseWith(0, 0.5), nil, "with no venture, an option that promises nothing is never tried")
	end

	-- The same creature, willing to find out.
	do
		t.eq(chooseWith(0.5, 0.5), "unsure", "venturing, it tries the one it knows least about")
	end

	-- It is the not-knowing that draws it, not the action. Tighten the same option's belief and
	-- there is nothing left to learn, so it goes back to doing nothing.
	do
		t.eq(chooseWith(0.5, 0.001), nil, "an option it is already sure of is not worth an experiment")
	end

	-- A real payoff still beats an experiment. Venturing is what a creature does when nothing it
	-- trusts is on offer, not a preference for the unknown over the known.
	do
		local i = Instinct.new({ seed = 0x5E1F }):defaults()
		i:quantity("warmth")
		i:role("self")
		i:part("body")
		i:sense("body", {})
		i:action("works", {
			occupies = { body = 1 },
			predicts = { { of = "self", warmth = { 0.60, spread = 0.05 } } },
		})
		i:action("mystery", {
			occupies = { body = 1 },
			predicts = { { of = "self", warmth = { 0, spread = 0.5 } } },
		})
		i:species("creature", {
			parts = { body = 2 },
			senses = { body = {} },
			expects = { warmth = { 0.90, spread = 0.05 } },
			dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.01, venture = 0.5 },
		})
		i:ready()
		local beast = i:spawn("creature", { seed = 0x11 })
		i:perceive(beast, { { via = "body", raw = { warmth = 0.20 } } })
		t.eq(i:think(beast, 0.5, 1), "works", "something that plainly works beats something merely unknown")
	end

	-- The counter says an experiment was admitted, so venturing is visible rather than mysterious.
	do
		local i, beast = world(0.5, 0.5)
		i:perceive(beast, { { via = "body", raw = { warmth = 0.20 } } })
		i:think(beast, 0.5, 1)
		local why = i:why(beast)
		local tried = nil
		for _, row in why.considered do
			if row.chosen then
				tried = row
			end
		end
		t.ok(tried ~= nil, "the experiment shows up in what was considered")
		t.ok(tried.cancels < 0.01, "chosen despite promising essentially nothing")
	end
end
