--!strict

local Instinct = require("../src")
local Fixture = require("./Fixture")

return function(t: any)
	t.err(function()
		local i = Instinct.new():defaults()
		i:quantity("hydration")
		i:quantity("hydration")
	end, "already declared", "a duplicate quantity is refused")

	t.err(function()
		local i = Instinct.new():defaults()
		i:part("legs")
		i:sense("sight", { needs = "eyes" })
	end, "needs part", "a sense needing an undeclared part is refused")

	t.err(function()
		local i = Instinct.new():defaults()
		i:feature("proximity", { from = "sight" })
	end, "reads sense", "a feature reading an undeclared sense is refused")

	t.err(function()
		local i = Instinct.new():defaults()
		i:kind("wolf", { is = { "animal" } })
	end, "nobody declared", "a kind inheriting an undeclared kind is refused")

	t.err(function()
		local i = Instinct.new():defaults()
		i:action("stab", { occupies = { arms = 1 } })
	end, "occupies part", "an action occupying an undeclared part is refused")

	t.err(function()
		local i = Instinct.new():defaults()
		i:part("arms")
		i:action("stab", { occupies = { arms = 1 }, skill = "blade" })
	end, "names skill", "an action naming an undeclared skill is refused")

	t.err(function()
		local i = Fixture.world()
		Fixture.elf(i, { expects = { nonsense = { 1, spread = 0.1 } } })
	end, "expects", "a species expecting an undeclared quantity is refused")

	t.err(function()
		local i = Fixture.world()
		Fixture.elf(i, { forms = { "notAFeature" } })
	end, "forms", "a species forming an undeclared feature is refused")

	t.err(function()
		local i = Fixture.world()
		Fixture.elf(i, { parts = { wings = 2 } })
	end, "has part", "a species with an undeclared part is refused")

	t.err(function()
		local i = Fixture.world()
		Fixture.elf(i)
		Fixture.elf(i)
	end, "already declared", "a duplicate species is refused")

	t.err(function()
		local i = Fixture.world()
		Fixture.elf(i, {
			instinct = { { about = "dragon", predicts = {} } },
		})
		i:ready()
	end, "a kind nobody declared", "an instinct about an undeclared kind is refused at ready")

	t.err(function()
		local i = Fixture.world()
		Fixture.elf(i, {
			instinct = { { about = "wolf", predicts = { { of = "self", nonsense = -0.5 } } } },
		})
		i:ready()
	end, "a quantity nobody declared", "a prediction about an undeclared quantity is refused")

	t.err(function()
		local i = Fixture.world()
		Fixture.elf(i, {
			instinct = { { about = "wolf", predicts = { { of = "ghost", integrity = -0.5 } } } },
		})
		i:ready()
	end, "role", "a prediction about an undeclared role is refused")

	t.err(function()
		local i = Fixture.world()
		Fixture.elf(i)
		i:spawn("dragon")
	end, "a species nobody declared", "spawning an undeclared species is refused")

	local ok = Fixture.world()
	Fixture.elf(ok)
	ok:ready()
	t.ok(true, "a well formed vocabulary links")

	local one = ok:spawn("elf", { seed = 1 })
	local two = ok:spawn("elf", { seed = 2 })
	t.eq(ok:size(), 2, "two elves are alive")
	t.ok(one ~= two, "and they are different creatures")

	t.err(function()
		ok:spawn("elf", { id = one })
	end, "already alive", "spawning onto a live id is refused")

	t.ok(ok:remove(one), "remove reports it removed something")
	t.eq(ok:size(), 1, "and the count falls")
	t.eq(ok:think(one, 0, 1), nil, "a removed creature decides nothing")
end
