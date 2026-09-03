--!strict
--!native

local Registry = require("./Registry")
local Values = require("./Values")
local Percepts = require("./Percepts")

local Think = {}

export type Error = {
	of: string,
	quantity: string,
	want: number,
	amount: number,
	spread: number,
	salience: number,
	subject: any,
	after: number,
	kind: string?,
}

local function confidenceOf(value: number, spread: number): number
	local size = math.abs(value)
	if size + spread <= 0 then
		return 0
	end
	return size / (size + spread)
end

Think.confidenceOf = confidenceOf

local function urgency(after: number): number
	return math.exp(-math.max(after, 0) / 30)
end

local FLOOR = 1.0

Think.FLOOR = FLOOR

local function priorOf(state: any, quantity: string): (number, number)
	local prior = state.expects[quantity]
	if prior == nil then
		return 0, 1
	end
	return prior.value, math.max(prior.spread, 1e-4)
end

function Think.selfErrors(state: any, out: { Error })
	for quantity, prior in state.expects do
		local held = state.level[quantity]
		if held == nil then
			continue
		end

		-- With a horizon, the need is measured against where the creature is HEADING rather than
		-- where it is, projected along its own believed drift. The projection carries that belief's
		-- uncertainty, widened by how far ahead it reaches: being unsure how fast you empty makes a
		-- distant forecast worth very little, and a wide enough one falls under the salience floor
		-- and is ignored. So foresight is not switched on -- it sharpens as the creature learns its
		-- own body, and reaches less far the less certain it is.
		local after = prior.after or 0
		local looking = held
		local spread = prior.spread
		if after > 0 then
			local drift = state.beliefs[("drift|%s"):format(quantity)]
			if drift ~= nil then
				looking = math.clamp(held + drift.v * after, 0, 1)
				spread = math.sqrt(spread * spread + (drift.s * after) * (drift.s * after))
			end
		end

		local want = prior.value - looking
		if want == 0 then
			continue
		end
		spread = math.max(spread, 1e-4) / state.precision(quantity)
		local salience = math.abs(want) / spread
		if salience < FLOOR then
			continue
		end
		table.insert(out, {
			of = "self",
			quantity = quantity,
			want = want,
			amount = math.abs(want),
			spread = spread,
			salience = salience,
			subject = nil,
			after = after,
			kind = nil,
		})
	end
end

function Think.beliefFor(state: any, about: string, predicted: any, subject: any): any
	local Beliefs = state.beliefs
	local kindKey = ("kind|%s|%s|%s"):format(about, predicted.of, predicted.quantity)
	local kindHeld = state.hold(kindKey, predicted.expr.const or 0, predicted.expr.spread, "instinct")
	if subject == nil then
		return kindHeld, kindKey
	end
	local _ = Beliefs
	local subKey = ("subject|%s|%s|%s|%s"):format(tostring(subject), about, predicted.of, predicted.quantity)
	return state.hold(subKey, kindHeld.v, kindHeld.s, "kind:" .. about, kindKey), subKey
end

function Think.predictedErrors(reg: Registry.Registry, state: any, per: Percepts.Percepts, out: { Error })
	for _, view in per.views do
		for pass = 1, 2 do
			local source = if pass == 1 then state.instinct else state.learned
			for _, entry in source do
				if not Percepts.isKind(per, view, entry.about) then
					continue
				end
				for _, predicted in entry.predicts do
					local held, key = Think.beliefFor(state, entry.about, predicted, view.subject)
					local delta, spread = Values.resolve(reg, predicted.expr, function(name: string)
						return Percepts.read(per, view, name)
					end, held.v, held.s)
					if delta ~= nil then
						state.expect(key, held, predicted, view.subject, delta)
					end
					if delta == nil or delta >= 0 then
						continue
					end
					local worsening = -delta
					if worsening < 1e-6 then
						continue
					end
					local _, rawPrior = priorOf(state, predicted.quantity)
					local priorSpread = rawPrior / state.precision(predicted.quantity)
					local after = predicted.after or 0
					local weight = confidenceOf(delta, spread) * urgency(after) * view.confidence
					local salience = (worsening / priorSpread) * weight
					if salience < FLOOR then
						continue
					end
					table.insert(out, {
						of = predicted.of,
						quantity = predicted.quantity,
						want = worsening,
						amount = worsening,
						spread = spread,
						salience = salience,
						subject = view.subject,
						after = after,
						kind = view.kind,
					})
				end
			end
		end
	end
end

