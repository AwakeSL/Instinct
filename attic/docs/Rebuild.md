# Instinct, rebuilt around prediction

A specification for making the package do what its first line already says.

> Creatures that predict what their senses will report, and act to close the gap.

Today it does not. There are exactly two sources of error — `Think.selfErrors`, which walks the
creature's needs, and `Think.predictedErrors`, which walks its instincts — and neither predicts a
percept. The creature predicts its *needs*. The tagline promises perception.

This document specifies the version where that is true, and the consequences of it being true.

---

## 0. What the engine does, and what the creature holds

The package owns machinery; the creature owns a model. Everything below is on one side or the other,
and the line matters because the creature is never asked to learn the machinery.

| the engine does | the creature holds |
|---|---|
| groups sensory returns into subjects | which readings it can form |
| maintains estimates from evidence, widens them in absence | which predictions it holds |
| the `(value, spread)` arithmetic -- update, blend, relax | what it prefers |
| checks predictions when their horizons come due | its dials |
| picks the action predicted to cancel most error | |

A creature never learns *that there are things*. It learns what those things are like. That is
roughly the line between what an animal is born with and what it works out, and it is the same line
the authoring doc draws when it says the package owns the arithmetic and you own every name and
number.

### What a subject is

A subject is **not a thing in the world**. It is a slot that keeps one set of readings apart from
another. The room is a subject because its colour must not be confused with the square's; two noises
need two subjects because otherwise their directions collide.

So a noise from an unknown source is a subject -- provisionally, and honestly. `noise_12` claims only
*these readings belong together and are not those readings*. It asserts nothing about a noise being
an object.

What happens next is the interesting part:

- if its direction keeps tracking something visible, **association merges them** -- one subject now
  receiving readings on two channels
- if it does not, it stays separate and relaxes to nothing, costing nothing

That is sound-and-sight fusion with a mechanism instead of an assumption. A creature that has merged
them expects to hear the thing it can see. One that has not holds two unrelated beliefs and does not
know they are the same animal -- a real state, and one it can come out of.

It also decides whether *seeing it leave while still hearing it* is a contradiction at all. Unmerged,
there is none: a sound continues and a thing departs, unrelated facts. Merged, it is a hard conflict
demanding attribution. Same world, different creature, according to what it had worked out.

**Two subjects are always present.** `self`, for everything arriving through the body channel, and
`here` -- the ambient and unattributable. Room colour, light, temperature: true of the situation
rather than of anything in it.

The cost is that the subject count is dynamic and can spike, since every transient noise takes a
slot. Bounded as everything else is: `attention` caps how many are carried, and unreinforced ones
relax to nothing and are collected by the forgetting that already exists.

### Association is the core pointed at a different question

Grouping returns into subjects looks like a second hard problem. It is not: **a return belongs to the
track whose prediction best explains it** -- over whatever readings it carries, spatial or not. Precision-weighted match, exactly as
everywhere else.

Which makes mis-association behaviour rather than failure. Two similar animals close together and
moving alike will have their returns swapped, and the creature will be confused in the way a real one
is.

**The gate is the track's own spread.** How near a return must fall to count as the same thing is
just how confident the prediction was: a track held tightly accepts only what lands close, a vague one
accepts a wide range. How willing a creature is to call this the same thing as that is exactly how
sure it was about where it would be. No new parameter.

### Matching is not similarity

Similarity matching would ask *does this return look like that track's last observation*, and would
clump every blue thing together. Prediction matching asks *is this what that track's model said would
happen* -- and for anything moving, the prediction is at a new position, so a return sitting at the
old one is a poor match however alike it looks. Prediction beats similarity because it accounts for
change.

So three blue cubes do not merge. They agree on colour and disagree on position, and position
discriminates.

**And a reading that matches everything equally cannot decide anything**, which needs no rule to
enforce. A return goes to whichever track explains it *best*, so the scores are compared. If every
track predicts blue and the return is blue, colour lifts them all identically and the ranking is
untouched. Common factors cancel.

That is the discrimination rule of §3e appearing a third time:

- in **learning** -- an ever-present square explains nothing, being equally there whether or not the
  prediction failed
- in **blame** -- a candidate cause must differ between the cases
- in **perception** -- a reading identical across candidates cannot tell them apart

The same principle each time, and each time it falls out of comparing rather than being imposed.

**Merging is not categorising.** Two blue cubes can be different subjects of the same kind: separate
things that resemble each other. Merging says *these readings are one thing*; a kind says *these two
things are alike*. Conflating them produces a creature that believes every wolf is the same wolf.

### A sense is abstract, and nothing needs a position

The engine has no idea what hearing is. A **sense is a channel that delivers named numbers** and
carries a reliability that widens the spreads of readings taken through it. That is the entire
contract. `sight`, `hearing` and `smell` are names an author chose; a channel called `market`
delivering `price` behaves identically.

So association does not need position. The honest statement is **does the return match what the track
predicted**, over whatever readings it has -- not *does it land where predicted*. Position is an
excellent discriminator in a physical world, because things move continuously and cannot be in two
places, so a predicted position is very informative. Nothing in the mechanism requires it. Pitch
works. Temperature works.

**What a channel carries bounds what can be told apart.**

- returns carrying direction -- two simultaneous sounds are two tracks, each followable
- returns carrying only loudness -- the creature hears *something loud*, and can never separate two
  sounds however clever it is

That is a structural perceptual limit falling out of the data, not a dial for how good its hearing
is. Pushed to the end: returns carrying nothing that distinguishes them collapse into a single track,
which is correct rather than broken. **Two things a creature cannot tell apart are one thing, to it.**

Nothing spatial lives in the engine. `visible`, `between`, facing, occlusion are all authored
readings whose meaning is the game's. The engine knows only that they are readings predictions can be
built from -- which is why this is a predictive model over whatever channels are declared, and the
animal is what appears when those channels happen to be senses.

### Matching is what as well as where

Geometry alone is not enough. A lion's roar and a cat's purr can arrive from the same spot and still
not be the same animal, while a footstep and a jump plainly are.

So a track predicts not only where a thing will be but **what returns it produces** -- this one makes
footsteps, that one roars, this one is silent. A roar near a track that has never roared is a poor
match whatever the geometry says. This is the perceptibility of §3a taken one step: that predicts
*whether* it will be sensed, this predicts *what it will sound like*, and both are ordinary
predictions about a subject.

