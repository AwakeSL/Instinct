--!strict

local Fixture = require("./Fixture")

local function thief(dials: any?): (any, any)
	local i = Fixture.world()
	local d: any = {
		tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1,
		adaptability = 0.5, capacity = 0.8, grudge = 0.95, attribution = 0.8, insight = 0.5,
	}
	for k, v in pairs(dials or {}) do
		d[k] = v
	end
	Fixture.elf(i, {
		feels = { "fear", "anger" },
		expects = {
			integrity = { 1.00, spread = 0.05 },
			energy = { 0.70, spread = 0.20 },
			hydration = { 0.90, spread = 0.15 },
			safety = { 1.00, spread = 0.10 },
			wealth = { 0.90, spread = 0.10 },
		},
		dials = d,
	})
	i:ready()
	return i, i:spawn("elf", { seed = 91 })
end

local function body(wealth: number): any
	return Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0, wealth = wealth })
end

local function flare(): any
	return Fixture.seen("flare1", "flare", { distance = 20, at = true })
end

local function night(i: any, elf: any, at: number, wealthBefore: number, wealthAfter: number)
	i:perceive(elf, { body(wealthBefore), flare() })
	i:think(elf, 0.5, at)
	i:perceive(elf, { body(wealthAfter) })
	i:think(elf, 0.5, at + 10)
end

local function learnedAbout(i: any, elf: any, kind: string): any
	for _, entry in i:stateOf(elf).learned do
		if entry.about == kind then
			return entry
		end
	end
	return nil
end

return function(t: any)
	local i, elf = thief()
	i:perceive(elf, { body(0.9), flare() })
	i:think(elf, 0.5, 1)
	t.eq(learnedAbout(i, elf, "flare"), nil, "a flare on its own teaches nothing")

	night(i, elf, 10, 0.9, 0.3)
	t.ok(i:stats().unexplained > 0, "wealth vanishing with no cause is counted as unexplained")
	t.ok(learnedAbout(i, elf, "flare") ~= nil, "and the only recent anomaly gets the blame")
	t.ok(i:stats().associations > 0, "an association is formed, not authored")

	i:perceive(elf, { body(0.9), flare() })
	local guarded = i:think(elf, 0.5, 100)
	t.ok(guarded ~= nil, "the next flare now predicts a loss")
	local why = i:why(elf)
	t.eq(why.because.quantity, "wealth", "and the creature is worried about its things")
	t.eq(why.because.subject, "flare1", "attributed to the flare it once followed")

	local honest, hElf = thief()
	honest:perceive(hElf, { body(0.9), flare() })
	honest:think(hElf, 0.5, 1)
	honest:perceive(hElf, { body(0.9) })
	honest:think(hElf, 0.5, 11)
	t.eq(learnedAbout(honest, hElf, "flare"), nil, "a flare with no theft after it teaches nothing")

	local doubter, dElf = thief({ attribution = 0.1 })
	night(doubter, dElf, 10, 0.9, 0.3)
	t.ok(doubter:stats().unexplained > 0, "a self doubting creature still notices the loss")
	t.eq(learnedAbout(doubter, dElf, "flare"), nil, "but concludes it misplaced its own things")

	local forgetful, fElf = thief({ capacity = 0.0, grudge = 0.05 })
	forgetful:perceive(fElf, { body(0.9), flare() })
	forgetful:think(fElf, 0.5, 10)
	for step = 1, 6 do
		forgetful:perceive(fElf, { body(0.9) })
		forgetful:think(fElf, 0.5, 10 + step * 40)
	end
	forgetful:perceive(fElf, { body(0.3) })
	forgetful:think(fElf, 0.5, 400)
	t.eq(learnedAbout(forgetful, fElf, "flare"), nil,
		"a cause older than the creature's reach can never be learned, however often it repeats")

	local blamed = i:stateOf(elf).blamed
	t.eq(blamed, "flare1", "blame names the subject, not just the kind")

	local fooled, foElf = thief()
	night(fooled, foElf, 10, 0.9, 0.3)
	t.ok(learnedAbout(fooled, foElf, "flare") ~= nil, "the association forms")
	for round = 1, 10 do
		fooled:perceive(foElf, { body(0.9), flare() })
		fooled:think(fooled and foElf, 0.5, 100 + round * 20)
		fooled:perceive(foElf, { body(0.9) })
		fooled:think(foElf, 0.5, 100 + round * 20 + 10)
	end
	t.eq(learnedAbout(fooled, foElf, "flare"), nil,
		"but flares without thefts disconfirm it, and the creature stops reacting")
	t.ok(fooled:stats().recanted > 0, "recanting a learned association is counted")

	local stubborn, stElf = thief({ insight = 0.0, grudge = 0.99 })
	night(stubborn, stElf, 10, 0.9, 0.3)
	t.ok(learnedAbout(stubborn, stElf, "flare") ~= nil, "a creature with no insight forms it too")
end
