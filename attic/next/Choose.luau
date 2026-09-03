--!strict
-- Preferences, and what to do about them.
--
-- A **preference** is a prior over a reading -- the only thing in the package that produces motion.
-- Everything else a creature holds, it simply learns. Error is `wanted` minus where the reading is
-- **heading**, not where it is, and how far ahead that looks is decided by the predictions the
-- creature happens to hold rather than by anything on the preference. A creature with no prediction
-- about its own decline projects nowhere and only acts once it is already short; one that has
-- learned it runs down sees it coming. Foresight is a consequence of having a model.
--
-- An action is worth **how much better the projection is if it does it**. Project once with no
-- action and once conditioned on this one, and the difference is what the action is for. That works
-- for changes and levels, for the creature and for anything else, with no special case per form.

local Predict = require("./Predict")
local World = require("./World")

local Choose = {}

-- Below this an error is not worth having an opinion about, and everything under it is ignored
-- before anything is ranked.
local FLOOR = 0.2

export type Error = {
	reading: string,
	subject: any,
	wanted: number,
	heading: number,
	want: number, -- signed: positive means it wants more
	amount: number,
	spread: number,
	salience: number,
}

-- An error smaller than its own spread is not evidence. It sits inside the range the model already
-- allows, which is why a creature stops reacting to something it has thoroughly learned.
function Choose.errors(reg: any, state: any): { Error }
	local out: { Error } = {}
	for reading, prior in state.wants do
		local heading, spread = Predict.project(reg, state, World.SELF, state.species.kind, reading, nil)
		if heading == nil then
			continue
		end
		local want = prior.value - heading
		local width = math.max(prior.spread, 1e-4)
		local salience = math.abs(want) / width
		if salience < 1 or math.abs(want) < FLOOR * width then
			continue
		end
		table.insert(out, {
			reading = reading,
			subject = World.SELF,
			wanted = prior.value,
			heading = heading,
			want = want,
			amount = math.abs(want),
			spread = math.max(spread, 1e-4),
			salience = salience,
		})
	end
	table.sort(out, function(a, b)
		return a.salience > b.salience
	end)
	return out
end

local function confidenceOf(value: number, spread: number): number
	local size = math.abs(value)
	if size + spread <= 0 then
		return 0
	end
	return size / (size + spread)
end

Choose.confidenceOf = confidenceOf

-- How much of what this action does the creature does not yet know. An action it holds a wide belief
-- about has something to teach; one it is sure of has nothing. Measured against the same yardstick
-- used everywhere else for "unsure", with a floor so a creature does not fidget over options it has
-- entirely settled.
local UNSURE_SCALE = 0.5
local UNSURE_FLOOR = 0.15

function Choose.unknownOf(reg: any, state: any, action: string): number
	local worst = 0
	for index, entry in state.predicts do
		if entry.doing ~= action then
			continue
		end
		local held = state.beliefs[Predict.beliefKey(index, World.SELF)]
		local spread = if held ~= nil then held.s else entry.expr.spread
		local reading = math.clamp(spread / UNSURE_SCALE, 0, 1)
		if reading > worst then
			worst = reading
		end
	end
	return if worst < UNSURE_FLOOR then 0 else worst
end

export type Considered = {
	action: string,
	gain: number,
	ready: number, -- how far its preconditions hold, 0..1
	confidence: number,
	venture: number,
	score: number,
	passes: boolean,
	chosen: boolean,
	forKey: string?, -- the reading it was picked to serve, when that reading was a means to an end
}

-- How far an action's preconditions hold of the creature right now.
local function readyFor(reg: any, state: any, action: string): number
	local decl = reg.actions[action]
	if decl == nil or decl.requires == nil then
		return 1
	end
	return World.matches(reg, state, World.SELF, state.species.kind, decl.requires)
end

Choose.readyFor = readyFor

-- What a pattern is asking for, as a number.
local function askedFor(wanted: any): number?
	if wanted == "high" then
		return 1
	elseif wanted == "low" then
		return 0
	elseif type(wanted) == "number" then
		return wanted
	end
	return nil
end

-- The wants a blocked action creates. *I want to eat, eating needs me holding something, so now I
-- want to be holding something* -- and from there nothing is different: an ordinary want, served by
-- whichever action the creature predicts will raise it. That is the whole of chaining. It inherits
-- the spread of the preference it serves, so a means is exactly as urgent as its end.
local function needs(reg: any, state: any, missing: any, from: Error, seen: { [string]: boolean }): { Error }
	local out: { Error } = {}
	for key, wanted in pairs(missing) do
		if key == "kind" or seen[key] then
			continue
		end
		local target = askedFor(wanted)
		if target == nil then
			continue
		end
		local heading, spread = Predict.project(reg, state, World.SELF, state.species.kind, key, nil)
		if heading == nil then
			continue
		end
		local want = target - heading
		local width = math.max(from.spread, 1e-4)
		if math.abs(want) < FLOOR * width then
			continue -- already near enough; this link is not what is stopping it
		end
		table.insert(out, {
			reading = key,
			subject = World.SELF,
			wanted = target,
			heading = heading,
			want = want,
			amount = math.abs(want),
			spread = math.max(spread, 1e-4),
			salience = math.abs(want) / width,
		})
	end
	table.sort(out, function(a, b)
		return a.salience > b.salience
	end)
	return out
