--!strict
-- Instinct, rebuilt around prediction. See docs/Rebuild.md.
--
-- A creature is a model of what is around it and what is about to happen, plus a short list of
-- readings it would rather were different. Error always teaches; error on something it has a
-- preference about also moves it.
--
-- This slice does the first half: perceive, project, and learn. A creature here builds a model of
-- things it has no opinion about whatsoever, which is precisely what the previous design could not
-- do -- there, only a need could produce an error, so a colour that changed taught nothing.

local Registry = require("@self/Registry")
local Values = require("@self/Values")
local Beliefs = require("@self/Beliefs")
local World = require("@self/World")
local Predict = require("@self/Predict")
local Choose = require("@self/Choose")
local Associate = require("@self/Associate")
local Acquire = require("@self/Acquire")

local Instinct = {}
Instinct.__index = Instinct

local DIALS: { [string]: number } = {
	adaptability = 0.5,
	grudge = 0.5,
	attention = 0.5,
	capacity = 0.5,
	caution = 0.4,
	patience = 0.5,
	commitment = 0.5,
	tempo = 0.5,
	attribution = 0.9,
	insight = 0.4,
	resilience = 0.5,
	reaction = 0.25,
	venture = 0,
	ingenuity = 0.3,
	retention = 0.4,
}

Instinct.DIALS = DIALS

local function fail(message: string): never
	error(("[instinct] %s"):format(message), 0)
end

function Instinct.new(config: any?): any
	local reg = Registry.new()
	-- Close the loop here rather than with a require, so Registry can stay dependency-free.
	reg.compile = function(authored: any, site: string): any
		return Values.compile(reg, authored, site)
	end
	local self = setmetatable({
		reg = reg,
		state = {} :: { [number]: any },
		high = 0,
		counts = { perceived = 0, projected = 0, learned = 0, chosen = 0, born = 0, collected = 0, acquired = 0 },
		seed = (config or {}).seed or 0,
	}, Instinct)
	return self
end

-- Declaration passes straight through, so the surface reads as one long sentence about the world.
local surface = Instinct :: any
for _, method in { "sense", "operator", "reading", "emotion", "kind", "action", "species" } do
	local declare = (Registry :: any)[method]
	surface[method] = function(self: any, name: string, decl: any?): any
		declare(self.reg, name, decl)
		return self
	end
end

function Instinct.defaults(self: any): any
	self:operator("times", { stage = 2, costs = 0.004, apply = function(a, b) return a * b end })
	self:operator("over", { stage = 2, costs = 0.006, apply = function(a, b)
		return if b == 0 then nil else a / b
	end })
	self:operator("inverted", { stage = 2, costs = 0.004, apply = function(a, b)
		return if b == 0 then nil else math.clamp(1 - a / b, 0, 1)
	end })
	self:operator("atLeast", { stage = 3, costs = 0.002, apply = function(a, b) return math.max(a, b) end })
	self:operator("atMost", { stage = 3, costs = 0.002, apply = function(a, b) return math.min(a, b) end })

	-- Temporal. Change-in-anything cannot be written without one, which is why `closing` had to be
	-- authored before and can be discovered now.
	self:operator("delta", {
		stage = 1,
		costs = 0.030,
		recalls = true,
		apply = function(a: number, _b: number, past: any): number?
			if past == nil or past.input == nil then
				return nil
			end
			return (a - past.input) / past.since
		end,
	})
	return self
end

