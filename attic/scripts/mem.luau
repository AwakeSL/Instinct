--!strict
-- What an episode actually costs, measured rather than guessed.
--
-- Luau cannot be told to collect, so a single creature is lost in the noise.
-- Instead: a hundred creatures per condition, differing only in `retention`.
-- The gap between the two heaps is the episode buffers and very little else.

local Instinct = require("../next")

local READINGS = 8
local HERD = 100
local TICKS = 300

local function build(retention: number): (any, { any })
	local i = Instinct.new():defaults()
	i:sense("sight", {})
	i:sense("body", {})
	i:reading("integrity", { from = "body" })
	local forms: { string } = { "integrity" }
	for n = 1, READINGS do
		i:reading(("r%d"):format(n), { from = "sight" })
		table.insert(forms, ("r%d"):format(n))
	end
	i:kind("thing")
	i:species("prey", {
		senses = { sight = {}, body = {} },
		forms = forms,
		wants = { integrity = { 1.0, spread = 0.05 } },
		predicts = {
			{ about = "thing", of = "self", changes = { integrity = { -0.2, spread = 0.2 } }, after = 1 },
		},
		dials = { retention = retention, ingenuity = 0, adaptability = 0.5 },
	})
	local herd: { any } = {}
	for _ = 1, HERD do
		table.insert(herd, i:spawn("prey"))
	end
	return i, herd
end

local function live(i: any, herd: { any })
	local integrity = 1.0
	for clock = 1, TICKS do
		local raw: { [string]: number } = {}
		for n = 1, READINGS do
			raw[("r%d"):format(n)] = (clock * n % 17) / 17
		end
		for _, who in herd do
			i:perceive(who, {
				{ via = "body", raw = { integrity = integrity } },
				{ subject = "beast", kind = "thing", via = "sight", raw = raw },
			}, clock)
			i:tick(who, 1, clock)
		end
		integrity -= 0.002
	end
end

local function heap(): number
	return collectgarbage("count") * 1024
end

local Acquire = require("../next/Acquire")

local kept: { any } = {}
local marks: { { room: number, held: number, cost: number } } = {}

-- The baseline matters. Both herds are kept alive, so the heap after the second
-- one includes the first -- and without subtracting each herd's own cost from
-- the one before it, the creature structures get charged to the episodes.
local baseline = heap()
local last = baseline

for _, retention in { 0.0, 1.0 } do
	local i, herd = build(retention)
	live(i, herd)
	table.insert(kept, i) -- hold a reference so nothing is collected out from under us

	local state = (i :: any).state[herd[1]]
	local episodes = 0
	for _, run in state.episodes do
		episodes += #run
	end
	local now = heap()
	local cost = now - last
	last = now
	table.insert(marks, { room = Acquire.room(state), held = episodes, cost = cost })
	print(("retention %.1f -> room %d, %d episodes each, this herd cost %.2f MB (%.0f KB per creature)"):format(
		retention, Acquire.room(state), episodes, cost / 1048576, cost / HERD / 1024))
end

local a, b = marks[1], marks[2]
local perEpisode = (b.cost - a.cost) / (HERD * (b.held - a.held))
local perCreature = a.cost / HERD - perEpisode * a.held
print("")
print(("a creature itself, before any episodes: %.1f KB"):format(perCreature / 1024))
print(("one episode of %d readings: %.0f bytes"):format(READINGS, perEpisode))
print(("200 episodes, one prediction, one subject: %.0f KB"):format(perEpisode * 200 / 1024))
print(("8 predictions x 5 subjects x 200: %.1f MB per creature"):format(
	perEpisode * 200 * 8 * 5 / 1048576))