**So the engine owns the mechanics and the creature owns the criterion.** Matching returns to tracks
is fixed machinery; what counts as a match falls out of what the creature has learned. Association is
not a perceptual primitive sitting under the model -- it is the model being used.

A creature that has never met a lion will merge the roar and the purr, and that is correct. It cannot
know yet.

### Association must be revisable

Merging is covered: a return joins the track that best explains it. Splitting is not, and is needed.
A track that keeps failing to predict its own returns -- roaring when it should purr -- may not be
one thing. The trigger is the same persistent unresolved error that drives everything else; the
resolution is a split rather than a revised belief.

This is also the way back out of a wrongly merged noise and sight. Without it, a creature that once
decided a sound belongs to a thing can never undecide it.

#### As built

A split is a **refusal to merge**, which is why it needs no machinery for dividing a history.

Each track carries a decaying average of how much of what it is handed it fails to account for. When
that average passes a threshold, the next return that would have joined it opens a new track instead.
The old track keeps everything it had worked out and simply stops receiving what never fitted; if
nothing reinforces it, it fades and is collected like anything else.

`attribution` sets the threshold -- how bad an explanation a creature will live with before it revises
what it is looking at rather than what it believes. The *count* barely matters: a decaying average
reaches any modest count quickly, so what actually separates a credulous creature from a stubborn one
is how poorly it will let a track do. (A decaying count has a ceiling of `1 / (1 - RECENT)`, and a
demand above it means a patient creature does not take longer to split -- it can never split at all.
That was a real bug, caught by the dial having no visible effect.)

**The scenario that exercises it is narrower than it first looks**, and the narrowing is itself the
finding. Two things far enough apart to strain a track are also far enough apart that they never merge
-- the second return simply opens its own track, which is correct. A track can only be *torn* by what
it once plausibly held. So the case is two animals that **sounded alike and then did not**: early on,
one thing is the right answer, and the creature is not talked out of it by a return that lands a
little off. As they separate, the single track is asked to be both, and keeps failing.

It also takes an animal with **poor ears** -- which does not mean one that hears wrong things, but one
that holds what it hears loosely, and so can be talked out of it. `reliable` on a sense, declared since
the first draft and never read until now, is what says so.

Specified in `test/next/SplitSpec.luau`, including the creature that will not be told, which holds them
together to the end.

Kinds carry the load meanwhile. If roars and purrs are readings and the creature holds kind-level
beliefs -- lions roar, cats purr -- a lion it has never met inherits them at once and the next pair is
not merged. Experience with the category transfers where experience with the individual cannot.

### Worked: five noises, each closer

- **First.** Nothing predicts it. A track opens, somewhere behind.
- **Second**, slightly nearer. The track has one observation and so predicts *roughly where it was,
  widening*. The second falls inside that and associates. Now there are two observations and a motion
  estimate.
- **Third, fourth, fifth.** Each associates and sharpens it. `delta(distance)` is consistently
  negative.

By the fourth the creature holds one thing, approaching, at a rate it is increasingly sure of -- and
predicts a sixth, nearer still. It is also **surprised** if the next comes from the other side, which
is the more useful half.

If they do not associate -- five pops scattered around the room, seconds apart -- that is correct as
well. Five subjects, no relationship, each relaxing to nothing, because there is no relationship to
find.

Two consequences. **Kinds generalise across separate tracks**: five unrelated noises still share the
kind *sound*, so a creature hurt by approaching noises before applies that to a brand-new track at
once. And a creature that associates badly can still learn *a noise tends to be followed by a nearer
noise* as a cross-subject prediction -- but it needs many examples and generalises poorly, where the
track version needs three pops.

So association quality is a real difference in competence. One creature hears **something
approaching**. Another hears **a series of unrelated bangs**, and has to work out statistically and
slowly that bangs tend to precede nearer bangs. Same world, same ears.

### Binding: which readings belong to the same thing

Everything above assumes a return arrives already bundled -- colour, position and rotation in one
packet. That is an assumption, and worth naming. If the senses are genuinely separate channels each
returning a list, nothing says `colour[1]` goes with `position[1]`.

**In a single frame there is no answer.** Three colours, three positions and three rotations contain
no information distinguishing *three things with three properties* from *nine things with one
property each*. Not a hard inference -- an impossible one. The information is not present.

**Binding requires time.** What binds blue to a position is that they change together: when the
position moves, blue moves with it, while blue and some other position drift independently. Things
that co-vary belong to one thing.

Which is the same merging, with a different criterion -- not *did this land where predicted* but *do
these keep moving together*:

- begin with nine provisional subjects, each holding one reading
- track each over time
- merge the ones whose changes correlate
- arrive at three subjects with three readings each

Same error-driven correction as everywhere else. Bind blue to the wrong position and the resulting
predictions fail, and the split rule pulls it apart again.

**A static world cannot be bound.** If nothing changes, nothing co-varies, and there is no way to know
which readings go together. A creature learns that objects exist by watching things move as units.
That is not a limitation to fix; it is what the information supports.

**The combinatorics are brutal** -- `(N!)^(M-1)` bindings for N things across M channels. Incremental
merging avoids the search, but a creature doing this from nothing is slow and wrong for a while.

### How much the game hands over

| the game supplies | the creature must work out |
|---|---|
| `subject = wolf7` with readings | nothing -- today's behaviour |
| bundled returns, unlabelled | which returns are the same thing over time |
| raw per-channel lists | that, and which readings belong together at all |

Most games belong on the first rung and should stay there. The third is for a creature whose
perception is genuinely its own achievement, and it is a stage rather than a switch.

Supply `subject` and association is skipped. Omit it and the engine works it out -- which is what a
game wants when it wants creatures that can genuinely lose track of something, or mistake one thing
for another.

---

## 1. One mechanism

Everything a creature holds becomes an answer to a single question:

> Given what I am perceiving and what I am doing, what will I perceive next?

An error is the gap between that answer and what the senses then report. Error always teaches. Error
on a reading the creature has a **preference** about also moves it.

That distinction — teaches versus moves — is the only place the old split between "perception" and
"needs" survives, and it is not a split between kinds of prediction. It is a fact about whether the
creature would rather the number were different.

### Why an action is not a special case

An action is a condition on a prediction, not a separate category. *I struck it and it went green*
has the same shape as *it was closing and I got hurt*. Both are: given this situation and this doing,
expect this reading. Once that is admitted, three mechanisms collapse into one:

