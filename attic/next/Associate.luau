--!strict
-- Grouping returns into things.
--
-- A **subject** is not a claim that something is an object. It is a slot keeping one set of readings
-- apart from another, which is why a noise from an unknown source gets one as readily as a wolf does.
--
-- Matching is **prediction**, not similarity. Similarity would ask *does this look like what that
-- track last reported*, and would clump every blue thing together. Prediction asks *is this what that
-- track's model said would happen* -- and for anything moving, the prediction is somewhere new, so a
-- return sitting where it used to be is a poor match however alike it looks.
--
-- The gate is the track's own spread. How near a return must fall to count as the same thing is just
-- how confident the prediction was: a track held tightly accepts only what lands close, a vague one
-- accepts a wide range. No separate parameter for it.
--
-- Nothing here is spatial. A return is matched over whatever readings it carries, and position is
-- merely an excellent discriminator in a physical world because things move continuously. Pitch does
-- as well. What a channel carries bounds what can be told apart, and two things a creature cannot
-- tell apart are one thing, to it.

local Predict = require("./Predict")
local World = require("./World")

local Associate = {}

-- Below this, the best match is not good enough and the return is something new.
local BIRTH = 0.15
-- A track nobody has reinforced in this long, whose estimates have gone vague, is collected.
local FORGOTTEN = 30

-- Average unexplained-ness at which a track stops being one thing. Above this it has been accepting
-- returns it cannot account for -- roaring when it should purr -- and the honest reading of that is
-- not a worse belief but a second animal.
--
-- How much is tolerated is `attribution`: how far a creature will go on revising what it believes
-- before it revises what it is looking at, which is exactly this decision. The count matters far less
-- than it looks -- a decaying average reaches any modest count quickly, so what actually separates a
-- credulous creature from a stubborn one is how bad an explanation it will live with.
local TORN = 0.40
local TORN_SPAN = 0.35

-- How much recent history the strain on a track is measured over. Old failures fade, so one bad match
-- never splits anything and a track that has settled down is left alone. Note that a decaying count
-- has a ceiling of 1/(1 - RECENT), and how much a creature demands must stay under it -- otherwise a
-- patient creature does not merely take longer to split, it can never split at all.
local RECENT = 0.9

-- How far a thing may have got away from the creature, per second unlooked-at. Matching against an
-- estimate that is still as tight as the moment it was taken says a thing which moved at all must be
-- something else -- so the gate has to slacken with time, which is only *I do not know where it has
-- got to*. A creature that has learned how fast things move would derive this; until then it is the
-- one honest constant here.
local ADRIFT = 0.15

-- How well one track explains one return, as 0..1. Readings the track has no estimate for say
-- nothing either way; readings it does are scored by how many of its own spreads out the return
-- landed, so a confident track is fussy and an uncertain one is not.
local function explains(reg: any, state: any, track: any, kind: string?, raw: { [string]: any }): (number, number)
	local worst = 1
	local shared = 0
	for reading, value in pairs(raw) do
		if type(value) ~= "number" or reg.readings[reading] == nil then
			continue
		end
		local expected, spread = Predict.project(reg, state, track, kind, reading, state.doing)
		if expected == nil then
			continue
		end
		shared += 1
		local held = state.beliefs[World.estimateKey(track, reading)]
		local since = if held ~= nil then math.max(state.now - held.seen, 0) else 0
		local loose = math.sqrt(spread * spread + (ADRIFT * since) * (ADRIFT * since))
		local z = (value - expected) / math.max(loose, 0.02)
		local holds = math.exp(-0.5 * z * z)
		if holds < worst then
			worst = holds
		end
	end
	return worst, shared
end

Associate.explains = explains

-- Which thing is this? The best-explaining track, or a new one.
--
-- Cross-channel fusion falls out of the same test: a sound and a sight can only be judged the same
-- thing if their returns share a reading to be judged on -- direction, usually. Channels sharing
-- nothing can never be fused, which is correct, since there would be nothing to fuse them on.
function Associate.place(reg: any, state: any, raw: { [string]: any }, kind: string?): any
	local best, bestScore = nil, 0
	for handle, track in state.tracked do
		if handle:find("|kind", 1, true) then
			continue
		end
		local trackKind = state.tracked[handle .. "|kind"]
		-- Something known to be a different kind of thing is not a candidate at all.
		if kind ~= nil and trackKind ~= nil and kind ~= trackKind then
			continue
		end
		local score, shared = explains(reg, state, track, trackKind, raw)
		if shared == 0 then
			continue -- nothing in common to judge on
		end
		if score > bestScore then
			best, bestScore = track, score
		end
	end

	if best ~= nil and bestScore >= BIRTH then
		-- How much this track keeps failing to account for what it is handed. The trigger is the same
		-- persistent unresolved error that drives everything else in the package; only the resolution
		-- differs, because there is no belief that would fix being two things.
		local handle = tostring(best)
		local strain = state.strain[handle] or { n = 0, total = 0 }
		strain.n = strain.n * RECENT + 1
		strain.total = strain.total * RECENT + (1 - bestScore)
		state.strain[handle] = strain

		local stubborn = math.clamp(state.dial("attribution"), 0, 1)
		local torn = TORN + TORN_SPAN * stubborn
		if strain.n >= 3 and (strain.total / strain.n) > torn then
			state.strain[handle] = nil
			state.born += 1
			return ("t%d"):format(state.born), true
		end
		return best, false
	end

	state.born += 1
	return ("t%d"):format(state.born), true
end

-- Tracks nobody has reinforced, whose estimates have gone as vague as knowing nothing, stop costing
-- anything. Half-remembering is a real state; having entirely forgotten is not a state at all.
function Associate.collect(state: any): number
	local dropped = 0
	local stale: { string } = {}
	for handle, track in state.tracked do
		if handle:find("|kind", 1, true) then
			continue
		end
		if track == World.SELF or track == World.HERE then
			continue
		end
		local seen = -math.huge
		local prefix = World.estimateKey(track, "")
		for key, held in state.beliefs do
			if key:sub(1, #prefix) == prefix and held.seen > seen then
				seen = held.seen
			end
		end
		if state.now - seen > FORGOTTEN then
			table.insert(stale, handle)
		end
	end
	for _, handle in stale do
		local track = state.tracked[handle]
		local prefix = World.estimateKey(track, "")
		for key in state.beliefs do
			if key:sub(1, #prefix) == prefix then
				state.beliefs[key] = nil
			end
		end
		state.tracked[handle] = nil
		state.tracked[handle .. "|kind"] = nil
		state.strain[tostring(track)] = nil
		dropped += 1
	end
	return dropped
end

return Associate
