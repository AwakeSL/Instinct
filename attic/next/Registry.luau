--!strict
-- Declarations. Everything a world contains before any creature exists in it.
--
-- The big change from `src`: `quantity` and `feature` are gone, and there is one concept in their
-- place -- a **reading**. Both were names for something a creature can read, and the only difference
-- was where the number came from, which the `from` channel already records. A creature's own hunger
-- is a reading about `self` arriving through the body channel.

-- Deliberately requires nothing. `Values` needs the registry's operator table to compile an
-- expression, so a static require in this direction would close a cycle; the compiler is handed in
-- instead, on the same table it compiles against.
local Registry = {}

export type Reading = {
	name: string,
	from: { string },
	expr: any?, -- nil for a raw reading; an expression for a derived one
	costs: number,
}

export type Operator = {
	name: string,
	stage: number,
	costs: number,
	apply: (number, number, any?) -> number?,
	spreads: ((number, number, number, number, number) -> number)?,
	recalls: boolean,
}

export type Registry = {
	senses: { [string]: any },
	readings: { [string]: Reading },
	operators: { [string]: Operator },
	kinds: { [string]: any },
	actions: { [string]: any },
	actionOrder: { string },
	species: { [string]: any },
	taken: { [string]: string },
	compile: (any, string) -> any,
}

local function fail(site: string, message: string): never
	error(("[instinct] %s: %s"):format(site, message), 0)
end

local function needName(name: any, site: string)
	if type(name) ~= "string" or name == "" then
		fail(site, "needs a name")
	end
end

-- One namespace for every declared word, so a reading and an operator can never collide and quietly
-- shadow each other inside an expression.
local function reserve(self: Registry, name: string, what: string, site: string)
	local held = self.taken[name]
	if held ~= nil then
		fail(site, ("already a %s; every declared name is unique"):format(held))
	end
	self.taken[name] = what
end

function Registry.new(): Registry
	return {
		senses = {},
		readings = {},
		operators = {},
		kinds = {},
		actions = {},
		actionOrder = {},
		species = {},
		taken = {},
		compile = function(_authored: any, site: string): any
			fail(site, "no expression compiler was installed on this registry")
		end,
	}
end

function Registry.sense(self: Registry, name: string, decl: any?)
	local site = ("sense %q"):format(tostring(name))
	needName(name, site)
	if self.senses[name] ~= nil then
		fail(site, "already declared")
	end
	reserve(self, name, "sense", site)
	local row = decl or {}
	-- How much the channel is to be believed, when a percept does not say for itself. Ears are worse
	-- than eyes, and a creature with bad ears is not one that hears wrong things -- it is one that
	-- holds what it hears loosely, and so can be talked out of it.
	if row.reliable ~= nil and (type(row.reliable) ~= "number" or row.reliable < 0 or row.reliable > 1) then
		fail(site, "`reliable` is how far the channel is to be believed, from 0 to 1")
	end
	self.senses[name] = { name = name, needs = row.needs, reliable = row.reliable }
end

function Registry.operator(self: Registry, name: string, decl: any)
	local site = ("operator %q"):format(tostring(name))
	needName(name, site)
	if self.operators[name] ~= nil then
		fail(site, "already declared")
	end
	if type(decl) ~= "table" or type(decl.stage) ~= "number" then
		fail(site, "declares a numeric stage; precedence is data")
	end
	if type(decl.apply) ~= "function" then
		fail(site, "declared with no implementation is a load error")
	end
	reserve(self, name, "operator", site)
	self.operators[name] = table.freeze({
		name = name,
		stage = decl.stage,
		costs = decl.costs or 0,
		apply = decl.apply,
		spreads = decl.spreads,
		-- A temporal operator. `apply` receives a third argument carrying what it last saw at this
		-- site for this subject, and how long ago, so `delta` and `sustain` are expressible at all.
		-- Without this a feature is a pure function of the present and change-in-anything cannot be
		-- written down, which is why `closing` had to be authored rather than found.
		recalls = decl.recalls == true,
	})
end

