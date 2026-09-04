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

-- CHECKSEP=1: check the separable pick search against the full worth() on every combination scored
if process.env.CHECKSEP == "1" then
	local orig = Mind.scoreCombos
	local maxErr, n = 0, 0
	Mind.scoreCombos = function(self, Xs, feasible, scored)
		orig(self, Xs, feasible, scored)
		local phi = {}
		for _, sc in ipairs(scored) do
			local v = self:worth(Xs[sc.p[1]], sc.p, phi)
			maxErr = math.max(maxErr, math.abs(v - sc.v))
			n += 1
		end
		if n % 20000 < #scored then
			print(("CHECKSEP %d combinations, max error %.3g"):format(n, maxErr))
		end
	end
end

local EPIS = tonumber(process.args[1]) or 60
local SEED = tonumber(process.env.SEED) or 1
local WORLD = tonumber(process.env.WORLD) or 2
math.randomseed(SEED * 7919 + WORLD)

-- ------------------------------------------------------------------ a world (the prototype's world 2 and 24: an item that respawns and may drift)
local TICK = 0.1
local SLOTS = { "host", "item", "haz", "ally" }
-- SUBJ=D: every slot carries D learned numbers about the individual in it (memory of people and things)
local SUBJ = tonumber(process.env.SUBJ) or 0
local NAMES = Senses.layout(SLOTS, { "timeLeft", "armed" }, SUBJ)
local WHO = nil -- the mind's who-function, once it exists
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
	elseif WORLD == 3
	then { size = 20, length = 400, mySpeed = 8, itemRadius = 4, drift = 2, people = true }
	else { size = 30, length = 300, mySpeed = 10, itemRadius = 5, drift = 0 }
-- WORLD=3, people: three individuals of one kind (all in the `host` slot, nearest first) wander the arena.
-- Reaching A is a meal, reaching B is a wound, C is nothing. Nothing in their senses tells them apart: only
-- what each has come to mean to the creature can, which is what the subject memory is for.
local PEOPLE = { { id = "A", meal = true }, { id = "B", hurt = true }, { id = "C" } }

local function place()
	return Vector3.new((math.random() - 0.5) * 1.6 * R.size, 0, (math.random() - 0.5) * 1.6 * R.size)
end

local function newWorld()
	local w = { me = { position = Vector3.zero, heading = math.random() * 2 * math.pi, velocity = Vector3.zero, hp = 1, speed = R.mySpeed / 20 }, t = 0, eaten = 0, taken = 0, food = place(), foodH = math.random() * 2 * math.pi, tgt = nil }
	if R.people then
		w.people = {}
		for k, who in ipairs(PEOPLE) do
			w.people[k] = { id = who.id, meal = who.meal, hurt = who.hurt, position = place(), heading = math.random() * 2 * math.pi, velocity = Vector3.zero }
		end
	end
	return w
end

local function nearestPerson(w)
	local best, bd = nil, math.huge
	for _, pr in ipairs(w.people) do
		local d = (pr.position - w.me.position).Magnitude
		if d < bd then
			best, bd = pr, d
		end
	end
	return best
end

local function entities(w)
	if R.people then
		local pr = nearestPerson(w)
		return { host = { id = pr.id, position = pr.position, velocity = pr.velocity, hp = 1, extra = 0 } }
	end
	return { item = { position = w.food, velocity = w.foodV or Vector3.zero, hp = 1, extra = 1 } }
end

local function senses(w)
	return Senses.encode(w.me, SLOTS, entities(w), { (R.length - w.t) / R.length, 0 }, 40, WHO, SUBJ)
end

local function feasible(p)
	if R.people then
		return p[1] ~= 3 and p[1] ~= 4 and p[4] == 1
	end
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
	elseif picks[1] == 2 then
		tgt = ents.host
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
	if R.people then
		for _, pr in ipairs(w.people) do
			-- each wanders, and one that is reached does what it does and moves elsewhere
			pr.heading += (math.random() - 0.5) * 0.4
			local p0 = pr.position
			pr.position = clamp(pr.position + Vector3.new(math.cos(pr.heading), 0, math.sin(pr.heading)) * R.drift * TICK)
			pr.velocity = (pr.position - p0) / TICK
			if (pr.position - me.position).Magnitude < R.itemRadius then
				if pr.meal then
					w.eaten += 1
				elseif pr.hurt then
					w.taken += 1
				end
				pr.position = place()
			end
		end
	elseif (w.food - me.position).Magnitude < R.itemRadius then
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
local function greedyPicks(w)
	if R.people then
		-- approach the nearest person only when it is the one that feeds you; otherwise keep away from them
		local pr = nearestPerson(w)
		return if pr.meal then { 2, 2, 2, 1 } else { 2, 3, 1, 1 }
	end
	return { 3, 2, 2, 1 }
end
local function refEpisode(policy)
	local w = newWorld()
	while w.t < R.length do
		step(w, policy(w))
	end
	return w.eaten * PREF.eaten + w.taken * PREF.taken
end

-- ------------------------------------------------------------------ the creature
local GROUPS = Senses.groups(SLOTS, { "timeLeft", "armed" }, SUBJ)
local BLOCKS = if process.env.BLOCKS == "1" then GROUPS else nil
local OPTS = { set = "OMECA", subjects = if SUBJ > 0 then { dim = SUBJ, learn = tonumber(process.env.SUBJLEARN) or 0.05 } else nil, code = tonumber(process.env.CODE), calibrated = process.env.CALIB ~= "0", separable = process.env.SEP ~= "0", centredFlags = process.env.CENTRED == "1", optionBlock = process.env.OPTBLOCK == "1", effectsInputs = process.env.EFFIN, lms = tonumber(process.env.LMS), poolRaw = process.env.POOLRAW ~= "0", readings = READINGS, pref = PREF, horizon = 24, step = 12, beam = tonumber(process.env.BEAM) or 10, blocks = BLOCKS, groups = GROUPS, sparse = process.env.SPARSE == "1", equivariant = process.env.EQUIV == "1", pooledValue = process.env.POOL == "1" }
local mind = Mind.new(#NAMES, CHOICES, OPTS)
if SUBJ > 0 then
	WHO = mind:whoFn()
end
-- COACH=floor: rebirth below the random floor; COACH=stall: and when stalled within half the way to greedy
local coach = Coach.new(mind, {
	explore = 5,
	every = 10,
	floor = if process.env.COACH then "explore" else nil,
})
-- INSTINCTS=1: born with the forage instincts (the place's Instincts.forage, in this world's names)
if process.env.INSTINCTS == "1" then
	mind:learnFrom({
		priors = {
			{ reading = "eaten", feature = "itemthere", w = 3, conf = 3 },
			{ reading = "eaten", feature = "itemdist", w = -4, conf = 3 },
			{ reading = "eaten", feature = "itemclosing", w = 2, conf = 3 },
			{ reading = "eaten", feature = "mul(move=approach,itemthere)", w = 3, conf = 3 },
			{ reading = "eaten", feature = "mul(target=item,itemthere)", w = 3, conf = 3 },
		},
		features = {
			{ op = "mul", a = "move=approach", b = "itemthere" },
			{ op = "mul", a = "target=item", b = "itemthere" },
		},
	}, NAMES)
	print(("instincts: %d priors placed, %d features"):format(mind.stats.priors or 0, #mind.acquired))
end

local function episode(learn)
	local w = newWorld()
	local tick = 0
	local heldPicks = nil
	while w.t < R.length do
		local reflexEvery = tonumber(process.env.REFLEX)
		local holdEvery = tonumber(process.env.HOLD)
		local picks, x, phi, event
		if holdEvery and tick % holdEvery ~= 0 and heldPicks then
			-- HOLD=k: a full decision every k-th tick, the picks held between (no think, no row)
			picks = heldPicks
		else
			picks, x, phi, event = mind:think(function()
				return senses(w)
			end, feasible, reflexEvery ~= nil and tick % reflexEvery ~= 0)
			heldPicks = picks
			if learn then
				mind:note(x, phi, picks, event, totalsOf(w), tick)
			end
		end
		step(w, picks)
		tick += 1
		if learn then
			mind:settle(totalsOf(w), senses(w), tick, w.t >= R.length)
		end
	end
	return w.eaten * PREF.eaten + (w.taken or 0) * PREF.taken
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
if process.env.COACH == "stall" then
	coach.stallAbove = (grd - rnd) / 2
end

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
print(("RESULT world %d: %s, last 10 episodes %.0f (greedy %.0f), %.0f us a think, %.1f s in all, rebirths %d (%d stalled), acquired: %s"):format(
	WORLD,
	if reached then ("threshold at episode %d after %d rows"):format(reached, reachedRows) else "threshold never reached",
	coach:rolling(),
	grd,
	mind:microsecondsAThink(),
	os.clock() - t0,
	coach.rebirths,
	coach.stalls or 0,
	table.concat(mind:acquiredNames(NAMES), "  ")
))

-- save and reload: the creature is itself afterwards
local saved = mind:save()
local again = Mind.new(#NAMES, CHOICES, OPTS)
again:load(saved)
again.exploring = false
if SUBJ > 0 then
	WHO = again:whoFn()
end
if process.env.DISTILL == "1" then
	-- a spawn of the same kind: born from what the first creature distilled, not from its whole covariance
	local loaded = again
	local K = mind:distill(NAMES, tonumber(process.env.DISTILL_TOP), tonumber(process.env.DISTILL_CONF), tonumber(process.env.DISTILL_MEM))
	again = Mind.new(#NAMES, CHOICES, OPTS)
	again:learnFrom(K, NAMES)
	again.exploring = false
	print(("  distilled: %d priors, %d features, %d memories -> placed %d priors, %d features"):format(#K.priors, #K.features, #K.memories, again.stats.priors or 0, #again.acquired))
	if process.env.DISTILL_DEBUG == "1" then
		local worst, wf = 0, 0
		for r = 1, mind.NRO do
			for f = 1, math.min(mind.O.F, again.O.F) do
				local d = math.abs(mind.O.W[r][f] - again.O.W[r][f])
				if d > worst then
					worst, wf = d, f
				end
			end
		end
		print(("  weights: F %d vs %d, largest gap %.3f at input %d (%s); bias %.2f vs %.2f"):format(mind.O.F, again.O.F, worst, wf, if wf > 1 then mind:inputName(wf - 1, NAMES) else "bias", mind.O.W[3][1], again.O.W[3][1]))
		-- the same senses to both: do they choose alike?
		local w = newWorld()
		local agree, n = 0, 0
		for _ = 1, 150 do
			local x = senses(w)
			local p1 = loaded:think(function()
				return x
			end, feasible)
			local p2 = again:think(function()
				return x
			end, feasible)
			n += 1
			if table.concat(p1, ",") == table.concat(p2, ",") then
				agree += 1
			end
			step(w, p1)
		end
		print(("  decisions alike on %d of %d; distilled acquired %d, loaded acquired %d, FO %d vs %d, F %d vs %d"):format(agree, n, #again.acquired, #loaded.acquired, again.FO, loaded.FO, again.O.F, loaded.O.F))
		-- first-step values on one set of senses, both minds
		local x = senses(w)
		local X1, X2 = loaded:extend(loaded:encode(x)), again:extend(again:encode(x))
		local dX = 0
		for i = 1, #X1 do
			dX = math.max(dX, math.abs(X1[i] - (X2[i] or 0)))
		end
		local dv, dv1 = 0, 0
		for _, p in ipairs(loaded.combos) do
			local v1 = loaded:worth(X1, p, {}, true)
			local v2 = again:worth(X2, p, {}, true)
			dv = math.max(dv, math.abs(v1 - v2))
			dv1 = math.max(dv1, math.abs(v1 - again:worth(X1, p, {}, true)))
		end
		print(("  same senses: extended inputs differ by %.3f at most; first-step worth differs by %.3f (by %.3f on identical inputs); effect priors %s, drift priors %s"):format(dX, dv, dv1, tostring(again.stats.effectPriors), tostring(again.stats.driftPriors)))
	end
end
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
