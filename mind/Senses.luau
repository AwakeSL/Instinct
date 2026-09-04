--!strict
-- The one sense layout every world is read through: the creature itself, then one slot per role
-- (the nearest hostile, the nearest item, the nearest hazard, the nearest ally...), each in the
-- creature's own frame with the same seven descriptors. This is what lets what was learned about
-- "a hostile closing" in one place apply to the next place's hostile: the weights are the same
-- weights everywhere.
--
-- Nothing here is Roblox-specific. Positions are taken on the XZ plane; heading is
-- the creature's look direction as an angle.

local Senses = {}

-- Anything with X and Z fields will do for a position: a Vector3, or a plain table.
export type Vec = { X: number, Z: number }
local ZERO: Vec = { X = 0, Z = 0 }

export type Entity = {
	position: Vec,
	velocity: Vec?,
	hp: number?, -- 0..1
	extra: number?, -- one more thing about it the world wants to say (armed, parrying...)
}

export type Self = {
	position: Vec,
	heading: number, -- radians on the XZ plane
	velocity: Vec?,
	hp: number, -- 0..1
	speed: number?, -- as a share of 20 studs a second
	cooldown: number?, -- 0..1
	committing: number?,
	potion: number?,
}

local SLOT_FIELDS = { "there", "dist", "bearing", "absBearing", "closing", "hp", "extra" }
local SELF_FIELDS = { "hp", "cosH", "sinH", "speed", "cd", "committing", "pot" }

Senses.SLOT_FIELDS = SLOT_FIELDS

local function wrap(a: number): number
	while a > math.pi do
		a -= 2 * math.pi
	end
	while a < -math.pi do
		a += 2 * math.pi
	end
	return a
end

-- The names, in order: the self readings, the world's own extra readings, then each slot's seven.
-- `subjectDim` > 0 gives every slot that many more fields, `<slot>who1..D`: the creature's own learned
-- numbers about the individual in the slot (Mind's `subjects` option), so two things of one kind can be told
-- apart by what each has come to mean to it.
function Senses.layout(slots: { string }, worldReadings: { string }?, subjectDim: number?): { string }
	local names = table.clone(SELF_FIELDS)
	for _, n in ipairs(worldReadings or {}) do
		table.insert(names, n)
	end
	for _, sl in ipairs(slots) do
		for _, f in ipairs(SLOT_FIELDS) do
			table.insert(names, sl .. f)
		end
		for q = 1, subjectDim or 0 do
			table.insert(names, sl .. "who" .. q)
		end
	end
	return names
end

local function slot(x: { number }, me: Self, e: Entity?, range: number, who: any?, k: number?, subjectDim: number?)
	local D = subjectDim or 0
	if e == nil then
		-- an empty slot reads all zeros: "there" already says absent, and a zero row costs nothing to learn from
		for _ = 1, 7 + D do
			table.insert(x, 0)
		end
		if who and k then
			who(nil, k) -- nobody here: the mind's note of who is in this slot is cleared
		end
		return
	end
	local dx, dz = e.position.X - me.position.X, e.position.Z - me.position.Z
	local d = math.sqrt(dx * dx + dz * dz)
	local b = wrap(math.atan2(dz, dx) - me.heading)
	local mv = me.velocity or ZERO
	local ev = e.velocity or ZERO
	local rvx, rvz = ev.X - mv.X, ev.Z - mv.Z
	table.insert(x, 1)
	table.insert(x, d / range)
	table.insert(x, b / math.pi)
	table.insert(x, math.abs(b) / math.pi)
	table.insert(x, if d > 1e-6 then -(rvx * dx + rvz * dz) / d / 10 else 0)
	table.insert(x, e.hp or 1)
	table.insert(x, e.extra or 0)
	if D > 0 then
		-- what this creature has learned about the individual here (zeros for a stranger or an unnamed thing)
		local d = if who then who(e.id, k) else nil
		for q = 1, D do
			table.insert(x, if d then d[q] else 0)
		end
	end
end

-- Encode one moment. `entities[slot]` is the entity in that slot or nil; `world` is the world's own
-- extra readings in layout order; `range` is the distance that reads as 1.
-- `who` is the mind's `who` (mind:whoFn()), which fills each named entity's subject fields.
function Senses.encode(me: Self, slots: { string }, entities: { [string]: Entity? }, world: { number }?, range: number?, who: any?, subjectDim: number?): { number }
	local x = {
		me.hp,
		math.cos(me.heading),
		math.sin(me.heading),
		(me.speed or 0.5),
		me.cooldown or 0,
		me.committing or 0,
		me.potion or 0,
	}
	for _, v in ipairs(world or {}) do
		table.insert(x, v)
	end
	for k, sl in ipairs(slots) do
		slot(x, me, entities[sl], range or 40, who, k, subjectDim)
	end
	return x
end

-- The sense groups of a layout, for a block-local mind: the self and world readings first, then each slot.
function Senses.groups(slots: { string }, worldReadings: { string }?, subjectDim: number?): { { number } }
	local groups = {}
	local first = {}
	local nSelf = #SELF_FIELDS + #(worldReadings or {})
	local size = #SLOT_FIELDS + (subjectDim or 0)
	for i = 1, nSelf do
		table.insert(first, i)
	end
	table.insert(groups, first)
	for k = 1, #slots do
		local blk = {}
		for q = 1, size do
			table.insert(blk, nSelf + (k - 1) * size + q)
		end
		table.insert(groups, blk)
	end
	return groups
end

-- The bearing to an entity, in the creature's frame, for realising a move.
function Senses.bearing(me: Self, e: Entity): number
	return wrap(math.atan2(e.position.Z - me.position.Z, e.position.X - me.position.X) - me.heading)
end

Senses.wrap = wrap

return Senses
