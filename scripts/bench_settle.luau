--!nonstrict
-- How long a settle (learning) takes as the creature widens: slots of seven senses each.
--     lune run scripts/bench_settle [slots]   env: EQUIV=1 POOL=1 for the flat mind
local process = require("@lune/process")
local Instinct = require("../src")
local Mind, Senses = Instinct.Mind, Instinct.Senses

local NSLOTS = tonumber(process.args[1]) or 4
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
	beam = 9,
})
math.randomseed(1)
local present = math.max(1, math.floor(NSLOTS / 4)) -- a quarter of the slots filled, as in a crowd seen from one place
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
local function sensesOf()
	return x
end
local eaten, settleTime = 0, 0
for t = 1, 700 do
	local picks, xr, phi, event = m:think(sensesOf)
	m:note(xr, phi, picks, event, { 0, 0, eaten }, t)
	x = senses()
	if math.random() < 0.1 then
		eaten += 1
	end
	local t0 = os.clock()
	m:settle({ 0, 0, eaten }, x, t, false)
	if t > 200 then
		settleTime += os.clock() - t0
	end
end
print(("%d senses (%d slots, %d present): settle %.0f us, think %.0f us"):format(#NAMES, NSLOTS, present, settleTime / 500 * 1e6, m.thinkTime / m.stats.thinks * 1e6))
