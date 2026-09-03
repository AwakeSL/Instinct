--!strict
-- Projection and learning.
--
-- A prediction says: given these circumstances, this reading will be so, that long from now. What
-- makes it a prediction rather than a rule is that its number is a belief -- authored as an opening
-- position, revised every time the horizon comes due and the world says otherwise.
--
-- Several predictions bear on one reading at once and they do not compete. Changes **add**: a wolf
-- costing 0.3 and a wound costing 0.2 is expecting to lose 0.5. Levels **merge by precision**: two
-- guesses of 10 and 12 do not make 22, and the one held more tightly wins. A narrower condition
-- **overrides** the ones it refines -- instead of them, not added to them -- but only once it is held
-- more tightly than they are, which being rarer it takes longer to earn.

local Beliefs = require("./Beliefs")
local Values = require("./Values")
local World = require("./World")

local Predict = {}

-- How much of the belief must survive its conditions before the creature will be held to it.
--
-- A prediction scaled to almost nothing claims almost nothing, and the outcome is divided by that
-- scale to get back into the belief's own terms -- so a claim scaled to a thousandth turns an ordinary
-- moment into a thousandfold surprise. Left unguarded that is a genuine runaway: the belief overshoots,
-- which shrinks the next scale, which amplifies harder, and within a minute the belief is at 1e100 and
-- then NaN, and the creature is broken for good. Below this the prediction simply is not filed.
local FAINT = 0.05

local function beliefKey(index: number, subject: any): string
	return ("pred|%d|%s"):format(index, tostring(subject))
end

Predict.beliefKey = beliefKey

-- The creature's own belief about what this prediction is worth, for this subject. Authored value is
-- the opening position; everything after is experience.
local function heldFor(state: any, index: number, entry: any, subject: any): any
	return Beliefs.hold(
		state.beliefs,
		beliefKey(index, subject),
		entry.expr.const or 0,
		math.max(entry.expr.spread, 1e-3),
		"predicted"
	)
end

Predict.heldFor = heldFor

export type Bearing = {
	index: number,
	entry: any,
	subject: any,
	where: any, -- the thing the condition was judged against, which need not be the target
	value: number,
	spread: number,
	weight: number, -- how well the condition holds, 0..1
	narrowness: number,
}

-- Everything the creature currently predicts about one reading of one subject.
--
-- The condition and the target need not be the same thing. *A wolf predicts harm to me* is judged
-- against the wolf and lands on the creature, so a prediction about `self` is checked once for every
-- thing whose presence might bring it about -- and two wolves are twice the trouble, with nothing
-- said about wolves in particular.
function Predict.bearingOn(
	reg: any,
	state: any,
	subject: any,
	kind: string?,
	reading: string,
	doing: string?,
	within: number?
): { Bearing }
	local out: { Bearing } = {}
	for index, entry in state.predicts do
		if entry.reading ~= reading then
			continue
		end
		if entry.doing ~= nil and entry.doing ~= doing then
			continue
		end
		-- Asked what will be true within so long, only what comes due by then has anything to say.
		if within ~= nil and entry.after > within then
			continue
		end

		local target = if entry.of == "self" then World.SELF else subject
		if target ~= subject then
			continue
		end

		-- Where the condition is judged: the creature itself when nothing is named, otherwise every
		-- thing it is tracking that might answer to the description. Kept as pairs, because a subject
		-- of no known kind is a perfectly ordinary thing and must not slide the list out of step.
		local wheres: { { subject: any, kind: string? } } = {}
		if entry.of ~= "self" or entry.about == nil then
			if entry.of == "self" then
				table.insert(wheres, { subject = World.SELF, kind = state.species.kind })
			else
				table.insert(wheres, { subject = subject, kind = kind })
			end
		else
			for handle, track in state.tracked do
				if handle:find("|kind", 1, true) then
					continue
				end
				table.insert(wheres, { subject = track, kind = state.tracked[handle .. "|kind"] })
			end
		end

		for _, at in wheres do
			local where = at.subject
			local weight = World.matches(reg, state, where, at.kind, entry.about)
			if weight <= 0 then
				continue
			end

			local held = heldFor(state, index, entry, subject)
			local value, spread = Values.resolve(reg, entry.expr, function(name: string)
				return World.read(reg, state, where, name)
			end, held.v, held.s)
			if value == nil then
				continue
			end

			table.insert(out, {
				index = index,
				entry = entry,
				subject = subject,
				where = where,
				value = value,
				spread = spread,
				weight = weight,
				narrowness = World.narrowness(entry.about),
			})
		end
	end
	return out
