--!strict

local Fixture = require("./Fixture")

local function ready(): (any, any)
	local i = Fixture.world()
	Fixture.elf(i)
	i:ready()
	return i, i:spawn("elf", { seed = 7 })
end

return function(t: any)
	local i, elf = ready()

	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }),
	})
	t.eq(i:think(elf, 0.1, 1), nil, "a creature with nothing wanting does nothing")

	i:perceive(elf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.3, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 2, at = true }),
	})
	t.eq(i:think(elf, 0.1, 2), "drink", "a thirsty elf with water in reach drinks")

	local why = i:why(elf)
	t.eq(why.because.quantity, "hydration", "and says the thirst drove it")
	t.ok(why.because.spreads > 3, "reported in spreads, not raw error")

	local dry, dryElf = ready()
	dry:perceive(dryElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.3, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 40 }),
	})
	local chose = dry:think(dryElf, 0.1, 1)
	t.eq(chose, "walk_to", "water out of reach recruits a settler")

	local occupied, oElf = ready()
	occupied:perceive(oElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
	})
	t.eq(occupied:think(oElf, 0.1, 1), "stab", "a free elf stabs the wolf")

	local oState = occupied:stateOf(oElf)
	oState.doing = "guard"
	oState.busy = { arms = 2 }
	t.eq(occupied:think(oElf, 0.1, 2), "guard", "both arms guarding leaves none to stab with")
	local sawBlocked = false
	for _, row in occupied:why(oElf).considered do
		if row.action == "stab" and row.blocked == "parts" then
			sawBlocked = true
		end
	end
	t.ok(sawBlocked, "and the contention is reported, not hidden")

	oState.busy = { arms = 1 }
	t.eq(occupied:think(oElf, 0.1, 3), "stab", "one free arm is enough for a one armed action")

	local careful, cElf = ready()
	local cState = careful:stateOf(cElf)
	cState.dials.caution = { expr = { const = 0.97, spread = 0, terms = {}, mods = {}, costs = 0 } }
	careful:perceive(cElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.75, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 2, at = true }),
	})
	local timid = careful:think(cElf, 0.1, 1)
	t.eq(timid, nil, "a steep caution refuses a marginal error a shallow one accepts")
	t.ok(careful:stats().belowThreshold > 0, "and the refusal is counted, not silent")

	local bold, bElf = ready()
	bold:perceive(bElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.75, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 2, at = true }),
	})
	t.eq(bold:think(bElf, 0.1, 1), "drink", "while a shallow caution takes the same marginal error")

	local wolf, wElf = ready()
	wolf:perceive(wElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 6, approachRate = -4, size = 1, integrity = 0.9, at = true }),
	})
	local fight = wolf:think(wElf, 0.1, 1)
	t.ok(fight ~= nil, "a closing wolf produces an intent")
	local wWhy = wolf:why(wElf)
	t.eq(wWhy.because.quantity, "integrity", "driven by predicted harm")
	t.ok(wWhy.because.subject == "wolf1", "attributed to the wolf")

	local far, fElf = ready()
	far:perceive(fElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 }, { blade = true }),
		Fixture.seen("wolf1", "wolf", { distance = 200, approachRate = -4, size = 1, integrity = 0.9 }),
	})
	t.eq(far:think(fElf, 0.1, 1), nil, "the same wolf at two hundred studs predicts nothing")

	local tempo, tElf = ready()
	tempo:perceive(tElf, {
		Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.3, safety = 1.0 }),
		Fixture.seen("pond", "water", { distance = 2, at = true }),
	})
	tempo:think(tElf, 0.1, 1)
	local before = tempo:stats().thinks
	tempo:think(tElf, 0.001, 1.001)
	t.eq(tempo:stats().thinks, before, "a second think inside the tempo window is skipped")
	t.ok(tempo:stats().skipped > 0, "and counted as skipped rather than starved")
end