function Instinct.spawn(self: any, speciesName: string, options: any?): any
	local species = self.reg.species[speciesName]
	if species == nil then
		fail(("no species named %q"):format(tostring(speciesName)))
	end
	local opts = options or {}

	local dials: { [string]: number } = table.clone(DIALS)
	for name, value in pairs(species.dials) do
		dials[name] = value
	end
	for name, value in pairs(opts.dials or {}) do
		dials[name] = value
	end

	local id = self.high + 1
	self.high = id

	local state: any
	state = {
		id = id,
		species = species,
		now = 0,
		beliefs = Beliefs.new(),
		pending = {},
		tracked = {},
		readMemo = {},
		deriving = {},
		feelings = {},
		strain = {},
		mute = {},
		recalled = {},
		predicts = table.clone(species.predicts),
		readings = {},
		forms = table.clone(species.forms),
		episodes = {},
		residual = {},
		searched = {},
		lastSnapshot = {},
		lastSnapshotAt = {},
		wants = species.wants,
		actionOrder = self.reg.actionOrder,
		doing = nil,
		since = 0,
		born = 0,
		last = nil,
		attending = World.SELF,
		attendingKind = species.kind,
		dials = dials,
		dial = function(name: string): number
			local base = dials[name] or DIALS[name] or 0.5
			-- An emotion acts back on the dials, which is the second of the two powers that make it
			-- one. The factor is earned in proportion to how strongly the thing is felt, so a creature
			-- feeling nothing is exactly the creature it was declared to be.
			--
			-- Guarded, because working out how afraid it is may itself ask what its dials are. Inside
			-- that question the answer is what it was born with, which is the only non-circular one.
			if state.feeling then
				return base
			end
			state.feeling = true
			for emotion, decl in self.reg.readings do
				local factor = if decl.emotion then decl.modulates[name] else nil
				if factor == nil then
					continue
				end
				local felt = state.feelings[("%s|%s"):format(World.SELF, emotion)]
				if felt == nil then
					continue
				end
				base *= 1 + (factor - 1) * math.clamp(felt.value, 0, 1)
			end
			state.feeling = false
			return base
		end,
	}
	state.project = function(subject: any, reading: string, within: number?): (number?, number)
		return Predict.project(self.reg, state, subject, self:kindOf(id, subject), reading, state.doing, within)
	end
	state.snapshot = function(subject: any): any
		return Acquire.snapshot(self.reg, state, subject, state.forms)
	end
	-- Every resolved prediction is a remembered moment: what could be seen, and what then happened.
	-- Keeping the ones that came out right as well as the ones that did not is the whole reason a
	-- thing that is simply always there cannot look guilty.
	state.recall = function(row: any, observed: number, surprise: number)
		Acquire.blame(state, ("%d|%s"):format(row.index, tostring(row.subject)), surprise)
		if row.snapshot ~= nil and row.before ~= nil then
			Acquire.remember(
				state,
				row.index,
				row.subject,
				row.snapshot,
				row.before,
				math.max(row.seenAt - (row.beforeAt or (row.seenAt - 1)), 1e-4),
				row.predicted or 0,
				observed
			)
		end
	end
	self.state[id] = state
	return id
end

function Instinct.stateOf(self: any, id: any): any
	return self.state[id]
end

-- Evidence in. A percept is a subject and the readings a channel reported about it; `self` and
-- `here` are subjects like any other.
function Instinct.perceive(self: any, id: any, list: { any }, now: number?)
	local state = self.state[id]
	if state == nil then
		return
	end
	-- Perceiving happens at a time, and association needs to know which: how far a thing may have
	-- got since it was last seen is the difference between recognising it and deciding it is
	-- something new.
	if now ~= nil then
		state.now = now
	end
	World.forget(state)

	for _, percept in list do
		local channel = percept.via
		local sense = self.reg.senses[channel]
		if sense == nil then
			fail(("perceived via %q, a sense nobody declared"):format(tostring(channel)))
		end
		if state.species.senses[channel] == nil then
			continue -- this creature does not have that sense
		end

		-- A percept may state its own confidence; otherwise the channel's own reliability stands.
		local trust = percept.confidence
		if trust == nil then
			trust = self.reg.senses[channel].reliable
		end
		if trust == nil then
			trust = 1
		end

		-- A percept either says which thing it is about, or leaves the creature to work it out.
		-- Supplying `subject` skips association entirely, which is what most games want and what
		-- every one of them gets today. `returns` is the honest input: a list of things sensed, with
		-- no identity attached.
		local batch: { any }
		if percept.returns ~= nil then
			batch = percept.returns
		else
			batch = { { subject = percept.subject, kind = percept.kind, raw = percept.raw or {} } }
		end

		for _, one in batch do
			local raw = if one.raw ~= nil then one.raw else one
			local kind = one.kind
			local subject = one.subject

			if subject == nil and percept.returns == nil then
				subject = if channel == "body" then World.SELF else World.HERE
			end
			if subject == nil then
				local placed, fresh = Associate.place(self.reg, state, raw, kind)
				subject = placed
				if fresh then
					self.counts.born += 1
				end
			end

			if kind ~= nil then
				state.tracked[tostring(subject) .. "|kind"] = kind
			end
			for reading, value in pairs(raw) do
				if self.reg.readings[reading] == nil then
					continue
				end
				if type(value) == "number" then
					World.observe(state, subject, reading, value, trust)
				end
			end
		end
	end
	self.counts.perceived += 1