function Think.rank(errors: { Error })
	table.sort(errors, function(a, b)
		if a.salience ~= b.salience then
			return a.salience > b.salience
		end
		return a.quantity < b.quantity
	end)
end

local function partsFree(state: any, action: Registry.Action): boolean
	local busy = if state.doing ~= nil and state.doing ~= action.name then state.busy else nil
	for partName, count in action.occupies do
		local have = state.parts[partName]
		if have == nil then
			return false
		end
		if busy ~= nil then
			have -= (busy[partName] or 0)
		end
		if have < count then
			return false
		end
	end
	return true
end

Think.partsFree = partsFree

local function flagged(view: Percepts.View, key: string): boolean
	local held = view.raw[key]
	if held == true then
		return true
	end
	return type(held) == "number" and held > 0
end

function Think.resolveTarget(
	state: any,
	per: Percepts.Percepts,
	action: Registry.Action,
	preferred: any
): (any, string?)
	local needKey: string? = nil
	local needKind: string? = nil
	for key, want in action.requires do
		if key == "holding" then
			if not state.holding[want] then
				return nil, "holding"
			end
		elseif needKey == nil then
			needKey, needKind = key, want
		end
	end

	if needKey == nil then
		return preferred, nil
	end

	if preferred ~= nil then
		local view = per.bySubject[preferred]
		if view ~= nil and Percepts.isKind(per, view, needKind :: string) then
			return preferred, if flagged(view, needKey :: string) then nil else needKey
		end
	end

	local fallback: any = nil
	for _, view in per.views do
		if not Percepts.isKind(per, view, needKind :: string) then
			continue
		end
		if flagged(view, needKey :: string) then
			return view.subject, nil
		end
		if fallback == nil then
			fallback = view.subject
		end
	end

	if fallback ~= nil then
		return fallback, needKey
	end
	return nil, needKey
end

-- The predictions actually in play for an action: what the action itself authored, overlaid
-- with what this creature's species `believes` about it. A `believes` entry replaces the
-- action's entry for the same (of, quantity) and is otherwise added -- which is how an action
-- that predicts nothing on its own, like `vocalise`, can still predict relief from grief.
-- Merged once per creature and cached, since neither side changes after spawn.
function Think.predictsOf(state: any, action: Registry.Action): { any }
	local cached = state.actionPredicts[action.name]
	if cached ~= nil then
		return cached
	end
	local believed = state.believes[action.name]
	local merged: { any }
	if believed == nil or #believed == 0 then
		merged = action.predicts
	else
		merged = {}
		local slotOf: { [string]: number } = {}
		for _, predicted in action.predicts do
			table.insert(merged, predicted)
			slotOf[predicted.of .. "|" .. predicted.quantity] = #merged
		end
		for _, predicted in believed do
			local at = slotOf[predicted.of .. "|" .. predicted.quantity]
			if at ~= nil then
				merged[at] = predicted
			else
				table.insert(merged, predicted)
				slotOf[predicted.of .. "|" .. predicted.quantity] = #merged
			end
		end
	end
	state.actionPredicts[action.name] = merged
	return merged
end

-- `when` narrows a belief to a circumstance. Only `target = "blamed"` is defined; a prediction
-- carrying any other condition does not apply rather than applying unconditionally, so an
-- unrecognised condition can never make a creature act on something it never meant.
function Think.whenHolds(state: any, predicted: any, target: any): boolean
	local when = predicted.when
	if when == nil then
		return true
	end
	if when.target == "blamed" then
		return target ~= nil and state.blamed == target
	end
	return false
end

function Think.actionBelief(state: any, action: Registry.Action, predicted: any): (any, string)
	local key = ("action|%s|%s|%s"):format(action.name, predicted.of, predicted.quantity)
	local spread = predicted.expr.spread
	if action.skill ~= nil then
		local believed = state.selfImage[action.skill] or state.selfImage.skill
		local level = if believed ~= nil then believed.value else state.skills[action.skill]
		spread /= math.clamp(if level ~= nil then level else 0.05, 0.05, 1)
	end
	return state.hold(key, predicted.expr.const or 0, spread, "action:" .. action.name), key
end

function Think.cancelsSelf(
	reg: Registry.Registry,
	state: any,
	action: Registry.Action,
	err: Error,
	look: (string) -> (number?, number),
	target: any
): (number, number)
	local total, spread = 0, 0
	for _, predicted in Think.predictsOf(state, action) do
		if predicted.of ~= "self" or predicted.quantity ~= err.quantity then
			continue
		end
		if not Think.whenHolds(state, predicted, target) then
			continue
		end
		local held = Think.actionBelief(state, action, predicted)
		local delta, ds = Values.resolve(reg, predicted.expr, look, held.v, held.s)
		if delta == nil or delta == 0 then
			continue
		end
		if (delta > 0) ~= (err.want > 0) then
			continue
		end
		total += math.min(math.abs(delta), err.amount)
		spread = math.sqrt(spread * spread + ds * ds)
	end
	return total, spread