| today | after |
|---|---|
| `expects` — the creature's needs | a **preference** over a reading |
| `emotion` — a derived feeling | a reading built on a prediction, keeping `decays` and `modulates` |
| `instinct` — what a kind predicts about me | a prediction conditioned on a **kind** |
| `sign` — seeing one thing tells you about another | a prediction conditioned on a **different subject** |
| action `predicts` — what my move does | a prediction conditioned on an **action** |

`expects` stops being a kind of prediction and becomes the thing that turns error into movement.

---

## 2. Readings

`quantity` and `feature` merge. Both are names for something the creature can read, and the only
difference was where the number came from — which is already captured by the sense a feature is
`from`.

A **reading** is identified by *(subject, name)*. The creature's own body is a subject like any
other; `fullness` is the reading `fullness` about `self`, arriving through the `body` channel.

Readings are raw or derived, exactly as features are today:

```lua
i:reading("distance", { from = "sight" })                              -- raw
i:reading("looming",  { is = { "proximity", times = "size" } })        -- derived
i:reading("fullness", { from = "body" })                               -- raw, about self
```

Nothing else changes about them. Derived readings still carry spread, still propagate uncertainty
through the operator arithmetic, still cost time to compute.

**Consequence.** "What a creature can believe is bounded by what it can construct" stops being a
slogan about features and becomes true of everything it holds, including its own hunger.

---

## 3. Predictions

One table, replacing `instinct`, `believes`, and an action's `predicts`:

```lua
predicts = {
    -- a kind predicts something about me, whatever I am doing
    { about = "wolf", of = "self", integrity = { -0.9, by = { "proximity", "closing" } },
      after = { 3.0, spread = 2.0 } },

    -- ...or a pattern of readings, with no kind declared for it at all. A kind is a named feature
    -- pattern, so a condition may name the pattern directly. This is what lets a creature hold
    -- "water that is green" without anybody having invented a `poison` kind for it to notice.
    { about = { wet = "high", green = "high" }, of = "self", integrity = { -0.4 }, after = 20 },

    -- doing something predicts something about me
    { doing = "drink", of = "self", hydration = { 0.8, spread = 0.1 }, after = 4.0 },

    -- doing something predicts something about the thing I do it to
    { about = "wolf", doing = "stab", of = "target", integrity = { -0.7 }, after = 0.2 },
}
```

`about` and `doing` are both optional. A prediction with neither is a bare expectation about a
reading — *this tends to be so*. A prediction with both is the narrowest kind, and by the same
argument the docs already make about specificity, it will be the slowest to earn confidence.

Beliefs stay keyed so that a particular thing specialises from its kind, and the existing blend and
relaxation between the two is unchanged. It is one of the best parts of the package and this does not
touch it.

---

## 3b. Readings versus predictions, and layers

A **reading** is what is. A **prediction** is what will be. A reading may be built from other
readings, and those from others again — but however deep it goes it is still a statement about now.
Only a prediction reaches forward.

Layers are readings built on readings:

```
raw sight  ->  proximity, size, closing  ->  looming, threat  ->  predicted
```

The creature does not predict every raw number it can sense. It predicts at whatever layer it holds
beliefs about, and predicting `threat` once is worth more than predicting fifty raw readings
separately. That is what layers are for.

**Acquired features are how a creature grows its own layers.** Inventing `closing` out of
`delta(distance)` is building a new level of abstraction for itself. It is the same mechanism as an
authored derived reading, arrived at differently — which is a better reason to build the search than
that the plan calls for it.

## 3a. Estimates and projections

A reading is not what the senses said this tick. It is an **estimate the creature maintains** about a
property of a subject, updated by whatever evidence arrives. A prediction is the expected **future
value of such an estimate**. Those are different things: one is held and revised, the other is
derived and checked.

Object permanence proves they must be. If a reading were a passthrough of current sensation, looking
away would destroy the creature's belief that anything is there. The authoring doc already says
otherwise -- a subject belief keeps predicting out of sense range, widening as it goes -- and that
only works because the estimate is held rather than read.

| | what it is | how it changes |
|---|---|---|
| **estimate** | what is currently held about a subject's property | evidence updates it; absence widens it |
| **projection** | what that estimate is expected to be at T | derived from estimates and predictions |

**So the README's line is loose.** "Predict what their senses will report" suggests modelling
sensations. The creature models **subjects and their properties**; senses are evidence about them.
Sound from a direction and sight of a shape update one estimate of one creature, and losing either
does not destroy it.

### Predict properties AND perceptibility

Predicting a raw sensory pattern is brittle. *I will see an explosion in three seconds* is falsified
by seeing ash, because the explosion is over. *Its `stability` will reach zero* is confirmed by ash.
So predictions about what a thing **is** should sit at a layer abstract enough to survive whichever
sensory pattern realises them.

But that is only half of it. A creature that sees something, turns away, and turns back must predict
that it will see it again -- and a creature that stops hearing something it always hears when near
must take that as reason to doubt it is there. So it also predicts **whether it will perceive at
all**.

Perceptibility is a **relational** reading: about the pair (me, it), not about the thing. Whether
something is visible depends on facing, distance and what lies between. The authoring doc already has
this shape in `between` features -- "computed across a pair, not from the creature outward" -- so
`visible` and `audible` are `between(self, subject)` readings, and predictions about them are
conditioned on the creature's own actions. Turning changes facing, facing changes predicted `visible`,
turning back predicts it again.

### Absence is evidence

Today a subject that is not perceived is simply absent from the list, and the belief widens on a
timer. Absence carries no information at all.

It must. **Not perceiving something is evidence against its presence, in proportion to how confidently
its perceptibility was predicted.** Not seeing what is behind you means nothing. Not seeing what you
were certain was in front of you means a great deal.

This makes object permanence sharper than relaxation alone:

- absence **explained** by facing away -- the belief barely widens, nothing surprising happened
- absence **unexplained**, staring at where it should be -- large error, and the belief collapses

Same mechanism, no special case; the difference is only whether perceptibility was predicted.

### Contradiction between senses

Hearing says present and sight says absent, both confidently. That error has three honest places to
land: the presence belief is wrong and it left, the sense is wrong, or the **identity** is wrong and
that sound was never this creature.

`attribution` already decides between the first two -- the doc assigns it exactly this job, whether
error lands on the world-belief or on the creature's own perception. A creature that trusts its ears
concludes the thing is still there and it cannot see why; one that doubts them concludes it misheard.
Both are correct, and which creature it is was already authored.

