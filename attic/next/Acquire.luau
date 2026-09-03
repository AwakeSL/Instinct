--!strict
-- Working out a better way of seeing.
--
-- A creature composes the operators it was given; it never invents one. Given `delta` it can find
-- that change-in-distance predicts what is about to happen better than distance does -- and that
-- discovery *is* `closing`. It did not invent differentiation, it found a composition in a space
-- somebody else defined.
--
-- An acquired reading is a new **layer**: an abstraction built on the ones below it, exactly like an
-- authored derived reading and indistinguishable from one afterwards. That is the honest reason to
-- have this at all -- not that a plan called for it, but that it is how a creature grows its own
-- vocabulary rather than being stuck with the one it was born with.
--
-- It only goes looking when its current ideas keep failing it. Searching every tick would be absurd;
-- never searching means no creature ever forms `closing`.

local Beliefs = require("./Beliefs")
local World = require("./World")

local Acquire = {}

-- Episodes kept per prediction, scaled by `retention`. Both the times it was right and the times it
-- was wrong: keep only the failures and a thing that was present every time you were surprised looks
-- guilty, when it was equally present every time you were not.
--
-- A long memory is what makes an ambitious creature possible. A handful of moments cannot tell a real
-- idea from a lucky one when there are hundreds of ideas to choose between, so `retention` is the
-- price of `ingenuity`.
local KEPT = 60

-- Persistent unresolved error before it goes looking, scaled by `insight`.
local PATIENCE = 6

-- How many times a prediction may be scaled into silence by an idea the creature adopted before that
-- idea is given up. Being unable to say anything is not the same as being right.
local MUTE = 24

-- How much better a candidate must be before it is adopted, scaled by `attribution`. A creature that
-- trusts its own senses demands a great deal before rewriting how it sees; one that doubts them
-- reaches for a new idea readily. The doc already assigns that dial exactly this job.
local MARGIN = 0.12

local function episodeKey(index: number, subject: any): string
	return ("%d|%s"):format(index, tostring(subject))
end

-- What happened, and what the creature could see at the time. Kept as plain readings so a candidate
-- that did not exist then can still be tried against it now.
function Acquire.remember(state: any, index: number, subject: any, snapshot: any, before: any, gap: number, predicted: number, actual: number)
	local key = episodeKey(index, subject)
	local run = state.episodes[key]
	if run == nil then
		run = {}
		state.episodes[key] = run
	end
	table.insert(run, {
		readings = snapshot,
		before = before,
		gap = math.max(gap, 1e-4),
		predicted = predicted,
		actual = actual,
	})
	while #run > Acquire.room(state) do
		table.remove(run, 1)
	end
end

-- How many moments a creature keeps per prediction.
function Acquire.room(state: any): number
	return 4 + math.floor(state.dial("retention") * KEPT)
end

-- ---------------------------------------------------------------- the search space
--
-- A creature composes the operators **it was declared with**; it never invents one. Given `delta` it
-- can find that change-in-distance predicts what is about to happen better than distance does -- and
-- that discovery *is* `closing`. It did not invent differentiation, it found a composition in a space
-- somebody else defined.
--
-- An idea is a little tree: a reading, a constant, or an operator applied to two of those. Adding is
-- not an operator here -- the expression language already sums the elements of a list -- so adding and
-- subtracting are offered alongside whatever was declared.
--
-- `ingenuity` is how deep it may go. Past depth one the space is far too large to enumerate, so it is
-- walked as a **beam**: at each level only the few best ideas so far are extended, and only by a raw
-- reading or a constant. That reaches `(a - b) x c` without ever considering the millions of trees a
-- full enumeration would have to.
local BEAM = 4
local MAX_DEPTH = 3

-- How much better a deeper idea must be than a shallower one, per level. Occam, stated plainly: an
-- elaborate explanation that fits no better than a simple one is a worse explanation -- and an
-- elaborate one has far more ways to fit a small number of moments by accident.
local SIMPLER = 0.25