end

function Think.cancelsThreat(
	reg: Registry.Registry,
	state: any,
	per: Percepts.Percepts,
	action: Registry.Action,
	err: Error,
	target: any
): (number, number)
	if target == nil then
		return 0, 0
	end
	local view = per.bySubject[target]
	if view == nil then
		return 0, 0
	end

	local override: { [string]: number } = {}
	local touched = false
	local trust = 0
	for _, predicted in action.predicts do
		if predicted.of ~= "target" then
			continue
		end
		local held = Think.actionBelief(state, action, predicted)
		local delta, ds = Values.resolve(reg, predicted.expr, function(name: string)
			return Percepts.read(per, view, name)
		end, held.v, held.s)
		if delta == nil then
			continue
		end
		trust = math.max(trust, ds)
		local current = Percepts.read(per, view, predicted.quantity)
		if current == nil then
			continue
		end
		override[predicted.quantity] = math.clamp(current + delta, 0, 1)
		touched = true
	end
	if not touched then
		return 0, 0
	end

	local function look(name: string): (number?, number)
		local forced = override[name]
		if forced ~= nil then
			return forced, 0
		end
		return Percepts.read(per, view, name)
	end

	local before, after = 0, 0
	local spread = 0
	for _, entry in state.instinct do
		if not Percepts.isKind(per, view, entry.about) then
			continue
		end
		for _, predicted in entry.predicts do
			if predicted.of ~= err.of or predicted.quantity ~= err.quantity then
				continue
			end
			local was, ws = Values.resolve(reg, predicted.expr, function(name: string)
				return Percepts.read(per, view, name)
			end)
			local now = Values.resolve(reg, predicted.expr, look)
			if was ~= nil and now ~= nil then
				before += math.max(-was, 0)
				after += math.max(-now, 0)
				spread = math.sqrt(spread * spread + ws * ws)
			end
		end
	end

	local gained = before - after
	if gained <= 0 then
		return 0, 0
	end
	return math.min(gained, err.amount), math.sqrt(spread * spread + trust * trust)
end

-- How much the creature does not know about what this action does, as 0..1: the widest spread it
-- holds on any of the action's own predictions, against the same yardstick Emotions measures
-- novelty by, so "unsure" means the same thing wherever the package says it.
--
-- Deliberately not measured against the AUTHORED spread. That reads 1 for every belief the moment
-- it is created, so a creature would find everything equally mysterious and the term would say
-- nothing. What matters is how loosely the belief is held now, full stop.
local UNSURE_SCALE = 0.5

-- Below this an option counts as known, and is not worth an experiment. Without a floor any spread
-- at all reads as a little bit unknown, so a venturing creature would fidget forever over options
-- it has entirely settled. Same shape as the rule that an error inside its own spread is not
-- evidence: uncertainty too small to matter is not uncertainty.
local UNSURE_FLOOR = 0.15

function Think.unknownOf(state: any, action: Registry.Action): number
	local worst = 0
	for _, predicted in Think.predictsOf(state, action) do
		local key = ("action|%s|%s|%s"):format(action.name, predicted.of, predicted.quantity)
		local held = state.beliefs[key]
		local spread = if held ~= nil then held.s else predicted.expr.spread
		local reading = math.clamp(spread / UNSURE_SCALE, 0, 1)
		if reading > worst then
			worst = reading
		end
	end
	return if worst < UNSURE_FLOOR then 0 else worst
end

function Think.costPressure(state: any, action: Registry.Action): number
	local pressure = 0
	for quantity, amount in action.costs do
		local prior = state.expects[quantity]
		if prior == nil then
			continue
		end
		local held = state.level[quantity]
		if held == nil then
			continue
		end
		local afterwards = held - amount
		local shortfall = prior.value - afterwards
		local already = math.max(prior.value - held, 0)
		local added = math.max(shortfall, 0) - already
		local spreads = added / math.max(prior.spread, 1e-4)
		if spreads >= FLOOR then
			pressure += spreads
		end
	end
	return pressure
end

function Think.threshold(state: any, downside: number): number
	local base = state.dial("caution", { downside = downside })
	return math.clamp(base, 0, 0.98)
end

return Think
