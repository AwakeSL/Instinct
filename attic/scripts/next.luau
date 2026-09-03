--!strict
-- The rebuild's own suite, run apart from the 0.4.0 one so both can be green at once.

local process = require("@lune/process")

local SPECS: { [string]: any } = {
	CoreSpec = require("../test/next/CoreSpec"),
	ActSpec = require("../test/next/ActSpec"),
	SeeSpec = require("../test/next/SeeSpec"),
	LearnSpec = require("../test/next/LearnSpec"),
	ChainSpec = require("../test/next/ChainSpec"),
	FeelSpec = require("../test/next/FeelSpec"),
	PassOnSpec = require("../test/next/PassOnSpec"),
	SplitSpec = require("../test/next/SplitSpec"),
}

local failures: { string } = {}
local cases = 0
local current = "?"
local t = {}

function t.ok(condition: any, message: string)
	cases += 1
	if not condition then
		table.insert(failures, ("%s: %s"):format(current, message))
	end
end

function t.eq(got: any, want: any, message: string)
	cases += 1
	if got ~= want then
		table.insert(failures, ("%s: %s (got %s, want %s)"):format(current, message, tostring(got), tostring(want)))
	end
end

function t.near(got: any, want: number, message: string, slack: number?)
	cases += 1
	local room = slack or 1e-6
	if type(got) ~= "number" or math.abs(got - want) > room then
		table.insert(failures, ("%s: %s (got %s, want %s)"):format(current, message, tostring(got), tostring(want)))
	end
end

function t.err(fn: () -> (), pattern: string, message: string)
	cases += 1
	local ok, err = pcall(fn)
	if ok then
		table.insert(failures, ("%s: %s (expected an error, none thrown)"):format(current, message))
	elseif not tostring(err):find(pattern, 1, true) then
		table.insert(failures, ("%s: %s (no mention of '%s': %s)"):format(current, message, pattern, tostring(err)))
	end
end

local names: { string } = {}
for name in SPECS do
	table.insert(names, name)
end
table.sort(names)

for _, name in names do
	current = name
	local ok, err = pcall(SPECS[name], t)
	if not ok then
		table.insert(failures, ("%s: threw: %s"):format(name, tostring(err)))
	end
end

if #failures == 0 then
	print(("instinct/next: %d cases, all green (%d specs)"):format(cases, #names))
else
	print(("instinct/next: %d cases, %d RED"):format(cases, #failures))
	for _, line in failures do
		print("  " .. line)
	end
	process.exit(1)
end
