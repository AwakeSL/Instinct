--!strict

local Registry = {}
Registry.__index = Registry

export type Quantity = { name: string, low: number, high: number }
export type Operator = { name: string, stage: number, costs: number, apply: (number, number) -> number?, spreads: ((number, number, number, number, number) -> number)? }
export type Feature = { name: string, from: { string }, between: { string }?, expr: any, costs: number }
export type Kind = { name: string, stage: number, is: { string }, all: { [string]: boolean } }
export type Action = {
	name: string,
	requires: { [string]: string },
	occupies: { [string]: number },
	settles: { [string]: boolean },
	skill: string?,
	predicts: { any },
	costs: { [string]: number },
}

local function fail(site: string, message: string): never
	error(("[instinct] %s: %s"):format(site, message), 0)
end

function Registry.new()
	local self = setmetatable({}, Registry)
	self.quantities = {} :: { [string]: Quantity }
	self.roles = {} :: { [string]: boolean }
	self.senses = {} :: { [string]: any }
	self.operators = {} :: { [string]: Operator }
	self.features = {} :: { [string]: Feature }
	self.featureOrder = {} :: { string }
	self.kinds = {} :: { [string]: Kind }
	self.parts = {} :: { [string]: boolean }
	self.skills = {} :: { [string]: boolean }
	self.actions = {} :: { [string]: Action }
	self.actionOrder = {} :: { string }
	self.emotions = {} :: { [string]: any }
	self.signs = {} :: { [string]: any }
	self.species = {} :: { [string]: any }
	self.taken = {} :: { [string]: string }
	self.linked = false
	return self
end

export type Registry = typeof(Registry.new())

local function reserve(self: Registry, name: string, slot: string, site: string)
	local held = self.taken[name]
	if held ~= nil then
		fail(site, ("%q is already a %s; one name never means two things"):format(name, held))
	end
	self.taken[name] = slot
end

local function needName(name: any, site: string)
	if type(name) ~= "string" or name == "" then
		fail(site, "a declaration needs a name")
	end
end

function Registry.quantity(self: Registry, name: string, decl: any?)
	local site = ("quantity %q"):format(tostring(name))
	needName(name, site)
	if self.quantities[name] ~= nil then
		fail(site, "already declared")
	end
	reserve(self, name, "quantity", site)
	local range = if decl then decl.range else nil
	self.quantities[name] = table.freeze({
		name = name,
		low = if range then range[1] else 0,
		high = if range then range[2] else 1,
	})
end

function Registry.role(self: Registry, name: string)
	local site = ("role %q"):format(tostring(name))
	needName(name, site)
	if self.roles[name] then
		fail(site, "already declared")
	end
	self.roles[name] = true
end