The third possibility is the identity loop of §10.5 arriving as a consequence rather than an
assumption, which is the strongest argument that it belongs in a later stage rather than never.

### Many predictions, one state

Predictions are not rival stories competing to be true. Each contributes to a single estimate per
(subject, reading), merged by the rules in §3c. There is one coherent projected state, assembled from
many contributions.

**Theory of mind stops being special.** Predicting where another creature will walk is a prediction
about *its* position estimate, not about the creature's own vision of it -- which is why it survives
looking away. What is predicted was never the retina.

### Predictions can still feed predictions

An estimate and a projection both produce values, so a projection can be an input like anything
else:

```lua
i:reading("dying", { predicts = "integrity", after = 3 })          -- what I think health will be
i:reading("anger", { is = { "dying", times = "canFightBack" } })   -- built on that prediction
```

"I predict my health will fall" is an ordinary input, and "so my anger rises" is built on it exactly
as `looming` is built on `proximity x size`. Layers apply to predictions, not only to readings.

### Emotions stop being a subsystem

A fear declaration today is already this, wearing a disguise:

```lua
i:emotion("fear", {
    from = { of = "self", quantity = "integrity", falling = true, efficacy = "low" },
    decays = 0.8,
    modulates = { precision = { integrity = 1.6 }, commitment = 0.5, tempo = 1.8 },
})
```

`falling = true` means *the prediction about integrity is negative*. Fear is a value derived from a
prediction, computed by bespoke machinery -- `Emotions.settle` and a hardcoded `matches` over error
shapes -- to produce what an ordinary derived reading would produce anyway.

So `i:emotion` mostly stops existing. What survives is `decays`, because relaxing over time is not
something a plain expression does, and `modulates`, because acting back on the dials is genuinely a
different power. The fourth subsystem to dissolve, after `expects`, `instinct` and action `predicts`.

### Two risks

**Cycles.** Anger built from a prediction about health, and that prediction scaled by anger, is a
loop. `Percepts.read` already tracks `resolving[name]` and raises "feature depends on itself", so
this is a load-time or first-evaluation error rather than a hang.

**Horizon arithmetic, and this is open.** If a prediction three seconds out feeds one that looks two
seconds ahead, is that five or two? Either horizons compound, so a deeper chain reaches further, or
an inner prediction is evaluated at the *outer* horizon and its own `after` is only a default. The
second keeps "at time T, what will everything read?" a single consistent question instead of letting
each layer drift to its own clock, and is the way this document leans -- but it is a real choice and
it decides what a deep chain means.

### As built

Both halves exist, and the horizon question turned out to be dodgeable rather than answerable.

A **projection reading** is what the creature expects, rather than what it holds:

```lua
i:reading("dying", { predicts = "integrity" })            -- what I expect my health to be
i:reading("soon", { predicts = "integrity", after = 2 })  -- ...within two seconds
```

`after` does not compound anything and does not reach further. It **narrows**: only predictions that
come due within that long have anything to say. That is a question a creature can answer without
anybody deciding whether horizons add, and it is the useful half of what `after` was wanted for.

An **emotion** is then an ordinary derived reading with exactly two powers a plain expression lacks:

```lua
i:emotion("fear", {
    is = { "dying", inverted = 1 },
    decays = 0.5,
    modulates = { tempo = 2.0, caution = 0.2, precision = { integrity = 4 } },
})
```

- **It lingers.** `decays` is the fraction it keeps each second, and what lingers can only ever raise
  what the moment says, never lower it. Onset is immediate; leaving is not. A creature does not become
  afraid gradually, it stops being afraid gradually -- and that asymmetry is the whole reason an
  emotion is not simply an expression.
- **It acts back on the dials.** A factor is earned in proportion to how strongly the thing is felt,
  so a creature feeling nothing is exactly the creature it was declared to be. `precision` is the same
  arithmetic aimed at one reading: a frightened creature does not see its health more accurately, it
  treats what it sees as more decisive.

Everything else about an emotion is a reading, because that is all it is. It can be read, built on,
used as a condition, or scaled by. `i:emotion` survives only to carry those two words.

**Fear of what is about to happen falls straight out of this**, and is the case worth pointing at: a
creature at *full health* is afraid because something it can see is expected to cost it, and less
afraid of the one further off. There is no rule anywhere about wolves being frightening. The fear is
built on a projection instead of a reading, and that is the entire difference.

**The cycle risk is real and is caught**, and it is narrower than expected. Panic about a *wolf*
scaling a prediction about the *creature* is not a loop, because a reading is held per subject and
they are different subjects. Only a feeling that feeds back onto itself is, and `deriving` raises
"depends on itself" the first time it is evaluated.

Specified in `test/next/FeelSpec.luau`.

## 3c. Two forms of prediction, and how they stack

A creature will hold several predictions bearing on the same reading at once: the wolf costs it
integrity, and so does bleeding. How those combine depends on which form they are, and both forms
are needed.

**A change.** *This will cost me 0.3.* Changes **add** — a wolf taking 0.3 and a wound taking 0.2
means expecting to lose 0.5. Spreads add as variances, which is what expression arithmetic already
does.

**A level.** *This will read 0.7.* Levels do **not** add; two guesses of 10 and 12 do not make 22.
They merge weighted by precision, so the belief held more tightly dominates.

| form | example | stacks by |
|---|---|---|
| change | `integrity = { -0.9 }` | adding |
| level | `colour = { 0.7 }` | precision-weighted merge |

The package today has only changes, and preferences are its only levels. That is precisely why it
cannot predict that green follows blue: predicting a colour is a prediction of a *level*, and there
is no such thing to write.

Predicted level of a reading is therefore: what it reads now, plus every applicable change, merged
with every applicable level prediction. Preference error is what the creature wants minus that.

### When adding is wrong

Adding assumes the causes do not interact, and often they do. A wolf costs 0.3 and a wound costs 0.2,
but if bleeding makes the wolf hang back -- or draws it in -- 0.5 is not the answer.

This needs no new way of combining. It needs the creature to notice that *wolf and bleeding together*
is its own circumstance with its own answer, rather than two circumstances stacked:

```lua
{ about = "wolf",                                integrity = { -0.3 } }
{ about = { bleeding = "high" },                 integrity = { -0.2 } }
{ about = { kind = "wolf", bleeding = "high" },  integrity = { -0.1 } }   -- not 0.5
```

