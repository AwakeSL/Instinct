--!strict
--!native
-- Recursive least squares, one shared inverse-covariance per model and any number of outputs.
--
-- A model is a table: F inputs (the first is the constant 1), NR outputs, W[r][i] the weights,
-- P[i][j] the covariance, and per output a decayed mean, variance and squared error that say how
-- much of that output the model explains. Everything the creature knows is one of these.

local RLS = {}

export type Model = {
	F: number,
	NR: number,
	n: number,
	W: { { number } },
	P: { { number } },
	err: { number },
	var: { number },
	mean: { number },
	-- block-local: index lists partitioning 1..F, the covariance kept within a block only; and per output,
	-- the inputs it reads. Cost per row becomes the sum of block sizes squared plus the outputs' input counts.
	blocks: { { number } }?,
	ins: { { number } }?,
	-- absent: per input, true when it belongs to a slot that is absent this row (set by the mind before each
	-- update). Absent inputs are skipped: their weights do not move and their cross-covariance with what is
	-- present is not updated. Full covariance among what is present together, at the cost of its square.
	-- Note this is by slot, never by value: a flag that reads zero is a value, and skipping it breaks learning.
	absent: { boolean }?,
}

function RLS.new(F: number, NR: number, ridge: number): Model
	local P = table.create(F)
	for i = 1, F do
		local row = table.create(F, 0)
		row[i] = 1 / ridge
		P[i] = row
	end
	local W = table.create(NR)
	for r = 1, NR do
		W[r] = table.create(F, 0)
	end
	return {
		F = F,
		NR = NR,
		n = 0,
		W = W,
		P = P,
		err = table.create(NR, 0),
		var = table.create(NR, 0),
		mean = table.create(NR, 0),
	}
end

-- The share of an output the model explains, 0..1. A model with fewer than 30 rows has earned
-- nothing, whatever its bookkeeping says.
function RLS.confidence(m: Model, r: number): number
	if m.n < 30 then
		return 0
	end
	local v = m.var[r]
	if v < 1e-9 then
		return 0
	end
	local c = 1 - m.err[r] / v
	return if c > 0 then c else 0
end

local function updateBlocks(m: Model, phi: { number }, y: { number })
	local P, blocks = m.P, m.blocks :: { { number } }
	local Pphi = table.create(m.F, 0)
	local denom = 1
	for _, B in blocks do
		for _, i in B do
			local s = 0
			local Pi = P[i]
			for _, j in B do
				s += Pi[j] * phi[j]
			end
			Pphi[i] = s
			denom += phi[i] * s
		end
	end
	if not (denom > 1e-9) then
		return
	end
	local ins = m.ins
	for r = 1, m.NR do
		local w = m.W[r]
		local target = y[r]
		if target ~= target then
			continue
		end
		local e = target
		local I = if ins then ins[r] else nil
		if I then
			for _, i in I do
				e -= w[i] * phi[i]
			end
		else
			for i = 1, m.F do
				e -= w[i] * phi[i]
			end
		end
		m.mean[r] = 0.99 * m.mean[r] + 0.01 * target
		m.err[r] = 0.99 * m.err[r] + 0.01 * e * e
		m.var[r] = 0.99 * m.var[r] + 0.01 * (target - m.mean[r]) ^ 2
		local g = e / denom
		if I then
			for _, i in I do
				w[i] += Pphi[i] * g
			end
		else
			for i = 1, m.F do
				w[i] += Pphi[i] * g
			end
		end
	end
	for _, B in blocks do
		for _, i in B do
			local Pi = P[i]
			local ki = Pphi[i] / denom
			for _, j in B do
				Pi[j] -= ki * Pphi[j]
			end
		end
	end
	m.n += 1
end

local function updateSparse(m: Model, phi: { number }, y: { number }, absent: { boolean })
	local F, P = m.F, m.P
	local act = {}
	for i = 1, F do
		if not absent[i] then
			table.insert(act, i)
		end
	end
	local Pphi = table.create(F, 0)
	local denom = 1
	for _, i in act do
		local s = 0
		local Pi = P[i]
		for _, j in act do
			s += Pi[j] * phi[j]
		end
		Pphi[i] = s
		denom += phi[i] * s
	end
	if not (denom > 1e-9) then
		return
	end
	for r = 1, m.NR do
		local w = m.W[r]
		local target = y[r]
		if target ~= target then
			continue
		end
		local e = target
		for _, i in act do
			e -= w[i] * phi[i]
		end
		m.mean[r] = 0.99 * m.mean[r] + 0.01 * target
		m.err[r] = 0.99 * m.err[r] + 0.01 * e * e
		m.var[r] = 0.99 * m.var[r] + 0.01 * (target - m.mean[r]) ^ 2
		local g = e / denom
		for _, i in act do
			w[i] += Pphi[i] * g
		end
	end
	for _, i in act do
		local Pi = P[i]
		local ki = Pphi[i] / denom
		for _, j in act do
			Pi[j] -= ki * Pphi[j]
		end
	end
	m.n += 1
end

