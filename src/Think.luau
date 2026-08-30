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
		local want = prior.value - held
		if want == 0 then
			continue
		end
		local spread = math.max(prior.spread, 1e-4) / state.precision(quantity)
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
			after = 0,
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

function Think.cancelsSelf(reg: Registry.Registry, state: any, action: Registry.Action, err: Error, look: (string) -> (number?, number)): (number, number)
	local total, spread = 0, 0
	for _, predicted in action.predicts do
		if predicted.of ~= "self" or predicted.quantity ~= err.quantity then
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
