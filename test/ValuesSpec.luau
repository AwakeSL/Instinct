--!strict

local Instinct = require("../src")
local Registry = require("../src/Registry")
local Values = require("../src/Values")

local function fresh(): any
	local i = Instinct.new():defaults()
	i:quantity("amount")
	return i
end

local function resolve(i: any, authored: any, raw: any?): (number?, number)
	local ev = Values.compile(i.reg, authored, "test")
	return Values.resolve(i.reg, ev, function(name: string): (number?, number)
		local held = (raw or {})[name]
		if type(held) == "table" then
			return held[1], held[2]
		end
		if type(held) == "number" then
			return held, 0
		end
		return nil, 0
	end)
end

local function near(t: any, got: number?, want: number, message: string, slack: number?)
	t.ok(got ~= nil and math.abs((got :: number) - want) <= (slack or 1e-6), message)
end

return function(t: any)
	local i = fresh()

	near(t, (resolve(i, 15)), 15, "a bare number is itself")
	near(t, (resolve(i, { 15, 23 })), 38, "the array part means sum, so { 15, 23 } is 38")
	near(t, (resolve(i, { 15, 23, 2 })), 40, "and it keeps summing")
	near(t, (resolve(i, "gap", { gap = 7 })), 7, "a name reads a value")
	near(t, (resolve(i, { 10, "gap" }, { gap = 5 })), 15, "a name sums with a literal")

	near(t, (resolve(i, { 40, times = 2 })), 80, "a named key is an operator on the sum")
	near(t, (resolve(i, { 10, "gap", times = 2 }, { gap = 5 })), 30, "the sum happens before the modifier")
	near(t, (resolve(i, { 0.4, { "progress", times = 0.5 } }, { progress = 0.6 })), 0.7, "a nested list is a term")

	near(t, (resolve(i, { 60, inverted = 60 })), 0, "inverted at the far end is zero")
	near(t, (resolve(i, { 0, inverted = 60 })), 1, "inverted at zero distance is one")
	near(t, (resolve(i, { 30, inverted = 60 })), 0.5, "and halfway is a half")

	t.eq((resolve(i, { 1, over = 0 })), nil, "a divide by zero refuses rather than throwing")
	t.eq((resolve(i, "missing")), nil, "an unresolvable name refuses")
	t.eq((resolve(i, { 1, "missing" })), nil, "and a sum containing one refuses whole")

	i:operator("early", { stage = 1, apply = function(a, b) return a - b end })
	i:operator("late", { stage = 9, apply = function(a, b) return a * b end })
	near(t, (resolve(i, { 10, late = 2, early = 4 })), 12, "stage decides the order, not the table")

	t.err(function()
		resolve(i, { 10, nonsense = 2 })
	end, "not a declared operator", "an undeclared operator is a load error")

	t.err(function()
		i:operator("times", { stage = 1, apply = function(a, b) return a end })
	end, "already declared", "a duplicate operator is refused")

	t.err(function()
		i:operator("noImpl", { stage = 1 })
	end, "no implementation", "an operator with no apply is refused")

	local _, plainSpread = resolve(i, { 5, spread = 2 })
	near(t, plainSpread, 2, "a literal carries its own spread")

	local _, summed = resolve(i, { { 3, spread = 3 }, { 4, spread = 4 } })
	near(t, summed, 5, "spreads add in quadrature across a sum", 1e-4)

	local product, productSpread = resolve(i, { { 4, spread = 1 }, times = { 3, spread = 1 } })
	near(t, product, 12, "a product resolves")
	t.ok(productSpread > 1, "and uncertainty propagates through the arithmetic")
	t.ok(productSpread > 4.9 and productSpread < 5.1, "two uncertain terms give a wider product than either")

	local _, tightSpread = resolve(i, { { 4, spread = 0 }, times = { 3, spread = 0 } })
	near(t, tightSpread, 0, "certain terms give a certain result")

	i:operator("halfSpread", {
		stage = 5,
		apply = function(a, b)
			return a + b
		end,
		spreads = function(_v, s, _ov, _os, _nv)
			return s * 0.5
		end,
	})
	local _, declared = resolve(i, { { 10, spread = 4 }, halfSpread = 1 })
	near(t, declared, 2, "an operator may declare how it carries spread")

	local Reg = Registry.new()
	t.ok(Reg ~= nil, "a registry constructs")
end