end

-- Where a reading is heading: what it reads now, plus every change, merged with every level.
--
-- Refinement first: a narrower condition displaces the broader ones it refines, so an interaction --
-- *wolf and bleeding together* -- replaces the sum of its parts rather than piling onto it. Only once
-- it is held more tightly, which rarity delays, exactly as the specificity argument requires.
function Predict.project(
	reg: any,
	state: any,
	subject: any,
	kind: string?,
	reading: string,
	doing: string?,
	within: number?
): (number?, number)
	local bearing = Predict.bearingOn(reg, state, subject, kind, reading, doing, within)
	if #bearing == 0 then
		return World.read(reg, state, subject, reading)
	end

	local widest = 0
	for _, one in bearing do
		if one.narrowness > widest then
			widest = one.narrowness
		end
	end

	-- Keep the narrowest that is also held tightly enough to have earned the right to speak for the
	-- broader ones. Otherwise everything applicable contributes.
	local ruling: { Bearing } = {}
	for _, one in bearing do
		if one.narrowness == widest then
			table.insert(ruling, one)
		end
	end
	local sharp = 0
	for _, one in ruling do
		sharp += one.spread
	end
	local blunt, broadCount = 0, 0
	for _, one in bearing do
		if one.narrowness < widest then
			blunt += one.spread
			broadCount += 1
		end
	end
	local using = bearing
	if widest > 0 and broadCount > 0 and (sharp / #ruling) < (blunt / broadCount) then
		using = ruling
	end

	local now, nowSpread = World.read(reg, state, subject, reading)
	local total = now or 0
	local variance = (nowSpread or 0) ^ 2

	local levelValue, levelWeight = 0, 0
	for _, one in using do
		if one.entry.form == "change" then
			total += one.value * one.weight
			variance += (one.spread * one.weight) ^ 2
		else
			-- precision-weighted: the tighter belief dominates
			local precision = one.weight / math.max(one.spread * one.spread, 1e-6)
			levelValue += one.value * precision
			levelWeight += precision
		end
	end

	if levelWeight > 0 then
		local merged = levelValue / levelWeight
		local mergedSpread = math.sqrt(1 / levelWeight)
		if now == nil then
			return merged, mergedSpread
		end
		-- a level prediction and a projected-from-change prediction are two estimates of the same
		-- future number, so they merge rather than one winning outright
		local changeSpread = math.sqrt(variance)
		local a = 1 / math.max(changeSpread * changeSpread, 1e-6)
		local b = 1 / math.max(mergedSpread * mergedSpread, 1e-6)
		return (total * a + merged * b) / (a + b), math.sqrt(1 / (a + b))
	end

	return total, math.sqrt(variance)
end

-- File what is expected, so it can be held to it. One row per belief at a time: re-predicting the
-- same thing before the last one resolved would stack duplicates and learn from each of them.
function Predict.commit(reg: any, state: any, subject: any, kind: string?, doing: string?)
	for _, one in Predict.bearingOn(reg, state, subject, kind, "", doing) do
		local _ = one
	end
end

function Predict.expect(reg: any, state: any, subject: any, kind: string?, doing: string?, readings: { string })
	for _, reading in readings do
		for _, one in Predict.bearingOn(reg, state, subject, kind, reading, doing) do
			local key = beliefKey(one.index, subject)
			local pending = state.pending[key]
			if pending ~= nil then
				continue
			end
			local was = World.read(reg, state, subject, reading)
			if was == nil then
				continue
			end
			local held = heldFor(state, one.index, one.entry, subject)
			if held.v == 0 and one.entry.form == "change" then
				continue -- nothing claimed, nothing to be held to
			end
			-- The same thought, for a claim the conditions have scaled down to nothing: a move that
			-- barely points at the food is not making a prediction about the food.
			local scale = if held.v ~= 0 then one.value / held.v else 1
			if not (math.abs(scale) >= FAINT) then
				-- Silence is itself worth counting. An idea a creature worked out for itself can end
				-- up scaling its prediction to nothing in every situation it meets, and then that
				-- prediction never speaks, never resolves, and never gathers the evidence that would
				-- let the idea be reconsidered. So a prediction that keeps having nothing to say is
				-- remembered as such, and that is grounds to give the idea up.
				state.mute[one.index] = (state.mute[one.index] or 0) + 1
				continue
			end
			state.mute[one.index] = 0
			state.pending[key] = {
				key = key,
				index = one.index,
				subject = subject,
				reading = reading,
				form = one.entry.form,
				was = was,
				-- how much of the belief the conditions scaled it by, so the observation can be
				-- divided back out and taught to the belief in its own terms
				scale = scale,
				predicted = one.value,
				at = state.now + one.entry.after,
				seenAt = state.now,
				-- what the creature could read about it when it committed, so an idea it did not
				-- have then can still be tried against the moment now
				where = one.where,
				snapshot = state.snapshot(one.where),
				before = state.lastSnapshot[tostring(one.where)],
				beforeAt = state.lastSnapshotAt[tostring(one.where)],
			}
		end
	end
end

-- The horizon has come. What the senses now say is the outcome; there is no `outcome` call, because
-- the next perception is the outcome.
function Predict.settle(reg: any, state: any): number
	local learned = 0
	for key, row in state.pending do
		if state.now < row.at then
			continue
		end
		state.pending[key] = nil

		local nowValue = World.read(reg, state, row.subject, row.reading)
		if nowValue == nil then
			continue
		end
		local held = state.beliefs[key]
		if held == nil or not (math.abs(row.scale) >= FAINT) then
			continue
		end

		local observed: number
		if row.form == "change" then
			observed = (nowValue - row.was) / row.scale
		else
			observed = nowValue / (if row.scale ~= 0 then row.scale else 1)
		end

		-- The observation's own spread scales with how much happened. A catastrophe is unambiguous
		-- and narrow; an uneventful moment is weak evidence and wide. That single asymmetry is what
		-- makes taming gradual and trauma instant, with no branch between them.
		local magnitude = math.clamp(math.abs(observed - held.v), 0, 1)
		local witness = math.max(0.05, 0.5 * (1 - magnitude))
		local surprise = Beliefs.update(held, observed, witness, state.dial("adaptability"))
		held.seen = state.now
		-- What is remembered is what happened **in the world**, not what it meant for this belief.
		-- The belief-space number is divided through by however much the conditions scaled it, and
		-- that scaling is itself part of what a search is trying to reconsider -- so remembering it
		-- would be measuring every candidate against the very idea it is meant to replace.
		state.recall(row, if row.form == "change" then nowValue - row.was else nowValue, surprise)
		learned += 1
	end
	return learned
end

-- What is not tested drifts back toward what it was born believing, and widens on the way.
--
-- This is forgetting, and it is also the only thing that makes a creature willing to reconsider. A
-- belief driven narrow and low is unfalsifiable: nothing will pick that action, so nothing will ever
-- test it, so the belief that killed it can never be revised -- `venture` cannot help, because there
-- is nothing left to find out about something one is certain of. Letting an untested belief go vague
-- again restores the doubt that makes an experiment worth running. **A creature can only reconsider
-- what it has begun to forget.**
local FORGET = 0.06

function Predict.forget(state: any, dt: number)
	local slowness = 1 - state.dial("grudge") * 0.8
	for key, held in state.beliefs do
		if key:sub(1, 5) ~= "pred|" then
			continue
		end
		if held.seen >= state.now - 1e-6 then
			continue
		end
		local index = tonumber(key:match("^pred|(%d+)|"))
		local entry = if index ~= nil then state.predicts[index] else nil
		if entry == nil then
			continue
		end
		Beliefs.relax(
			held,
			entry.expr.const or 0,
			math.max(entry.expr.spread, 1e-3),
			FORGET * slowness,
			dt
		)
	end
end

return Predict
