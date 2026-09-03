--!nonstrict
-- Stage-by-stage probe of the learned mind under Lune, to find what stalls.
local Vector3 = require("@lune/roblox").Vector3
local t0 = os.clock()
local function stage(name: string)
	print(("[%6.2fs] %s"):format(os.clock() - t0, name))
end
stage("start; Vector3 is " .. tostring(Vector3))
local Instinct = require("../mind")
stage("required mind")
local Mind, Senses, Coach = Instinct.Mind, Instinct.Senses, Instinct.Coach
local SLOTS = { "host", "item", "haz", "ally" }
local NAMES = Senses.layout(SLOTS, { "timeLeft", "armed" })
stage(("layout: %d names"):format(#NAMES))
local CHOICES = {
	{ name = "target", options = { "keep", "hostile", "item", "ally" } },
	{ name = "move", options = { "hold", "approach", "retreat", "orbit", "centre" } },
	{ name = "aim", options = { "none", "face" } },
	{ name = "act", options = { "none", "strike" } },
}
local mind = Mind.new(#NAMES, CHOICES, { set = "OMECA", readings = { "dealt", "taken", "eaten" }, pref = { dealt = 1, taken = -1, eaten = 20 } })
stage(("mind: %d combos, FO %d"):format(#mind.combos, mind.FO))
local me = { position = Vector3.zero, heading = 0.3, velocity = Vector3.zero, hp = 1, speed = 0.5 }
local ents = { item = { position = Vector3.new(5, 0, 3), hp = 1, extra = 1 } }
local x = Senses.encode(me, SLOTS, ents, { 1, 0 }, 40)
stage(("encode: %d senses, item dist %.3f bearing %.3f"):format(#x, x[9 + 7 + 2], x[9 + 7 + 3]))
local feasible = function(p) return p[1] ~= 2 and p[1] ~= 4 and p[4] == 1 end
local picks, xr, phi, ev = mind:think(function() return x end, feasible)
stage(("think: picks %d %d %d %d, phi %d"):format(picks[1], picks[2], picks[3], picks[4], #phi))
for tick = 1, 40 do
	mind:note(xr, phi, picks, ev, { 0, 0, 0 }, tick)
	mind:settle({ 0, 0, tick > 30 and 1 or 0 }, x, tick, false)
end
stage(("40 notes and settles: kept %d, O.n %d"):format(mind.stats.kept, mind.O.n))
local t1 = os.clock()
for _ = 1, 100 do
	mind:think(function() return x end, feasible)
end
stage(("100 thinks: %.0f us each"):format((os.clock() - t1) * 1e4))
