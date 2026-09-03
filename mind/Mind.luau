--!nonstrict
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
	self.ridge = o.ridge or 1
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
	self.nExtra = (if self.has.C then nIn else 0) + self.nHaz + self.nTrace
	self.nX = nIn + self.nExtra
	self.FO = 1 + self.nX + nOpt
	self.O = RLS.new(self.FO, self.NRO, self.ridge)
	for i = 1 + nIn + 1, 1 + self.nX do
		self.O.P[i][i] = 1 / self.extraRidge
	end
	if self.has.E then
		self.E = {}
		for k = 1, nOpt do
			self.E[k] = RLS.new(1 + self.nX, nIn, self.ridge)
		end
	end
	if self.has.H then
		self.Hm = RLS.new(1 + nIn, self.nHaz, self.ridge)
		self.eventLog = {}
	end
	if self.has.C then
		self.Cm = RLS.new(1 + nIn, nIn, self.ridge)
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
	local k = 0
	for ci, c in ipairs(choices) do
		self.optIndex[ci] = {}
		for oo = 1, #c.options do
			k += 1
			self.optIndex[ci][oo] = k
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
		local dphi = { 1 }
		local ld = self.lastDx
		for i = 1, n do
			dphi[i + 1] = if ld then ld[i] else 0
		end
		for i = 1, n do
			k += 1
			local c = RLS.confidence(self.Cm, i)
			X[k] = if ld and c > 0 then c * RLS.predict(self.Cm, i, dphi) else 0
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
	for i = 1, self.nX do
		phi[i + 1] = X[i]
	end
	local k = self.nX + 1
	for ci, c in ipairs(self.choices) do
		for oo = 1, #c.options do
			k += 1
			phi[k] = if picks[ci] == oo then 1 else 0
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
function Mind:stepAhead(X: { number }, picks: { number }, out: { number }?): ({ number }, number)
	local nxt = out or {}
	for i = 1, self.nIn do
		nxt[i] = X[i]
	end
	local phi = self:phiE(X)
	local total, count = 0, 0
	for ci = 1, #self.choices do
		local m = self.E[self.optIndex[ci][picks[ci]]]
		if m.n > 0 then
			for i = 1, self.nIn do
				local c = RLS.confidence(m, i)
				if c > 0 then
					nxt[i] += c * RLS.predict(m, i, phi)
				end
				total += c
				count += 1
			end
		end
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
	for _, p in ipairs(self.combos) do
		if not feasible or feasible(p) then
			table.insert(scored, { p = p, v = self:worth(Xs[p[1]], p, phi) })
		end
	end
	if #scored == 0 then
		return finish(table.clone(self.combos[1]), nil)
	end
	-- second step: the best BEAM extended by their projected next senses, held
	if self.has.E then
		table.sort(scored, function(a, b)
			return a.v > b.v
		end)
		local nxt = {}
		for k = 1, math.min(self.beam, #scored) do
			local s = scored[k]
			local _, conf = self:stepAhead(Xs[s.p[1]], s.p, nxt)
			local X2 = self:extend(nxt)
			s.v += self.gamma * conf * self:worth(X2, s.p, phi, true)
		end
	end
	if self.eps > 0 and self.exploring and math.random() < self.eps then
		-- a random combination, held for a while: re-rolling every tick cancels out into a jitter that
		-- goes nowhere, and teaches the effects models nothing about what holding a move does
		local p = self.stickyPicks
		if p == nil or math.random() >= self.sticky or (feasible and not feasible(p)) then
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
	local nRaw = self.nX + self.nOpt
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
			if self.lastDx then
				local dphi = { 1 }
				for i = 1, self.nIn do
					dphi[i + 1] = self.lastDx[i]
				end
				RLS.update(self.Cm, dphi, dx)
			end
			self.lastDx = dx
		end
		self.lastX = xNow
	end
	-- effects: rows one STEP old
	if self.has.E then
		local keep = {}
		for _, r in ipairs(self.pendingE) do
			if tick - r.at >= self.STEP or over then
				local phi = self:phiE(r.X)
				local dy = {}
				for i = 1, self.nIn do
					dy[i] = xNow[i] - r.X[i]
				end
				for ci = 1, #self.choices do
					RLS.update(self.E[self.optIndex[ci][r.picks[ci]]], phi, dy)
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
			for _ = 1, reps do
				RLS.update(self.O, r.phi, y)
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
	self.O = RLS.new(F, NR, self.ridge)
	for i = 1 + self.nIn + 1, 1 + self.nX do
		self.O.P[i][i] = 1 / self.extraRidge
	end
	for q = 1, #self.acquired do
		self.O.P[self.FO + q][self.FO + q] = 1 / self.extraRidge
	end
	self.pending = {}
	self.stats.rebirths += 1
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
	local nRaw = self.nX + self.nOpt
	-- the residuals to chase: the value's, and the worst reading's
	local targets = { { name = "value", res = {} } }
	if self.acqReading then
		table.insert(targets, { name = self.readings[self.acqReading], q = self.acqReading, res = {} })
	end
	local phi, Xr, pk = {}, {}, {}
	for k, r in ipairs(rows) do
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
			return i + 1
		end
	end
	local k = 1 + self.nX
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
	return nil
end

function Mind:inputName(i: number, names: { string }): string
	if i <= self.nIn then
		return names[i]
	end
	local k = self.nX
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
		self.acqEarly = 200
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
		if f > 1 + self.nX and f <= self.FO then
			return self:inputName(f - 1, names)
		end
		if f > self.FO and self.acquired[f - self.FO] then
			return self:acquiredName(self.acquired[f - self.FO], names)
		end
		return nil
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
	}
	for _, a in ipairs(self.acquired) do
		table.insert(out.acquired, { op = a.op, i = a.i, j = a.j, c = a.c, forReading = a.forReading })
	end
	for _, e in ipairs(self.MEM) do
		table.insert(out.mem, { x = table.clone(e.x), picks = table.clone(e.picks), y = e.y, n = e.n, sum = e.sum, mask = e.mask })
	end
	if self.has.E and not self.sharedE then
		out.E = {}
		for k = 1, self.nOpt do
			out.E[k] = RLS.save(self.E[k])
		end
	end
	if self.has.C then
		out.Cm = RLS.save(self.Cm)
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
	self.O = RLS.load(saved.O, self.ridge)
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
	if saved.E and self.has.E and not self.sharedE then
		for k = 1, self.nOpt do
			self.E[k] = RLS.load(saved.E[k], self.ridge)
		end
	end
	if saved.Cm and self.has.C then
		self.Cm = RLS.load(saved.Cm, self.ridge)
	end
	if saved.Hm and self.has.H then
		self.Hm = RLS.load(saved.Hm, self.ridge)
	end
	self.pending, self.pendingE = {}, {}
end

-- The effects models are the physics of the world, and every creature of a kind lives in the same
-- one; sharing them is the largest saving in memory and the fastest learning of what acts do.
function Mind:shareEffects(E)
	self.E = E
	self.sharedE = true
end

function Mind:microsecondsAThink(): number
	return self.thinkTime * 1e6 / math.max(1, self.stats.thinks)
end

return Mind