function Registry.reading(self: Registry, name: string, decl: any?)
	local site = ("reading %q"):format(tostring(name))
	needName(name, site)
	if self.readings[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}

	local from: { string } = {}
	if type(row.from) == "string" then
		from = { row.from }
	elseif type(row.from) == "table" then
		from = table.clone(row.from)
	end
	for _, channel in from do
		if self.senses[channel] == nil then
			fail(site, ("reads sense %q, which nobody declared"):format(tostring(channel)))
		end
	end

	reserve(self, name, "reading", site)

	local expr = nil
	local costs = 0
	if row.is ~= nil then
		expr = self.compile(row.is, site)
		costs = expr.costs
	end

	-- A reading may be a **projection**: not what something reads, but what the creature expects it to
	-- read. "I predict my health will fall" is then an ordinary input, and anything at all can be built
	-- on it. `after` narrows it to what comes due within that long, which is a question a creature can
	-- answer without anybody deciding whether horizons compound.
	-- A reading may report **how well the creature knows something** rather than what it is. That is
	-- an ordinary fact about a thing, available to be built on like any other -- and it is what makes
	-- curiosity expressible at all, since a creature with no way to read its own uncertainty can only
	-- ever be curious about actions, never about things.
	local unsure = row.unsure
	if unsure ~= nil then
		if expr ~= nil then
			fail(site, "gives both `is` and `unsure`; pick one")
		end
		if type(unsure) ~= "string" or self.readings[unsure] == nil then
			fail(site, ("is unsure of %q, a reading nobody declared"):format(tostring(unsure)))
		end
	end

	local predicts = row.predicts
	if predicts ~= nil then
		if unsure ~= nil then
			fail(site, "gives both `unsure` and `predicts`; pick one")
		end
		if expr ~= nil then
			fail(site, "gives both `is` and `predicts`; pick one")
		end
		if type(predicts) ~= "string" or self.readings[predicts] == nil then
			fail(site, ("predicts %q, a reading nobody declared"):format(tostring(predicts)))
		end
		if row.after ~= nil and (type(row.after) ~= "number" or row.after <= 0) then
			fail(site, "`after` on a projection is how far ahead to look, and must be positive")
		end
	end

	self.readings[name] = table.freeze({
		name = name,
		from = table.freeze(from),
		expr = expr,
		predicts = predicts,
		unsure = unsure,
		after = row.after,
		costs = costs,
	})
end

