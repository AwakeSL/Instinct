--!nonstrict
-- Where a settle's time goes, by model: wraps RLS.update and times each model kind.
--     lune run scripts/prof_settle [slots]   env: EQUIV=1 POOL=1 (flat), CODE=16 (code)
local process = require("@lune/process")
local Instinct = require("../src")
local Mind, Senses, RLS = Instinct.Mind, Instinct.Senses, Instinct.RLS

local NSLOTS = tonumber(process.args[1]) or 3
local SLOTS = {}
for k = 1, NSLOTS do
	SLOTS[k] = "slot" .. k
end
local NAMES = Senses.layout(SLOTS, { "timeLeft", "armed" })
local CHOICES = {
	{ name = "target", options = { "keep", "hostile", "item", "ally" } },
	{ name = "move", options = { "hold", "approach", "retreat", "orbit", "centre" } },
	{ name = "act", options = { "none", "strike" } },
}
local m = Mind.new(#NAMES, CHOICES, {
	set = "OMECA",
	readings = { "dealt", "taken", "eaten" },
	pref = { dealt = 1, taken = -1, eaten = 20 },
	groups = Senses.groups(SLOTS, { "timeLeft", "armed" }),
	equivariant = process.env.EQUIV == "1",
	pooledValue = process.env.POOL == "1",
	code = tonumber(process.env.CODE),
	effectsInputs = process.env.EFFIN,
	poolRaw = process.env.POOLRAW == "1",
	beam = tonumber(process.env.BEAM) or 9,
})
-- tag the models
local tags = {}
local function tag(model, name)
	if model then
		tags[model] = name
	end
end
tag(m.O, "outcome")
tag(m.Cm, "couplings")
tag(m.CG, "couplings")
tag(m.CS, "couplings")
for _, e in pairs(m.E or {}) do tag(e, "effects") end
for _, e in pairs(m.EG or {}) do tag(e, "effects") end
for _, e in pairs(m.ES or {}) do tag(e, "effects") end
local spent, calls = {}, {}
-- THINK=1: time the think's parts too
local thinkSpent = {}
if process.env.THINK == "1" then
	for _, name in { "extend", "scoreCombos", "stepAhead", "worth", "encode", "phiO" } do
		local f = Mind[name]
		Mind[name] = function(...)
			local t0 = os.clock()
			local a, b, c = f(...)
			thinkSpent[name] = (thinkSpent[name] or 0) + (os.clock() - t0)
			return a, b, c
		end
	end
end
local orig = RLS.update
RLS.update = function(model, ...)
	local t0 = os.clock()
	orig(model, ...)
	local name = tags[model] or "other"
	spent[name] = (spent[name] or 0) + (os.clock() - t0)
	calls[name] = (calls[name] or 0) + 1
end
math.randomseed(1)
local present = math.max(1, math.floor(NSLOTS / 2))
local function senses()
	local x = {}
	for i = 1, #NAMES do
		x[i] = math.random()
	end
	local nSelf = #NAMES - 7 * NSLOTS
	for k = present + 1, NSLOTS do
		for q = 1, 7 do
			x[nSelf + (k - 1) * 7 + q] = 0
		end
	end
	return x
end
local x = senses()
local eaten, settleTime, thinkTime = 0, 0, 0
local N = 600
for t = 1, N + 200 do
	local t0 = os.clock()
	local picks, xr, phi, event = m:think(function()
		return x
	end)
	if t > 200 then
		thinkTime += os.clock() - t0
	end
	m:note(xr, phi, picks, event, { 0, 0, eaten }, t)
	x = senses()
	if math.random() < 0.1 then
		eaten += 1
	end
	if t == 200 then
		spent, calls = {}, {}
		thinkSpent = {}
	end
	t0 = os.clock()
	m:settle({ 0, 0, eaten }, x, t, false)
	if t > 200 then
		settleTime += os.clock() - t0
	end
end
local parts = {}
local inUpdates = 0
for name, s in pairs(spent) do
	table.insert(parts, ("%s %.0f us (%.1f updates a settle)"):format(name, s / N * 1e6, calls[name] / N))
	inUpdates += s
end
table.sort(parts)
if process.env.THINK == "1" then
	local tp = {}
	for name, v in pairs(thinkSpent) do
		table.insert(tp, ("%s %.0f"):format(name, v / N * 1e6))
	end
	table.sort(tp)
	print("think parts (us, nested): " .. table.concat(tp, ", "))
end
print(("%d senses (%d slots, %d present), outcome F %d: think %.0f us, settle %.0f us of which RLS updates %.0f us: %s"):format(
	#NAMES, NSLOTS, present, m.O.F, thinkTime / N * 1e6, settleTime / N * 1e6, inUpdates / N * 1e6, table.concat(parts, "; ")))