So composition has two levels:

- **Independent conditions add.** Separate causes, separate contributions.
- **A more specific condition overrides the ones it refines** -- instead of them, not added to them.

When the specific one takes over is not a rule that has to be written. The authoring doc already
supplies it: a narrower combination occurs less often, accumulates evidence more slowly, and cannot
reach confidence no matter how consistent it is. So a conjunction overrides its parents only once it
is held **more precisely** than they are, which its own rarity delays. Until it has earned that, the
sum stands. Precision-weighting does the work; nothing special is added.

**This widens what the search is for.** A missing conjunction announces itself the same way a missing
reading does -- the prediction is consistently wrong under a particular circumstance. So the search
invents *conditions* as well as *readings*, and both are the same act: carve the world differently so
predictions get sharper. One carves by composing readings, the other by composing circumstances.

## 3d. Conditions may be about another subject

Every condition so far is about the prediction's own subject: its kind, its readings, or what the
creature is doing. That cannot express *the triangle stopped spinning, so the room turned red*, where
the cause and the effect are different things.

The design already has this shape under another name. A **sign** is exactly a prediction whose
condition is one subject and whose target is another:

```lua
i:sign("smoke", { seeing = { kind = "smoke" }, tells = { kind = "fire", proximity = { 0.7 } } })
```

So signs are not a separate mechanism either. A condition may name another subject, and `sign`
becomes sugar for that -- the sixth subsystem to fold in.

## 3e. What can explain a surprise

When a prediction breaks with nothing obvious to blame, the belief moves hard, widens -- confidence
is losable -- and the event is recorded as unexplained, waiting for something to make sense of it.
Nothing has to be blamed immediately.

**A candidate must discriminate.** The tempting rule is "only something that changed can explain a
change", and it is wrong: a green pond never changes, and green is still the explanation. The real
test is not whether a candidate varied during the episode but whether it **differs between the
episodes where the prediction held and the ones where it broke**:

- *green* -- there when it got sick, absent when it did not -- discriminates, a real candidate
- *a square that is identical in every episode* -- discriminates nothing, never a candidate, however
  reliably present it was

This is the reason the buffer must keep the predictions that came out **right** as well as the ones
that came out wrong. Keep only failures and the ever-present square looks as guilty as anything else,
because it was there every time the creature was surprised. Keep both and it is eliminated at once,
because it was equally there every time the creature was not.

## 3f. What may be blamed, and what does not transfer

**A creature's own actions are candidate causes.** Today only perceived subjects are -- the recent
run records things seen, never things done -- so a creature could never conclude that something
happened because of what it did. Its own recent actions belong in the candidate set, arguably ahead
of anything it merely saw.

With that, a creature alone in a black room with one unexplained button learns *X makes it white*
from one press, and on the second press -- white, not white again -- discriminates on the room's
prior colour and refines into two conditions:

```
black + X  ->  white
white + X  ->  black
```

**Toggling is not a special case.** It is a conditioned prediction found by the same machinery that
finds green ponds, and nothing was built for it.

### Doing and watching are different things

Its own action is a `doing` condition, internal to what it is deciding. Another creature's action is
a reading about another subject, external and merely seen. Nothing connects them, and nothing should:
there is no built-in notion that *what I do* and *what I watch you do* are the same category of event.

So a creature that has learned what its own press does knows **nothing** about another creature
pressing. It can learn that separately, at the same cost, from the same machinery -- and it must.

That is the honest boundary of a creature without theory of mind, and the reason theory of mind is
its own stage rather than a free consequence. A creature that had it would transfer in one
observation; this one learns the world twice.

### Events must arrive structured, never as labels

An opaque token cannot generalise. If the creature is handed `"creature_X_fired_A"` as one symbol,
then `"creature_Y_fired_A"` is a different symbol sharing nothing with it, and no amount of
experience will ever connect them.

An event arrives as **a subject with readings on it**:

```
subject  = creature X
readings = { firing_A = 0.8 }        -- how sure it is that this is what they are doing
```

Three generalisations then fall out of the same data, as three conditions over it:

| | condition | generalises over |
|---|---|---|
| any creature, doing anything | `about = "creature"` | what was fired |
| anyone, firing A | `about = { firing_A = "high" }` | who fired it |
| that creature firing A | `about = { kind = "creature", firing_A = "high" }` | nothing; the specific case |

The third is the **conjunction** of the first two, so §3c already governs it: it refines both parents
and overrides them only once held more tightly, which being narrower takes longer. A creature reaches
for the loose generalisations first and earns the specific one only if the specifics matter.

**The constraint this puts on authoring is worth stating plainly, because getting it wrong silently
ruins a creature: never hand over an opaque event label.** `"wolf7_bit_me"` is a dead end.
`subject = wolf7, biting = 1` generalises three ways for nothing.

An observable action is one reading per action, valued by confidence rather than boolean -- watching
what somebody is doing is exactly the sort of thing one can be wrong about. And *doing anything at
all* need not be supplied: `atLeast` is a declared operator, so `atLeast(firing_A, firing_B, ...)` is
composable, and the creature can **acquire an abstraction over actions** itself if that predicts
better than any single one. The feature search, inventing a category, with nothing added for it.

### Generalisation requires categorisation

Learning about one creature partly becomes a belief about its **kind**, so a creature never seen
before inherits it -- weakly from one example, strongly from ten. That is the existing subject-to-kind
blend and it needs no changes.

But only if they are seen as the same kind of thing. Two opaque subjects sharing no kind are learned
from scratch and never inform each other. Kinds are tagged by the game today; a creature that works
out for itself that these two are the same sort of thing is doing clustering, which is the same
family of problem as association in §0 and takes the same answer -- bake it in, or defer it.

## 4. Preferences

What makes a creature act:

```lua
wants = {
    fullness  = { 0.90, spread = 0.05, after = 30 },
    integrity = { 1.00, spread = 0.05 },
}
```

A preference is a prior over a reading. Error is `wanted − projected`, where the projection uses the
creature's own predictions about that reading — including, when `after` is set, what it predicts the
reading will be later if nothing changes.

**0.3.0's drift belief dissolves into this.** `drift|fullness` was a bespoke answer to "what will this
reading be in thirty seconds if I do nothing", which is just a prediction with no `doing`. The
foresight behaviour survives; the special case does not.

---

## 5. What learning becomes

