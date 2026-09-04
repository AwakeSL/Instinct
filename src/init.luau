--!strict
-- Instinct, the learned-mind tree: a linear creature that predicts the outcomes of its options and
-- the effects of its acts, remembers surprises, invents inputs where it keeps being wrong, and can
-- be given instincts as revisable priors. See C:\lua code\FINDINGS.md for what earned its place.

local Mind = require("@self/Mind")
local RLS = require("@self/RLS")
local Senses = require("@self/Senses")
local Coach = require("@self/Coach")

return {
	Mind = Mind,
	RLS = RLS,
	Senses = Senses,
	Coach = Coach,
}
