--!strict

local Instinct = require("../src")

-- A creature with one need and nothing to do about it. All these cases ask is whether it holds an
-- error, so no actions are declared.
local function world(after: number): (any, any)
	local i = Instinct.new({ seed = 0x5E1F }):defaults()
	i:quantity("fullness")
	i:role("self")
	i:part("eyes")
	i:sense("sight", { needs = "eyes" })
	i:sense("body", {})
	i:species("beast", {
		parts = { eyes = 2 },
		senses = { sight = {}, body = {} },
		expects = { fullness = { 0.90, spread = 0.05, after = after } },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, adaptability = 0.8 },
	})
	i:ready()
	return i, i:spawn("beast", { seed = 0x11 })
end

local function feel(i: any, beast: any, level: number, clock: number)
	i:perceive(beast, { { via = "body", raw = { fullness = level } } })
	i:think(beast, 0.6, clock)
end

-- Live a while, running down at a steady rate, so the creature can learn what it does to itself.
local function runDown(i: any, beast: any, rate: number): number
	local clock, level = 1.0, 1.00
	for _ = 1, 16 do
		clock += 0.6
		level = math.max(0.05, level - rate * 0.6)
		feel(i, beast, level, clock)
	end
	return clock
end

local function errorNow(i: any, beast: any): number?
	local why = i:why(beast)
	return if why ~= nil and why.because ~= nil then why.because.error else nil
end

local function drift(i: any, beast: any): any
	return i:stateOf(beast).beliefs["drift|fullness"]
end

return function(t: any)
	-- Sitting exactly on its prior. Whatever error it holds can only come from the forecast.
	local AT_PRIOR = 0.90

	-- A creature that has never run down does not know it will.
	do
		local i, beast = world(30)
		local clock = 1.0
		for _ = 1, 16 do
			clock += 0.6
			feel(i, beast, AT_PRIOR, clock)
		end
		t.ok(drift(i, beast) == nil, "a life with no decline in it teaches no drift")
		t.ok(errorNow(i, beast) == nil, "and a creature that has never emptied does not anticipate emptying")
	end

	-- One that has run down learns the rate, and then wants food while it is still full.
	do
		local i, beast = world(30)
		local clock = runDown(i, beast, 0.04)
		local held = drift(i, beast)
		t.ok(held ~= nil, "running down teaches the creature that it runs down")
		t.ok(held.v < 0, "and that the drift is downward")
		t.ok(held.n > 1, "learned across several readings, not one")

		feel(i, beast, AT_PRIOR, clock + 0.6)
		local amount = errorNow(i, beast)
		t.ok(amount ~= nil, "sitting exactly on its prior, it is still moved")
		t.ok(amount > 0.1, "because where it is heading is well below where it wants to be")
	end

	-- The control: same life, no horizon. This is the old behaviour and it must be unchanged.
	do
		local i, beast = world(0)
		local clock = runDown(i, beast, 0.04)
		feel(i, beast, AT_PRIOR, clock + 0.6)
		t.ok(errorNow(i, beast) == nil, "with no horizon, a creature on its prior wants nothing")
		t.ok(drift(i, beast) == nil, "and does not bother tracking a drift it would never use")
	end

	-- Looking further ahead finds a bigger shortfall.
	do
		local near, nearBeast = world(10)
		local nearClock = runDown(near, nearBeast, 0.04)
		feel(near, nearBeast, AT_PRIOR, nearClock + 0.6)

		local far, farBeast = world(40)
		local farClock = runDown(far, farBeast, 0.04)
		feel(far, farBeast, AT_PRIOR, farClock + 0.6)

		local a, b = errorNow(near, nearBeast), errorNow(far, farBeast)
		t.ok(a ~= nil and b ~= nil, "both are looking ahead")
		t.ok(b > a, "the one looking further ahead is the hungrier of the two")
	end

	-- Rises are the world feeding it, and say nothing about how fast it runs down unattended.
	do
		local i, beast = world(30)
		local clock = 1.0
		local level = 0.20
		for _ = 1, 16 do
			clock += 0.6
			level = math.min(1.0, level + 0.05)
			feel(i, beast, level, clock)
		end
		t.ok(drift(i, beast) == nil, "a creature that has only ever been filled learns no drift from it")
	end
end
