--!strict

local Emotions = {}

local function matches(from: any, err: any, efficacy: number): number
	if from.of ~= nil and from.of ~= err.of then
		return 0
	end
	if from.quantity ~= nil and from.quantity ~= err.quantity then
		return 0
	end
	if from.falling == true and err.after == nil then
		return 0
	end

	local want = from.efficacy
	if want == "low" and efficacy >= 0.33 then
		return 0
	end
	if want == "high" and efficacy < 0.33 then
		return 0
	end
	if want == "none" and efficacy > 0.05 then
		return 0
	end

	return math.clamp(err.salience / 6, 0, 1)
end

function Emotions.novelty(state: any, per: any, errors: { any }): number
	local loudest: { [string]: number } = {}
	for _, err in errors do
		if err.subject == nil then
			continue
		end
		local key = tostring(err.subject)
		if (loudest[key] or 0) < err.salience then
			loudest[key] = err.salience
		end
	end

	local best = 0
	for _, view in per.views do
		if view.subject == nil then
			continue
		end
		local key = tostring(view.subject)
		if (loudest[key] or 0) >= 1 then
			continue
		end
		local widest = 0
		local mark = ("subject|%s"):format(key)
		for name, held in pairs(state.beliefs) do
			if name:find(mark, 1, true) and held.s > widest then
				widest = held.s
			end
		end
		if widest == 0 and state.beliefs[("presence|%s"):format(key)] ~= nil then
			widest = 0.35
		end
		local reading = math.clamp(widest / 0.5, 0, 1)
		if reading > best then
			best = reading
		end
	end
	return best
end

function Emotions.settle(reg: any, state: any, errors: { any }, efficacy: number, dt: number, novelty: number)
	if dt <= 0 then
		return
	end
	for _, name in state.feels do
		local decl = reg.emotions[name]
		if decl == nil then
			continue
		end
		local target = 0
		if decl.from.spread == "high" then
			target = novelty
		else
			for _, err in errors do
				local reading = matches(decl.from, err, efficacy)
				if reading > target then
					target = reading
				end
			end
		end
		local held = state.level[name] or 0
		if target > held then
			held = target
		else
			held += (target - held) * math.clamp(decl.decays * dt, 0, 1)
		end
		state.level[name] = math.clamp(held, 0, 1)
	end
end

function Emotions.scale(reg: any, state: any, dialName: string, base: number): number
	local out = base
	for _, name in state.feels do
		local level = state.level[name]
		if level == nil or level <= 0 then
			continue
		end
		local decl = reg.emotions[name]
		if decl == nil then
			continue
		end
		local factor = decl.modulates[dialName]
		if type(factor) == "number" then
			out *= 1 + (factor - 1) * level
		end
	end
	return out
end

function Emotions.precision(reg: any, state: any, quantity: string): number
	local out = 1
	for _, name in state.feels do
		local level = state.level[name]
		if level == nil or level <= 0 then
			continue
		end
		local decl = reg.emotions[name]
		if decl == nil or type(decl.modulates.precision) ~= "table" then
			continue
		end
		local factor = decl.modulates.precision[quantity]
		if type(factor) == "number" then
			out *= 1 + (factor - 1) * level
		end
	end
	return math.max(out, 0.05)
end

return Emotions
