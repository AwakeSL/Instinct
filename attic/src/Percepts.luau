--!strict
--!native

local Registry = require("./Registry")
local Values = require("./Values")

local Percepts = {}
Percepts.__index = Percepts

export type View = {
	subject: any,
	kind: string?,
	confidence: number,
	via: string?,
	raw: { [string]: any },
	memo: { [string]: any },
	cost: number,
}

function Percepts.new(reg: Registry.Registry)
	local self = setmetatable({}, Percepts)
	self.reg = reg
	self.views = {} :: { View }
	self.bySubject = {} :: { [any]: View }
	self.forms = {} :: { [string]: boolean }
	self.gains = {} :: { [string]: number }
	self.resolving = {} :: { [string]: boolean }
	self.cost = 0
	return self
end

export type Percepts = typeof(Percepts.new(Registry.new()))

function Percepts.reset(self: Percepts, forms: { [string]: boolean }, gains: { [string]: number }?)
	table.clear(self.views)
	table.clear(self.bySubject)
	self.forms = forms
	self.gains = gains or {}
	self.cost = 0
end

function Percepts.add(self: Percepts, entry: any)
	local view: View = {
		subject = entry.subject,
		kind = entry.kind,
		confidence = if entry.confidence ~= nil then entry.confidence else 1,
		via = entry.via,
		raw = entry.raw or {},
		memo = {},
		cost = 0,
	}
	table.insert(self.views, view)
	if entry.subject ~= nil then
		self.bySubject[entry.subject] = view
	end
	return view
end

local function reliability(self: Percepts, view: View, from: { string }): number
	if #from == 0 then
		return 1
	end
	local best = 0
	for _, channel in from do
		local sense = self.reg.senses[channel]
		local r = 1
		if sense ~= nil and sense.reliable ~= nil then
			for _, factor in sense.reliable :: { string } do
				local supplied = view.raw[factor]
				if type(supplied) == "number" then
					r *= math.clamp(supplied, 0, 1)
				end
			end
		end
		if r > best then
			best = r
		end
	end
	return math.max(best, 0.05)
end

function Percepts.read(self: Percepts, view: View, name: string): (number?, number)
	local held = view.memo[name]
	if held ~= nil then
		return held[1], held[2]
	end

	local feature = self.reg.features[name]
	if feature ~= nil and self.forms[name] then
		if self.resolving[name] then
			error(("[instinct] feature %q depends on itself"):format(name), 0)
		end
		self.resolving[name] = true
		local value: number?, spread: number = nil, 0
		if feature.expr ~= nil then
			value, spread = Values.resolve(self.reg, feature.expr, function(inner: string)
				return Percepts.read(self, view, inner)
			end)
		else
			local raw = view.raw[name]
			if type(raw) == "number" then
				value, spread = raw, 0
			end
		end
		self.resolving[name] = nil
		if value ~= nil then
			local gain = self.gains[name]
			if gain ~= nil then
				value *= gain
			end
			spread /= reliability(self, view, feature.from)
			self.cost += feature.costs
			view.cost += feature.costs
		end
		view.memo[name] = { value, spread }
		return value, spread
	end

	if feature ~= nil then
		view.memo[name] = { nil, 0 }
		return nil, 0
	end

	local raw = view.raw[name]
	if type(raw) == "number" then
		view.memo[name] = { raw, 0 }
		return raw, 0
	end
	if type(raw) == "boolean" then
		local n = if raw then 1 else 0
		view.memo[name] = { n, 0 }
		return n, 0
	end

	view.memo[name] = { nil, 0 }
	return nil, 0
end

function Percepts.isKind(self: Percepts, view: View, kindName: string): boolean
	if view.kind == nil then
		return false
	end
	local decl = self.reg.kinds[view.kind]
	if decl == nil then
		return view.kind == kindName
	end
	return decl.all[kindName] == true
end

return Percepts
