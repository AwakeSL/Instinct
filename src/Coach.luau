--!strict
-- The rules that turn a mind into a creature that learns reliably. None of them know the world;
-- they know only the creature's own score, a random policy's score, and time.
--
--   explore   the first few episodes are random (the rows that seed everything)
--   floor     after every `every` episodes, a creature whose rolling score is below what a random
--             policy scores forgets its conclusions and explores again. A bad early draw is not
--             repaired by more rows; it is repaired by throwing the dice again, and the throw has
--             to include the exploration that seeded the draw. This took world 24 of the generated
--             set from five seeds in nine learning it to six of six.
--
-- An "episode" is whatever the game calls one: a match, or a fixed number of ticks of a continuous
-- life. The coach only needs to be told when one ends and what it scored.

local Coach = {}
Coach.__index = Coach

export type Options = {
	explore: number?, -- random episodes at birth and after a rebirth (5)
	every: number?, -- how often the floor is checked, in episodes (10)
	window: number?, -- episodes in the rolling score (10)
	floor: (number | string)?, -- the random policy's score; "explore" takes the mean of the exploration episodes; nil never rebirths
	-- STALL (Kestrel's row): a creature can sit above the random floor and still be lost, so the floor never
	-- fires (world 24's failures sat at 34-276 over a floor of 62, under half the threshold). With `stallAbove`
	-- set, a creature whose rolling score is within that much of the floor and has not improved over the last
	-- `stall` checks is reborn too.
	stallAbove: number?, -- how far above the floor still counts as lost (score units; nil: no stall rule)
	stall: number?, -- checks without improvement before a stalled creature is reborn (2)
}

function Coach.new(mind: any, o: Options?)
	o = o or {}
	local self = setmetatable({}, Coach)
	self.mind = mind
	self.explore = o.explore or 5
	self.every = o.every or 10
	self.window = o.window or 10
	self.floor = o.floor
	self.stallAbove = o.stallAbove
	self.stall = o.stall or 2
	self.checks = {}
	self.episode = 0
	self.exploreUntil = self.explore
	self.recent = {} :: { number }
	self.rebirths = 0
	return self
end

-- Call before an episode: sets the mind's exploration for it.
function Coach:beginEpisode()
	self.episode += 1
	self.mind.eps = if self.episode <= self.exploreUntil then 1 else 0
	self.mind.exploring = true
end

-- Call after an episode with its score. Returns true if the creature was reborn.
function Coach:endEpisode(score: number): boolean
	table.insert(self.recent, score)
	if #self.recent > self.window then
		table.remove(self.recent, 1)
	end
	-- the exploration episodes are a random policy: their mean is the floor, if none was given
	if self.floor == "explore" and self.episode == self.explore then
		local m = 0
		for _, v in ipairs(self.recent) do
			m += v
		end
		self.floor = m / #self.recent
		self.explored = self.floor
	end
	if type(self.floor) ~= "number" or self.episode % self.every ~= 0 or #self.recent < self.window then
		return false
	end
	local m = 0
	for _, v in ipairs(self.recent) do
		m += v
	end
	m /= #self.recent
	table.insert(self.checks, m)
	local lost = m < self.floor
	if not lost and self.stallAbove and m < self.floor + self.stallAbove and #self.checks > self.stall then
		-- no better than it was `stall` checks ago, and still near the floor
		lost = m <= self.checks[#self.checks - self.stall]
		if lost then
			self.stalls = (self.stalls or 0) + 1
		end
	end
	if lost then
		self.mind:rebirth()
		self.exploreUntil = self.episode + self.explore
		self.rebirths += 1
		self.checks = {}
		return true
	end
	return false
end

function Coach:rolling(): number
	local m = 0
	for _, v in ipairs(self.recent) do
		m += v
	end
	return if #self.recent > 0 then m / #self.recent else 0
end

return Coach
