--!strict

local process = require("@lune/process")

local SPECS: { [string]: any } = {
	ValuesSpec = require("../test/ValuesSpec"),
	DeclareSpec = require("../test/DeclareSpec"),
	ActSpec = require("../test/ActSpec"),
	ChainSpec = require("../test/ChainSpec"),
	LearnSpec = require("../test/LearnSpec"),
	SkillSpec = require("../test/SkillSpec"),
	MemorySpec = require("../test/MemorySpec"),
	FeelSpec = require("../test/FeelSpec"),
	BlameSpec = require("../test/BlameSpec"),
	SignSpec = require("../test/SignSpec"),
	LineageSpec = require("../test/LineageSpec"),
	ScheduleSpec = require("../test/ScheduleSpec"),
	CreditSpec = require("../test/CreditSpec"),
	MindSpec = require("../test/MindSpec"),
	AcquireSpec = require("../test/AcquireSpec"),
	ActionLearnSpec = require("../test/ActionLearnSpec"),
	ForesightSpec = require("../test/ForesightSpec"),
	VentureSpec = require("../test/VentureSpec"),
	CuriositySpec = require("../test/CuriositySpec"),
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
		table.insert(failures, ("%s: %s (error did not mention '%s': %s)"):format(current, message, pattern, tostring(err)))
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
	print(("instinct: %d cases, all green (%d specs)"):format(cases, #names))
else
	print(("instinct: %d cases, %d RED"):format(cases, #failures))
	for _, line in failures do
		print("  " .. line)
	end
	process.exit(1)
end