Every prediction that comes due is checked against what the senses now report about that subject, and
the belief updates. This is the existing pending mechanism generalised from *self quantities* to *any
(subject, reading)*.

**`of = "target"` learns, finally.** It never did because the check read `state.level` — the creature's
own. A target's integrity is a reading about another subject and always was.

**Predicted gains need no rule.** Today `predictedErrors` discards any non-negative delta, so a good
thing pulls a creature nowhere and the "newborn drawn to water" in the authoring doc cannot exist.
Under preferences it falls out: a predicted rise is motivating exactly when a preference says higher
is better and the creature is below it. A full creature correctly ignores more food.

---

## 6. What stops it exploding

A belief per (subject × reading × context) is unbounded. Three things bound it, and all three already
exist.

**It predicts what it has a belief about, not everything.** The creature does not enumerate its
sensorium. It holds predictions it was authored with, plus ones formed from surprise — the existing
association machinery. The model grows where the world has been surprising and stays absent where it
has not. This is the load-bearing bound.

**`attention`** decides how many subjects are predicted about at all on a given tick.

**`capacity`** decides how much structure can be held: how deep a derived reading may compose, how
many contexts a prediction may be split across.

---

## 7. Where acquired features land

A discovered reading is a **better predictor**, and the objective is now general and honest: does
using it lower prediction error on the next reading?

`closing` becomes discoverable for the reason the authoring doc gives — change-in-distance predicts
next-tick distance far better than distance does — and that is true whether or not anything ever hurt
the creature. Under the current design it could only be found by predicting harm better, which is
both narrower and stranger.

The episode buffer we spent two rounds designing is no longer a thing to build. Every resolved
prediction is a sample of *what I saw* against *what happened*, including the ones that came out
right, which is what stops spurious features surviving.

Settled in design, unchanged by the rebuild:

- **Temporal operators.** `recalls = true`, `apply(a, b, past)` where `past` carries `input`, `output`
  and `since`, kept per (site, subject). This is what makes `delta` expressible at all.
- **`ingenuity`** — how deep a composition may go. **`retention`** — how much is kept to test against.
  **`insight`** — how often it looks. **`attribution`** — how much better a candidate must be, since
  the authoring doc already assigns that dial to whether a creature revises its beliefs or its way of
  seeing. *(All four built. `retention` turned out to be the price of `ingenuity`, which was not
  planned and is the more interesting half of the pair.)*
- **Content-addressed names**, so two creatures that independently invent the same reading agree.
- **Reference-counted death**: dropped from a prediction that keeps failing with it, deleted when
  nothing uses it.

### As built

`next/Acquire.luau`, wired into the tick.

A creature goes looking only where it keeps being wrong: a running tally of surprise per prediction,
gated by `insight` both for how much failure it tolerates first and for how often it looks at all.
Nothing changes from one tick to the next, and the search is the one expensive thing in the package.

**The space is the operators it was declared with.** An idea is a little tree -- a reading, a constant,
or an operator applied to two of those -- and it is built from whatever `i:operator` calls the world
made, in a fixed order so two creatures given the same world reach the same ideas. Adding and
subtracting come along free, because the expression language already sums the elements of a list.
Constants sit on the right where an operator wants one: `inverted` against 1, `delta` against nothing.

**`ingenuity` is how deep it may go**, one to three. Past depth one the space cannot be enumerated --
eight readings and six operators is hundreds of thousands of trees by depth two -- so it is walked as a
**beam**: at each level only the best few ideas so far are extended, and only by a raw reading or a
constant. That reaches `(a - b) x c` without ever considering the millions it would otherwise have to.

Each idea is scored by fitting a free scale factor against the moments the creature actually lived
through, so it is judged on whether it carries the signal rather than on its units. Two ideas that say
the same thing about every moment lived through are the same idea, and the one reached first is kept.

Three things keep it from believing coincidences, and all three were earned the hard way:

- **Occam.** A deeper idea must beat a shallower one by a margin per level. An elaborate explanation
  that fits no better than a simple one is worse, and it has far more ways to fit a handful of moments
  by accident.
- **The margin grows with how many ideas were tried against how much evidence there was.** A creature
  that can reach four compositions and one that can reach four hundred are not in the same position
  after both find something that fits a little better.
- **Reaching further costs memory.** `retention` is what pays for `ingenuity`: a creature that can
  think of hundreds of ideas cannot judge between them on eight moments, and one that tries will adopt
  an elaborate coincidence every time.

**It may build on the idea it already has.** A composition is otherwise never built on a composition --
the space would grow without bound and creatures would end up with towers of private notions -- but the
one idea a prediction has already committed to is different. Refusing to build on that is refusing to
let it *refine*: a creature that works out its harm goes with how fast a thing is closing could never
go on to notice that a big one hurts more, without throwing the first idea away and finding the whole
of the second in one go.

That has a consequence worth stating, because it was a surprise. **`ingenuity` is not a ceiling on what
a creature can end up believing.** It is how much of an idea it can reach in a single step. A shallow
creature arrives at the same place by a longer road, one operator at a time, provided every step earns
its keep on its own -- and since Occam makes it prefer the simplest adequate idea, a creature that
*could* have reached the whole thing at once usually takes the same road anyway. Depth decides what is
reachable only when no single step would do.

The baseline it must beat is the better of a flat number and what the creature currently says. Judging
only against its own prediction is no good once that belief has collapsed toward zero, because then
anything at all fits better than nothing.

What it adopts is registered as a reading on **that creature alone** and appended to the failing
prediction as a `times` mod, and the old belief is wiped — it is a claim about something else now, and
carrying the number over would be inheriting a verdict passed on a different idea. Afterwards an
acquired reading is indistinguishable from an authored one, which is the point.

Both halves of the episode are kept, the right ones as well as the wrong ones. Keep only the failures
and anything that was present every time you were surprised looks guilty, when it was equally present
every time you were not.

Verified in `test/next/LearnSpec.luau`: a creature hurt exactly as fast as a beast closes, and mended
exactly as fast as it withdraws, finds `delta(distance)`. The same creature with `ingenuity = 0` never
does — that dial is the whole difference, with what it senses, what it wants, and what happens to it
held identical. And a creature whose authored prediction is simply working adopts nothing, which is
what stops every creature ending up encrusted with readings that fit noise.

Also there: a world where the truth needs two operators, because the creature is hurt as fast as the
beast closes *scaled by how big the beast is*. It gets there in two thoughts -- `delta(distance)`, then
that over the size of the thing -- and an ambitious creature with no memory to test against works
nothing out at all.

