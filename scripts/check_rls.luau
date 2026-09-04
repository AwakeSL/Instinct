--!nonstrict
-- Checks RLS.update against the plain textbook update (dense matvec, full downdate, one row at a time):
-- the zero-skipping, the mirrored downdate and the closed-form repeated row must agree to rounding.
local RLS = require("../src/RLS")

local F, NR = 40, 3
local function plain(m, phi, y)
	local P = m.P
	local Pphi, denom = {}, 1
	for i = 1, F do
		local s = 0
		for j = 1, F do
			s += P[i][j] * phi[j]
		end
		Pphi[i] = s
		denom += phi[i] * s
	end
	for r = 1, NR do
		local w, e = m.W[r], y[r]
		for i = 1, F do
			e -= w[i] * phi[i]
		end
		local g = e / denom
		for i = 1, F do
			w[i] += Pphi[i] * g
		end
	end
	for i = 1, F do
		for j = 1, F do
			P[i][j] -= Pphi[i] * Pphi[j] / denom
		end
	end
end
math.randomseed(3)
local a, b = RLS.new(F, NR, 1), RLS.new(F, NR, 1)
local maxW, maxP = 0, 0
for t = 1, 400 do
	local phi, y = { 1 }, {}
	for i = 2, F do
		phi[i] = if math.random() < 0.6 then 0 else math.random() * 2 - 1 -- most inputs zero, as absent slots read
	end
	for r = 1, NR do
		y[r] = math.random() * 2 - 1
	end
	local reps = if t % 7 == 0 then 3 else 1
	for _ = 1, reps do
		plain(a, phi, y)
	end
	RLS.update(b, phi, y, reps)
	for r = 1, NR do
		for i = 1, F do
			maxW = math.max(maxW, math.abs(a.W[r][i] - b.W[r][i]))
		end
	end
	for i = 1, F do
		for j = 1, F do
			maxP = math.max(maxP, math.abs(a.P[i][j] - b.P[i][j]))
		end
	end
end
print(("RLS.update against the plain update over 400 rows (57 of them counted three times): max weight difference %.3g, max covariance difference %.3g"):format(maxW, maxP))
