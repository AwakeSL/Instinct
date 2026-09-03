--!strict

local Instinct = require("../src")

-- A creature that finds an unfamiliar thing interesting, and an action for looking at it.
local function world(narrows: boolean): (any, any, any)
	local i = Instinct.new({ seed = 0x5E1F }):defaults()
	i:quantity("integrity")
	-- No `i:quantity("curiosity")` -- an emotion declares its own name, and is a quantity by being
	-- one. §07: "An emotion IS a quantity. The only difference is where its value comes from."
	i:role("self")
	i:part("eyes")
	i:sense("sight", { needs = "eyes" })
	i:sense("body", {})
	i:feature("distance", { from = "sight" })
	i:kind("thing")
	i:kind("oddity", { is = { "thing" } })

	i:emotion("curiosity", {
		from = { spread = "high", salience = "low" },
		decays = 0.6,
		modulates = { patience = 0.3 },
	})

	local watch: any = {
		requires = { at = "thing" },
		occupies = { eyes = 2 },
		predicts = { { of = "self", curiosity = { -0.60, spread = 0.10 } } },
	}
	if narrows then
		watch.narrows = "subject"
	end
	i:action("watch", watch)

	i:species("beast", {
		parts = { eyes = 2 },
		senses = { sight = {}, body = {} },
		forms = { "distance" },
		feels = { "curiosity" },
		expects = {
			integrity = { 1.00, spread = 0.30 },
			curiosity = { 0.00, spread = 0.45 },
		},
		-- Something to hold an opinion about, so the creature has a belief about this particular
		-- oddity that starts out wide. Held loosely and predicting almost nothing, so what it feels
		-- is unfamiliarity rather than danger.
		instinct = {
			{
				about = "oddity",
				predicts = { { of = "self", integrity = { -0.02, spread = 0.40 }, after = 3 } },
			},
		},
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.6, adaptability = 0.4 },
	})
	i:ready()
	local beast = i:spawn("beast", { seed = 0x11 })
	return i, beast, watch
end

local function look(i: any, beast: any, clock: number): string?
	i:perceive(beast, {
		{ via = "body", raw = { integrity = 1.0 } },
		{ subject = "oddity1", kind = "oddity", via = "sight", raw = { distance = 3, at = true } },
	})
	return i:think(beast, 0.4, clock)
end

local function widest(i: any, beast: any): number
	local worst = 0
	for name, held in pairs(i:stateOf(beast).beliefs) do
		if name:find("subject|oddity1", 1, true) and held.s > worst then
			worst = held.s
		end
	end
	return worst
end

local function feeling(i: any, beast: any): number
	return i:stateOf(beast).level.curiosity or 0
end

return function(t: any)
	-- It looks, and looking tells it something.
	do
		local i, beast = world(true)
		t.eq(look(i, beast, 1), "watch", "an unfamiliar thing is worth looking at")

		local before = widest(i, beast)
		t.ok(before > 0.2, "and it starts out holding a wide opinion of this particular one")
		local rose = feeling(i, beast)
		t.ok(rose > 0, "which is what curiosity is")

		local clock = 1
		for _ = 1, 12 do
			clock += 0.4
			look(i, beast, clock)
		end

		t.ok(widest(i, beast) < before * 0.5, "watching it tightens what is believed about it")
		t.ok(feeling(i, beast) < rose, "so the curiosity that sent it there subsides")
	end

	-- The same creature whose looking does not narrow. Note the claim: not that it learns nothing --
	-- ordinary experience tightens a belief anyway, because every prediction that comes due updates
	-- it -- but that deliberately attending to something tells it much more than merely being near
	-- it does, and settles the curiosity that sent it there.
	do
		local attentive, a = world(true)
		local idle, b = world(false)
		local clock = 1
		for _ = 1, 12 do
			clock += 0.4
			look(attentive, a, clock)
			look(idle, b, clock)
		end
		t.ok(widest(attentive, a) < widest(idle, b) * 0.6,
			"attending to a thing tells it far more than just having it in view")
		t.ok(feeling(attentive, a) < feeling(idle, b),
			"and the creature that learned something is the one that stops wondering")
	end

	-- Watching narrows what it is looking at, and nothing else.
	do
		local i, beast = world(true)
		local clock = 1
		for _ = 1, 8 do
			clock += 0.4
			i:perceive(beast, {
				{ via = "body", raw = { integrity = 1.0 } },
				{ subject = "oddity1", kind = "oddity", via = "sight", raw = { distance = 3, at = true } },
				{ subject = "oddity2", kind = "oddity", via = "sight", raw = { distance = 40 } },
			})
			i:think(beast, 0.4, clock)
		end
		local other = 0
		for name, held in pairs(i:stateOf(beast).beliefs) do
			if name:find("subject|oddity2", 1, true) and held.s > other then
				other = held.s
			end
		end
		t.ok(other > widest(i, beast), "the one it was not looking at is still a mystery")
	end
end