### Death, and passing it on

**Reference-counted death.** An acquired reading lives as long as something is using it. When a
prediction that adopted one is still being caught out, and nothing else it can reach explains matters
any better, the creature asks the only question that counts: *would this prediction do any worse
without it?* If not, the idea is given up and the reading goes with it, since nothing else refers to
it and nothing else can.

That question is asked of the **acquired reading**, not of the prediction as a whole. A creature whose
authored scaling is simply wrong would otherwise throw away the one part of the prediction that was
right, on the grounds that the whole is still poor.

Note the asymmetry, which is the same one that runs through the rest of the package: adopting an idea
demands a real margin, because a spurious one fits a little better by luck. Keeping one demands only
that it help **at all**. Scepticism belongs where a creature takes an idea on, not where it decides
whether to abandon something that has been working.

Two guards, both about evidence rather than patience:

- It will not adopt on fewer moments than `retention` says are enough (`room / 3`). On a handful of
  moments almost anything fits, and a creature that adopts there spends its life taking ideas up and
  putting them down again.
- It will not *drop* an idea until the buffer has refilled since adoption (`room / 2`), because the
  only episodes to hand until then are from one stretch of one situation, where a reading that varies
  slowly is indistinguishable from one that does not vary at all. Judging an idea there would throw
  every idea away immediately after having it.

**Passing it on.** `i:extract(id)` hands a creature's life back out as plain declarations:

```lua
local got = i:extract(who)
for name, decl in got.readings do
	i:reading(name, decl)     -- the readings it worked out for itself
end
i:species("prey2", got.species)  -- forms, wants, dials, and what it came to believe
```

This is what makes an acquired reading worth having beyond the one animal that thought of it. A
creature works out that change-in-distance is what hurts it; extract it, declare it, and its children
are **born** knowing -- with the discovery sitting in the prediction's `by` exactly as if it had been
authored, because by then there is no difference.

It is also the only sense in which anything here is inherited. Nothing passes between living
creatures: two of the same species, one of which has had a life, and the other is none the wiser. What
one worked out dies with it unless somebody deliberately writes it down.

The prediction priors that travel are the **precision-weighted merge** of what the creature came to
believe across every subject it met -- one number about the claim in general, rather than about any
one thing.

Specified in `test/next/PassOnSpec.luau`.

Still open: content-addressed names, so two creatures that independently invent the same reading
agree; and revising an *authored* scaling that turns out to be wrong, which a creature currently
cannot do -- it can only add to one.

### Scaling a claim by what triggered it

Not in the original spec, and it turned out to be load-bearing. `by` on a prediction takes a list of
ordinary authored expressions and multiplies the claim by each:

```lua
{ about = "wolf", of = "self", changes = { integrity = { -0.40, spread = 0.10 } },
  by = { { "distance", inverted = 1 } }, after = 1 }
```

*A wolf costs me health in proportion to how near it is* is then one claim rather than a family of
them, and two wolves cost twice over, because both bear on the same reading and changes add — with
nothing anywhere saying anything about pairs.

This also forced the condition and the target apart. A prediction of the form *about a wolf, of self*
is judged against the wolf and lands on the creature, so it is checked once for every thing that might
bring it about, and the readings it scales by are read off that thing, not off the creature.

---

## 7b. Chaining, and the disappearance of `settles`

An action may declare `requires`: a pattern, in the same vocabulary as `about`, of what must be true
of the creature before it can do what it claims.

```lua
i:action("eat", { requires = { holding = "high" } })
i:action("grab", { requires = { near = "high" } })
```

There is deliberately **no `settles`**. 0.4.0 needed one because an action had to be nominated as the
answer to a missing precondition. Here the creature already predicts that grabbing raises `holding` --
that is an ordinary prediction, learnable like any other -- so naming it a second time would be naming
it once too often.

What happens instead: when nothing the creature can do serves what it wants, but something it *cannot
do yet* would have, the precondition becomes a want. From there nothing is different. It is an
ordinary want, served by whichever action the creature predicts will raise it, and if that action is
itself blocked the same thing happens again. `patience` is how many times.

The derived want inherits the spread of the preference it serves, so **a means is exactly as urgent as
its end** -- with no separate notion of a goal, a plan, or a subgoal anywhere.

Two things fall out that were special cases before:

- **Partial readiness is graded**, because patterns are. An action whose preconditions half hold is
  worth half as much, and the half it is missing is what it chains on. No threshold.
- **A blocked action is not experimented with.** `venture` scales by readiness, so a creature does not
  try to eat what it is not holding in order to find out what eating does.

`why` reports `forKey` on each row: the reading an action was taken for, when that reading was a means
rather than the end. A creature that grabs because it is hungry says exactly that -- `because` is
`fullness`, and the chosen row's `forKey` is `holding`.

Specified in `test/next/ChainSpec.luau`, including the two-link case, and `patience` deciding how far
back a creature will follow before it gives up and stands there.

---

## 8. What survives untouched

Worth being explicit, because it is most of the good parts:

- `(value, spread)` beliefs, and every update rule over them — including the taming/trauma asymmetry,
  which is the thing the whole design was staked on
- the subject → kind → species blend, and forgetting as relaxation toward the parent
- parts and occupancy
- chaining and `patience`, though not `settles` -- the behaviour survives, the declaration does not
  (§7b)
- emotions, and their modulation of precision, tempo and commitment
- blame and attribution
- the dial set, plus `venture`, `ingenuity`, `retention`
- `narrows`, which becomes *attending to something sharpens what I predict about it* — closer to what
  it meant than what it currently does

---

### A creature cannot be surer than its senses

Found while building the search, and it matters well beyond it.

An estimate narrowed without bound. Given a reading it could see exactly every tick, a creature became
more certain of it than the sense that told it -- and then any real change tripped the shock rule. The
symptom was a limit cycle: a steady drift tracked in stutters, the creature astonished every third
tick by something that had been happening all along, and its remembered outcomes carrying three times
more noise than signal.

`World.observe` now floors an estimate's spread at the observation's own. The shock rule is meant for
the world changing, not for the creature's own overconfidence.

This is the sort of thing only a search finds. Nothing about the behaviour looked wrong from outside
-- the creature tracked its health, roughly -- but everything built on *what it remembered happening*
was being fed noise.

---

### What porting a real test place found

