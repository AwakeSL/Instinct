--!strict

local Instinct = require("../../next")

-- A creature with poor ears. That does not mean it hears wrong things -- it means it holds what it
-- hears loosely, and so can be talked out of it, which is the whole reason it can make a bad merge in
-- the first place.
local function ears(attribution: number): (any, any)
	local i = Instinct.new():defaults()
	i:sense("hearing", { reliable = 0.55 })
	i:reading("direction", { from = "hearing" })
	i:reading("pitch", { from = "hearing" })
	i:species("listener", {
		senses = { hearing = {} },
		forms = { "direction", "pitch" },
		dials = { attribution = attribution, adaptability = 0.25, grudge = 0.95 },
	})
	return i, i:spawn("listener")
end

-- Two animals in the same thicket that sounded alike and then did not. Early on the creature is right
-- to hold them together: on what it can hear they are one thing. As they separate, the one track it
-- has is asked to be both, and keeps failing.
local function thicket(i: any, who: any, rounds: number)
	local gap = 0.0
	for at = 1, rounds do
		gap = math.min(0.40, gap + 0.03)
		local pitch = if at % 2 == 0 then 0.5 - gap else 0.5 + gap
		i:perceive(who, { { via = "hearing", returns = { { direction = 0.5, pitch = pitch } } } }, at + 1)
		i:tick(who, 0.5, at + 1)
	end
end

return function(t: any)
	-- While they still sound alike, one thing is the right answer, and it is not talked out of it by
	-- the first return that lands a little off.
	do
		local i, who = ears(0.3)
		thicket(i, who, 6)
		t.eq(#i:tracking(who), 1, "two things it cannot tell apart are one thing, to it")
	end

	-- Once they have separated, the track that keeps being asked to be both stops being one thing.
	do
		local i, who = ears(0.3)
		thicket(i, who, 26)
		t.ok(#i:tracking(who) >= 2, "a track that cannot account for what it keeps being handed is not one")
	end

	-- And it is a **split**, not a fresh start: what it had already worked out about where they are is
	-- not thrown away with the mistake.
	do
		local i, who = ears(0.3)
		thicket(i, who, 26)
		local placed = 0
		for _, track in i:tracking(who) do
			local where = i:estimate(who, track, "direction")
			if where ~= nil and math.abs(where - 0.5) < 0.2 then
				placed += 1
			end
		end
		t.ok(placed >= 2, "both of them are still where it heard them")
	end

	-- `attribution` is how far it will go on revising what it believes before it revises what it is
	-- looking at. Same ears, same thicket, same noises.
	do
		local credulous, one = ears(0.0)
		thicket(credulous, one, 13)
		local stubborn, other = ears(0.6)
		thicket(stubborn, other, 13)
		t.ok(#credulous:tracking(one) > #stubborn:tracking(other), "the credulous one gives up on it sooner")

		local mule, third = ears(1.0)
		thicket(mule, third, 26)
		t.eq(#mule:tracking(third), 1, "and one that will not be told holds them together to the end")
	end

	-- One animal, heard imperfectly over and over, is not torn apart. A creature that split on every
	-- mediocre match would end up with a new thing per moment and could never learn about anything.
	do
		local i, who = ears(0.3)
		local wobble = 0.0
		for at = 1, 30 do
			wobble = -wobble
			i:perceive(who, {
				{ via = "hearing", returns = { { direction = 0.5 + wobble * 0.03, pitch = 0.6 + wobble * 0.05 } } },
			}, at + 1)
			i:tick(who, 0.5, at + 1)
		end
		t.eq(#i:tracking(who), 1, "and one thing heard imperfectly is still one thing")
	end
end
