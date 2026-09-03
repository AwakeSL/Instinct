--!strict

local Instinct = require("../../next")

-- A creature that is afraid of what it expects to happen to it, rather than of what has happened.
-- `dying` is an ordinary reading whose value is a projection; `fear` is an ordinary reading built on
-- that one. Nothing here is a subsystem.
local function nervous(modulates: any?): (any, any)
	local i = Instinct.new():defaults()
	i:sense("body", {})
	i:sense("sight", {})
	i:reading("integrity", { from = "body" })
	i:reading("distance", { from = "sight" })
	i:reading("dying", { predicts = "integrity" })
	i:kind("wolf")
	i:action("flee", {})
	i:emotion("fear", {
		is = { "dying", inverted = 1 },
		decays = 0.5,
		modulates = modulates or {},
	})
	i:species("elk", {
		senses = { body = {}, sight = {} },
		forms = { "integrity", "distance" },
		wants = { integrity = { 1.0, spread = 0.05 } },
		predicts = {
			{
				about = "wolf",
				of = "self",
				changes = { integrity = { -0.60, spread = 0.10 } },
				by = { { "distance", inverted = 1 } },
				after = 1,
			},
		},
		dials = { caution = 0.1, commitment = 0.01, adaptability = 0.9, grudge = 0.99 },
	})
	return i, i:spawn("elk")
end

local function alone(i: any, who: any, integrity: number, clock: number)
	i:perceive(who, { { via = "body", raw = { integrity = integrity } } }, clock)
	i:tick(who, 1, clock)
end

-- What it can see is a belief, not a readout, so it takes a moment for a creature to be convinced of
-- something. Settling that is not what these cases are about.
local function convinced(i: any, who: any, integrity: number, from: number): number
	local clock = from
	for _ = 1, 3 do
		alone(i, who, integrity, clock)
		clock += 1
	end
	return clock
end

local function watched(i: any, who: any, integrity: number, distance: number, clock: number)
	i:perceive(who, {
		{ via = "body", raw = { integrity = integrity } },
		{ subject = "wolf", kind = "wolf", via = "sight", raw = { distance = distance } },
	}, clock)
	i:tick(who, 1, clock)
end