Four working trials were moved onto the rebuild. The specs were all green before and all green after;
none of the following was caught by them, and all four were caught within an hour of running creatures
in a room with walls.

**A creature could become surer than its senses.** Covered above; found first, and the most damaging.

**Seeing something badly forgot what you knew well.** The floor on an estimate's spread was the
*current* look rather than the best one ever had, so walking away from a thing -- where the reports are
poor -- widened the estimate back out. A creature drawn to what it does not understand then shuttles
between two objects forever, re-learning each as it abandons the other. The floor is now the best look.

**A claim scaled to nothing was a runaway.** The outcome of a prediction is divided by however much
its conditions scaled it, to get back into the belief's own terms. A move that barely points at the
food scales its claim to a thousandth -- and then an ordinary moment is a thousandfold surprise, which
overshoots the belief, which shrinks the next scale, which amplifies harder. Within a minute the belief
was at 1e100 and then NaN, and the creature was broken for good. Below `FAINT` a prediction is simply
not filed, and `Beliefs.update` now ignores a number that is not one, because a single NaN can never be
washed out by later evidence.

That fix opened a hole worth naming: an acquired reading can scale its own prediction to nothing in
every situation the creature meets, and then that prediction never speaks, never resolves, and never
gathers the evidence that would let the idea be reconsidered. Silence is now counted, and a prediction
that keeps having nothing to say is grounds to give the idea up. **Being unable to say anything is not
the same as being right.**

**The feature search was far too credulous in a rich world.** The specs gave creatures two or three raw
readings. A forager has eight, which is thirty-six reachable compositions, fitted against twenty noisy
moments with a free scale factor -- and something always fits. It reliably invented
`times(clearEast, toSouth)`, grafted it onto its prediction about food, and stopped foraging.

The margin now scales with how many ideas were tried against how much evidence there was. That is
ordinary honesty about hypothesis counting, and it is expressible in the package's own terms: a
creature that can reach more ideas needs more convincing before it believes any one of them. With the
fix the same forager invents nothing, and instead converges on its own drain rate -- born believing it
empties by 0.150 every eight seconds, settling on 0.091 against a true 0.096.

**Three lessons that were about the trials, not the package**, and are worth separating out because the
temptation each time was to change the package instead:

- *A horizon is a claim, not a tuning knob.* "Moving this way is followed by food within a second" is
  false about nineteen moves out of twenty on a journey across a room, so every belief decays to
  nothing and the creature correctly stops. The horizon has to be on the order of the journey.
- *Changes add, so two strange things in the same direction are twice the reason to go that way* -- and
  a creature placed between them goes to the point in the middle and resolves neither. That is the
  model being right and the trial being badly arranged.
- *A creature pinned against a wall learns nothing from anything it tries*, because everything fails
  equally. Three of the four trials had a version of this, and every one of them read as the creature
  being stupid.

---

## 9. What breaks

The authoring surface changes shape. `quantity` and `feature` become `reading`; `expects` becomes
`wants`; `instinct`, `believes` and action `predicts` become one `predicts` list. Every spec in the
suite is written against the old surface and will need rewriting — which is the honest cost, and the
reason to do it now rather than after there are users.

`Think` is rebuilt, not extended. `selfErrors`, `predictedErrors`, `cancelsSelf` and `cancelsThreat`
become one path over one kind of belief.

---

## 10. Open

1. **How many contexts may one prediction split into**, and does the creature choose, or does
   `capacity` cap it and the search decide where to spend it?
2. **Does a preference need `after` at all**, or does every preference project by default and the
   horizon become a property of the creature rather than the need?
3. **When does one condition refine another?** With declared kinds, subsumption is trivial. With
   graded patterns -- `green = "high"` -- it is fuzzy, and the rule for deciding it is genuinely
   undecided. Everything about interaction effects rests on this test.
4. ~~**Do horizons compound down a chain of predictions**~~ -- sidestepped. `after` on a projection
   reading narrows which predictions count rather than reaching further, so nothing has to compound.
   The question returns only if a prediction is ever allowed to name a horizon relative to another's.
   Original wording: **do horizons compound down a chain of predictions**, or is an inner prediction evaluated at the
   outer one's horizon? See §3a.
5. **How far does association go?** Settled in principle (§0): the engine does it, using prediction
   as the matcher, and identity may still be supplied to skip it. What is undecided is how much
   ambiguity it tolerates -- whether a return that matches two tracks equally well is assigned to
   the better one, split between them, or held as genuinely unresolved.
6. ~~**Order of work.**~~ -- settled by doing it. Core first, then each capability with its own spec
   and both suites kept green throughout. Original wording: readings and predictions first, with the
   old behaviour re-verified against the new core, then acquired features on top; or the whole thing
   at once, which is faster to write and much harder to tell what broke.

Two more that the build itself raised:

7. **Content-addressed names for acquired readings**, so two creatures that independently invent the
   same one agree, and `extract` from either produces the same declaration.
8. **Revising an authored scaling that turns out to be wrong.** A creature can add a factor to a
   prediction but never remove or replace one it was born with. This was visible in the search: a
   creature found the right factor while an authored one it could not touch went on wrecking the
   prediction, and it was only the death rule asking the narrow question -- *is the acquired reading
   earning its keep* -- that stopped it discarding the right answer.

---

## 11. What is built

`next/`, 88 cases across 8 specs, alongside the shipped 0.4.0's 282. Both green, selene clean.

| | |
|---|---|
| `Beliefs` | `(value, spread)`, the update rule, relaxation. Unchanged from 0.4.0. |
| `Values` | Expressions, operators, temporal operators via `recalls`. |
| `Registry` | Declaration and validation. Requires nothing; the compiler is injected. |
| `World` | Estimates, derived readings, projections, emotions, patterns, fading. |
| `Predict` | Bearings, projection, filing what is expected, settling it, forgetting. |
| `Choose` | Preferences, what an action is worth, venture, chaining. |
| `Associate` | Grouping returns into things, and splitting them again. |
| `Acquire` | The feature search, adoption, and death. |

Built and specified: readings and layers; estimates and projections; predictions with conditions on
kind, pattern, action and another subject; `by` scaling; change-versus-level composition; refinement
by precision; preferences and error; action selection with venture and commitment; chaining; the
feature search with reference-counted death; `extract`; association, binding and splitting; emotions.

Not built: contexts (§10.1), and the parts/occupancy surface that 0.4.0 has and this has not needed
yet.
