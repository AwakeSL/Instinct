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

-- One row: inputs phi, outputs y. Every output shares the gain, so the covariance is updated once.
function RLS.update(m: Model, phi: { number }, y: { number })
	local F, P = m.F, m.P
	local Pphi = table.create(F, 0)
	local denom = 1
	for i = 1, F do
		local s = 0
		local Pi = P[i]
		for j = 1, F do
			s += Pi[j] * phi[j]
		end
		Pphi[i] = s
		denom += phi[i] * s
	end
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
		for i = 1, F do
			e -= w[i] * phi[i]
		end
		m.mean[r] = 0.99 * m.mean[r] + 0.01 * target
		m.err[r] = 0.99 * m.err[r] + 0.01 * e * e
		m.var[r] = 0.99 * m.var[r] + 0.01 * (target - m.mean[r]) ^ 2
		local g = e / denom
		for i = 1, F do
			w[i] += Pphi[i] * g
		end
	end
	for i = 1, F do
		local Pi = P[i]
		local ki = Pphi[i] / denom
		for j = 1, F do
			Pi[j] -= ki * Pphi[j]
		end
	end
	m.n += 1
end

function RLS.predict(m: Model, r: number, phi: { number }): number
	local w = m.W[r]
	local v = 0
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