return function(t: any)
	-- Unhurt and unthreatened, it feels nothing.
	do
		local i, who = nervous()
		alone(i, who, 1.0, 1)
		t.ok(i:feels(who, "fear") < 0.1, "with nothing wrong and nothing coming, there is nothing to feel")
	end

	-- Hurt, it is afraid.
	do
		local i, who = nervous()
		convinced(i, who, 0.2, 1)
		t.ok(i:feels(who, "fear") > 0.6, "hurt, it is afraid")
	end

	-- The one that matters: it is at **full health**, and afraid, because something it can see is
	-- expected to cost it. Fear of what is about to happen falls out of building the feeling on a
	-- projection rather than on a reading -- there is no rule anywhere about wolves being frightening.
	do
		local near, whoNear = nervous()
		watched(near, whoNear, 1.0, 0.05, 1)
		t.ok(near:feels(whoNear, "fear") > 0.4, "unhurt, but afraid of what is about to happen to it")

		local far, whoFar = nervous()
		watched(far, whoFar, 1.0, 0.95, 1)
		t.ok(far:feels(whoFar, "fear") < near:feels(whoNear, "fear"), "and less so of the one further off")
	end

	-- Onset is immediate; leaving is not. A creature restored to full health is still frightened, and
	-- stops being frightened gradually. That asymmetry is the whole reason an emotion is not just an
	-- expression.
	do
		local i, who = nervous()
		local clock = convinced(i, who, 0.1, 1)
		local peak = i:feels(who, "fear")
		t.ok(peak > 0.8, "badly hurt, badly frightened")

		alone(i, who, 1.0, clock)
		local after = i:feels(who, "fear")
		t.ok(after > 0.3, "made whole again, it is still afraid")
		t.ok(after < peak, "though less so")

		for tick = clock + 1, clock + 6 do
			alone(i, who, 1.0, tick)
		end
		t.ok(i:feels(who, "fear") < 0.05, "and it does pass")
	end

	-- It acts back on the dials. Same creature, same moment, and what it is willing to do differs by
	-- how it feels.
	do
		local i, who = nervous({ tempo = 2.0, caution = 0.2 })
		local clock = convinced(i, who, 1.0, 1)
		local calmTempo = i:why(who).dials.tempo
		local calmCaution = i:why(who).dials.caution

		convinced(i, who, 0.1, clock)
		local scaredTempo = i:why(who).dials.tempo
		local scaredCaution = i:why(who).dials.caution

		t.ok(scaredTempo > calmTempo * 1.5, "frightened, it moves faster")
		t.ok(scaredCaution < calmCaution * 0.5, "and is willing to try things it would not have")
	end

	-- Attention narrows what it is aimed at. A frightened creature does not see its health more
	-- accurately; it treats what it sees as more decisive, which is the same arithmetic.
	do
		local i, who = nervous({ precision = { integrity = 4 } })
		local clock = convinced(i, who, 1.0, 1)
		local _, calm = i:estimate(who, "self", "integrity")

		convinced(i, who, 0.1, clock)
		local _, scared = i:estimate(who, "self", "integrity")
		t.ok(scared < calm * 0.6, "afraid, it holds what it knows about its own health more tightly")
	end

	-- A feeling built on a prediction that is itself scaled by the feeling is a loop, and is caught
	-- rather than hung on. Note how narrow the real cycle is: panic about a *wolf* scaling a
	-- prediction about the *creature* is not one, because they are different subjects and the reading
	-- is held per subject. Only a feeling that feeds back onto itself is.
	do
		local i = Instinct.new():defaults()
		i:sense("body", {})
		i:reading("integrity", { from = "body" })
		i:reading("dying", { predicts = "integrity" })
		i:emotion("panic", { is = { "dying", inverted = 1 } })
		i:species("elk", {
			senses = { body = {} },
			forms = { "integrity" },
			wants = { integrity = { 1.0, spread = 0.05 } },
			predicts = {
				{
					of = "self",
					changes = { integrity = { -0.5, spread = 0.1 } },
					by = { { "panic" } },
					after = 1,
				},
			},
		})
		local who = i:spawn("elk")
		i:perceive(who, { { via = "body", raw = { integrity = 0.5 } } })
		t.err(function()
			i:tick(who, 1, 1)
		end, "depends on itself", "a feeling that is its own cause is caught, not hung on")
	end

	-- A creature can read how well it knows a thing, and be moved by that alone. Curiosity is then an
	-- ordinary emotion built on an ordinary reading, with nothing in the package knowing what
	-- curiosity is.
	do
		local i = Instinct.new():defaults()
		i:sense("sight", { reliable = 0.5 })
		i:reading("shape", { from = "sight" })
		i:reading("strangeness", { unsure = "shape" })
		i:kind("thing")
		i:emotion("curiosity", { is = { "strangeness" }, decays = 0.7 })
		i:species("watcher", { senses = { sight = {} }, forms = { "shape" }, dials = { adaptability = 0.6 } })
		local who = i:spawn("watcher")

		-- Never seen, so as strange as a thing can be.
		t.eq(i:estimate(who, "rock", "strangeness"), 1, "a thing it has never got a look at is wholly strange")

		-- Glimpsed poorly. It has an opinion, and the opinion is vague.
		i:perceive(who, { { subject = "rock", kind = "thing", via = "sight", raw = { shape = 0.4 } } }, 1)
		i:tick(who, 0.5, 1)
		local glimpsed = i:estimate(who, "rock", "strangeness")
		t.ok(glimpsed ~= nil and glimpsed > 0.3 and glimpsed < 1, "glimpsed, it has a vague opinion of it")

		-- Looked at properly -- a percept it trusts, which is what getting closer amounts to.
		for clock = 2, 6 do
			i:perceive(who, {
				{ subject = "rock", kind = "thing", via = "sight", confidence = 1, raw = { shape = 0.4 } },
			}, clock)
			i:tick(who, 0.5, clock)
		end
		local known = i:estimate(who, "rock", "strangeness")
		t.ok((known :: number) < (glimpsed :: number) * 0.5, "looked at properly, it is no longer strange")

		-- And a second thing it has not looked at is still strange, so this is about the thing and
		-- not about the creature's mood.
		t.eq(i:estimate(who, "stump", "strangeness"), 1, "while whatever it has not looked at still is")
	end

end
