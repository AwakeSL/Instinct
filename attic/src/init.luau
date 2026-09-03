--!strict

local Registry = require("@self/Registry")
local Values = require("@self/Values")
local Percepts = require("@self/Percepts")
local Think = require("@self/Think")
local Defaults = require("@self/Defaults")
local Beliefs = require("@self/Beliefs")
local Emotions = require("@self/Emotions")
local Blame = require("@self/Blame")

local Instinct = {}
Instinct.__index = Instinct

-- Looking at something tightens what is believed about it, toward this floor at this rate. The
-- floor is not zero: watching a thing does not make you certain of it, it makes you better
-- informed than you were.
local WATCH_RATE = 1.2
local WATCH_FLOOR = 0.06

-- Drift sampling: how often to take a reading, how wide a newborn holds its own drift, and how
-- much to trust one reading. A creature that has never run down believes it never will.
local DRIFT_EVERY = 0.5
local DRIFT_UNSURE = 0.05
local DRIFT_NOISE = 0.02

local DIAL_DEFAULT: { [string]: number } = {
	patience = 0.5,
	commitment = 0.5,
	caution = 0.4,
	reaction = 0.25,
	tempo = 0.5,
	adaptability = 0.5,
	resilience = 0.5,
	grudge = 0.5,
	attention = 0.5,
	capacity = 0.5,
	attribution = 0.9,
	insight = 0.4,
	-- How much an option being UNKNOWN is worth, as against an option being good. At 0 a creature
	-- only ever does the thing it currently believes pays best, which sounds sensible and is how it
	-- gets permanently stuck: an option believed to be worth nothing is never picked, so it is never
	-- tested, so the belief that killed it can never be revised. Raised, a creature will try
	-- something it is merely unsure of when nothing it trusts is available.
	--
	-- Defaults to 0, and must. A creature that freezes under steep caution, or refuses to chain
	-- with no patience, is doing something the package deliberately specifies -- and an experiment
	-- admitted regardless of caution would quietly undo both. Venturing is a disposition a species
	-- is given, not a correction applied to every creature.
	venture = 0,
}

Instinct.DIALS = DIAL_DEFAULT

local function fail(message: string): never
	error(("[instinct] %s"):format(message), 0)
end

local function detect(): any
	local hooks: any = {}
	if (os :: any) ~= nil and (os :: any).clock ~= nil then
		hooks.clock = (os :: any).clock
	end
	return hooks
end

function Instinct.new(config: any?): any
	local settings = config or {}
	local reg = Registry.new()
	local self = setmetatable({
		reg = reg,
		per = Percepts.new(reg),
		clock = detect().clock,
		slotOf = {} :: { [any]: number },
		idOf = {} :: { [number]: any },
		state = {} :: { [number]: any },
		high = 0,
		count = 0,
		linked = false,
		counts = {
			thinks = 0,
			skipped = 0,
			starved = 0,
			belowThreshold = 0,
			chainsFormed = 0,
			chainsAbandoned = 0,
			actionsChosen = 0,
			unexplained = 0,
			associations = 0,
			acquired = 0,
			recanted = 0,
			signsRead = 0,
			learnedSocially = 0,
			learned = 0,
			violations = 0,
			released = 0,
		},
		seed = settings.seed or 0x1B51,
	}, Instinct)
	return self
end

function Instinct.engine(self: any, hooks: any): any
	if hooks.clock ~= nil then
		self.clock = if hooks.clock == false then nil else hooks.clock
	end
	return self
end

function Instinct.defaults(self: any): any
	Defaults(self)
	return self
end

local PASS = {
	quantity = "quantity",
	role = "role",
	sense = "sense",
	operator = "operator",
	part = "part",
	skill = "skill",
	feature = "feature",
	kind = "kind",
	action = "action",
	emotion = "emotion",
	sign = "sign",
	species = "species",
}

local LATE: { [string]: boolean } = { species = true }

for method, call in PASS do
	(Instinct :: any)[method] = function(self: any, name: string, decl: any?): any
		if self.linked and not LATE[method] then
			fail(("%s %q declared after ready()"):format(method, tostring(name)))
		end
		;(Registry :: any)[call](self.reg, name, decl)
		if self.linked then
			self:link(name)
		end
		return self
	end
end

