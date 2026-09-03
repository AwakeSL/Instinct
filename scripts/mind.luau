--!nonstrict
-- The learned mind, without Roblox: a creature in a small generated world, scored the way the
-- prototype scored it (rows until its rolling score reaches halfway from a random policy to a greedy
-- hand policy). Checks that the port learns, and how fast, against the prototype's numbers.
--
--     lune run scripts/mind [episodes]   env: WORLD, SEED

local process = require("@lune/process")
local Vector3 = require("@lune/roblox").Vector3
local Instinct = require("../mind")
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
	return { me = { position = Vector3.zero, heading = math.random() * 2 * math.pi, velocity = Vector3.zero, hp = 1, speed = R.mySpeed / 20 }, t = 0, eaten = 0, food = place(), foodH = math.random() * 2 * math.pi, tgt = nil }
end

local function entities(w)
	return { item = { position = w.food, velocity = w.foodV or Vector3.zero, hp = 1, extra = 1 } }
end

local function senses(w)
	return Senses.encode(w.me, SLOTS, entities(w), { (R.length - w.t) / R.length, 0 }, 40)
end

local function feasible(p)
	return p[1] ~= 2 and p[1] ~= 4 and p[4] == 1
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
	if (w.food - me.position).Magnitude < R.itemRadius then
		w.eaten += 1
		w.food = place()
	end
	w.t += 1
end

local function totalsOf(w)
	return { 0, 0, w.eaten }
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
local mind = Mind.new(#NAMES, CHOICES, { set = "OMECA", readings = READINGS, pref = PREF, horizon = 24, step = 12, beam = 10 })
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

-- save and reload: the creature is itself afterwards
local saved = mind:save()
local again = Mind.new(#NAMES, CHOICES, { set = "OMECA", readings = READINGS, pref = PREF, horizon = 24, step = 12, beam = 10 })
again:load(saved)
again.exploring = false
local check = 0
for _ = 1, 5 do
	local w = newWorld()
	while w.t < R.length do
		local picks = again:think(function()
			return senses(w)
		end, feasible)
		step(w, picks)
	end
	check += w.eaten * PREF.eaten
end
print(("  reloaded creature, 5 check episodes: %.0f"):format(check / 5))
