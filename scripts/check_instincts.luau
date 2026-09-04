--!nonstrict
-- Do declared instincts land on the inputs they name, under the pooled value as under the dense one?
local Instinct = require("../mind")
local Mind, Senses = Instinct.Mind, Instinct.Senses
local SLOTS = { "host", "item", "haz", "ally" }
local NAMES = Senses.layout(SLOTS, { "timeLeft", "armed" })
local CHOICES = {
	{ name = "target", options = { "keep", "hostile", "item", "ally" } },
	{ name = "move", options = { "hold", "forward", "retreat" } },
	{ name = "turn", options = { "none", "left", "right" } },
}
local K = {
	priors = {
		{ reading = "eaten", feature = "itemdist", w = -4, conf = 3 },
		{ reading = "eaten", feature = "mul(move=forward,itemthere)", w = 3, conf = 3 },
		{ reading = "eaten", feature = "mul(itembearing,turn=left)", w = 2, conf = 3 },
	},
	features = {
		{ op = "mul", a = "move=forward", b = "itemthere" },
		{ op = "mul", a = "itembearing", b = "turn=left" },
	},
}
for _, pooled in { false, true } do
	local m = Mind.new(#NAMES, CHOICES, {
		set = "OMECA", readings = { "eaten" }, pref = { eaten = 1 },
		groups = Senses.groups(SLOTS, { "timeLeft", "armed" }), equivariant = pooled, pooledValue = pooled,
	})
	m:learnFrom(K, NAMES)
	local named = {}
	for _, a in m.acquired do
		table.insert(named, m:acquiredName(a, NAMES))
	end
	print(("pooled=%s: priors placed %d of 3, features %s; itemdist -> input %s"):format(tostring(pooled), m.stats.priors or 0, table.concat(named, " "), m:inputName(m:featureIndex("itemdist", NAMES) - 1, NAMES)))
end

-- under a code the instincts are taught as rows: does the taught value point the same way?
do
	local m = Mind.new(#NAMES, CHOICES, {
		set = "OMECA", code = 16, readings = { "eaten" }, pref = { eaten = 1 },
	})
	m:learnFrom(K, NAMES)
	local function worthOf(x, picks)
		local X = m:extend(m:encode(x))
		return m:worth(X, picks, {}, true)
	end
	local none = table.create(#NAMES, 0)
	local near = table.create(#NAMES, 0)
	near[table.find(NAMES, "itemthere")] = 1
	near[table.find(NAMES, "itemdist")] = 0.2
	near[table.find(NAMES, "itembearing")] = 0.5
	local far = table.clone(near)
	far[table.find(NAMES, "itemdist")] = 1
	local hold, forward, left, right = { 1, 1, 1 }, { 1, 2, 1 }, { 1, 1, 2 }, { 1, 1, 3 }
	print(("code: priors taught %d rows, acquired %d; worth nothing/hold %.2f, near/hold %.2f, near/forward %.2f, far/forward %.2f, near/left %.2f, near/right %.2f"):format(
		m.stats.priors or 0, #m.acquired, worthOf(none, hold), worthOf(near, hold), worthOf(near, forward), worthOf(far, forward), worthOf(near, left), worthOf(near, right)))
end
