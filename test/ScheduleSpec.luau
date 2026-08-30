--!strict

local Fixture = require("./Fixture")

local function herd(count: number): (any, { any })
	local i = Fixture.world()
	Fixture.elf(i, {
		feels = { "fear", "anger" },
		dials = { tempo = 1.0, caution = 0.1, attention = 1.0, commitment = 0.1 },
	})
	i:ready()
	local ids = {}
	for n = 1, count do
		table.insert(ids, i:spawn("elf", { seed = 200 + n }))
	end
	return i, ids
end

local function calm(): any
	return Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.9, safety = 1.0 })
end

local function parched(): any
	return Fixture.body({ integrity = 1.0, energy = 0.7, hydration = 0.1, safety = 1.0 })
end

return function(t: any)
	local i, ids = herd(6)
	for _, id in ids do
		i:perceive(id, { calm() })
	end
	local served = i:step(0.1, 1)
	t.eq(served, 6, "every creature gets a think when there is budget for it")

	local before = i:stats().skipped
	i:step(0.001, 1.001)
	t.ok(i:stats().skipped > before, "a second step inside the tempo window skips them")
	t.eq(i:stats().starved, 0, "skipping for tempo is not starvation")

	local tight, tightIds = herd(6)
	for index, id in tightIds do
		tight:perceive(id, { if index == 3 then parched() else calm() })
	end
	tight:step(0.1, 1)
	local pressures = {}
	for _, id in tightIds do
		table.insert(pressures, tight:stateOf(id).pressure)
	end
	t.ok(pressures[3] > pressures[1], "the creature in trouble carries the higher pressure")

	for _, id in tightIds do
		tight:perceive(id, { if id == tightIds[3] then parched() else calm() })
	end
	local servedFew = tight:step(0.1, 10, { budgetMs = 0 })
	t.eq(servedFew, 0, "a budget of nothing serves nobody")
	t.ok(tight:stats().starved > 0, "and starvation is counted, unlike skipping")

	local order = {}
	for slot = 1, tight.high do
		local state = tight.state[slot]
		if state ~= nil then
			table.insert(order, state)
		end
	end
	table.sort(order, function(a, b)
		return a.pressure > b.pressure
	end)
	t.eq(order[1].id, tightIds[3], "the thirsty one is first in line when the budget is short")

	local fake = 0
	local clocked, clockedIds = herd(3)
	clocked:engine({
		clock = function()
			fake += 0.0001
			return fake
		end,
	})
	for _, id in clockedIds do
		clocked:perceive(id, { calm() })
	end
	t.eq(clocked:step(0.1, 1, { budgetMs = 1000 }), 3, "an injected clock drives the budget")

	local a, aIds = herd(2)
	local b, bIds = herd(2)
	for _, id in aIds do
		a:perceive(id, { parched() })
	end
	for _, id in bIds do
		b:perceive(id, { parched() })
	end
	a:step(0.1, 1)
	b:step(0.1, 1)
	t.eq(a:doing(aIds[1]), b:doing(bIds[1]), "the same inputs and the same clock give the same decision")
	t.eq(a:stateOf(aIds[1]).pressure, b:stateOf(bIds[1]).pressure, "and the same pressure, exactly")
end