-- An emotion is a derived reading with two powers a plain expression does not have: it **lingers**,
-- and it **acts back on the dials**. Everything else about it -- what it is built from, that it can be
-- read, that other things can be built on it -- is exactly a reading, because that is all it is.
function Registry.emotion(self: Registry, name: string, decl: any?)
	local site = ("emotion %q"):format(tostring(name))
	needName(name, site)
	if self.readings[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	if row.is == nil then
		fail(site, "says nothing it is built from")
	end
	reserve(self, name, "reading", site)

	-- The fraction of itself it keeps per second. Onset is immediate, which is the whole point of
	-- having one: a creature does not become afraid gradually, it stops being afraid gradually.
	local decays = row.decays
	if decays ~= nil and (type(decays) ~= "number" or decays < 0 or decays >= 1) then
		fail(site, "`decays` is the fraction it keeps each second, from 0 up to but not including 1")
	end

	local modulates: any = {}
	local precision: any = {}
	for dial, factor in pairs(row.modulates or {}) do
		if dial == "precision" then
			if type(factor) ~= "table" then
				fail(site, "`modulates.precision` is a table of reading to factor")
			end
			for reading, scale in pairs(factor) do
				if self.readings[reading] == nil then
					fail(site, ("sharpens %q, a reading nobody declared"):format(tostring(reading)))
				end
				if type(scale) ~= "number" or scale <= 0 then
					fail(site, ("sharpens %q by something that is not a positive number"):format(reading))
				end
				precision[reading] = scale
			end
			continue
		end
		if type(factor) ~= "number" or factor < 0 then
			fail(site, ("modulates %q by something that is not a number at or above zero"):format(tostring(dial)))
		end
		modulates[dial] = factor
	end

	local expr = self.compile(row.is, site)
	self.readings[name] = table.freeze({
		name = name,
		from = table.freeze({}),
		expr = expr,
		emotion = true,
		decays = decays or 0,
		modulates = table.freeze(modulates),
		precision = table.freeze(precision),
		costs = expr.costs,
	})
end

function Registry.kind(self: Registry, name: string, decl: any?)
	local site = ("kind %q"):format(tostring(name))
	needName(name, site)
	if self.kinds[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	local is: { string } = {}
	for _, parent in (row.is or {}) :: { string } do
		if self.kinds[parent] == nil then
			fail(site, ("is a %q, which nobody declared"):format(tostring(parent)))
		end
		table.insert(is, parent)
	end
	reserve(self, name, "kind", site)
	self.kinds[name] = table.freeze({ name = name, is = table.freeze(is) })
end

-- Every kind a thing counts as, itself included, walking up the chain.
function Registry.kindsOf(self: Registry, name: string?): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local function walk(here: string?)
		if here == nil or out[here] then
			return
		end
		local kind = self.kinds[here]
		if kind == nil then
			return
		end
		out[here] = true
		for _, parent in kind.is do
			walk(parent)
		end
	end
	walk(name)
	return out
end

-- An action is a thing a body can do. It carries no predictions of its own: what it does is said by
-- a prediction conditioned on `doing`, which is the same shape as a prediction conditioned on a kind.
-- There is no separate notion of what an action's effects are.
function Registry.action(self: Registry, name: string, decl: any?)
	local site = ("action %q"):format(tostring(name))
	needName(name, site)
	if self.actions[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	reserve(self, name, "action", site)

	-- What has to be true of the creature before this action can do what it claims. Written in the
	-- same pattern vocabulary as `about`, because it is the same question asked of the creature
	-- itself. There is deliberately no matching `settles`: what raises a reading is already something
	-- the creature predicts, so naming it twice would be naming it once too often.
	local requires = row.requires
	if requires ~= nil then
		if type(requires) ~= "table" then
			fail(site, "`requires` is a pattern of readings that must hold before it can be done")
		end
		for key in pairs(requires) do
			if self.readings[key] == nil then
				fail(site, ("requires %q, a reading nobody declared"):format(tostring(key)))
			end
		end
		requires = table.freeze(table.clone(requires))
	end

	self.actions[name] = table.freeze({
		name = name,
		requires = requires,
		costs = table.freeze(table.clone(row.costs or {})),
	})
	table.insert(self.actionOrder, name)
end

-- A prediction: given these circumstances, this reading will be so, that long from now.
--
-- `changes` is a delta and `reads` is a level, and they compose differently -- deltas add, levels
-- merge by precision. Two causes each costing a little add up; two guesses at a value do not.
local function compilePredicts(self: Registry, list: any, site: string): { any }
	local out = {}
	for index, entry in ipairs(list or {}) do
		if type(entry) ~= "table" then
			fail(site, ("predicts[%d] is a table"):format(index))
		end

		local form: string? = nil
		local body: any = nil
		if entry.changes ~= nil then
			form, body = "change", entry.changes
		end
		if entry.reads ~= nil then
			if form ~= nil then
				fail(site, ("predicts[%d] gives both `changes` and `reads`; pick one"):format(index))
			end
			form, body = "level", entry.reads
		end
		if form == nil then
			fail(site, ("predicts[%d] says neither `changes` nor `reads`"):format(index))
		end

		local reading: string? = nil
		local expr: any = nil
		for key, authored in pairs(body) do
			if self.readings[key] == nil then
				fail(site, ("predicts %q, a reading nobody declared"):format(tostring(key)))
			end
			if reading ~= nil then
				fail(site, "predicts two readings in one entry; give each its own")
			end
			reading = key
			expr = self.compile(authored, site)
		end
		if reading == nil then
			fail(site, ("predicts[%d] names no reading"):format(index))
		end

		-- `by` scales the claim by what is read off the thing the condition matched. *A wolf costs me
		-- health in proportion to how near it is* is one prediction, not a family of them -- and each
		-- entry is an ordinary authored expression, so there is no second little language for it.
		if entry.by ~= nil then
			if type(entry.by) ~= "table" or #entry.by == 0 then
				fail(site, ("predicts[%d] `by` is a list of expressions to scale the claim by"):format(index))
			end
			if self.operators.times == nil then
				fail(site, "`by` needs a `times` operator, which nobody declared")
			end
			local mods = table.clone(expr.mods)
			local highest = 0
			for _, mod in mods do
				if mod.site > highest then
					highest = mod.site
				end
			end
			local costs = expr.costs
			for _, authored in ipairs(entry.by) do
				local operand = self.compile(authored, site)
				highest += 1
				costs += operand.costs + self.operators.times.costs
				table.insert(mods, {
					op = "times",
					stage = self.operators.times.stage,
					site = highest,
					operand = operand,
				})
			end
			expr = { const = expr.const, spread = expr.spread, terms = expr.terms, mods = mods, costs = costs }
		end

		-- `about` is a kind, or a pattern of readings, or absent for "whatever I am looking at".
		local about = entry.about
		if type(about) == "string" and self.kinds[about] == nil then
			fail(site, ("is about %q, a kind nobody declared"):format(about))
		end
		if type(about) == "table" then
			for key in pairs(about) do
				if key ~= "kind" and self.readings[key] == nil then
					fail(site, ("is about %q, a reading nobody declared"):format(tostring(key)))
				end
			end
		end

		if entry.doing ~= nil and self.actions[entry.doing] == nil then
			fail(site, ("is conditioned on doing %q, an action nobody declared"):format(tostring(entry.doing)))
		end

		local after = 0
		if entry.after ~= nil then
			local horizon = self.compile(entry.after, site)
			after = horizon.const or 0
		end
		if after <= 0 then
			fail(site, ("predicts[%d] needs an `after`; a prediction with no horizon cannot be checked"):format(index))
		end

		table.insert(out, table.freeze({
			about = about,
			doing = entry.doing,
			of = entry.of, -- nil means the subject the condition matched; "self" means the creature
			form = form,
			reading = reading,
			expr = expr,
			after = after,
			-- What it was written as, kept so a creature's beliefs can be handed back out as a
			-- declaration. A compiled expression is not something anybody can read or re-declare.
			source = table.freeze(table.clone(entry)),
		}))
	end
	return out
end

function Registry.species(self: Registry, name: string, decl: any?)
	local site = ("species %q"):format(tostring(name))
	needName(name, site)
	if self.species[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}

	local forms: { string } = {}
	for _, reading in (row.forms or {}) :: { string } do
		if self.readings[reading] == nil then
			fail(site, ("forms %q, a reading nobody declared"):format(tostring(reading)))
		end
		table.insert(forms, reading)
	end

	local senses: { [string]: any } = {}
	for channel, cfg in (row.senses or {}) :: any do
		if self.senses[channel] == nil then
			fail(site, ("has sense %q, which nobody declared"):format(tostring(channel)))
		end
		senses[channel] = cfg
	end

	local wants: { [string]: any } = {}
	for reading, authored in (row.wants or {}) :: any do
		if self.readings[reading] == nil then
			fail(site, ("wants %q, a reading nobody declared"):format(tostring(reading)))
		end
		local value = if type(authored) == "table" then authored[1] else authored
		wants[reading] = {
			value = value,
			spread = if type(authored) == "table" then (authored.spread or 0.1) else 0.1,
			after = if type(authored) == "table" then (authored.after or 0) else 0,
		}
	end

	reserve(self, name, "species", site)
	self.species[name] = table.freeze({
		name = name,
		kind = row.kind,
		senses = senses,
		forms = table.freeze(forms),
		wants = wants,
		predicts = table.freeze(compilePredicts(self, row.predicts, site)),
		dials = row.dials or {},
	})
end

return Registry