-- One row: inputs phi, outputs y. Every output shares the gain, so the covariance is updated once.
-- One row of evidence. `reps` counts the row that many times, in closed form (k identical updates are one
-- update with denominator 1 + k phi'P phi and gain k P phi / that: the same weights and covariance).
function RLS.update(m: Model, phi: { number }, y: { number }, reps: number?)
	if m.blocks then
		updateBlocks(m, phi, y)
		return
	end
	if m.absent then
		updateSparse(m, phi, y, m.absent)
		return
	end
	local F, P = m.F, m.P
	local k = reps or 1
	local Pphi = table.create(F, 0)
	-- the inputs that are not zero: absent slots and unpicked options read zero, and a zero term is skipped
	-- exactly (the index list pays only when a fair share of the inputs are zero)
	local nz, nnz = nil, 0
	for j = 1, F do
		if phi[j] ~= 0 then
			nnz += 1
		end
	end
	if nnz * 4 < F * 3 then
		nz = table.create(nnz)
		for j = 1, F do
			if phi[j] ~= 0 then
				table.insert(nz, j)
			end
		end
	end
	local quad = 0
	for i = 1, F do
		local s = 0
		local Pi = P[i]
		if nz then
			for _, j in nz do
				s += Pi[j] * phi[j]
			end
		else
			for j = 1, F do
				s += Pi[j] * phi[j]
			end
		end
		Pphi[i] = s
		quad += phi[i] * s
	end
	local denom = 1 + k * quad
	if not (denom > 1e-9) then
		return -- a covariance gone bad: skip the row rather than poison the weights
	end
	for r = 1, m.NR do
		local w = m.W[r]
		local target = y[r]
		if target ~= target then
			continue -- a NaN can never be washed out by later evidence
		end
		local e = target
		if nz then
			for _, i in nz do
				e -= w[i] * phi[i]
			end
		else
			for i = 1, F do
				e -= w[i] * phi[i]
			end
		end
		for _ = 1, k do
			m.mean[r] = 0.99 * m.mean[r] + 0.01 * target
			m.err[r] = 0.99 * m.err[r] + 0.01 * e * e
			m.var[r] = 0.99 * m.var[r] + 0.01 * (target - m.mean[r]) ^ 2
		end
		local g = k * e / denom
		for i = 1, F do
			w[i] += Pphi[i] * g
		end
	end
	-- the covariance is symmetric, so the downdate is done once an entry pair and mirrored
	for i = 1, F do
		local Pi = P[i]
		local ki = k * Pphi[i] / denom
		Pi[i] -= ki * Pphi[i]
		for j = i + 1, F do
			local v = Pi[j] - ki * Pphi[j]
			Pi[j] = v
			P[j][i] = v
		end
	end
	m.n += k
end

function RLS.predict(m: Model, r: number, phi: { number }): number
	local w = m.W[r]
	local v = 0
	local ins = m.ins
	if ins then
		for _, i in ins[r] do
			v += w[i] * phi[i]
		end
		return v
	end
	for i = 1, m.F do
		v += w[i] * phi[i]
	end
	return v
end

-- sqrt(phi' diag(P) phi): how unsure the model is of a prediction on these inputs, diagonal only.
function RLS.spread(m: Model, phi: { number }): number
	local s = 0
	for i = 1, m.F do
		s += phi[i] * phi[i] * m.P[i][i]
	end
	return math.sqrt(math.max(0, s))
end

-- One more input, with a tight prior so it has to earn its place.
function RLS.grow(m: Model, tight: number)
	local F = m.F + 1
	for i = 1, F - 1 do
		m.P[i][F] = 0
	end
	local row = table.create(F, 0)
	row[F] = 1 / tight
	m.P[F] = row
	for r = 1, m.NR do
		m.W[r][F] = 0
	end
	m.F = F
	if m.blocks then
		local last = m.blocks[#m.blocks]
		table.insert(last, F)
	end
end

-- Set one input's weight for one output and its confidence (the covariance is 1/conf, uncoupled).
function RLS.prior(m: Model, r: number, f: number, w: number, conf: number)
	m.W[r][f] = w
	for j = 1, m.F do
		m.P[f][j] = 0
		m.P[j][f] = 0
	end
	m.P[f][f] = 1 / conf
end

-- The model as plain data for saving: weights, and only the covariance diagonal. A reloaded creature
-- is a little less sure of the couplings between its inputs, which costs it about a tenth, and the
-- whole covariance is F squared numbers that do not deserve a save slot.
function RLS.save(m: Model): any
	local diag = table.create(m.F)
	for i = 1, m.F do
		diag[i] = m.P[i][i]
	end
	local W = table.create(m.NR)
	for r = 1, m.NR do
		W[r] = table.clone(m.W[r])
	end
	return { F = m.F, NR = m.NR, n = m.n, W = W, diag = diag, err = table.clone(m.err), var = table.clone(m.var), mean = table.clone(m.mean) }
end

function RLS.load(saved: any, ridge: number): Model
	local m = RLS.new(saved.F, saved.NR, ridge)
	m.n = saved.n
	for r = 1, m.NR do
		for i = 1, m.F do
			m.W[r][i] = saved.W[r][i]
		end
		m.err[r] = saved.err[r]
		m.var[r] = saved.var[r]
		m.mean[r] = saved.mean[r]
	end
	for i = 1, m.F do
		m.P[i][i] = saved.diag[i]
	end
	return m
end

return RLS
