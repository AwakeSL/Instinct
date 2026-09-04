--!nonstrict
-- SLOT PROBE (Kestrel, 2026-09-04). scripts/mind.luau's world with three more slots made live -- a
-- hostile that chases, a hazard that wanders, an ally that trails -- so that all four slots are
-- populated at once and the covariance actually accumulates cross-slot terms.
--
-- Why it exists: worlds 2 and 24 present ONE slot of four. An absent slot reads all zeros and a zero
-- row accumulates no cross-covariance, so on those worlds every cross-slot block of P is exactly zero
-- and no diagnostic run on them can say anything about slot coupling, slot tying or separability.
--
-- It prints each model's effective dimension (d_eff = F - sum_i r_i*P[i][i], with r_i read off an
-- untrained twin because the outcome model's extraRidge is not uniform) and dumps the 28x28 slot
-- block of P (and the weight block) to probe_out/*.csv for offline analysis.
--
-- This is a PROBE, not a scored world: it is not part of the held-out battery and its numbers are not
-- comparable to the baselines in docs/IDEAS.md. It exists to make covariance geometry observable.
--
--     lune run scripts/slots4_mind [episodes]   env: WORLD, SEED

local process = require("@lune/process")
local Vector3 = require("@lune/roblox").Vector3
local Instinct = require("../src")
local Mind, Senses, Coach = Instinct.Mind, Instinct.Senses, Instinct.Coach

local EPIS = tonumber(process.args[1]) or 60
local SEED = tonumber(process.env.SEED) or 1
local WORLD = tonumber(process.env.WORLD) or 2
math.randomseed(SEED * 7919 + WORLD)

-- ------------------------------------------------------------------ a world (the prototype's world 2 and 24: an item that respawns and may drift)
local TICK = 0.1
local SLOTS = { "host", "item", "haz", "ally" }
local NAMES = Senses.layout(SLOTS, { "timeLeft", "armed" })
local CHOICES = {
	{ name = "target", options = { "keep", "hostile", "item", "ally" } },
	{ name = "move", options = { "hold", "approach", "retreat", "orbit", "centre" } },
	{ name = "aim", options = { "none", "face" } },
	{ name = "act", options = { "none", "strike" } },
}
local READINGS = { "dealt", "taken", "eaten" }
local PREF = { dealt = 1, taken = -1, eaten = 20 }

local R = if WORLD == 24
	then { size = 15, length = 800, mySpeed = 6, itemRadius = 3, drift = 3 }
	else { size = 30, length = 300, mySpeed = 10, itemRadius = 5, drift = 0 }

local function place()
	return Vector3.new((math.random() - 0.5) * 1.6 * R.size, 0, (math.random() - 0.5) * 1.6 * R.size)
end

local function newWorld()
	return { me = { position = Vector3.zero, heading = math.random() * 2 * math.pi, velocity = Vector3.zero, hp = 1, speed = R.mySpeed / 20 }, t = 0, eaten = 0, taken = 0, food = place(), foodH = math.random() * 2 * math.pi, tgt = nil,
		host = place(), hostV = Vector3.zero, haz = place(), hazH = math.random() * 2 * math.pi, hazV = Vector3.zero, ally = place(), allyV = Vector3.zero }
end

local function entities(w)
	return {
		item = { position = w.food, velocity = w.foodV or Vector3.zero, hp = 1, extra = 1 },
		host = { position = w.host, velocity = w.hostV, hp = 1, extra = 0 },
		haz = { position = w.haz, velocity = w.hazV, hp = 1, extra = 1 },
		ally = { position = w.ally, velocity = w.allyV, hp = 1, extra = 0 },
	}
end

local function senses(w)
	return Senses.encode(w.me, SLOTS, entities(w), { (R.length - w.t) / R.length, 0 }, 40)
end

local function feasible(p)
	return p[4] == 1
end

local function clamp(v: Vector3): Vector3
	return Vector3.new(math.clamp(v.X, -R.size, R.size), 0, math.clamp(v.Z, -R.size, R.size))
end

local function step(w, picks)
	local me = w.me
	local ents = entities(w)
	local tgt = w.tgt
	if picks[1] == 3 then
		tgt = ents.item
	end
	w.tgt = tgt
	local turn, move = 0, nil
	local b = if tgt then Senses.bearing(me, tgt) else 0
	local Q = math.rad(90) * TICK
	local function turnTo(a)
		if a > Q / 2 then
			turn = 1
		elseif a < -Q / 2 then
			turn = -1
		end
	end
	if picks[3] == 2 and tgt then
		turnTo(b)
	end
	local mv = picks[2]
	if mv == 2 and tgt then
		if math.abs(b) < math.pi / 3 then
			move = "forward"
		else
			turnTo(b)
		end
	elseif mv == 3 and tgt then
		local away = Senses.wrap(b + math.pi)
		if math.abs(away) < math.pi / 3 then
			move = "forward"
		else
			turnTo(away)
		end
	elseif mv == 4 and tgt then
		move = "strafe"
	elseif mv == 5 then
		local dc = Senses.wrap(math.atan2(-me.position.Z, -me.position.X) - me.heading)
		if math.abs(dc) < math.pi / 6 then
			move = "forward"
		else
			turnTo(dc)
		end
	end
	me.heading = Senses.wrap(me.heading + turn * math.rad(90) * TICK)
	local before = me.position
	local speed = R.mySpeed
	if move == "forward" then
		me.position = clamp(me.position + Vector3.new(math.cos(me.heading), 0, math.sin(me.heading)) * speed * TICK)
	elseif move == "strafe" then
		me.position = clamp(me.position + Vector3.new(-math.sin(me.heading), 0, math.cos(me.heading)) * speed * TICK)
	end
	me.velocity = (me.position - before) / TICK
	if R.drift > 0 then
		w.foodH += (math.random() - 0.5) * 0.4
		local f0 = w.food
		w.food = clamp(w.food + Vector3.new(math.cos(w.foodH), 0, math.sin(w.foodH)) * R.drift * TICK)
		w.foodV = (w.food - f0) / TICK
	end
	-- the hostile chases, the hazard wanders, the ally trails the creature
	local function toward(from, to, sp)
		local d = to - from
		if d.Magnitude < 1e-6 then return from, Vector3.zero end
		local nxt = clamp(from + d.Unit * sp * TICK)
		return nxt, (nxt - from) / TICK
	end
	w.host, w.hostV = toward(w.host, me.position, R.mySpeed * 0.7)
	w.ally, w.allyV = toward(w.ally, me.position - Vector3.new(math.cos(me.heading), 0, math.sin(me.heading)) * 6, R.mySpeed * 0.9)
	w.hazH += (math.random() - 0.5) * 0.5
	local h0 = w.haz
	w.haz = clamp(w.haz + Vector3.new(math.cos(w.hazH), 0, math.sin(w.hazH)) * R.mySpeed * 0.4 * TICK)
	w.hazV = (w.haz - h0) / TICK
	if (w.host - me.position).Magnitude < 4 then
		w.taken += 1
	end
	if (w.haz - me.position).Magnitude < 4 then
		w.taken += 1
	end
	if (w.food - me.position).Magnitude < R.itemRadius then
		w.eaten += 1
		w.food = place()
	end
	w.t += 1
end

local function totalsOf(w)
	return { 0, w.taken, w.eaten }
end

-- reference policies
local function randomPicks()
	local p
	repeat
		p = { math.random(4), math.random(5), math.random(2), math.random(2) }
	until feasible(p)
	return p
end
local function greedyPicks()
	return { 3, 2, 2, 1 }
end
local function refEpisode(policy)
	local w = newWorld()
	while w.t < R.length do
		step(w, policy())
	end
	return w.eaten * PREF.eaten
end

-- ------------------------------------------------------------------ the creature
local GROUPS = Senses.groups(SLOTS, { "timeLeft", "armed" })
local BLOCKS = if process.env.BLOCKS == "1" then GROUPS else nil
local mind = Mind.new(#NAMES, CHOICES, { set = "OMECA", calibrated = process.env.CALIB ~= "0", readings = READINGS, pref = PREF, horizon = 24, step = 12, beam = 10, blocks = BLOCKS, groups = GROUPS, sparse = process.env.SPARSE == "1", equivariant = process.env.EQUIV == "1", pooledValue = process.env.POOL == "1" })
local coach = Coach.new(mind, { explore = 5, every = 10, floor = nil })

local function episode(learn)
	local w = newWorld()
	local tick = 0
	while w.t < R.length do
		local picks, x, phi, event = mind:think(function()
			return senses(w)
		end, feasible)
		if learn then
			mind:note(x, phi, picks, event, totalsOf(w), tick)
		end
		step(w, picks)
		tick += 1
		if learn then
			mind:settle(totalsOf(w), senses(w), tick, w.t >= R.length)
		end
	end
	return w.eaten * PREF.eaten
end

local rnd, grd = 0, 0
for _ = 1, 10 do
	rnd += refEpisode(randomPicks)
	grd += refEpisode(greedyPicks)
end
rnd, grd = rnd / 10, grd / 10
local thr = rnd + 0.5 * (grd - rnd)
coach.floor = rnd
print(("world %d: random %.0f, greedy %.0f, threshold %.0f  (%d senses, %d combinations)"):format(WORLD, rnd, grd, thr, #NAMES, #mind.combos))

local recent, reached, reachedRows = {}, nil, nil
local sum = 0
local t0 = os.clock()
for g = 1, EPIS do
	coach:beginEpisode()
	local s = episode(true)
	if coach:endEpisode(s) then
		print(("  reborn at episode %d"):format(g))
	end
	sum += s
	table.insert(recent, s)
	if #recent > 10 then
		table.remove(recent, 1)
	end
	if not reached and #recent == 10 and coach:rolling() >= thr then
		reached, reachedRows = g, mind.stats.kept
	end
	if g % 10 == 0 then
		print(("  episodes %d-%d: %.0f"):format(g - 9, g, sum / 10))
		sum = 0
	end
end
print(("RESULT world %d: %s, last 10 episodes %.0f (greedy %.0f), %.0f us a think, %.1f s in all, acquired: %s"):format(
	WORLD,
	if reached then ("threshold at episode %d after %d rows"):format(reached, reachedRows) else "threshold never reached",
	coach:rolling(),
	grd,
	mind:microsecondsAThink(),
	os.clock() - t0,
	table.concat(mind:acquiredNames(NAMES), "  ")
))




-- ------------------------------------------------- effective dimension, with the per-input ridge read from a fresh twin
-- d_eff = tr(G P) and P0^-1 = diag(r_i), so d_eff = F - sum_i r_i * P[i][i]. The outcome model uses
-- extraRidge on its extra inputs, so r_i is NOT uniform: take it from an untrained twin's diagonal.
local twin = Mind.new(#NAMES, CHOICES, { set = "OMECA", calibrated = process.env.CALIB ~= "0", readings = READINGS, pref = PREF, horizon = 24, step = 12, beam = 10, blocks = BLOCKS, groups = GROUPS, sparse = process.env.SPARSE == "1", equivariant = process.env.EQUIV == "1", pooledValue = process.env.POOL == "1" })
local function deff(m, m0, label)
	if m0 == nil then print(label .. ": no twin, skipped"); return end
	local grown = m.F - m0.F -- acquisition appends inputs at 1/extraRidge
	local d, untouched, distinct = m.F, 0, {}
	for i = 1, m.F do
		local r = if i <= m0.F then 1 / m0.P[i][i] else mind.extraRidge
		distinct[r] = (distinct[r] or 0) + 1
		d -= r * m.P[i][i]
		if i <= m0.F and math.abs(m.P[i][i] - m0.P[i][i]) < 1e-12 then untouched += 1 end
	end
	local rs = {}
	for r, c in pairs(distinct) do table.insert(rs, string.format("%gx%d", r, c)) end
	print(("%-22s F=%-4d rows=%-6d d_eff=%8.2f   unpaid=%7.2f (%2.0f%%)   never-excited=%-4d grown=+%d ridges=%s"):format(
		label, m.F, m.n, d, m.F - d, (m.F - d) / m.F * 100, untouched, grown, table.concat(rs, " ")))
end
print("")
print("effective dimension of the real models, d_eff = F - sum_i r_i*P[i][i]:")
local best, bestN, bestK = nil, -1, nil
for k, m in pairs(mind.E) do if m.n > bestN then best, bestN, bestK = m, m.n, k end end
local quiet, quietN = nil, math.huge
for k, m in pairs(mind.E) do if m.n < quietN then quiet, quietN = m, m.n end end
if best then deff(best, twin.E[bestK], "effects (busiest)") end
if quiet then deff(quiet, twin.E[bestK], "effects (quietest)") end
if mind.O then deff(mind.O, twin.O, "outcome") end
if mind.Cm then deff(mind.Cm, twin.Cm, "couplings") end

-- ---------------------------------------------------------------- dump the slot block for a Kronecker test
local fs = require("@lune/fs")
local NSELF, NSLOT, NFIELD = 9, 4, 7
local function dumpSlotBlock(m, label)
	local idx = {}
	for k = 1, NSLOT do
		for q = 1, NFIELD do
			table.insert(idx, 1 + NSELF + (k - 1) * NFIELD + q)
		end
	end
	local rows = {}
	for _, i in ipairs(idx) do
		local r = {}
		for _, j in ipairs(idx) do
			table.insert(r, string.format("%.17g", m.P[i][j]))
		end
		table.insert(rows, table.concat(r, ","))
	end
	if not fs.isDir("probe_out") then fs.writeDir("probe_out") end
	fs.writeFile("probe_out/s4_" .. label .. ".csv", table.concat(rows, string.char(10)))
	print(("dumped %s (%dx%d, n=%d)"):format(label, #idx, #idx, m.n))
end
local b2, n2, k2 = nil, -1, nil
for k, m in pairs(mind.E) do if m.n > n2 then b2, n2, k2 = m, m.n, k end end
if b2 then dumpSlotBlock(b2, "effects") end
if mind.O then dumpSlotBlock(mind.O, "outcome") end
if mind.Cm then dumpSlotBlock(mind.Cm, "couplings") end

-- the WEIGHTS over the slot block, one row an output: is W[r][slot][field] ~ a[slot]*b[field]?
local function dumpW(m, label)
	local idx = {}
	for k = 1, NSLOT do
		for q = 1, NFIELD do
			table.insert(idx, 1 + NSELF + (k - 1) * NFIELD + q)
		end
	end
	local rows = {}
	for r = 1, m.NR do
		local out = {}
		for _, i in ipairs(idx) do
			table.insert(out, string.format("%.17g", m.W[r][i]))
		end
		table.insert(rows, table.concat(out, ","))
	end
	if not fs.isDir("probe_out") then fs.writeDir("probe_out") end
	fs.writeFile("probe_out/w4_" .. label .. ".csv", table.concat(rows, string.char(10)))
	print(("dumped weights %s (%d outputs x %d slot inputs)"):format(label, m.NR, #idx))
end
if b2 then dumpW(b2, "effects") end
if mind.O then dumpW(mind.O, "outcome") end
