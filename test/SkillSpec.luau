--!strict

local Fixture = require("./Fixture")

local function brute(skills: any): (any, any)
	local i = Fixture.world()
	Fixture.elf(i, {
		skills = skills,
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1, adaptability = 0.5 },
	})
	i:ready()
	return i, i:spawn("elf", { seed = 31 })
end

local function facing(i: any, elf: any, at: number): string?
	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { bow = true, blade = false }),
		Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
	})
	return i:think(elf, 0.1, at)
end

local function rowFor(i: any, elf: any, name: string): any
	for _, row in i:why(elf).considered do
		if row.action == name then
			return row
		end
	end
	return nil
end

return function(t: any)
	local i, elf = brute({ blade = 0.6, unarmed = 0.35, archery = 0.02 })
	local chose = facing(i, elf, 10)
	t.eq(chose, "punch", "a brute with no archery fights with its fists")

	local bow = rowFor(i, elf, "shoot")
	local fist = rowFor(i, elf, "punch")
	t.ok(bow ~= nil, "the bow was not forbidden, only considered")
	t.ok(bow.cancels > fist.cancels, "and it is predicted to do more than a punch")
	t.ok(bow.confidence < fist.confidence, "but the creature has no idea whether it will")
	t.ok(bow.score < fist.score, "so confidence, not damage, decides")

	local archer, aElf = brute({ blade = 0.6, unarmed = 0.35, archery = 0.9 })
	t.eq(facing(archer, aElf, 10), "shoot", "the same creature with the skill shoots instead")

	local wide = rowFor(i, elf, "shoot").confidence
	local tight = rowFor(archer, aElf, "shoot").confidence
	t.ok(tight > wide, "competence is the precision of a prediction, not a damage bonus")

	local learner, lElf = brute({ blade = 0.6, unarmed = 0.35, archery = 0.02 })
	facing(learner, lElf, 10)
	local before = nil
	for key, held in pairs(learner:stateOf(lElf).beliefs) do
		if key:find("action|shoot", 1, true) then
			before = held.s
		end
	end
	t.ok(before ~= nil, "using an action creates a belief about what it does")
	t.ok(before > 1.0, "held very wide when the creature is unskilled")

	local sure, sElf = brute({ blade = 0.6, unarmed = 0.35, archery = 0.9 })
	facing(sure, sElf, 10)
	local after = nil
	for key, held in pairs(sure:stateOf(sElf).beliefs) do
		if key:find("action|shoot", 1, true) then
			after = held.s
		end
	end
	t.ok(after < before / 4, "and far tighter when it is practised")
end