end

function Choose.pick(
	reg: any,
	state: any,
	errors: { Error },
	depth: number?,
	seen: { [string]: boolean }?
): (string?, { Considered })
	local considered: { Considered } = {}
	if #errors == 0 then
		return nil, considered
	end

	local attention = math.max(1, math.floor(state.dial("attention") * 4 + 0.5))
	local caution = math.clamp(state.dial("caution"), 0, 0.98)
	local best: Considered? = nil

	-- The best thing it cannot do yet, and what is stopping it.
	local stuck: { worth: number, missing: any, from: Error }? = nil

	for rank = 1, math.min(attention, #errors) do
		local err = errors[rank]

		-- Where it is heading if it does nothing. Everything is measured against this.
		local idle = Predict.project(reg, state, err.subject, state.species.kind, err.reading, nil)
		local idleMiss = math.abs(err.wanted - (idle or err.heading))

		for _, action in state.actionOrder do
			local heading, spread =
				Predict.project(reg, state, err.subject, state.species.kind, err.reading, action)
			if heading == nil then
				continue
			end
			local whole = idleMiss - math.abs(err.wanted - heading)
			local ready = readyFor(reg, state, action)

			-- What is being left on the table for want of the preconditions. An action that would
			-- help a great deal and cannot be done yet is exactly what a chain is for.
			if whole > 0 and ready < 1 then
				local worth = whole * (1 - ready)
				if stuck == nil or worth > stuck.worth then
					stuck = { worth = worth, missing = reg.actions[action].requires, from = err }
				end
			end
			if ready <= 0 then
				continue -- it cannot be done at all, so it is not on offer
			end

			local gain = whole * ready

			-- What trying it would teach. This is what stops "worth nothing" being a life sentence:
			-- without it an action believed useless is never picked, so never tested, so the belief
			-- that killed it can never be revised.
			local unknown = Choose.unknownOf(reg, state, action)
			local venture = unknown * state.dial("venture") * math.min(err.amount, 1) * ready

			if gain <= 0 and venture <= 0 then
				continue
			end

			local confidence = confidenceOf(gain, math.max(spread, 1e-4))
			-- An experiment does not have to clear caution, because it is not claiming it will work.
			local passes = confidence >= caution or venture > 0
			local row: Considered = {
				action = action,
				gain = gain,
				ready = ready,
				confidence = confidence,
				venture = venture,
				score = gain * confidence + venture,
				passes = passes,
				chosen = false,
				forKey = if depth ~= nil then err.reading else nil,
			}
			table.insert(considered, row)
			if not passes then
				continue
			end
			if best == nil or row.score > best.score then
				best = row
			end
		end

		if best ~= nil then
			break
		end
	end

	-- Nothing it can do serves what it wants -- but something it cannot do yet would. So it wants the
	-- precondition instead, and asks the same question again. `patience` is how far it will follow
	-- that back before giving up, which is the difference between a creature that fetches a tool and
	-- one that only ever reaches for the food.
	if best == nil and stuck ~= nil then
		local left = depth or math.floor(state.dial("patience") * 3 + 1e-9)
		if left > 0 then
			local walked = if seen ~= nil then table.clone(seen) else {}
			for _, err in errors do
				walked[err.reading] = true
			end
			local onward = needs(reg, state, stuck.missing, stuck.from, walked)
			if #onward > 0 then
				local chosen, more = Choose.pick(reg, state, onward, left - 1, walked)
				for _, row in more do
					table.insert(considered, row)
				end
				if chosen ~= nil then
					return chosen, considered
				end
			end
		end
	end

	if best == nil then
		return nil, considered
	end

	-- Sticking with what it is already doing, unless something is clearly better. `commitment` is in
	-- the same units as `score`, so it has to be set against the scale the world actually produces.
	local holding = state.doing
	if holding ~= nil and holding ~= best.action then
		local incumbent: Considered? = nil
		for _, row in considered do
			if row.action == holding then
				incumbent = row
				break
			end
		end
		if incumbent ~= nil and best.score < incumbent.score + state.dial("commitment") then
			incumbent.chosen = true
			return holding, considered
		end
	end

	best.chosen = true
	return best.action, considered
end

return Choose