end

function Instinct.kindOf(self: any, id: any, subject: any): string?
	local state = self.state[id]
	return if state ~= nil then state.tracked[tostring(subject) .. "|kind"] else nil
end

-- One turn of the wheel: settle what has come due, decide, and commit to being held to it. Returns
-- what the creature is now doing, or nil if there is nothing it would rather were different.
function Instinct.tick(self: any, id: any, dt: number, now: number): string?
	local state = self.state[id]
	if state == nil then
		return nil
	end
	state.now = now
	World.forget(state)

	-- Feel first. What it feels sharpens what it attends to and bends what it is willing to do, so it
	-- has to be settled before anything reads a spread or asks for a dial.
	for name, decl in self.reg.readings do
		if decl.emotion then
			World.read(self.reg, state, World.SELF, name)
		end
	end

	local learned = Predict.settle(self.reg, state)
	self.counts.learned += learned

	World.fade(state, dt)
	Predict.forget(state, dt)
	self.counts.acquired += Acquire.consider(self.reg, state)
	self.counts.collected += Associate.collect(state)

	-- What it would rather were different, and what to do about it.
	local errors = Choose.errors(self.reg, state)
	local doing, considered = Choose.pick(self.reg, state, errors)
	if doing ~= state.doing then
		state.doing = doing
		state.since = now
		if doing ~= nil then
			self.counts.chosen += 1
		end
	end
	state.last = { errors = errors, considered = considered }

	-- Commit to being held to what it now expects. The creature's own doing is a condition like any
	-- other, so an action's predictions are filed exactly as an instinct's are -- which is the whole
	-- reason a creature can learn what its own moves do without a second mechanism for it.
	for handle, subject in state.tracked do
		if handle:find("|kind", 1, true) then
			continue
		end
		local kind = state.tracked[handle .. "|kind"]
		Predict.expect(self.reg, state, subject, kind, state.doing, state.forms)
	end
	if state.wants ~= nil then
		local mine: { string } = {}
		for reading in state.wants do
			table.insert(mine, reading)
		end
		Predict.expect(self.reg, state, World.SELF, state.species.kind, state.doing, mine)
	end
	for handle, subject in state.tracked do
		if not handle:find("|kind", 1, true) then
			state.lastSnapshot[tostring(subject)] = state.snapshot(subject)
			state.lastSnapshotAt[tostring(subject)] = now
		end
	end
	state.lastSnapshot[World.SELF] = state.snapshot(World.SELF)
	state.lastSnapshotAt[World.SELF] = now
	self.counts.projected += 1

	return state.doing
end

-- Why it is doing that: the driving error in spreads, and everything else that was weighed.
function Instinct.why(self: any, id: any): any
	local state = self.state[id]
	if state == nil then
		return nil
	end
	local out: any = { doing = state.doing, since = state.since, considered = {}, dials = {} }
	for name in Instinct.DIALS do
		out.dials[name] = state.dial(name)
	end
	local last = state.last
	if last == nil then
		return out
	end
	local top = last.errors[1]
	if top ~= nil then
		out.because = {
			reading = top.reading,
			wanted = top.wanted,
			heading = top.heading,
			error = top.amount,
			spreads = top.salience,
		}
	end
	for _, row in last.considered do
		table.insert(out.considered, {
			action = row.action,
			gain = row.gain,
			ready = row.ready,
			confidence = row.confidence,
			venture = row.venture,
			score = row.score,
			chosen = row.chosen,
			-- the reading it was taken for, when that reading was a means rather than the end
			forKey = row.forKey,
		})
		if row.chosen then
			out.confidence = row.confidence
		end
	end
	return out
