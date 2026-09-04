--!nonstrict
--!native
-- A mind made of tiers of tiny linear predictions, learned online. Ported from the offline
-- prototype (C:\lua code\tabmind3.lua) with only what earned its place there.
--
--   O  outcomes   what each reading will accumulate over the horizon, from the senses and the
--                 picks (one flag per option)                                    [always on]
--   M  memory     surprising good moments, replayed when the senses come near again
--   E  effects    per option, how each sense will have changed one STEP on; a combination's
--                 effect is the sum of its options', which lets a plan look a step ahead
--   C  couplings  what tends to move with what, with no action in it: the predicted drift of every
--                 sense is an extra input
--   A  acquire    on persistent error, a search over operator pairs of the raw inputs; what it
--                 finds becomes a new input with a tight prior
--   H  hazards    named events the world reports (a parry, a shot): whether each is about to
--                 happen, from the senses, as extra inputs, plus a decaying trace of each
--   trends        every sense's change since the last decision, as inputs (always on unless
--                 o.trend = false); acts' descriptors, when given, as in o.descriptors
--
-- Every tick the creature scores every feasible combination of picks on its senses, extends the
-- best few by their predicted next step, and takes the best. Rows settle a horizon later.
--
--     local mind = Mind.new(nSenses, choices, { set = "OMECA", readings = {...}, pref = {...} })
--     local picks, x, phi, event = mind:think(sensesOf, feasible)
--     mind:note(x, phi, picks, event, totals, tick)
--     mind:settle(totals, sensesNow, tick, over)
--
-- `totals` are the readings' running totals (damage dealt so far, meals so far...); the mind works
-- with their differences. Nothing here knows what a sense means.

local RLS = require("./RLS")

local Mind = {}
Mind.__index = Mind

local OPS = {
	mul = function(a: number, b: number): number return a * b end,
	min = function(a: number, b: number): number return if a < b then a else b end,
	max = function(a: number, b: number): number return if a > b then a else b end,
	sub = function(a: number, b: number): number return a - b end,
	gate = function(a: number, b: number): number return if a > 0 then b else 0 end,
	gt = function(a: number, b: number): number return if a > b then 1 else 0 end,
	absdiff = function(a: number, b: number): number return math.abs(a - b) end,
}
local OPNAMES = { "mul", "min", "max", "sub", "gate", "gt", "absdiff" }
Mind.OPS, Mind.OPNAMES = OPS, OPNAMES

local clock = os.clock

local function unpackPicks(p: { number }): { number }
	return table.clone(p)
end

