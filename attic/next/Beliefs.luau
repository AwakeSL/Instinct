--!strict
--!native

local Beliefs = {}

export type Held = { v: number, s: number, n: number, from: string, parent: string?, toward: number?, seen: number }

local MIN_SPREAD = 1e-3

function Beliefs.new(): { [string]: Held }
	return {}
end

function Beliefs.key(kind: string, name: string, role: string, quantity: string): string
	return ("%s|%s|%s|%s"):format(kind, name, role, quantity)
end

function Beliefs.hold(
	store: { [string]: Held },
	key: string,
	priorValue: number,
	priorSpread: number,
	from: string,
	parent: string?
): Held
	local held = store[key]
	if held == nil then
		held = {
			v = priorValue,
			s = math.max(priorSpread, MIN_SPREAD),
			n = 0,
			from = from,
			parent = parent,
			toward = nil,
			seen = 0,
		}
		store[key] = held
	end
	return held
end

function Beliefs.rateFor(grudge: number): number
	local halfLife = 5 * math.pow(10, 2.5 * math.clamp(grudge, 0, 1))
	return 0.6931 / halfLife
end

function Beliefs.forget(store: { [string]: Held }, now: number, rate: number, inView: { [string]: boolean })
	for key, held in pairs(store) do
		if inView[key] then
			continue
		end
		local gone = now - held.seen
		if gone <= 0 then
			continue
		end
		if held.toward ~= nil then
			Beliefs.relax(held, held.toward :: number, 0.5, rate, gone)
			held.seen = now
			continue
		end
		local parent = held.parent
		if parent == nil then
			continue
		end
		local toward = store[parent]
		if toward == nil then
			continue
		end
		Beliefs.relax(held, toward.v, toward.s, rate, gone)
		held.seen = now
	end
end

function Beliefs.read(store: { [string]: Held }, key: string): Held?
	return store[key]
end

function Beliefs.surprise(held: Held, observed: number): number
	return math.abs(observed - held.v) / math.max(held.s, MIN_SPREAD)
end

function Beliefs.update(held: Held, observed: number, observedSpread: number, adaptability: number): number
	-- Nothing at all is learned from a number that is not one. A sense handing over a NaN would
	-- otherwise poison the belief permanently: every operation afterwards produces another NaN, and no
	-- later evidence can wash it out.
	if observed ~= observed or observed == math.huge or observed == -math.huge then
		return 0
	end
	local os = math.max(observedSpread, MIN_SPREAD)
	local s = math.max(held.s, MIN_SPREAD)
	local surprise = math.abs(observed - held.v) / s

	local gain = 0.25 + adaptability * 1.5
	local prior = 1 / (s * s)
	local evidence = gain / (os * os)

	local total = prior + evidence
	local moved = (held.v * prior + observed * evidence) / total
	local narrowed = math.sqrt(1 / total)

	local shaken = math.clamp((surprise - 2) / 4, 0, 1)
	local widened = math.max(narrowed, math.abs(observed - held.v) * shaken)

	held.v = moved
	held.s = math.max((1 - shaken) * narrowed + shaken * widened, MIN_SPREAD)
	held.n += 1
	return surprise
end

function Beliefs.relax(held: Held, towardValue: number, towardSpread: number, rate: number, dt: number)
	if rate <= 0 or dt <= 0 then
		return
	end
	local pull = 1 - math.exp(-rate * dt)
	held.v += (towardValue - held.v) * pull
	held.s += (math.max(towardSpread, MIN_SPREAD) - held.s) * pull
end

function Beliefs.confidence(held: Held): number
	local size = math.abs(held.v)
	if size + held.s <= 0 then
		return 0
	end
	return size / (size + held.s)
end

return Beliefs