type Recipe = {
	kind: string, -- "ref" | "const" | "op"
	name: string?,
	value: number?,
	op: string?,
	apply: ((number, number, any?) -> number?)?,
	recalls: boolean?,
	a: Recipe?,
	b: Recipe?,
}

-- What an idea would have read in one moment the creature actually lived through. `before` asks about
-- the moment before that instead, which is what makes a change expressible at all.
local function valueOf(recipe: Recipe, episode: any, before: boolean): number?
	if recipe.kind == "const" then
		return recipe.value
	end
	if recipe.kind == "ref" then
		local from = if before then episode.before else episode.readings
		return from[recipe.name :: string]
	end

	local a = recipe.a :: Recipe
	local b = recipe.b :: Recipe
	if recipe.recalls then
		-- A temporal operator needs what its input was a moment ago, and the creature kept only one
		-- moment. So it can be asked what something is doing now, but not what it was doing then --
		-- which is why a change of a change is out of reach.
		if before then
			return nil
		end
		local was = valueOf(a, episode, true)
		local now = valueOf(a, episode, false)
		if was == nil or now == nil then
			return nil
		end
		local other = valueOf(b, episode, false)
		return (recipe.apply :: any)(now, other or 0, { input = was, output = nil, since = episode.gap })
	end

	local x = valueOf(a, episode, before)
	local y = valueOf(b, episode, before)
	if x == nil or y == nil then
		return nil
	end
	return (recipe.apply :: any)(x, y)
end

Acquire.valueOf = valueOf

local function valuesOf(recipe: Recipe, run: { any }): { number? }
	local out: { number? } = {}
	for at, episode in run do
		out[at] = valueOf(recipe, episode, false)
	end
	return out
end

Acquire.valuesOf = valuesOf

local function plus(a: number, b: number): number?
	return a + b
end

local function minus(a: number, b: number): number?
	return a - b
end

