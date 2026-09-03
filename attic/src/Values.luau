--!strict
--!native

local Registry = require("./Registry")

local Values = {}

export type EV = {
	ref: string?,
	const: number?,
	spread: number,
	terms: { EV },
	mods: { { op: string, stage: number, operand: EV } },
	costs: number,
}

local RESERVED: { [string]: boolean } = {
	spread = true,
	after = true,
	of = true,
	when = true,

}

local function fail(site: string, message: string): never
	error(("[instinct] %s: %s"):format(site, message), 0)
end

local EMPTY_TERMS: { EV } = table.freeze({})
local EMPTY_MODS: { any } = table.freeze({})

function Values.compile(reg: Registry.Registry, authored: any, site: string): EV
	if type(authored) == "number" then
		return table.freeze({ const = authored, spread = 0, terms = EMPTY_TERMS, mods = EMPTY_MODS, costs = 0 }) :: any
	end

	if type(authored) == "string" then
		return table.freeze({ ref = authored, spread = 0, terms = EMPTY_TERMS, mods = EMPTY_MODS, costs = 0 }) :: any
	end

	if type(authored) ~= "table" then
		fail(site, ("a value is a number, a name or a list, not a %s"):format(typeof(authored)))
	end

	local const: number? = nil
	local terms: { EV } = {}
	local costs = 0

	for _, element in ipairs(authored) do
		if type(element) == "number" then
			const = (const or 0) + element
		else
			local sub = Values.compile(reg, element, site)
			costs += sub.costs
			table.insert(terms, sub)
		end
	end

	local mods = {}
	local spread = 0
	for key, value in pairs(authored) do
		if type(key) ~= "string" then
			continue
		end
		if key == "spread" then
			if type(value) ~= "number" then
				fail(site, "`spread` is a number")
			end
			spread = value
		elseif key == "by" then
			local scale = reg.operators.times
			if scale == nil then
				fail(site, "`by` scales through `times`, which nobody declared")
			end
			local names: { any } = if type(value) == "table" and #value > 0 then value else { value }
			for _, each in names do
				local operand = Values.compile(reg, each, site)
				costs += scale.costs + operand.costs
				table.insert(mods, { op = "times", stage = scale.stage, operand = operand })
			end
		elseif not RESERVED[key] then
			local op = reg.operators[key]
			if op == nil then
				fail(site, ("%q is not a declared operator"):format(key))
			end
			local operand = Values.compile(reg, value, site)
			costs += op.costs + operand.costs
			table.insert(mods, { op = key, stage = op.stage, operand = operand })
		end
	end

	table.sort(mods, function(a, b)
		if a.stage ~= b.stage then
			return a.stage < b.stage
		end
		return a.op < b.op
	end)

	if const == nil and #terms == 0 and #mods > 0 then
		fail(site, "a modifier needs something to modify")
	end

	return table.freeze({
		const = const,
		spread = spread,
		terms = table.freeze(terms),
		mods = table.freeze(mods),
		costs = costs,
	}) :: any
end

local function propagate(op: Registry.Operator, v: number, s: number, ov: number, os: number, nv: number): number
	if op.spreads ~= nil then
		return (op.spreads :: any)(v, s, ov, os, nv)
	end
	local fromLeft = 0
	if s > 0 then
		local hi = op.apply(v + s, ov)
		local lo = op.apply(v - s, ov)
		if hi ~= nil and lo ~= nil then
			fromLeft = math.abs(hi - lo) * 0.5
		end
	end
	local fromRight = 0
	if os > 0 then
		local hi = op.apply(v, ov + os)
		local lo = op.apply(v, ov - os)
		if hi ~= nil and lo ~= nil then
			fromRight = math.abs(hi - lo) * 0.5
		end
	end
	return math.sqrt(fromLeft * fromLeft + fromRight * fromRight)
end

function Values.resolve(
	reg: Registry.Registry,
	ev: EV,
	look: (string) -> (number?, number),
	baseValue: number?,
	baseSpread: number?
): (number?, number)
	if ev.ref ~= nil then
		return look(ev.ref :: string)
	end

	local value = if baseValue ~= nil then baseValue else ev.const
	local held = if baseSpread ~= nil then baseSpread else ev.spread
	local variance = held * held

	for _, term in ev.terms do
		local tv, ts = Values.resolve(reg, term, look)
		if tv == nil then
			return nil, 0
		end
		value = (value or 0) + tv
		variance += ts * ts
	end

	if value == nil then
		return nil, 0
	end

	local spread = math.sqrt(variance)
	local current = value :: number

	for _, mod in ev.mods do
		local ov, os = Values.resolve(reg, mod.operand, look)
		if ov == nil then
			return nil, 0
		end
		local op = reg.operators[mod.op]
		local next = op.apply(current, ov)
		if next == nil then
			return nil, 0
		end
		spread = propagate(op, current, spread, ov, os, next)
		current = next
	end

	return current, spread
end

function Values.refs(ev: EV, out: { string })
	if ev.ref ~= nil then
		table.insert(out, ev.ref :: string)
		return
	end
	for _, term in ev.terms do
		Values.refs(term, out)
	end
	for _, mod in ev.mods do
		Values.refs(mod.operand, out)
	end
end

function Values.isConst(ev: EV): boolean
	return ev.ref == nil and #ev.terms == 0 and #ev.mods == 0
end

return Values