function Mind.new(nIn: number, choices: { any }, o: any)
	o = o or {}
	local self = setmetatable({}, Mind)
	local set = o.set or "OMECA"
	self.has = {}
	for ch in set:gmatch(".") do
		self.has[ch] = true
	end
	self.has.O = true
	self.nIn, self.choices = nIn, choices
	self.H = o.horizon or 24 -- ticks a row waits before it is judged
	self.STEP = o.step or 12 -- ticks between an effects row and its answer
	self.ridge = o.ridge or (if o.sparse == true then 4 else 1)
	-- the outcome model's own ridge: the pooled value needs a strong one (the absent slots of the raw layout were
	-- an accidental ridge); the physics models want 1
	self.valueRidge = o.valueRidge or (if o.pooledValue == true then 30 else self.ridge)
	self.extraRidge = o.extraRidge or 20 -- the tight prior of couplings, hazards and acquired inputs
	self.readings = o.readings or { "dealt", "taken" }
	self.NRO = #self.readings
	self.discount = o.discount or 1
	self.pref = {}
	for k = 1, self.NRO do
		self.pref[k] = (o.pref and o.pref[self.readings[k]]) or 0
	end
	self.kU = o.kU or 1 -- curiosity, if the set has U: value += kU * spread
	self.beam = o.beam or 10
	-- SEPARABLE pick search: the value is linear in phi and phi is additive in the picks (one-hot flags, the
	-- pooled field-by-option sums, the descriptors' sums), so a combination's worth is a base plus one number
	-- per chosen option, and the first pass costs the options rather than their product. An identity: the same
	-- combinations come back (to rounding). Acquired features pairing two choices are the one exception and are
	-- evaluated per combination. Off with o.separable = false, or whenever the set has U (the spread is not additive).
	self.separable = o.separable ~= false
	self.gamma = o.gamma or 0.7 -- how much the projected next step counts
	self.surprise = o.surprise or 5 -- a row this far from its prediction is a surprise
	self.memory = if self.has.M then (o.memory or 200) else 0
	self.memGood = o.memGood or 10 -- a surprise this good is worth remembering
	self.memFloor = o.memFloor or 0.1 -- the least chance a stored surprise is replayed when near
	self.memRadius = o.memRadius or 0.35 * math.sqrt(nIn / 14) * 2
	self.memTries = o.memTries or 4
	self.reps = o.reps or 3 -- extra updates for a surprising good row
	self.eps = 0 -- chance of a random feasible combination instead of the best (the coach sets it)
	self.sticky = o.sticky or 0.9 -- while exploring, the chance of holding the last random combination another tick
	self.nudgeAfter = o.nudgeAfter or 10 -- decisions with unchanged senses before the creature tries something else
	self.sameFor = 0
	self.exploring = true -- false while a creature is being checked rather than taught
	local nOpt = 0
	for _, c in ipairs(choices) do
		nOpt += #c.options
	end
	self.nOpt = nOpt
	-- extra inputs: the couplings' predicted drift (nIn), hazards (3 per event) and traces (1 per event)
	self.events = o.events or {}
	self.nHaz = if self.has.H then #self.events * 3 else 0
	self.nTrace = if self.has.H then #self.events else 0
	self.trace = table.create(#self.events, 0)
	-- trends: every sense's change since the last decision, scaled, as inputs. No model behind them, and
	-- worth as much on the generated worlds as the arena's hand-written timers were (FINDINGS 72).
	self.trend = if o.trend == nil then true else o.trend
	self.nExtra = (if self.has.C then nIn else 0) + self.nHaz + self.nTrace + (if self.trend then nIn else 0)
	self.groups = o.groups or o.blocks
	self.nX = nIn + self.nExtra
	self.pooledValue = o.pooledValue == true and self.groups ~= nil and #self.groups >= 2
	self.nXO = self.nX -- the senses as the outcome model sees them
	self.nPool = 0
	if self.pooledValue then
		self.poolSelf = self.groups[1]
		self.poolSlots = {}
		for g = 2, #self.groups do
			table.insert(self.poolSlots, self.groups[g])
		end
		self.poolSize = #self.groups[2]
		self.poolKinds = math.min(#self.poolSlots, 6)
		self.nXO = #self.poolSelf
		self.poolCopies = { 0 }
		local off = nIn
		if self.has.C then
			table.insert(self.poolCopies, off)
			off += nIn
		end
		if self.trend then
			table.insert(self.poolCopies, off)
			off += nIn
		end
		self.nPool = self.poolSize * (self.poolKinds * #self.poolCopies + nOpt)
	end
	-- DESCRIPTORS: o.descriptors[optionIndex] = { d1..dD } (o.descrDim = D), for the options that have
	-- one (acts, usually). An option then enters the value through its descriptor, plus the descriptor's
	-- interactions with the senses in o.descrSenses (default all), as well as through its own flag: options
	-- that resemble each other share what they learn, and one never tried is valued by its resemblance.
	-- With o.descrLearn > 0 the descriptor takes a gradient step on the option's own rows, so a tag is a
	-- prior the creature revises, not a rule. Measured: revisable descriptors beat private flags at 8, 32
	-- and 100 acts, and fixed ones are worse than revisable ones everywhere.
	self.descr = o.descriptors ~= nil
	self.descriptors = o.descriptors
	self.descrDim = o.descrDim or 0
	self.descrLearn = o.descrLearn or 0
	self.descrN = {}
	self.descrSenses = o.descrSenses
	if self.descr and not self.descrSenses then
		self.descrSenses = {}
		for i = 1, nIn do
			self.descrSenses[i] = i
		end
	end
	self.nDescr = if self.descr then self.descrDim * (1 + #self.descrSenses) else 0
	self.FO = 1 + self.nXO + nOpt + self.nPool + self.nDescr
	self.O = RLS.new(self.FO, self.NRO, self.valueRidge)
	for i = 1 + nIn + 1, 1 + self.nXO do
		self.O.P[i][i] = 1 / self.extraRidge
	end
	-- SPARSE (o.sparse = true, with o.groups from Senses.groups): a slot whose "there" reading is 0 is skipped
	-- in every covariance update, with all its numbers and copies. Linear cost in the absent slots, but sound
	-- only for slots that never return: a returning slot's stale cross-covariance wrecks its weights (FINDINGS
	-- 77). Use it for slots that are absent for good, not for things that come and go.
	-- off unless asked: skipping an absent slot is sound only for slots that never come back (FINDINGS 77)
	self.sparse = o.sparse == true and self.groups ~= nil
	self.sparseReset = o.sparseReset == true -- a slot back from absence forgets its cross-covariance
	-- BLOCK-LOCAL (o.blocks: index groups over the raw senses, the first being the self group): covariance is
	-- kept within a group only, and effects and couplings predict a group's senses from that group and the
	-- self. Learning cost becomes linear in the senses instead of their square, which is what makes a creature
	-- with hundreds of senses affordable. Senses.groups builds the groups for a slot layout.
	self.blocks = o.blocks
	-- o.localOutcome = true also makes the outcome model's covariance block-local (flags and descriptors kept
	-- in the self group's block); by default only the effects and couplings are local, which is most of the cost
	self.localOutcome = o.localOutcome == true
	if self.blocks then
		local groupOf = {}
		for g, B in ipairs(self.blocks) do
			for _, i in ipairs(B) do
				groupOf[i] = g
			end
		end
		self.groupOf = groupOf
	end
	if self.blocks and self.localOutcome then
		local ob = {}
		local function addCopy(offset: number)
			for g, B in ipairs(self.blocks) do
				local blk = {}
				if offset == 1 and g == 1 then
					blk[1] = 1
				end
				for _, i in ipairs(B) do
					table.insert(blk, offset + i)
				end
				table.insert(ob, blk)
			end
		end
		addCopy(1)
		local off = 1 + nIn
		if self.has.C then
			addCopy(off)
			off += nIn
		end
		if self.trend then
			addCopy(off)
			off += nIn
		end
		if self.has.H then
			local blk = {}
			for i = off + 1, off + self.nHaz + self.nTrace do
				table.insert(blk, i)
			end
			if #blk > 0 then
				table.insert(ob, blk)
			end
			off += self.nHaz + self.nTrace
		end
		assert(off == self.nX + 1, "[instinct] blocks: extras out of order")
		-- the option flags and descriptors share the self group's block: a flag cut off from the bias cannot be
		-- told apart from it, which is the lock-in of FINDINGS 67 built in
		for i = self.nX + 2, self.FO do
			table.insert(ob[1], i)
		end
		table.insert(ob, {}) -- the acquired inputs, appended as they come
		self.O.blocks = ob
	end
	if self.descr then
		-- the private flags start tight when descriptors carry the load
		for f = self.nXO + 2, self.nXO + 1 + nOpt do
			self.O.P[f][f] = 1 / self.extraRidge
		end
	end
	-- EQUIVARIANT effects (o.equivariant = true, with o.groups from Senses.groups): per option, one law for how
	-- the self and world readings change, and one law shared across every slot for how a slot's readings change
	-- (inputs: the self readings, the slot's own, their trends, and the slot's kind). Every present slot's rows
	-- train the same law and absent slots are skipped, so parameters do not grow with the slot count and the
	-- cost grows with the slots present: at 318 senses the settle fell from 8.9 ms to 2.0 ms in the prototype
	-- with no loss on world 2 (FINDINGS 80). Proposed in docs/IDEAS.md.
	self.equivariant = o.equivariant == true and self.groups ~= nil and #self.groups >= 2
	if self.has.E and self.equivariant then
		self.eqSelf = self.groups[1]
		self.eqSlots = {}
		for g = 2, #self.groups do
			table.insert(self.eqSlots, self.groups[g])
		end
		self.eqSlotSize = #self.groups[2]
		self.eqKinds = math.min(#self.eqSlots, 6)
		local nSelf, nSlot = #self.eqSelf, self.eqSlotSize
		local copies = if self.trend then 2 else 1
		-- both laws also read a pooled summary of every present slot: sums of each field by kind
		self.eqPoolN = self.eqKinds * nSlot
		self.eqFG = 1 + nSelf * copies + self.eqPoolN
		self.eqFS = 1 + (nSelf + nSlot) * copies + self.eqKinds + self.eqPoolN
		self.EG, self.ES = {}, {}
		for k = 1, nOpt do
			self.EG[k] = RLS.new(self.eqFG, nSelf, self.ridge)
			self.ES[k] = RLS.new(self.eqFS, nSlot, self.ridge)
		end
	elseif self.has.E then
		self.E = {}
		for k = 1, nOpt do
			self.E[k] = RLS.new(1 + self.nX, nIn, self.ridge)
			if self.blocks then
				self:localise(self.E[k], self.nX)
			end
		end
	end
	if self.has.H then
		self.Hm = RLS.new(1 + nIn, self.nHaz, self.ridge)
		self.eventLog = {}
	end
	if self.has.C and self.equivariant then
		-- tied couplings: one drift law for the self readings (from their last change and the pooled slots' last
		-- change by kind) and one shared across slots for a slot's drift (FINDINGS 82)
		self.cqPoolN = self.eqKinds * self.eqSlotSize
		self.CG = RLS.new(1 + #self.eqSelf + self.cqPoolN, #self.eqSelf, self.ridge)
		self.CS = RLS.new(1 + #self.eqSelf + self.eqSlotSize + self.eqKinds + self.cqPoolN, self.eqSlotSize, self.ridge)
		self.lastX, self.lastDx = nil, nil
	elseif self.has.C then
		self.Cm = RLS.new(1 + nIn, nIn, self.ridge)
		if self.blocks then
			self:localise(self.Cm, nIn)
		end
		self.lastX, self.lastDx = nil, nil
	end
	-- acquisition
	self.acquired = {}
	self.recent = {}
	self.acqKeep, self.acqSample, self.acqBudget = o.acqKeep or 1500, o.acqSample or 400, o.acqBudget or 300
	self.acqMax = o.acqMax or 6
	self.acqError, self.acqPatience, self.acqMinGap, self.acqDecay = 0.6, 400, 600, 0.995
	self.errV, self.varV, self.meanV, self.aboveFor, self.sinceSearch = 0, 1e-6, 0, 0, 0
	self.acqReading = nil
	self.searches, self.acqTime = 0, 0
	self.opPrior = {}
	for _, op in ipairs(OPNAMES) do
		self.opPrior[op] = 1
	end
	self.sensePrior = {}
	self.curious = {}
	-- every combination of picks, and each option's index in the one-hot
	self.combos = {}
	local function rec(ci: number, acc: { number })
		if ci > #choices then
			table.insert(self.combos, table.clone(acc))
			return
		end
		for oo = 1, #choices[ci].options do
			acc[ci] = oo
			rec(ci + 1, acc)
		end
	end
	rec(1, {})
	self.optIndex = {}
	self.optChoice, self.optLocal = {}, {}
	local k = 0
	for ci, c in ipairs(choices) do
		self.optIndex[ci] = {}
		for oo = 1, #c.options do
			k += 1
			self.optIndex[ci][oo] = k
			self.optChoice[k], self.optLocal[k] = ci, oo
		end
	end
	self.MEM, self.FLAT = {}, {}
	self.pending, self.pendingE = {}, {}
	self.tickTotals = {}
	self.thinkTime, self.train = 0, 0
	self.stats = { stored = 0, retests = 0, confirmed = 0, forgotten = 0, kept = 0, seen = 0, thinks = 0, updates = 0, rebirths = 0 }
	return self
end

-- ------------------------------------------------------------------ inputs

-- Which inputs of a model belong to a slot absent in raw senses x (its "there" reading, the group's first sense,
-- is 0). `copies` are the offsets at which the senses repeat in the model's inputs (1 for the senses, 1 + nIn for
-- the couplings' drift, and so on). Only slot groups can be absent; the first group is the self and never is.
function Mind:markAbsent(m, x: { number }, copies: { number })
	if not self.sparse then
		return
	end
	local absent = m.absent
	if not absent then
		absent = table.create(m.F, false)
		m.absent = absent
	end
	for i = 1, m.F do
		absent[i] = false
	end
	local was = m.wasAbsent
	if not was then
		was = {}
		m.wasAbsent = was
	end
	for g = 2, #self.groups do
		local B = self.groups[g]
		local gone = x[B[1]] == 0
		if gone then
			for _, off in ipairs(copies) do
				for _, i in ipairs(B) do
					absent[off + i] = true
				end
			end
		elseif was[g] and self.sparseReset then
			local P = m.P
			for _, off in ipairs(copies) do
				for _, i in ipairs(B) do
					local idx = off + i
					if idx <= m.F then
						local Pi = P[idx]
						local d = Pi[idx]
						for j = 1, m.F do
							Pi[j] = 0
							P[j][idx] = 0
						end
						Pi[idx] = d
					end
				end
			end
		end
		was[g] = gone
	end
end

-- the offsets at which the raw senses repeat in the outcome and effects inputs
function Mind:senseCopies(): { number }
	local copies = { 1 }
	local off = 1 + self.nIn
	if self.has.C then
		table.insert(copies, off)
		off += self.nIn
	end
	if self.trend then
		table.insert(copies, off)
		off += self.nIn
	end
	return copies
end

-- A model whose inputs are 1 followed by copies of the senses (nInputs of them) and whose outputs are the
-- senses: covariance within each copy of each group, and each output reads only its own group and the self
-- group, in every copy.
function Mind:localise(m, nInputs: number)
	local nIn, groups = self.nIn, self.blocks
	local copies = math.floor(nInputs / nIn)
	local blocks = {}
	for c = 0, copies - 1 do
		for g, B in ipairs(groups) do
			local blk = {}
			if c == 0 and g == 1 then
				blk[1] = 1
			end
			for _, i in ipairs(B) do
				table.insert(blk, 1 + c * nIn + i)
			end
			table.insert(blocks, blk)
		end
	end
	m.blocks = blocks
	m.ins = {}
	for r = 1, m.NR do
		local g = self.groupOf[r] or 1
		local I = { 1 }
		for c = 0, copies - 1 do
			for _, i in ipairs(groups[1]) do
				table.insert(I, 1 + c * nIn + i)
			end
			if g ~= 1 then
				for _, i in ipairs(groups[g]) do
					table.insert(I, 1 + c * nIn + i)
				end
			end
		end
		m.ins[r] = I
	end
end

-- The senses as the models see them: the raw senses, then the couplings' predicted drift, then
-- the hazards and their traces.
function Mind:extend(x: { number }, out: { number }?): { number }
	local X = out or {}
	local n = self.nIn
	for i = 1, n do
		X[i] = x[i]
	end
	local k = n
	if self.has.C then
		-- the couplings' predicted drift depends only on the last change, so it is the same for every
		-- extension within a think (and every candidate in the beam): computed once per settle
		local drift = self.driftCache
		if drift == nil then
			if self.equivariant then
				drift = self:cqDrift(self.lastX or x)
			else
				drift = table.create(n, 0)
				local ld = self.lastDx
				if ld then
					local dphi = { 1 }
					for i = 1, n do
						dphi[i + 1] = ld[i]
					end
					for i = 1, n do
						local c = RLS.confidence(self.Cm, i)
						if c > 0 then
							drift[i] = c * RLS.predict(self.Cm, i, dphi)
						end
					end
				end
			end
			self.driftCache = drift
		end
		for i = 1, n do
			k += 1
			X[k] = drift[i]
		end
	end
	if self.trend then
		local lx = self.lastThinkX
		for i = 1, n do
			k += 1
			X[k] = if lx then (x[i] - lx[i]) * 5 else 0
		end
	end
	if self.has.H then
		local hphi = { 1 }
		for i = 1, n do
			hphi[i + 1] = x[i]
		end
		for r = 1, self.nHaz do
			k += 1
			-- a hazard enters only above half explained share, and scales from there
			local c = (RLS.confidence(self.Hm, r) - 0.5) / 0.5
			if c < 0 then
				c = 0
			end
			local v = if c > 0 then RLS.predict(self.Hm, r, hphi) else 0
			X[k] = c * math.clamp(v, 0, 1)
		end
		for e = 1, #self.events do
			k += 1
			X[k] = self.trace[e]
		end
	end
	return X
end

-- The outcome model's inputs: 1, the extended senses, one flag per option, the acquired pairs.
function Mind:phiO(X: { number }, picks: { number }, out: { number }?): { number }
	local phi = out or {}
	phi[1] = 1
	if self.pooledValue then
		for q, i in ipairs(self.poolSelf) do
			phi[q + 1] = X[i]
		end
	else
		for i = 1, self.nX do
			phi[i + 1] = X[i]
		end
	end
	local k = self.nXO + 1
	for ci, c in ipairs(self.choices) do
		for oo = 1, #c.options do
			k += 1
			phi[k] = if picks[ci] == oo then 1 else 0
		end
	end
	if self.pooledValue then
		local size, kinds, nOpt = self.poolSize, self.poolKinds, self.nOpt
		local base = k
		for q = 1, self.nPool do
			phi[base + q] = 0
		end
		local copies = self.poolCopies
		local nc = #copies
		for g, B in ipairs(self.poolSlots) do
			if X[B[1]] ~= 0 then
				local kind = math.min(g, kinds) - 1
				for c, off in ipairs(copies) do
					local kb = base + (kind * nc + (c - 1)) * size
					for q, i in ipairs(B) do
						phi[kb + q] += X[off + i] or 0
					end
				end
				for ci = 1, #self.choices do
					local ob = base + kinds * nc * size + (self.optIndex[ci][picks[ci]] - 1) * size
					for q, i in ipairs(B) do
						phi[ob + q] += X[i]
					end
				end
			end
		end
		k = base + self.nPool
	end
	if self.descr then
		local D = self.descrDim
		local acc = self.descrAcc
		if not acc then
			acc = table.create(D, 0)
			self.descrAcc = acc
		end
		for q = 1, D do
			acc[q] = 0
		end
		for ci = 1, #self.choices do
			local d = self.descriptors[self.optIndex[ci][picks[ci]]]
			if d then
				for q = 1, D do
					acc[q] += d[q]
				end
			end
		end
		for q = 1, D do
			k += 1
			phi[k] = acc[q]
		end
		local ds = self.descrSenses
		for q = 1, D do
			local a = acc[q]
			for _, i in ipairs(ds) do
				k += 1
				phi[k] = a * X[i]
			end
		end
	end
	k = self.FO
	for _, a in ipairs(self.acquired) do
		k += 1
		phi[k] = OPS[a.op](phi[a.i + 1], phi[a.j + 1])
	end
	return phi
end

function Mind:phiE(X: { number }): { number }
	local phi = { 1 }
	for i = 1, self.nX do
		phi[i + 1] = X[i]
	end
	return phi
end

-- The senses one step on, if these picks are held: the sum of the options' effects, each counted
-- as much as its model has earned. Returns the next senses and the mean confidence behind them.
-- Each option's predicted, confidence-weighted change of the senses on inputs X, computed once per think and
-- summed per candidate: the beam then costs a vector sum per candidate instead of a prediction per option.
local function optionEffect(self, cache, k: number, X: { number }, phi: { number })
	local e = cache[k]
	if e then
		return e
	end
	local m = self.E[k]
	local d = table.create(self.nIn, 0)
	local total = 0
	if m.n > 0 then
		for i = 1, self.nIn do
			local c = RLS.confidence(m, i)
			if c > 0 then
				d[i] = c * RLS.predict(m, i, phi)
			end
			total += c
		end
	end
	e = { d = d, conf = if m.n > 0 then total / self.nIn else 0 }
	cache[k] = e
	return e
end

-- the pooled last change of the present slots, by kind
function Mind:cqPool(dx: { number }, x: { number }): { number }
	local pool = table.create(self.cqPoolN, 0)
	local size = self.eqSlotSize
	for g, B in ipairs(self.eqSlots) do
		if x[B[1]] ~= 0 then
			local base = (math.min(g, self.eqKinds) - 1) * size
			for q, i in ipairs(B) do
				pool[base + q] += dx[i]
			end
		end
	end
	return pool
end

function Mind:cqPhiG(dx: { number }, pool: { number }): { number }
	local phi = { 1 }
	for _, i in ipairs(self.eqSelf) do
		table.insert(phi, dx[i])
	end
	for q = 1, self.cqPoolN do
		table.insert(phi, pool[q])
	end
	return phi
end

function Mind:cqPhiS(dx: { number }, g: number, pool: { number }, out: { number }?): { number }
	local phi = out or {}
	phi[1] = 1
	local k = 1
	for _, i in ipairs(self.eqSelf) do
		k += 1
		phi[k] = dx[i]
	end
	for _, i in ipairs(self.eqSlots[g]) do
		k += 1
		phi[k] = dx[i]
	end
	local kind = math.min(g, self.eqKinds)
	for q = 1, self.eqKinds do
		k += 1
		phi[k] = if q == kind then 1 else 0
	end
	for q = 1, self.cqPoolN do
		k += 1
		phi[k] = pool[q]
	end
	return phi
end

-- the predicted drift of every sense from the last change, through the tied laws
function Mind:cqDrift(x: { number }): { number }
	local n = self.nIn
	local drift = table.create(n, 0)
	local ld = self.lastDx
	if not ld then
		return drift
	end
	local pool = self:cqPool(ld, x)
	local phiG = self:cqPhiG(ld, pool)
	for r, i in ipairs(self.eqSelf) do
		local c = RLS.confidence(self.CG, r)
		if c > 0 then
			drift[i] = c * RLS.predict(self.CG, r, phiG)
		end
	end
	local phiS = {}
	for g, B in ipairs(self.eqSlots) do
		if x[B[1]] ~= 0 then
			self:cqPhiS(ld, g, pool, phiS)
			for r, i in ipairs(B) do
				local c = RLS.confidence(self.CS, r)
				if c > 0 then
					drift[i] = c * RLS.predict(self.CS, r, phiS)
				end
			end
		end
	end
	return drift
end

-- where the trend copy of the senses sits in X (nil without trends)
function Mind:trendOffset(): number?
	if not self.trend then
		return nil
	end
	return self.nIn + (if self.has.C then self.nIn else 0)
end

function Mind:eqPool(X: { number }): { number }
	local pool = table.create(self.eqPoolN, 0)
	local size = self.eqSlotSize
	for g, B in ipairs(self.eqSlots) do
		if X[B[1]] ~= 0 then
			local base = (math.min(g, self.eqKinds) - 1) * size
			for q, i in ipairs(B) do
				pool[base + q] += X[i]
			end
		end
	end
	return pool
end

function Mind:eqPhiG(X: { number }, out: { number }?, pool: { number }?): { number }
	local phi = out or {}
	phi[1] = 1
	local k = 1
	for _, i in ipairs(self.eqSelf) do
		k += 1
		phi[k] = X[i]
	end
	local to = self:trendOffset()
	if to then
		for _, i in ipairs(self.eqSelf) do
			k += 1
			phi[k] = X[to + i]
		end
	end
	pool = pool or self:eqPool(X)
	for q = 1, self.eqPoolN do
		k += 1
		phi[k] = pool[q]
	end
	return phi
end

function Mind:eqPhiS(X: { number }, g: number, out: { number }?, pool: { number }?): { number }
	local phi = out or {}
	phi[1] = 1
	local k = 1
	local B = self.eqSlots[g]
	for _, i in ipairs(self.eqSelf) do
		k += 1
		phi[k] = X[i]
	end
	for _, i in ipairs(B) do
		k += 1
		phi[k] = X[i]
	end
	local to = self:trendOffset()
	if to then
		for _, i in ipairs(self.eqSelf) do
			k += 1
			phi[k] = X[to + i]
		end
		for _, i in ipairs(B) do
			k += 1
			phi[k] = X[to + i]
		end
	end
	local kind = math.min(g, self.eqKinds)
	for q = 1, self.eqKinds do
		k += 1
		phi[k] = if q == kind then 1 else 0
	end
	pool = pool or self:eqPool(X)
	for q = 1, self.eqPoolN do
		k += 1
		phi[k] = pool[q]
	end
	return phi
end

function Mind:stepAheadEquiv(X: { number }, picks: { number }, out: { number }?, cache: any?): ({ number }, number)
	local nxt = out or {}
	for i = 1, self.nIn do
		nxt[i] = X[i]
	end
	cache = cache or {}
	local pool = cache.pool
	if not pool then
		pool = self:eqPool(X)
		cache.pool = pool
	end
	local phiG = cache.phiG
	if not phiG then
		phiG = self:eqPhiG(X, nil, pool)
		cache.phiG = phiG
	end
	local phiS = cache.phiS
	if not phiS then
		phiS = {}
		for g, B in ipairs(self.eqSlots) do
			if X[B[1]] ~= 0 then
				phiS[g] = self:eqPhiS(X, g, nil, pool)
			end
		end
		cache.phiS = phiS
	end
	local total, count = 0, 0
	for ci = 1, #self.choices do
		local k = self.optIndex[ci][picks[ci]]
		local G, S = self.EG[k], self.ES[k]
		if G.n > 0 then
			for r, i in ipairs(self.eqSelf) do
				local c = RLS.confidence(G, r)
				if c > 0 then
					nxt[i] += c * RLS.predict(G, r, phiG)
				end
				total += c
				count += 1
			end
		end
		if S.n > 0 then
			for g, B in ipairs(self.eqSlots) do
				local ps = phiS[g]
				if ps then
					for r, i in ipairs(B) do
						local c = RLS.confidence(S, r)
						if c > 0 then
							nxt[i] += c * RLS.predict(S, r, ps)
						end
						total += c
						count += 1
					end
				end
			end
		end
	end
	return nxt, if count > 0 then total / count else 0
end

function Mind:stepAhead(X: { number }, picks: { number }, out: { number }?, cache: any?): ({ number }, number)
	if self.equivariant then
		return self:stepAheadEquiv(X, picks, out, cache)
	end
	local nxt = out or {}
	for i = 1, self.nIn do
		nxt[i] = X[i]
	end
	cache = cache or {}
	local phi = cache.phi
	if not phi then
		phi = self:phiE(X)
		cache.phi = phi
	end
	local total, count = 0, 0
	for ci = 1, #self.choices do
		local e = optionEffect(self, cache, self.optIndex[ci][picks[ci]], X, phi)
		local d = e.d
		for i = 1, self.nIn do
			nxt[i] += d[i]
		end
		total += e.conf
		count += 1
	end
	return nxt, if count > 0 then total / count else 0
end

-- ------------------------------------------------------------------ memory of surprises

local function rebuildFlat(self)
	local F, MEM = self.FLAT, self.MEM
	table.clear(F)
	local n = self.nIn
	for e, ev in ipairs(MEM) do
		local base = (e - 1) * n
		for i = 1, n do
			F[base + i] = ev.x[i]
		end
	end
end

local function nearest(self, x: { number })
	local F, MEM, n = self.FLAT, self.MEM, self.nIn
	local bd, bestE = self.memRadius * self.memRadius, 0
	for e = 1, #MEM do
		local base = (e - 1) * n
		local d = 0
		local mk = MEM[e].mask
		if mk then
			for q = 1, n do
				local t = (x[q] - F[base + q]) * mk[q]
				d += t * t
				if d >= bd then
					break
				end
			end
		else
			for q = 1, n do
				local t = x[q] - F[base + q]
				d += t * t
				if d >= bd then
					break
				end
			end
		end
		if d < bd then
			bestE, bd = e, d
		end
	end
	return if bestE > 0 then MEM[bestE] else nil
end

local function storeMemory(self, x: { number }, picks: { number }, y: number, mask: { number }?)
	if #self.MEM >= self.memory then
		table.remove(self.MEM, 1)
		rebuildFlat(self)
	end
	local e = { x = table.clone(x), picks = table.clone(picks), y = y, n = 1, sum = y, mask = mask }
	table.insert(self.MEM, e)
	local base = #self.FLAT
	for i = 1, self.nIn do
		self.FLAT[base + i] = x[i]
	end
	return e
end

-- ------------------------------------------------------------------ value

function Mind:setPreferences(pref: { [string]: number })
	for k = 1, self.NRO do
		self.pref[k] = pref[self.readings[k]] or 0
	end
end

function Mind:valueOf(phi: { number }): number
	local O, v = self.O, 0
	for k = 1, self.NRO do
		local w = self.pref[k]
		if w ~= 0 then
			v += w * RLS.predict(O, k, phi)
		end
	end
	return v
end

-- The worth of one combination on senses X.
function Mind:worth(X: { number }, picks: { number }, phi: { number }, plain: boolean?): number
	self:phiO(X, picks, phi)
	local v = self:valueOf(phi)
	if plain then
		return v
	end
	if self.has.U then
		v += self.kU * RLS.spread(self.O, phi)
	end
	return v
end

-- ------------------------------------------------------------------ separable pick search

-- Which choice an outcome input depends on: nil for none, a choice index for one, false for several (the
-- descriptors sum over every choice).
function Mind:pickDep(idx: number): any
	local nXO, nOpt = self.nXO, self.nOpt
	if idx <= 1 + nXO then
		return nil
	elseif idx <= 1 + nXO + nOpt then
		return self.optChoice[idx - 1 - nXO]
	elseif idx <= 1 + nXO + nOpt + self.nPool then
		local r = idx - (1 + nXO + nOpt) - self.poolKinds * #self.poolCopies * self.poolSize
		if r <= 0 then
			return nil
		end
		return self.optChoice[(r - 1) // self.poolSize + 1]
	elseif idx <= self.FO then
		return false
	end
	local a = self.acquired[idx - self.FO]
	local di, dj = self:pickDep(a.i + 1), self:pickDep(a.j + 1)
	if di == nil then
		return dj
	elseif dj == nil or di == dj then
		return di
	end
	return false
end

-- One outcome input for combination p on the context of a target option (its senses, the pick-free entries
-- and the pooled slot sums), without building phi.
local function sepEntry(self, ctx, idx: number, p: { number }): number
	local nXO, nOpt = self.nXO, self.nOpt
	if idx <= 1 + nXO then
		return ctx.phiB[idx]
	elseif idx <= 1 + nXO + nOpt then
		local g = idx - 1 - nXO
		return if p[self.optChoice[g]] == self.optLocal[g] then 1 else 0
	elseif idx <= 1 + nXO + nOpt + self.nPool then
		local size = self.poolSize
		local r = idx - (1 + nXO + nOpt) - self.poolKinds * #self.poolCopies * size
		if r <= 0 then
			return ctx.phiB[idx]
		end
		local g = (r - 1) // size + 1
		return if p[self.optChoice[g]] == self.optLocal[g] then ctx.poolSum[r - (g - 1) * size] else 0
	elseif idx <= self.FO then
		local D = self.descrDim
		local r = idx - (1 + nXO + nOpt + self.nPool)
		local q, i
		if r <= D then
			q = r
		else
			local nDS = #self.descrSenses
			q = (r - D - 1) // nDS + 1
			i = self.descrSenses[(r - D - 1) % nDS + 1]
		end
		local acc = 0
		for ci = 1, #self.choices do
			local d = self.descriptors[self.optIndex[ci][p[ci]]]
			if d then
				acc += d[q]
			end
		end
		return if i then acc * ctx.X[i] else acc
	end
	local a = self.acquired[idx - self.FO]
	return OPS[a.op](sepEntry(self, ctx, a.i + 1, p), sepEntry(self, ctx, a.j + 1, p))
end

-- Scores every feasible combination into `scored` ({ p, v }), as worth() would, at a base plus one number a
-- chosen option (plus the few acquired features that pair two choices, evaluated per combination).
function Mind:scoreCombos(Xs: { { number } }, feasible, scored)
	local O = self.O
	local F, NRO, FO = O.F, self.NRO, self.FO
	local nXO, nOpt, nPool = self.nXO, self.nOpt, self.nPool
	local choices = self.choices
	local nCh = #choices
	-- the value's direction: value(phi) = u . phi
	local u = self.uBuf
	if not u then
		u = {}
		self.uBuf = u
	end
	for f = 1, F do
		u[f] = 0
	end
	for k = 1, NRO do
		local w = self.pref[k]
		if w ~= 0 then
			local W = O.W[k]
			if O.ins then
				for _, i in O.ins[k] do
					u[i] += w * W[i]
				end
			else
				for f = 1, F do
					u[f] += w * W[f]
				end
			end
		end
	end
	local pooled = self.pooledValue
	local size, kinds = self.poolSize, self.poolKinds
	local nc = if pooled then #self.poolCopies else 0
	local poolOptBase = 1 + nXO + nOpt + (if pooled then kinds * nc * size else 0)
	local descr = self.descr
	local D = if descr then self.descrDim else 0
	local dBase = 1 + nXO + nOpt + nPool
	local ds = self.descrSenses
	local ctxs, bases, deltas, cross = {}, {}, {}, {}
	for a = 1, #choices[1].options do
		local X = Xs[a]
		-- the pick-free part of phi, the rest zero
		local phiB = table.create(FO, 0)
		phiB[1] = 1
		if pooled then
			for q, i in ipairs(self.poolSelf) do
				phiB[q + 1] = X[i]
			end
		else
			for i = 1, self.nX do
				phiB[i + 1] = X[i]
			end
		end
		local poolSum
		if pooled then
			poolSum = table.create(size, 0)
			local base = 1 + nXO + nOpt
			local copies = self.poolCopies
			for g, B in ipairs(self.poolSlots) do
				if X[B[1]] ~= 0 then
					local kind = math.min(g, kinds) - 1
					for c, off in ipairs(copies) do
						local kb = base + (kind * nc + (c - 1)) * size
						for q, i in ipairs(B) do
							phiB[kb + q] += X[off + i] or 0
						end
					end
					for q, i in ipairs(B) do
						poolSum[q] += X[i]
					end
				end
			end
		end
		local ctx = { X = X, phiB = phiB, poolSum = poolSum }
		ctxs[a] = ctx
		local b = 0
		for f = 1, FO do
			local v = phiB[f]
			if v ~= 0 then
				b += u[f] * v
			end
		end
		-- a descriptor's worth, its own and through the senses it is read against
		local gq
		if descr then
			gq = table.create(D, 0)
			local nDS = #ds
			for q = 1, D do
				local g = u[dBase + q]
				local row = dBase + D + (q - 1) * nDS
				for t, i in ipairs(ds) do
					g += u[row + t] * X[i]
				end
				gq[q] = g
			end
		end
		-- one number a chosen option
		local delta = {}
		for ci, c in ipairs(choices) do
			local dc = {}
			for oo = 1, #c.options do
				local g = self.optIndex[ci][oo]
				local v = u[1 + nXO + g]
				if pooled then
					local ob = poolOptBase + (g - 1) * size
					for q = 1, size do
						v += u[ob + q] * poolSum[q]
					end
				end
				if descr then
					local dd = self.descriptors[g]
					if dd then
						for q = 1, D do
							v += dd[q] * gq[q]
						end
					end
				end
				dc[oo] = v
			end
			delta[ci] = dc
		end
		-- the acquired features: pick-free ones into the base, one-choice ones into that choice's numbers
		local scratch = table.create(nCh, 1)
		for f, _ in ipairs(self.acquired) do
			local uf = u[FO + f]
			if uf ~= 0 then
				local dep = self:pickDep(FO + f)
				if dep == nil then
					b += uf * sepEntry(self, ctx, FO + f, scratch)
				elseif dep then
					local dc = delta[dep]
					for oo = 1, #choices[dep].options do
						scratch[dep] = oo
						dc[oo] += uf * sepEntry(self, ctx, FO + f, scratch)
					end
					scratch[dep] = 1
				elseif a == 1 then
					table.insert(cross, { idx = FO + f, u = uf })
				end
			end
		end
		bases[a] = b
		deltas[a] = delta
	end
	local pool = self.scoredPool
	if not pool then
		pool = {}
		self.scoredPool = pool
	end
	local n = 0
	for _, p in ipairs(self.combos) do
		if not feasible or feasible(p) then
			local a = p[1]
			local v = bases[a]
			local delta = deltas[a]
			for ci = 1, nCh do
				v += delta[ci][p[ci]]
			end
			if #cross > 0 then
				local ctx = ctxs[a]
				for _, cr in ipairs(cross) do
					v += cr.u * sepEntry(self, ctx, cr.idx, p)
				end
			end
			n += 1
			local e = pool[n]
			if not e then
				e = {}
				pool[n] = e
			end
			e.p, e.v = p, v
			scored[n] = e
		end
	end
end

-- ------------------------------------------------------------------ think

-- sensesOf(target) returns the raw senses as if that target option were taken (the first choice is
-- the target, and choosing one changes what the slots hold). feasible(picks) says whether the
-- world would accept a combination.
function Mind:think(sensesOf, feasible)
	local t0 = clock()
	local xs, Xs = {}, {}
	for a = 1, #self.choices[1].options do
		xs[a] = sensesOf(a)
		Xs[a] = self:extend(xs[a])
	end
	local x1 = xs[1]
	local function finish(picks, event)
		self.lastThinkX = xs[picks[1]]
		self.stats.thinks += 1
		self.thinkTime += clock() - t0
		return picks, xs[picks[1]], self:phiO(Xs[picks[1]], picks), event
	end
	-- a remembered surprise near these senses: replay it, as often as its retests have earned
	if self.memory > 0 then
		local event = nearest(self, x1)
		if event then
			local follow = true
			if event.n > 1 then
				local share = (event.sum / event.n) / math.max(event.y, 1e-6)
				follow = math.random() < math.max(if event.mask then 0.02 else self.memFloor, math.min(1, share))
			end
			if follow and (not feasible or feasible(event.picks)) then
				self.stats.retests += 1
				return finish(table.clone(event.picks), event)
			end
		end
	end
	-- first step: every combination the world would accept
	local scored = {}
	local phi = {}
	if self.separable and not self.has.U then
		self:scoreCombos(Xs, feasible, scored)
	else
		for _, p in ipairs(self.combos) do
			if not feasible or feasible(p) then
				table.insert(scored, { p = p, v = self:worth(Xs[p[1]], p, phi) })
			end
		end
	end
	if #scored == 0 then
		return finish(table.clone(self.combos[1]), nil)
	end
	-- second step: the best BEAM extended by their projected next senses, held
	if self.has.E then
		-- the best BEAM to the front, in order (a selection, not a sort: the rest need no order)
		-- the best BEAM to the front, in order (a selection, not a sort: the rest need no order); ties drawn
		-- at random so the same combinations are not always the ones looked ahead on
		local nb = math.min(self.beam, #scored)
		for i = 1, nb do
			local bi, bv, ties = i, scored[i].v, 1
			for j = i + 1, #scored do
				local v = scored[j].v
				if v > bv then
					bi, bv, ties = j, v, 1
				elseif v == bv then
					ties += 1
					if math.random(ties) == 1 then
						bi = j
					end
				end
			end
			scored[i], scored[bi] = scored[bi], scored[i]
		end
		local nxt = {}
		local caches = {} -- one effects cache per target option's senses
		for k = 1, nb do
			local s = scored[k]
			local a = s.p[1]
			local cache = caches[a]
			if not cache then
				cache = {}
				caches[a] = cache
			end
			local _, conf = self:stepAhead(Xs[a], s.p, nxt, cache)
			local X2 = self:extend(nxt)
			s.v += self.gamma * conf * self:worth(X2, s.p, phi, true)
		end
	end
	-- STUCK: the senses have not moved for nudgeAfter decisions while it acts, so whatever it is doing does
	-- nothing (a body against a wall). Repeating it teaches nothing; one random other combination is taken.
	if self.exploring and self.nudgeAfter > 0 and #scored > 1 then
		local lx = self.lastThinkX
		local same = lx ~= nil
		if same then
			for i = 1, self.nIn do
				if math.abs(x1[i] - lx[i]) > 1e-3 then
					same = false
					break
				end
			end
		end
		self.sameFor = if same then self.sameFor + 1 else 0
		if self.sameFor >= self.nudgeAfter then
			-- and hold the nudge for as long as the stuck spell lasted, so it actually displaces the body:
			-- one random decision handed straight back to the same greedy choice moves nothing
			self.sameFor = 0
			self.stats.nudged = (self.stats.nudged or 0) + 1
			local s = scored[math.random(#scored)]
			self.stickyPicks = s.p
			self.nudgeUntil = self.stats.thinks + self.nudgeAfter
			return finish(table.clone(s.p), nil)
		end
		if self.nudgeUntil and self.stats.thinks < self.nudgeUntil and self.stickyPicks and (not feasible or feasible(self.stickyPicks)) then
			return finish(table.clone(self.stickyPicks), nil)
		end
	end
	if self.eps > 0 and self.exploring and math.random() < self.eps then
		-- a random combination, held for a while: re-rolling every tick cancels out into a jitter that
		-- goes nowhere, and teaches the effects models nothing about what holding a move does
		local p = self.stickyPicks
		-- a held move whose senses have not changed since the last decision (a body pinned on a wall) is
		-- teaching nothing: re-roll it at once
		local stuck = false
		local lx = self.lastThinkX
		if p ~= nil and lx ~= nil then
			stuck = true
			for i = 1, self.nIn do
				if math.abs(x1[i] - lx[i]) > 1e-3 then
					stuck = false
					break
				end
			end
		end
		if p == nil or stuck or math.random() >= self.sticky or (feasible and not feasible(p)) then
			p = scored[math.random(#scored)].p
			self.stickyPicks = p
		end
		self.stats.explored = (self.stats.explored or 0) + 1
		return finish(table.clone(p), nil)
	end
	local best, bp, ties = -math.huge, nil, 1
	for _, s in ipairs(scored) do
		if s.v > best + 1e-9 then
			best, bp, ties = s.v, s.p, 1
		elseif s.v > best - 1e-9 then
			ties += 1
			if math.random(ties) == 1 then
				bp = s.p
			end
		end
	end
	if not bp then
		bp = scored[math.random(#scored)].p -- every value NaN: anything rather than nothing
	end
	return finish(table.clone(bp), nil)
end

-- ------------------------------------------------------------------ events

function Mind:sawEvent(tick: number, name: string)
	if not self.has.H then
		return
	end
	local e = self.eventLog[tick]
	if not e then
		e = {}
		self.eventLog[tick] = e
	end
	e[name] = true
	for i, n in ipairs(self.events) do
		if n == name then
			self.trace[i] = 1
		end
	end
end

-- The hazard readings of a row made at `at`: for each event, whether it happened next tick, how
-- long until it did (capped at the horizon), and whether it happened within eight ticks.
local function hazardsOf(self, at: number): { number }
	local y = {}
	for _, name in ipairs(self.events) do
		local first = nil
		for t = at + 1, at + self.H do
			local e = self.eventLog[t]
			if e and e[name] then
				first = t - at
				break
			end
		end
		table.insert(y, if first == 1 then 1 else 0)
		table.insert(y, (first or self.H) / self.H)
		table.insert(y, if first and first <= 8 then 1 else 0)
	end
	return y
end

-- ------------------------------------------------------------------ rows

-- A decision was taken on senses x with these picks; the readings' totals stand at `totals`.
function Mind:note(x: { number }, phi: { number }, picks: { number }, event, totals: { number }, tick: number)
	local X = self:extend(x)
	local snap = table.clone(totals)
	table.insert(self.pending, { x = x, X = X, phi = phi, picks = picks, event = event, totals = snap, at = tick })
	self.tickTotals[tick] = snap
	if self.has.E then
		table.insert(self.pendingE, { X = X, picks = picks, at = tick })
	end
end

local function trackError(self, score: number, predicted: number)
	local a = self.acqDecay
	self.meanV = a * self.meanV + (1 - a) * score
	self.errV = a * self.errV + (1 - a) * (score - predicted) ^ 2
	self.varV = a * self.varV + (1 - a) * (score - self.meanV) ^ 2
	self.sinceSearch += 1
	-- the worst-explained reading the preferences care about, by the outcome model's own bookkeeping
	local worst, wq = 0, nil
	for q = 1, self.NRO do
		if self.pref[q] ~= 0 and self.O.var[q] > 1e-3 then
			local sh = self.O.err[q] / (1.01 * self.O.var[q] + 1e-6)
			if sh > worst then
				worst, wq = sh, q
			end
		end
	end
	self.acqReading = wq
	local above = wq ~= nil and worst > self.acqError
	self.aboveFor = if above then self.aboveFor + 1 else 0
	if self.acqEarly and self.stats.kept >= self.acqEarly then
		self.acqEarly = nil
		self:acquire()
	elseif self.aboveFor >= self.acqPatience and self.sinceSearch >= self.acqMinGap and #self.acquired < self.acqMax then
		self:acquire()
	end
end

-- A settled row joins the recent record (raw inputs and readings) for the search.
local function remember(self, phi: { number }, y: { number })
	local raw = {}
	local nRaw = self.nXO + self.nOpt + self.nPool
	for i = 1, nRaw do
		raw[i] = phi[i + 1]
	end
	table.insert(self.recent, { raw = raw, y = table.clone(y) })
	if #self.recent > self.acqKeep then
		table.remove(self.recent, 1)
	end
end

-- Settle what has come due. `totals` are the readings' totals now, `xNow` the senses now.
function Mind:settle(totals: { number }, xNow: { number }, tick: number, over: boolean?)
	local S = self.stats
	if self.has.H then
		for e = 1, #self.events do
			self.trace[e] *= 0.85
		end
	end
	-- couplings: the change of the senses since the last settle, and what the last change said would follow
	if self.has.C then
		if self.lastX then
			local dx = {}
			for i = 1, self.nIn do
				dx[i] = xNow[i] - self.lastX[i]
			end
			if self.lastDx and self.equivariant then
				local ld = self.lastDx
				local pool = self:cqPool(ld, self.lastX)
				local dyG = {}
				for q, i in ipairs(self.eqSelf) do
					dyG[q] = dx[i]
				end
				RLS.update(self.CG, self:cqPhiG(ld, pool), dyG)
				local phiS, dyS = {}, {}
				for g, B in ipairs(self.eqSlots) do
					if self.lastX[B[1]] ~= 0 and xNow[B[1]] ~= 0 then
						self:cqPhiS(ld, g, pool, phiS)
						for q, i in ipairs(B) do
							dyS[q] = dx[i]
						end
						RLS.update(self.CS, phiS, dyS)
					end
				end
			elseif self.lastDx then
				local dphi = { 1 }
				for i = 1, self.nIn do
					dphi[i + 1] = self.lastDx[i]
				end
				self:markAbsent(self.Cm, xNow, { 1 })
				RLS.update(self.Cm, dphi, dx)
			end
			self.lastDx = dx
			self.driftCache = nil
		end
		self.lastX = xNow
	end
	-- effects: rows one STEP old
	if self.has.E then
		local keep = {}
		for _, r in ipairs(self.pendingE) do
			if (tick - r.at >= self.STEP or over) and self.equivariant then
				local X = r.X
				local pool = self:eqPool(X)
				local phiG = self:eqPhiG(X, nil, pool)
				local dyG = {}
				for q, i in ipairs(self.eqSelf) do
					dyG[q] = xNow[i] - X[i]
				end
				local phiS, dyS = {}, {}
				for ci = 1, #self.choices do
					local k = self.optIndex[ci][r.picks[ci]]
					RLS.update(self.EG[k], phiG, dyG)
					local S = self.ES[k]
					for g, B in ipairs(self.eqSlots) do
						if X[B[1]] ~= 0 and xNow[B[1]] ~= 0 then
							self:eqPhiS(X, g, phiS, pool)
							for q, i in ipairs(B) do
								dyS[q] = xNow[i] - X[i]
							end
							RLS.update(S, phiS, dyS)
						end
					end
				end
			elseif tick - r.at >= self.STEP or over then
				local phi = self:phiE(r.X)
				local dy = {}
				for i = 1, self.nIn do
					dy[i] = xNow[i] - r.X[i]
				end
				local copies = if self.sparse then self:senseCopies() else nil
				for ci = 1, #self.choices do
					local m = self.E[self.optIndex[ci][r.picks[ci]]]
					if copies then
						self:markAbsent(m, r.X, copies)
					end
					RLS.update(m, phi, dy)
				end
			else
				table.insert(keep, r)
			end
		end
		self.pendingE = keep
	end
	-- outcomes: rows a horizon old
	local keep = {}
	for _, r in ipairs(self.pending) do
		if tick - r.at >= self.H or over then
			local y = {}
			local g = self.discount
			if g >= 1 then
				for k = 1, self.NRO do
					y[k] = totals[k] - r.totals[k]
				end
			else
				for k = 1, self.NRO do
					y[k] = 0
				end
				local prev = r.totals
				for t = r.at + 1, tick do
					local cur = self.tickTotals[t] or totals
					local w = g ^ (t - r.at)
					for k = 1, self.NRO do
						y[k] += w * (cur[k] - prev[k])
					end
					prev = cur
				end
			end
			S.seen += 1
			local score = 0
			for k = 1, self.NRO do
				score += self.pref[k] * y[k]
			end
			if #r.phi ~= self.O.F then
				self:phiO(r.X, r.picks, r.phi) -- a search grew the model since
			end
			local predicted = self:valueOf(r.phi)
			local wrong = math.abs(predicted - score) > self.surprise
			if self.memory > 0 then
				if r.event then
					local e = r.event
					e.n += 1
					e.sum += score
					if (e.n >= self.memTries and e.sum / e.n < self.memGood / 2) or (e.mask and e.n >= 40 and e.sum / e.n < self.memGood) then
						local at = table.find(self.MEM, e)
						if at then
							table.remove(self.MEM, at)
							rebuildFlat(self)
						end
						S.forgotten += 1
					elseif score >= self.memGood then
						S.confirmed += 1
					end
				elseif wrong and score >= self.memGood then
					storeMemory(self, r.x, r.picks, score)
					S.stored += 1
				end
			end
			if self.has.H then
				local hphi = { 1 }
				for i = 1, self.nIn do
					hphi[i + 1] = r.x[i]
				end
				RLS.update(self.Hm, hphi, hazardsOf(self, r.at))
			end
			local reps = if self.memory > 0 and wrong and score >= self.memGood then self.reps else 1
			if self.has.A then
				remember(self, r.phi, y)
				trackError(self, score, predicted)
				if #r.phi ~= self.O.F then
					self:phiO(r.X, r.picks, r.phi)
				end
			end
			if self.sparse then
				self:markAbsent(self.O, r.x, self:senseCopies())
			end
			RLS.update(self.O, r.phi, y, reps)
			if self.descr and self.descrLearn > 0 then
				self:descrStep(r, y)
			end
			S.updates += 1
			S.kept += 1
		else
			table.insert(keep, r)
		end
	end
	self.pending = keep
	if self.has.H then
		for t in pairs(self.eventLog) do
			if t < tick - self.H - 30 then
				self.eventLog[t] = nil
			end
		end
	end
	for t in pairs(self.tickTotals) do
		if t < tick - self.H - 2 then
			self.tickTotals[t] = nil
		end
	end
end

-- Forget the conclusions, keep the physics and the memories. What a creature that learned something
-- false in its first moments needs is not more rows but a fresh start; the coach decides when.
function Mind:rebirth()
	local F, NR = self.O.F, self.O.NR
	local blocks = self.O.blocks
	self.O = RLS.new(F, NR, self.valueRidge)
	self.O.blocks = blocks
	for i = 1 + self.nIn + 1, 1 + self.nXO do
		self.O.P[i][i] = 1 / self.extraRidge
	end
	for q = 1, #self.acquired do
		self.O.P[self.FO + q][self.FO + q] = 1 / self.extraRidge
	end
	if self.descr then
		for f = self.nXO + 2, self.nXO + 1 + self.nOpt do
			self.O.P[f][f] = 1 / self.extraRidge
		end
	end
	self.pending = {}
	self.stats.rebirths += 1
end

-- DESCRIPTOR LEARNING: value = sum_q W_q d_q + sum_{q,i} W_{q,i} d_q x_i (+ the rest), so the gradient of the
-- preference-weighted value with respect to d_q is sum_r pref_r (W_r[q] + sum_i W_r[q,i] x_i). One step toward
-- the row's residual for each chosen option that has a descriptor, at a rate that fades as its rows mount.
function Mind:descrStep(r, y: { number })
	local O, D = self.O, self.descrDim
	local base = 1 + self.nXO + self.nOpt + self.nPool
	local score, predicted = 0, self:valueOf(r.phi)
	for q = 1, self.NRO do
		score += self.pref[q] * y[q]
	end
	local e = score - predicted
	if e ~= e then
		return
	end
	local ds = self.descrSenses
	for ci = 1, #self.choices do
		local k = self.optIndex[ci][r.picks[ci]]
		local d = self.descriptors[k]
		if d then
			self.descrN[k] = (self.descrN[k] or 0) + 1
			local rate = self.descrLearn / (1 + self.descrN[k] / 50)
			for q = 1, D do
				local g = 0
				for rr = 1, self.NRO do
					local w = self.pref[rr]
					if w ~= 0 then
						local W = O.W[rr]
						local t = W[base + q]
						local off = base + D + (q - 1) * #ds
						for j, i in ipairs(ds) do
							t += W[off + j] * r.X[i]
						end
						g += w * t
					end
				end
				d[q] = math.clamp(d[q] + rate * e * g, -3, 3)
			end
		end
	end
end

-- ------------------------------------------------------------------ acquisition

function Mind:acquire()
	local t0 = clock()
	local all = self.recent
	if #all < 200 then
		return
	end
	local rows = {}
	local step = math.max(1, math.floor(#all / self.acqSample))
	for k = 1, #all, step do
		table.insert(rows, all[k])
	end
	local R = #rows
	local nRaw = self.nXO + self.nOpt + self.nPool
	-- the residuals to chase: the value's, and the worst reading's
	local targets = { { name = "value", res = {} } }
	if self.acqReading then
		table.insert(targets, { name = self.readings[self.acqReading], q = self.acqReading, res = {} })
	end
	local phi, Xr, pk = {}, {}, {}
	for k, r in ipairs(rows) do
		if self.pooledValue then
			-- the row's inputs are stored whole; only the acquired inputs are recomputed
			phi[1] = 1
			for i = 1, nRaw do
				phi[i + 1] = r.raw[i]
			end
			local kk = self.FO
			for _, a in ipairs(self.acquired) do
				kk += 1
				phi[kk] = OPS[a.op](phi[a.i + 1], phi[a.j + 1])
			end
		else
			for i = 1, self.nX do
				Xr[i] = r.raw[i]
			end
			local q = self.nX
			for ci, c in ipairs(self.choices) do
				pk[ci] = 1
				for oo = 1, #c.options do
					q += 1
					if r.raw[q] == 1 then
						pk[ci] = oo
					end
				end
			end
			self:phiO(Xr, pk, phi)
		end
		for _, t in ipairs(targets) do
			if t.q then
				t.res[k] = r.y[t.q] - RLS.predict(self.O, t.q, phi)
			else
				local score = 0
				for q2 = 1, self.NRO do
					score += self.pref[q2] * r.y[q2]
				end
				t.res[k] = score - self:valueOf(phi)
			end
		end
	end
	for _, t in ipairs(targets) do
		local m, sd = 0, 0
		for k = 1, R do
			m += t.res[k]
		end
		m /= R
		for k = 1, R do
			sd += (t.res[k] - m) ^ 2
		end
		t.mR, t.sdR = m, math.sqrt(sd / R) + 1e-9
	end
	-- a candidate's correlation with the residuals: the best over the targets
	local function corr(get)
		local m, m2 = 0, 0
		local v = {}
		for k = 1, R do
			v[k] = get(k)
			m += v[k]
			m2 += v[k] * v[k]
		end
		m /= R
		local sd = math.sqrt(math.max(0, m2 / R - m * m))
		if sd <= 1e-6 then
			return 0, nil
		end
		local best, bestName = 0, nil
		for _, t in ipairs(targets) do
			local c = 0
			for k = 1, R do
				c += (v[k] - m) * (t.res[k] - t.mR)
			end
			c = math.abs(c / R / sd / t.sdR)
			if c > best then
				best, bestName = c, t.name
			end
		end
		return best, bestName
	end
	local own = {}
	for i = 1, nRaw do
		own[i] = corr(function(k)
			return rows[k].raw[i]
		end)
	end
	local taken = {}
	for _, a in ipairs(self.acquired) do
		taken[a.i .. "," .. a.j .. a.op] = true
	end
	local function weighted(list, w)
		local tot = 0
		for _, x in ipairs(list) do
			tot += w[x] or 1
		end
		local r = math.random() * tot
		for _, x in ipairs(list) do
			r -= w[x] or 1
			if r <= 0 then
				return x
			end
		end
		return list[#list]
	end
	local idx = {}
	for i = 1, nRaw do
		idx[i] = i
	end
	local best = {}
	-- the curious pairs a knowledge file named come first, with a head start
	for _, cu in ipairs(self.curious) do
		local have = false
		for _, a in ipairs(self.acquired) do
			if a.i == cu.i and a.j == cu.j then
				have = true
			end
		end
		if not have then
			local bc = nil
			for _, op in ipairs(OPNAMES) do
				local f = OPS[op]
				local c, forWhat = corr(function(k)
					return f(rows[k].raw[cu.i], rows[k].raw[cu.j])
				end)
				if c > 0.15 and c > own[cu.i] + 0.03 and c > own[cu.j] + 0.03 and (not bc or c > bc.c - 0.1) then
					bc = { c = c + 0.1, op = op, i = cu.i, j = cu.j, forReading = forWhat }
				end
			end
			if bc then
				table.insert(best, bc)
			end
		end
	end
	for _ = 1, self.acqBudget do
		local i, j = weighted(idx, self.sensePrior), weighted(idx, self.sensePrior)
		if i ~= j and (i <= self.nIn or j <= self.nIn) then
			local op = weighted(OPNAMES, self.opPrior)
			if not taken[i .. "," .. j .. op] then
				local f = OPS[op]
				local c, forWhat = corr(function(k)
					return f(rows[k].raw[i], rows[k].raw[j])
				end)
				if c > 0.2 and c > own[i] + 0.05 and c > own[j] + 0.05 then
					table.insert(best, { c = c, op = op, i = i, j = j, forReading = forWhat })
				end
			end
		end
	end
	table.sort(best, function(a, b)
		return a.c > b.c
	end)
	local added = 0
	for _, b in ipairs(best) do
		if #self.acquired >= self.acqMax or added >= 2 then
			break
		end
		local dup = false
		for _, a in ipairs(self.acquired) do
			if a.i == b.i and a.j == b.j and a.op == b.op then
				dup = true
				break
			end
		end
		if not dup then
			b.at = self.stats.kept
			b.forReading = b.forReading or "value"
			table.insert(self.acquired, b)
			RLS.grow(self.O, self.extraRidge)
			self.opPrior[b.op] += b.c
			self.sensePrior[b.i] = (self.sensePrior[b.i] or 1) + b.c
			self.sensePrior[b.j] = (self.sensePrior[b.j] or 1) + b.c
			added += 1
		end
	end
	self.searches += 1
	self.sinceSearch, self.aboveFor = 0, 0
	self.acqTime += clock() - t0
end

-- ------------------------------------------------------------------ names

-- The index in phi of a named input: a sense, "choice=option", or an acquired "op(a,b)".
function Mind:featureIndex(name: string, names: { string }): number?
	for i, n in ipairs(names) do
		if n == name then
			if not self.pooledValue then
				return i + 1
			end
			-- under the pooled value the self readings keep their place and a slot sense is the raw copy of its
			-- field pooled by its slot's kind
			local q = table.find(self.poolSelf, i)
			if q then
				return q + 1
			end
			for g, B in ipairs(self.poolSlots) do
				local f = table.find(B, i)
				if f then
					local kind = math.min(g, self.poolKinds) - 1
					return 1 + self.nXO + self.nOpt + kind * #self.poolCopies * self.poolSize + f
				end
			end
			return nil
		end
	end
	local k = 1 + self.nXO
	for _, c in ipairs(self.choices) do
		for _, o in ipairs(c.options) do
			k += 1
			if name == c.name .. "=" .. o then
				return k
			end
		end
	end
	for q, a in ipairs(self.acquired) do
		if self:acquiredName(a, names) == name then
			return self.FO + q
		end
	end
	if self.descr then
		local base = 1 + self.nXO + self.nOpt + self.nPool
		local q = tonumber(name:match("^tag(%d+)$"))
		if q and q >= 1 and q <= self.descrDim then
			return base + q
		end
		local q2, sn = name:match("^tag(%d+)%*(.+)$")
		if q2 then
			q2 = tonumber(q2)
			for j, i in ipairs(self.descrSenses) do
				if names[i] == sn and q2 >= 1 and q2 <= self.descrDim then
					return base + self.descrDim + (q2 - 1) * #self.descrSenses + j
				end
			end
		end
	end
	return nil
end

-- The name of a descriptor feature ("tag5", "tag5*hostdist"), or nil if f is not one.
function Mind:descrFeatureName(f: number, names: { string }): string?
	if not self.descr then
		return nil
	end
	local base = 1 + self.nXO + self.nOpt + self.nPool
	if f > base and f <= base + self.descrDim then
		return "tag" .. (f - base)
	end
	local ds = self.descrSenses
	if f > base + self.descrDim and f <= base + self.descrDim * (1 + #ds) then
		local off = f - base - self.descrDim - 1
		local q, j = math.floor(off / #ds) + 1, (off % #ds) + 1
		return ("tag%d*%s"):format(q, names[ds[j]] or ("in" .. ds[j]))
	end
	return nil
end

function Mind:inputName(i: number, names: { string }): string
	if self.pooledValue then
		if i <= self.nXO then
			return names[self.poolSelf[i]]
		end
		local r = i - self.nXO - self.nOpt
		local size, nc = self.poolSize, #self.poolCopies
		if r >= 1 and r <= self.poolKinds * nc * size then
			-- a field pooled by kind: named after the first slot of that kind (its raw copy bare)
			local kind = (r - 1) // (nc * size)
			local c = ((r - 1) % (nc * size)) // size
			local f = (r - 1) % size + 1
			local n = names[self.poolSlots[kind + 1][f]]
			return if c == 0 then n else "copy" .. c .. ":" .. n
		end
	elseif i <= self.nIn then
		return names[i]
	end
	local k = self.nXO
	for _, c in ipairs(self.choices) do
		for _, o in ipairs(c.options) do
			k += 1
			if k == i then
				return c.name .. "=" .. o
			end
		end
	end
	return "in" .. i
end

function Mind:acquiredName(a, names: { string }): string
	return ("%s(%s,%s)"):format(a.op, self:inputName(a.i, names), self:inputName(a.j, names))
end

function Mind:acquiredNames(names: { string }): { string }
	local out = {}
	for _, a in ipairs(self.acquired) do
		table.insert(out, ("%s: %s %.2f"):format(a.forReading or "value", self:acquiredName(a, names), a.c or 0))
	end
	return out
end

-- ------------------------------------------------------------------ knowledge

-- KNOWLEDGE: { priors = { { reading = "dealt", feature = "act=strike", w = 15, conf = 50 } },
--              features = { { op = "mul", a = "hostdist", b = "hostclosing" } },
--              effects = { { option = "move=approach", sense = "itemdist", dw = -0.2, conf = 2 } },
--              curious = { { a = "hosthp", b = "act=strike" } },
--              memories = { { x = { itemthere = 1, itemdist = 0.1 }, picks = { 3, 2, 1 }, y = 20 } } }
-- A prior sets a weight and how sure of it the creature starts; a feature declares a pair worth
-- making; an effect says what an option does to a sense; a curious pair is searched first; a
-- memory matches only on the senses it names. All of it stays revisable: priors, not rules.
function Mind:learnFrom(k, names: { string })
	local O = self.O
	for _, pf in ipairs(k.features or {}) do
		local i, j = self:featureIndex(pf.a, names), self:featureIndex(pf.b, names)
		if i and j and OPS[pf.op] then
			table.insert(self.acquired, { op = pf.op, i = i - 1, j = j - 1, c = 0, forReading = "declared" })
			RLS.grow(O, self.extraRidge)
		end
	end
	for _, pr in ipairs(k.priors or {}) do
		local r = table.find(self.readings, pr.reading)
		local f = self:featureIndex(pr.feature, names)
		if r and f then
			RLS.prior(O, r, f, pr.w, pr.conf or 1)
			self.stats.priors = (self.stats.priors or 0) + 1
		end
	end
	for _, ep in ipairs(k.effects or {}) do
		local k2 = nil
		for ci, c in ipairs(self.choices) do
			for oo, o in ipairs(c.options) do
				if ep.option == c.name .. "=" .. o then
					k2 = self.optIndex[ci][oo]
				end
			end
		end
		local si = table.find(names, ep.sense)
		if k2 and si and self.E then
			local m = self.E[k2]
			m.W[si][1] = ep.dw
			m.P[1][1] = math.min(m.P[1][1], 1 / (ep.conf or 1))
			m.n = math.max(m.n, 30)
			m.var[si] = math.max(m.var[si], ep.dw * ep.dw)
			self.stats.effectPriors = (self.stats.effectPriors or 0) + 1
		end
	end
	for _, cu in ipairs(k.curious or {}) do
		local i, j = self:featureIndex(cu.a, names), self:featureIndex(cu.b, names)
		if i and j then
			table.insert(self.curious, { i = i - 1, j = j - 1, reading = cu.reading })
		end
	end
	if #self.curious > 0 then
		self.acqEarly = 1000 -- curious pairs are searched early, but not before there is anything to explain
	end
	for _, m in ipairs(k.memories or {}) do
		local x, mask = table.create(self.nIn, 0), table.create(self.nIn, 0)
		for sn, v in pairs(m.x) do
			local f = self:featureIndex(sn, names)
			if f and f - 1 <= self.nIn then
				x[f - 1] = v
				mask[f - 1] = 1
			end
		end
		storeMemory(self, x, m.picks, m.y, mask)
	end
end

-- The opposite: the largest weights, the acquired pairs and the best memories as a knowledge table,
-- for a spawn of the same kind. The whole covariance is not what makes a creature; this is.
function Mind:distill(names: { string }, top: number?, conf: number?, nMem: number?)
	top, conf, nMem = top or 40, conf or 50, nMem or 30
	local out = { priors = {}, features = {}, memories = {} }
	for _, a in ipairs(self.acquired) do
		table.insert(out.features, { op = a.op, a = self:inputName(a.i, names), b = self:inputName(a.j, names) })
	end
	local function nameOf(f: number): string?
		if f >= 2 and f <= 1 + self.nIn then
			return names[f - 1]
		end
		if f > 1 + self.nXO and f <= 1 + self.nXO + self.nOpt then
			return self:inputName(f - 1, names)
		end
		if f > self.FO and self.acquired[f - self.FO] then
			return self:acquiredName(self.acquired[f - self.FO], names)
		end
		return self:descrFeatureName(f, names)
	end
	for r = 1, self.NRO do
		if self.pref[r] ~= 0 then
			local ws = {}
			for f = 2, self.O.F do
				local nm = nameOf(f)
				if nm then
					table.insert(ws, { nm = nm, w = self.O.W[r][f] })
				end
			end
			table.sort(ws, function(a, b)
				return math.abs(a.w) > math.abs(b.w)
			end)
			for q = 1, math.min(top, #ws) do
				table.insert(out.priors, { reading = self.readings[r], feature = ws[q].nm, w = ws[q].w, conf = conf })
			end
		end
	end
	local mem = table.clone(self.MEM)
	table.sort(mem, function(a, b)
		return a.sum / a.n > b.sum / b.n
	end)
	for q = 1, math.min(nMem, #mem) do
		local e = mem[q]
		local x = {}
		for i = 1, self.nIn do
			x[names[i]] = e.x[i]
		end
		table.insert(out.memories, { x = x, picks = table.clone(e.picks), y = e.sum / e.n })
	end
	return out
end

-- ------------------------------------------------------------------ save and load

-- Everything the creature has learned, as plain data (the covariances as diagonals). A creature
-- reloaded from this is itself, a little less sure of its couplings.
function Mind:save()
	local out = {
		nIn = self.nIn,
		set = self.has,
		O = RLS.save(self.O),
		acquired = {},
		mem = {},
		opPrior = table.clone(self.opPrior),
		sensePrior = table.clone(self.sensePrior),
		descriptors = if self.descr then self.descriptors else nil,
	}
	for _, a in ipairs(self.acquired) do
		table.insert(out.acquired, { op = a.op, i = a.i, j = a.j, c = a.c, forReading = a.forReading })
	end
	for _, e in ipairs(self.MEM) do
		table.insert(out.mem, { x = table.clone(e.x), picks = table.clone(e.picks), y = e.y, n = e.n, sum = e.sum, mask = e.mask })
	end
	if self.has.E and not self.sharedE then
		if self.equivariant then
			out.EG, out.ES = {}, {}
			for k = 1, self.nOpt do
				out.EG[k] = RLS.save(self.EG[k])
				out.ES[k] = RLS.save(self.ES[k])
			end
		else
			out.E = {}
			for k = 1, self.nOpt do
				out.E[k] = RLS.save(self.E[k])
			end
		end
	end
	if self.has.C then
		if self.equivariant then
			out.CG, out.CS = RLS.save(self.CG), RLS.save(self.CS)
		else
			out.Cm = RLS.save(self.Cm)
		end
	end
	if self.has.H then
		out.Hm = RLS.save(self.Hm)
	end
	return out
end

function Mind:load(saved)
	if saved.nIn ~= self.nIn then
		error("[instinct] a saved mind with a different number of senses", 0)
	end
	self.acquired = {}
	for _, a in ipairs(saved.acquired or {}) do
		table.insert(self.acquired, { op = a.op, i = a.i, j = a.j, c = a.c, forReading = a.forReading })
	end
	local blocks = self.O.blocks
	self.O = RLS.load(saved.O, self.valueRidge)
	if blocks then
		-- the acquired inputs' block must cover whatever was loaded
		local last = blocks[#blocks]
		table.clear(last)
		for q = 1, #self.acquired do
			table.insert(last, self.FO + q)
		end
		self.O.blocks = blocks
	end
	self.MEM, self.FLAT = {}, {}
	for _, e in ipairs(saved.mem or {}) do
		storeMemory(self, e.x, e.picks, e.y, e.mask)
		local last = self.MEM[#self.MEM]
		last.n, last.sum = e.n, e.sum
	end
	if saved.opPrior then
		self.opPrior = table.clone(saved.opPrior)
	end
	if saved.sensePrior then
		self.sensePrior = table.clone(saved.sensePrior)
	end
	if saved.descriptors and self.descr then
		for k, d in pairs(saved.descriptors) do
			if self.descriptors[k] then
				self.descriptors[k] = table.clone(d)
			end
		end
	end
	if saved.E and self.has.E and not self.sharedE and not self.equivariant then
		for k = 1, self.nOpt do
			self.E[k] = RLS.load(saved.E[k], self.ridge)
		end
	end
	if saved.EG and self.equivariant then
		for k = 1, self.nOpt do
			self.EG[k] = RLS.load(saved.EG[k], self.ridge)
			self.ES[k] = RLS.load(saved.ES[k], self.ridge)
		end
	end
	if saved.Cm and self.has.C and not self.equivariant then
		self.Cm = RLS.load(saved.Cm, self.ridge)
	end
	if saved.CG and self.equivariant then
		self.CG, self.CS = RLS.load(saved.CG, self.ridge), RLS.load(saved.CS, self.ridge)
	end
	if saved.Hm and self.has.H then
		self.Hm = RLS.load(saved.Hm, self.ridge)
	end
	self.pending, self.pendingE = {}, {}
end

-- The effects models are the physics of the world, and every creature of a kind lives in the same
-- one; sharing them is the largest saving in memory and the fastest learning of what acts do.
function Mind:shareEffects(E, EG, ES)
	if self.equivariant then
		self.EG, self.ES = EG, ES
	else
		self.E = E
	end
	self.sharedE = true
end

function Mind:microsecondsAThink(): number
	return self.thinkTime * 1e6 / math.max(1, self.stats.thinks)
end

return Mind