-- Everything the creature can reach, gathered depth by depth, best first.
local function candidates(
	reg: any,
	state: any,
	forms: { string },
	run: { any },
	seed: any?,
	score: ({ number? }) -> number?
): { any }
	local depth = math.ceil(math.clamp(state.dial("ingenuity"), 0, 1) * MAX_DEPTH)
	if depth <= 0 then
		return {}
	end

	-- What it senses, rather than what it has already worked out: a composition is never built on a
	-- composition, so the space stays a function of what the creature can actually perceive.
	local raw: { string } = {}
	for _, name in forms do
		local decl = state.readings[name] or reg.readings[name]
		if decl ~= nil and decl.expr == nil and decl.predicts == nil and decl.unsure == nil then
			table.insert(raw, name)
		end
	end
	table.sort(raw)

	local base: { any } = {}
	for _, name in raw do
		table.insert(base, {
			name = name,
			authored = name,
			depth = 0,
			recipe = { kind = "ref", name = name } :: Recipe,
		})
	end

	-- The idea this prediction is already using, if it has one. A composition is otherwise never built
	-- on a composition -- the space would grow without bound and a creature would end up with towers of
	-- private notions. But the one idea it has already committed to is different: refusing to build on
	-- that is refusing to let it **refine**, so a creature that works out its harm goes with how fast
	-- the thing is closing can never go on to notice that a big one hurts more. It would have to throw
	-- the first idea away and find the whole of the second in one go.
	if seed ~= nil and seed.recipe ~= nil then
		table.insert(base, { name = seed.name, authored = seed.is, depth = 0, recipe = seed.recipe })
	end

	-- What may sit on the right of an operator: anything it senses, or a plain number. The constants
	-- are what make the one-handed uses reachable -- `inverted` against 1, `delta` against nothing.
	local nothing = { name = "0", authored = 0, depth = 0, recipe = { kind = "const", value = 0 } }
	local operands: { any } = table.clone(base)
	table.insert(operands, nothing)
	table.insert(operands, { name = "1", authored = 1, depth = 0, recipe = { kind = "const", value = 1 } })

	-- Every operator the creature was declared with, in a fixed order so that two creatures given the
	-- same world reach the same ideas in the same order.
	local ops: { any } = {}
	for name, op in reg.operators do
		table.insert(ops, { name = name, apply = op.apply, recalls = op.recalls })
	end
	table.sort(ops, function(x, y)
		return x.name < y.name
	end)
	-- Adding and subtracting, which the expression language says by summing a list rather than by an
	-- operator, and which would otherwise be the two obvious things a creature could not think.
	if reg.operators.times ~= nil then
		table.insert(ops, { name = "plus", apply = plus, adds = true })
		table.insert(ops, { name = "minus", apply = minus, subtracts = true })
	end

	local all: { any } = table.clone(base)
	local seen: { [string]: boolean } = {}
	local pool = base

	for level = 1, depth do
		local made: { any } = {}
		for _, x in pool do
			for _, entry in ops do
				-- A temporal operator is asked about one thing. Handing it a second would only make a
				-- family of ideas that all read the same, since it has nowhere to put it. Adding and
				-- subtracting a constant is likewise nothing a fitted scale could not already do.
				local right = operands
				if entry.recalls then
					right = { nothing }
				elseif entry.adds or entry.subtracts then
					right = base
				end
				for _, y in right do
					local authored: any
					if entry.adds then
						authored = { x.authored, y.authored }
					elseif entry.subtracts then
						authored = { x.authored, { y.authored, times = -1 } }
					else
						authored = { x.authored, [entry.name] = y.authored }
					end
					-- A temporal operator has nowhere to put a second operand, so it does not name one.
					local called = if entry.recalls
						then ("%s(%s)"):format(entry.name, x.name)
						else ("%s(%s,%s)"):format(entry.name, x.name, y.name)
					table.insert(made, {
						name = called,
						authored = authored,
						depth = level,
						recipe = {
							kind = "op",
							op = entry.name,
							apply = entry.apply,
							recalls = entry.recalls,
							a = x.recipe,
							b = y.recipe,
						} :: Recipe,
					})
				end
			end
		end

		-- Two ideas that say the same thing about every moment the creature has lived through are the
		-- same idea, and the one it reached first is the simpler one.
		local kept: { any } = {}
		for _, node in made do
			node.values = valuesOf(node.recipe, run)
			local mark: { string } = {}
			local told = false
			for _, value in node.values do
				if value ~= nil then
					told = true
				end
				table.insert(mark, if value == nil then "-" else ("%.4f"):format(value))
			end
			local signature = table.concat(mark, ",")
			if told and not seen[signature] then
				seen[signature] = true
				table.insert(kept, node)
				table.insert(all, node)
			end
		end

		if level == depth or #kept == 0 then
			break
		end
		-- Only the best few are worth building on. Everything else is a dead end that would multiply
		-- into thousands by the next level.
		table.sort(kept, function(x, y)
			return (score(x.values) or math.huge) < (score(y.values) or math.huge)
		end)
		pool = {}
		for at = 1, math.min(BEAM, #kept) do
			table.insert(pool, kept[at])
		end
	end

	for _, node in base do
		if node.values == nil then
			node.values = valuesOf(node.recipe, run)
			seen[table.concat({ node.name }, ",")] = true
		end
	end
	return all
end

-- How badly a set of moments is explained by one idea, allowing the best single scale factor. Without
-- fitting the scale an idea would be judged on its units rather than on whether it carries the signal.
local function fit(run: { any }, values: { number? }): number?
	local top, bottom, n = 0, 0, 0
	local rows: { { number } } = {}
	for at, episode in run do
		local basis = values[at]
		if basis == nil then
			continue -- a moment this one has nothing to say about, rather than a reason to say nothing
		end
		table.insert(rows, { basis, episode.actual })
		top += basis * episode.actual
		bottom += basis * basis
		n += 1
	end
	if n < 4 or bottom <= 1e-9 then
		return nil
	end
	local k = top / bottom
	local sum = 0
	for _, row in rows do
		local miss = row[2] - k * row[1]
		sum += miss * miss
	end
	return sum / n
end

local function column(run: { any }, of: (any) -> number?): { number? }
	local out: { number? } = {}
	for at, episode in run do
		out[at] = of(episode)
	end
	return out
end

-- Two numbers about what the creature is already managing: how well a flat number would do, and how
-- well what it actually says does. Judging only against its own prediction is no good once that belief
-- has collapsed toward zero, because then anything at all fits better than nothing -- and judging only
-- against a flat number would throw away an idea that is working.
local function standing(run: { any }): (number?, number?)
	local flat = fit(run, column(run, function()
		return 1
	end))
	local own = fit(run, column(run, function(episode: any): number?
		return episode.predicted
	end))
	return flat, own
end

-- Adopt it: register the reading on this creature alone, teach it to form it, and rewrite the
-- failing prediction to scale by it. Acquired readings are private -- an idea one creature worked out
-- is not one every creature is born with -- and they are kept as **authored** expressions alongside
-- the compiled ones, so they can be handed back out as a declaration and given to a species.
-- Rewrite one prediction so it scales by a reading, or stops scaling by one. Both directions go
-- through here, because adopting an idea and abandoning it are the same edit.
local function rewrite(reg: any, state: any, index: number, drop: string?, take: any?)
	local entry = state.predicts[index]
	local mods: { any } = {}
	local site = 0
	for _, mod in entry.expr.mods do
		if drop ~= nil and mod.operand ~= nil and mod.operand.ref == drop then
			continue
		end
		site = math.max(site, mod.site)
		table.insert(mods, mod)
	end

	local by: { any } = {}
	for _, one in (entry.source.by or {}) do
		if drop == nil or one[1] ~= drop then
			table.insert(by, one)
		end
	end

	local uses = if entry.uses ~= drop then entry.uses else nil
	if take ~= nil then
		table.insert(mods, {
			op = "times",
			stage = reg.operators.times.stage,
			site = site + 1,
			operand = { ref = take.name, spread = 0, terms = {}, mods = {}, costs = 0 },
		})
		table.insert(by, { take.name })
		uses = take.name
	end

	local source = table.clone(entry.source)
	source.by = if #by > 0 then by else nil
	local fresh = table.clone(entry)
	fresh.uses = uses
	fresh.source = source
	fresh.expr = {
		const = entry.expr.const,
		spread = entry.expr.spread,
		terms = entry.expr.terms,
		mods = mods,
		costs = entry.expr.costs,
	}
	state.predicts[index] = fresh

	-- The belief starts again: it is a claim about something else now, and carrying the old number
	-- over would be inheriting a verdict passed on a different idea.
	local key = ("pred|%d|"):format(index)
	for beliefKey in state.beliefs do
		if beliefKey:sub(1, #key) == key then
			state.beliefs[beliefKey] = nil
		end
	end
end

-- An acquired reading lives as long as something is using it. A creature that has abandoned the only
-- idea built on it should not still be paying to work it out every tick.
local function release(state: any, name: string?)
	if name == nil then
		return
	end
	local decl = state.readings[name]
	if decl == nil then
		return
	end
	decl.users -= 1
	if decl.users > 0 then
		return
	end
	state.readings[name] = nil
	for at, form in state.forms do
		if form == name then
			table.remove(state.forms, at)
			break
		end
	end
end

local function adopt(reg: any, state: any, index: number, idea: any)
	local name = idea.name
	local decl = state.readings[name]
	if decl == nil then
		state.readings[name] = {
			name = name,
			from = {},
			-- Kept so it can be asked, later, whether it is still worth having.
			recipe = idea.recipe,
			is = idea.authored, -- kept readable, so it can be declared on a registry as it stands
			expr = reg.compile(idea.authored, ("acquired %q"):format(name)),
			costs = 0,
			acquired = true,
			users = 1,
		}
		table.insert(state.forms, name)
	else
		decl.users += 1
	end

	local was = state.predicts[index].uses
	rewrite(reg, state, index, was, idea)
	release(state, was)
end

-- Go looking, but only where the creature keeps being wrong, and only every so often.
--
-- `insight` is how often it looks. Nothing changes from one tick to the next, so a creature that
-- searched every frame would do the same futile work sixty times a second -- and the search is the one
-- expensive thing in the package, since a deep one weighs hundreds of ideas against every moment it
-- has kept.
local LOOK_EVERY = 15

function Acquire.consider(reg: any, state: any): number
	if state.dial("ingenuity") <= 0 then
		return 0
	end
	local needed = 2 + math.floor((1 - math.clamp(state.dial("insight"), 0, 1)) * PATIENCE)
	local demand = MARGIN * (0.3 + state.dial("attribution"))
	local rest = 1 + (1 - math.clamp(state.dial("insight"), 0, 1)) * LOOK_EVERY
	local taken = 0

	-- Ideas that have silenced their own prediction. These leave no episodes behind, so they have to
	-- be swept up before the buffer is walked or they would never be looked at again.
	for index, count in state.mute do
		local entry = state.predicts[index]
		if entry ~= nil and entry.uses ~= nil and count >= MUTE then
			local dropped = entry.uses
			rewrite(reg, state, index, dropped, nil)
			release(state, dropped)
			state.mute[index] = 0
			state.residual[("%d|%s"):format(index, World.SELF)] = nil
			state.episodes[("%d|%s"):format(index, World.SELF)] = nil
			taken += 1
		end
	end

	for key, run in state.episodes do
		local index = tonumber(key:match("^(%d+)|"))
		if index == nil then
			continue
		end
		local entry = state.predicts[index]
		if entry == nil then
			continue
		end
		local stuck = state.residual[key]
		if stuck == nil or stuck.n < needed or (stuck.total / stuck.n) < 1 then
			continue
		end
		-- How much it insists on having seen before it will believe a new idea. `retention` is how much
		-- a creature keeps to test against, so it is also what decides how much is enough: on a handful
		-- of moments almost anything fits, and a creature that adopts there spends its life taking
		-- ideas up and putting them down again.
		-- Reaching further costs evidence. A creature that can think of four hundred ideas cannot judge
		-- between them on eight moments, and one that tries will adopt an elaborate coincidence every
		-- time. `retention` is what pays for `ingenuity`.
		local depth = math.ceil(math.clamp(state.dial("ingenuity"), 0, 1) * MAX_DEPTH)
		if #run < math.max(8, Acquire.room(state) // 3, 4 * depth) then
			continue
		end
		if state.now - (state.searched[key] or -math.huge) < rest then
			continue
		end
		state.searched[key] = state.now

		local flat, own = standing(run)
		local base = flat
		if own ~= nil and (base == nil or own < base) then
			base = own
		end
		if base == nil or base <= 1e-9 then
			continue
		end

		-- What this prediction would come to without the reading it worked out, so the question asked
		-- of an acquired idea is the one that matters -- *is this earning its keep* -- rather than
		-- whether the prediction as a whole is any good. A creature whose authored scaling is simply
		-- wrong would otherwise throw away the one part of it that was right.
		local without: number? = nil
		if entry.uses ~= nil then
			local used = state.readings[entry.uses]
			local shape = if used ~= nil then used.recipe else nil
			if shape ~= nil then
				without = fit(run, column(run, function(episode: any): number?
					local f = valueOf(shape, episode, false)
					if f == nil or math.abs(f) < 1e-4 then
						return nil
					end
					return episode.predicted / f
				end))
			end
		end

		local held = if entry.uses ~= nil then state.readings[entry.uses] else nil
		local reachable = candidates(reg, state, state.forms, run, held, function(values: { number? }): number?
			return fit(run, values)
		end)

		-- How much better a new idea must be before it is believed. Trying more ideas against the same
		-- evidence has to cost more: a creature that can reach four compositions and one that can reach
		-- four hundred are not in the same position after both find one that fits a little better, and
		-- with enough candidates and few enough moments something always fits. This is the difference
		-- between a creature that works things out and one that is forever adopting coincidences.
		--
		-- It matters more than it sounds. A forager with eight readings can reach hundreds of ideas,
		-- and on a flat margin it reliably invented one -- `times(clearEast, toSouth)` -- grafted it
		-- onto a prediction about food, and stopped foraging.
		--
		-- It is also what makes `ingenuity` cost something. A creature that reaches further needs a
		-- longer memory to justify what it finds there, or it will never be sure enough to use it.
		local asked = demand * (1 + math.sqrt(#reachable / math.max(#run, 1)))

		local best, bestScore = nil, base
		for _, idea in reachable do
			if idea.name == entry.uses then
				continue -- the idea it already has is the one that is failing
			end
			local got = fit(run, idea.values)
			if got == nil then
				continue
			end
			-- Occam: an elaborate explanation that fits no better than a simple one is worse.
			got *= 1 + idea.depth * SIMPLER
			if got < bestScore then
				best, bestScore = idea, got
			end
		end

		-- Spurious ideas fit a little better by luck, so a little better is not enough.
		if best ~= nil and bestScore < base * (1 - asked) then
			adopt(reg, state, index, best)
			state.residual[key] = nil
			state.episodes[key] = nil
			state.searched[key] = nil
			taken += 1
		elseif
			entry.uses ~= nil
			-- An idea cannot be judged on a handful of moments that were all alike. The buffer was
			-- emptied when it was adopted, and until it has filled again the only episodes to hand are
			-- from one stretch of one situation -- where a reading that varies slowly is
			-- indistinguishable from one that does not vary at all. Judging it there would throw away
			-- every idea a creature ever had, immediately after having it.
			and #run >= math.max(8, Acquire.room(state) // 2)
			and not (own ~= nil and without ~= nil and own < without)
		then
			-- It is still being caught out, nothing else it can reach explains this any better, and it
			-- would do no worse without the idea it adopted. So that idea is not earning its keep, and
			-- it gives it up. The test is the objective itself -- does using it lower prediction error
			-- -- rather than a patience counter, which is why an idea that is working survives being
			-- wrong about the scale while it relearns it.
			--
			-- Note the asymmetry, which is deliberate and is the same one that runs through the rest of
			-- the package. Adopting an idea demands a real margin, because a spurious one fits a little
			-- better by luck. Keeping one demands only that it help *at all*. Scepticism belongs at the
			-- point where a creature takes an idea on, not at the point where it is deciding whether to
			-- abandon something that has been working.
			local dropped = entry.uses
			rewrite(reg, state, index, dropped, nil)
			release(state, dropped)
			state.residual[key] = nil
			state.episodes[key] = nil
			state.searched[key] = nil
			taken += 1
		end
	end
	return taken
end

function Acquire.blame(state: any, key: string, surprise: number)
	local held = state.residual[key]
	if held == nil then
		held = { n = 0, total = 0 }
		state.residual[key] = held
	end
	held.n += 1
	held.total += surprise
end

-- A snapshot of everything the creature can currently read about one thing, for looking back on.
function Acquire.snapshot(reg: any, state: any, subject: any, forms: { string }): any
	local out: any = {}
	for _, name in forms do
		local decl = state.readings[name] or reg.readings[name]
		if decl == nil or decl.expr ~= nil then
			continue -- raw readings only; a composition can be rebuilt from them
		end
		local value = World.read(reg, state, subject, name)
		if value ~= nil then
			out[name] = value
		end
	end
	return out
end

Acquire.beliefsSeen = Beliefs

return Acquire
