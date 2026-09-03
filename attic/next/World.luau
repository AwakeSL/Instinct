--!strict
-- What the creature currently holds about everything it is tracking.
--
-- A reading is not what the senses said this tick. It is an **estimate**, updated by whatever
-- evidence arrives and widening when none does. That is what makes object permanence fall out
-- rather than be arranged: look away and the estimate persists, less and less certain, until it is
-- indistinguishable from knowing nothing.
--
-- A **subject** here is not a claim that something is a thing. It is a slot keeping one set of
-- readings apart from another. `self` and `here` are always present -- the body, and the ambient
-- that belongs to no particular thing.

local Beliefs = require("./Beliefs")
local Registry = require("./Registry")
local Values = require("./Values")

local World = {}

World.SELF = "self"
World.HERE = "here"

-- Absence widens an estimate toward knowing nothing. Fast enough that a creature is not certain
-- about a room it left an hour ago, slow enough that blinking costs it nothing.
local FADE = 0.25
local BLIND = 0.5

local function estimateKey(subject: any, reading: string): string
	return ("est|%s|%s"):format(tostring(subject), reading)
end

World.estimateKey = estimateKey

-- Evidence arriving on a channel. `trust` is the channel's reliability: an unreliable sense reports
-- the same number less convincingly, and everything downstream inherits that.
function World.observe(state: any, subject: any, reading: string, value: number, trust: number)
	local key = estimateKey(subject, reading)
	local held = state.beliefs[key]
	local spread = math.max(0.02, (1 - math.clamp(trust, 0, 1)) * 0.5 + 0.02)
	if held == nil then
		-- First sight of this. Take it at the sense's word rather than blending into a prior that
		-- does not exist.
		held = Beliefs.hold(state.beliefs, key, value, spread, "sense")
		held.n = 1
		held.best = spread
	else
		Beliefs.update(held, value, spread, state.dial("adaptability"))
		-- A creature cannot know something more precisely than the **best look it ever got at it**.
		-- Without a floor an estimate narrows without bound, and a belief held tighter than the world
		-- can be measured makes ordinary drift look like a shock: the creature tracks a steady change
		-- in stutters, astonished every third tick by something that has been happening all along.
		--
		-- The floor is the best look and not the current one, which matters more than it sounds. A
		-- poor glimpse that agrees with what you already knew is not a reason to know it less well --
		-- and flooring at the current look means walking away from a thing makes you forget it, since
		-- the distant reports are bad ones. A creature drawn to what it does not know then shuttles
		-- back and forth between two things forever, re-learning each as it abandons the other.
		--
		-- Going vague with time is a different thing and belongs to `fade`, which is about the world
		-- moving on rather than about the quality of a look.
		held.best = math.min(held.best or spread, spread)
		held.s = math.max(held.s, held.best)
	end
	held.seen = state.now
	state.tracked[tostring(subject)] = subject
end

-- Nothing was heard from it. Widen, do not forget: half-remembering is a real state.
function World.fade(state: any, dt: number)
	for key, held in state.beliefs do
		if key:sub(1, 4) ~= "est|" then
			continue
		end
		if held.seen >= state.now - 1e-6 then
			continue
		end
		Beliefs.relax(held, held.v, BLIND, FADE * (1 - state.dial("grudge") * 0.8), dt)
	end
end