end

-- What it currently holds about one reading of one subject.
function Instinct.estimate(self: any, id: any, subject: any, reading: string): (number?, number)
	local state = self.state[id]
	if state == nil then
		return nil, 0
	end
	World.forget(state)
	return World.read(self.reg, state, subject, reading)
end

-- Where it thinks that reading is heading.
function Instinct.expects(self: any, id: any, subject: any, reading: string): (number?, number)
	local state = self.state[id]
	if state == nil then
		return nil, 0
	end
	World.forget(state)
	return Predict.project(self.reg, state, subject, self:kindOf(id, subject), reading, nil)
end

-- What it believes one of its predictions is worth, for one subject.
function Instinct.believes(self: any, id: any, index: number, subject: any): any
	local state = self.state[id]
	return if state ~= nil then state.beliefs[Predict.beliefKey(index, subject)] else nil
end

-- Everything it is currently tracking, however it came by them.
function Instinct.tracking(self: any, id: any): { any }
	local state = self.state[id]
	local out: { any } = {}
	if state == nil then
		return out
	end
	for handle, track in state.tracked do
		if not handle:find("|kind", 1, true) then
			table.insert(out, track)
		end
	end
	table.sort(out, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return out
end

-- Ideas it worked out for itself, which nobody gave it.
function Instinct.acquired(self: any, id: any): { string }
	local state = self.state[id]
	local out: { string } = {}
	if state == nil then
		return out
	end
	for name, decl in state.readings do
		if decl.acquired then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- Hand a creature's life back out as a declaration.
--
-- This is what makes an acquired reading worth having beyond the one animal that thought of it. A
-- creature works out that change-in-distance is what hurts it; extract it, declare the result, and its
-- children are **born** knowing. Which is also the only sense in which anything here is inherited:
-- nothing is copied between living creatures, and what one worked out dies with it unless somebody
-- deliberately writes it down.
--
-- Everything that comes back is plain data. The readings go to `i:reading`, the rest to `i:species`.
function Instinct.extract(self: any, id: any): any
	local state = self.state[id]
	if state == nil then
		return nil
	end
	local species = state.species

	local readings: { [string]: any } = {}
	for name, decl in state.readings do
		if decl.acquired then
			readings[name] = { is = decl.is }
		end
	end

	-- What it came to believe, in place of what it was born believing. Held per subject, so what the
	-- species gets is the precision-weighted merge -- one number that says what this creature learned
	-- about the claim in general, rather than about any one thing it met.
	local predicts: { any } = {}
	for index, entry in state.predicts do
		local row = table.clone(entry.source)
		local weight, total = 0, 0
		local prefix = ("pred|%d|"):format(index)
		for key, held in state.beliefs do
			if key:sub(1, #prefix) ~= prefix then
				continue
			end
			local precision = 1 / math.max(held.s * held.s, 1e-6)
			total += held.v * precision
			weight += precision
		end
		if weight > 0 then
			local body: { [string]: any } = {}
			body[entry.reading] = { total / weight, spread = math.sqrt(1 / weight) }
			if entry.form == "change" then
				row.changes = body
			else
				row.reads = body
			end
		end
		predicts[index] = row
	end

	local forms: { string } = {}
	for _, name in state.forms do
		table.insert(forms, name)
	end
	table.sort(forms)

	-- Back into the shape they were written in, rather than the shape they are held in.
	local wants: { [string]: any } = {}
	for reading, prior in species.wants do
		wants[reading] = { prior.value, spread = prior.spread, after = prior.after }
	end

	return {
		readings = readings,
		species = {
			kind = species.kind,
			senses = species.senses,
			forms = forms,
			wants = wants,
			predicts = predicts,
			dials = table.clone(state.dials),
		},
	}
end

-- How strongly it feels something, right now.
function Instinct.feels(self: any, id: any, emotion: string, subject: any?): number
	local state = self.state[id]
	if state == nil then
		return 0
	end
	local felt = state.feelings[("%s|%s"):format(tostring(subject or World.SELF), emotion)]
	return if felt ~= nil then felt.value else 0
end

function Instinct.stats(self: any): any
	return table.clone(self.counts)
end

return Instinct