local function isRange(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if #value ~= 2 then
		return false
	end
	if type(value[1]) ~= "number" or type(value[2]) ~= "number" then
		return false
	end
	for key in pairs(value) do
		if type(key) ~= "number" then
			return false
		end
	end
	return true
end

local function isDomainMap(reg: Registry.Registry, value: any): boolean
	if type(value) ~= "table" or #value > 0 then
		return false
	end
	local any = false
	for key in pairs(value) do
		if type(key) ~= "string" then
			return false
		end
		if reg.operators[key] ~= nil or key == "spread" then
			return false
		end
		any = true
	end
	return any
end

local function nextRandom(state: { n: number }): number
	state.n = (state.n * 1103515245 + 12345) % 2147483648
	return state.n / 2147483648
end

local function bake(reg: Registry.Registry, value: any, rng: { n: number }): any
	if type(value) == "number" then
		return value
	end
	if isRange(value) then
		return value[1] + (value[2] - value[1]) * nextRandom(rng)
	end
	if type(value) == "table" then
		local rolled: any = {}
		for key, element in pairs(value) do
			if type(key) == "number" and isRange(element) then
				rolled[key] = bake(reg, element, rng)
			else
				rolled[key] = element
			end
		end
		return rolled
	end
	return value
end

local function compilePredicts(reg: Registry.Registry, list: any, site: string): { any }
	local out = {}
	for index, entry in ipairs(list or {}) do
		if type(entry) ~= "table" then
			fail(("%s predicts[%d] is a table"):format(site, index))
		end
		local role = entry.of or "self"
		if not reg.roles[role] then
			fail(("%s predicts about role %q, which nobody declared"):format(site, tostring(role)))
		end
		local found = nil
		for key, authored in pairs(entry) do
			if type(key) ~= "string" or key == "of" or key == "after" or key == "when" then
				continue
			end
			if reg.quantities[key] == nil then
				fail(("%s predicts %q, a quantity nobody declared"):format(site, key))
			end
			if found ~= nil then
				fail(("%s predicts two quantities in one entry; give each its own"):format(site))
			end
			found = { quantity = key, expr = Values.compile(reg, authored, site) }
		end
		if found == nil then
			fail(("%s has a predicts entry naming no quantity"):format(site))
		end
		local after = 0
		if entry.after ~= nil then
			local horizon = Values.compile(reg, entry.after, site)
			after = horizon.const or 0
		end
		table.insert(out, {
			of = role,
			quantity = found.quantity,
			expr = found.expr,
			after = after,
			when = entry.when,
		})
	end
	return out
end

function Instinct.link(self: any, speciesName: string): any
	local reg = self.reg
	local species = reg.species[speciesName]
	if species == nil then
		return self
	end
	local site = ("species %q"):format(speciesName)
	for index, entry in ipairs(species.instinct) do
		if entry.about == nil then
			fail(("%s instinct[%d] names no `about`"):format(site, index))
		end
		if reg.kinds[entry.about] == nil then
			fail(("%s instinct[%d] is about %q, a kind nobody declared"):format(site, index, tostring(entry.about)))
		end
		entry.predicts = compilePredicts(reg, entry.predicts, ("%s instinct[%d]"):format(site, index))
	end
	local believes = {}
	for actionName, list in pairs(species.believes) do
		believes[actionName] = compilePredicts(reg, list, ("%s believes %q"):format(site, actionName))
	end
	species.believes = believes
	return self
end

function Instinct.ready(self: any): any
	if self.linked then
		return self
	end
	local reg = self.reg

	for _, name in reg.featureOrder do
		local feature = reg.features[name]
		if feature.raw ~= nil then
			feature.expr = Values.compile(reg, feature.raw, ("feature %q"):format(name))
			feature.costs = feature.expr.costs
		end
	end

	for _, name in reg.actionOrder do
		local action = reg.actions[name]
		action.predicts = compilePredicts(reg, action.predicts, ("action %q"):format(name))
	end

	self.linked = true
	for name in reg.species do
		Instinct.link(self, name)
	end
	return self
end

local function makeDial(reg: Registry.Registry, species: any, rng: { n: number }): any
	local compiled: { [string]: any } = {}
	for name in DIAL_DEFAULT do
		local authored = species.dials[name]
		if authored == nil then
			continue
		end
		if isDomainMap(reg, authored) then
			local domains: { [string]: any } = {}
			for domain, value in pairs(authored) do
				domains[domain] = Values.compile(reg, bake(reg, value, rng), ("dial %q"):format(name))
			end
			compiled[name] = { domains = domains }
		else
			compiled[name] = { expr = Values.compile(reg, bake(reg, authored, rng), ("dial %q"):format(name)) }
		end
	end
	return compiled
end

function Instinct.spawn(self: any, speciesName: string, options: any?): any
	self:ready()
	local species = self.reg.species[speciesName]
	if species == nil then
		fail(("spawn: %q is a species nobody declared"):format(tostring(speciesName)))
	end
	local opts = options or {}
	local id = opts.id
	if id == nil then
		self.seed += 1
		id = self.seed
	end
	if self.slotOf[id] ~= nil then
		fail(("spawn: %s is already alive"):format(tostring(id)))
	end

	local rng = { n = (opts.seed or self.seed) % 2147483648 }
	local dials = makeDial(self.reg, species, rng)
	if opts.dials ~= nil then
		for name, value in pairs(opts.dials) do
			if isDomainMap(self.reg, value) then
				local domains: { [string]: any } = {}
				for domain, inner in pairs(value) do
					domains[domain] = Values.compile(self.reg, bake(self.reg, inner, rng), ("dial %q"):format(name))
				end
				dials[name] = { domains = domains }
			else
				dials[name] = { expr = Values.compile(self.reg, bake(self.reg, value, rng), ("dial %q"):format(name)) }
			end
		end
	end

	local selfImage: { [string]: any } = {}
	for what, authored in pairs(species.selfImage) do
		local value = if type(authored) == "table" then authored[1] else authored
		local spread = if type(authored) == "table" then (authored.spread or 0.2) else 0.2
		selfImage[what] = { value = value, spread = spread }
	end
	if opts.selfImage ~= nil then
		for what, authored in pairs(opts.selfImage) do
			local value = if type(authored) == "table" then authored[1] else authored
			local spread = if type(authored) == "table" then (authored.spread or 0.2) else 0.2
			selfImage[what] = { value = value, spread = spread }
		end
	end

	local expects: { [string]: any } = {}
	for quantity, authored in pairs(species.expects) do
		local value = if type(authored) == "table" then authored[1] else authored
		local spread = if type(authored) == "table" then (authored.spread or 0.1) else 0.1
		-- `after` turns a need from a snapshot into a forecast: not "I am below where I should be"
		-- but "I will be, in this many seconds, if nothing changes". Defaults to 0, which is the
		-- old instantaneous behaviour exactly.
		local after = if type(authored) == "table" then (authored.after or 0) else 0
		expects[quantity] = { value = value, spread = spread, after = after }
	end

	local forms: { [string]: boolean } = {}
	for _, featureName in species.forms do
		forms[featureName] = true
	end

	local reads: { [string]: boolean } = {}
	for _, signName in species.reads do
		reads[signName] = true
	end

	local parts: { [string]: number } = table.clone(species.parts)

	local skills: { [string]: number } = table.clone(species.skills)
	if opts.skills ~= nil then
		for skillName, level in pairs(opts.skills) do
			skills[skillName] = level
		end
	end

	local slot = self.high + 1
	self.high = slot
	self.slotOf[id] = slot
	self.idOf[slot] = id
	self.count += 1

	local reg = self.reg
	local state
	state = {
		id = id,
		slot = slot,
		species = speciesName,
		expects = expects,
		instinct = species.instinct,
		believes = species.believes,
		forms = forms,
		reads = reads,
		feels = species.feels,
		parts = parts,
		partsTotal = table.clone(parts),
		skills = skills,
		selfImage = selfImage,
		holding = {},
		level = {},
		dials = dials,
		doing = nil,
		target = nil,
		busy = {},
		beliefs = Beliefs.new(),
		inView = {},
		pending = {},
		now = 0,
		chain = {},
		step = 0,
		since = 0,
		lastThink = -math.huge,
		lastSurprise = 0,
		efficacy = 0,
		lastErrors = {},
		lastNovelty = 0,
		pressure = math.huge,
		recent = {},
		gains = {},
		gainOf = {},
		actionPredicts = {},
		driftSeen = {},
		wasLevel = {},
		residual = {},
		learned = {},
		blamed = nil,
		trace = false,
		last = nil,
		hold = function(key: string, priorValue: number, priorSpread: number, from: string, parent: string?): any
			local held = Beliefs.hold(state.beliefs, key, priorValue, priorSpread, from, parent)
			held.seen = state.now
			state.inView[key] = true
			return held
		end,
		expect = function(key: string, held: any, predicted: any, subject: any, delta: number)
			if predicted.of ~= "self" then
				return
			end
			local horizon = predicted.after or 0
			if horizon <= 0 then
				return
			end
			for _, row in state.pending do
				if row.key == key then
					return
				end
			end
			local base = held.v
			if base == 0 then
				return
			end
			local level = state.level[predicted.quantity]
			if level == nil then
				return
			end
			local through: { string } = {}
			Values.refs(predicted.expr, through)
			table.insert(state.pending, {
				key = key,
				through = through,
				quantity = predicted.quantity,
				subject = subject,
				scale = delta / base,
				at = state.now + horizon,
				was = level,
			})
		end,
		dial = function(name: string, args: any?): number
			local held = state.dials[name]
			local fallback = DIAL_DEFAULT[name] or 0.5
			if held == nil then
				return fallback
			end
			local chosen = held.expr
			if chosen == nil and held.domains ~= nil then
				local domain = if args then args.domain else nil
				chosen = if domain then held.domains[domain] else nil
				if chosen == nil then
					local total, seen = 0, 0
					for _, expr in pairs(held.domains) do
						local v = Values.resolve(reg, expr, function()
							return nil, 0
						end)
						if v ~= nil then
							total += v
							seen += 1
						end
					end
					return if seen > 0 then total / seen else fallback
				end
			end
			if chosen == nil then
				return fallback
			end
			local value = Values.resolve(reg, chosen, function(key: string): (number?, number)
				local supplied = if args then args[key] else nil
				if type(supplied) == "number" then
					return supplied, 0
				end
				return nil, 0
			end)
			local base = if value ~= nil then value else fallback
			if args ~= nil and args.raw == true then
				return base
			end
			return Emotions.scale(reg, state, name, base)
		end,
		precision = function(quantity: string): number
			return Emotions.precision(reg, state, quantity)
		end,
	}
	self.state[slot] = state
	return id
end

function Instinct.remove(self: any, id: any): boolean
	local slot = self.slotOf[id]
	if slot == nil then
		return false
	end
	self.slotOf[id] = nil
	self.idOf[slot] = nil
	self.state[slot] = nil
	self.count -= 1
	return true
end

local function stateOf(self: any, id: any): any
	local slot = self.slotOf[id]
	if slot == nil then
		return nil
	end
	return self.state[slot]
end

Instinct.stateOf = stateOf

function Instinct.perceive(self: any, id: any, list: { any }): any
	local state = stateOf(self, id)
	if state == nil then
		return self
	end
	Percepts.reset(self.per, state.forms, state.gains)
	table.clear(state.inView)
	for _, entry in list do
		if entry.subject ~= nil and entry.absent == true then
			local key = ("presence|%s"):format(tostring(entry.subject))
			local held = state.beliefs[key]
			if held ~= nil then
				local shock = Beliefs.surprise(held, 0)
				state.lastSurprise = shock
				Beliefs.update(held, 0, 0.02, state.dial("adaptability"))
				held.seen = state.now
				self.counts.learned += 1
				if shock > 3 then
					self.counts.violations += 1
				end
			end
			continue
		end
		if entry.via == "body" and entry.subject == nil then
			for key, value in pairs(entry.raw or {}) do
				if self.reg.quantities[key] ~= nil and type(value) == "number" then
					state.level[key] = value
				end
			end
			if entry.holding ~= nil then
				state.holding = entry.holding
			end
			continue
		end
		local view = Percepts.add(self.per, entry)
		if entry.subject ~= nil then
			local key = ("presence|%s"):format(tostring(entry.subject))
			local held = Beliefs.hold(state.beliefs, key, 1, 0.05, "seen")
			held.toward = 0.5
			Beliefs.update(held, 1, 0.05, state.dial("adaptability"))
			held.seen = state.now
			state.inView[key] = true
		end
		local _ = view
	end

	local capacity = state.dial("capacity")
	if capacity > 0.05 then
		for _, entry in list do
			local reacting = entry.reacting
			if reacting == nil or entry.subject == nil or reacting.to == nil then
				continue
			end
			local witness = tostring(entry.subject)
			local about = reacting.to
			local aboutKind = reacting.kind
			if aboutKind == nil then
				for _, other in list do
					if other.subject == about then
						aboutKind = other.kind
					end
				end
			end
			if aboutKind == nil then
				continue
			end

			local dread = 0
			for key, held in pairs(state.beliefs) do
				if key:find(("subject|%s|"):format(witness), 1, true) and held.v < 0 then
					dread = math.max(dread, math.abs(held.v))
				end
			end
			local bond = math.clamp(1 - dread, 0, 1)
			local weight = capacity * bond
			if weight < 0.05 then
				continue
			end

			local quantity = reacting.about or "integrity"
			if self.reg.quantities[quantity] == nil then
				continue
			end
			local strength = reacting.as or 0.5
			local kindKey = ("kind|%s|self|%s"):format(aboutKind, quantity)
			local kindHeld = Beliefs.hold(state.beliefs, kindKey, 0, 0.6, "watched")
			local subKey = ("subject|%s|%s|self|%s"):format(tostring(about), aboutKind, quantity)
			local held = Beliefs.hold(state.beliefs, subKey, kindHeld.v, kindHeld.s, "kind:" .. aboutKind, kindKey)
			Beliefs.update(held, -strength, 0.4 / weight, state.dial("adaptability"))
			Beliefs.update(kindHeld, -strength, 1.6 / weight, state.dial("adaptability"))
			held.seen = state.now
			state.inView[subKey] = true
			self.counts.learnedSocially += 1
		end
	end

	for name, sign in pairs(self.reg.signs) do
		if not state.reads[name] then
			continue
		end
		for _, view in self.per.views do
			if sign.seeing.kind ~= nil and not Percepts.isKind(self.per, view, sign.seeing.kind) then
				continue
			end
			local reading = 1
			if sign.seeing.feature ~= nil then
				local got = Percepts.read(self.per, view, sign.seeing.feature)
				if got == nil then
					continue
				end
				reading = got
			end
			local about = sign.tells.subject or sign.tells.kind
			if about == nil then
				continue
			end
			local key = ("sign|%s|%s"):format(tostring(about), tostring(sign.tells.quantity or "presence"))
			local held = Beliefs.hold(state.beliefs, key, reading, 0.5, "sign:" .. name)
			held.toward = 0.5
			Beliefs.update(held, reading, sign.tells.spread or 0.05, state.dial("adaptability"))
			held.seen = state.now
			state.inView[key] = true
			self.counts.signsRead += 1
		end
	end

	return self
end

function Instinct.beliefs(self: any, id: any, subject: any?): any
	local state = stateOf(self, id)
	if state == nil then
		return nil
	end
	local out: any = {}
	local want = if subject ~= nil then tostring(subject) else nil
	for key, held in pairs(state.beliefs) do
		if want ~= nil and not key:find(want, 1, true) then
			continue
		end
		out[key] = { value = held.v, spread = held.s, seen = held.n, from = held.from }
	end
	return out
end

function Instinct.surprise(self: any, id: any): number
	local state = stateOf(self, id)
	return if state ~= nil then (state.lastSurprise or 0) else 0
end

function Instinct.holding(self: any, id: any, held: any): any
	local state = stateOf(self, id)
	if state ~= nil then
		state.holding = held or {}
	end
	return self
end

local function settlerFor(self: any, state: any, key: string): Registry.Action?
	for _, name in self.reg.actionOrder do
		local action = self.reg.actions[name]
		if action.settles[key] and Think.partsFree(state, action) then
			return action
		end
	end
	return nil
end

local function extend(self: any, state: any, per: any, action: Registry.Action, target: any, missing: string?): ({ string }?, string?)
	local links: { string } = { action.name }
	local budget = 1 + math.floor(state.dial("patience") * 3 + 1e-9)
	local key = missing
	local seen: { [string]: boolean } = { [action.name] = true }

	while key ~= nil do
		if #links >= budget then
			return nil, key
		end
		local settler = settlerFor(self, state, key)
		if settler == nil or seen[settler.name] then
			return nil, key
		end
		seen[settler.name] = true
		table.insert(links, 1, settler.name)
		local _, nextMissing = Think.resolveTarget(state, per, settler, target)
		key = nextMissing
	end

	return links, nil
end

function Instinct.think(self: any, id: any, dt: number, now: number): any
	local state = stateOf(self, id)
	if state == nil then
		return nil
	end

	local tempo = state.dial("tempo")
	local interval = if tempo > 0 then (1 / (tempo * 30)) else math.huge
	if now - state.lastThink < interval then
		self.counts.skipped += 1
		return state.doing
	end
	state.lastThink = now
	state.now = now
	self.counts.thinks += 1

	-- How fast the creature runs down, learned rather than authored. A quantity with a horizon on
	-- it needs a trajectory to project along, and that trajectory is a belief like any other: held
	-- with a spread, wrong at first, narrowing with experience. A newborn does not know it gets
	-- hungry -- its drift belief sits at zero held very wide, so its forecast is too uncertain to
	-- be worth acting on, and it only starts anticipating once it has felt itself empty a few
	-- times.
	--
	-- Only declines are sampled. Rises are the creature being fed or healed, which say nothing
	-- about how fast it runs down unattended, and averaging them in would cancel the drift to zero.
	for quantity, prior in state.expects do
		if (prior.after or 0) <= 0 then
			continue
		end
		local level = state.level[quantity]
		if level == nil then
			continue
		end
		local seen = state.driftSeen[quantity]
		if seen == nil then
			state.driftSeen[quantity] = { at = now, level = level }
			continue
		end
		local span = now - seen.at
		if span < DRIFT_EVERY then
			continue
		end
		local observed = (level - seen.level) / span
		state.driftSeen[quantity] = { at = now, level = level }
		if observed >= 0 then
			continue
		end
		local held = state.hold(("drift|%s"):format(quantity), 0, DRIFT_UNSURE, "drift")
		Beliefs.update(held, observed, DRIFT_NOISE, state.dial("adaptability"))
	end

	local adaptability = state.dial("adaptability")
	local index = 1
	while index <= #state.pending do
		local row = state.pending[index]
		if now < row.at then
			index += 1
			continue
		end
		local level = state.level[row.quantity]
		local held = state.beliefs[row.key]
		if level ~= nil and held ~= nil and row.scale ~= 0 then
			local actual = level - row.was
			local witnessed = actual / row.scale
			local magnitude = math.clamp(math.abs(actual), 0, 1)
			local witnessSpread = math.max(0.05, 0.5 * (1 - magnitude))
			local trust = math.clamp(state.dial("attribution", { domain = "sight" }), 0.02, 0.98)
			local toBelief = witnessSpread / math.sqrt(trust)
			local surprise = Beliefs.update(held, witnessed, toBelief, adaptability)
			self.counts.learned += 1
			if surprise > 3 then
				self.counts.violations += 1
			end
			Blame.residual(state, row.key, surprise)

			if row.through ~= nil and surprise > 1 then
				local toSenses = witnessSpread / math.sqrt(1 - trust)
				for _, featureName in row.through do
					if self.reg.features[featureName] == nil then
						continue
					end
					local gainKey = ("feature|%s|gain"):format(featureName)
					local gain = Beliefs.hold(state.beliefs, gainKey, 1, 0.12, "calibration")
					local ratio = if held.v ~= 0 then math.clamp(witnessed / held.v, 0.6, 1.6) else 1
					Beliefs.update(gain, gain.v * ratio, toSenses, adaptability)
					state.gains[featureName] = gain.v
				end
			end

			local parent = if held.parent ~= nil then state.beliefs[held.parent] else nil
			if parent ~= nil then
				Beliefs.update(parent, witnessed, witnessSpread * 4, adaptability)
				Blame.residual(state, held.parent :: string, surprise)
			end
		end
		local last = #state.pending
		state.pending[index] = state.pending[last]
		state.pending[last] = nil
	end

	local reg = self.reg
	local per = self.per
	local function gather(): { Think.Error }
		local found: { Think.Error } = {}
		Think.selfErrors(state, found)
		Think.predictedErrors(reg, state, per, found)
		Think.rank(found)
		return found
	end

	Blame.remember(state, per, now, state.dial("capacity"))

	local attribution = state.dial("attribution", { domain = "world" })
	for _, event in Blame.unexplained(state, now) do
		self.counts.unexplained += 1
		if attribution < 0.4 then
			continue
		end
		local culprit = Blame.pin(state, event, now, 60)
		if culprit == nil then
			continue
		end
		local lag = math.max(now - culprit.at, 0.5)
		local site = ("learned about %q"):format(tostring(culprit.kind))
		local found = nil
		for _, entry in state.learned do
			if entry.about == culprit.kind and entry.quantity == event.quantity then
				found = entry
				break
			end
		end
		if found == nil then
			found = {
				about = culprit.kind,
				quantity = event.quantity,
				learned = true,
				predicts = {
					{
						of = "self",
						quantity = event.quantity,
						expr = Values.compile(reg, { -event.amount, spread = event.amount }, site),
						after = lag,
					},
				},
			}
			table.insert(state.learned, found)
			self.counts.associations += 1
		end
		local key = ("kind|%s|self|%s"):format(culprit.kind, event.quantity)
		local held = Beliefs.hold(state.beliefs, key, -event.amount, event.amount, "learned")
		Beliefs.update(held, -event.amount, math.max(0.05, 0.5 * (1 - math.clamp(event.amount, 0, 1))),
			state.dial("adaptability"))
		state.blamed = culprit.subject

		if culprit.saw ~= nil then
			found.witnessed = found.witnessed or {}
			for featureName, reading in pairs(culprit.saw) do
				if reading < 0 or reading > 1 then
					continue
				end
				local row = found.witnessed[featureName]
				if row == nil then
					row = { sum = 0, n = 0, low = 1 }
					found.witnessed[featureName] = row
				end
				row.sum += reading
				row.n += 1
				row.low = math.min(row.low, reading)
			end
			found.times = (found.times or 0) + 1

			if found.times >= 2 and found.refined == nil and state.dial("insight") > 0.2 then
				local bestName, bestLow = nil, 0.75
				for featureName, row in pairs(found.witnessed) do
					if row.n >= found.times and row.low > bestLow then
						bestName, bestLow = featureName, row.low
					end
				end
				if bestName ~= nil then
					found.refined = bestName
					local site = ("acquired %q and %q"):format(tostring(culprit.kind), bestName)
					found.predicts[1].expr = Values.compile(
						reg,
						{ -event.amount, by = { bestName }, spread = event.amount },
						site
					)
					self.counts.acquired += 1
				end
			end
		end
	end

	local insight = state.dial("insight")
	local index2 = 1
	while index2 <= #state.learned do
		local entry = state.learned[index2]
		local key = ("kind|%s|self|%s"):format(entry.about, entry.quantity)
		local prior = state.expects[entry.quantity]
		local loudest = 0
		local mark = ("|%s|self|%s"):format(entry.about, entry.quantity)
		local anyHeld = false
		for name, belief in pairs(state.beliefs) do
			if name == key or name:sub(-#mark) == mark then
				anyHeld = true
				loudest = math.max(loudest, math.abs(belief.v))
			end
		end
		local faded = anyHeld and prior ~= nil
			and loudest / math.max(prior.spread, 1e-4) < 1
		if faded or Blame.stuck(state, key, insight) then
			local last = #state.learned
			state.learned[index2] = state.learned[last]
			state.learned[last] = nil
			state.residual[key] = nil
			self.counts.recanted += 1
		else
			index2 += 1
		end
	end

	local errors = gather()
	Beliefs.forget(state.beliefs, now, Beliefs.rateFor(state.dial("grudge")), state.inView)

	local efficacy = 0
	if #errors > 0 then
		local top = errors[1]
		for _, name in reg.actionOrder do
			local action = reg.actions[name]
			local aim = Think.resolveTarget(state, per, action, top.subject)
			if aim == nil or not Think.partsFree(state, action) then
				continue
			end
			local gained = Think.cancelsThreat(reg, state, per, action, top, aim)
			local share = if top.amount > 0 then gained / top.amount else 0
			if share > efficacy then
				efficacy = share
			end
		end
	end
	state.efficacy = efficacy
	Emotions.settle(reg, state, errors, efficacy, dt, Emotions.novelty(state, per, errors))
	errors = gather()

	state.pressure = if #errors > 0 then errors[1].salience else 0

	-- Commit whatever the creature is doing to the pending run, the same way a prediction about
	-- a kind is committed in Think.predictedErrors. Without this an `action|` belief is created
	-- for scoring and then never checked against what followed, so a creature stays wrong about
	-- its own punch forever however often it throws one. This runs on every exit that keeps an
	-- action rather than only where one is chosen, because a creature holding an action across
	-- many ticks has to keep re-checking it; `state.expect` de-duplicates by key, so a fresh row
	-- is filed only once the previous one has resolved. The check itself is already generic --
	-- the horizon sweep above reads a pending row by key and neither knows nor cares that this
	-- one names an action.
	local function keep(chosen: string?): string?
		if chosen == nil then
			return nil
		end
		local action = reg.actions[chosen]
		if action == nil then
			return chosen
		end

		-- An action that narrows does its work by being performed: every belief the creature holds
		-- about the thing it is attending to gets tighter. Nothing else in the package narrows a
		-- belief except a prediction coming due, which is why an action like `watch` did nothing at
		-- all before -- and, since 0.2.0, would have taught the creature that watching is useless.
		-- Curiosity closes its own loop from here: the emotion reads the widest belief held about a
		-- subject, so tightening those beliefs lowers it without anything having to say so.
		if action.narrows ~= nil and state.target ~= nil then
			local mark = ("subject|%s"):format(tostring(state.target))
			for name, held in state.beliefs do
				if name:find(mark, 1, true) then
					Beliefs.relax(held, held.v, WATCH_FLOOR, WATCH_RATE, dt)
				end
			end
		end
		local view = if state.target ~= nil then per.bySubject[state.target] else nil
		local function seen(name: string): (number?, number)
			if view ~= nil then
				return Percepts.read(per, view, name)
			end
			return nil, 0
		end
		for _, predicted in Think.predictsOf(state, action) do
			if predicted.of ~= "self" or not Think.whenHolds(state, predicted, state.target) then
				continue
			end
			local held, key = Think.actionBelief(state, action, predicted)
			local delta = Values.resolve(reg, predicted.expr, seen, held.v, held.s)
			if delta ~= nil then
				state.expect(key, held, predicted, state.target, delta)
			end
		end
		return chosen
	end

	if #errors == 0 then
		state.last = { errors = errors, considered = {} }
		if state.doing ~= nil then
			state.doing = nil
			state.target = nil
			state.busy = {}
			state.chain = {}
			state.step = 0
			self.counts.released += 1
		end
		return nil
	end

	local attention = math.max(1, math.floor(state.dial("attention") * 4 + 0.5))
	local considered: { any } = {}
	local best: any = nil
	local shy = 0

	for rankIndex = 1, math.min(attention, #errors) do
		local err = errors[rankIndex]
		for _, name in reg.actionOrder do
			local action = reg.actions[name]
			local target, missing = Think.resolveTarget(state, per, action, err.subject)
			local view = if target ~= nil then per.bySubject[target] else nil

			local function look(key: string): (number?, number)
				if view ~= nil then
					return Percepts.read(per, view, key)
				end
				return nil, 0
			end

			local cancels, spread = Think.cancelsSelf(reg, state, action, err, look, target)
			if cancels <= 0 and target ~= nil then
				local gained, gs = Think.cancelsThreat(reg, state, per, action, err, target)
				cancels, spread = gained, gs
			end
			local unknown = Think.unknownOf(state, action)
			local venture = unknown * state.dial("venture") * math.min(err.amount, 1)
			if cancels <= 0 and venture <= 0 then
				continue
			end

			local blocked: string? = nil
			local chain: { string } = { name }
			if not Think.partsFree(state, action) then
				blocked = "parts"
			elseif missing ~= nil then
				local links, stuck = extend(self, state, per, action, target, missing)
				if links == nil then
					blocked = stuck
				else
					chain = links
				end
			end

			-- What trying this would teach. An action the creature holds a wide belief about has
			-- something to tell it; one it is already sure of has nothing. Scaled by how badly the
			-- creature needs an answer, so it experiments under pressure rather than idly.
			--
			-- This is the term that stops "worth nothing" being a life sentence. Without it the
			-- creature only ever considers what it already believes will pay, so a move it has
			-- learned is useless -- or one a feature multiplied to zero -- can never be tried
			-- again, however much the world has changed since. With it, an option that promises
			-- nothing is still admitted as an experiment, and wins only when nothing better stands.
			local confidence = Think.confidenceOf(cancels, spread)
			local pressure = Think.costPressure(state, action)
			local score = cancels * confidence + venture - pressure * 0.15
			-- An experiment does not have to clear caution, because it is not claiming it will
			-- work. It only ever wins when everything that does make a claim has failed to.
			local passes = confidence >= Think.threshold(state, err.amount) or venture > 0
			local row = {
				action = name,
				cancels = cancels,
				confidence = confidence,
				score = score,
				chain = chain,
				blocked = blocked,
				err = err,
				target = target,
			}
			row.passes = passes
			table.insert(considered, row)
			if blocked ~= nil then
				continue
			end
			if not passes then
				shy += 1
				continue
			end
			if best == nil or score > best.score then
				best = row
			end
		end
		if best ~= nil then
			break
		end
	end

	state.last = { errors = errors, considered = considered, chosen = best }

	if best == nil then
		if shy > 0 then
			self.counts.belowThreshold += 1
		end
		return keep(state.doing)
	end

	local head = best.chain[1]
	local committed = state.doing
	if committed ~= nil and committed ~= head then
		local holdOn = state.dial("commitment", { progress = state.step / math.max(#state.chain, 1) })
		local incumbent = nil
		for _, row in considered do
			if row.chain[1] == committed then
				incumbent = row
				break
			end
		end
		if incumbent ~= nil and best.score < incumbent.score + holdOn then
			return keep(state.doing)
		end
		self.counts.chainsAbandoned += 1
	end

	if committed ~= head then
		state.doing = head
		state.target = best.target
		state.chain = best.chain
		state.step = 1
		state.since = now
		state.busy = reg.actions[head].occupies
		self.counts.actionsChosen += 1
		if #best.chain > 1 then
			self.counts.chainsFormed += 1
		end

	end

	return keep(state.doing)
end

function Instinct.step(self: any, dt: number, now: number, options: any?): any
	local opts = options or {}
	local budget = opts.budgetMs or math.huge
	local queue: { any } = {}

	for slot = 1, self.high do
		local state = self.state[slot]
		if state == nil then
			continue
		end
		local tempo = state.dial("tempo")
		local interval = if tempo > 0 then (1 / (tempo * 30)) else math.huge
		if now - state.lastThink < interval then
			self.counts.skipped += 1
			continue
		end
		table.insert(queue, state)
	end

	table.sort(queue, function(a, b)
		if a.pressure ~= b.pressure then
			return a.pressure > b.pressure
		end
		return a.slot < b.slot
	end)

	local spent = 0
	local served = 0
	for _, state in queue do
		if spent >= budget then
			self.counts.starved += 1
			continue
		end
		local before = if self.clock ~= nil then self.clock() else 0
		Instinct.think(self, state.id, dt, now)
		local after = if self.clock ~= nil then self.clock() else 0
		spent += (after - before) * 1000
		served += 1
	end

	return served
end

function Instinct.doing(self: any, id: any): (string?, any)
	local state = stateOf(self, id)
	if state == nil then
		return nil, nil
	end
	return state.doing, state.target
end

function Instinct.why(self: any, id: any): any
	local state = stateOf(self, id)
	if state == nil then
		return nil
	end
	local last = state.last
	local out: any = {
		doing = { action = state.doing, target = state.target, since = state.since },
		chain = state.chain,
		dials = {},
	}
	for name in DIAL_DEFAULT do
		if state.dials[name] ~= nil then
			out.dials[name] = { effective = state.dial(name) }
		end
	end
	if last == nil then
		return out
	end
	local top = last.errors[1]
	if top ~= nil then
		out.because = {
			of = top.of,
			quantity = top.quantity,
			error = top.amount,
			spreads = top.amount / top.spread,
			subject = top.subject,
			after = top.after,
		}
	end
	if last.chosen ~= nil then
		out.confidence = last.chosen.confidence
		out.threshold = Think.threshold(state, last.chosen.err.amount)
	end
	out.considered = {}
	for _, row in last.considered do
		table.insert(out.considered, {
			action = row.action,
			cancels = row.cancels,
			confidence = row.confidence,
			score = row.score,
			blocked = row.blocked,
			chosen = row == last.chosen,
		})
	end
	return out
end

local function wantsField(fields: { string }?, name: string): boolean
	if fields == nil then
		return true
	end
	for _, each in fields do
		if each == name then
			return true
		end
	end
	return false
end

function Instinct.extract(self: any, id: any, fields: { string }?, options: any?): any
	local state = stateOf(self, id)
	if state == nil then
		return nil
	end
	local opts = options or {}
	local asIndividual = opts.as == "individual"
	local species = self.reg.species[state.species]

	local out: any = {
		kind = species.kind,
		parts = table.clone(state.partsTotal),
		senses = species.senses,
		forms = species.forms,
		reads = species.reads,
		chunks = species.chunks,
		feels = species.feels,
	}

	if wantsField(fields, "skills") then
		out.skills = table.clone(state.skills)
	end

	if wantsField(fields, "expects") then
		local expects: any = {}
		for quantity, prior in pairs(state.expects) do
			expects[quantity] = { prior.value, spread = prior.spread }
		end
		out.expects = expects
	end

	if wantsField(fields, "selfImage") then
		local image: any = {}
		for what, held in pairs(state.selfImage) do
			image[what] = { held.value, spread = held.spread }
		end
		out.selfImage = image
	end

	if wantsField(fields, "instinct") then
		local instinct: any = {}
		for _, entry in state.instinct do
			local predicts: any = {}
			for _, predicted in entry.predicts do
				local key = ("kind|%s|%s|%s"):format(entry.about, predicted.of, predicted.quantity)
				local held = state.beliefs[key]
				local row: any = { of = predicted.of, after = predicted.after }
				row[predicted.quantity] = {
					if held ~= nil then held.v else (predicted.expr.const or 0),
					spread = if held ~= nil then held.s else predicted.expr.spread,
				}
				table.insert(predicts, row)
			end
			table.insert(instinct, { about = entry.about, predicts = predicts })
		end
		for _, entry in state.learned do
			local predicts: any = {}
			for _, predicted in entry.predicts do
				local key = ("kind|%s|%s|%s"):format(entry.about, predicted.of, predicted.quantity)
				local held = state.beliefs[key]
				local row: any = { of = predicted.of, after = predicted.after }
				row[predicted.quantity] = {
					if held ~= nil then held.v else (predicted.expr.const or 0),
					spread = if held ~= nil then held.s else predicted.expr.spread,
				}
				table.insert(predicts, row)
			end
			table.insert(instinct, { about = entry.about, predicts = predicts })
		end
		out.instinct = instinct
	end

	if wantsField(fields, "believes") then
		local believes: any = {}
		for _, name in self.reg.actionOrder do
			local action = self.reg.actions[name]
			local predicts: any = {}
			for _, predicted in Think.predictsOf(state, action) do
				local key = ("action|%s|%s|%s"):format(name, predicted.of, predicted.quantity)
				local held = state.beliefs[key]
				if held == nil then
					continue
				end
				local row: any = { of = predicted.of, after = predicted.after }
				row[predicted.quantity] = { held.v, spread = held.s }
				table.insert(predicts, row)
			end
			if #predicts > 0 then
				believes[name] = predicts
			end
		end
		out.believes = believes
	end

	local dials: any = {}
	for name in DIAL_DEFAULT do
		if state.dials[name] == nil then
			continue
		end
		local value = state.dial(name, { raw = true })
		if asIndividual then
			dials[name] = value
		else
			local spread = math.max(math.abs(value) * 0.15, 0.02)
			dials[name] = { math.max(value - spread, 0), math.min(value + spread, 1) }
		end
	end
	out.dials = dials

	return out
end

function Instinct.size(self: any): number
	return self.count
end

function Instinct.stats(self: any): any
	local out = table.clone(self.counts)
	out.creatures = self.count
	return out
end

return Instinct
