# instinct

**Creatures that predict what their senses will report, and act to close the gap.**

A creature holds beliefs as `(value, spread)` pairs. It predicts what it is about to perceive, the
world reports something else, and that difference is both the only reason it acts and the only way
it learns. Nothing is scored, weighted or ranked by a system you cannot see: an action is chosen
because it is predicted to cancel an error the creature currently holds.

```lua
local Instinct = require(path.to.Instinct)

local i = Instinct.new():defaults()

i:quantity("hydration")
i:role("self")
i:part("legs")
i:part("head")
i:sense("sight", { needs = "eyes" })
i:sense("body", {})
i:kind("drinkable")
i:kind("water", { is = { "drinkable" } })

i:action("walk_to", { occupies = { legs = 2 }, settles = { "at" } })
i:action("drink", {
    requires = { at = "drinkable" },
    occupies = { head = 1 },
    predicts = { { of = "self", hydration = { 0.80, spread = 0.10 }, after = { 4.0, spread = 2.0 } } },
})

i:species("elf", {
    parts   = { legs = 2, head = 1 },
    senses  = { sight = {}, body = {} },
    expects = { hydration = { 0.90, spread = 0.15 } },
    dials   = { patience = { 0.4, 0.9 }, caution = { 0.2, 0.6 } },
})

local elf = i:spawn("elf", { seed = 0x5E1F })

i:perceive(elf, {
    { via = "body", raw = { hydration = 0.3 } },
    { subject = pond, kind = "water", via = "sight", raw = { distance = 40 } },
})

local doing = i:think(elf, dt, now)
```

- **Every value is a prior, and every prior can move.** The numbers on an action are what a creature
  starts out believing about it, not what is true. Two creatures given different lives end up
  disagreeing about the same wolf.
- **Taming and trauma come out of one update.** Repeated uneventful contact narrows a belief
  gradually because each quiet moment is weak evidence; one catastrophe moves it hard in a single
  step and leaves the creature uncertain, because a dramatic event is not ambiguous. There is no
  branch between them.
- **Forgetting is a spread relaxing toward its parent.** An unseen subject drifts back into being a
  generic member of its kind, so nothing is evicted and half remembering is a real state.
- **An error smaller than its own spread is not evidence.** A creature ignores what sits inside the
  range its model already allows, which is why a tamed wolf stops provoking anything at all.
- **A bare list sums**, so `{ 15, 23 }` is 38; named keys are operators you declared, applied in the
  stage order you gave them. Uncertainty propagates through the arithmetic.
- **Dials are expressions, not just numbers.** `caution = { 0.3, { "downside", times = 0.9 } }` is a
  creature that needs more certainty as the stakes rise.
- **You can ask why.** `i:why(elf)` returns the driving error in spreads, the chain, everything that
  was considered, and what each option lost on.

`docs/Spec.md` is the build spec the implementation is held to.

## Install

```toml
[dependencies]
Instinct = "awakesl/instinct@0.1.0"
```

## Development

```
lune run scripts/headless      # the suite
selene src test scripts        # lint
```
