--!nonstrict
-- How long a think takes as the act set grows, with and without the separable pick search.
--     lune run scripts/bench_think [acts]   env: EQUIV=1 POOL=1 for the flat mind
local process = require("@lune/process")
local Instinct = require("../mind")
local Mind, Senses = Instinct.Mind, Instinct.Senses

local ACTS = tonumber(process.args[1]) or 200
local SLOTS = { "host", "item", "haz", "ally" }
local NAMES = Senses.layout(SLOTS, { "timeLeft", "armed" })
local acts = { "none" }
for k = 1, ACTS - 1 do
	table.insert(acts, "act" .. k)
end
local CHOICES = {
	{ name = "target", options = { "keep", "hostile", "item", "ally" } },
	{ name = "move", options = { "hold", "approach", "retreat", "orbit", "centre" } },
	{ name = "act", options = acts },
}
local flat = process.env.EQUIV == "1"
-- DESCR=1: every act carries a random descriptor of six numbers (tags), read against the senses
local descriptors, descrDim = nil, 0
if process.env.DESCR == "1" then
	descriptors, descrDim = {}, 6
	local k = 0
	for ci, c in ipairs(CHOICES) do
		for oo = 1, #c.options do
			k += 1
			if ci == 3 then
				local d = {}
				for q = 1, 6 do
					d[q] = math.random() * 2 - 1
				end
				descriptors[k] = d
			end
		end
	end
end
local function build(separable)
	local m = Mind.new(#NAMES, CHOICES, {
		descriptors = descriptors,
		descrDim = descrDim,
		descrLearn = 0.05,
		set = "OMECA",
		readings = { "dealt", "taken", "eaten" },
		pref = { dealt = 1, taken = -1, eaten = 20 },
		groups = Senses.groups(SLOTS, { "timeLeft", "armed" }),
		equivariant = flat,
		pooledValue = process.env.POOL == "1",
		separable = separable,
		beam = 9,
	})
	return m
end
math.randomseed(1)
local function senses()
	local x = {}
	for i = 1, #NAMES do
		x[i] = math.random()
	end
	return x
end
local function run(separable)
	local m = build(separable)
	local x = senses()
	local function sensesOf()
		return x
	end
	-- settle a few hundred rows so the models carry weights and the effects gate opens
	local eaten = 0
	for t = 1, 400 do
		local picks, xr, phi, event = m:think(sensesOf)
		m:note(xr, phi, picks, event, { 0, 0, eaten }, t)
		x = senses()
		if math.random() < 0.1 then
			eaten += 1
		end
		m:settle({ 0, 0, eaten }, x, t, false)
	end
	m.stats.thinks, m.thinkTime = 0, 0
	local t0 = os.clock()
	for t = 1, 200 do
		m:think(sensesOf)
		x = senses()
	end
	return (os.clock() - t0) / 200 * 1e6
end
if process.env.CHECK == "1" then
	-- the separable scoring against the full one, on a mind with descriptors and acquired features
	local m = build(true)
	local orig = Mind.scoreCombos
	local maxErr, n = 0, 0
	m.scoreCombos = function(self, Xs, feasible, scored)
		orig(self, Xs, feasible, scored)
		local phi = {}
		for _, sc in ipairs(scored) do
			maxErr = math.max(maxErr, math.abs(self:worth(Xs[sc.p[1]], sc.p, phi) - sc.v))
			n += 1
		end
	end
	local x = senses()
	local eaten = 0
	for t = 1, 600 do
		local picks, xr, phi, event = m:think(function()
			return x
		end)
		m:note(xr, phi, picks, event, { 0, 0, eaten }, t)
		x = senses()
		if math.random() < 0.1 then
			eaten += 1
		end
		m:settle({ 0, 0, eaten }, x, t, false)
	end
	print(("CHECK: %d combinations, %d acquired, descriptor inputs %d, max error %.3g"):format(n, #m.acquired, #m.descrInputs, maxErr))
	return
end
local full, sep = run(false), run(true)
print(("%d acts x 20 = %d combinations: think %.0f us full, %.0f us separable (%.1fx)"):format(ACTS, ACTS * 20, full, sep, full / sep))
