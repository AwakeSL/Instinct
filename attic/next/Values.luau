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
	about = true,
	doing = true,
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
	local sites = 0
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
				sites += 1
				table.insert(mods, { op = "times", stage = scale.stage, operand = operand, site = sites })
			end
		elseif not RESERVED[key] then
			local op = reg.operators[key]
			if op == nil then
				fail(site, ("%q is not a declared operator"):format(key))
			end
			local operand = Values.compile(reg, value, site)
			costs += op.costs + operand.costs
			sites += 1
			table.insert(mods, { op = key, stage = op.stage, operand = operand, site = sites })
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

-- `ctx`, when given, lets temporal operators see their own past. It carries `recall(site)` and
-- `remember(site, past)` -- keyed by the caller however it needs, since the same expression applied
-- to two subjects needs two histories -- and `now`, so an operator can tell how long ago it was.
export type Ctx = {
	recall: (string) -> any,
	remember: (string, any) -> (),
	now: number,
}

function Values.resolve(
	reg: Registry.Registry,
	ev: EV,
	look: (string) -> (number?, number),
	baseValue: number?,
	baseSpread: number?,
	ctx: Ctx?
): (number?, number)
	if ev.ref ~= nil then
		return look(ev.ref :: string)
	end

	local value = if baseValue ~= nil then baseValue else ev.const
	local held = if baseSpread ~= nil then baseSpread else ev.spread
	local variance = held * held

	for _, term in ev.terms do
		local tv, ts = Values.resolve(reg, term, look, nil, nil, ctx)
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
		local ov, os = Values.resolve(reg, mod.operand, look, nil, nil, ctx)
		if ov == nil then
			return nil, 0
		end
		local op = reg.operators[mod.op]

		local next: number?
		if op.recalls then
			-- A temporal operator: it is handed what it last produced here and how long ago, and
			-- returns nil the first time, because change is not a thing a single moment has.
			if ctx == nil then
				return nil, 0
			end
			local site = ("%s#%d"):format(mod.op, mod.site)
			local past = ctx.recall(site)
			if past ~= nil then
				past = { input = past.input, output = past.output, since = math.max(ctx.now - past.at, 1e-4) }
			end
			next = op.apply(current, ov, past)
			ctx.remember(site, { input = current, output = next, at = ctx.now })
		else
			next = op.apply(current, ov)
		end

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
