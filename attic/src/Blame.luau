--!strict

local Blame = {}

local WINDOW = 12

local Percepts = require("./Percepts")

function Blame.remember(state: any, per: any, now: number, capacity: number)
	local room = 2 + math.floor(capacity * WINDOW)
	for _, view in per.views do
		if view.subject == nil or view.kind == nil then
			continue
		end
		local found = nil
		for _, row in state.recent do
			if row.subject == view.subject then
				found = row
				break
			end
		end
		local saw: { [string]: number } = {}
		for featureName in pairs(state.forms) do
			local reading = Percepts.read(per, view, featureName)
			if reading ~= nil then
				saw[featureName] = reading
			end
		end
		if found ~= nil then
			found.at = now
			found.saw = saw
			continue
		end
		table.insert(state.recent, { subject = view.subject, kind = view.kind, at = now, saw = saw })
	end
	while #state.recent > room do
		local oldest, oldestAt = 1, math.huge
		for index, row in state.recent do
			if row.at < oldestAt then
				oldest, oldestAt = index, row.at
			end
		end
		table.remove(state.recent, oldest)
	end
end

function Blame.unexplained(state: any, now: number): { any }
	local found: { any } = {}
	for quantity, level in pairs(state.level) do
		local prior = state.expects[quantity]
		local was = state.wasLevel[quantity]
		state.wasLevel[quantity] = level
		if prior == nil or was == nil then
			continue
		end
		local dropped = was - level
		if dropped <= 0 then
			continue
		end
		if dropped / math.max(prior.spread, 1e-4) < 1 then
			continue
		end
		local covered = false
		for _, row in state.pending do
			if row.quantity == quantity then
				covered = true
				break
			end
		end
		if covered then
			continue
		end
		table.insert(found, { quantity = quantity, amount = dropped, at = now })
	end
	return found
end

function Blame.pin(state: any, event: any, now: number, reach: number): any
	local best, bestAt = nil, -math.huge
	for _, row in state.recent do
		if now - row.at > reach then
			continue
		end
		if row.at > bestAt then
			best, bestAt = row, row.at
		end
	end
	return best
end

function Blame.residual(state: any, key: string, surprise: number)
	local held = state.residual[key]
	if held == nil then
		held = { n = 0, total = 0 }
		state.residual[key] = held
	end
	held.n += 1
	held.total += surprise
end

function Blame.stuck(state: any, key: string, insight: number): boolean
	local held = state.residual[key]
	if held == nil then
		return false
	end
	local needed = 2 + math.floor((1 - math.clamp(insight, 0, 1)) * 10)
	return held.n >= needed and (held.total / held.n) > 2
end

return Blame
