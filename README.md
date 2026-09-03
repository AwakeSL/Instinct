# instinct

**Creatures that learn what their senses predict, what their acts do, and what to do about it.**

A creature holds a few tiny linear predictions and nothing else: what each reading it cares about
(meals, damage dealt, damage taken...) will accumulate over the next couple of seconds, from what it
senses and what it picks; what each of its options does to the senses one step on; and a memory of
the moments that surprised it for the better. Every tick it scores every combination of its options
on those predictions, looks one step ahead through the best few, and takes the best. The rows settle
a horizon later and every model updates online. Nothing is scored by a system you cannot see, and
nothing it holds is a rule: an instinct is a prior with a confidence, and the world revises it.

```lua
local Instinct = require(path.to.Instinct)
local Mind, Senses, Coach = Instinct.Mind, Instinct.Senses, Instinct.Coach

-- every world is read through the same layout: the self, then one slot per role
local SLOTS = { "host", "item", "haz", "ally" }
local NAMES = Senses.layout(SLOTS)

local CHOICES = {
    { name = "target", options = { "keep", "hostile", "item" } },
    { name = "move", options = { "hold", "approach", "retreat", "orbit" } },
    { name = "act", options = { "none", "strike", "parry" } },
}

local mind = Mind.new(#NAMES, CHOICES, {
    readings = { "dealt", "taken", "eaten" },
    pref = { dealt = 1, taken = -1, eaten = 20 },   -- the only thing you author about what is good
    horizon = 24,   -- decisions a row waits before it is judged
    step = 12,      -- decisions between an act and its measured effect
})
local coach = Coach.new(mind, { explore = 5, every = 10, floor = "explore" })

-- each decision (ten a second is the tested rate)
local x = Senses.encode(me, SLOTS, { host = wolf, item = food }, nil, 90)
local picks, xr, phi, event = mind:think(function() return x end, feasible)
mind:note(xr, phi, picks, event, totals, tick)
-- ...then, when the world has moved on:
mind:settle(totals, Senses.encode(...), tick, false)
```

`totals` are the readings' running totals; the mind works with their differences. `feasible(picks)`
says what the world would accept. Cut a life into windows and tell the coach when each ends and what
it scored: `coach:beginEpisode()` and `coach:endEpisode(score)`.

## What earned its place

Everything here was measured against alternatives in an offline prototype, on an arena of scripted
fighters, a foraging puzzle, a sheep-and-wolves world, and a generator of random worlds with four held
out that were never tuned on. The running log is `C:\lua code\FINDINGS.md`; the short version:

- **One linear outcome model with a flag per option** carries the policy. Every attempt to judge an
  option by its consequences alone made the creature uniformly worse.
- **Per-option effects models, one step ahead.** A second step, longer chains, and bootstrapped
  returns all lost: each projected step compounds the models' error.
- **A short horizon.** Longer waits credit every option with whatever happens later; the memory of
  surprises carries the long consequences instead.
- **Memory of surprises.** A surprisingly good moment is stored with its senses and picks and replayed
  when the senses come near, for as long as its retests keep earning it.
- **Acquisition.** Where a reading keeps being wrong, a search over operator pairs of the raw inputs
  invents a new input with a tight prior.
- **The coach.** Random windows at birth seed everything, and a creature doing worse than a random
  policy after a fair try forgets its conclusions and explores again. This is what turned a coin-flip
  failure on new worlds into every seed learning.
- **The slot layout.** The same seven descriptors for whatever fills a slot, in the creature's own
  frame, with no world flags. A creature that has lived in other worlds learns a new one in two to
  four times fewer rows.
- **Shared effects across a kind.** The physics is the same for everyone; sharing it is the biggest
  saving in memory and the fastest learning of what acts do.

## Instincts

A knowledge file is a table of revisable priors, loaded with `mind:learnFrom(file, NAMES)`:

```lua
return {
    priors = { { reading = "dealt", feature = "act=strike", w = 15, conf = 50 } },
    features = { { op = "mul", a = "hostdist", b = "hostclosing" } },
    effects = { { option = "move=approach", sense = "itemdist", dw = -0.2, conf = 2 } },
    curious = { { a = "hosthp", b = "act=strike" } },
    memories = { { x = { itemthere = 1, itemdist = 0.1 }, picks = { 3, 2, 1 }, y = 20 } },
}
```

A prior sets a weight and how sure the creature starts; a feature declares a pair worth making; an
effect says what an option does to a sense; a curious pair is searched first; a memory matches only on
the senses it names. `mind:distill(NAMES)` produces one of these from a creature that has lived, for a
spawn of the same kind; `mind:save()` and `mind:load()` are the whole creature as plain data.

## Checking it

```
lune run scripts/mind [episodes]     # env WORLD=2|24, SEED
```

runs a creature in the prototype's worlds without Roblox and reports rows to threshold, the final
score against a greedy hand policy, microseconds a think, and a save-and-reload check.