-- Read one reading of one subject, deriving it if it is built from others.
--
-- `recalls` operators are handed what they last returned at this site for this subject, which is the
-- only way change-over-time can be expressed at all. The memory is per (reading, subject), because
-- the same idea applied to two animals needs two histories.
function World.read(reg: any, state: any, subject: any, reading: string): (number?, number)
	-- A creature's own acquired readings come first: an idea one creature worked out is not one
	-- every creature is born with.
	local decl = state.readings[reading] or reg.readings[reading]
	if decl == nil then
		return nil, 0
	end

	local memo = state.readMemo
	local memoKey = ("%s|%s"):format(tostring(subject), reading)
	local cached = memo[memoKey]
	if cached ~= nil then
		return cached[1], cached[2]
	end

	local value: number?, spread: number = nil, 0

	if decl.unsure ~= nil then
		-- How well it knows the thing, not what the thing is. Nothing is claimed about the value.
		if state.deriving[memoKey] then
			error(("[instinct] reading %q depends on itself"):format(reading), 0)
		end
		state.deriving[memoKey] = true
		local known, width = World.read(reg, state, subject, decl.unsure)
		state.deriving[memoKey] = nil
		-- Nothing known at all is the most unsure a creature can be, rather than no answer: a thing
		-- it has never got a look at is exactly what it should find strange.
		value, spread = if known == nil then 1 else math.clamp(width / BLIND, 0, 1), 0
	elseif decl.predicts ~= nil then
		-- What the creature expects, rather than what it holds. Cycle detection covers this exactly as
		-- it covers any other layer, because it is one.
		if state.deriving[memoKey] then
			error(("[instinct] reading %q depends on itself"):format(reading), 0)
		end
		state.deriving[memoKey] = true
		value, spread = state.project(subject, decl.predicts, decl.after)
		state.deriving[memoKey] = nil
	elseif decl.expr == nil then
		local held = state.beliefs[estimateKey(subject, reading)]
		if held ~= nil then
			value, spread = held.v, held.s
			-- Attention narrows what it is aimed at. A frightened creature does not see its health
			-- more accurately; it treats what it sees as more decisive, which is the same arithmetic
			-- and the honest version of the claim.
			local sharper = World.sharpness(reg, state, reading)
			if sharper ~= 1 then
				spread /= sharper
			end
		end
	else
		if state.deriving[memoKey] then
			error(("[instinct] reading %q depends on itself"):format(reading), 0)
		end
		state.deriving[memoKey] = true
		local held = ("%s|%s|"):format(tostring(subject), reading)
		value, spread = Values.resolve(reg, decl.expr, function(inner: string)
			return World.read(reg, state, subject, inner)
		end, nil, nil, {
			-- one history per (reading, subject): the same idea applied to two animals needs two
			recall = function(site: string): any
				return state.recalled[held .. site]
			end,
			remember = function(site: string, past: any)
				state.recalled[held .. site] = past
			end,
			now = state.now,
		})
		state.deriving[memoKey] = nil
	end

	-- An emotion keeps a fraction of itself each second. Onset is immediate -- a creature does not
	-- become afraid gradually, it stops being afraid gradually -- so what lingers can only ever raise
	-- what the moment says, never lower it.
	if decl.emotion then
		local lingerKey = ("%s|%s"):format(tostring(subject), reading)
		local held = state.feelings[lingerKey]
		if held ~= nil and decl.decays > 0 then
			local since = math.max(state.now - held.at, 0)
			local left = held.value * decl.decays ^ since
			if value == nil or left > value then
				value, spread = left, math.max(spread, held.spread)
			end
		end
		if value ~= nil then
			state.feelings[lingerKey] = { value = value, spread = spread, at = state.now }
		end
	end

	memo[memoKey] = { value, spread }
	return value, spread
end

-- How much every emotion currently in play sharpens one reading. At no feeling nothing changes; the
-- factor is earned in proportion to how strongly the thing is felt.
function World.sharpness(reg: any, state: any, reading: string): number
	local _ = reg
	local total = 1
	for name, decl in reg.readings do
		if not decl.emotion then
			continue
		end
		local scale = decl.precision[reading]
		if scale == nil then
			continue
		end
		local felt = state.feelings[("%s|%s"):format(World.SELF, name)]
		if felt == nil then
			continue
		end
		local strength = math.clamp(felt.value, 0, 1)
		total *= 1 + (scale - 1) * strength
	end
	return if total > 0 then total else 1
end

function World.forget(state: any)
	state.readMemo = {}
end

-- Does this subject match a condition -- a kind, or a pattern of readings, or nothing at all?
--
-- A pattern is graded: `{ green = "high" }` asks how green, not whether green. So a condition
-- returns how well it holds, and a prediction conditioned on it counts for that much.
function World.matches(reg: any, state: any, subject: any, kind: string?, about: any): number
	if about == nil then
		return 1
	end
	if type(about) == "string" then
		return if Registry.kindsOf(reg, kind)[about] then 1 else 0
	end

	local weakest = 1
	for key, wanted in pairs(about) do
		if key == "kind" then
			if not Registry.kindsOf(reg, kind)[wanted] then
				return 0
			end
			continue
		end
		local value = World.read(reg, state, subject, key)
		if value == nil then
			return 0
		end
		local holds: number
		if wanted == "high" then
			holds = math.clamp(value, 0, 1)
		elseif wanted == "low" then
			holds = math.clamp(1 - value, 0, 1)
		elseif type(wanted) == "number" then
			holds = math.clamp(1 - math.abs(value - wanted) * 2, 0, 1)
		else
			holds = 0
		end
		if holds < weakest then
			weakest = holds
		end
	end
	return weakest
end

-- How specific a condition is, for deciding which of two overlapping ones is the refinement. More
-- terms is narrower; a bare condition is the broadest thing there is.
function World.narrowness(about: any): number
	if about == nil then
		return 0
	end
	if type(about) == "string" then
		return 1
	end
	local count = 0
	for _ in pairs(about) do
		count += 1
	end
	return count
end

return World
