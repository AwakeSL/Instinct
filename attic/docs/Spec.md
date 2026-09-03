# Instinct specification

Creatures that predict what their senses will report, and act to close the gap. A belief is a
`(value, spread)` pair. The gap between prediction and report is the only reason a creature acts
and the only way it learns.

## The tick

```
perceive  raw percepts in, features built, presence and signs read
think     gather errors, settle emotions, gather again, select, act
```

Errors are gathered twice in one tick because emotions modulate the precision of the errors that
produce them. A single pass would leave every emotion a tick behind the world.

## Errors

A prior is a target and deviation either way is an error. Actions only ever move a quantity toward
its prior, so an excess of something nothing can spend simply produces no behaviour.

**An error smaller than its own spread is not evidence.** It sits inside the range the model already
allows, so it is discarded before ranking. That is why a tamed wolf stops provoking anything at all
rather than provoking a very small something.

Salience discounts a predicted error by the confidence of the prediction, by the classification
confidence of the percept, and by an exponential urgency over its horizon.

## Learning

Every prediction with a horizon becomes pending. When the horizon passes, what the senses now report
is compared against what was predicted, and the belief that produced it updates. **There is no
outcome call.** The next perception is the outcome.

The observation's own spread scales with the magnitude of what happened: a catastrophe is
unambiguous and narrow, an uneventful moment is weak evidence and wide. That single asymmetry is
what makes taming gradual and trauma instant through one update with no branch between them.

A violation widens a belief as well as moving it, so confidence is losable.

## Credit

One error is split between the belief that made the prediction and the perception that fed it, by
precision. `attribution` biases where it lands. A creature that trusts its senses revises its
beliefs; one that doubts them recalibrates its features and holds its beliefs longer. Both are
visible as beliefs.

Persistent unresolved error on a learned association is what `insight` reads, and it is how a
creature recants an attribution it made wrongly.

## Blending and forgetting

A subject belief is seeded from its kind and updates on its own. Its parent updates too, from the
same evidence held four times as wide, so a creature generalises from individuals to kinds slowly.

Forgetting is a subject belief relaxing back toward its parent, on a half-life set by `grudge`.
Nothing is evicted and half remembering is a real state. Presence beliefs relax toward not knowing,
which is why object permanence is a consequence rather than a switch.

## Actions

An action declares what it needs, what it occupies, and what it predicts. The numbers are priors:
one punch is authored, and every creature diverges from it.

An unmet requirement is not a disqualification. It becomes an error, something that settles it is
recruited, and `patience` bounds how far that goes. A chain is scored on what it ends in, so a
creature will walk through a worsening of the very error that motivated it.

`skill` is the precision of a creature's predictions about actions using it, not a damage bonus.
`selfImage` overrides it when scoring confidence, which is how a creature can be certain of a blade
it is bad with.

Caution filters candidates before the best is chosen, never after.

## What the package owns

Every name and number is authored. The package owns the arithmetic: how error distributes by
precision, `surprise = error / spread`, the blend across subject and kind, how chains form and are
scored, how salience is computed, and relaxation.