function Registry.sense(self: Registry, name: string, decl: any?)
	local site = ("sense %q"):format(tostring(name))
	needName(name, site)
	if self.senses[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	if row.needs ~= nil and self.parts[row.needs] == nil then
		fail(site, ("needs part %q, which nobody declared"):format(tostring(row.needs)))
	end
	self.senses[name] = table.freeze({
		name = name,
		needs = row.needs,
		reliable = if row.reliable then table.freeze(table.clone(row.reliable.by or {})) else nil,
	})
end

function Registry.operator(self: Registry, name: string, decl: any)
	local site = ("operator %q"):format(tostring(name))
	needName(name, site)
	if self.operators[name] ~= nil then
		fail(site, "already declared")
	end
	if type(decl) ~= "table" or type(decl.stage) ~= "number" then
		fail(site, "an operator declares a numeric stage; precedence is data")
	end
	if type(decl.apply) ~= "function" then
		fail(site, "declared with no implementation is a load error")
	end
	reserve(self, name, "operator", site)
	self.operators[name] = table.freeze({
		name = name,
		stage = decl.stage,
		costs = decl.costs or 0,
		apply = decl.apply,
		spreads = decl.spreads,
	})
end

function Registry.part(self: Registry, name: string)
	local site = ("part %q"):format(tostring(name))
	needName(name, site)
	if self.parts[name] then
		fail(site, "already declared")
	end
	self.parts[name] = true
end

function Registry.skill(self: Registry, name: string)
	local site = ("skill %q"):format(tostring(name))
	needName(name, site)
	if self.skills[name] then
		fail(site, "already declared")
	end
	self.skills[name] = true
end

function Registry.feature(self: Registry, name: string, decl: any?)
	local site = ("feature %q"):format(tostring(name))
	needName(name, site)
	if self.features[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	local from: { string } = {}
	if type(row.from) == "string" then
		from = { row.from }
	elseif type(row.from) == "table" then
		from = table.clone(row.from)
	end
	for _, channel in from do
		if self.senses[channel] == nil then
			fail(site, ("reads sense %q, which nobody declared"):format(tostring(channel)))
		end
	end
	if row.between ~= nil then
		if type(row.between) ~= "table" or #row.between ~= 2 then
			fail(site, "`between` names exactly two roles")
		end
		for _, roleName in row.between do
			if not self.roles[roleName] then
				fail(site, ("between names role %q, which nobody declared"):format(tostring(roleName)))
			end
		end
	end
	self.features[name] = {
		name = name,
		from = table.freeze(from),
		between = if row.between then table.freeze(table.clone(row.between)) else nil,
		raw = row.is,
		expr = nil,
		costs = 0,
	} :: any
	table.insert(self.featureOrder, name)
end

function Registry.kind(self: Registry, name: string, decl: any?)
	local site = ("kind %q"):format(tostring(name))
	needName(name, site)
	if self.kinds[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	local is: { string } = if row.is then table.clone(row.is) else {}
	for _, parent in is do
		if self.kinds[parent] == nil then
			fail(site, ("is a %q, which nobody declared"):format(tostring(parent)))
		end
	end
	local all: { [string]: boolean } = { [name] = true }
	for _, parent in is do
		for ancestor in self.kinds[parent].all do
			all[ancestor] = true
		end
	end
	self.kinds[name] = table.freeze({
		name = name,
		stage = row.stage or 2,
		is = table.freeze(is),
		all = table.freeze(all),
	})
end

function Registry.action(self: Registry, name: string, decl: any?)
	local site = ("action %q"):format(tostring(name))
	needName(name, site)
	if self.actions[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	local occupies: { [string]: number } = {}
	for partName, count in (row.occupies or {}) :: any do
		if type(partName) == "number" then
			fail(site, "`occupies` maps part names to counts")
		end
		if self.parts[partName] == nil then
			fail(site, ("occupies part %q, which nobody declared"):format(tostring(partName)))
		end
		occupies[partName] = count
	end
	local settles: { [string]: boolean } = {}
	for _, key in (row.settles or {}) :: { string } do
		settles[key] = true
	end
	if row.skill ~= nil and self.skills[row.skill] == nil then
		fail(site, ("names skill %q, which nobody declared"):format(tostring(row.skill)))
	end
	for quantityName in (row.costs or {}) :: any do
		if self.quantities[quantityName] == nil then
			fail(site, ("costs %q, a quantity nobody declared"):format(tostring(quantityName)))
		end
	end
	self.actions[name] = {
		name = name,
		requires = table.freeze(table.clone(row.requires or {})),
		occupies = table.freeze(occupies),
		settles = table.freeze(settles),
		skill = row.skill,
		predicts = row.predicts or {},
		costs = table.freeze(table.clone(row.costs or {})),
	} :: any
	table.insert(self.actionOrder, name)
end

function Registry.emotion(self: Registry, name: string, decl: any?)
	local site = ("emotion %q"):format(tostring(name))
	needName(name, site)
	if self.emotions[name] ~= nil then
		fail(site, "already declared")
	end
	if self.quantities[name] ~= nil then
		fail(site, "already a quantity; an emotion declares its own name")
	end
	local row = decl or {}
	reserve(self, name, "emotion", site)
	self.quantities[name] = table.freeze({ name = name, low = 0, high = 1 })
	self.emotions[name] = {
		name = name,
		from = row.from or {},
		decays = row.decays or 0.5,
		modulates = row.modulates or {},
	}
end

function Registry.sign(self: Registry, name: string, decl: any?)
	local site = ("sign %q"):format(tostring(name))
	needName(name, site)
	if self.signs[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	if row.seeing == nil or row.tells == nil then
		fail(site, "a sign declares what it is `seeing` and what that `tells`")
	end
	self.signs[name] = { name = name, seeing = row.seeing, tells = row.tells }
end

function Registry.species(self: Registry, name: string, decl: any?)
	local site = ("species %q"):format(tostring(name))
	needName(name, site)
	if self.species[name] ~= nil then
		fail(site, "already declared")
	end
	local row = decl or {}
	local base = nil
	if row.of ~= nil then
		base = self.species[row.of]
		if base == nil then
			fail(site, ("extends %q, which nobody declared"):format(tostring(row.of)))
		end
	end

	local function inherit(field: string): any
		local mine = row[field]
		if base == nil then
			return mine
		end
		if mine == nil then
			return base[field]
		end
		if type(mine) ~= "table" or type(base[field]) ~= "table" then
			return mine
		end
		local merged = table.clone(base[field])
		for k, v in mine do
			merged[k] = v
		end
		return merged
	end

	local parts: { [string]: number } = {}
	for partName, count in (inherit("parts") or {}) :: any do
		if type(partName) == "number" then
			fail(site, "`parts` maps part names to counts")
		end
		if self.parts[partName] == nil then
			fail(site, ("has part %q, which nobody declared"):format(tostring(partName)))
		end
		parts[partName] = count
	end

	local senses: { [string]: any } = {}
	for senseName, cfg in (inherit("senses") or {}) :: any do
		if self.senses[senseName] == nil then
			fail(site, ("has sense %q, which nobody declared"):format(tostring(senseName)))
		end
		senses[senseName] = cfg
	end

	for _, featureName in (inherit("forms") or {}) :: { string } do
		if self.features[featureName] == nil then
			fail(site, ("forms %q, a feature nobody declared"):format(tostring(featureName)))
		end
	end
	for _, signName in (inherit("reads") or {}) :: { string } do
		if self.signs[signName] == nil then
			fail(site, ("reads %q, a sign nobody declared"):format(tostring(signName)))
		end
	end
	for _, emotionName in (inherit("feels") or {}) :: { string } do
		if self.emotions[emotionName] == nil then
			fail(site, ("feels %q, an emotion nobody declared"):format(tostring(emotionName)))
		end
	end
	for skillName in (inherit("skills") or {}) :: any do
		if self.skills[skillName] == nil then
			fail(site, ("has skill %q, which nobody declared"):format(tostring(skillName)))
		end
	end
	for quantityName in (inherit("expects") or {}) :: any do
		if self.quantities[quantityName] == nil then
			fail(site, ("expects %q, a quantity nobody declared"):format(tostring(quantityName)))
		end
	end
	if row.kind ~= nil and self.kinds[row.kind] == nil then
		fail(site, ("is kind %q, which nobody declared"):format(tostring(row.kind)))
	end
	for actionName in (inherit("believes") or {}) :: any do
		if self.actions[actionName] == nil then
			fail(site, ("believes about %q, an action nobody declared"):format(tostring(actionName)))
		end
	end

	self.species[name] = {
		name = name,
		kind = row.kind or (if base then base.kind else nil),
		parts = parts,
		senses = senses,
		forms = inherit("forms") or {},
		reads = inherit("reads") or {},
		chunks = inherit("chunks") or {},
		skills = inherit("skills") or {},
		feels = inherit("feels") or {},
		expects = inherit("expects") or {},
		selfImage = inherit("selfImage") or {},
		instinct = inherit("instinct") or {},
		believes = inherit("believes") or {},
		dials = inherit("dials") or {},
	}
end

return Registry
