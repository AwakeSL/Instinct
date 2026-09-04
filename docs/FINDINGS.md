# The staged symbolic search — what was built, what was measured, what went wrong

Working notes. Everything here was measured by running it; where a claim is a guess it says so.
Written because most of it existed only in a conversation.

The point of the exercise: prototype a feature search offline, fast, so the version that goes into
the **Instinct** creature package (`C:\Roblox Packages\Instinct`) is one that has been tested rather
than reasoned about. §9 is what should carry over.

---

## 1. The files

| | |
|---|---|
| `countdrift.lua` → `data.csv` | sheep always runs **east at a fixed speed**. Original dataset. |
| `countfree.lua` → `free.csv` | sheep starts anywhere, runs in a **random direction at a random speed**, and its own velocity is a channel. The interesting one. |
| `types.lua` | the type table: what values exist and what may legally be done to them |
| `findtyped.lua` | the typed staged search. **The main program.** |
| `findstage.lua` | untyped staged search, kept for comparison |
| `findonce.lua` | `findfast.lua` with nulls off, for fast sweeps |
| `ask.lua` | scores **hand-written** formulas against the same data — the yardstick |
| `typed.bat` | runs `findtyped.lua` with the settings in its own SETTINGS block |
| `go.bat` | same, with settings as arguments: `go data=free.csv stages=1 nulls=0` |

`findfast.lua`, `countstuff.lua`, `countburst.lua` and `data.csv` are untouched originals.

`findtyped.lua` now has three **leaf** settings — `ownSpeed`, `ahead`, `aheadDist` — that hand the
creature facts about itself as starting channels rather than making the search derive them. They are
what §12 is about. `types.lua` defines a reciprocal `inv`; it is off in the ops list, and §12 says why.

**`ask.lua` scores on the whole dataset; the search reports a held-out slice.** The two are not the
same number. The same idea reads 0.2213 in `ask.lua` and anywhere from 0.20 to 0.235 as a search
held-out, depending on the seed — the slice is worth ±0.015 by itself. Compare a search result to the
yardstick by rebuilding it by hand, never by reading the held-out column against `ask.lua`'s table.

**`ask.lua` is the most useful thing here and the most easily forgotten.** The search tells you what
it found; `ask.lua` tells you what it *missed*, by putting a named idea in front of the same data and
reporting the same number. Every important conclusion below came from comparing the two.

### cmd gotchas

- `CFG_x=1 luajit ...` is bash syntax and does nothing in `cmd`. Use `set CFG_x=1` on its own line,
  or `go.bat`.
- `set` persists for the whole session, so a stray setting from ten minutes ago silently changes the
  next run. `go.bat` clears every `CFG_` variable first and echoes what it is using.
- `cmd` splits arguments on `=` as well as spaces, so `go data=free.csv` and `go data free.csv` are
  identical to the script.
- From Git Bash, `cmd /c` gets mangled (`/c` becomes a path). Use PowerShell, or `cmd //c`.

---

## 2. The yardstick (free.csv, MAX_START_SPEED = 12)

> **Superseded by §12.** The table below is still right about every formula in it; the conclusions
> drawn from it were wrong. 0.2644 was the ceiling of formulas built on *closing speed*, not of the
> data. The data's ceiling is **1.0** — re-simulating the generator from the columns scores 0.9989 —
> and the sheep's *own speed*, a raw fact, gets a hand formula to 0.2702 and the search past 0.31.

From `ask.lua`. These are what a formula written by hand achieves, so they say what is *there to be
found* rather than what the search happens to reach.

```
R2 0.2644   worth where dist < closing*w + 2*w*w    <-- the ceiling
R2 0.2213   window/dist * worth
R2 0.2112   window/dist
R2 0.2057   worth * w*w/dist
R2 0.1968   w*w/dist
R2 0.1715   worth if dist < 2*w*w
R2 0.1044   worth if it arrives   (closing test, no acceleration)
R2 0.0965   dist < closing*window
R2 0.0914   1/dist
R2 0.0291   closing speed alone
```

**Best the search had reached when this was written: 0.2335** held-out — which is about 0.227 on
the whole dataset, so a shade over `window/dist × worth`, not 88% of anything (see the note in §1).

Two things this table settles — **one of them wrongly**:

~~**The last 12% needs closing speed and cannot be had incrementally.**~~ **Wrong.** It needs the
sheep's own speed, which is a raw channel. `worth × window × (25 − ownspeed) / dist` scores
**0.2702** — above the "ceiling" — and closing speed in any smooth form scores *worse* than nothing
(`worth × window × closing / dist` = 0.0478). What was true: closing scores 0.029 alone and the
staged search could not reach it. What was false: that closing was the thing it needed. The reason
own speed was not being found is in §4 and §12, and it is not "useless alone".

**The generator's settings move the ceiling a long way.** `MAX_START_SPEED` 12 → 50 dropped it from
0.2644 to 0.1650, because wolves then start with speeds up to 50 but are capped to 25 once moving, so
most of the initial velocity is discarded and arrival becomes far more random. If a run looks like it
has stopped making progress, check the ceiling before blaming the search.

### A trap in `countdrift.lua`

Its header says the task is solvable because the sheep's speed is in the search's `constants` list —
it says `SHEEP_VX = 2`, and line 41 says **20**, with constants `{1, 2}`. So on `data.csv` closing
speed is **not in the search space at all, at any depth**. Every result measured on that file is a
proxy. Fix the header or the constant before anyone uses it again.

---

## 3. The one law that kept reappearing

> **The evidence you need scales with the number of ideas you are choosing between.**

It showed up at four different levels, and every time I mistook it for something else first:

| where | what it looked like |
|---|---|
| moments per creature | at 50 remembered moments **every** method scored negative held-out — worse than predicting the average. Reliable discovery needed ~200. |
| `sketch` vs candidates | at `sketch=500` with 40k candidates: fit climbed to 0.27 while held-out fell to 0.03, some rows **negative**. |
| `cascade` vs candidates | ranking 99k ideas on 250 scenarios is close to shuffling them. Cost a third of the signal. |
| channels accumulating | as promotion grows the vocabulary, candidates grow 10–60× while `sketch` stays fixed — so a round that was fine at stage 1 is hopeless by stage 10. |

The last one is worth stating separately: **a fixed `sketch` silently becomes too small as the run
goes on.** Nothing warns you.

### It is NOT compounding overfitting

I claimed the staged search compounds overfitting. **That was wrong**, and the correction matters: a
promoted channel keeps **no fitted parameters** — the `a·x + b` is discarded and only the raw
expression's per-subject values are stored. So a channel chosen by coincidence is, on new data, an
inert column. It does not carry bias forward.

The real mechanism is a growing multiple-comparisons problem: the same mistake each round, made
easier each round by a larger pool against fixed evidence.

---

## 4. The recurring failure: useless alone, essential in combination

Appeared five separate times, in different costumes, and it is the deepest limitation of the whole
approach:

- ~~**closing speed** scores 0.029 alone → never wins a round → the 0.2644 answer is unreachable~~
  — the 0.2644 answer was never the answer (§2, §12). The mechanism is real; this example is not.
- **`vel.x − 20`** (closing, on the drift data) is a signed quantity that predicts nothing alone → never
  survives the beam to be built on, so handing over the constant `20` changed *nothing*
- **`dot(offset, ex)`** — a signed coordinate — never earns a beam slot, so typing the vectors made
  components *unreachable* rather than merely more expensive
- **a foundation channel** stops being *named* once derived versions exist, so LRU sees it as idle
  exactly when it is most load-bearing
- **an intermediate that only pays in a pair** cannot be found by any procedure that requires each
  step to improve on its own

Anything ranked by its own score cannot see these. Multi-promotion and decorrelation help (they let a
weaker foundation survive next to a stronger one) but do not solve it.

### A second failure that looks like this one and is not

**Cut by the beam before its transforms are tried.** `len(own)` — the sheep's own speed — scores
**0.02** alone because it is one number per scenario. So the beam drops it at the first level, and
`window / len(own)`, which scores **0.227** alone (above `window/dist × worth`), is never built. That
is not "useless alone, essential in combination": the useful idea is one operator away and would win
a round outright. It was never tried, not tried and rejected.

The two need different fixes. The first needs a way to value an idea by what it enables. The second
only needs the raw material to be *there*: hand the creature its own speed as a number and
`div(window, ownspeed)` is a depth-1 candidate that wins stage 1 (§12).

And the search *did* find own speed eventually, in a depth-2 run at stage 4, as `offset.y / own.y`
clamped between two other channels — a signed time for its own motion to cover the wolf's north
offset, the same trick as `dist − offset.x` on the drift data. It got there by accident: the raw ratio
scored 0.1988 on a fit slice that happened to contain no near-zero `own.y`, and **−6.49** held-out.
Promoted anyway (promotion ranks by fit), clamped by the next round, best idea of the run: 0.2577 on
the whole dataset against 0.0029 for the ratio alone. Useless alone, essential in combination, reached
by a fluke that a sensible guard would have prevented. See §6.10.

---

## 5. The guards, and why each exists

Every one of these was added to stop a real, observed failure — and **every one needed a second pass
because its first form also blocked something good.** That pattern is worth remembering.

| guard | stops | the second pass it needed |
|---|---|---|
| **Pareto front** (`frontOf`) | a good small idea hiding inside a bigger one that scores a shade higher | had to be carried into the *exact-scoring* pass too, or the score-ranked shortlist filtered small ideas out before Pareto could see them |
| **distillation** (`distil`) | passengers: `(A+B)*C` promoted whole when `C` is dead weight | the carrier must **stand on its own**. "The other slot doesn't matter" ≠ "the operator doesn't matter" — `min(x, anything)` still clips. Also needs **most** substitutes to hold, not all: one unlucky substitute vetoed every true finding. |
| **decorrelation** (`apart`) | three promotion slots going to three spellings of one idea | must never return **empty**: at depth 1 every candidate is one operator from an existing channel, so all of them correlate, promotion stalls, and the search freezes for eighteen rounds re-deriving the same six expressions |
| **R² dedupe** | `x`, `2x`, `−x`, `x/2` surviving as four separate ideas — the value signature cannot see a scale change, R² is exactly the invariant that can | **needs one, not done.** It is right at the top level, where `a·x+b` absorbs the offset, and wrong for an *intermediate* under a nonlinearity: `add(fd, 2)` is a twin of `fd`, so `window/(fd+2)` — worth **+0.04** over `window/fd`, because a wolf inside touch radius has already arrived — cannot be spelled. Also: leaves never enter the twin table, so `add(window,window)` survives beside `window` (§6.11) |
| **culling** (`grace`) | channels nothing has used for N rounds | — |
| **eviction** (`maxChannels`) | unbounded vocabulary growth | freezing promotion at the cap is worse than evicting; the search then spends its remaining rounds re-choosing among what it has |
| **fall-through** | a rejected pick being *lost* rather than replaced | the promotion list was only the Pareto front (~5 entries); it now descends the full ranking |

### Decorrelation was the single biggest win

Same seed, everything else held:

```
before:  0.1391  0.1405  0.1343  0.1384  0.1369    circling, peak 0.1405
after:   0.1419  0.1405  0.1434  0.1532  0.1692    climbing, peak 0.1692
```

**+20%.** The mechanism is visible in the log: stage 1 promoted two channels instead of three and
passed over one as too alike, and the freed slot went to `min(dot(scale(offset,k13),vel), own.y)` —
a *geometric* foundation instead of a third copy of `window/dist`. It wasn't stuck for lack of reach;
it was stuck because all three slots held one idea.

### A decision NOT taken

**Do not credit a channel's ancestors when a descendant is used.** Once `k15 = mul(worth, k13)`
exists, `k13`'s information is inside it, and a channel is a column of numbers that never consults its
own definition again. Crediting ancestors would keep raw material alive beside the product, work
against decorrelation, and mean nothing ever ages out.

The rediscovery problem it was meant to fix (`div(window,dist)` found **five times** in twenty rounds)
is real but has a different cause: **promotion rate against channel cap.** Promoting 16–20 channels a
round into 80 slots replaces most of the vocabulary every round, so nothing lives long enough to build
on. Fix the rate, not the metric.

---

## 6. Bugs found (all fixed unless noted)

Ordered by how long they hid.

1. **`count` discards its argument.** `count(anything)` is the subject count, so every idea scored
   identically under it; when that tie beat the real candidates the ranking became arbitrary and a
   whole round went to four spellings of "how many wolves are there". Removed — `sum(1)` says the same
   thing and has to earn it.
2. **Vector dedupe compared only the x component**, silently merging different vectors.
3. **Vectors were ranked at a fixed pseudo-score of 0.5**, above every real R², so the beam filled
   entirely with vectors and no scalar intermediate was ever extended. Now judged by the best cheap
   reduction (`len`, `dot` with a basis vector).
4. **`unary and nil or b`** evaluates to `b`, not `nil` — `(true and nil)` is `nil`, and `(nil or b)`
   is `b`. So unary operators got `false` as a right operand. Every consumer wrote `node.b and …`,
   which treats `false` and `nil` alike, so it hid until something used `== nil` and indexed a boolean.
5. **`NAN` contains an `A`**, so substituting operands before it turned `NAN` into `Nax[p]N` in the
   generated kernel.
6. **Channel names were reused** (`k(#SHAPE+1)`), so after a cull the numbering shifted and two live
   channels could both be `k24` — corrupting the flattening substitution as well as the log. Now a
   monotonic counter.
7. **`cascade` was fixed** while candidates grew from 8k to 99k. Now a floor that scales.
8. **`resample = false` aliased.** `off = ((stage-1)*nfit) % (ntrain-nfit)` at `sketch=5000` of 15000
   gives offsets 0, 5000, 0, 5000 — two slices for ever, neither fresh nor stable.
9. **Held-out was reported but never computed** in the first draft.
10. **Deeply nested promoted channels produce degenerate divisors** — from stage ~17 the held-out
    column starts reading `n/a` because something like `div(k314, k316)` has `k316` hitting zero on the
    test set. **Not fixed, and now deliberately so.** It showed up at stage 2 of a depth-2 run
    (`div(k14, speed)`, a zero-speed wolf in the held-out slice, promoted on fit) and at stage 4
    (`offset.y / own.y`, held-out **−6.49**, promoted on fit). The guard that was going to fix it —
    refuse a divisor that comes near zero anywhere in the training pool — would have killed the
    second one, and the second one clamped became the best idea of that run (§4). A near-zero
    divisor is a bad *answer* and a fine *ingredient*. If a guard is ever added it must apply to what
    is reported, not to what is promoted.
11. **Leaves never enter the R² twin table** (`search`, where the pool is seeded by value signature
    only). So an operator that makes a scale twin of an existing channel — `add(window,window)`,
    `mul(k13,2)` — is a fresh idea every round, and decorrelation is what has been catching them.
    Visible in every stage-1 listing as `sum(window)` and `sum(add(window,window))` at the same
    score. **Not fixed**; cheap.

---

## 7. Performance

`3.88s → 0.16s` for a depth-1 round; depth 3 now runs faster than depth 1 used to.

| change | gain |
|---|---|
| fuse the five aggregate passes into one | **2.7×** — the biggest |
| cache scores so the final ranking doesn't redo the beam's work | included above |
| **cascade** — rank on a sample, exactly score only the survivors | ~3× |
| check nan once per scenario instead of once per subject | ~30% |
| compile operators into the loop (codegen kernels) | **20%** |
| stop allocating a column per candidate (scratch buffers) | **~10%** |

**The last two are the ones everybody would try first, and they barely mattered.** The cost was never
the Lua calls or the memory churn — it was simply `candidates × subjects × passes`. Optimise the
number of elements touched, not the constant factor.

---

## 8. Method — how to not fool yourself

**Run three seeds before believing any comparison.** Variance between seeds on this data is ±0.02,
which is the same size as most of the effects being measured. I drew the wrong conclusion from a
single run **three times**:

- staged vs one-shot (staged looked much better; over 8 paired seeds it merely matched shallow)
- typed vs untyped (typed looked worse; the cause was a missing basis vector, not typing)
- `resample` (reuse looked better; that was seed 5 specifically, and it loses on 17 and 29)

**Fit and held-out disagree constantly.** Two ideas within 0.005 on fit can differ by 0.03 out of
sample, and nothing about the fit score tells you which. Promotion still ranks by fit. ~~The honest fix
is a three-way split (train / validation / test).~~ **Withdrawn.** Nothing may be tested against the
held-out slice, and a validation slice that promotion steers by is just a second fit slice — the same
multiple-comparisons law (§3) against a smaller sample. The held-out number is an estimate only for
as long as nothing consults it.

**The held-out slice is worth ±0.015 by itself.** The same idea (`window/dist × worth`) read 0.2349
on one seed's slice and 0.2047 on another's, against 0.2213 on the whole dataset. A run that looks
like a record on its own held-out column may be an ordinary run on a generous slice — one of the
depth-2 runs reported 0.2742 held-out for an idea that scores 0.2577 on everything. Rebuild the idea
by hand and score it on the whole dataset before believing a number; that is what `ask.lua` is for,
and for a two-level idea (a pack aggregate used inside a per-wolf expression) it means rebuilding
the promoted channels from the log's arrow lines.

**`stopEarly = false` is both better and more honest.** In one run the sequence was
0.113 → 0.123 → **−0.097** → 0.128: the old rule would have quit at round 2 and never seen the best
round. And since the stop rule was the *only* thing that consulted the held-out slice, removing it
means nothing the search does depends on that slice — so the number it reports is a real out-of-sample
estimate again rather than something optimised against.

**Watch the fit/held gap, not either alone.** Healthy: they track each other, and held-out is
sometimes *higher* (the test slice is just different scenarios). Sick: fit climbs while held-out
falls. Stage 4 of one run scored fit 0.2254 / held **−0.0969** — the best fit of the whole run and
worse than useless.

---

## 9. What should carry over to the Instinct package

The package's own search (`next/Acquire.luau`) is a cut-down version of this. What this prototype
learned that it does not yet have:

**Certain**

- **What a creature is handed matters more than how deep it can search.** Two readings it can
  compute from what it already knows — *how fast am I going* and *how far is that thing from where I
  will be* — took a depth-1 search from 0.22 to 0.31 in three rounds under half a second, where no
  depth or beam reached 0.29 without them (§12). Give the creature its own speed and its own
  projected position as readings. A vector it cannot promote is not a reading; the scalar is.
- **Hold moments back.** A creature can split its own memory — fit on some, check on the rest. The
  package currently uses an invented margin (`demand × (1 + sqrt(candidates/moments))`) as a proxy for
  what a holdout measures directly.
- **`count` is not an aggregate.** Never add it.
- **Dedupe on R², not on values.** Scale-twins are one idea.
- **Aggregates over subjects** — `min`/`max`/`mean` as well as `sum`. The package can only ever *add*
  (several predictions on one reading sum), so it cannot say *the nearest*, *the worst*, or *how many*.
  This is a real expressive hole for a creature standing in a crowd.
- **Promote more than one idea per round**, and require them to be **unlike each other**. Worth +20%
  here, and it is the only thing that lets a weak-but-necessary foundation survive.
- **Vectors as a type, with components still addressable.** Typing alone *lost* (it hides components
  behind an operator); typing **plus** exposed components matched untyped exactly on this data while
  making `dot(unit(offset), vsub(vel, own))` reachable. Vectors should be a *view* over scalar
  readings — expression-level only — so `Beliefs.luau` never needs to know what a vector is.
  **But a vector is never promoted**, so a vector fact only helps within a single round: handing over
  `ahead = own × window` as a vector changed nothing at depth 1 or 2, while the scalar
  `len(offset − ahead)` was the best single fact in the data (§12). Every vector fact a creature is
  given needs its scalar shadow beside it.

**Probably**

- **Rolling buffer of raw moments, shared.** Measured: an episode as Lua tables costs **~1,447 bytes**
  for 8 readings, where the data is 19 numbers. A flat f32 buffer with moments shared across
  predictions is **~85×** smaller — 11 MB per creature becomes ~130 KB. The outcomes are already in the
  buffer (a later row), so per-prediction outcome storage disappears entirely.
- **Depth 1 per round, composing across rounds** rather than a deep one-shot search. Measured on
  `data.csv`: staged depth-2 beam-100 reached **0.303** held-out against one-shot depth-3 beam-100 at
  **0.212**.

**Do not**

- Do not credit ancestors when culling (§5).
- Do not add a **hard** comparison operator. `World.matches` is already graded, and a graded ramp is
  both easier to fit (a hard threshold has no gradient — it cannot slide) and better behaviour: a wolf
  slightly too far away should not be a cliff edge. The smooth `window/dist` beat the hard arrival
  count here (0.2112 vs 0.0965), and it still holds with the better ingredients: smooth
  `worth × window/(fd+2)` 0.3144 against the hard `worth if fd < speed·w + 2w²` 0.3056.
- Do not add a guard against near-zero divisors at promotion (§6.10).

---

## 10. Settings that work, and what they cost

Measured on `free.csv`, one round, `sketch=2000`:

```
depth beam cascade  time    held out
    1   30     250  0.16s     0.1148
    2   30     250  0.35s     0.1165
    3   30     250  0.60s     0.1209   <-- good default
    3  100     250  1.85s     0.1206
    3  100     500  2.69s     0.1204
```

Beam past 30 bought nothing *at that sketch*. At `sketch=4000+` a wider beam does pay — the run that
reached 0.2335 used `beam=3000`.

### The budget is 100–500 ms a round, and channels are what break it

The package gets a few hundred milliseconds per search, not minutes, so anything at depth 3 or beam
in the thousands is a curiosity. What actually eats the budget at `depth=1, beam=30, sketch=1500`:

```
stage    1      2      3      4      5      6      8     12     16
built   1.9k   3.0k   4.6k   7.2k  10.3k  12.7k  18.3k  27.6k  36.7k
time   0.18s  0.26s  0.39s  0.63s  0.86s  1.15s  1.72s  2.54s  3.28s
```

Beam and depth are fixed; the growth is entirely promoted channels — six a round — multiplying the
level-1 candidates. Three rounds fit the budget, five nearly do, and nothing after about stage 7 pays
anyway: in a 16-stage run held-out never beat stage 7 while fit climbed from 0.29 to 0.36 (§3's law,
12k ideas on 1,500 scenarios). So: **promote less, cull faster, stop around stage 5.** The knobs are
`promote` and `maxChannels`, not `beam` or `sketch`.

Rules of thumb:

- **`sketch`** is the first thing to raise if a run wanders instead of climbing. Below ~2000 the
  stage-by-stage numbers are meaningless.
- **`cascade`** should grow with the candidate count. At 50k distinct candidates, 500 is too thin —
  1500 is worth trying. It is a floor, and the floor is `candidates/100`.
- **`promote`** against **`maxChannels`** sets the turnover. 3 promotions (6 channels) into 80 slots is
  ~8% a round and lets foundations compound. 16 promotions into 80 is 40% and nothing survives.
- **`nulls`** costs `(1 + nulls) ×` the whole run. Leave at 0 while exploring; raise it only when
  deciding whether to believe a result.
- **`seed`** — set a number when comparing two configurations, leave `nil` when asking whether a result
  is robust.

---

## 11. Open

- ~~**The last 12%** on `free.csv` needs closing speed~~ — closed, wrongly diagnosed; see §12. What is
  open instead: **the remaining two thirds.** The data's ceiling is 1.0 and the best anything reaches is
  0.32, because arrival is a hard event (2.9% of wolves) and no product of ratios with one fitted scale
  imitates it well. Whether a smooth, direction-aware formula exists that beats 0.32 nobody has tried.
- **Ideas that pay only in combination** are still unreachable by design (§4), and the one time the
  search found one it was by a fluke that a guard would have stopped. The honest open problem of the
  approach, unchanged.
- **Promotion still ranks by fit**, and a three-way split is *not* the fix (§8). No fix known.
- **Decorrelation selects for passengers.** In the depth-2 run, stage 2 promoted `min(max(vel.y,
  window), k14)` — k14 clipped by wolf-velocity noise, scoring 0.2012 on the whole dataset against
  0.2213 for k14 itself — because the noise made it *unlike* k14. Meanwhile the round's best idea, a
  real refinement of k14, was passed over as too alike, twice running. The guard should judge what a
  candidate adds over the channel it resembles (the R² of its residual), not raw correlation.
- **The offset twin** — `add(x, c)` deduped against `x` — blocks `window/(fd+2)` (§5). Wants the twin
  key to apply only where the fit can absorb the offset, i.e. at the top level.
- **Leaves outside the twin table** (§6.11). Cheap.
- **Time per round grows with channels** and the budget is fixed (§10). Promotion rate is the knob and
  has not been tuned against the budget.
- **Term revision** (§13). Terms are fixed for ever. A creature needs to revise one when it fails, and
  only on evidence from moments where its gate was open. Not built, not tested.
- **The spoiler term sits on the term floor** (§13): worth 0.02 of the residual, found on one seed in
  three. That is the evidence law again (§3) — a real term the size of the floor is a coin toss on a
  sketch of 1,500. Raising `sketch` for the residual rounds, when the candidate count is small anyway,
  is the obvious thing to try.
- **`joinBranches`** — allowing a grown branch on the *right* of an operator — costs ~2.5× and changed
  nothing here, because the shape it unlocks (`dot(unit(offset), vsub(vel,own))`) scores 0.03 on its
  own. Kept off. The other shape it would have unlocked, `div(k13, len(own))`, scores 0.257 — but
  handing over `ownspeed` as a leaf made that a chain, so the case for it is weaker than it looked.
- **`inv`**, the reciprocal, is defined in `types.lua` and off. With it plus a rule that a leaf under
  one unary operator is never cut by the beam, a depth-3 run found `window/len(own)` at stage 1 and
  reached 0.2894 on the whole dataset by stage 3 — the best idea of the day — in 140 s. Out of budget.
  Both were reverted in favour of the leaf; the operator stays for a world where the reciprocal of a
  *derived* quantity is what pays.

---

## 12. What 1 September found: the ingredient, not the depth

Everything below is on `free.csv`, whole-dataset R² unless it says held-out. The short version: the
search was never short of reach. It was short of a fact the creature already knew.

### How it came apart

A depth-2, beam-10000 run (minutes a stage, far out of budget) climbed to 0.2606 by stage 6 on
`max(add(k30, k33), 2)`, where k30 was a clamped `offset.y / own.y`. Stripped down, every piece
scored nothing alone; together 0.26. Own velocity was in the load-bearing piece, so I put own speed in
front of the yardstick by hand:

```
R2 0.2213   sum(worth*window/dist)                         what stage 1 always finds
R2 0.2644   worth if dist < closing*w + 2*w*w              the old "ceiling"
R2 0.2572   sum(worth*window/(dist*ownspeed))              one div from what exists
R2 0.2702   sum(worth*window*(25 - ownspeed)/dist)         wolves cap at 25; this is their edge
R2 0.0478   sum(worth*window*closing/dist)                 closing, smooth: worse than nothing
R2 0.1698   sum(worth*window*(25 - ownspeed*cos)/dist)     own speed *projected* on the bearing: worse
```

Direction does not help. The magnitude of the sheep's own speed does, and it beats the closing-speed
formula the whole §2 argument rested on.

### Why the search could not spell it

`window / len(own)` scores 0.227 alone — it would win stage 1. But `len(own)` scores 0.02 (one number
per scenario), the beam ranks by own score and cuts it at level 1, and the reciprocal needs a grown
branch on the *right* of `div`, which the search never builds. So the idea is three operators from a
leaf that never survives its first level.

Three fixes, measured, all seed 7:

| fix | depth | result |
|---|---|---|
| `inv` operator alone | 3 | **identical to control**, stage for stage — `len(own)` was already gone |
| `inv` + never cut a leaf-under-one-unary | 3 | `window/len(own)` wins stage 1; 0.2894 whole-dataset by stage 3; 140 s |
| `ownSpeed = true` — own speed as a scalar leaf | **1** | `div(window, ownspeed)` wins stage 1 at 0.20 s |

The third is the one kept. In budget, three seeds, best held-out over six depth-1 rounds:

```
seed      7       17       29
off    0.2016   0.2115   0.2207    plateaued by stage 3
on     0.2631   0.2636   0.2923    still climbing at stage 6
```

Three times the seed variance, same direction every time. On the whole dataset the run's own ideas:

```
stage 2   0.26s   sum(window^2/(ownspeed*dist))                       0.2596
stage 3   0.44s   sum(window/dist * (1 + window/ownspeed))            0.2687   > the old ceiling
stage 4   0.69s   ... + min(window/ownspeed, worth*window/dist)       0.2789
stage 5   0.86s   pack threat + pack threat * window/own * worth      0.2859
```

### Then the projected position

Suggested from outside: hand over *where I will be*, `own × window`. Measured by hand first — with
`fd = len(offset − own×window)`, the wolf's distance from where the sheep ends up:

```
R2 0.3144   sum(worth*window/(fd + 2))                     best single fact in the data
R2 0.3056   worth if fd < speed*w + 2*w*w                  the hard version, close behind
R2 0.2722   sum(worth*window/fd)                           without the +2: a wolf at 0 has arrived
R2 0.3205   sum(worth*window/(fd+2)*(1+window/ownspeed))   both facts: best hand formula
R2 0.9989   exact re-simulation of countfree.lua           the truth is all in the columns
```

Only **2.9%** of wolves arrive. That is why every smooth formula sits near a third of the ceiling.

As a *vector* leaf (`ahead = true`): **no effect**, identical runs — `vsub(offset, ahead)` is a
vector, vectors are never promoted, and `len` of it needs a third operator before it pays. As a
*scalar* leaf (`aheadDist = true`): wins stage 1 on every seed, and in budget, depth 1, best held-out
over eight rounds:

```
seed                      7        17        29
nothing                0.2016    0.2115    0.2207
ownSpeed               0.2631    0.2636    0.2923
ownSpeed + aheadDist   0.3027    0.3117    0.3272
```

Seed 7's stage 3, at 0.50 s: `sum(worth × min(window/aheadDist, window/ownspeed))` — each wolf's
worth, scaled by the smaller of *how many times over it can cover the gap to where I'll be* and *how
many times over I can outrun the window* — **0.3157** on the whole dataset, within 0.005 of the best
formula I can write by hand. From 0.22 to 0.32 in one day, and every step of it was an ingredient,
not a search setting.

### What the search still cannot say

- `window/(fd + 2)`: the `+2` is worth 0.04 and is an offset twin of `fd` (§5, §11).
- Anything that imitates a hard arrival well. The exact answer is in the data at 0.9989; the best
  smooth formula is 0.32. That gap is the shape of the problem, not a bug.

### Settings this added

`ownSpeed`, `ahead`, `aheadDist` in the SETTINGS block, all overridable as `CFG_name=0`. `ahead` costs
a little and buys nothing; turn it off. `inv` in `types.lua`, off in the ops list. The beam rule
(never cut a leaf under one unary) was tried and reverted: it quadruples level-2 candidates at
beam 30 and at depth 2 cannot reach the shape anyway.

---

## 13. Groups and terms: when two things move the score

The question: if two kinds of thing each move the score by their own mechanism, and how many of each
kind is present varies — often none — can the search find that on its own, without kinds being
declared anywhere? And does a term learned while a kind was present survive rounds where it is absent?

### The dataset

`countkinds.lua` → `kinds.csv`. Three kinds of wolf, one `kind` channel, nothing else said about them:

| kind | does | share of wolves | absent from |
|---|---|---|---|
| 1 wolf | reaches the sheep → **adds** its points | 66% | 5% of scenarios |
| 2 hunter | chases the nearest wolf or spoiler; a catch **adds** its points and removes the prey | 17% | 44% |
| 3 spoiler | reaches the sheep → **subtracts** its points; faster (cap 40, pull 8) | 17% | 44% |

Spoilers were first given the same speed as wolves, and the hunters ate most of them before they
arrived: the spoiler term was worth **+0.003** R² by hand, and a search that never found it was right,
not broken. They were made faster so the negative case has something to find. Everything below is
on the faster version.

`y` is the net change. Hand yardstick, per-kind terms fitted **jointly** by least squares:

```
R2 0.1178   wolves only                       threat(kind 1)
R2 0.1268   wolves + spoilers                 ... coefficient -0.28
R2 0.3024   wolves + hunters                  threat(1) + worth*window(2)
R2 0.3171   all three                         ... + threat(3), coefficient -0.36
R2 0.3756   hunters as worth*window*prey      the best hand model
```

Hunters are half the signal. Spoilers are worth about 0.015 on top of wolves and hunters — real,
but against a residual of 0.70 that is a term of 0.02, exactly the floor.

### What the one-expression model does with it

Baseline, `findtyped.lua` as it stood, three seeds, best held-out over eight rounds:
**0.2164 / 0.2265 / 0.2232.** It cannot say "hunters add, spoilers subtract" — one expression, one
scale — so it finds `sum(worth + window)`, a weighted head-count, and then spends seven rounds using
`kind` as a *number*: `div(k14, kind)`, `mul(kind, k26)`. That is the third layer missing: the score is
a sum of things and the model is a product of things.

### Two additions

**Groups** (`groups = true`). For a channel the shape marks `discrete`, one boolean leaf per value
with enough support, found from the data: `is(kind,1)`, `is(kind,2)`, `is(kind,3)`. Appended as
columns like promoted channels, so `gate(f, is(kind,2))` is an ordinary idea and a leaf nothing gates
on is culled by the ordinary grace rule. Nothing declares what a kind is.

**Terms** (`terms = N`). Each round's winner is fixed as a term, its scale refitted on the whole
training pool, its contribution subtracted from the outcome, and the next round searches what is
left. Two effects with two coefficients are unsayable in one expression; on the residual the second
one is simply what remains. A term is only fixed if it explains at least `termFloor` of what is left
*on the pool* — the first version scaled terms on the 1,500-scenario sketch and the sixth term of one
run made the model worse on the pool itself. Nothing held out is consulted.

### What happened

Same three seeds, held-out of the whole model:

```
seed                 7        17        29
baseline          0.2164    0.2265    0.2232
groups + terms    0.3265    0.3345    0.3278     3-4 terms, in 0.2-0.8s a round
hand, 3 terms     0.3171
hand, best        0.3756
```

Seed 17, in order: term 1 `sum(worth + window)`, the head-count; term 2 `sum(gate(k16, is(kind,2)))`,
**hunters, on the residual**; term 3 `-0.059 × sum(gate(window, is(kind,3)))`, **spoilers, negative,
on the residual of that**, model 0.27 → 0.32. Three mechanisms, three terms, three signs right, with
nothing declared. Seeds 7 and 29 found the hunter gate **first** — `sum(gate(window, is(kind,2)))` wins
stage 1 outright — then a `is(kind,1)` gate for the wolves, and never spelled the spoiler term: at
0.02 of the residual it sits on the floor and two seeds out of three lost it to the sketch. Both
still reached 0.33, above the hand-written three-term model, so the sum of terms is doing the work
whether or not every group is spelled with its gate.

So: the groups are discovered, the terms come out one per mechanism with the right sign, a group
nothing gates on is culled, and the model beats the hand-written three-term one on every seed. The
residual is what makes the second and third mechanisms findable at all — on the raw outcome the
hunter idea scores 0.07 and the spoiler idea less, and neither would ever win a round.

### What this settles about absence

A term, once fixed, is never touched, so on this harness absence cannot harm it trivially. The real
question is the *revision* rule, which is not built: when a term's predictions go wrong, revise it
only if its gate has been open recently. Absence of a kind is no evidence about it. That rule is
what stops a rebuild from forgetting wolf 2, and it is the next thing to test — fit with hunters
present, run on scenarios with none, bring them back.

### Settings this added

`groups`, `groupShare` (0.05), `terms` (0 = the old model), `termFloor` (0.02). `KINDS_SHAPE` is
picked by column count, ten. Only `kind` is marked `discrete`; `worth` takes three values too and
could be, and was not, so `free.csv` runs are unchanged.

---

## 14. Eight kinds: where the sum of terms runs out

`countzoo.lua` → `zoo.csv`. The three kinds of §13 plus five more, chosen so that some matter, some
do nothing, and one is a wolf with noise on it:

| kind | does | share | worth by hand |
|---|---|---|---|
| 1 wolf | adds on touch; chases the nearest of sheep and decoys | 42% | +0.020 |
| 2 hunter | catches wolves, spoilers, gamblers; adds | 11% | **+0.168** |
| 3 spoiler | fast; subtracts on touch | 11% | +0.013 |
| 4 decoy | fake sheep; absorbs 5 points of attacks, none count | 7% | +0.000 |
| 5 gambler | wolf AI; 80% nothing, 20% five times its points | 7% | +0.003 |
| 6 repel bug | random walk; the sheep steers away from it | 7% | +0.000 |
| 7 sweet bug | random walk; the sheep steers toward it; touch adds 1 | 7% | +0.009 |
| 8 bug eater | eats bugs | 7% | +0.000 |

"Worth by hand" is what a crude per-kind feature adds to a joint least-squares fit of all eight,
which reaches **0.2650**. Hunters are three quarters of the signal, because there is so much prey.
Everything else is a few hundredths, and three kinds are nothing at all, as designed.

```
seed                              7        17        29
baseline, one expression       0.1540    0.1579    0.1729
groups + terms, in budget      0.1919    0.2096    0.1980     2-3 terms
same, sketch 6000, floor 0.01  0.2141    0.2148               3-4 terms, 12s
hand, eight crude terms        0.2650
```

**What worked.** The hunter gate wins stage 1 outright on every seed; the wolf gate is term 2 on the
residual with more evidence. Decoy, repel bug and bug eater gates were culled on every run, which is
right. The gambler got no term of its own, which is also right: it is a wolf in expectation.

**What did not.** Spoilers and sweet bugs, worth 0.013 and 0.009, were never fixed as terms. With the
gates kept alive (§14 changed `cullStale` so a group leaf lives as long as the model may still grow —
before that `is(kind,3)` was culled at stage 3 on every run, one round before its layer) the best
residual idea for them scores 0.006–0.010, and the floor is 0.01. Lowering the floor further lets
noise in: at sketch 6000 with ~3,000 candidates a round, chance alone reaches about 0.008.

So this is §3's law at the level of terms, and it has a §4 shape too: a small kind needs a gate *and*
a formula to clear the floor, and at depth 1 each round supplies one of them. `gate(window,
is(kind,3))` alone is not enough; `gate(threat, is(kind,3))` would be, but `threat` for spoilers is
only ever built if something already made it worth building. The sum of terms finds every effect
that clears the floor on its own and none that need two steps to clear it.

**Not a failure of the idea.** The model is still 25–35% better than the one-expression baseline on
every seed, the groups it names are the right ones, and the ones it culls are the right ones. What it
says about the creature: with a few hundred moments it will learn the two or three biggest things in
its world and be blind to the rest, and the blindness is honest — it cannot tell a small real effect
from luck, and neither can anyone else with that much evidence.

### Rare hunters, and what the gambler's dice do to R²

Hunters were then made rare (0–2, absent 70%: 2.4% of subjects, under the 5% group threshold, so
`groupShare` had to drop to 0.02 for them to get a gate) and the gambler's payout raised, twice. The
generator on disk is the last of these.

| gambler | hand, 8 terms | wolves alone | baseline | groups + terms |
|---|---|---|---|---|
| 20% × 5, hunters common | 0.2650 | 0.0708 | 0.15–0.17 | 0.19–0.21 |
| 20% × 10, hunters rare | 0.0847 | 0.0316 | 0.02–0.04 | 0.03–0.05 |
| **1% × 100**, hunters rare | 0.0509 | 0.0202 | 0.07–0.10 | 0.10–0.11 |

Nothing about the wolves changed between rows, yet "wolves alone" fell by 3.5×. **R² measures a
share of the variance, and the gambler's dice became most of the variance.** At 20% × 10 a touch is a
coin worth up to 30. At 1% × 100 the file has exactly one scenario of `y = 300` in 20,000, and that
one row is about three quarters of the total sum of squares — so every fit number reads 0.02 (the row
is in the pool) and every held-out number reads 0.10 (it is not), and the difference between
configurations is which slice the row fell in. Rare hunters did the intended thing: by hand, wolves,
hunters, spoilers and sweet bugs are now a flat field of 0.006–0.018 each. It just cannot be seen.

### The flat field, gambler off

With the gambler removed (generator on disk: `max = 0`) and hunters still rare, the field is what
rare hunters were meant to give: by hand, wolves +0.068, hunters +0.053, spoilers +0.049, sweet bugs
+0.026, the other three nothing; all seven together **0.1982**.

```
seed                 7        17        29
baseline          0.0680    0.0730    0.0864
groups + terms    0.1452    0.1540    0.1471     3-4 terms, groupShare 0.02
hand, 7 terms     0.1982
```

Twice the baseline on every seed. And the terms, across the three seeds: a **wolf** gate first on
two, a **hunter** gate on two, a **spoiler** gate with a negative scale on two (−0.86, −0.055), a
**sweet bug** gate on one (+0.93). Every kind that matters was found as its own gated term with the
right sign on at least one seed; decoy, repel bug and bug eater on none. What §14 above could not
show through the hunters' dominance and then the gambler's dice, this shows plainly: four
mechanisms of similar size, four terms.

### Kinds that act through other kinds: decoys and havens

Two kinds were added that do nothing to the score themselves and were meant to act on the wolves —
a **decoy** (a fake sheep that draws and absorbs attacks) and a **haven** (kind 9: pushes every
other kind away at a strength below a chaser's acceleration, fading to nothing as the sheep gets
within 10 studs of it; attracts the sheep; havens push each other apart). Both came out worth
nothing by hand (+0.0002, +0.0004) and both gates were culled by the search. Checked whether either
matters as an *interaction* instead — wolves that a decoy diverts removed from the wolf term; wolves'
gap to the sheep lengthened by a haven's push — and neither helps: 0.1337 against 0.1365 for the
decoy, 0.1805 against 0.1816 for the haven. They are real nulls, and the reason is spawning:

- A quarter of wolves have a decoy nearer than the sheep, but only **3%** of the wolves within 15
  studs do — and arrival is decided by those. A decoy scattered uniformly over a 60-stud arena
  diverts wolves that were never going to arrive.
- A haven's push fades to nothing exactly where the sheep is, so it cannot protect the sheep from the
  wolves that are close, and those are the only ones that matter. The rule "not as strong as their
  acceleration when the sheep is close" makes it a shelter that opens as you reach it.

Worth keeping as a result: a kind that only acts *through* another kind is invisible to a sum of
terms unless the interaction is in a channel — a wolf's distance to the nearest decoy, say. Nothing
in the search builds cross-subject channels of that kind, and nothing in these two worlds needed it.

The haven was then made **rare and strong** (at most one, absent 75%; push 20 against a chaser's 4,
no fade — a wolf at full speed stops inside it; generator on disk): a sheep that reaches one is safe.
Still worth **+0.0001** by hand, coefficient now negative as it should be, and the interaction check
turns the right way (0.1736 against 0.1724) — but only 1.6% of wolves, and 1.7% of the wolves that
matter, ever start inside a haven's reach, and the sheep starts within sensing range of one in about
3% of scenarios. A shelter that works and is never reached is the same as none. Spawning is the
whole story for kinds like this: to test "the sheep gets into one" the haven has to be put where the
sheep is going.

**So it was put there** (generator on disk): 10–25 studs ahead of the sheep, within half a radian of
its heading. Now 9.1% of the wolves that matter start inside a haven's reach, the haven is worth
**+0.0073** by hand with a coefficient of **−1.51** — the largest of any kind — and lengthening the
wolves' gaps by its push improves the wolf term, 0.1700 against 0.1636. It is a real, strong, rare
shelter: present in 13% of scenarios, and where present it is the biggest single thing there.

```
seed                              7        17        29
baseline                       0.0909    0.0736    0.0641
groups + terms, in budget      0.1162    0.0766    0.1225     no haven term on any seed
same, sketch 6000, floor 0.01  0.1597    0.1289    0.1456     haven term on 7 and 29, negative
hand, all kinds                0.1839
```

At sketch 6000 the haven came out as its own gated term with the right sign on two seeds of three
(−0.216 × `sum(gate(k16, is(kind,9)))`; −0.016 × `sum(gate(k14, is(kind,9)))`), alongside wolves,
hunters, spoilers (negative) and sweet bugs. In budget it never did: 0.0073 of the outcome is under
0.01 of the residual. Rare and strong means a small share of variance however strong, and the share
is what the floor sees. Which is the honest summary of the whole kinds line: **what the search finds
is set by evidence per round against effect size, and by where things spawn; not by depth, and not
by the number of kinds.**

### Faster and better on the same evidence

Asked for: faster and more accurate without more data. Reference: `zoo.csv`, depth 1, beam 50,
sketch 2000, gates for every kind, terms on, six rounds, seeds 7/17/29 — held-out **0.115 / 0.137 /
0.155**, 6.4 s, rounds growing 0.3 → 1.6 s.

Three changes to how a round becomes a term, none touching the data:

- **The pool chooses the term.** The sketch ranks the round's ideas; the best `termTry` of them are
  each tried as an extra term of the joint model on the *whole training pool*, and the one that
  improves the pool most is kept. The sketch's winner was not the pool's choice in about a third of
  rounds.
- **All term scales are refitted together every round.** A later term changes what the earlier ones
  should have been; fixing scales one at a time left that on the table. A small least squares over
  the terms, training pool only.
- **Stop after `stopIdle` idle rounds.** Every round after the last term is fixed was a wasted and
  more expensive round (§10). Two in a row that fix nothing ends the run. Training pool only.

Result at the same six rounds: **0.161 / 0.134 / 0.147** — one seed up a lot, two within the ±0.02
seed noise. Accuracy per round did not move much; the term step was never the bottleneck.

**Speed is the vocabulary.** Round time is candidates × subjects and candidates go as the square of
the channel count, so the lever is how many channels a round adds. Measured, eight rounds:

```
promote 3 (reference)   rounds 0.3 → 1.7 s   held-out at 6:  0.161 / 0.134 / 0.147
promote 2               rounds 0.3 → 1.2 s   at 8:           0.150 / 0.135 / 0.148
promote 1, grace 1,
  maxChannels 40,
  termTry 12            rounds 0.3 → 0.6 s   at 8:           0.166 / 0.119 / 0.149    4.5-4.9 s total
```

With one promotion a round every round stays inside the budget through eight rounds and the model is
as good per unit of *time* as the reference — at 3.4 s cumulative it averages 0.145 against the
reference's 0.123 — while being a little worse per *round* on two seeds. The trade is fewer channels
to build on against more rounds affordable; on this file it comes out even on rounds and ahead on
time. Seed 17 is the stubborn one throughout.

**Operators cost linearly and the extra ones buy nothing here.** Same fast configuration, four
rounds, seed 7: 5 operators (`add sub mul div gate`) 1.19 s, 9 (+ `min max abs gt`) 1.52 s, 13 (+ `lt
len dot scale`) 1.79 s, all 17 1.83 s. The first three terms are identical across all four
vocabularies to the last digit; the fourth differs by 0.005. Every term ever fixed on this file is
made of `div`, `mul`, `gate`, `sub` and occasionally `min`/`max`. A binary operator costs a full
leaf-squared block a round; a unary one costs a row.

**Culling the world's own channels, and dropping vector components.** `cullRaw = true` lets a raw
channel go after `graceRaw` idle rounds. Measured, eight rounds, fast configuration:

```
                              seed 7   seed 17  seed 29   time
as above                      0.166    0.119    0.149     4.5-4.9 s
cullRaw                       0.164    0.116    0.155     4.2-4.3 s   culls offset, vel, own and components
both = false (no components)  0.172    0.125    0.157     3.0-3.6 s   better on every seed, a third faster
both = false + cullRaw        0.153    0.136    0.152     2.8-3.3 s
```

The channels culling removes are exactly the vectors and their components, which is what `both =
false` removes up front — and the components were never help on this file, only frame-dependent
noise (`div(vel.y, offset.y)` was a term on one seed). So on `zoo.csv` the answer is not to cull raw
channels but not to hand over the components at all: better on all three seeds and a third faster.
`cullRaw` stays as a setting, off; on top of `both = false` it is neutral. On `free.csv` §12 found the
opposite (components matched untyped exactly), so `both` stays true by default.

**Not done, and what they would need.** Refining an existing term in place (re-search the residual
with that term removed, swap if the pool improves) is the one lever left that could move accuracy
without more evidence, at one extra search per refined term. The offset-twin fix (§5) would let
`window/(aheadDist + 2)` be built, but at depth 1 the shifted operand cannot be reached in one step
regardless, so it needs the reciprocal or a shifted divide as an operator.

### Seeing only a cone

`countcone.lua` → `cone.csv`: countfree's world, but the sheep is only told about wolves inside a
60° cone about its own heading. The others still chase and still score. Scenarios with no visible
wolf (21%) carry no subject rows and are dropped at load. What is left: 3.5 visible wolves a
scenario out of ~16, and **9.4%** of visible wolves arrive against 2.9% of all wolves — a wolf ahead
is one the sheep is running *toward*.

```
R2 0.6040   exact re-simulation of the VISIBLE wolves     the creature's ceiling: 40% of the outcome is things it cannot see
R2 0.2463   best hand formula on visible wolves           (0.2796 with full view)
R2 0.2131   sum(worth*window/dist)                        (0.2213)

search, one expression, depth 1, six rounds, held-out:   0.259 / 0.262 / 0.261
search, sum of terms:                                    0.282 / 0.293 / 0.282
```

Two things. The search beats the best hand formula here, on every seed, with one expression — the
first time that has happened; the hand formulas were tuned on the full view, and the cone changes
what matters (`window/(fd+2)` falls to 0.06 because a wolf ahead is one whose gap the sheep closes
itself). And as a *share of what it could know*, the creature does better half-blind: 0.29 of a
0.60 ceiling is 48%, against 0.32 of 0.999 with full view. The cone removed exactly the wolves whose
arrival was hardest to predict, the ones catching up from behind. What it can see, it predicts well;
what it cannot see is simply absent from the number, and no search setting touches that 40%.

### A last second: episodes with lagged inputs

Every file above is a still frame and one number. `countepisode.lua` runs countfree's chase for six
back-to-back windows (0.5–2 s, one length per episode) and hands each window, per wolf, the velocity
change and distance change since a window ago, and the previous window's outcome as a per-wolf
constant (`dvel`, `ddist`, `prevy`; a wolf's lags are only known if it was seen a window ago). Column
14 is the episode number; `findtyped.lua` splits held-out by whole episodes. `lags = false` hands
over the same file as a snapshot world. `episode.csv` full view, `episode_cone.csv` 60° cone.

```
                                  full view                    cone
ceiling (re-simulation)           1.000                        0.487
best snapshot hand formula        0.147                        0.088
sum of terms, lags off            0.181 / 0.189 / 0.185        0.181 / 0.132 / 0.148
sum of terms, lags on             0.176 / 0.226 / 0.217        0.198 / 0.157 / 0.170
```

Held-out, six rounds, depth 1, beam 30, sketch 1500, one promotion a round, 0.3–0.8 s a round.

**With the full view, term 1 on every seed is `sum(div(ddist, dist))`** — the closing rate as a
fraction of the distance, negative scale. That is closing speed, the thing §2 called unreachable
and §12 found was the wrong target on a snapshot. Given a last second it is one operator from a raw
fact and the first thing the search picks up. The rest of the gain (+0.03 on two seeds, −0.005 on
one) is ordinary refinement on top of it.

**In the cone the gain is on every seed** (+0.017 / +0.026 / +0.022) and comes through `ddist` again
(`mul(ddist, k13)`, `div(ddist, ownspeed)`) and once `dvel.y`. The previous outcome, `prevy`, was
used in exactly one term on one seed. The idea that it would stand in for the unseen 40% did not
pay here: what bit you a window ago is usually dead (a wolf that arrives is removed), so the past
outcome says less about the next one than expected. It would in a world where the threat persists.

Two things this settles. History is not a new kind of learning, it is two more channels, and the
search treated them as such. And the thing the whole line was missing turns out to be the derivative
of the one channel it always had: not where the wolf is, but how fast that is changing.

### The other way round: which readings an action moves

Everything above fixes an outcome and searches the inputs. A creature also needs the reverse: fix
one input — the action it is running — and ask each reading whether that action moves it. Nothing in
`next/` does this; an action's effects are authored (`doing = ...` on a declared prediction) and
`Acquire` only refines the condition of a prediction that already exists.

`countact.lua` → `act.csv`: a sheep with four actions (run, dash, stop, graze), five readings whose
change over a one-second window is recorded (harm, fullness, stamina, nearest-wolf distance, and a
pure-noise control), and a **policy** — run or dash when a wolf is near, graze when hungry, else
stop — with 25% random exploration. `act0.csv` is the same with no exploration. `scanact.lua` is the
scan, two ways: **raw**, the mean change while doing X minus while standing still, over the spread;
and **with the situation taken out**, the change regressed jointly on what the sheep could see and
on the action, so the action's coefficient is what it adds over the situation — which is exactly
what `Choose.pick` computes for one action already, the projection with it minus without.

```
harm and run,  24,000 windows:  raw +0.162 (t +14)    situation taken out -0.121 (t -8.6)
harm and dash:                  raw +0.202 (t +18)    situation taken out -0.111 (t -8.5)
```

**The raw scan is confidently wrong about the one thing that matters.** Running and dashing are
what the sheep does when wolves are near, so "running" and "about to be bitten" are the same column,
and noticing concludes that running causes harm. With the situation taken out both actions reduce
harm, with the right sign and at eight spreads. The three deterministic readings (stamina, fullness,
nearness) come out right both ways, and the noise control is silent everywhere at every evidence
level — the scan does not invent effects. At 300 windows the deterministic effects are already
found; harm needs thousands, because a bite is rare.

**Without exploration** the situation-corrected scan still recovers the harm signs at full evidence
(t −7, −6), which is luck rather than principle: the policy's thresholds are not linear in the
controls, so a linear model of the situation leaves the action some variation to be identified by.
A policy the model could represent exactly would leave none. Exploration is what makes the answer
not depend on that luck.

**Where it goes in the package.** At `Predict.settle`, when a row resolves: for every reading in the
before/after snapshots, credit a running (mean, spread, n) for the action that was running, on the
change *minus the no-action projection*. When a pair clears the margin — the same evidence law as
every floor in these notes — mint a prediction entry with `doing = X`, `form = change`, belief
seeded at the measured mean, and the ordinary machinery owns it from there: filed, learned, refined,
culled if it goes quiet. Cost: readings × actions counters. The scan is not a search.

### Living in order: stream mode and the ladder

`findtyped.lua` `stream = N` learns the file **in order**, as a creature would: each chunk of N
scenarios is scored *ahead* with the model as it stands, then the model learns from a sliding
memory of the last `memory` scenarios. It searches while young (`stages` chunks), then rests. Three
modes: **ladder** (refit every chunk; when a term keeps being wrong, climb for that term: bridge →
edit in place one level deeper with the term removed → drop), **frozen** (learn while young, never
again), **scratch** (throw the model away every chunk and rebuild). `countshift.lua` is countkinds'
world in order with a rule change halfway; `shift_wolves.csv` is the wolves-only version, where the
wolf term is the whole model and the break is loud: after scenario 10,000 a wolf only scores if it
*started faster than the sheep runs* — a third of them, and the third the old model predicted worst.

```
ahead R2, mean          before the break   after   last quarter   cost
frozen                  0.175             -0.568   -0.799         2 s
refit every chunk       0.173              0.036    0.089         2 s      (ladder, rung 1 only)
ladder, full            0.173              0.025    0.068        11 s      13 rounds
scratch every chunk     0.093              0.025    0.089        49 s     113 rounds
```

**What worked.** Refitting the scales every chunk on the memory is nearly free and recovers most of
what can be recovered: from −0.57 to +0.04 after the break, the same as rebuilding from scratch at
one twentieth the cost. The new world is genuinely less predictable (a third of the wolves count,
so fewer arrivals), and 0.09 in the last quarter is what scratch reaches too.

**What did not.** The higher rungs. Rung 3 replaced terms with ones that improved the *memory*
(0.103 → 0.125, 0.073 → 0.108) and predicted *worse ahead* (0.025 against refit's 0.036; last
quarter 0.068 against 0.089). A replacement chosen on 1,500 remembered scenarios one level deeper is
an in-sample gain, and the evidence law (§3) does not care that the term was wrong. Wider search on
the same memory is how a creature chases the noise of its own surprise.

**What it took to make the ladder climb at all,** each a real lesson about what "this term is wrong"
means:

- **An absolute miss cannot see a world that has gone quiet.** After the break the wolves score less,
  the squared misses *shrink*, and a model that has become worse than the mean looks healthier than
  ever. Wrongness has to be a share: miss over the variance of the outcome on the term's moments.
- **In-sample on the memory is fooled by the refit.** Refit to the new world's noise, the model
  explains 0.13–0.16 of the memory while predicting 0.10 ahead, and nothing looks wrong. Judge on
  what was predicted *ahead*.
- **The yardstick must be what the term achieved when healthy**, held through rung 1. Re-measuring
  it after the refit made every term look fine again and nothing ever climbed.
- **Consecutive-chunk streaks reset on every lucky chunk** and reached nothing. A decaying average of
  verdicts — the package's own `RECENT` idea — climbed two chunks after the break.

**Two big terms, one breaks.** `shift_two.csv` (`TWO_BIG=1`): up to 25 wolves, up to 3 hunters,
no spoilers, wolves' rule breaks at 10,000. Both terms are large — the model reaches 0.37 ahead
before the break, wolves and hunters each carrying a good share. Two changes were needed first:

- **Attribution by blame, not by open moments.** Two terms open on the same moments cannot be told
  apart by "the model is wrong where this term is open". What can: does the term's *own column*
  explain the ahead residual on the chunk (an R² against the residual, `blame`, noise about
  1/chunk). That is what "this term's scale is wrong" means. With it, the frozen model blames the
  wolf term on 18 of the 20 chunks after the break, heat 1.00, and the hunter term on about six,
  never for long. The broken one is named.
- **A term never extrapolates.** `mean(div(k21, speed))` met a wolf with speed near zero on chunk
  32 and one row scored the chunk at **−29**, poisoning every average. A term's column is now read
  through a cap of three times its 99th-percentile |value| on the memory. The maximum did not
  work: one exploded row already in the memory sets a cap that lets the next one through.

```
ahead R2 (mean / median)     before the break   after            last quarter     cost
frozen                       0.369 / 0.355      0.032 / 0.033    0.071 / 0.061    3 s
refit every chunk (ladder)   0.373 / 0.369      0.299 / 0.324    0.333 / 0.335    3 s
scratch every chunk          0.373 / 0.375      0.309 / 0.342    0.346 / 0.350   80 s
```

The ladder climbed rung 1 for the wolf term two chunks after the break and once, wrongly, for the
hunter term at chunk 30; nothing went higher, because after the refit the wolf term's blame fell
under the floor. Right call: this break is mostly a rescale (the wolf effect shrinks to a third),
and refit recovers 0.30 of the 0.37. Scratch found the true new condition, `gt(speed, ownspeed)`,
on one chunk, and its last quarter is 0.013 ahead of refit — about the floor, at 25× the cost. The
edit rung could have found the same gate, and the evidence law says it would as often have found
noise; on this much memory the trade is even and the cheap side wins.

**For the package.** Rung 1 — refit the scales of what you already believe, every time — is the
whole of the win here, and it is cheaper than anything else the creature does. The trigger for
anything wider should be ahead-surprise on a term's own moments against its own healthy record, with
a decaying memory of verdicts. And wider search on the same evidence should be treated with the same
suspicion as any other idea found on too little: it is the answer to "the world changed", not to
"I keep being surprised".

### The closed loop: a sheep that chooses

Everything above ends at a prediction. `countchoose.lua` puts a choice on the end. The sheep has
five actions — stand still, or run at its speed along +x, −x, +y, −y for the window — and its
velocity *is* the action (the `own` channel; `ownspeed` and `aheadDist` follow from it), with the
action's number as a discrete channel besides. Two files: `choose_train.csv`, 12,000 situations with
**one action each, picked at random** — what a creature exploring at random would remember; and
`choose_test.csv`, 2,000 situations **each played five times**, once per action with the same
wolves, so the realized harm of every action is known. `findtyped.lua apply = choose_test.csv`
evaluates the learned terms on the test file (promoted channels rebuilt from their recipes, which
`CHANNELS` now keeps by name for ever); `chooser.lua` picks, per situation, the action the model
predicts least harm for, and scores what that choice actually cost.

```
mean realized harm per situation, 2,000 situations          seed 7
  random    pick any action                                  0.362
  still     always stand still                               0.411
  away      run most directly away from the nearest wolf     0.244
  model     the action the learned model predicts least for  0.156
  oracle    the action that truly does least                 0.000
```

The model, `0.67 × sum(window/aheadDist) + 0.54 × max(worth × k13)`, two terms found in two rounds
in under two seconds, explains **0.12** of the harm on the test file — and its choice is as good as
the oracle's in **93%** of situations, at a third of the harm of the hand-written reflex. Choosing is
easier than predicting: ranking five actions in one situation needs only their order, and most
actions in most situations cost nothing. The oracle's 83% "stand still" is tie-breaking among
harmless actions, not a preference; the model stood still in 1% and was right to, since standing
still is the worst policy in this world (the wolves converge).

**What this closes.** The chain now runs end to end on data: readings the creature can compute
about itself → discovered groups and a sum of terms → a model applied to every action it could take
→ a choice, and the choice is measured against the truth rather than against a feeling. It uses no
authored prediction: nothing told the sheep that running from wolves helps; it found `aheadDist`,
the wolf's distance from where the action would put it, and that was enough.

**Where the confound sits.** The training file's actions are uniform at random, which is the easy
case (§ The other way round). A creature acting on this model would generate a *policy* file, and
its next model would be learned under that policy. Whether the loop stays honest under its own
choices — with `venture` supplying the variation — is the test after this one.

### Choosing a plan instead of an action

`countchoose3.lua`: the window cut into three parts with an action each, so a plan is (right, left,
up) and the like. Inputs are the same machinery: the mean velocity over the window as `own` (so
`aheadDist` is still where the plan *ends*), the three part-velocities as `own1..own3`, the three
action codes as discrete channels, and one new leaf, **`pathDist`**, the closest the planned path
comes to the wolf checked at the end of each part — a wolf run past halfway is what a plan changes.
Training: one random plan per situation. Test: each situation under 20 plans, the five constant
ones (the old single actions) plus 15 random, same wolves, realized harm known for every plan.

```
mean realized harm per situation      windows 1.5-3 s      windows 5-8 s
  random plan                          0.452                1.924
  still                                0.435                4.227
  away (constant)                      0.272                0.824
  model, best of the 5 constant plans  0.143                0.536
  model, best of all 20 plans          0.161                0.536
  oracle, best constant plan           0.000                0.039
  oracle, best of the 20 plans         0.000                0.014
  a plan truly beats every constant    0.0% of situations   1.7%
```

The search found `pathDist` as its first term unprompted on the short windows. And plans bought
nothing, in either world, because **the world gives no reason to turn**: the wolves converge from
everywhere and running straight in the emptiest direction is always best, so the oracle's best plan
is a constant one in 98–100% of situations and choosing among plans only gives the model more ways
to be wrong (0.143 → 0.161 on the short windows; on the long ones it never picked a non-constant
plan and matched its constant self). The model still beats the hand reflex by a third to a half.

A sequence matters where a straight line fails: a wall to stop at, a corner to leave, a goal to
reach past a wolf, a decoy to circle. None of those exist in this arena. The machinery is ready
for them and this is the world to build next if plans are to be tested at all — the package's own
lab has walls and food, which is exactly the setting.

**Interceptors.** `INTERCEPT=1 WACCEL=8 WMAXV=26 WMIN=3 WMAX=5 luajit countchoose3.lua`: wolves
faster than the sheep that aim at where it *will be* on its current heading, given the time they
need to get there. Now a straight run is met and a change of direction makes the interceptor wrong:

```
mean realized harm per situation, interceptors
  random plan                          2.714
  away (constant)                      2.043
  model, best of the 5 constant plans  1.075
  model, best of all 20 plans          1.149     picks a non-constant plan 21% of the time
  oracle, best constant plan           0.282
  oracle, best of the 20 plans         0.090     a plan truly beats every constant in 11.2%
```

The world rewards a juke three to one at the oracle. The search, given `feint` — how far the plan's
end is from where its first heading would have led, the interceptor's error in one number — took it
as term 3 with a negative scale: *feinting reduces harm*. And still the model's choice among plans
is worse than its choice among constant actions. A per-wolf version, `dodge` (each wolf's aim point
against where the plan actually has the sheep when that wolf arrives), scores 0.15 alone and was
never picked over `feint` on the residual. The gap between the oracle's 0.09 and the model's 1.1 is
the biggest left anywhere in these notes, and it is a *prediction* gap: R² 0.37 ranks five straight
runs well enough and twenty plans not well enough. Choosing among more options needs a better
model, not a better chooser — the evidence law with the options as the candidates.

Left here. What the interceptor world needs is what the package's lab would need too: an ingredient
that says, per wolf, *will it be where I am* — the intercept miss with the wolf's real speed rather
than its current one — and probably a plan search that proposes plans near good ones rather than
twenty at random.

**Walls.** `WALLS=45` on top of the interceptors: a square arena nothing can leave, the sheep
starting within 40 of its centre so a wall is 5–85 away. The sheep is handed its distance to each
wall from where it starts, and how near a wall its plan ends (`endWall`; `own` is now the plan's
*actual* mean velocity, walls and all, so `aheadDist` is where it really ends up). Against a wall
the sheep is not moving and the interceptor knows it.

```
mean realized harm per situation, interceptors + walls           by wolves:  3-6    7-10   11-14  15-20
  random plan                          4.017
  still                                4.754
  away (constant)                      4.585    worse than random: running away pins you
  model, best of the 5 constant plans  3.167                                 1.17   2.48   3.51   4.71
  model, best of all 20 plans          2.681    plans finally pay            0.97   2.02   2.96   4.06
  oracle, best constant plan           1.393
  oracle, best of the 20 plans         0.337
  a plan truly beats every constant    41.7% of situations                   12%    34%    49%    62%
```

Three things changed at once. The reflex broke: "away from the nearest wolf" is now worse than a
random plan, because away is usually toward a wall. Plans became the game: a non-constant plan is
truly best in 42% of situations, 62% in a crowd. And the model's choice among plans finally beats
its choice among straight runs, in every wolf bucket, by 0.2–0.5 harm — the first time more
options bought anything. The search found the wall on its own: term 2 is `sum(lt(endWall, 1))`,
*this plan ends pinned*, and term 3 `mean(sub(aheadDist, pathDist))`. R² 0.46, the highest of any
choosing world, and the model's pick still matches the oracle in only 34% of situations, so the
prediction gap from the interceptor world stands; it is just that with walls the options the model
can tell apart are the ones that matter.

**Random wall clumps.** `MAZE=1 WALLS=45 ...`: 2–5 clumps of 5-unit cells inside the box, each
grown a neighbour at a time with a neighbour that continues a straight run weighted four times one
that starts a kink; the sheep stops at a wall, wolves slide along one, nobody pathfinds. The sheep
sees the nearest wall each way from its start, how near a wall its plan ends, and per wolf whether
the straight line to it is `blocked` (22% of wolves; a discrete channel, so it gets gates).

```
mean realized harm per situation, interceptors + clumps            by wolves:  3-6    7-10   11-14  15-20
  random plan                          3.664
  still                                4.364
  away (constant)                      4.117
  model, best of the 5 constant plans  3.233                                   1.19   2.46   3.68   4.90
  model, best of all 20 plans          2.506    picks a plan 90% of the time    1.01   2.05   2.64   3.78
  oracle, best constant plan           1.252
  oracle, best of the 20 plans         0.270
  a plan truly beats every constant    40.1%                                   9%     31%    49%    62%
```

The largest gain from planning so far: 0.73 harm per situation, 1.1 in a crowd, and the model
chooses a non-constant plan nine times in ten. Its second term is `sum(div(pathDist, endWall))` —
how close the path comes to each wolf, over how near a wall it ends: cover and corner in one idea —
and its fifth is `max(mul(k13, feint))`, the juke weighted by the wolf it fools. `blocked` was
offered and not used; line of sight does not decide anything in a world where a wolf slides round a
wall in a second. The oracle's plan is still four times better than the model's, and the model
matches it in 36% of situations, so the remaining gap is the same prediction gap as before.

**Dense.** `WOLVES_MIN=20 WOLVES_MAX=60 CLUMPS_MIN=8 CLUMPS_MAX=20 CLUMP_CELLS=12`, same interceptors:

```
mean realized harm per situation, dense                     by wolves:  20-30  31-40  41-50  51-60
  random plan                         10.23
  still                               10.91
  away (constant)                     11.59    the reflex is the worst policy there is
  model, best of the 5 constant plans  9.72                                5.89   8.73  10.72  14.06
  model, best of all 20 plans          7.41    a plan every time            4.70   6.61   8.26  10.47
  oracle, best constant plan           5.88
  oracle, best of the 20 plans         2.98
  a plan truly beats every constant   72.9%                                64%    73%    75%    81%
```

Planning is now worth 2.3 harm per situation, 3.6 in the thickest crowd, and the model never picks
a straight run. And the first term changed: `sum(sub(blocked, window))`, then `mean(gate(worth,
is(blocked, 0)))` — *the worth of the wolves that can see me*. Line of sight, offered and ignored
in the sparse maze, is the first thing the search reaches for once the walls are dense enough that
a wolf behind one stays behind it for the whole window. Same ingredient, different world, opposite
verdict; nothing was declared either time. The model matches the oracle in 20% of situations, down
from 36%, because there are more plans that differ by less — the prediction gap again, wider as the
world gets harder, while the value of getting it right grows faster still.

**How much memory the chooser needs.** Dense world, five seeds per sketch, harm of the model's
chosen plan:

```
sketch    mean harm    worst .. best     R2 on test    matches oracle    train time
  250       8.04       8.48 .. 7.64        0.400           15.9%             9.5 s
  500       8.50       9.15 .. 7.80        0.444           14.3%            13.6 s
 1000       8.11       9.15 .. 7.66        0.422           15.6%            15.2 s
 1500       7.88       8.55 .. 7.42        0.443           17.1%            14.7 s
 2000       7.57       7.82 .. 7.41        0.438           17.9%            16.4 s
```

The best run at every size is about 7.4–7.8: more memory does not raise the ceiling. What it does
is remove the bad draws. The 9.15 runs at 500 and 1000 are models that found no plan-sensitive
term beyond `sub(dist, pathDist)` and spent their other slots on `worth/dist` and line of sight,
which are the same for every plan and so cannot change the choice; with 2000 moments that draw
never happened in five seeds. Only terms that depend on the action decide the choice, and which of
those a run finds is luck at small memories. Time barely moves across the range (about 40 µs a
candidate is spent regardless of the sketch, a fifth of it in the value-signature dedupe), so
memory is cheap here and the vocabulary is the lever for the budget.

**And how wide.** Same world, sketch 1000, depth 2 (at depth 1 the beam does nothing — every
candidate is one operator from a leaf and all are scored), three seeds per beam:

```
beam    mean harm    seeds                  R2      round 1          train time
  10      7.92       7.82  7.95  7.99      0.417   12,600 in 2.0 s     16 s
  30      7.66       7.70  7.70  7.59      0.455   17,400 in 2.7 s     23 s
 100      7.64       7.54  7.78  7.59      0.456   28,000 in 4.3 s     38 s
 300      7.77       7.91  7.82  7.58      0.467   62,000 in 11 s      99 s
```

Beam 30 is the knee, as it was in §10 on the first day: 100 buys 0.02 for 1.6× the time, 300 buys
nothing for 4×. What depth 2 does buy, at any beam, is the end of the bad draws: the worst of nine
runs at beams 10–100 is 7.99, against 9.15 at depth 1 with the same memory, because a two-operator
round can build `sub(dist, pathDist)` and the like in one step instead of hoping a first-step
promotion leads there. R² keeps climbing with the beam while the choice does not — the prediction
gap again, the part of the outcome the extra width explains being the part every plan shares.

The visualizer (`vizexport.lua` → `viz.json` → the page; `viz.html` beside it) replays all of this:
the same wolves under each policy's plan, walls drawn, bites marked.

Two lessons for the creature from the gambler, both about the instrument rather than the search:

- **A rare huge outcome makes R² meaningless and does not make the world unlearnable.** The
  expected value of a gambler is still one wolf, and a creature deciding what to do needs the
  expectation, not the share of variance explained. The right question for the 100× gambler is
  whether the coefficient on its gate is about a wolf's, and the right instrument is a loss that does
  not square the miss — or a comparison of the term's scale to the truth, which the hand fit gets
  right (gambler 0.51 against wolf 0.20 at 20% × 10, i.e. roughly the 2× expectation).
- **Scoring by squared error hands the whole search to the outlier.** One row of 300 outweighs
  thousands of ordinary ones in every fit, every held-out and every twin key. A creature scoring its
  predictions this way would spend its life explaining the one time the sky fell. Something like a
  clipped or absolute loss for ranking, with the square kept only for the final scale, is the obvious
  thing to try and has not been.

### Per-round time: the structure of a round, not its vocabulary

The question of 2 September was whether one search round — the creation of a prediction
formula — can be made cheap enough that hundreds of creatures can afford it whenever their
mispredictions pile up, *without* changing what the creature sees, how much it remembers, or which
operators it may use. Cutting operators is a band-aid; this section is about the round itself.

All numbers: the dense maze world (`choose3_train.csv`, 20–60 wolves, 480k rows), sketch 1000,
depth 1, beam 30, seed 7, the same four rounds each time. Every row of the table picks the same four
terms with the same fits as the row above it at the same screen, so these are like-for-like.

| change                                                                                   | round, screen 590 | round, screen 60 |
|------------------------------------------------------------------------------------------|-------------------|------------------|
| before: two passes per idea (kernel writes a column, fold reads it), interleaved rows     | 2.3–2.8 s         | 0.69–0.92 s      |
| + fused scorer: kernel and fold in one loop, four aggregates at once, hashed signature    | 1.3–1.7 s         | 0.30–0.50 s      |
| + exact pass fused too (no 40k-row column per shortlisted survivor)                       | 1.4–1.6 s         | 0.29–0.41 s      |
| + channels as columns; whole-memory view an alias; leaves are pointers                    | 1.6–1.8 s         | 0.27–0.32 s      |

Four rounds, small screen, end to end: 11.6 s → 3.0 s → 2.9 s → 1.6 s, of which about 0.2 s is
loading the file and splitting it into columns, once. At screen 590 the last row is unchanged within
noise: at that screen a round is arithmetic, and the column change is about everything else.

What each change is:

- **Fused scorer** (`fused`, on by default). Per idea the old path ran the operator's kernel into a
  column of P values, formatted some three hundred sampled values into a signature string, then read
  the column back once per aggregate. Now one generated loop per operator computes each row's value
  and folds it into its situation's sum, mean, min and max as it goes, accumulating the fit sums for
  all four aggregates in the same pass; the dedupe signature is two weighted sums of sampled values.
  No column is written or read. 1.7×, and the same ideas win.
- **Screen 60** (`cascade = 60`, `refine = 30`). The cascade ranks every idea on a sample of
  situations and rescores a shortlist exactly. 590 situations → 60 (2400 rows at 40 wolves) is
  2.5×. This is a knob, not a structural change, and its picks differ from the 590 ones — but the
  chooser does not care: seeds 7/17/29 give 9.13/7.82/7.84 (mean 8.26) against the 8.11 mean of the
  sketch-1000 sweep. It is listed because the structural changes multiply with it.
- **Exact pass fused.** The few hundred survivors of the screen were each rescored on the full
  sketch by materialising a 40k-row column. They now go through the same one-pass scorer straight
  from their children's columns.
- **Columns.** After fusion the profile said a quarter of the run was copying: the whole-memory view
  (480k rows × ~24 channels, ~90 MB) was rebuilt up to three times a round — for the term step, for
  promotion, for culling — every leaf was re-evaluated on it because the cache died with the view,
  and promoting or culling *one* channel re-laid out the entire interleaved block. Channels are now
  separate arrays. The whole-memory view is an alias built once, with leaves cached by name across
  rounds; a subset view (sketch, screen, held-out slice) copies a column the first time an idea reads
  it, and only that column; promotion appends a column; a cull drops a pointer. The work outside the
  search fell from ~1.6 s to ~0.45 s over the four rounds, and rounds lost their allocation churn.

A bug the columns exposed: a fitted term keeps its leaf nodes, and a leaf held a column *number*. When
the search culled a channel ahead of that one, the columns were renumbered and the term silently read
its neighbour's column from then on — the interleaved layout made the wrong read succeed. In the
column layout the read failed outright (stream mode's bridge, which re-evaluates old terms after a
cull, caught it). Leaves now resolve their channel by name through a pointer map that a cull never
shrinks: a term fitted on `k14` keeps reading `k14`, even after `k14` has left the vocabulary. Every
run in this file before 2 September that culled a channel ahead of one a term used was quietly
wrong after that cull; the closed-loop numbers of §14 were all measured without culls firing inside a
model's lifetime, so they stand.

What did not help: building idea names lazily and using numeric dedupe keys instead of strings — no
change, slightly worse with a metatable on every node. The per-idea bookkeeping is about a quarter of
a fast round and the rest is arithmetic: ten thousand ideas × 2400 rows is 24 M row-evaluations at
roughly 7 ns each, which is what LuaJIT scalar code costs.

Where it stands. A round on the dense world is **0.27–0.32 s** at the small screen, inside the
100–500 ms budget of §10, down from 2.3–2.8 s on the same evidence and vocabulary — about 8×, of
which roughly 3× is structural (fusion, columns) and 2.5× the screen. Depth 2 at beam 30 (the better
chooser, 7.66 against 8.39) is 0.47–0.77 s a round, 3.0 s for four rounds. A fast round is now about
55% arithmetic, 25% bookkeeping, 20% exact pass and promotion. The structural levers are spent;
below ~0.15 s on this world the only ways down are fewer rows per idea — fewer situations or fewer
subjects in the screen — or a cheaper row, which is the vocabulary again.

Settings this added or changed: `fused = true`; `screenRows = 2400` — the screen now takes situations
until it has that many rows, because its cost is rows (60 situations of 40 wolves order ideas well;
60 of 3 lost the free world's winner) — with `cascade` as the floor in situations, 450 → 60, and
`refine` 100 → 30. `CFG_fused=0` restores the two-pass scorer for A/B; both paths give identical
picks.

## 15. The duel: a fighter made of predictions against a scripted one

The question of 2 September, second half: put a hand-scripted bot in a top-down 1 v 1 against a
fighter whose policy is nothing but the prediction machinery, on the same senses and actions, and
see who wins. Files: `duelsim.lua` (the arena), `countduel.lua` and `countduelstep.lua` (data),
`predictor.lua` (runs an exported model), `chain.lua` (the chained chooser), `duel.lua` (live
fights), `chooserduel.lua` (offline scoring). `findtyped.lua` gained `CFG_export=file`, which writes
the fitted terms and channel recipes as a Lua file the predictor runs — the predict function a
creature would carry.

### The arena

Two fighters: position, facing, health 100, two potions (+40), a gun with an 0.8 s reload, bullets
at 30 units/s doing 15, a hit radius of 3. Actions per tick (0.1 s): nothing, turn left, turn
right, walk forward, shoot, drink, strafe left, strafe right. The bot's rules, untuned: drink at
≤35 health if nothing is coming; turn toward the enemy until within 0.15 rad; walk in to 25;
shoot when the gun is ready; walk in to 12; else stand. Against itself it ends in mutual death
about 95% of the time in 12 s, which says what the fight is: whoever is aimed and ready hits.

The learner's senses, per subject (the enemy, every bullet in flight, later its own bullets too):
offset, velocity, distance, speed, kind, the subject's facing, its health; broadcast: my health,
potions, reload, facing; and the plan as what it does to me (velocity and facing per part, shoot
and drink flags per part).

### First attempt: predict the harm of a whole plan (the sheep's method)

y = health I lose − health the enemy loses over the plan's window, +100/−100 for a death. The
search finds it as well as anything here (R² 0.5–0.6, the same terms you would write: health,
where the threat ends up, potions gated on drinking), and the offline chooser is far better than
random (mean realized harm −8.4 against +16.9; the oracle −14.5). Live, it never won a game.

It took five arena versions to be sure why, because each version fixed something real:

- **A 1.5 s window, parts of 0.5 s.** Nothing attacks: a shot fired after turning lands after the
  window closes. The oracle (true rollouts of every plan) stands still 91% of the time.
- **A 3 s window.** The oracle still loses 84 of 100: a part of one second turns 90°, the bot
  re-aims every tick to 9°, so every evaluated "turn then shoot" overshoots.
- **Re-choosing every tick, 0.3 s parts, a softer gun, bot-mixed exploration.** The oracle draws
  more and wins less. Turning still too coarse to aim by; and the bot only drinks when nothing is
  coming, so the explorer's drinks correlate with safety and the learner decides drinking is what
  makes you safe. (An explorer's habits become the learner's superstitions.)
- **Unequal parts (1, 4, 12 ticks) so the evaluated move is the executed one; time-weighted harm.**
  The weighting was needed for a separate reason: under a sliding window "shoot now" and "wait,
  then shoot" score the same, the tie went to the first plan in the list, which starts with doing
  nothing, and the oracle deferred forever. With sooner worth more it stops deferring — and kites:
  0 wins, 77% timeouts, never shoots. Facing an opponent that is already aimed at you costs
  health inside the window; the greedy optimum is to run.
- **Strafing and slower bullets**, so dodging is possible at all. The oracle now survives (+24
  health, 93% timeouts) and still does not attack.

The learner, on every version, learned survival — strafing out of bullets, drinking, walking —
and never learned to shoot. Right in every case: a predictor of harm over a window cannot value an
action whose payoff lands past the window, and with an opponent already aimed at you, no window
short enough to predict well contains a payoff for turning to face it. The sheep never met this,
because being caught inside the window was the whole game.

### Second attempt: predict the next senses, and chain (the user's proposal)

Instead of one outcome for a whole plan, every step (four ticks, one action held) is a situation
and each sense after it is its own target. Seven searches on the same data (`countduelstep.lua`,
49k steps from 1500 games of a 70%-random explorer; depth 2, beam 30, eight rounds each, about 4 s
each):

| target                         | fit R² | held-out R² |
|--------------------------------|--------|-------------|
| where the enemy will be (x, y) | 0.999  | 0.999       |
| where it will face (x, y)      | 0.98–0.99 | 0.98–0.99 |
| whether it fires this step     | 0.71   | 0.72        |
| health I lose this step        | 0.77   | 0.76        |
| health it loses this step      | 0.40   | 0.39        |

The chooser (`chain.lua`) feeds the predicted situation back in with the next action, three steps
deep, reads harm off the chain, and carries its plan from tick to tick (on a tie the plan in hand
wins). Candidates: every first action with every second action held to the end, 64 plans, plus
the carried one.

**With the learned hurt and dealt in the chain: 0 wins in 50**, though it was the first learner
that shot at all (10% of ticks). The diagnosis, comparing the chain's numbers with true rollouts
from mid-fight states: the enemy's position and facing are predicted almost exactly, but "health
it loses" is blurred — it predicts a partial hit 58° off target — so the chain cannot aim by it;
and a turn evaluated as a whole 36° step overshoots from anywhere inside 36°, so no plan ever
predicts a hit and the fighter never lines up.

**What fixed it: let the chain know its own physics.** A creature knows where its body goes and
how its projectile flies; what it has to learn is the other creature. So the chain now computes
hits by geometry — a bullet, mine or theirs, passing within the hit radius of the predicted
positions — and uses the learned models only for what the enemy does: where it goes, where it
faces, whether it fires. Heals are known. And the first step of a plan may hold a turn for one or
two ticks instead of a whole step. Nothing else changed.

**Result, live, 50 games, seed 5: the chained fighter won 28, lost 22, mean health difference
+12.3, no mutual deaths.** It shoots when aligned with a ready gun, strafes out of the line of fire
when not, drinks rarely (2%). On the same seeds: standing still and random lose 100 of 100; the bot
against itself is a coin flip with 94% mutual deaths; the whole-plan learner loses 98 of 100.
Confirmed on seed 11, 100 games, depth 3: **won 58, lost 42, health +19.4**, no mutual deaths.

The chain's depth is the lever, and it is not subtle (30 games, seed 5):

| chain depth | won | lost | health B−A | shoots |
|-------------|-----|------|------------|--------|
| 2 (0.8 s)   | 16  | 14   | +2.5       | 10%    |
| 3 (1.2 s)   | 17  | 13   | +12.3      | 12%    |
| 4 (1.6 s)   | 28  | 2    | +53.5      | 34%    |
| 5 (2.0 s)   | 28  | 2    | +55.8      | 36%    |
| 6 (2.4 s)   | 21  | 9   | +8.2      | 36%    |

At depth 4 the chain can see a turn, a shot and the bullet's arrival in one plan, and the fighter
changes character: it attacks a third of the time and wins 28 of 30 against the bot that killed
every earlier learner 100 of 100. This is the same window-length effect as before, but now the
window is made of one-step predictions that stay accurate, so lengthening it helps instead of
hurting. Cost: about 4 s per game at depth 4 (64 plans × 4 steps × 5 models per tick, in plain
Lua on the predictor's tree-walker; nothing about it is optimised).

### What this settles

- **Predict senses, not outcomes, and chain.** The one-step predictions of the other creature are
  the accurate ones (0.99 for motion and facing); harm is what falls out of them. This is the shape
  Instinct's predict function should have: what will I sense next, given what I do.
- **The creature should own its physics.** Its body, its projectiles, and what a hit does are not
  things to learn from correlation; learning them blurs exactly the precision aiming needs.
  Learning is for the other creature.
- **Carry the plan.** It is what stops "later" from beating "now" under a sliding window, and it
  is where the misprediction signal will come from: the step the plan expected against the step
  that happened.
- **A window-limited outcome predictor is the wrong object for a fight**, and the failure is not
  visible in R² or in the offline chooser, both of which looked fine. Only the live loop showed it.

Depth 6 falls back to 21–9 and +8: six chained one-step predictions compound their errors past
what the extra reach buys. Four or five is the knee here.

Not yet done: the misprediction trigger (the carried plan makes it a one-line comparison) and the
surprise statistic in the live loop.

### Everything predicted, with instincts as senses

The chain above still hands the fighter its own physics: the hit test, the potion, the reload, its
own facing. The user's objection stood — a creature made of predictions should predict, and
"bullets hitting creatures leads to damage" belongs in it as an *instinct*, something it is born
knowing, not as code that overrides the learner. The resolution: instincts are **senses the creature
is born with**, handed to the search as leaves exactly as the sheep's `aheadDist` was, and nothing
after a step is computed — every sense after the step is a learned target, chained.

`countduelstep2.lua` writes thirty targets from the same 1500 games (`step2_<target>.csv`), each
its own search and export; `chain2.lua` chains them. The inputs are the senses now and the action,
plus the instinct channels, computed before the step from what is already sensed:

| instinct   | what it is                                                                   |
|------------|------------------------------------------------------------------------------|
| `own1`, `aim1` | my velocity during the step and my facing after it, for this action      |
| `flight`   | where this thing will be after the step if it keeps going straight           |
| `atMe`     | this bullet's straight path passes within reach of me (given my move)        |
| `atThem`   | this bullet of mine passes within reach of the enemy, it keeping its velocity |
| `aimed`    | a shot fired now along my facing would pass within reach of the enemy        |
| `saimed`   | a shot the enemy fires now along its facing would pass within reach of me    |

The targets, and how learnable they are (held-out R², depth 2, eight rounds each, ~4 s per target):

| target group                                        | R²            |
|-----------------------------------------------------|---------------|
| my facing after; each bullet's position, velocity, direction; a new bullet's direction | 0.999–1.000 |
| the enemy's position and facing after; a new bullet's position | 0.96–0.999 |
| my reload, my potions after                          | 0.98–0.99     |
| did I fire                                           | 0.59 without the aiming senses → 0.94 with |
| health I lose this step                              | 0.79 → 0.89   |
| health the enemy loses this step                     | 0.47 → 0.79   |
| the enemy's velocity after; does it fire; is a bullet still flying; its reload | 0.46–0.82 |

Three lessons from getting there:

- **A creature needs instincts about its own limits too.** The first fully predicted fighter drank at
  full health: the learned "health I lose" had no way to say the potion is capped at 100 (the
  vocabulary's constants are 1, 2 and −1, and the fitted scales cannot make a cap), so a drink
  predicted 27 health at 100. Giving the search the world's magnitudes as constants (4, 15, 40, 100)
  did not help. A one-line instinct in the chain — I cannot be healthier than full — fixed it.
- **The hits the record could not explain were shots fired *during* the step.** With `atMe` and
  `atThem` for bullets already in flight, "health I lose" still sat at 0.79, because at close range
  the bot fires and hits inside the same 0.4 s step, and no bullet-in-flight sense sees a bullet
  that does not exist yet. `aimed` and `saimed` — would a shot fired now hit — are what moved the
  hit targets. The instinct that matters is not "where bullets go" but "am I in someone's sights".
- **The precision problem was never the search's.** Given the right born senses, depth 2 found
  `gate(..., atMe)` and `gate(..., aimed)` terms in the first rounds. Without them, no depth or
  constant set got "health it loses" past 0.6.

Live, depth 4, 30 games, seed 5, against the bot:

| fighter                                             | won | lost | health B−A |
|-----------------------------------------------------|-----|------|------------|
| fully predicted, no aiming senses, no health limit  | 1   | 29   | −46.5      |
| fully predicted, aiming senses + health limit       | 19  | 11   | +16.2      |
| the chain that computes its own physics (§ above)   | 28  | 2    | +53.5      |
| fully predicted, aiming senses + health limit, seed 11 | 16  | 13   | +18.0      |

(Seed 11 also had one mutual death.)

So a fighter that predicts everything, given instincts as senses, beats the scripted bot. It is
weaker than the one that computes its physics, which is what one would expect: thirty learned
predictions chained four deep drift more than five learned ones plus arithmetic. But it is the
version that generalises — the instincts are senses, and the learner decides what they mean.

The shape this leaves for Instinct: a creature is born with senses (including derived ones, about
its own body and about things on course for it), learns one-step predictions of every sense that
matters given its action, chains them a few steps to choose, and carries the plan. Its thinking is
the chain; its learning is the search, run when the chain is wrong.

### Beam search over the chain: cut by the beam, again

The user asked why the chooser weighs 64 fixed plan shapes ("one action, then another held") rather
than searching: keep the best two states after step 1, expand each, keep the best two, and so on.
Built as `CHAIN_BEAM` in `chain2.lua` (8 + width × 8 × (depth − 1) step predictions, every plan a
real sequence, the carried plan protected from pruning). Depth 4, 30 games, seed 5:

| chooser          | won | lost | health B−A | turns |
|------------------|-----|------|------------|-------|
| 64 fixed shapes  | 19  | 11   | +16.2      | 5%    |
| beam width 2     | 1   | 29   | −57.0      | 0%    |
| beam width 3     | 1   | 29   | −61.2      | 0%    |

It never turned. Turning toward the enemy costs a hit now and pays only two steps later when the
shot lands, so at the first cut the safe move — strafe away — always outranks it, and the branch
that would have won is gone before it can show why. The fixed shapes survive this because "turn,
then shoot for three steps" is evaluated whole. It is the same failure as the search's own "cut by
the beam" (§4): a greedy cut by the score so far cannot keep an idea whose worth arrives later. The
fix is the same in both places — rank by what the branch is worth, not by what it has cost — and
for the fighter that means either a value for the state reached, or a born sense that turning toward
the interception line is progress (a `lead` angle), so the cost of turning is offset inside the step
it is paid.

Two proposals from the same discussion, not built: lagged steps as inputs to the one-step models
(memory across steps — worth doing; a snapshot cannot see that the enemy is mid-turn), and a
second pass that re-predicts each step seeing the whole first-pass trajectory, before and after it
(argued against: an earlier step cannot depend on later actions, so the backward inputs carry only
the model's own errors).

### Correction, and where the fighters stand at the end of 2 September

**The fully predicted 1 v 1 fighter did not win.** The 19–11 (seed 5) and 16–13 (seed 11) results
above came from a bug in `predictor.lua`'s tree-walker: a promoted channel that read another
channel read it at the wrong subject's row. Fixed, and with a compiled predictor that agrees with
the fixed walker to the last digit, the same models lose 7–23; retrained with a ridge or a swing
guard on the joint refit they lose 1–29; retrained without either they lose 7–23 again; and the
bug reproduced behind a flag with the *current* models gives 4–26. So the wins were the bug, and
the fighter that predicts everything has never beaten the bot. The fighter that computes its own
physics and predicts only the enemy (28–2 at depth 4) stands.

The instincts section's numbers are wrong in that one row and the conclusion "a fighter that
predicts everything, given instincts as senses, beats the scripted bot" is withdrawn. What survives
of that section: the instinct senses do make the hit and heal targets learnable (the R² table is
right), and a creature needs instincts about its own limits.

**What was built for the thinking cost, and what it costs now** (2 v 2 unless said):

| version                                              | think cost                      | thinks per tick | result vs the bot pair |
|------------------------------------------------------|---------------------------------|-----------------|------------------------|
| full chain, interpreted predictor                    | ~1 s                            | 1               | (too slow to measure)  |
| full chain, compiled predictor, first step shared    | 35 ms                           | 1               | lost 30/30             |
| local candidate set (2×actions+1 plans)              | 18 ms                           | 1               | (1 v 1: 0–30)          |
| one alternative per tick (`nudge`)                   | ~5 ms                           | 1               | not scored             |
| think only when surprised (`surprise`)               | 35 ms per think                 | 0.09            | lost 30/30             |
| operators, 81 two-action sequences, effect models    | ~1.5 ms per think               | 0.13            | lost 30/30             |
| operators, four goal aggregates, weighted            | ~0.3 ms per think               | 0.13            | lost 30/30 at every weighting |
| the same, chained one operator deep                  | ~1.5 ms per think               | 0.13            | lost 30/30             |

The `predictor.lua` compiler turns an exported model into one straight-line function (3–5× per
evaluation); a think in the operator versions is a few hundred evaluations; 30 games of 2 v 2 run
in about a second. The thinking-cost question is answered: a fighter that keeps a plan and thinks
per operator, or only when surprised, costs a few hundred evaluations per think and thinks a few
times a second. None of these fighters wins.

**Why none wins, as far as the numbers say.** The models that matter for attacking are the ones
that stay poor: "health this fighter loses" 0.08 → 0.18 with per-fighter aiming senses → 0.20 for
operators; "damage my team deals" 0.34; the four goal aggregates 0.34–0.66 over 0.8 s. Everything
positional is 0.99. The fighters therefore learn to avoid and to drink (the effects they can
predict) and not to attack (the effect they cannot). The 1 v 1's "health the enemy loses" reached
0.79 only with the aiming senses and with one enemy; with two of everything the same senses do not
carry it. The record is also thin where it matters: an explorer that acts at random lands few
aligned shots, so the attacking outcomes are rare events in the data. And the models are fragile:
the same data, the same seed, a ridge of 1e-4 or a guard on term swings — three fighters with the
same fit numbers and different behaviour.

What was tried and did not help: constants in the vocabulary (4, 15, 40, 100), a ridge, a swing
guard, beam search (never turns), longer operators, weight sweeps on the goal.

Open, in order of how much I think each would move the result:

1. **A better explorer.** Half of the record should come from a fighter that already attacks (the
   bot's own rules, or the physics chain), so that hits are common enough to learn from. This is
   the same lesson as the sheep's spoilers: rare outcomes need a record that contains them.
2. **The pairwise aiming senses done properly.** "Who is aimed at whom" as one sense per pair,
   with reload, rather than the counts I added at the end.
3. **Depth 3 for the damage targets**, which took the 1 v 1's "health it loses" from 0.39 to 0.60
   before the aiming senses existed.

### Five hand-written options: how much structure buys, and what latency costs

The user's question: give the fighter five options — shoot at where the enemy will be, heal, move
out of a bullet's line, approach, retreat — each a small hand-written controller from the situation
to a primitive action, and let the learner choose among them. `teamsim.optionAct`, data
`countteamopt.lua` (opt_<target>.csv, TEAM4 shape: TEAM3 plus `healable`/`giveable`, what a potion
would restore), targets the five aggregates over a hold: damage I deal, my team deals, I take, my
team takes, potions I spend. Policies in `team.lua`: `randopt`, `ruleopt` (a fixed rule over the
options), `options` (the learned choice, weights from `OPT_GOAL`). 30 games, seed 5, 2 v 2.

**Latency first.** The same fixed rule over the options, re-choosing every tick or holding each
choice:

| hold (ticks) | won | lost | team health B−A |
|--------------|-----|------|-----------------|
| 1            | 15  | 12   | −4.7            |
| 2            | 3   | 27   | −43.8           |
| 4            | 2   | 28   | −54.3           |
| 8            | 0   | 30   | −66.0           |

A bot that re-decides every 0.1 s is matched by the same rule at the same rate and beaten 30–0 by it
at 0.8 s. Every learned fighter built today commits for 4 to 8 ticks (one-step chains re-plan per
tick but predict whole 0.4 s steps; operators hold 0.8 s), so all of them carried this handicap
before their models were even consulted. The 1 v 1 physics chain that won had one-tick first
parts. This is the largest single effect found in the duel work.

**Then the learned choice**, re-choosing every tick with the same five options (effect models:
dealMe 0.77, takeMe 0.64, dealTeam 0.41, takeTeam 0.48, spent 0.89 held-out R²):

| weights (dealMe, dealTeam, takeMe, takeTeam, potion price) | won | lost | health B−A |
|------------------------------------------------------------|-----|------|------------|
| 1,1,1,1 (no potion price)                                  | 0   | 30   | −107       |
| 1,1,1,1, price 35 / 45 / 50                                | 0 / 1 / 1 | 30 / 29 / 29 | −79 / −70 / −66 |
| 2,1,1,0.5, price 40                                        | 3   | 26   | −42        |

What separates it from the rule, measured over 20 games: it heals at a mean health of 87 without a
potion price and 72 with one (the rule: 36), shoots 20% less, and deals 60% of the damage (286
against 468 per game). Healing 12 now genuinely beats shooting for 0.4 s, and nothing inside a
window says a potion is worth 40 later; the potion price is the right kind of fix (a resource's
future worth as a weighted term, priced by winning) but a linear price cannot reproduce a threshold
with effect models this soft, and the same softness costs it shots at the moments the rule takes them.

So: structure in the *actions* is not what was missing. With the right options and per-tick
choice, a fixed rule matches the bot. The learned choice among the same options does not, because
its models value the next 0.4 s at R² 0.4–0.8 and a fight is decided by timing sharper than that.

### Actions with a length, and the wall every greedy chooser hits

The user's next proposal: instead of fixed steps, hold an action for a variable length and learn
each effect as a function of the length. `countteamhold.lua` (hold_<target>.csv, TEAMH shape:
TEAM4 plus `hold`, the length in seconds; the born senses computed for that length), targets the
five aggregates over the hold; `team.lua` policy `hold` scores every action at lengths 1, 2, 4, 8
ticks by weighted value per tick and commits for the chosen length.

The effects learn as well as before or better as functions of length (damage I deal 0.83, potions
spent 0.92, damage I take 0.52, team damage 0.40–0.44). The fighter loses 30 of 30 at every
weighting and every length set, team health −145 to −160, and never turns once (left 0%, right
0%). Pricing the state a hold leaves — "aimed at an enemy when it ends", predicted at 0.43 — at
2, 5, 10 or 20 changed nothing.

Two-action operators re-chosen every tick, scored by the four aggregates, also never turn (0 of 20),
and adding the sense a two-part move needs — would a shot at the start of part 2, along my facing
after part 1, hit — did not make them turn either (0 of 20; the operator's damage model 0.70).

This is the same wall in every form tried today: **an action whose payoff needs a different action
after it is never chosen by a chooser that values one action (or one hold, or one operator) at a
time.** The beam pruned turning at step one; the options never picked "approach"; the holds never
turn; the operators never turn even with "turn, shoot" in the vocabulary. The fixed shapes of the
first chain survived it by accident ("turn, then shoot for three steps" scored whole), and the
physics chain won because its computed bullets made the second step's hit visible. The learned
versions do not see it because in a record made by random play, "turn then shoot" almost never
lands: the turn is 36° and the alignment window ±8.5°, so the pair is aligned by chance a few
percent of the time, and the model's expected damage for the pair stays near zero.

Two more turns of the operator version, per tick, scored by the aggregates (20 games each):

- With the two-part sense ("would a shot at the start of part 2, after part 1's turn, hit") and
  a length for part 1 (1, 2 or 4 ticks), the record finally carries the setup move: "turn then
  shoot" deals 13 when aligned after the turn and 0.3 when not, and the damage model's first term
  is exactly `gate(gate(shealth, shoot1), aimed2)`. The chooser now sees turn-then-shoot as worth
  something — and still never turns, because from almost any state "drink, then shoot" outranks
  it: a potion counts as 40 less damage taken and nothing charged for it.
- With potions priced (a `spentMe` target, weight 40–60): 0 of 20 at every price, drinking still
  34–42% of ticks. The spend model sits at R² 0.69 for what is a deterministic quantity, so the price
  is applied to a blur; a zero constant in the vocabulary (so "potions > 0" is sayable) did not
  move it. The damage-dealt model, meanwhile, fell from 0.83 (one action, variable length) to 0.65
  as the operator vocabulary grew.

Where the day ends: every learned chooser is limited by the sharpness of its effect models, not by
its search or its vocabulary of actions. The quantities a fight turns on — did the shot land, did
the potion get used, is the enemy about to fire — are near-deterministic given the right senses
and come out of the search at 0.5–0.8, and a chooser comparing options a few points apart cannot
work with that. The structural changes that helped (latency to one tick, instincts as senses,
senses for two-part moves, resources priced by winning) are all right and all kept; the piece that
is missing is a search that gets the deterministic parts of the world to 0.99 the way it gets
positions to 0.99 — more rounds on the goal targets, a record from an explorer that produces the
rare outcomes densely, and the vocabulary gaps found today (a zero; thresholds) closed.

### The future as the target, and why it cannot be learned from a loser

The user's last proposal: score by damage dealt, weighted by health, rather than by health kept.
That is a value of the state, and the clean version is to let the search predict it: `futureDeal`
and `futureTake`, the damage I deal and take from this hold to the end of the fight, as targets
in `countteamhold.lua`, and a chooser that maximises the predicted one minus the other.

From the random explorer's record: `futureTake` is predicted *perfectly* (R² 1.00) by the one term
`mean(health)` — every explorer dies in every game, so its future is always all of its health plus
the death — and `futureDeal` is unpredictable (0.18), because the future in the record is a random
player's. A value learned from random play is the value of playing randomly. The chooser on those
values: 0 of 30.

So the record was made by the chooser itself (70%) plus random (30%), relearned, and re-played,
three times over. The chooser lost 398, 398 and 400 of 400 games while making the record, the
future stayed "all of your health, then death" (0.93–1.00) and "damage dealt from here" stayed
0.20–0.40, and the fights stayed 0 of 30. A value function bootstraps from wins the policy already
gets; a policy that never wins records no futures worth learning. The way in is the same as for
every other rare outcome today: a record that contains winning play — a competent explorer, or the
bot pair's own games seen from the learner's side — before the learner's own games can carry it.

### The hand scorer, the aim-sense bug, and the ablation that names the missing term

The user's turn: write the best scorer we can by hand, confirm it wins, then replace one term at a
time with its learned version and see which replacement loses the fight. `hand.lua`, policy
`hand` in `team.lua`, `HAND_ABLATE=<term>` swaps a term for the learned hold model.

    V(a, n) = [ 15·P_hit − 15·P_hurt + heal − PRICE·spent + RHO·close ] / n + LAMBDA·aimedAfter − MU·teamHurt

with P_hit = shooting, ready inside the hold, aimed, inside RANGE; P_hurt = loaded enemies with me
in their sights given my move, plus bullets on course; heal = what a potion restores, only when
nothing is about to hit me; close = how much the hold brings me toward the nearest enemy;
aimedAfter = the hold ends with me on target and the gun ready; teamHurt = enemy guns on my ally.
PRICE 30, LAMBDA 8, MU 0.5, RHO 1, RANGE 25, CLOSE 12, holds 1/2/4 ticks, chosen every tick.

**First it lost 30–0, and the trace found a bug in the born senses that has been there since holds
were introduced:** "would a shot now hit" was computed over the *hold's* duration, so a one-tick
hold only counted hits inside three units and a step inside twelve, while the bots fight at 12–25.
Every learned model since the holds — options, operators, holds, the future value — was told that
shooting at range never hits. Fixed (`aimed`, `saimed`, `aimedAt`, `sighted` now follow the
bullet's whole flight against the target's straight path), and everything before this section that
used those senses is suspect and would need re-running.

**With the sense fixed, the hand scorer beats the bot pair 28–2 (seed 5, +50 health) and 28–2
(seed 11).** Then the ablation, 30 games, seed 5:

| term replaced by its learned model | won | lost | health B−A |
|------------------------------------|-----|------|------------|
| none (the hand scorer)             | 28  | 2    | +50        |
| aimedAfter (learned 0.46)          | 30  | 0    | +115       |
| hit (damage dealt, 0.77)           | 27  | 3    | +88        |
| hurt (damage taken, 0.57)          | 26  | 4    | +44        |
| team (0.40)                        | 16  | 14   | +4         |
| heal (from damage taken)           | 13  | 16   | −8         |
| spent (potions used, 0.91)         | 0   | 30   | −120       |
| all but spent                      | 3   | 27   | −95        |
| all                                | 1   | 29   | −122; seed 11: 0–30 |

So the learner's hit, hurt and aiming models are already good enough to fight with, one at a
time. The potion is the term that kills it on its own: a deterministic quantity learned at 0.91,
whose small errors, multiplied by the price, make the fighter drink at the wrong moments and lose
every game. Heal and the team term each cost about half the wins. And the errors compound: with
everything learned but the potion it is still 3–27, because four soft terms together mis-rank
options that one soft term does not.

What this settles: the search's models are close on the continuous things and fatally soft on
the discrete, deterministic ones — did I use a potion, how much did it heal — which the vocabulary
cannot say exactly (no zero, no thresholds). That is the first thing to fix, and it is a small
one. After it, the compounding of several near-good terms, which is a matter of rounds and record.

**Correction on the potion term.** The zero constant was not what was missing: added to the
vocabulary, nothing changed, and no zero-based idea ever reached the beam. The record showed why:
the "exact" rule (drink or give when it would restore something) explained potions spent only at
0.85, *below* the learned 0.91 — because a fighter holding "drink" for two ticks drank twice, so
spent was a count that depended on the hold's length and the potions left. The game had no reload
on potions. Given one (the gun's, 8 ticks, for the bots too), the bot pair against itself is
unchanged (8–13–9), the hand scorer still wins 27–3, and the learned-potion ablation goes from 0–30
to 19–11. The lesson is a better one than "add a zero": when a deterministic quantity refuses to
be learned, look at whether it is deterministic — here the world had a loophole, and the learner
was faithfully modelling the loophole. All learned: 3–27; all but the potion: 0–30 (the compounding
of the soft continuous terms, as before).

### Starting the learner from the hand rules (`CFG_start`)

The user's proposal: seed the model with the hand scorer's terms and let the search only add or
repair. `CFG_start="agg:expr;agg:expr"` parses written formulas (any operator, group leaves as
named, numbers as constants), fits their scales, and puts them in as the first terms; the rounds
then add only what clears the floor on the residual; stream mode's ladder would repair them as any
other term. Results on the hold models, 30 games:

| | seeds only | seeds + 8 rounds |
|---|---|---|
| damage dealt, seeded with P_hit  | R² 0.40 | 0.75 |
| damage taken, seeded with P_hurt and heal | 0.30 | 0.7x |
| potions, seeded with the exact rule | 0.83 (scales 0.99, 0.98) | 0.88 |
| hand scorer with everything learned | 0–29 | **6–24** (best "all learned" yet; was 1–29) |
| with hit, hurt, spent learned, rest hand | 0–30 | 0–30 |

Two things this settles. The mechanism works: a written expectation goes in, keeps its place with
a fitted scale, and the search adds around it. And the surprise: **the hand rules are poor
predictors of the record** — 0.40 for damage dealt against the learned 0.77 — while being far
better *decision* rules (27–3 against 3–27). Predicting how much damage a random explorer's hold
produced is not the same task as ordering the options a fighter has in one state. The record
teaches the level; the choice needs the difference. The sheep world had this right from the start
without naming it: its test files held every plan for the same situation, and the chooser was
scored on the difference. The next step that follows is to train on contrasts — the outcome of
each action minus the outcome of a baseline action in the same state — so that the search's
objective is the one the chooser uses.

### The lookup: a table or a tree of facts instead of scoring nine actions

The user's proposal: turn the chosen senses into a multi-dimensional table with one action per
cell, so acting is a single lookup. Built as `tablefacts.lua` (24 yes/no facts: the boolean senses
and thresholds on the numeric ones), `maketable.lua` (greedy axes, cells filled by the action
whose value summed over the cell is best; the record is the hand scorer's play, 150 games, 34k
situations, with every action's value in each), `maketree.lua` (the same as a tree, each node
splitting on the fact that most reduces the value lost in its own rows), and `table` / `tree`
policies in `team.lua`.

| | cost per tick | value kept of the hand scorer's | vs the bot pair |
|---|---|---|---|
| hand scorer (9 actions × 3 holds × 6 terms) | ~150 µs | all | 27–3 |
| grid, 8 axes by majority action | 8 µs | 53% of decisions agree | 0–30 |
| grid, 8 axes by summed value | 8 µs | 0.62 of 1.16 per row lost | 0–30 |
| grid, 10 axes with finer angle/distance facts | 9 µs | 0.58 lost | 0–30 |
| tree, 65 splits, depth 11 | 10 µs | 0.59 of 0.84 lost | 0–30 |

Where the value goes: when the hand scorer drinks or gives, the grid shoots 100% of the time
(the potion facts never earned an axis — healing is rare, so its share of the total loss is
small); when it strafes out of a bullet the grid shoots half the time; when it turns, the grid
turns about half the time and the wrong way a quarter. The tree fixes the rarity problem in
principle and does no better, because the limit is the facts: the fight is decided by continuous
things — which side the enemy is on and by how many degrees, how far, how many ticks to reload,
which side of me a bullet passes — and yes/no facts at a few thresholds keep about a third of
that. The formula keeps all of it for 150 µs, fifteen times the lookup and still far under a
tick. A lookup is the right shape for the parts of a decision that are discrete (do I have a
potion, is the gun ready); the continuous parts want the formula.

**The lookup picking templates instead of primitives** (`TEMPLATES=1 maketable.lua`, policy
`tabletpl`): the cells hold one of the five action templates (lead-shot, heal, dodge, approach,
retreat), whose continuous part — which way to turn, which side to step — is computed inside the
template from the senses. The record's value lost per situation falls from 0.59 to 0.35 with eight
axes (aimed, off-aim 4°, health ≤ 50, within 35, sighted, potion worth 30, bullet coming, off-aim
10°), so the split "lookup for the kind of situation, formula for the continuous part" keeps far
more of the decision than facts alone. It still loses 30–0: it heals 15% of the time where the
winning rule heals 2%, never dodges, and stands 62% of ticks, because the templates it chooses
return "none" while reloading or slightly off-aim. The loss that remains is timing — when to
commit to which template — which the eight facts do not carry either. 74 of 256 cells filled.

**Operators at 20%, depth and beam doubled** (`CFG_ops` added; `add,mul,gt,gate` at depth 4,
beam 60 against all seventeen at depth 2, beam 30), on the hold targets:

| target | full vocabulary, depth 2 | four operators, depth 4 |
|---|---|---|
| damage I deal | 0.77 | 0.65 |
| damage I take | 0.53 | 0.52 |
| potions spent | 0.89 | 0.86 |
| aimed after | 0.45 | 0.41 |
| search per round | 0.47–0.57 s | 0.37–0.41 s |
| hand scorer, all terms learned | 3–27 | 4–26 |

Slightly cheaper per round (four operators shrink each level more than the doubled beam and depth
grow it), slightly worse on every target, and the same fight. Depth does not buy back what the
operators lose: the terms that matter here use `sub`, `div`, `min`, `lt` and the vector
operators, and no composition of `add`, `mul`, `gt` and `gate` four deep replaces `min(potions,
1)` or `lt(dist, 25)` cheaply. Vocabulary is not where the time or the accuracy is.

**A beam that keeps only different ideas** (`beamApart`: a beam slot goes to an idea only if its
values correlate below the ceiling with every idea already in the beam; 1 = off):

| ceiling | damage I deal | damage I take | potions | aimed after | s/round | all learned |
|---|---|---|---|---|---|---|
| off | 0.77 | 0.53 | 0.89 | 0.45 | 0.46–0.57 | 3–27 |
| 0.95 | 0.75 | 0.56 | 0.89 | 0.46 | 0.49–0.56 | 2–28 |
| 0.80 | 0.75 | 0.56 | 0.89 | 0.45 | 0.50–0.59 | 5–25 |

Within noise on every count: a couple of hundredths either way on the fits, the same round time,
fights inside the seed spread. The beam was not full of near-copies — the twin rule and the
signature already remove the exact ones, and the near ones are not what limits these targets.

### Beam 200: a fully learned scorer that wins, and why its twin loses

Beam 200 at depth 2 (rounds 1.6–2.3 s) lifted "aimed after the hold" from 0.45 to 0.65 and gave
the first fully learned fighter that beats the bot pair: with the search's own models in every
term of the hand scorer, search seed 7 wins **27–3, 30–0, 28–2** on fight seeds 5, 11, 17 —
better than the hand scorer itself on seed 17 (21–9). The same search with seed 8, with equal or
better held-out fits on every target (damage dealt 0.745 vs 0.752), loses 1–28, 1–29, 0–30.

Swapping models between the two sets: any single seed-8 model dropped into the seed-7 set still
wins (27–30 of 30); the seed-8 set is rescued by seed 7's damage-dealt model alone (1–28 →
25–5). The two damage-dealt models, side by side on live situations, agree everywhere except the
one case a fight turns on — *shooting now, aimed, gun ready, one-tick hold*: the winning model
says +2.5 damage, the losing one says −1.65, because its fourth term subtracts distance when
shooting at a fighter it is aimed at. That case is 617 situations of 7,000; R² over the record
cannot see it, and the fight is decided by it.

This is the level-versus-difference finding in one number. What the chooser needs from a model
is the *sign of the difference between actions in the same state*; what the search fits is the
level across states. Two models equal on the second can have opposite signs on the first. The
beam-200 win is real and repeatable across fight seeds, and it is also luck of the search seed,
which is the same thing said twice: the objective the search optimises is one step removed from
the one the fighter needs. Training on contrasts remains the thing to build.

### Contrast training, and the 50 ms question

**Contrasts.** `countcontrast.lua` plays every action from a copy of each situation (two holds,
the teammate deciding by the hand scorer inside each future) and targets the difference from
doing nothing. 14k situations, 255k scenarios, half an hour of simulation. The full search on it
(beam 200, seeds 7 and 8): damage dealt 0.24 / 0.21, damage taken 0.23 / 0.24, potions 0.76 /
0.69, aimed after 0.43 / 0.35 — and the contrast scorer (`HAND_CONTRAST=1`, every term a learned
difference) loses 30–0 on every seed, both search seeds, with both fighters dead in most games.
Differences of outcomes over one to four ticks are mostly zero and otherwise noise, and a model
fitted to them mis-orders actions worse than the level models do. The cheap variant — the five
born expectations with scales fitted on contrasts by one least-squares solve — also loses 30–0.
So the diagnosis "fit the difference, not the level" was right about the *objective* and wrong
about the *method*: the raw difference of two short rollouts is not a usable target.

**The 50 ms training budget** (the user's goal: a fighter that sometimes wins from 50 ms of
training). What fits in 50 ms and what it yields:

| training | cost | vs the bot pair |
|---|---|---|
| a full search round today | 0.5–2 s | (8 rounds × 5 targets: 27–3 with the lucky seed, 1–28 with the other) |
| the smallest search: depth 1, beam 5, 100 situations, 3 rounds, 5 targets | ~150 ms | 0–30 (fits 0.27–0.40) |
| born expectations, scales fitted to outcome levels on 3k situations | ~5 ms of solving | 0–30, 0–30 |
| born expectations, scales fitted to contrasts | ~5 ms | 0–30, 0–30 |
| born expectations with the hand weights (no fitting) | 0 | 27–3, 28–1, 21–9 |

The only thing that fits in 50 ms is calibrating inborn expectations, and calibrating them to
any outcome record we can make — levels or differences — produces a *worse* fighter than the
uncalibrated weights: a hit fitted at 9.2 instead of 15, a bullet at 18, a heal at 1, and the
ordering of options goes wrong. The weights that win were found by playing (the sweeps and the
ablations), which costs games, not milliseconds. Within 50 ms, then, the creature that wins is
the one born winning, and nothing I can fit in that time improves it. What would: a fitting
objective that is about ordering actions within a state (ranking, not regression), which needs
no counterfactual simulation and is cheap to evaluate — not built.

### 50 ms, take two: fit the born weights on the decision, from a lived record

The five born expectations fitted as separate outcome models lose because each is calibrated
alone to its own level. Fitting the hand's **seven terms as one value** on a **fight-relevant
outcome** is a different objective, and it is the first thing that has produced a fighter that
wins some games for less than a search round's cost.

*Counterfactual version* (`fitweights.lua`): every action is played from a copy for its hold and
then by the hand up to horizon H; target = Δ(dealt − taken − ½ team taken) against doing
nothing; features = Δ of the seven terms. One least-squares solve of 7 unknowns, microseconds.
Horizon 8, 5 games (1156 situations, 90 s of rollouts): 3–27, 2–28, 2–28. Horizon 4 loses
0–30 (spent +15: within four ticks a potion only heals). The hand's own weights have *negative*
R² on this target on every horizon — the hand scorer is not a short-horizon outcome predictor,
it is a whole-fight heuristic — and the fitted R² is 0.02–0.05: nearly all of the difference
between actions over 8 ticks is noise the seven terms do not see.

*Lived version* (`fitlived.lua`): no copies. The fighter records the seven terms of the action it
takes, and H ticks later what happened to it. Same solve with an intercept.

| explorer | games / rows | horizon | training compute | fights (seeds 5, 11, 17) |
|---|---|---|---|---|
| hand + 30 % random | 20 / 4658 | 8 | 0.1 s total (~20 µs per row; solve < 1 ms) | 0–30, 3–27, 1–29 |
| same | 20 / 4658 | 16 | same | **5–25, 3–26, 8–22** |
| same | 20 / 4658 | 24 | same | 7–22, 5–25, 1–29 |
| same | 20 / 4658 | 32 | same | 2–28, 1–29, 1–29 |
| same | 50 / 11.6k | 16 | 0.25 s | 5–25, 1–29, 0–30 |
| same | 1, 2, 5 games | 16 | — | weights unstable (aimedAfter negative, spent ±54) |
| purely random | 20 / 4658 | 16 | 0.1 s | 0–30 ×3, both dead (hit −3.4, close +36) |
| round 2: living by the round-1 weights | 20 / 4658 | 16 | 0.1 s | 0–30 ×3 (close +34, aimedAfter −0.8) |

So: training compute is inside the budget by a wide margin (about 5 ms per game of living,
plus a sub-millisecond solve), and the result sometimes wins — 15–25 % of games at horizon
16–24 against the bots the hand beats 90 %. Weights it finds (horizon 16): hit 4.7, hurt −5.7,
heal 0.6, spent **+8.9**, close −2.4, aimedAfter 3.8, team 0. It has learned that drinking pays
and that the hand's potion price is wrong for a 16-tick horizon, and it under-values the hit.

Two hard limits showed up. **The life must be lived competently**: the same fit on a random
life, or on a life lived by its own first weights, gives a charging fighter that dies every
game (closeness and spending get the credit for outcomes the good policy caused). The
record's policy is the confound; without either a competent teacher in the loop or
counterfactuals this fit does not bootstrap. **Twenty games is the floor**: fewer than about
4000 lived decisions gives weights with the wrong signs.

Files: `fitweights.lua` (counterfactual), `fitlived.lua` (lived), `hand.lua` `HAND_W=w1..w7`
(weights on the raw terms hit,hurt,heal,spent,close,aimedAfter,team; the hand's own are
15,−15,1,−30,1,8,−7.5).

## 16. Ten numbers, five actions, no structure, 50 ms: the same learner on both games

The user's constraint: the creature gets about ten numbers and five actions, 50 ms of training
compute from nothing, no structure allowed -- and the same system must not do horribly on the
sheep game. `tabula.lua` is that learner: one linear value per action over the numbers (or the
numbers and their pairwise products, "quad"), ridge least squares on whatever score the world
hands back, epsilon-greedy. It is told nothing about what the numbers mean or the actions do.
Training compute is the accumulation of the normal equations and the solves; living is not counted.

**The sheep game** (`tabsheep.lua`; the world of countchoose.lua). Ten numbers: the two nearest
wolves' offsets and velocities, own speed, the window. Five actions: still, +x, -x, +y, -y. Score:
minus the harm of the window. It lives 12,000 situations, one action each, 30% random, refitting
every 500, then is scored as chooser.lua scores on 2,000 fresh situations played under all five
actions.

```
mean realized harm per situation                  training compute
  random                               0.344
  still                                0.358
  away (the hand reflex)               0.214
  linear learner, seeds 1 / 2 / 3      0.202 / 0.188 / 0.170      6 ms
  quadratic learner                    0.201                      73 ms
  the symbolic search's model (Sec 14) 0.156                      ~2 s
  oracle                               0.001
```

The linear learner, with 6 ms of training, beats the hand-written reflex and picks the oracle's
action in 90% of situations. It needs the living: 1,000 situations 0.296, 2,000 0.239, 4,000
0.222, 12,000 0.202. The products buy nothing here.

**The duel** (`tabduel.lua`; duelsim.lua, 1 v 1 against the scripted bot). Ten numbers: the
enemy's offset ahead and aside of me, its relative velocity ahead and aside, cosine and sine of its
heading relative to mine, both healths, my cooldown, my potions. Five actions: walk, shoot, drink,
turn left, turn right. Score: the change in (my health - its health), a death counting 100,
either over a horizon H (one solve per game), or one step at a time with fitted Q iteration
(`MODE=fqi`, gamma 0.95, ten iterations every ten games -- off-policy, so a random life is a
valid record). Then 30 greedy games on a fixed seed.

```
                                                  training     greedy vs the bot (won-lost-drew)
  horizon 8,  20 games, linear                    0 ms         0-30-0
  horizon 8,  20 games, quad                      33 ms        0-30-0
  horizon 24, 50 games, linear, seed 1            3 ms         7-22-1
    same, seeds 2 / 3 / 4 / 5                     3 ms         0-30, 0-28-2, 0-28-2, 0-30
    same, 200 games                               17 ms        0-24-6
    same, random life (eps 1), 50 / 100 games     3 ms         0-29-1, 0-26-4
  horizon 16 / 32 / 48, 50 games, linear          3-7 ms       0-30 each
  horizon 24 / 48, 50 games, quad                 73-79 ms     0-30 each
  fitted Q, linear, 50 games, seeds 1 / 2 / 3     43 ms        0-30, 0-29-1, 0-30
    gamma 0.90 / 0.98                             43 ms        0-29-1, 0-30
    random life                                   43 ms        0-30 (drinks 90%)
  fitted Q, quad, 50 games                        218 ms       0-30
```

One seed won seven games; nothing else won any. **Why the two games differ.** In the sheep game
the score is exact and immediate (the harm of this window, this action), the best action is a
near-linear function of the nearest wolf's offset ("run away from it"), and one situation is one
row. In the duel the reward is sparse and late (a hit is +15 some 20 ticks after the turn that
made it possible, and whether it lands depends on the bot), a good policy is a conjunction (aimed
AND in range AND ready, then shoot; otherwise turn toward), and a linear value per action cannot
hold the conjunction while a quadratic one needs more rows than 50 games give and four times the
budget. Fitted Q with linear features finds "drink" (the one immediate reward) and little else.
The evidence law of Sec 3 again: the shape the duel needs is three operators deep in these ten
numbers, and no structureless fit reaches it on 6,000 rows.

**Verdict on the user's test.** The exact system does well on the sheep game -- better than the
hand reflex, at 6 ms -- and loses the duel except by luck. The sheep game is a one-step choice
with an exact score; the duel is not, and that, not the budget, is the line.

Files: `tabula.lua`, `tabduel.lua` (env HORIZON, EPS, RIDGE, MODE=fqi, GAMMA, ITERS, FITEVERY,
SEED, EVALSEED), `tabsheep.lua` (env EPS, RIDGE, FIT, SEED, TESTSEED).

**What the duel wins actually are** (traced from the replay, greedy games 1 and 3 of the 7-22-1
run). The spawn faces the two fighters roughly at each other (heading noise ±0.75 rad). In the
games it wins the learner starts within a few degrees of aimed (−1.6°, −4.6°) and never turns:
its aim offset is constant to the last tick. It shoots whenever the gun is ready and drinks when
hurt, and the bot, whose rule is "walk straight at the enemy until 25 units", walks down the line
of fire for forty ticks -- bullets reach 75 units, the bot only shoots inside 25 -- arriving at
40-55 health before it fires once. The rest is a trade at 12 units that the head start decides.
In greedy game 2 the spawn is 37° off; the learner shoots into nothing, drinks both potions, and
ends at 25 health circling for 800 ticks in a draw. So the learned policy is "shoot on cooldown,
drink when hurt"; the aiming is the spawn's, and the seven wins are the seven starts that were
aimed. That is consistent with the seeds that won nothing.

### Thrown in: no training phase, refit on the mispredicts, 50 ms in all

The user's next constraint: no exploration phase. The learner is born with zero weights, fights
greedily from its first tick, and after every match keeps only the rows its values got wrong by
more than a threshold (`SURPRISE=5`, in health points over the horizon) and re-solves on those.
Training compute is capped at 50 ms in all (`BUDGET_MS=50`); the check is 30 greedy games.

```
                                                 games in the 50 ms   greedy vs the bot (won-lost-drew)
  refit on every row, greedy, seed 1             410                  0-30-0
  mispredicts > 5, greedy, seed 1                663                  0-1-29
    seed 2                                       384                  0-14-16
    seed 3                                       1027                 0-0-30
  mispredicts > 15, greedy                       874                  0-8-22
  mispredicts > 5, quad features                 28                   0-6-24
  mispredicts > 5, 5% random actions             699                  0-30-0
  mispredicts > 5, horizon 8                     1107                 0-30-0
```

It learns not to die. The survivor's policy is walk 65-70% and one turn direction 27-30%, no
shooting, no drinking: it circles at 11-12 units and the bot, which fires only when within about
9 degrees of it, keeps turning after a target that keeps sliding sideways, and misses when it
does fire. Games run to the 900-tick limit; on seed 3 it drew 987 of its 1027 training games. It
never wins because winning needs the turn-and-shoot chain that pays nothing until it completes,
and circling pays every tick in damage not taken. The mispredict filter is what makes this work:
the rows that are kept are the ones where it got hit or expected to and was not, so the record is
about consequences; fitting every row (the first line) drowns those in the ticks where nothing
happened. Five percent random actions destroy it: a random action while circling is a hit taken,
and the record then says everything is dangerous. Horizon 8 is too short to see the bullets
coming and it dies as before. The mispredict check itself is one dot product per row, about
3 ms for the run, which the reported training figure does not include.

**Timing, re-measured.** The 50 ms above was `os.clock`, which ticks in whole milliseconds on
Windows; `tabula.lua` now times with QueryPerformanceCounter. The refit figure holds (the seed-3
survivor: 890 games, 50.0 ms of refits), but two costs sat outside it: the per-tick thinking
(features and five values: 0.67 µs a tick, 525 ms over 787k ticks) and the mispredict check
(0.76 µs a row, 600 ms). Charging the check to the budget as well, 50 ms buys 77 games on seed 3
and the survivor still appears (0-1-29); charging the thinking too, 39 games and 0-0-30. Seed 1
under the same honest budget: 274 games, 0-30-0, so the survivor is a lucky-seed result at 50 ms
and a reliable one at about 650 ms of learner compute.

### The closing zone

`duelsim.lua` `ZONE=1`: a safe circle round the centre shrinks from 57 units (the whole arena)
to 5 over `ZONE_T` = 600 ticks; a fighter outside it loses `ZONE_DMG` = 1 health a tick. The bot
got a rule: within three units of the edge or past it, turn to the centre and walk. The learner
got three more numbers: how far inside the circle it is, and the centre's offset ahead and aside
of it. Thirteen numbers, the same five actions, no other change.

```
                                                    greedy vs the bot, 30 games
  thrown in, mispredicts, 50 ms, seeds 1 / 2 / 3     0-30-0, 0-30-0, 0-30-0   (games last 26-50 s)
  trained 50 games with 30% random actions           0-30-0
  untrained, random actions                          0-30-0
```

The draw is gone: nothing can circle for 90 seconds inside a five-unit circle with the bot walking
to its centre. What the learner takes from the zone is drinking (7-21% of ticks, up from 0), which
offsets the burn for a while, and one turn direction; it does not learn to walk to the centre,
because walking there pays only later and through the zone term, which is a straight line in
"how far inside", while circling pays now. With the draw removed the structureless learner has
nothing left against the bot: it loses every game, as does the exploring recipe, as does an
untrained one. The zone is in the replay page as a third run.

### Two values instead of one (`tabduel2.lua`)

The user's proposal: predict damage dealt (d) and damage taken (t) as two separate linear
values per action, and combine them at choice time so that doing both earns more than either:
`sumsq` = (d + (M − t))², `product` = d · (M − t), against `linear` = d + (M − t), M = 30.
Thrown in greedy with the mispredict filter (either value wrong by more than 5), 50 ms of refits
plus mispredict check.

```
                            no zone, seeds 1 / 2 / 3         zone, seeds 1 / 2 / 3
  linear                    0-30-0, 0-19-11, 0-3-27          -
  sumsq                     0-30-0, 0-19-11, 0-1-29          0-30-0 x3
  product                   0-30-0 x3 (walks 100%)           0-30-0 x3 (walks 100%)
  sumsq, exploring recipe   3-24-3 (the lucky seed-1 spawns again)
```

Two things. **Squaring a sum changes no choice.** (d + v)² is monotone in d + v, so `sumsq`
ranks the five actions exactly as `linear` does; the rows are the same to within the ticks where
the sum went negative. A "much more for both" needs a cross term with its own weight, d·v added
to d + v, or the product alone. **The product alone breaks.** With d near zero for every action
but a landed shot, d·(M − t) is near zero everywhere and negative wherever t exceeds M, and the
argmax lands on walking every tick. Splitting the target does make the dealt model cleaner
(its rows are +15 events only), but the model is still a line in ten numbers and the chain from
turn to hit is still unrepresented, so the result is the earlier one: the survivor on the lucky
seed without the zone, nothing with it.

**a + b + 36ab/(a+b)** (`COMBINE=harm`, K = 36; a = dealt, b = avoided): a genuine cross term,
a scaled harmonic mean that is large only when both are. Thrown in, no zone, seeds 1/2/3:
0-30-0, 0-22-8, 0-2-28; with the zone 0-30-0 ×3; exploring recipe 0-18-12. It does pull the
policy toward shooting where the plain sum did not (seed 1 shoots 51% of ticks; in the zone 9-34%),
because a landed shot now lifts the whole score rather than one fifteenth of it, but the shots are
unaimed: the value of turning is still the flat line it was, and a combination of two predictions
cannot put a peak into either of them.

### Several things at once (`tabduel3.lua`)

The user's next change: moving, turning, shooting and drinking are no longer one choice among
five but four choices made every tick -- move (still | walk), turn (none | left | right), shoot
(hold | shoot), drink (no | drink) -- nine linear values over the same numbers, each choice
taking its best option, every chosen option fitted to the one score (the change in health lead
over 24 ticks). `duelsim.lua` got `actMulti` (turn, then move, then shoot, then drink, in one
tick) and `botMulti`, the scripted bot's rules made non-exclusive (`BOTMULTI=1`). Thrown in
greedy, mispredict filter, 50 ms of refits plus check; the check is 30 greedy games.

```
                                                 seeds 1 / 2 / 3 (won-lost-drew)
  bot one thing a tick, no zone                  0-1-29, 0-0-30, 1-0-29
  bot one thing a tick, zone                     14-16-0, 8-22-0, 5-25-0     (seed 1 on eval seeds 11, 17: 16-14, 17-13)
  bot several things too, zone                   0-30-0, 3-27-0, 8-22-0 (5-24-1 on a rerun)
  bot several things too, no zone                14-0-16, 0-0-30, 13-0-17
  exploring recipe (30% random per choice)       no zone 0-0-30; zone 0-30-0
```

The first fighter from nothing that wins games it did not spawn into. Its policy is the same on
every seed: walk every tick, fire every tick the gun is ready, drink every tick (a no-op when
full, so the drink value never learns to be choosy), and turn -- toward the enemy: in the traced
win 424 turns toward against 25 away. It orbits the bot at one to two units, firing on every
cooldown, and the bot, which turns at the same rate, is always a few degrees behind. The loss it
records is the failure mode: with the enemy behind it, the turn value (a line in "aside") flips
sign as it oscillates, it dithers left-right, walks away, and burns in the zone.

Why this works when one-of-five did not: **the turn is no longer paid for by not shooting.** With
exclusive actions a tick spent turning is a tick not spent shooting or walking, so the turn's
value had to beat the shot's on the same score and never did; now the turn's value is fitted
with the shot happening anyway, and "left when the enemy is left" is the only thing left in its
column to explain. The credit problem did not go away; the competition that hid the credit did.
The zone helps for the same reason it hurt before: without it the orbit is a draw; with it the
bot walks to the centre and the orbiting learner, which never learned the centre, gets its
kills before the burn. Against a bot that also acts in parallel it is even without the zone
(14-0-16, 13-0-17 on two seeds, all draws on the third) and loses most games with it.

Note the budget stop is by measured time, so the number of games in 50 ms varies run to run
(seed 3 in the zone: 8-22 then 5-24-1). Nothing else is random between reruns.

### Exclusive gun, costs for moving and shooting -- and a correction

The user's next rules: shooting and drinking exclusive in a tick (the learner's gun is one
choice: hold | shoot | drink, `GUN=excl`); one health per second of moving (`MOVECOST=1`); one
health per shot (`SHOTCOST=1`); both fighters pay. First runs, all 0-30-0, showed something odd:
the turn choice and the gun choice always chose the same option index (left 63% / shoot 63%,
right 31% / drink 31%, on every seed).

**The correction.** At birth every value is zero, ties went to the first option, so two choices
with the same number of options saw identical rows from the first tick and were fitted to
identical weights for ever: clones. In the four-choice run above, move, shoot and drink (two
options each) were one learner in three places -- "walk 98% shoot 98% drink 98%" on every seed
is that -- and the turn choice (three options) was the only one on its own. So the 14-16 fighter
was "always walk, always shoot, always drink, and a learned turn". The turn was genuinely learned
(424 toward, 25 away), but the rest was a coupling accident that happens to be a strong policy in
this game. Ties are now broken at random (`tabduel3.lua`), and the choices are independent.

```
with random tie-breaking                                 seeds 1 / 2 / 3
  four choices, no costs, zone, bot single (the 14-16)   0-30-0, 0-29-1, 0-30-0
  gun exclusive + costs, zone, bot single                0-30-0 x3
  gun exclusive + costs, zone, bot multi                 0-30-0 x3
  gun exclusive + costs, no zone, bot multi              0-30-0 x3
```

With the three independent, each is fitted to the whole score with the others as noise, and
none of the three finds its part: the shoot value learns the shot's cost (1 health, immediate)
before its payoff (15, later and conditional), so it holds 80-94% of ticks on most seeds; the
drink value learns the heal; the turn value still aims on some seeds (seed 3, zone, bot multi:
left 90%) but with nothing fired it is aiming for nothing. The structureless learner is back to
losing every game, and the earlier win is withdrawn.

**Sideways movement** (move: still | walk | strafe left | strafe right; `MOVES` in tabduel3.lua,
codes 7/8 in `actMulti`, the move cost applying). Exclusive gun, costs, random tie-breaking:

```
                                            seeds 1 / 2 / 3
  zone, bot single                          0-30-0 x3
  zone, bot multi                           0-30-0 x3
  no zone, bot multi                        1-16-13, 0-25-5, 0-30-0
  no costs, four choices, zone, bot single  0-30-0 (seed 1)
```

Given a sideways option it finds the dodge: without the zone it strafes one way 98% of ticks and
holds fire 98%, circling the bot at a range where the bot's shots miss -- the old survivor, now
sideways -- and it draws 13 and 5 games. But moving costs one health a second and the circle lasts
80 seconds, so it also bleeds to death in most of them: the survivor's trick is priced out by the
move cost. With the zone the same dodge walks it into the burn. Nothing it does with the extra
option changes the gun: shooting still costs one now and pays rarely later, so it holds.

### One raycast

`RAY=1` in tabduel3.lua: one more number, 1 if the enemy is on the line of my heading within a
bullet's reach and hit radius, else 0 -- "what I am looking at". With it the peak the line could
not hold is a single input a line can hold. Same recipe (strafe, exclusive gun, costs, zone,
random tie-breaking, thrown in, 50 ms): 0-30-0 on every seed, all three variants. The side
model's weight on the ray for enemy health lost after a shot was **negative** (−1.9).

**Why: it never had the experience.** Plain counts of the thrown-in life, unfiltered: ticks
with the gun ready and the ray on the enemy, 206; ticks it chose to shoot on one of them, **1**.
The shoot value had gone negative on unaimed shots before the first aimed opportunity, and a
greedy learner never fires again in the one state where firing pays. The ray is informative --
in an exploring record 67% of ray-on shots cost the enemy 15 within the horizon against 12% of
ray-off shots -- but the record has to contain them.

**Exploring the gun alone** (`EPS_GUN=0.3`: the gun choice random 30% of ticks, moving and
turning greedy -- a random shot costs one health, a random step gets it killed):

```
raycast + gun exploring 30%                  seeds 1 / 2 / 3
  zone, bot single                           0-30-0 x3
  zone, bot multi                            1-29-0, 2-28-0, 7-23-0
  no zone, bot multi                         4-26-0, 0-18-12, 0-30-0
  gun exploring 10%, zone, bot single        0-30-0, 1-29-0, 0-30-0
```

With shots in the record the ray's weight in the lead model turns positive (+7.5) and its own
record shows 56% of ray-on shots landing against 22% of ray-off; it now shoots 13-83% of ticks
depending on the seed and wins a few games against the parallel bot. It still loses most:
against the one-thing bot the aimed shots come while walking into the bot's own aimed shots, and
the trade at one health a shot and one a second of moving goes to whoever spawned better. The
enemy-health side model still puts the ray near zero (−0.6) because the facing and offset
numbers carry the same information in a line, so the credit for a hit is spread across them.

### A memory of surprising events (`MEMORY=n` in tabduel3.lua)

The user's proposal after the raycast finding: give it a memory of the events that surprised
it. A settled row whose outcome surprised the values by more than SURPRISE *and was good*
(y ≥ MEMGOOD = 10) is kept as an event: the numbers seen, the picks, the outcome; capacity 200,
oldest out. Two uses. **Weight**: the event enters the fit MEMW = 20 times, so one experience can
move a line. **Retest**: when the numbers now are within MEMRADIUS = 0.35 (Euclidean, scaled
inputs) of a remembered event, the event's picks are repeated -- the experiment is run again --
and the event keeps a running mean; after four retests with a mean under 5 it is forgotten. No
exploration at all otherwise: greedy from birth, raycast on, exclusive gun, costs, zone.

```
                                  seed 1              seeds 2 / 3 / 4 / 5 / 6 / 7
  zone, bot multi                 25-5-0              0-30-0 each
    seed 1 on eval seeds 11, 17   22-8-0, 23-7-0
  zone, bot single                21-9-0              0-30-0, 0-30-0
  no zone, bot multi              0-29-1              0-30-0, 4-26-0
  with gun exploring 10%          9-21-0              5-25-0, 1-29-0
```

**What seed 1 found.** Strafe left and turn right, every tick, firing on every cooldown: it
orbits the bot at three to nine units, facing it, faster than the bot can turn (10 units a second
at a radius of four is 2.5 rad/s against the bot's 1.57), and at that range the bullet's hit
radius of three covers ±20-40°, so nearly every shot lands while most of the bot's miss. The
enemy loses 15 every eight ticks; the fighter loses one a second to moving and a hit now and then.
Two of its five losses on the check seed are spawns facing away. Its life: 1,167 events stored,
3,472 retests, 1,645 confirmed, 372 forgotten, in 82 games; the memory scan is 200 events × 14
numbers a tick and raised the per-tick thinking from ~30 ms to 148 ms over the life, outside
the 50 ms of refits and checks.

**What the other seeds found.** Nothing: 86-570 events, few confirmed, and the policy is the
old dodge or the old drink. The first good surprise has to be the right kind -- a hit while
orbiting -- and whether one happens in the first games is the spawn's doing. This is the first
fighter from nothing that reliably wins its check games, and it is one seed in seven at 50 ms.

Four times the budget (200 ms) does not make seeds 2 or 3 find it: 1,291 and 411 events, 2,206 and 977 confirmed, still 0-30-0 -- what they confirm is drinking and dodging. The memory retests what surprised it; it does not go looking for the surprise it has not had.

### Thinking cost at 240 Hz (target: 0.5 ms of thinking per second of life)

`BENCH=1` in tabduel3.lua: after the life, one greedy game's numbers are recorded tick by tick
and spread into 24 drifting frames a tick; the trained learner thinks on every frame, and with a
skip cache (`SKIP=1`, `SKIPTOL`: a frame whose numbers all moved less than the tolerance reuses
the last picks). The loop without thinking is subtracted. Two memory layouts: the events in
tables (`MEMINDEX=1` files them in a grid on the enemy's offset; it barely helped, the fights
cluster in a few cells) and `MEMFLAT=1`, the events' numbers in one flat array.

```
ms of thinking per second of life at 240 Hz          JIT (LuaJIT)     interpreter (luajit -joff, a proxy for Luau)
  memory 200, tables, every frame                    1.41             3.53
  memory 200, flat, every frame                      0.75             3.32
  memory 200, flat, skip 0.05 / 0.1                  0.20 / 0.13      1.07 / 0.65
  memory 100, flat, skip 0.05 / 0.1                  -                0.53 / 0.37
  memory 50, flat, skip 0.05 / 0.1                   -                0.35 / 0.25
  no memory, every frame                             -                0.58
  no memory, skip 0.05                               -                0.19
```

Per think: 2.4 µs without the memory (interpreter), 14 µs with 200 events; the value
evaluation (14 numbers × 10 options) is a tenth of it, the memory scan the rest. The levers,
in order of what they buy: (1) do not think on a frame whose numbers have not moved -- at 240 Hz
against a 10 Hz world that is most frames, and a 0.05 tolerance on inputs scaled to ±1 is about
two units of offset -- ×3-5; (2) keep the events' numbers in one flat array -- ×2 under the JIT,
nothing in the interpreter; (3) hold fewer events -- linear, and the fighter needs them: 50 held
gave 3-27, 100 gave 15-15, 200 gave 24-6 / 29-1 on the same seed; (4) think at a lower rate than
the frame rate: cost is per think, so 60 Hz is a quarter of 240. Under the JIT the target is met
with (1)+(2) at 200 events; in the interpreter it takes (1) at 0.1 or a memory of 100 at 0.05,
or thinking at 36 Hz. `MEMMERGE=1` (merge a new event into a twin within half the radius) did not
shrink the memory (198 distinct events) and broke the fighter (0-30); off.

## 17. Eight in the arena, each learning alone

`ffa.lua` (a free-for-all: N fighters, the zone, several actions a tick, the costs),
`tabmind.lua` (one creature's mind as a module: the tabduel3 learner with its flat memory, so
many can live at once, nothing shared) and `tabffa.lua` (the match). The user's rules: eight
creatures, the zone, each learning alone, the only score the damage it deals to others. Each
sees, as the sheep saw its wolves, every other fighter: the seven others nearest first, five
numbers each (offset ahead and aside, relative velocity ahead and aside, health), then its own
health, cooldown and potions, the zone (three numbers) and one raycast -- 42 numbers. Move (4),
turn (3), gun (3). Thrown in greedy, mispredict filter, memory of good surprises, 50 ms of
learning each (refits + checks), then 30 matches with learning off.

```
                                        damage dealt per match, per creature (30 check matches)
  8 learners, seed 1                    56, 56, 71, 74, 42, 28, 29, 75      (last standing: 5,0,1,3,0,7,1,13)
  8 learners, seed 2                    71, 57, 67, 66, 59, 47, 38, 43      (0,0,16,6,4,3,0,1)
  the same creatures acting at random   37, 32, 51, 39, 36, 38, 37, 35
  4 scripted + 4 learners, seed 1       scripted 181, 166, 170, 183; learners 50, 67, 42, 59
  4 scripted + 4 learners, seed 2       scripted 190, 175, 174, 195; learners 48, 42, 64, 31
  same, 200 ms of learning each         scripted 164, 164, 156, 184; learners 57, 74, 101, 57
```

Fifty milliseconds buys 18-20 matches here (42 inputs make a refit four times the duel's).
What the eight learn in that: to shoot when something is near and on the ray (every creature
fires 11-84% of ticks, against a scripted bot's aimed-only firing), to drink, and a movement
habit each -- one strafes, one stands, one walks; no two alike, which is the point of learning
alone. Against each other they deal about twice what a random creature deals. Against the
scripted bot -- turn to the nearest, walk to it, shoot when the ray is on it -- they deal a
third of its damage and die sooner: the bot aims, they spray. Four times the budget lifts the
best learner to 101 against the bot's 164-184.

The memory never fires here: with 42 numbers, and the seven others re-sorted nearest first
every tick, no two situations come within the radius (0-3 retests a life at the scaled radius,
0-149 at radius 1.0, and the creature with 149 retests dealt the most, 76, and won 13). The
sorted slots are the trouble: the same fighter jumping from slot two to slot one moves ten
numbers at once. The memory needs a stable description of the world to recognise a situation
again -- the earlier lesson about "what the numbers mean", arriving from the other side.

## 18. Useful senses, structured outputs (`tabffa2.lua`)

The structureless test was to see how far and fast a bare learner goes; this is the same
arena, the same learner (tabmind.lua: linear values, mispredict filter, memory of good
surprises, 50 ms of learning each, alone), with the senses and outputs a designer would give a
creature. Each keeps a **target**. Twenty-two senses: about the target (distance, bearing and
its size, my gun on it, it on me and ready, its health, closing speed, inside the zone, is it
the nearest / weakest / the one on me), the field (enemies alive, nearest distance, weakest
health, anyone on me, a bullet coming, raycast), and me (health, cooldown, potions, inside the
zone, bearing to the centre). Four choices a tick: target (keep | nearest | weakest |
attacker), move (hold | approach | retreat | orbit | centre), aim (none | face), gun (hold |
shoot -- fires only when on the target and ready | drink). The low-level walk/strafe/turn is
derived. The scripted bot is written in the same vocabulary.

```
damage dealt per match (30 check matches)
  8 learners, seed 1                    141, 85, 54, 110, 29, 68, 48, 155     last standing 13,1,2,5,0,2,0,7
  8 learners, seed 2                    82, 56, 91, 101, 37, 138, 88, 94      2,1,2,3,0,9,7,6
  the same, acting at random            76, 64, 97, 82, 86, 81, 76, 80
  4 scripted + 4 learners, seed 1       bots 198, 168, 162, 184; learners 61, 95, 32, 102
  4 scripted + 4 learners, seed 2       bots 211, 172, 170, 190; learners 61, 104, 22, 65
  same, 200 ms each, seed 1             bots 109, 143, 148, 137; learners 107, 117, 53, 185 (18 wins of 30)
```

Against the unstructured arena (§17: learners 28-75, bots 160-195) everything moved. The
memory works again -- 26-259 retests a life, because the senses are stable and a situation can
be recognised. With 50 ms the best learners (141, 155) deal what a scripted bot deals in the
unstructured arena, and one in eight finds "target nearest, face, orbit, shoot" -- the duel's
orbit fighter -- by itself. With 200 ms against four scripted bots, creature 8 deals 185 a match
and is last standing in 18 of 30, above all four bots; two more learners match the bots.

Note what the random baseline says: a creature choosing these outputs at random deals 64-97,
more than most unstructured learners deal after learning, because "face" and "shoot the target"
are half of a good policy on their own. That is what structure in the outputs is worth: the
learner's job shrinks to choosing among things that are each already sensible, and the values it
fits are over senses whose meaning does not shift. The cost of the same learner is unchanged
(learning 50-90 ms a life, thinking 20-30 ms); the difference is entirely what it was given.

Seeds 2 and 3 at 200 ms against the bots: learners 79, 141, 106, 70 against bots 150-182, and 78, 133, 61, 146 (12 and 9 wins) against bots 134-151. On every seed one or two of the four learners fight at the scripted bot's level, one is well below, and the spread is the point: each found its own way there -- orbit and shoot, or hold and shoot the attacker, or chase the weakest.

## 19. One step out: choosing by predicted readings (`POLICY=project` in tabffa2.lua)

Instinct's way, in the structured arena: predict the readings one horizon out for each thing
the creature could do, from models the search finds, and take the option whose projection is
best. Two models, damage dealt and health lost over 24 ticks, found by `findtyped.lua` on a
record of the arena (`LOG=arena`, the ARENA shape: one subject a situation, the 22 senses and
the four picks as discrete channels; 82k situations from 136 matches of four learners against
four scripted bots, 30% of the learners' picks made at random so the record can tell what a
pick causes from what the state causes). The chooser projects the senses for each target pick
(keep, nearest, weakest, attacker: four sense computations), then predicts every combination of
the other picks on them, 120 combinations, and takes the best dealt − λ·taken. Nothing is
learned in the match.

```
                                   search              models (held-out R2)          vs 4 bots: learners' damage / bots'   think
  depth 1, beam 30, 6 rounds        1.1 s per model     dealt 0.27, taken 0.47        66-80 / 156-192 (move and gun uniform)   95 us
  depth 2, beam 100, 6 rounds       2.4 s per model     dealt 0.28, taken 0.47        69-96 / 145-170 (face 100%, shoot 100%)  137 us
  the same at λ = 0.5                                                                 73-90 / 150-167
  for comparison: the linear learner, 50 ms alone                                     61-102 / 162-198
  the linear learner, 200 ms alone                                                    53-185 / 109-184
```

**What the projection found and what it did not.** The first record (learners' own picks,
no randomness) gave models with no pick terms at all: the learners shoot whenever they are on
target, so "on target" explains the damage and the pick adds nothing -- the projector chose
hold-everything and dealt 0. With random picks in the record and depth 2 the dealt model has
`gate(pAim, is(pGun,2))`, and the projector faces and shoots every tick; its aim and gun are
the scripted bot's. Its movement is a coin toss (19-21% on each of five moves) and it never
drinks, because neither model has a term for either: over 24 ticks a move's effect on damage is
small and conditional, and the record of one life does not separate it from the noise at depth
2. The linear learner alone did not find those from its fit either; it found orbit through the
memory's retest of a surprise, which the projector has no equivalent of.

**Cost.** The search is 1-2.5 s per model on this record, 130 µs a think (four sense
computations are 100 of them; the 240 predictions are 40). So the projection is within the
per-tick budget and the search is the once-in-a-life thing, as Instinct has it.

**Where this leaves the two methods.** One step out with searched models reaches the aimed-shot
half of the scripted bot immediately and stably, with no lucky seed -- every projecting creature
shoots when on target from its first tick. What it lacks is the part the memory gave the linear
learner: a way to keep and re-run a rare good event. The combination is the obvious next build:
project one step for the aim and the gun, keep the surprise memory for the moves.

## 20. Adjusting the weights as each outcome arrives (`ONLINE=1`)

The user's proposal after the predictive-coding video: no refit after the match; adjust the
weights continuously. `tabula.lua` `update`: recursive least squares, the batch solution kept
exact one row at a time (about F² multiply-adds a row, F = 23 here), with a forgetting factor
(`FORGET`) that lets old rows fade. `tabmind.lua` `online`: a settled row that passed the
mispredict filter updates the chosen option of every choice at once, memory events with the
same 20× weight. Same arena, four scripted bots and four learners, 200 ms of learning each.

```
                                   learners' damage a match (30 check matches)     bots
  batch refit after each match      107, 117, 53, 185 (18 wins)                    109-148     (§18, seed 1)
  online, seed 1                    59, 135, 88, 127 (7 wins)                       151-175
  online, seed 2                    43, 174, 78, 108 (16 wins)                      142-161
  online, seed 3                    22, 104, 60, 137 (7 wins)                       159-195
  online, 50 ms, seed 1             71, 153, 70, 46 (14 wins)                       153-182
  online, forget 0.999, seed 1      88, 67, 74, 179 (16 wins)                       137-167
  online, forget 0.99, seed 1       102, 18, 86, 4                                  174-224
```

The same picture as batch: on every seed one of the four learners fights at the scripted bot's
level (135-179 a match, 7-16 last-standings of 30) and one is weak. Nothing is lost by never
refitting, and the learning is now spread evenly: 25-30 µs a settled row instead of a spike at
the end of the match, which is what a creature in a running game needs. It costs more compute
per row than the batch (an F×F update against an F-vector accumulation), so 200 ms buys 75-85
matches instead of 150, and the result is the same for it. Forgetting at 0.999 (a memory of
about a thousand rows) is harmless; at 0.99 (a hundred rows) the weights chase the last few
matches and two of the four creatures collapse to 4 and 18 a match.

So the answer to "what if you constantly adjust" is: it works exactly as well, it is what the
budget should have been all along for a live game, and the one setting that matters is how
long it remembers -- a hundred rows is a goldfish, a thousand is fine, forever is fine.

## 21. Predicting everything, online (`tabmind2.lua`, `POLICY=predict`)

From what it senses and what it does (the 22 senses and its picks one-hot, 37 inputs), the
creature predicts every reading one horizon out: damage dealt, health lost, and each of the
22 senses as they will be -- 24 readings. One shared inverse-covariance over the inputs
(recursive least squares), so the F×F part of an update is paid once a row and each reading
adds F. It chooses by projection: the senses it would have with each target it could pick,
every combination of the other picks on them, the best by its preferences (dealt − λ·taken).
Every prediction is zero at birth, so every combination ties and the first picks are random:
that is its exploration, and the only kind it has. The surprise memory is kept. Every settled
row updates (a good surprise three times).

```
                                  learners' damage a match (30 check matches)     bots
  50 ms, seed 1                   78, 0, 3, 0                                     175-242
  200 ms, seed 1                  55, 0, 5, 59                                    165-233
  200 ms, seed 2                  170 (11 wins), 82, 102, 0                       109-158
  200 ms, seed 3                  119, 165 (11 wins), 47, 0                       155-187
  200 ms, λ = 0.5, seed 1         110, 0, 61, 110                                139-199
```

Costs: 7 µs an update for all 24 readings (the shared gain is the point: 24 separate updates
would be 24× that), 50-67 µs a think (four sense computations, 120 combinations × 3 readings).
200 ms of updates is 160-260 matches, more living than any earlier learner got for the money.

What it finds: on seeds 2 and 3 a creature at or above the scripted bot's level, and the orbit
again (seed 2's creature 5: nearest, orbit, face, shoot, 100% of ticks). What it also finds,
on every seed, one or two creatures that deal nothing at all: "approach, face, hold fire" or
"centre, look nowhere, shoot" -- projections that settled early on "shooting costs a health and
pays nothing" from a few unaimed shots, after which the greedy projection never fires again
and nothing contradicts it. The value-per-option learner had the same trap and the same escape
(a remembered surprise); here the memory needs a score of 10 to store an event, and a creature
that never fires never earns one. The predict-everything mind is cheaper per row than the
value learner (7 µs against 25-30) and reaches the bot's level as often, and fails the same way.

## 22. Acquiring inputs, one operator deep (`ACQ_EVERY` in tabmind2.lua)

The user's proposal: the composition search of the earlier work, but for INPUTS -- one
operator over pairs of what the creature already senses (and its picks), keeping only
compositions that correlate with what its damage predictions still get wrong, feeding them
back as inputs whose scale the linear predictor learns like any other. Every 1,500 settled
rows the mind takes a sample of 500 recent rows, computes the residuals of its dealt and
taken predictions, and scores every pair (sense × sense, or pick × sense; never pick × pick)
under seven operators (mul, min, max, sub, gate, gt, absdiff; the ordered ones both ways) by
the larger of the two correlations. A composition is kept only if it beats both its parents'
own correlations by 0.05, is above 0.2, and is not a near-copy (r > 0.95) of one already
acquired; two per search, six in all. A new input grows the shared inverse-covariance by one
row and column. The search is 80-100 ms each time and is charged to the learning budget.

```
predict everything + acquire, 300 ms of learning each, 4 bots + 4 learners
                learners' damage a match (30 check matches)         bots            matches lived
  seed 1        2, 0, 175 (20 wins of 30), 0                        155-186         35
  seed 2        46, 101, 22, 0                                      169-224         39
  seed 3        146 (9 wins), 0, 40, 0                              157-210         33
  (first, looser version: seed 3 creature 5: 237 a match, 14 wins -- the best fighter of the session)
```

What it acquires is often sensible: `gate(targetInZone, gun=shoot)` (0.48), `mul(zoneIn,
gun=shoot)` (0.47), `gt(gun=shoot, myPot)` (0.61), `mul(onTarget, isNearest)` (0.30),
`mul(anyOnMe, move=approach)` (0.58), `sub(myHp, zoneIn)` (0.73) -- conjunctions of a pick
with a condition, exactly the peaks a line cannot hold on its own, found from its own
residuals in a tenth of a second. And the fighters it makes when it works are the best yet:
175 a match with 20 last-standings against four bots, and 237 with 14 in the looser run.

What it does not fix: the 1-in-4 pattern. On every seed one creature reaches or passes the
bots and one or two deal nothing, the same "hold fire" and "retreat and drink" collapses as
§21 -- a creature that stops shooting early acquires inputs about the zone and potions, since
those are where its residuals are, and never an input about shooting, since it never shoots.
Acquisition sharpens a creature that is already on the right track and cannot start one that
is not. And it is expensive for the budget as set: the searches took most of the 300 ms, so
these creatures lived 33-39 matches against 160-260 without it; the search should run on
persistent error, not on a row count.

## 23. The search on persistent error (`ACQ_ON_ERROR=1`)

The trigger is now the one Acquire describes: a decaying share of the damage outcomes the
predictions leave unexplained (squared error over the outcome's own variance, both decayed at
0.995, the variance floored at 4 so a creature whose outcomes never vary has nothing to
explain). When the share has stayed above 0.6 for 400 rows, and 600 rows have passed since
the last search, and the last search brought the share down (or was long enough ago), the
creature searches; otherwise it keeps living. Same arena, four bots and four learners, 300 ms.

```
                 learners' damage a match (30 check matches)          bots          matches lived    searches per creature
  seed 1         240 (15 wins), 0, 0.5, 3.5                           163-219       49               3, 3, 3, 3
  seed 1, before the variance floor: 218 (23 wins), 0, 104, 1.5       105-184       118              3, 2, 3, 3
  seed 2         0.5, 138 (15 wins), 0, 201 (11 wins)                 144-163       74               6, 3, 3, 3
  seed 3         20, 64, 42, 0                                        172-241       83               3, 3, 3, 2
  for comparison, the row-count trigger (§22): 175 / 101 / 146 best per seed, 33-39 matches lived
```

Searching only when the error persists roughly doubles the living for the same budget (49-118
matches against 33-39) and the fighters at the top are the strongest of the session: 240 and
218 a match on seed 1, 201 on seed 2, with 11-23 last-standings of 30 against four scripted
bots that deal 105-240. Two creatures out of twelve beat every bot in their arena.

The share itself is telling: it sits at 0.7-0.9 for most creatures after their searches. The
predictions explain a quarter of the damage variance one horizon out, and the acquired inputs
move that by hundredths. What the searches buy is not a better fit of the whole but the few
conjunctions the choice turns on -- `mul(onTarget, gun=shoot)`, `gate(bearing, gun=shoot)`,
`gt(myPot, gun=hold)` -- and a fighter that already shoots uses them. The 1-in-4 pattern is
unchanged: on every seed one or two creatures deal nothing, and their searches find inputs
about the zone and potions, which is where their residuals are. Nothing in this learner turns
"I am not shooting" into a hypothesis to test; that remains the missing piece, and it is not
one more input.

## 24. Tiers of tiny predictions, compared (`tabmind3.lua`, `POLICY=stack`, `SETS=`)

One mind with switchable tiers, so creatures in the same arena can be given different sets
and face the same bots on the same seed:

    O outcomes   damage dealt / health lost over the horizon from senses + picks (always on)
    M memory     surprising good events, retested
    E effects    per option, the change of every sense one STEP (8 ticks) on; a plan looks
                 two steps ahead (beam of 10 first steps, each extended by its best second)
    U spread     the outcome prediction's uncertainty from the inverse-covariance (diagonal),
                 added to the value at kU = 3: curiosity
    I improving  a bonus (kI = 5) for options whose effect predictions have been getting
                 better lately (fast error average under the slow one)
    C couplings  the next step's change of every sense from the last step's changes, no
                 action in it; its predicted drift is an extra input to O and E; a change
                 beyond its spread counts as a surprise
    T timers     ticks until the zone reaches me; the target's bearing and distance trends

Everything linear and online. Two arenas of four sets against four scripted bots, three
seeds each, 300 ms of learning per creature. Thinking: 90 µs (O M), ~460 µs with effects
(the second step is scored plain), ~570 µs with couplings.

```
damage a match, 30 check matches                     arenas A1 A2 A3 (sets 5-8 in order OM, OMEU, OMEUI, OMEUC)
                                                     arenas B1 B2 B3 (OMEUICT, OMEUC, OMEU, OM)
  set          A1    A2    A3    B1    B2    B3      mean   dealt nothing   best in its arena
  OM            97     0   150   208     0   137      99    2 of 6          3 of 6
  OMEU          23   185   163    96    65    13      91    0 of 6          2 of 6
  OMEUI         56   106     0     -     -     -      54    1 of 3          0 of 3
  OMEUC        179    77    65    23    63   123      88    0 of 6          1 of 6
  OMEUICT        -     -     -    10   178   146     111    0 of 3          1 of 3
  the bots' range in each arena: 86-179, 137-171, 100-157, 141-180, 103-172, 100-134
```

**What curiosity does.** The baseline fell into the deal-nothing collapse in two arenas of six
(retreat forever; drink forever). Of the fifteen creatures with effects and spread, one did
(OMEUI on A3), and the near-misses dealt 10-23 rather than 0. The trap is what the design said
it was: a belief about shooting held with a confidence it had not earned. Value the spread and
it gets tested.

**What curiosity costs.** The top fighter in an arena is the baseline as often as anything
else, and the best numbers of the session are still the baseline's (208 with 21 last-standings
on B1, in an arena where the curious sets dealt 10, 23 and 96). A spread weight of 3 keeps a
creature exploring after it knows; the winners pay for it in shots and steps that were for
finding out. The improvement bonus (I) looks like a loss on three samples; couplings (C) raise
the floor and lower the ceiling; the full set has one creature of each kind.

**Not equal living.** The effects tier updates four option models a row, so at the same 300 ms
the baseline lived 190-330 matches and the effects sets 60-70% of that; the comparison that
follows is at equal matches, with the spread weight lowered.

**At equal living (150 matches each) and spread weight 1**, the same two arenas, three seeds:

```
  set          A1    A2    A3    B1    B2    B3     mean   dealt nothing   best in its arena
  OM            80    15   110   201    29   110     91    0 of 6          2 of 6
  OMEU          90    62   132    36    82    40     74    0 of 6          1 of 6
  OMEUI        131     0    60     -     -     -     64    1 of 3          1 of 3
  OMEUC         29    50    85   127   168    29     81    0 of 6          2 of 6
  OMEUICT        -     -     -    55    41   100     65    0 of 3          0 of 3
```

The picture flattens: no set is ahead, the baseline no longer collapses in these six, the two
best creatures of the round are couplings (127 and 168, with 11 and 14 last-standings) and the
single highest is the baseline (201). The tiers change the shape of the distribution more than
its mean: curiosity cuts the bottom off, the baseline keeps the highest top, couplings put more
creatures in the middle, the improvement bonus has not earned its place. And note the pool:
eight fighters hold 1,440 health, so "damage a match" is a share of what the zone and the costs
leave, and a strong creature in an arena lowers everyone else's number, the bots' included --
which is why the sets are next run one per arena, four copies against the four bots.

## 25. The tiers measured properly: one set per arena, and team battles

The mixed arenas of §24 shared one pool of health between four different sets, so a set's
damage was partly what the others left it. Two cleaner measures, both at equal living (150
matches of training each, spread weight 1):

**One set per arena.** Four copies of one set against the four scripted bots; the score is
the learners' share of the arena's damage and the last-standing count.

```
  set          seed   learners' share   last-standings L / bots   the four, sorted        dealt < 10
  OM             1        13%                8 / 22                 0, 9, 47, 65            2
  OM             2        35%               13 / 16                 1, 77, 106, 140         1
  OM             3        32%               11 / 19                 0, 48, 115, 153         1
  OMEU           1        43%               27 /  3                 57, 65, 128, 149        0
  OMEU           2        25%                7 / 23                 4, 34, 63, 149          1
  OMEU           3        42%               24 /  6                 14, 95, 144, 159        0
  OMEUI          1        42%               24 /  5                 38, 61, 142, 146        0
  OMEUI          2        39%               18 / 12                 36, 76, 95, 193         0
  OMEUI          3        39%               20 / 10                 13, 54, 132, 192        0
  OMEUC          1        35%               22 /  8                 5, 71, 117, 128         1
  OMEUC          2        40%               21 /  8                 21, 98, 112, 154        0
  OMEUC          3        19%                9 / 21                 0, 31, 38, 106          1
  OMEUICT        1        45%               23 /  6                 30, 96, 143, 181        0
  OMEUICT        2        33%               15 / 15                 30, 64, 79, 134         0
  OMEUICT        3        38%               19 / 10                 0, 41, 137, 213         1
```

The baseline's four take 13-35% of the pool and lose the last-standing count every time. The
sets with effects and spread take 33-45% in ten arenas of twelve and win the last-standing
count in nine. The improvement bonus, a loss in the mixed arenas, is the most consistent set
here: twelve creatures, none near zero, 39-42% on every seed. What the mixed arenas measured
was sets taking from each other.

**Team battles** (`TEAMS=1`: team-mates' bullets pass through each other, each team spawns on
its own side of the ring, the match ends when a team is gone; the learners' senses count
enemies only). Four learners of one set against the four bots, 30 check matches:

```
  team of four        seed 1   seed 2   seed 3      (learners' team wins of 30)
  OM                    22        0       10
  OMEU                  14       13        0
  OMEUI                  0        0        0
  OMEUC                  0        0        7
  OMEUICT                5        0        0
  four random creatures  0
```

The team result contradicts the arena result, and the contradiction is the format. A team
match is decided by focus and by the opening: four bots each take their nearest and arrive
together, while a learner that targets the weakest or its attacker splits the team's fire; and
a team spawns together at long range, so the fight opens with a walk into aimed guns, the
situation these creatures handle worst. Inside the winning teams one creature did the work
(OMEU seed 2: 415 a match and 12 last-standings from one creature, 64, 10 and 3 from the
others). The learners have no team senses at all -- no ally, no ally's target, no ally under
fire -- so nothing they could learn would make them a team; what they can be is four
individuals, and four individuals lose to four bots that happen to focus.

**Where the tiers stand, then.** As individuals: effects and spread roughly double the
baseline's share and remove the collapse; the improvement bonus makes that consistent;
couplings and timers add little either way at this budget. As a team: none of it matters
until the creature can see its team.

## 26. A kind for every fighter and a public target: team senses (`TEAMSENSE=1`)

The user's proposal: give each team a type, and make what every bot is looking at a stat.
Seven senses added -- allies alive, the nearest ally's distance, whether that ally targets
what I target, how many enemies look at me, how many at my ally, whether my ally is under
fire, whether my target looks at my ally -- and a fifth target option, **focus**: target what
my nearest ally targets. Every fighter's target is public each tick (the bots look at their
nearest). Same team battles as §25, 150 matches of training, 30 checks, learners' wins of 30:

```
  team of four        seed 1   seed 2   seed 3      without team senses (§25)
  OM                     1       17       24        22, 0, 10
  OMEU                  22       14        0        14, 13, 0
  OMEUI                  4       14        0         0, 0, 0
  OMEUICT                0        7       10         5, 0, 0
```

Five of twelve arenas won or even, against three of twelve before; the improvement set went
from three shutouts to one. **Focus fire was learned**: on seed 1 the curiosity team's creature
6 dealt 229 a match choosing "focus" 85% of the time, its team-mate 7 took the attacker 63%,
and that team won 22 of 30. On seed 3 the everything set's creature 6 dealt 286 with focus at
40%. Nobody told them; the option was there and its value came out ahead.

**What still loses teams** is the same creature every time: the one at zero whose line reads
"retreat 100%". It learned early that retreating avoids damage, and since it never deals any,
nothing in a damage-dealt score argues back. In a free-for-all that creature is merely weak; in
a team it is a missing gun, and four bots against three learners is the whole story of every
0-30. The curiosity tier reduces that collapse and does not remove it, because retreating is not
uncertain -- it is reliably safe. The fix is a preference, not a sense: a creature alive and
dealing nothing while its allies fight should hold that as an error.

## 27. Wanting kills (`KILL`, `TEAMKILL`)

The arena's creatures wanted damage and nothing else: a kill was worth its last fifteen
points, dying cost nothing, and being alive and useless cost nothing. The user's rule: no loss
for dying, but a bonus for kills of one's own and for kills by the team. `ffa.lua` counts
kills per shooter; the score a creature learns on is dealt + 50 × own kills + 25 × each
team-mate's kills. Team senses on, 150 matches of training, 30 checks, learners' wins of 30:

```
  team of four        seed 1   seed 2   seed 3      with team senses, damage only (§26)
  OM                     8       28       22        1, 17, 24
  OMEU                  28        3        0        22, 14, 0
  OMEUI                  6       21        1        4, 14, 0
  OMEUICT                0       10        5        0, 7, 10
```

**What kills buy.** A team that kills now wins big: the baseline's 28 and 22 come from three
creatures each at 175-244 damage and over a kill a match; the curiosity team's 28 from four
at 65-196 with 0.6-1.1 kills each, and roles -- one takes the nearest, one the attacker (91%),
one the ally's target (35%). The bots' damage falls to 36-76 a match because they die before
they get their shots in. A team that finishes targets removes guns, which a damage-only score
could never see.

**What kills do not buy.** The curiosity team's seed 3 is 0-30 to the decimal as before
(0, 0, 19, 2.5), and that is the mechanism, not chance: a kill bonus enters the score only
once a kill happens, so a team that never gets its first kill learns from a score identical to
the damage-only one. The bonus rewards finishing; it does not create the first engagement.
And the idle creature survives it on the winning teams too -- one creature at exactly zero on
every baseline team that won -- because a quarter share of the team's kills arrives whether it
fights or not. Three fighters beat four bots; two do not.

So the kill bonus fixed the second half: a team with fighters now wins by removing guns. The
first half stands, the creature that never engages, and nothing in dealt-plus-kills argues
with it. That wants a preference about being useful while allies fight, or a share of team
kills that a creature only earns by being in the fight.

## 28. Every tier at its own confidence (`CONF`, on by default in tabmind3.lua)

The user's question: why not scale each tier by how confident it is, so the fancy parts stay
quiet until they have earned a say. Every model now keeps a running explained share per
reading (1 − decayed squared error / decayed variance, zero until thirty rows), and:

- a coupling's predicted drift enters the inputs multiplied by that share for the sense;
- a plan's second step counts for γ × the mean confidence of the effect models behind it;
- the improvement bonus is scaled by the same;
- a remembered event's picks are followed with a probability equal to the share of its first
  surprise that its retests kept (always the first time).

The spread is confidence already and is unchanged. Team battles, kills scored, team senses,
150 matches of training, learners' wins of 30:

```
  team of four        seed 1   seed 2   seed 3      ungated (§27)
  OMEU                  27       24        1        28, 3, 0
  OMEUI                 30        2        5         6, 21, 1
  OMEUICT               30       13       28         0, 10, 5
  OM (no tiers to gate; for reference)                8, 28, 22
```

Free-for-all, the gated everything set alone against the bots: shares 42%, 42%, 39% (ungated
45, 33, 38), last-standings 24/6, 20/8, 23/7.

The everything set goes from the weakest team in the table to the strongest: 0, 10, 5 wins to
30, 13, 28. Its tiers were never the problem; they were being listened to before they had been
right about anything. On the first tick every confidence is zero and the creature is the plain
curiosity creature; the lookahead and the drift inputs fade in as the models behind them earn
their share. Curiosity alone gains too (a 3 becomes a 24). The improvement set is the volatile
one, 30-0 on one seed and 2-28 on the next.

**What is left is the same creature as always.** Every losing team here has two or three
creatures at exactly zero -- the curiosity team's seed 3: 0, 0, 250, 0 -- and every winning
team carries one. Gating did not touch that and was not meant to: those creatures are not
listening to an untrustworthy tier, they learned early that not engaging is safe and nothing in
dealt-plus-kills contradicts them. That is the first-engagement problem, and it now stands
alone as the thing between these teams and winning every seed.

## 29. Abilities (`ffa2.lua`, `tabffa3.lua`): styles, and what the score cannot see

The user's rules: one act at a time, each with a commit that cannot be backed out of (moving
and turning continue), then a cooldown -- shoot (0.3 s wind-up), parry (a 0.4 s window, once a
second), melee (30 damage in a short cone), heal self or the nearest ally (20 over a second of
channelling), an area hit (8 to everyone within 6 units), haste (double speed for 3 s), the
potion. Fourteen senses about all of that (what I am committing and how long is left, which
abilities are ready, whether the target is winding up or parrying or in melee reach, enemies in
area range, the weakest ally's health and reach). The scripted bot got the abilities too, with
rules: parry a bullet coming, melee in reach, area a crowd, heal a hurt ally, haste when far,
else shoot when on target. Teams, kills scored, team senses, the gated everything set.

```
                                              team wins of 30        what the learners became
  joint model, 150 matches, seed 1                0                  one orbit-shooter (138, 19 shots a match); three collapsed
  seed 2                                          0                  a turret: hold 99%, shoot 25 + parry 17 a match (36 dealt); rest collapsed
  seed 3                                          0                  a bruiser: parry 22 + melee 7, orbit 62% (2 dealt); rest collapsed
  curiosity weight 3, seed 1                      0                  two orbit-shooters (165, 185) and a SUPPORT: orbit 97%, focus 66%, heal-ally 7 + area 17 a match
  400 matches, seed 1                             0                  orbit-shooter 178 (23 shots); a turret (parry 31, shoot 12); two collapsed
  free-for-all, seed 1                            -                  all four: self-heal 17 a match; one also shoots 41; three deal nothing
  separate heads (fixed), 4 runs                  0                  diffuse: every act 1-20 a match, targets and moves spread, 4-59 dealt
  separate heads, control on the simple arena     5                  (the joint model: 30 on this seed)
  four random creatures                           0
```

**Styles did appear**: the orbit-shooter, the parrying turret, the parry-and-melee bruiser, the
support that orbits its ally's target healing and spraying. Nobody told them any of it. And
every one of them loses, for three reasons that are about the world and the score, not the
learner.

- **The bots parry.** A rule says parry when a bullet is coming, and it fires 4-13 times a
  match; the learners' shots, the one thing they reliably learn, mostly hit a window. No learner
  learned to parry deliberately: parry's payoff is damage not taken, which no score of theirs
  contains, so their parries are scattered.
- **Self-heal is free.** Twenty health per second of channel, no cost, every two seconds. In the
  free-for-all every creature converged on it; the score sees taken go down and nothing else.
  The bot never self-heals, which is why it wins: it spends its commits on shots.
- **Nine acts to explore by chance.** Each is rare and conditional; 200 matches of greedy life
  give a creature a few tries of each in the situations where they pay.

**The separate-heads experiment.** One value per choice over all inputs including the previous
tick's picks (the user's proposal): 21 evaluations a think instead of 450, 0.2 ms against 1.3.
Fixed of a row-input bug (the row carried this tick's picks, not the previous tick's), it stays
diffuse in the abilities arena and gets 5 wins on the simple arena where the joint model gets
30. The joint model stays; the cost was cut instead by pruning combinations the world would
refuse (acts on cooldown, targets that do not exist): 0.55-0.6 ms a think with no change in
what is chosen.

**Speed of learning, honestly.** 150 matches is about 50 minutes of life at ten decisions a
second, for one competent fighter in four. Every decision is one noisy sample of a score 2.4 s
late; a linear value over sixty inputs needs hundreds of rows per option; the acts that pay are
rare. What would make it fast is what makes animals fast: a born opening position from a creature
that already learned, and learning from what the seven others do. Neither is built.

**With pruning** (the joint model scoring only the combinations the world would accept: acts
off cooldown and not mid-commit, potions left, an ally in heal reach, targets that exist --
0.55-0.6 ms a think), the creatures use three to five times as many acts a match, because no
tick is spent asking for something on cooldown, and the styles fill out. Three seeds, 200
matches, bots that parry; every team still 0-30:

```
  seed 1  creature 8: shoot 33, parry 33, area 16, self-heal 14, haste 8; orbit 98%, nearest   -- 123 dealt, lives 53 s
          creature 7: parry 71, melee 16; orbit / centre                                        -- a wall, 16 dealt
          creature 5: melee 47, self-heal 28, area 15, haste 12; hold 51%                       -- swings at air, 5 dealt
  seed 2  creature 5: shoot 33, self-heal 17, haste 9; orbit 100%, targets by turns             -- 127 dealt, lives 53 s
          creature 8: shoot 51, melee 36, parry 31, area 25, self-heal 20, haste 17; orbit 66%  -- uses everything, 32 dealt
          creature 7: melee 36, self-heal 25, parry 16; hold / orbit                            -- 0 dealt
  seed 3  creature 7: shoot 34, melee 15, self-heal 17, area 16; orbit 99%, the weakest         -- 166 dealt, lives 46 s
          creature 8: parry 31, melee 25, haste 19; centre / orbit                              -- a mobile brawler, 16 dealt
```

Matches now run 30-50 s, because everyone heals and parries. **Against bots that do not parry**
(seed 1) the two orbit-shooters deal 226 and 257 with 20-plus shots and half a kill each, and
the team still loses 0-30: creature 7 retreats and melees the air, creature 8 self-heals and
holds, and two fighters do not beat four bots that heal each other. So the bots' parry was not
the wall on its own. Nine arenas, one conclusion: the abilities produced the styles -- the
orbit-shooter, the wall, the brawler, the all-rounder, the support -- and the same half-a-team-
never-engages decides every match. What the abilities added is a wider space of ways not to
engage: self-heal, parry, retreat-and-melee, each a safe act a creature can settle in, and a
score of dealt-plus-kills argues with none of them.

The last of the set, bots without parry, seed 2: 4 wins of 30, and the two strongest creatures of the arena -- creature 7: shoot 28, melee 42, self-heal 16, area 6, haste 6 a match, orbit 100%, 337 dealt, alive 48 s; creature 8: shoot 33, parry 45, area 25, self-heal 14, haste 8, orbit 99%, 385 dealt, alive 51 s. Their two team-mates parried 37-39 times a match and dealt 0 and 49. Two all-rounders that outfight the bots one on one, and a team that still loses, for the same reason.

## 30. An extreme desire not to see team-mates die (`ALLYDEATH`, `NEARDEATH`)

The user's rule for the first-engagement problem: make a team-mate's death cost the creature a
great deal. `ALLYDEATH=200` takes 200 off the score in every row whose horizon covers the
death (a kill is 50, a match's damage 100-300). `NEARDEATH=1` charges the full amount only
when the creature was within heal reach (12 units) of the one who died, and an eighth
otherwise -- the cost pointed at "you could have helped" rather than at the fight. The
abilities arena, pruned joint model, 200 matches, bots that parry unless noted.

```
                                        wins   the four                                   heal-ally a match
  flat 200, seed 1                        0    24, 7, 38, 14 dealt; alive 7-16 s           0.1-5.6
  flat 200, seed 2                        0    9, 72, 35, 9                                 0-0.2
  flat 200, seed 3                        0    41, 7, 5, 11                                 0-2.3
  flat 200, bots without parry, seed 2    0    17, 40, 65, 55  (was 337 and 385 without)    0-4.2
  near 200, seed 1                        0    37, 28, 148, 91; the fighter alive 53 s      0.3-1.7
  near 200, seed 2                        0    59, 3, 10, 74                                0
  near 200, bots without parry, seed 2    0    14, 18, 16, 384; the fighter alive 57 s      0
```

**The flat cost made every creature worse**, including at the thing it was meant to protect:
four arenas, nobody above 72, survival down to 7-16 s, heal-ally never above 6 a match. At 200
the deaths are the largest thing in every score by far, they come in bursts in the fight phase,
and they land in every row of the window; the values become a model of when allies die, with
the creature's own outcomes as small print. And what precedes an ally's death is the fight
itself, the same for every position the creature can take, so nothing it does moves the
prediction and the values flatten toward "everything is bad here".

**The near cost undid the damage and produced no protector.** With the cost pointed at
proximity the fighters came back -- 148 and 384 dealt, alive 53-57 s -- but heal-ally stayed
at 0-1.7 a match. What rose was parry, 19-50 a match: the creatures learned to stay alive and
armed beside a dying ally, which is what reduces the deaths in their rows, and that is
indistinguishable from what kills already taught. A heal of 20 over a second does not change
a death that three guns deliver at 15 a hit, and there is no shield or taunt, so the only
means of protection is fighting, and the desire added nothing to it.

**On the confound.** The user asked whether the learner subtracts what would happen anyway
from what the action adds. It does, by regression: the senses carry the do-nothing prediction,
the pick flags carry the difference, and the choice compares differences only. The limit is
that the baseline can only contain what the senses can say, and an ally's death in the next
2.4 s is barely predictable from them; the leftover then lands on whatever is correlated with
it, and engagement is. A cloned rollout would give a baseline the senses cannot; the cheap
route is senses that predict the death -- how many guns are on the ally, and for how long --
which the creature does not have. The near-death cost worked from the other side, making the
cost something ally-distance and ally-under-fire do predict, and that is why it stopped
hurting.

So: a desire is only as strong as its means. To make "do not let them die" teach something,
the world needs an act that protects an ally more than a 20-point heal does, or the creature
needs a baseline that knows a death is coming before its flags are asked to explain it.

Flat 50, seed 1: 0 wins; 44, 163, 59, 103 dealt; heal-ally 0 -- the milder cost neither wrecks nor protects.

## 31. Predicting when things happen (`H` in tabmind3.lua), and the input tax

The user's proposal: predict time until events. Five events -- I take damage, my target takes
damage, my target dies, my nearest ally dies, I die -- each with three readings. First as
buckets (within 3, 8, 24 ticks); then, because three buckets are coarse, as the next-tick
hazard rate, the time until (capped at the horizon), and "within 8", plus a decaying trace per
event as an input (how recently it happened). All learned in the shared-gain update when a row
settles, when everything within the horizon is known. The predictions, at their confidence,
enter the outcome model as inputs.

**They learn.** After 30 matches "I get hurt within 0.3 s" is explained 27-51% and "an ally
dies within 2.4 s" 24-58%; the continuous "when" for ally death reaches 0.29-0.66 in 200
matches. Those are exactly the two predictions whose absence let the ally-death cost land on the
engagement flags (§30).

**They made the creatures fight worse.** Abilities arena, 200 matches, bots that parry, damage
of the four (seed 1 without the tier: 123, 16, 5, 25):

```
                                             the four                     wins
  buckets, no cost                            33, 29, 4, 1                 0
  buckets, near death 200, seeds 1 / 2        38, 0, 44, 11 / 57, 1, 5, 20 0, 0   (without the tier: 37, 28, 148, 91 / 59, 3, 10, 74)
  buckets, flat death 200                     42, 23, 50, 22               0      (without: 24, 7, 38, 14)
  buckets, bots without parry, seed 2         406, 25, 86, 22              0      (the strongest creature yet; without: 384, 14, 18, 16)
  continuous + traces, no cost                9, 2, 2, 23                  0
  continuous, near death 200, seeds 1 / 2     31, 48, 2, 5 / 2, 11, 37, 9  0, 0
  continuous, tightened prior, no cost        35, 1, 57, 63                0
  continuous, tightened prior, near death     64, 50, 8, 10                0
```

**The input tax, named.** This is the third time in the session that a tier which learned what
it was meant to learn made the creature worse: couplings before their gating (§24), the raw
everything set (§28), and now hazards. The mechanism is the same each time. Fifteen more inputs
into the outcome model are fifteen more weights to pin from the same 200 matches of rows, and
they enter the decision as soon as the prediction behind them is confident, which for "hurt"
is a few matches -- long before the outcome model has learned what to do with them. Every input
in a decision before its own weight has settled is a source of wrong values. Gating by the
prediction's confidence is the wrong gate for that; the right one is one level down: an input
speaks in the decision only once its weight in the outcome model is stable. The cheap form is a
tighter prior toward zero on the tier inputs (`EXTRA_RIDGE=20`), and it recovers most of the
loss (156 total damage against 169 without the tier) and not more.

**Where they would pay.** The 2.4-second outcome value already contains what the creature can
use a hazard for while the score is damage and kills. A prediction of "I die within a second"
or "my ally dies within two" earns its place only when something wants it: a preference over
the event rather than a cost smeared through the score. That is the occupancy-and-preferences
design, and the hazards are readings for it. As inputs to a damage value they are a tax.

## 32. Occupancy and preferences, trusted hazards, acquisition with operator priors

Built together (tabmind3.lua, tabffa3.lua): the outcome model predicts seven *readings* over
the horizon (dealt, taken, kills, team kills, ally deaths, my death, ally healing), the value is
a preference-weighted sum of the readings, and `setPreferences` changes the weights without
retraining (`PREF` for the life, `PREF_CHECK` for the check phase). The hazard tier stays but
its predictions enter the decision only above 0.5 explained (`HAZ_TRUST`). The acquisition
tier searches on persistent value error, weighting operators and senses by how often they
were chosen before (priors are reported). Abilities arena, bots that parry, 200 matches,
30 check matches. Training is deterministic for a seed, so the preference-switch runs use the
very same trained creatures as the base run of that seed.

```
                                                          the four                   total   think
  base OMEUICT, seed 1 / 2 / 3         154, 122, 114, 46 / 121, 105, 69, 63 / 97, 17, 56, 42   436 / 358 / 212   0.8-0.9 ms
  full OMEUICTHA, seed 1 / 2 / 3       49, 60, 19, 14 / 168, 58, 123, 126 / 35, 3, 26, 27      142 / 475 / 91    1.7-1.9 ms
  hazards only OMEUICTH, seed 1        20, 39, 48, 46                                           153               1.7-1.9 ms
  acquisition only OMEUICTA, seed 1    76, 56, 79, 54                                           265               1.0-1.1 ms
  (§31, same seeds, old value)         5, 25, 16, 123 / 37, 28, 148, 91                         169 / 304
```

**The occupancy value is not worse, and on two seeds better,** than the old single score
(436 and 358 against 169 and 304). Same information, but the readings are learned as seven
targets and summed afterwards, so each weight is pinned by its own reading's variance rather
than by the sum's. One caveat: the first parity run had a death counted as 100 more "taken"
and scored 152; a death is its own reading now, with weight 0 by default.

**Preferences switch behaviour without retraining.** Seed 1, the same trained creatures:

```
                                      the four              total   survived (s)         what changed
  base                                154, 122, 114, 46     436     30, 26, 23, 10
  died = -100 at check                132, 149, 69, 56      406     31, 51, 24, 20       self-heals 15 and 9 a match, lives longer, damage kept
  allyDeaths = -200 at check          92, 65, 57, 24        238     27, 21, 14, 5        ally heals appear (3 a match), creature 8 melees and aoes in the crowd
```

Fear of death is the first cost in the session that made creatures live longer without making
them stop fighting (§30 tried it as a score term and got nothing). It works because "I die
within 2.4 s" is now an outcome reading the model has been predicting all along; the
preference only changes what the creature does with it. The ally-death switch is weaker: ally
death depends on things the creature does not see well, so the reading is noisier and the
switch mostly costs damage. Under the full creature the same switches collapsed everything
(3.5, 7.5, 0, 6): more inputs, worse readings, preference times noise.

**Hazards still tax even when trusted.** At 0.5 the gate lets in "hurt when" and "die when"
(0.45-0.78 explained on some creatures, 0.00 on others of the same seed) and the creature is
worse in two seeds of three. The traces and the per-candidate hazard predictions also double
the think cost. As predicted in §31, the hazards are readings for a preference, not inputs for
a value; with `died` as an outcome reading there is nothing left for the death hazard to add.

**Acquisition with priors finds little.** Searches are cheap (6-40 a life, 0.1-0.8 s total)
and they do find inputs -- but at correlations of 0.2-0.4 with the value residual, mostly pairing
a tier input with a sense (`gt(x90, lookingAtMe)`, `min(isWeakest, nearestDist)`,
`gate(move=centre, enemiesInAoe)`). The priors barely move (1.0-1.5): no operator wins often
enough to be preferred. Each acquired input is one more weight to pin, and the set costs 170 of
436 on seed 1. The residual of a 2.4-second damage value in a fight is mostly things no pair of
senses explains; the search would need the *readings'* residuals (which reading is wrong) and
the couplings' (which sense moves unexpectedly) to find structure, not the summed value's.

**Keep:** readings + preferences (the value refactor), `died` as a reading, the trust gate.
**Off by default:** H and A. The next honest test of acquisition is on a reading's residual.

**Addendum: acquisition over three seeds, and on a reading's residual.** The one-seed verdict
above was wrong. With the search chasing the worst-explained reading's residual instead of the
summed value's (`ACQ_TARGET=reading`, now the default), and with two more seeds for the value
version:

```
                                       seed 1              seed 2               seed 3               total of three
  base OMEUICT                         154, 122, 114, 46   121, 105, 69, 63     97, 17, 56, 42       1006
  + acquisition, value residual        76, 56, 79, 54      150, 131, 121, 45    151, 134, 83, 18     1098
  + acquisition, reading residual      106, 58, 26, 30     151, 66, 178, 84     122, 79, 167, 129    1196
```

Seed 1 loses either way, seeds 2 and 3 gain, and the reading version gains most: the
178-damage and 167-damage creatures are the strongest single creatures so far against bots that
parry. The acquired inputs also read better when they are for a reading: "taken:
min(zoneIn, act=healSelf)" and "taken: gt(act=healSelf, zoneIn)" (healing inside the zone costs
health), "taken: sub(nearestDist, lookingAtMe)" (someone close and looking at me), "dealt:
gate(onTarget, targetInMelee)", "dealt: min(aim=face, ray)". The value-residual search mostly
found zone-and-something pairs. Searches cost 0.1-0.4 s over a whole life. Kept on; the seed
variance is still bigger than the effect and three seeds is the least that says anything.

## 33. One on one from birth: how long until it wins

The strongest set (OMEUICT), one creature against one scripted bot, greedy from zero, 400
training matches with a progress line every 20 (`PROGRESS=20`, `N=2 SCRIPTED=1`), then 30
check matches.

```
                                first win        best 20-block   check (30)        check damage, creature vs bot
  bot that parries, seed 3      match 1-20       9 of 20         12 - 17 - 1       127 vs 75
  bot that parries, seed 2      match 61-80      2 of 20         0 - 30            1.5 vs 52   (collapsed at the end: shoots and parries at nothing)
  bot that parries, seed 1      match 81-100     2 of 20         0 - 30            43 vs 97
  bot that never parries        match 1-20 (11)  15 of 20        13 - 17           140 vs 90
```

Wins arrive within 20 to 100 matches and then stop improving. The seed 3 creature out-damages
the bot in every check match and still loses more than it wins: the bot drinks at the right
moment and spends less on moving, and the creature dies to the accumulated small costs (a
health per shot, a health per second of moving, the zone) on top of the bot's shots. The no-parry
curve peaks at match 120 and drifts down to about a third while damage dealt stays at 130-150,
so the creature keeps its aim and loses its thrift: the online forgetting drifts the
taken-damage side of the value while the dealt side stays put. That, and not hitting, is the
thing to fix for a one-on-one winner.

**Both residuals at once (`ACQ_TARGET=both`).** Each search scores every candidate against the
value's residual and the worst reading's, keeps the better correlation, and triggers when either
is persistently unexplained.

```
                              seed 1             seed 2              seed 3             total
  both                        97, 48, 65, 72     114, 167, 63, 1     97, 49, 73, 32     878
  reading only (above)        106, 58, 26, 30    151, 66, 178, 84    122, 79, 167, 129  1196
  value only                  76, 56, 79, 54     150, 131, 121, 45   151, 134, 83, 18   1098
  none                        154, 122, 114, 46  121, 105, 69, 63    97, 17, 56, 42     1006
```

Worse than either alone. Two triggers fire more often, and two residuals give more candidates a
way over the 0.2 bar, so every creature reached the six-input cap early; the extra inputs are the
tax again. The reading target stays the default. The general rule holds: the search should be
starved, not fed.

## 34. Revelation against spread

`R` (tabmind3.lua): the option's bonus is the information one more row with its features would
give the outcome model, 0.5 * log(1 + phi' P phi / noise), noise being the value's residual
variance. Noisy outcomes earn less, an already-wide corner is not worth ten times a narrow one.
REV=full uses the whole covariance (F^2 a candidate, ~1.5x the think cost), REV=diag its
diagonal. kR=2, against spread at kU=1, and against neither. Abilities arena, bots that parry,
200 matches, three seeds (the twelve runs shared one machine, so the think times are inflated).

```
                          seed 1              seed 2               seed 3               total
  spread (U)              154, 122, 114, 46   121, 105, 69, 63     97, 17, 56, 42       1006
  revelation, full (R)    18, 124, 39, 18     161, 79, 61, 69      48, 5, 70, 133       824
  revelation, diagonal    5, 10, 12, 98       61, 111, 1, 28       84, 185, 109, 152    854
  neither                 74, 0, 123, 7       115, 76, 93, 121     104, 133, 141, 51    1036
```

Neither bonus matters at these gains: spread and no bonus are within noise of each other, and
revelation is a little worse in total while producing one of the strongest single creatures
(185). The exploration that makes these creatures is the random tie-breaking at birth and the
memory's retests, not the bonus term; the bonuses only move ties late in life, when they are
tenths of a hit-point against gaps of whole ones. Revelation stays available (set letter R), off
by default, and the fair test of it would be a world with an informative-but-unrewarding option,
which this arena does not have.

## 35. The runner: what a frozen creature cannot answer, and a learning one can

The user played the page (fight2.html, the frozen check-phase creature) and beat every creature
by running in a circle: they chased, spent themselves, and died to the zone. Reproduced with a
scripted runner (`BOT=runner`: strafes around its nearest enemy facing it, stays inside the
zone, never acts). One on one, OMEUICT, `N=2 SCRIPTED=1`:

```
                                                          first 20 matches vs runner   after 300     check (30)
  trained 300 vs the fighter bot, FROZEN, checked vs runner            --                 --         1 - 29   (dies to the zone at 52 s; 30 shots, 35 parries, 33 melees a match into air)
  learning from birth vs the runner                              16 - 4                  20 - 0      30 - 0   (14 shots, 2 potions, 86 damage, kills every match)
  trained 300 vs the fighter, then LEARNING vs the runner        19 - 1                  14 - 6      27 - 3
```

The frozen creature has no answer because its value is linear in senses plus one flag per
option: "centre" is worth a constant whatever the zone does, and the one-step projection is the
only place "inward when the zone is close" can live. The same creature allowed to keep learning
answers the runner inside its first twenty matches -- mostly by standing still while the runner
bleeds a health point a second moving -- and then drifts back down to 12-14 wins in 20 as it
learns to shoot more and chase, which costs it the zone again. From birth against the runner it
is perfect from match 21 and stays there.

Two conclusions. The check phase (and the page) freezing the creature is the wrong test of a
system whose point is online learning: the page should learn while you play. And the
representation gap is real: a per-option weight block over the senses, or acquisition biased to
sense-times-pick pairs, is what would let "go inward when the zone is close" be learned as a
weight rather than found by projection.

## 36. Learning in the page, and why a well-trained creature could not adapt

The page (fight2.html) now runs the whole mind: think, note, settle, the outcome, effects and
coupling models updated by the same recursive least squares as the Lua, the memory of surprises
stored and retested, all at about 1 ms a tick. Mouse aim uses the 400 ms look mechanic. Test:
a scripted runner in place of the player (orbit the creature facing it, stay inside the zone,
never act), the exported creature 7 of seed 2 (eight-fighter training, 76,000 rows), twelve
matches in a row, learning kept between them.

```
                                                   matches until it hits    won of 12    where it ends
  learning off                                     never (0 damage in 8)    0            radius 26-40, dies to the zone
  learning on, no forgetting                       never (0 damage in 8)    0            same
  learning on, forgetting 0.98, unbounded          3                        5            centre -- and the covariance trace reaches 1e51
  learning on, forgetting 0.98, trace clamped      never                    0            same as frozen
  learning on, forgetting 0.98, each variance capped at 100    3            6            radius 1-7, 42-61 damage a match
```

**Why plain online learning did nothing.** After 76,000 rows the inverse covariance is tiny in
every direction the creature has used, so a new row moves the weights by almost nothing, and the
spread bonus on the options it stopped taking is zero, so it never tries them. It orbits the
runner into the zone and dies, match after match, learning the same lesson at a gain of one part
in 76,000. In the Lua (§35) the switch worked because that creature had 15,000 rows from a
one-on-one life; the exported one is simply older.

**Forgetting is the fix, with a cap.** A forgetting factor lets the covariance regrow, so recent
rows count and unused options regain uncertainty; but unexcited directions then grow without
bound (the trace explosion), and a uniform trace clamp kills the effect because it shrinks the
excited directions too. Capping each feature's own variance at 100 by scaling its row and
column keeps the matrix positive and the effect intact: the creature stops orbiting within three
matches, moves to the centre, and starts hitting. `FORGET=0.98 PCAP=100` in tabmind3.lua, and
the page's play-time default. What this costs in the arena is being measured.

**What forgetting costs in training.** The same forgetting applied from birth (`FORGET`,
symmetrising the covariance each row, which it needs or a third of the rows break):

```
                                          arena, seed 2 (four creatures)   runner switch at 300: block right after, check
  no forgetting                           151, 66, 178, 84   (479)         19-1, 27-3
  0.98 every row                          19, 4, 10, 36      (69)          1-19 ... 20-0 after 140 matches, 30-0
  0.995 every row                         32, 30, 3, 33      (98)          --
  0.99 only at a break*                   31, 56, 51, 14     (152)         20-0, 28-2
  0.995 only at a break*                  43, 16, 57, 38     (154)         3-16, 30-0
```

*a break: the value's recent error (decay 0.95) above its long-run error (0.995); the
forgetting scales with the excess, up to the given rate.

Forgetting throws away exactly the slowly-pinned weights that make a fighter, and in training
the errors fluctuate enough that even the break-gated version fires a lot. A young creature
(15,000 rows) adapts to a new opponent without any forgetting; an old one (76,000 rows) cannot
without it. So: no forgetting in training (the default), break-gated forgetting at 0.98 in the
page, where the creature arrives old. The proper version of this is a covariance that stops
shrinking past some age rather than one that is later inflated -- a floor on uncertainty, which
is what a bounded-gain learner is -- and that is the next thing to try if creatures are to live
long in a game.

## 37. The search for a breakthrough: waves of ideas, three seeds each

The user asked for every idea to be tested and the testing to continue until something moves.
The yardstick is the current default (OMEUICTA, acquisition on a reading's residual):
220, 479, 497 = 1196 total damage of the four creatures over seeds 1-3, and its think cost.
Runs in a wave share the machine, so think costs compare within a wave only.

**Wave 1-2.**

```
                                         seed 1   seed 2   seed 3   total   think    verdict
  default                                220      479      497      1196    ~1.1 ms
  no spread, no improvement (OMECTA)     212      553      375      1140    0.9 ms   same performance, cheaper: DROP U AND I
  no effects either (OMCTA)              92       208      340      640     0.5 ms   the one-step projection is worth half the damage
  option blocks over 12 senses (BLOCK)   crashed (fixed) -- rerun in wave 3
  acquisition only on sense x pick       257      301      667      1225    ~1.1 ms  same total; seed 3 is the best four ever (151, 202, 120, 193)
  variance floor 0.01 (PFLOOR)           197      123      170      490              a floor that high keeps the gain noisy: DROP
  memory shared between team-mates       219      362      488      1069             nothing
```

The old-creature test in Lua did not reproduce the page's problem: a creature trained 900
matches one on one (about 45,000 rows) still answered the runner immediately, 49-1 in the first
fifty and 30-0 at the check, with no floor and no forgetting. So "too old to adapt" is about the
eight-fighter creature at 76,000 rows, or about the four-on-four regime, not age as such.

**Wave 3.**

```
                                                    seed 1   seed 2   seed 3   total   think     verdict
  option blocks over 12 senses (BLOCK=1)            507      295      542      1344    1.6 ms    +12%; the evenest four yet on seed 3 (147, 144, 138, 114)
  3% random combinations in training (EPS)          244      466      466      1176              nothing: the ties and the memory already explore
  bigger memory, lower bars (400 / 5 / 3)           359      18       440      817               worse; seed 2 collapsed
  aim x act and move x act one-hots (PICKPAIRS)     142      444      296      882               worse: 63 more inputs to pin
  self-play, checked against bots it never met      269      258      485      1012              nearly as good against a stranger: robust, not stronger
```

**Wave 4: the projection.** Base for this wave is OMECTA (spread and improvement dropped),
212, 553, 375 = 1140.

```
                                          seed 1   seed 2   seed 3   total   verdict
  effects step 4 ticks (STEP=4)           453      483      433      1369    +20%, and even across creatures
  effects step 12 ticks (STEP=12)         467      702      426      1595    +40%; seed 2's four: 184, 160, 165, 194, and 11 TEAM WINS of 30, the first real team wins
  lookahead weight 1.0 (GAMMA)            157      315      243      715     worse
  beam 30 second steps (BEAM)             285      166      328      779     worse
  horizon 12 ticks                        337      366      312      1015    worse
  horizon 48 ticks                        181      397      119      697     worse
```

The effects models predict how the senses change over STEP ticks under an option, and the
lookahead scores the projected senses. Eight ticks was a guess in §24 and was never tested; the
gain from twelve is the largest single change since the memory of surprises. The same setting
does nothing one on one (3-27, 0-30, 0-30): the duel's failure is thrift and the zone, not the
projection.

**Wave 5: bracketing the step.**

```
  STEP     4      8      12     16     20     24
  total    1369   1140   1595   866    1404   556      (three seeds each, OMECTA)
```

Not monotone: 16 is bad between two good neighbours, which says the swing between neighbouring
settings is mostly seed noise. Step 12 with option blocks: 190, 370, 404 = 964, worse than step
12 alone. The best-of-all-combinations second step (PLAN2=max) costs 8 ms a think and scored
161 on the one seed that finished. Five more seeds each of step 8 and step 12 are running to
settle whether the step is real.

**Duels with a cost on dying (preference, not a score term).** One on one, OMECTA, 300
matches, check of 30: `died=-100` gives 0-30, 15-15, 13-17 against 0-30, 0-30, 12-17 without --
the first near-even duels -- with 95-99 damage a match and lives of 32-69 s. `taken=-2` gives
1-29, 0-30, 0-30 (too cautious: 0-38 damage), and the two together 0-30, 0-30, 1-29.

**The step is real.** Eight seeds each (training is deterministic per seed, so these are
comparable runs):

```
  seed        1     2     3     4     5     6     7     8     mean
  STEP=8      212   553   375   96    253   289   216   500   312
  STEP=12     467   702   426   513   302   503   323   129   421    better on 6 of 8, +35%
```

STEP=12 is now the default. Steps 10 and 14 on three seeds (905, 784) are within the noise
band around it.

**How a creature collapses.** Per-creature training curves on a run whose four ended at
0, 2, 14, 2: the first twenty matches already read 1, 12, 17, 10 damage a match. A creature that
collapses never got off the ground -- no early hit, no surprise to remember, a value that
learned engaging costs health and gives nothing, and no exploration left to find otherwise.
It is not a later loss of skill. So the cure is at birth: optimism, novelty, or a warm-up of
random play (wave 7 and 8).

**Wave 7: against the collapse (STEP=8 base, 1140).**

```
                                          seed 1   seed 2   seed 3   total   verdict
  spread bonus at gain 5 (KU=5)           430      321      573      1324    +16%; one creature at 234, one at 0
  spread bonus at gain 15                 242      372      510      1124    nothing
  per-option novelty bonus 2 (UCB=2)      398      73       148      619     worse
  per-option novelty bonus 6 (UCB=6)      622      386      132      1140    same total; seed 1's four 170, 158, 116, 177 with 8 team wins
```

None of them stops a creature collapsing (zeros remain in every row), and none is a clean gain.

**Wave 8: a random warm-up at birth (WARMUP=10: the first ten matches played at random, then
greedy). STEP=12 base.**

```
                     seed 1          seed 2          seed 3          seed 8 (collapsed before)   collapse config (was 0, 2, 14, 2)
  STEP=12            467             702             426             129 (2, 8, 110, 9)         18
  + WARMUP=10        579 (8 wins)    398             503             575 (144, 160, 130, 141)   495 (141, 150, 134, 70)
```

No creature collapsed in any of the five runs (the least is 29); the two runs that had collapsed
are rescued outright, and seed 1 gives 8 team wins. Ten matches of random play at birth is the
cure for the never-got-off-the-ground creature: every option gets tried against the world before
the value has an opinion, so the early rows contain hits. Mean over the four seeds 514 against
431, and the spread between seeds falls from 129-702 to 398-579. More seeds and other warm-up
lengths are running.

**Wave 9: optimism and rebirth (STEP=12 base).**

```
                                              seed 1   seed 2   seed 3   seed 8   mean   team wins
  STEP=12                                     467      702      426      129      431    0, 11, 0, 0
  optimistic prior on attacks (OPTIMISM=5)    344      482      321      171      330    worse
  rebirth for a creature under a fifth of     545      634      467      656      576    5, 6, 0, 3
    its best team-mate over 20 matches
    (RESTART=20; 6, 4, 1, 11 rebirths)
```

Rebirth resets the outcome model's weights and covariance and nothing else: the memory, the
effects and coupling models stay. A creature reborn a few matches in gets a second chance at its
first hit with everything it learned about the world intact, and the runs show it: no creature
under 68, the best four yet on seed 8 (145, 149, 189, 174), and team wins on three seeds of
four. The optimistic prior on the attacking flags, by contrast, is worse on every seed: a prior
is a fixed opinion, a rebirth is a fresh one.

**Wave 10-11: combinations and more seeds.** Spread at gain 5 on top of step 12: 590, 241,
386 = 1217; novelty bonus 6 on top of step 12: 280, 329, 545 = 1154; both below step 12 alone
(1595). The exploration bonuses are dropped for good. Warm-up on more seeds: seed 5 402, seed
6 397, seed 7 139 (49, 69, 20, 1) -- so ten random matches do not prevent every collapse, they
make it rarer. Warm-up of 20 matches: 531, 383, 527 = 1441 against 1480 for ten.

**Wave 12: the warm-up in the duel.** One on one against the parrying bot, 300 matches, the
standing failure of the session (best before: 12-17 on one seed, 0-30 on the rest):

```
                          training blocks of 50 (wins)      check (30)   damage, creature vs bot
  WARMUP=10, seed 1       3, 19, 17, 13, 13, 27             22 - 8       132 vs 15   (29 shots, 6 self-heals; takes 23 a match from 30 bot shots)
  WARMUP=10, seed 2       --                                9 - 21
  WARMUP=10, seed 3       --                                0 - 30
  WARMUP=10 + died=-100   --                                0, 0, 0
```

The first duel the creature wins outright, 22-8, and it wins by not being hit: the bot fires
thirty shots a match and lands one. Still one seed in three. (Two long runs earlier were cut
short by the 100 s learning-time budget under machine load; the budget is now effectively off.)

**Wave 12: warm-up and rebirth together (STEP=12).**

```
                                 seed 1            seed 2            seed 3            total   team wins
  STEP=12 alone                  467               702               426               1595    0, 11, 0
  + WARMUP=10                    579               398               503               1480    8, 1, 1
  + RESTART=20                   545               634               467               1646    5, 6, 0
  + both                         583 (137-176)     516 (103-146)     650 (140-187)     1749    5, 1, 8
```

Both together is the best three-seed total of the session, and the evenest: the weakest
creature of the twelve is 103, where every earlier configuration had one under 30. Against the
session-start default (OMEUICT, 1006) that is +74%, at the same think cost, from three changes:
a 12-tick effects step, ten random matches at birth, and a rebirth for a creature that falls
behind its team. All three are now defaults (`STEP=12 WARMUP=10 RESTART=20`).

Duels with the rebirth floor (30 a match): 0-30, 0-30, 14-16; with the death cost as well:
13-17, 0-30, 13-17. Warm-up duels on more seeds: 1-29 and 11-19 so far.

**Duels with the warm-up, eight seeds:** check wins of 30: 22, 9, 0, 21, 1, 0, 4, 11 (mean 8.5,
against 0, 0, 12 before). Two seeds in eight now beat the bot outright, and both do it the same
way: 130-140 damage a match while taking about 20 from thirty shots.

**Rebirth over eight seeds (STEP=12, no warm-up):**

```
  seed        1     2     3     4     5     6     7     8     mean   min creature
  STEP=8      212   553   375   96    253   289   216   500   312    0
  STEP=12     467   702   426   513   302   503   323   129   421    0
  + RESTART   545   634   467   574   622   644   538   656   585    68
```

Better than step 12 alone on seven seeds of eight, +39% on the mean, and the spread between
seeds falls from 129-702 to 467-656. Against the step-8 base it is +88%. The rebirth is doing
what the whole exploration apparatus (spread, novelty, improvement, random play) could not: it
gives a creature that started badly a second first impression, with its world models intact.

**Warm-up and rebirth together, eight seeds:** 583, 516, 650, 575, 402, 573, 353, 575 = mean
528, against 585 for rebirth alone and 446 for warm-up alone. Together is worse than rebirth
alone: the warm-up lifts the weak creatures just above the rebirth threshold (0 rebirths on
three of the five new seeds) and they stay mediocre (353, 402). The arena default is therefore
rebirth without warm-up; the warm-up stays on for a lone creature, which has no team to be
measured against and where it is what produced the duel wins.

**Wave 14 (on warm-up + rebirth, 1749) and the net-exchange duel.** Rebirth threshold a third
instead of a fifth: 631, 539, 520 = 1690 (7 team wins on seed 1); rebirth every 10 matches:
532, ?, 540; memory sharing 1412; sense-times-pick acquisition 1442; self-play seed 2 172.
Nothing above the base. Duels reborn on a losing exchange (dealt minus taken under -20 a
match): 14, 11, 8, 0, 0, 9, 5, 0 = mean 5.9 against 8.5 for the warm-up alone; the seeds that
collapsed were reborn 13 times, which is a creature that never gets to learn. Rebirth needs to
be rare to work.

**Wave 15: partial rebirths (warm-up + rebirth base, 1749).** Resetting the value and the
memory too: 599, 516, 597 = 1712 (the same as full on seed 2, where nothing was reborn).
Resetting only the option weights and keeping the sense weights: 510, 522, 359 = 1391, worse.
A creature that has gone wrong has gone wrong in what it thinks the senses mean, not only in
what it thinks of its options. Full rebirth stays.

Option blocks on the warm-up + rebirth base: 503, 423, 593 = 1519 (base 1749); self-play on
it, checked against bots: 410, 172, 268. Both dropped.

**Wave 17: horizon 36.** With step 12: 387, 506, 430 = 1323; with step 18: 569, 224, 324 = 1117;
the rebirth base at horizon 24 is 1646. The 2.4 s horizon stays.

**Waves 16-19 (rebirth base: 545, 634, 467 = 1646).**

```
                                                  seed 1   seed 2   seed 3   total   verdict
  reborn creature inherits its best team-mate's   615      685      467      1767    +7%; seed 2's four 198, 164, 124, 200 with 11 team wins; seed 3 had no rebirth
    memory of surprises (INHERIT)
  a team of four tempos (steps 8, 12, 16, 20)     369      338      572      1279    worse
  400 matches instead of 200                      495      --       --               no gain from longer training on seed 1
  self-play, checked against bots                 277      402      367      1046    worse
  ally death preference -50                       571      416      170      1157    worse
  kills worth 0 / kills worth 100                 527, 469 on seed 1                  nothing
```

400 matches instead of 200 on the rebirth base: 495, 616, 554 = 1665 against 1646. Training
twice as long buys nothing; the creatures are what they are by match 100 or so, and the rest
is drift. Kills worth nothing (KILL=0 TEAMKILL=0): 527, 474, 695 = 1696, the same as with them.

## 38. Where the search stands

Nineteen waves, about 250 arena runs and 60 duels. What moved the number, in order:

```
                                          mean of the four creatures' damage, 8 seeds   worst creature
  session-start default (OMEUICT)         ~335 (three seeds)                            0
  drop spread and improvement (OMECTA)    same, cheaper
  effects step 8 -> 12                    312 -> 421                                    0
  rebirth for a creature far behind       421 -> 585                                    68
  (+ memory inheritance at rebirth        1646 -> 1767 on three seeds; more seeds running)
```

Cost is unchanged (~1 ms a think, one creature, JIT). Everything else tried -- eleven exploration
and representation ideas, five training regimes, horizon and lookahead settings, preferences --
was within seed noise or worse, and is recorded above with its numbers. Two lessons that
generalise beyond this arena: an addition to the model is a tax until its weights settle, and a
creature's fate is decided in its first few matches, so the cheap wins are in what happens at
birth and in what happens when a life goes wrong, not in the model.

Still open: the one on one, where the warm-up gets two wins in eight seeds, and the old
creature in the page, which needs forgetting because it cannot be reborn against a team.

**Inheritance over eight seeds:** 615, 685, 467, 574, 614, 644, 434, 395 = mean 554, against
585 for rebirth alone. Two seeds unchanged (no rebirth), one much better (seed 2, 11 team
wins), two worse (seed 8 was reborn 14 times: a creature handed a stranger's memory keeps
falling behind and keeps being reset). Not a gain; off by default. With the machine idle the
current default thinks in 0.6 ms.

**Wave 20: a duel population.** Four independent one-on-one learners per seed, each in its own
duels, reborn when under a fifth of the pool's best over 20 matches. Check wins of 30 per
creature:

```
  no warm-up   seed 1: 6, 4, 1, 27     seed 2: 0, 0, 13, 0     seed 3: 2, 0, 11, 4
  warm-up 10   seed 1: 8, 2, 3, 0      seed 2: 0, 2, 7, 4      seed 3: 7, 9, 0, 0
```

One creature in twenty-four wins 27-3 (145 damage a match), the best duel of the session; the
mean is 5 of 30, no better than the warm-up alone. Rebirth does not fix the duel: the reborn
creatures come back weak (30-74 damage). The winning duellists all do the same thing -- keep
moving across the bot's line and shoot -- and most creatures never find it; in a team the
rebirth gives a second chance at a first hit, but the duel's skill is not a first hit, it is a
way of moving, which one match does not teach.

**Wave 21: replaying the best matches.** One extra update a tick from the rows of the
creature's five best matches so far. Arena: 466, 597, 401 = 1464 against 1646; duels: 0, 7, 1,
0, 0, 7, 0, 0 wins of 30 against a mean of 8.5 without. Worse everywhere: the best matches'
rows were scored under an older value and drag the current one back to it. Dropped.

**Wave 22: two bullet senses (time until the nearest incoming bullet is level with me, and
which side it passes).** Arena: 462, 385, 298 = 1145 against 1646; duels: 3, 0, 0, 5, 0, 13,
1, 8 wins of 30 against a mean of 8.5. The input tax once more, and this time on the thing
the duel needs most: the creature that dodges learned it from bearing and "incoming" already,
and two more inputs to pin made every seed worse. Off by default (`BULLETSENSE=1`). A rebirth
cooldown of 40 matches (with the senses on): 479, 534, 498, 407, no better.

**Wave 23: a duel curriculum.** 150 matches against the bot that never parries, then 150
against the full bot, warm-up 10, eight seeds. Check wins of 30:

```
  warm-up only          22, 9, 0, 21, 1, 0, 4, 11     mean 8.5    two seeds over 12
  curriculum            0, 5, 21, 14, 12, 9, 17, 5    mean 10.4   four seeds over 12, one zero
```

The first stage is won outright (32-18 in its last block) and the creature keeps most of the
style when the parry arrives; damage 107-134 a match on six seeds of eight. The first
consistent duel result: not a breakthrough on the mean, but the floor has moved.

**Wave 24: curriculum lengths, eight seeds each.** 100 then 300: 0, 12, 7, 11, 8, 4, 14, 11
(mean 8.4); 200 then 200: 0, 10, 7, 7, 12, 17, 8, 7 (mean 8.5); 150 then 150 (wave 23) mean
10.4. The length does not matter much; what the curriculum buys is consistency: seven seeds of
eight at 4 wins or more in every variant, where the plain warm-up had three seeds at 0 or 1.
Seed 1 is 0 in all three -- some starts are unrecoverable one on one.

**The curriculum in the arena** (100 matches against no-parry bots, then 100 against the full
bots, rebirth default): 765, 500, 503 = 1768 against 1646. Seed 1's four are 211, 118, 202,
233 with 10 team wins -- the strongest four of the session; seeds 2 and 3 are a little under
the base. More seeds running.

**Wave 25: deciding every second or third tick (the picks held between).** Arena: every 2nd
tick 550, 544, 297 = 1391; every 3rd 487, 494, 454 = 1435; base 1646. Duels with the curriculum,
every 2nd tick: 18, 7, 0, 11, 9, 11, 11, 11 = mean 9.75 against 10.4 -- and the most even duel
row yet, seven seeds of eight at 7 or more. Half the thinking for a small loss in the arena and
none in the duel: the cheap setting for many creatures.

**The arena curriculum over eight seeds:** 765, 500, 503, 625, 526, 566, 626, 589 = mean 588
against 585 for rebirth alone -- the same damage, but 39 team wins of 240 against 27, and no
creature under 76. Kept as the training regime. At half the decision rate the curriculum gives
577, 479, 542 = 1598 (three seeds), about a tenth under the full rate.

**Three stages in the duel** (no-parry 100, camper 100, full bot 100, every 2nd tick): 0, 1,
0, 6, 11, 8, 12, 5 = mean 5.4 against 9.75 for two stages. The camper teaches standing still,
which the full bot punishes. Two stages it is.

**Three stages in the arena** (no-parry 70, camper 60, full): 689 (12 team wins), 429, 517 =
1635 against 1768 for two stages. **Hierarchical think** (targets, moves and aims scored with
no act, then every act on the best three): duels 7, 1, 5, 14, 0, 0, 0, 0 = mean 3.4 against
10.4, and no cheaper in the sanity run. Committing to a move before seeing the acts loses the
combinations that only make sense together ("approach and melee"). Dropped.

Hierarchical think in the arena: 468, 443, 344 = 1255 against 1768. **Act family tags** (four
flags -- attack, defend, heal, buff -- beside the act flag) in the duel: 12, 1, 0, 8, 5, 2, 4, 17
= mean 6.1 against 10.4. At nine acts the tags are four more inputs to pin and nothing to
share; they would earn their place only with a long act list, where each act alone is starved.

**Wave 29: a teacher instead of dice.** The scripted bot plays the creature's first ten matches
through its body while the creature learns from the rows (`WARMDEMO=1`). Arena: 450, 301, 325 =
1076 against 1646; with the curriculum 481, 370, 406 = 1257 against 1768; duels 3, 0, 7, 2, 0,
12, 1, 5 = mean 3.75 against 10.4. Worse everywhere, and by a lot. A demonstration gives the
creature confident values for the handful of options the teacher takes and nothing about the
rest, which is the shape of a collapse; ten random matches give it a little about everything,
which is the shape of a start. If a knowledge base is wanted, it should be seeded memories
(tried when near, dropped when wrong) or a weak prior, not demonstrated rows. Tags in the
arena: 559, 537, 362 = 1458 against 1768.

**Tagging senses for the effects models.** A hand mask (each option's effects model predicts
only the senses its choice "can" move) is a fixed structure the creature could not revise --
a sword that knocks the target back would be invisible to a move model told it cannot touch
distance -- so it was replaced before being tested by a learned one: outputs a model has never
explained (confidence 0 after 200 rows) are refitted every tenth row only, and can come back
(`EMASK=learn`). Measured on an idle machine it saves almost nothing: the effects update's cost
is the shared covariance gain, 96 squared per model, not the per-output work, so masking outputs
cannot reach it. The cheap lever on the effects tier is the beam (3 instead of 10: 0.31 ms
against 0.42 ms a think), being tested.

**Wave 31: a beam of 3 second steps instead of 10.** Arena with the curriculum: 579, 573, 644
= 1796 against 1768; duels 5, 0, 28, 8, 11, 0, 11, 12 = mean 9.4 against 10.4, with the best
duel of the session (28-2, 148 damage a match). Same performance for a quarter less think:
BEAM=3 is now the default. The learned effects mask (unexplained outputs refitted every tenth
row): 483, 496, 579 = 1558, a little worse and no cheaper; off.

Beam 3 over eight seeds: 579, 573, 644, 452, 561, 541, 464, 457 = mean 534 against 588 for
beam 10 on the same seeds with the curriculum: 9% less damage for a quarter less think. Not
free after all; the default goes back to 10, and beam 3 joins "decide every second tick" as
the settings for a crowd.

## 39. Instincts: a creature that starts with something

The user's constraint: no pretraining in a Roblox game, so what a creature knows at birth must
be written, and it must still be the creature that learns. The knowledge file (instincts.lua)
holds four kinds of thing in the creature's own vocabulary, all of them priors: value weights
with a confidence, declared pair features ("on target and shooting"), effects beliefs ("approach
closes distance by 0.3 a step"), and masked playbook memories ("bullet coming, parry ready:
parry"). A vague instinct (vague.lua) names only a pair and a reading -- "low health, drinking,
damage taken are connected somehow" -- and the acquisition search tests every operator on that
pair at birth plus 200 rows, keeps the shape that explains the reading, and a small novelty
bonus makes the creature try the named acts early.

**Hand-written instincts against blank, full bots from birth, no warm-up, no curriculum**
(the closest thing to a spawn), three seeds:

```
                    first 20 matches (damage a match, the four)    final check      team wins
  blank, seed 4     56, 31, 40, 23                                  491              2
  instinct, seed 4  34, 6, 48, 35                                   596              5
  blank, seed 5     4, 2, 3, 6                                      611              1
  instinct, seed 5  11, 53, 52, 24                                  484              0
  blank, seed 6     48, 4, 0, 32                                    494              0
  instinct, seed 6  32, 2, 30, 45                                   491              4
```

The instincts fix the dead start (seed 5's blank four begin at 4, 2, 3, 6 and the instinct four
at 11, 53, 52, 24), give more team wins (9 against 3), and end at the same damage. They do not
make a creature that is competent in match one against the full bot -- nobody's first twenty
are good -- but they make the first twenty survivable, which is what a spawn needs. The
distilled-knowledge spawns and the vague instincts are running.

**Vague instincts** (five "these are connected" lines, no weights): seed 4: 622 with 10 team
wins (blank 491 and 2; precise instincts 596 and 5); seed 5: 430; seed 6: 466. The pair it was
told about became "dealt: mul(onTarget, act=shoot)" on its own within the first search. Same
damage as blank over three seeds, more team wins (11 against 3).

**A spawn from distilled knowledge.** The strongest creature of the seed-1 curriculum run was
distilled into a knowledge file: its 25 largest weights per reading it cares about (100
priors, at confidence 50) and its 30 best memories. Four fresh creatures on seed 4 were given
that file and nothing else, no warm-up:

```
                              first 20 matches (vs no-parry bots)   check vs full bots   team wins
  blank, seed 4 (curriculum)  ~30-60 a match, 0 wins                625                  7
  spawned from the file       274, 172, 248, 196; wins 18-2         736 (196, 150, 188, 203)   18 of 30
```

Competent from the first match, and at the check the first team in the session to win a
majority against the full bots. The file is a few kilobytes: the whole brain is 1.8 MB. Two
lessons: what makes a creature is a hundred weights and a playbook, not the covariance; and a
prior at confidence 50 is strong enough to be a start and weak enough to be improved on, since
the spawned four beat the run they were distilled from. Confidence 5 and 500, and seeds 5 and
6, are running.

**Distilled spawns, three seeds and three confidences** (check damage of the four, team wins
of 30; first-20-match wins against the no-parry bots in brackets):

```
                 seed 4              seed 5              seed 6              mean   
  blank          491 (2 wins)        611 (1)             494 (0)             532
  blank + curriculum   625 (7)       526 (2)             566 (4)             572
  file, conf 5   642 (5) [12-8]      750 (11) [18-2]     574 (6) [12-8]      655
  file, conf 50  815 (17) [18-2]     736 (18) [19-1]     742 (15) [18-2]     764
  file, conf 500 743 (16) [19-1]     807 (18) [19-1]     768 (6) [20-0]      773
```

Every spawn is competent from its first match (200 damage a match and 18-20 of its first 20
against the no-parry bots), and at confidence 50 or more the four win a majority of their check
matches against the full bots on five seeds of six, with the highest damage of the session
(807 on seed 5). Confidence 5 fades too soon and ends 15% lower. The file came from one creature
of one run; the spawns are four different creatures on three different seeds, and their check
lines show four different act profiles, so the priors set a start, not a style. +34% over the
blank curriculum creature, and a majority of team wins, from a file of a few kilobytes.

**The file in duels, and a second source.** The seed-1 arena file spawned into one-on-one
duels: 10, 8, 6, 12, 0, 17, 8, 0 wins of 30 (mean 7.6 against 10.4 for the plain curriculum);
the spawns win their first fifty against the no-parry bot 50-0, and the full bot still beats
most of them. Arena knowledge does not carry to the duel, whose skill is a way of moving. A
file distilled from a weaker source (seed 2's best, from a run of 500): spawns 520, 467, 528 =
mean 505, under the blank curriculum's 572. The file is only as good as the creature it came
from, so the distiller should take the best creature of the best run, and a second generation
-- distil the best spawn, spawn again -- is the obvious next test.

**Generations.** First-generation spawns from the seed-1 file on five seeds: 815, 736, 742,
820, 735 = mean 770, team wins 17, 18, 15, 21, 11. The best of them (seed 5, rerun with the
distiller: 840, 27 wins of 30) distilled again and spawned on four seeds: 656, 838, 801, 812 =
mean 777, wins 8, 16, 12, 16. A second generation is no better than the first: one distillation
takes a creature from 570 to 770, and the second finds nothing left to take, against these bots.
The scripted bots are now the ceiling of the measurement, not the creatures: the next yardstick
has to be the spawned creatures themselves.

**A fuller hand-written file** (18 value priors at confidence 50, 14 effects beliefs, 15
playbook entries, 3 vague lines), full bots from birth: 374, 456, 486 = 1316 against 1596
blank and 1571 for the thin file; 2 team wins. Better first twenty than blank on two seeds,
worse at the end on all three, one creature collapsed to 3. Written numbers at confidence 50
are the optimism failure again: where a guessed weight is wrong (is closeness worth -8 to
damage dealt? I made that up) the creature spends fifty rows unlearning it. The distilled
numbers work because they were measured. So for hand-crafting: playbook entries and vague
lines, which the creature tests and can drop, and effects beliefs about the world's mechanics,
which are easy to get right; value weights only where you would bet on the number.

## 40. Creatures as the yardstick, and generations

With the scripted bots beaten, the check phase can field spawned creatures as the opponents
(`CHECK_VS=file.lua`: the other team is four creatures spawned from that file, frozen). Three
seeds each, team wins of 30 against first-generation spawns:

```
  blank curriculum creatures       16, 3, 1     (mean 6.7)
  first-generation spawns          16, 16, 15   (even, as it should be: same file, and the learners had 200 matches more)
  second-generation spawns         28, 20, 19   (mean 22.3)
```

The second generation was no better than the first against bots and is much better against
creatures: the bots had been the ceiling of the measurement since wave 12. So the loop is
distil the best, spawn, train, distil the best again, and each turn of it is a few kilobytes
and a few minutes. It is selection, but what is selected is a file of instincts, not a
creature: every spawn is still its own creature with its own style, and the file can be edited
by hand between generations.

**Playbook, effects beliefs and vague lines only, no value weights:** first twenty 38, 22, 94,
21 / 47, 25, 78, 36 / 41, 75, 72, 44 (blank: 56, 31, 40, 23 / 4, 2, 3, 6 / 48, 4, 0, 32), so
the birth is fixed on every seed; the end 496, 423, 238 = 1157 against 1596, with one creature
at 0 and no team wins. The playbook helps the first minute and hurts the two-hundredth match:
a masked entry matches whenever its two or three senses do, which is often, and the replay
floor of one in ten keeps it firing for life. Hand-written memories need to fade: a lower
floor, and removal after enough retests that do not pay.

With fading hand memories: first twenty 53, 54, 35, 33 / 8, 29, 41, 34 / 30, 65, 85, 54; end
578, 266, 553 = 1397 against 1596, team wins 5 against 3. The verdict on hand-writing, after
five files: it reliably fixes the dead start and adds a few team wins, and it does not make a
stronger two-hundredth-match creature than a blank one; the distilled file does both. The
recipe for a game is therefore: distil for the numbers, hand-write the playbook and the vague
lines for the things you want the creature to try, and let both fade.

**Third generation**, team wins of 30 against second-generation spawns: 20, 21, 25 (mean 22),
where second against second is 23, 18, 14 (mean 18). Each generation still beats the last,
by less: 6.7 -> 22 -> 18 (even) -> 22 over the same yardstick shift. The page now carries two
second-generation teams (194-236 damage a match against the bots, 16 of 30 team wins).

## 41. Capacity

First-generation spawns against first-generation spawns (an even 16, 16, 15 team wins of 30),
with the stores made larger or smaller, three seeds:

```
  acquired interactions 6 (default)   16, 16, 15
  acquired interactions 12            18, 18, 16
  acquired interactions 24            17, 16, 16
  memory 50 entries                   29, 13, 17
  memory 200 (default)                16, 16, 15
  memory 800                          23, 20, 17
```

More interactions buy nothing, which fits everything since wave 1: the value's exceptions are
limited by rows, not by the cap. The memory is different: 800 entries beat 200 on every seed,
and 50 entries produced the single best result of the wave on one seed and the worst on
another. The memory is the store that holds a creature's exceptions, and the evidence is that
200 is not its ceiling and that its contents matter more than its size. More seeds and a
larger memory are running.

Memory size over five seeds (4-8), team wins against first-generation spawns: 50 entries 29,
13, 17, 24, 17 (mean 20.0); 200 entries 16, 16, 15, 22, 18 (17.4); 800 entries 23, 20, 17, 21,
16 (19.4); 3200 entries 15, 26, 15 (18.7, three seeds). All within noise of each other. The
size of the exception store is not what limits these creatures either; with the interactions
cap and the input tax that makes three stores that do not bind. What binds is rows -- how much
of the world a creature has seen -- and the file, which is rows distilled.

**A duel file.** The 28-2 duellist (seed 3, beam 3, curriculum) distilled at confidence 50 and
spawned into seven fresh duels against the full bot from birth, no warm-up, no curriculum:
11, 9, 6, 17, 18, 10, 14 wins of 30 (mean 12.1), and 9-18 wins in the first fifty matches. The
plain curriculum creature averages 10.4 with zeros; these have no zeros and the worst is 6.
The duel's skill did not travel in the arena file and does travel in a duel file: what a
creature knows is specific to what it has fought, so the species needs a file per kind of
fight, or one file distilled from a creature that has done both.

**Second duel generation and the file with the curriculum.** Duel gen-2 spawns: 11, 7, 15, 9,
14, 7, 5 (mean 9.7); gen-1 file plus the curriculum: 8, 10, 13, 6, 8, 4, 14 (mean 9.0); gen-1
file alone 12.1. The duel does not compound the way the arena does: every route lands at 9-12
wins of 30 against the parrying bot, with the odd creature at 28. One on one against a bot that
parries on sight, the creature's vocabulary of moves and a 2.4 s horizon reach about a third,
and the file cannot carry what the vocabulary cannot express.

## 42. Nobody parries

Bullets blocked by parries, counted for the first time (a second-generation team against the
bots, 30 checks):

```
                 parries started a match   bullets blocked a match
  scripted bots  17 - 41                   8 - 11
  creatures      0 - 24                    0 - 1.6
```

The bots block a third to two thirds of what they parry for; the creatures block almost
nothing. A creature that parries 24 times a match and blocks 1.6 is spending a one-tick commit
and a ten-tick cooldown on a habit. Every creature that wins does it by moving off the line and
out-hitting, never by parrying. The reason is timing: a parry is a four-tick window, a bullet
crosses the last ten units in three ticks, and the only sense about bullets is a binary
"one is coming", which is true for eight ticks before and after the moment that matters. The
bullet-time sense (wave 22) was exactly the missing input and was dropped as a tax on damage;
it should be judged on blocks.

**Memory settings on the creature yardstick** (team wins of 30 against first-generation
spawns; the baseline is 16, 16, 15 on these seeds and 22, 18 on two more, so the noise band is
about 15-22):

```
  match radius x0.5     21, 20, 18      surprise bar 3     15, 16, 20
  match radius x2       28, 18, 21      surprise bar 8     19, 24, 7
  payoff bar 5          17, 23, 22      payoff bar 20      20, 16, 24
```

Nothing leaves the band except perhaps the doubled radius (a 28 among them), which gets more
seeds. The memory's settings, like its size, are not where the creatures are limited.

**What makes a creature parry** (bullets blocked a match, best creature of four / the others):

```
  spawned file, no instinct           0.9 / 0, 0, 0          0 / 0, 0, 0
  + bullet-time sense                 1.4 / 0, 0, 0          0 / 0, 0, 0
  blank + hand instincts              7.1 / 1.0, 1.5, 2.2    2.4 / 0.1, 1.2, 2.1
  blank + instincts + bullet sense    0.8 / 0, 0, 0          6.1 / 1.5, 1.7, 1.8
```

The sense that makes timing possible does nothing on its own; the instinct that says parrying
matters -- one declared situation and one playbook line -- produces creatures that block at the
bot's rate. What a creature learns is what it has a reason to try. (The instinct teams deal
less and win less than the spawned team, so parrying is a skill worth adding to a file, not a
replacement for one.)

Doubled memory radius over five seeds (4-8), team wins against first-generation spawns: 28,
18, 21, 28, 19 = mean 22.8 against 17.4 for the default radius on the same seeds; better on
four of five. Payoff bar 5: 17, 23, 22, 20, 16 = 19.6. The radius is the one memory setting
that may matter: a stored surprise replayed from further away fires more often. Three more
seeds at x2 and x3 are running before it becomes the default.

## 43. The bare creature

Raw senses (my state; every other fighter's raw relative position, heading, health, side, in
fixed slots; the nearest bullet: 71 inputs) and raw outputs (move, turn, act: 108 combinations,
no target), with every improvement of the session on top -- step 12, rebirth, the curriculum.

```
                        200 matches            400 matches            structured, 200 matches
  seed 1                49, 13, 49, 12 (123)   58, 45, 7, 27 (136)    765
  seed 2                4, 10, 1, 14 (29)      38, 21, 6, 18 (84)     500
  seed 3                44, 11, 39, 12 (105)   78, 15, 60, 16 (169)   503
```

A fifth to a seventh of the structured creature, no team wins, and the training curves are
flat from match 200 on. The improvements fix how a creature starts and recovers; what it can
learn per row is set by the vocabulary. "Close and facing" is one sense to the structured
creature and a function of fourteen raw numbers to the bare one, which a linear value cannot
form and the residual search finds only by luck. And it thinks in 3 ms, because every model is
sized by the raw inputs. The structure is the creature; the learning is what fills it.

## 44. Cost levers and the file with an instinct pasted in

**Diagonal covariance** (`RLS_DIAG=1`, one variance per feature): learning a row 0.17 ms
against 0.46 under load, a third of the cost. Spawns against spawns: 6, 15, 16 team wins
(baseline 16, 16, 15); blank curriculum against bots: 515, 507, 490 = 1512 against 1768. About
15% less damage for a third of the learning cost -- a trade, like beam 3 and the half-rate
decision, for a crowd rather than a champion.

**The distilled file with the parry instinct added by hand** (one declared situation at
confidence 30, one playbook line): damage 173-243, team wins 18 and 16 of 30 -- the file's
strength kept -- but blocks of only 0.5-1.7 a match, where the same two lines on a blank
creature produced 6-7. A hundred confident priors drown two lines at confidence 30: the
instinct never gets tried enough to be learned. To add a skill to a file, the instinct has to
be at least as confident as the file, or the file has to be distilled from a creature that
already had the skill.

## 45. The live species prior, at four creatures

One outcome model shared by the four learners (every row updates it), each creature's own
model learning only its residual, the value the sum. Three seeds:

```
                              full bots from birth      curriculum
  four separate creatures     545, 634, 467 = 1646      765, 500, 503 = 1768
  species + residuals         477, 550, 463 = 1490      594, 361, 540 = 1495   (one creature at 0, team wins 1, 0, 2)
```

Worse by 10-15% at four creatures, and rebirth no longer rescues, since it resets the residual
and the shared part carries on. The argument for the species model was rows multiplied by the
number of creatures; four is not many, and what it costs at four -- the pull toward one style
and a rebirth that cannot reach the shared part -- is visible before the gain is. A test at
eight learners is running; if the gain does not appear there either, the species should stay a
file, taken from the best creature, rather than a live average of all of them.

## 46. A sword picked up mid-life: descriptor senses

The sword: a second melee with reach 6.5 and 45 damage, usable from match 100 of 200. Two
creatures: one with the sword as a new act flag born at zero, one whose acts carry five
descriptors -- reach, damage, commit, cooldown, heal -- so the sword is a point between acts it
knows (`DESCR=1`). Curriculum, three seeds; the block right after the pickup, and the check:

```
                       matches 101-120 (the four)      check          sword use    total
  act flag only        48, 55, 71, 26 / 138.. / 47..   376, 504, 398  3-23 a match  1278
  with descriptors     159, 185, 195, 155 / 137.. /..  620, 569, 491  15 a match    1680
  (no sword at all)                                    765, 500, 503                1768
```

A new act as a bare flag is a tax and a stumble: the block after the pickup drops to a third
on two seeds while the creature tries a thing it has no opinion about, and the check ends 28%
under a creature that never got a sword. With descriptors there is no stumble -- the block
after the pickup is the best block of the life on seed 1 -- and the check is within 5% of the
no-sword creature while using the sword fifteen times a match. That is the mechanism for a
hundred weapons: one act, a few numbers that describe what is in hand.

## 47. A fast think between big thinks

Big think (every combination, the projection) every 5 or 10 ticks; between, a fast think that
re-scores the big think's best eight on the senses of the moment, value only. Curriculum,
three seeds: every 5 -> 428, 423, 450 = 1301; every 10 -> 157, 326, 390 = 873; holding the
picks every 2nd tick (wave 25) 1598; every tick 1768. Worse than simply holding, and no
cheaper: the fast think recomputed the senses for its shortlist and wrote a row each tick, so
learning cost doubled, and a value without the projection overrides a choice that was made
with it -- the projection is worth half the damage, and the fast think threw it away. Second
version: the fast think carries each shortlisted combination's projection bonus from the big
think, and writes no rows.

**Memory radius over eight seeds** (team wins against first-generation spawns):

```
  seed        1     2     3     4     5     6     7     8     mean
  default     20    29    17    16    16    15    22    18    19.1
  x2          27    27    20    28    18    21    28    19    23.5   better on six of eight
  x3          4     14    4     --    --    --    --    --           far worse: replaying from that far is a hijack
```

Doubling the radius at which a stored surprise is replayed is a real, modest gain, +4 wins of
30, and tripling it wrecks. The new default is x2. It fits the rest: the memory is the exception
store, and the creatures were using it a little too rarely.

Second version (projection bonus carried, no rows from fast thinks): 473, 508, 376 = 1357
against 1598 for holding and 1768 for every tick -- and thinking time went up, not down. The
fast think has to compute the senses for the targets on its shortlist, and that, not the
scoring, is the per-tick cost. Two versions say the same thing: below the big think, the cheap
loop is holding the picks plus the reflex match on senses already in hand; a "fast think" that
needs fresh senses is a big think in disguise. For Roblox that is the useful reading -- the
raycasts and distance scans will be the budget, not the arithmetic.

Correction, measured: a senses computation costs 19 us, five of them a think, about a tenth of
the think in Lua. So the fast think's extra time is its extend and scoring, not the senses,
and the reason to drop it is the damage it loses, not its cost. The Roblox caution stands on
its own grounds (raycasts are dearer than arithmetic there), not on this measurement.

Descriptors with no sword: 464, 598, 584 = 1646 against 1768 without descriptors -- five more
inputs, a 7% tax while nothing changes in hand, repaid many times over the day a weapon does.
The parry instinct at confidence 100 on the distilled file: 829 and 807 damage with 21 and 22
team wins -- stronger than the file alone -- and blocks still 0.4-1.7. The confident weight
changed what the creature is worth, not what it can do: a skill with timing in it is learned
from rows, and a prior can only make the rows likelier. The file distilled from a creature that
parries is the remaining test of that.

The distiller took the strongest creature of the instinct-born run by damage (creature 7,
1.5 blocks), not the parrier (creature 6, 7.1 blocks), so the spawns from it block 0-1.6.
Rerunning with the parrier chosen by hand.

**At eight learners** (eight against eight bots, curriculum, two seeds; total of the eight):
separate 1262 and 662, species prior 931 and 859. Worse on one seed, better on the other, a
7% loss on the mean, and no team wins either way. Twice the creatures did not make the species
model pay, so the mechanism as built -- shared model plus residuals, every row shared -- is
not a gain in this arena. The species stays a file: distilled once from the best creature,
edited by hand, spawned into. If a live version is wanted for a game, it should learn from
the best creatures' rows, not everyone's, and rebirth should reset it as well.

## 48. Deciding when to decide

Two ways to hold the picks except when it matters. A hand rule (`THINK_EVENT`): think when any
sense moved more than a threshold, a binary sense flipped, an act came off cooldown, a commit
ended, or the target died. A learned rule (`THINK_META`): every big think scores the picks it
was holding and records what it gained over them; a one-output model from the senses predicts
that gain, and the creature thinks when the prediction is above a bar. Curriculum, three seeds:

```
                                      damage (three seeds)     ticks held    think cost
  every tick                          765, 500, 503 = 1768     0%            1
  hold every 2nd tick (fixed)         577, 479, 542 = 1598     50%           0.5
  attention model, bar 0.5            529, 506, 510 = 1545     58-68%        ~0.37
  attention model, bar 1              394, 447, 433 = 1274     70-76%        ~0.27
  attention model, bar 2              413, 407, 631 = 1451     79-81%        ~0.2   (two collapses)
```

The learned attention at bar 0.5 thinks a quarter less often than the fixed half rate for 3%
less damage: about the same trade at a better point, and it is learned from the creature's own
decisions rather than set. Past that bar it holds through moments that mattered. The model is
47 weights and the training signal is free, so it is the right shape; a richer input (the
held picks, the time held, the last gain) would probably move the curve.

**The parrier's own file.** Distilled from the creature that blocked 7.1 a match (a weak
creature otherwise, 134 damage) and spawned on two seeds: blocks 3.1, 1.2, 0.5, 0 and 0.9,
3.8, 3.1, 2.5 -- more than any other file's spawns (0-1.7), a third to a half of the source --
and weak teams, because the source was weak. A timed skill carries partly in a file; the rest
is rows. The recipe stands: distil the best fighter, and if it must also parry, make it learn
to parry before it is distilled.

The hand rule, for the record: threshold 0.3 on the largest sense change, plus flips,
readiness and a dead target: 466, 547, 679 = 1692 with only 20% of ticks held; flips and
readiness alone: 327, 639, 566 = 1532 at 24% held. With eighteen binary senses something
flips most ticks, so the hand rule thinks nearly every tick and saves nothing; the learned
attention holds three ticks in five for the same damage. Learned wins over written, again.

**Attention with the hold time and the last gain as inputs**, bar 0.5: 676 (8 team wins), 368
(one collapse), 573 = 1617, thinking on 27% of ticks (64,410 big thinks, 176,977 held). Against
every tick (1768, 100%) and the fixed half rate (1598, 50%): a quarter of the thinks for 91% of
the damage, where the fixed rule needed half the thinks for 90%. Bar 1: 377, 509, 552 = 1438
at 21-24% thinking. The learned attention is the crowd setting: `THINK_META=0.5`. Three more
seeds are running to hold it to that claim.

**The slow tier.** Every tenth think a three-step projection chain chooses a plan, and the
plan's combination gets a bonus in the big thinks between. Plan worth 3: 475, 465, 374 = 1314;
worth 8: 420, 406, 309 = 1135; no slow tier 1768. Worse, and worse the more the plan is
trusted. The deeper projection is not a better judge, it is a noisier one -- three steps of a
linear effects model compound its error -- and a bias toward its choice is a bias toward noise.
The tiered mind, as measured, is: reflex every tick, a big think when the attention model says
so, learning every row, and no slow tier.

## 49. Where things stand (after 57 waves)

The creature: readings and preferences; a one-step effects projection at a 12-tick step; the
couplings; a memory of surprises matched at twice the old radius; acquisition on a reading's
residual; rebirth for a creature far behind its team; a random warm-up for a lone creature; a
curriculum from no-parry bots to full ones; and a learned attention that decides when to think.
Off, because measured worse: every exploration bonus, hazards, option blocks, choice pairs,
tags at nine acts, bullet senses, forgetting in training, memory sharing and inheritance, the
live species prior, replay, longer training, the fast think, the slow tier.

The species: a distilled file (a hundred weights at confidence 50, thirty memories, a few
kilobytes) that makes a spawn competent from its first match and stronger than a blank creature
by a third at match two hundred; generations of it compound against creatures; hand-written
instincts fix a dead start and teach timed skills a file cannot carry; descriptor senses let a
new weapon be predicted before it is held.

The numbers, mean damage of the four creatures per seed: session start ~335; now ~590 blank,
~770 spawned from a file, with team wins against the bots going from none to a majority. Cost
0.4 ms a think, 0.2 ms a row, 3.7 MB a creature (0.6 without the effects covariances); the
crowd settings (attention, half rate, beam 3, diagonal) each trade about a tenth of the damage
for two to four times the creatures.

Attention at bar 0.5 over six seeds: 676, 368, 573, 586, 599, 417 = mean 537, thinking on
32-39% of ticks, against the every-tick curriculum's 581 on the same seeds. Eight percent of
the damage for two thirds of the thinking, learned by the creature itself. Confirmed as the
crowd setting. Effects models with a diagonal covariance take a creature from 3.7 MB to 1.8
MB (the rest is their weights and LuaJIT's per-table overhead); the damage test is running.

**Diagonal covariance on the effects models** (3.7 MB -> 1.8 MB a creature): 318, 478, 425 =
1221 against 1768. A 31% loss: the projection that is worth half the damage needs the full
covariance to learn the effects fast enough, and a diagonal one learns them too slowly to
matter by match 200. Not a trade worth making; the memory answer is to share the effects
models across the kind (running), and to keep covariances only for creatures that are awake.

## 50. Shared physics

One set of effects models for all the creatures of a kind, with their covariances, learning
from every creature's rows (`SHARE_E`). Curriculum, three seeds: 637, 590, 625 = 1852 against
1768 with a set per creature; the weakest creature 129 against 76. Better, evener, and a
creature's own memory falls from 3.7 MB to about 0.5 MB, since the 3.2 MB of effects are held
once per kind. The value stayed per creature and the live species value prior failed; the
effects are shared and the shared effects win. The line between them is the line between
style and physics: what a creature wants is its own, what its options do to the world is its
kind's. Now the default for any team of learners.

**The split: species holds the full covariances, the creature a diagonal.** Shared effects
(full), a species value model (full, every row), and each creature's own residual value with
a diagonal covariance: 608, 513, 634 = 1755, team wins 5, 1, 6, against 1852 and 4, 3, 3 for
shared effects alone and 1495 for the species value with full per-creature covariances. The
diagonal residual repaired most of what the species value prior lost: a residual should be
cheap and quick to move, and a full covariance made it slow and careful about the wrong thing.
At this point a creature's own live state is about two thousand numbers -- a diagonal, its
residual weights, its memory -- and everything expensive is held once per kind. Five percent
under shared effects alone on damage, a few more team wins; three more seeds running.

Shared effects over six seeds: 637, 590, 625, 608, 721, 590 = mean 628 against 581 for a set
per creature on the same seeds; +8%, no creature under 123. Confirmed as the default.

**The pruning search.** Every 300 rows, inputs the value barely used (weight times spread
under 2% or 5% of the largest) were frozen out of the model. Curriculum, three seeds: 111,
265, 135 and 99, 69, 144 against 1852. Catastrophic, and instructive: an input the value has
learned to ignore costs nothing in a decision, so pruning it gains nothing; the tax is paid
while a weight is being pinned, not after. And the least-used inputs are the option flags the
creature has not tried yet, so freezing them is freezing its future. Dropped. The residual
search grows the model and pays; its reverse does not.

The split over six seeds: 608, 513, 634, 395, 438, 430 = mean 503 against 628 for shared
effects with a full per-creature value. Twenty percent under. The three-seed result was the
good half of the noise. So the line stands where the first species test drew it: the value is
the creature's, with its own full covariance, and only the physics is shared. A creature's live
state is then about half a megabyte, which is fine; the diagonal residual saved memory that
did not need saving and cost damage that did.

**Macro memories** (a surprise remembers the picks that followed it and replays both ticks):
491, 417, 539 = 1447 against 1852. Worse. The second tick's picks were whatever the creature
happened to do next, not what made the surprise, and replaying them is a coin toss the memory
did not use to make. Dropped.

## 51. Sleeping and waking

A save-and-reload that keeps a creature's own weights and only the diagonal of its own
covariances, at match 100 of 200 (shared physics stays resident): 500, 475, 517 = 1492 against
1852 for creatures that never slept. A 19% loss by match 200: the senses are correlated, and a
covariance without its off-diagonal terms mis-sizes the next hundred matches of updates. With
the physics shared, a creature's own full covariance is only 117 squared, about fourteen
thousand numbers, 55 KB as float32, so the right save is the full own covariance and nothing
diagonal; being tested.

## 52. Depth in a world with no one else in it

The user's objection to "deeper projection is noise": the arena's variance is seven other
minds; alone, a creature's own effects might project cleanly. A solo world (tabforage.lua):
a switch that makes food appear for eight seconds somewhere, a pit, one creature, seventeen
senses, twelve combinations. Shaped: the switch itself pays 5 and food 20. Unshaped: only food
pays, so eating needs the two-step idea "the switch is worth going to because of what follows".
Food eaten a match at the check, three seeds:

```
                               shaped              unshaped
  one step (CHAIN=1)           7.7, 2.5, 2.4       0.0, 0.1, 2.9
  two steps                    2.4, 4.5, 0.7       0.1, 0.2, 1.0
  three steps                  1.8, 3.5, 2.9       0.0, 0.1, 0.8
  horizon 48, step 24                              0.1, 0.6, 1.1
  best of all at step two                          6.9, 0.0, 0.1
```

Chaining the projection does not help even here, shaped or not: the linear effects model's
error compounds without any other agent's help, because the switch and the food are
discontinuities (food appears, the pit starts hurting) that a linear step cannot carry. What
did work, on one seed, is the best-of-all-combinations second step: 6.9 a match with food only,
the best result in the world by far -- and 0 on the other two seeds. The variance moved from
the projection to the discovery: whether a creature ever stumbles on the sequence at all. So
the hypothesis is half right: without other agents the second step is worth searching over
properly; deeper linear chains still are not.

Over eight seeds, food only: one step 0.1, 0.0, 2.9, 0.6, 0.4, 4.0, 5.4, 10.8 (mean 3.0);
best-of-all second step 6.9, 0.0, 0.1, 0.7, 1.0, 0.2, 0.2, 1.4 (mean 1.3). The one-step
creature solves the puzzle on four seeds of eight, once at eleven meals a match; the wider
search on one. The seed-1 result was luck. So even alone, with only its own effects to
project, the creature gains nothing from looking further or wider, and the question of whether
it solves the puzzle is whether its first twenty random matches happened to include the
sequence. Depth is closed as a lever in this model; discovery is the lever, and the tools for
it are the warm-up, the rebirth, the memory and the file.

Sleeping with the full own value covariance kept (55 KB), the couplings and attention models
diagonalised: 560, 547, 605 = 1712 against 1852 without a sleep and 1492 with only diagonals.
An 8% cost for a reload at match 100, most of it the wake itself (the pending rows are
dropped, the couplings restart). So a save is: the own value weights and their full
covariance, the memory, the residual, the preferences and bonds -- under 100 KB -- and the
physics stays with the species.

## 53. The experience lookahead

For a candidate, the ten remembered rows most like it with the same picks lend the mean of
what followed them over sixty rows (a lookup over lived transitions, bends included), added to
the candidate's value. Solo world, food only, eight seeds (the one-step creature: 0.1, 0.0,
2.9, 0.6, 0.4, 4.0, 5.4, 10.8, mean 3.0):

```
  every candidate, every think (5.4 ms a think)   0.9, 0.1, 3.0, 0.1, 2.0, 0.1, 2.6, 0.1   mean 1.1
  gated by a predictor of its own payoff          3.8, 1.4, 2.3, 1.9, 1.0, 4.2, 0.1, 0.2   mean 1.8
```

Applied everywhere it hurts: ten nearest rows' returns are a noisy judge and it overrules the
model on noise, at ten times the cost. Gated, it is cheap again and steadier -- six seeds of
eight eat, against four -- but its best seeds are half the one-step creature's best, so the
mean is lower. What it does is smooth the luck: fewer creatures that never find the switch,
none that make a habit of it. Not a gain on the mean; the gate is the right mechanism, the
judge behind it is not good enough yet.

In the arena, on the beam plus eight others, every think: 270, 222 on two seeds against 617
a seed, at 5.8 ms a think. Ten similar rows from a fight are ten different fights; their mean
return is noise with a large weight. The experience lookahead is off; the idea survives only
as the gate's shape.

## 54. Three experts and a chooser

Three outcome models; a settled row trains whichever predicted it best; the active one, used for
all scoring, is re-chosen every ten thinks by the smallest recent error or by a vote of the
nearest remembered rows. Arena: recent chooser 291, 193, 241 = 725; nearest-rows chooser 353,
333, 373 = 1059; one model 1852. Solo world: both choosers 5.5, 0.1, 0.1, 2.7, 0.2, 0.0, 0.5,
0.2 = mean 1.1 against 3.0 for one model. Worse in both, and the reason is the session's
oldest one: competitive assignment gives each expert a third of the rows, so every expert is a
third as pinned as the one model would be, and a creature choosing among three half-learned
lines does worse than one that owns a whole one. Rows are the constraint, and any structure
that divides them loses before its extra shape can pay.

**What the deep tier can and cannot be, after 68 waves.** Everything that judged candidates
differently from the fast think lost: deeper lines, wider second steps, remembered returns,
experts. Everything that decided *when* the fast think should run, or *what* it should be
fed, won: the attention gate, the residual search, the curriculum, rebirth, the file. The
expensive tier's work in this model is not to think better about the next tick; it is to
decide when to think, what inputs to grow, and when a life needs a fresh start.

## 55. A model of the opponent, and the sheep world again

**The opponent model.** Two more events for the hazard tier -- this target starts a parry,
this target starts a shot -- predicted from the senses and entering the value at their
confidence. Duels with the curriculum, eight seeds, check wins of 30:

```
  curriculum alone                    0, 5, 21, 14, 12, 9, 17, 5    mean 10.4
  hazards on, old events only         0, 1, 11, 16, 4, 4, 6, 7      mean 6.1
  hazards on with the opponent events 16, 17, 7, 5, 17, 16, 20, 10  mean 13.5
```

The best duel result of the session on the mean, with six seeds of eight at 10 or more. The
hazard tier without those events is a tax, as it was in the arena; with them it is a model of
what this enemy is about to do, which is the one thing the duel needed and the one prediction
that had a measured failure to aim at. The slow tier's real work again: learning about a
specific thing, not deciding harder.

**The sheep world with the current mind** (tabsheep3.lua, episodes of one to three seconds,
re-deciding every 0.1 s among still and the four directions): after 2000 episodes the creature
takes 0.52, 0.52, 0.33 harm an episode against 0.35 for standing still and 0.01 for the hand
reflex. It learned nothing, and the reason is the raw creature's: signed offsets to the wolves
and five directions give a weighted sum no way to say "close is harm" or "away is good". Same
gap, third time. The fix is not sheep-specific, so it became the shared sense layout of the
three-world creature (tabmulti.lua): every world read as the creature itself plus the nearest
hostile, item, hazard and ally in its own frame with distance, bearing, unsigned bearing and
closing speed; the same target/move/aim/act choices, pruned to what a world can do; the sheep
world made continuous with wolves that keep coming.

## 56. One mind, three worlds

The shared sense layout (the creature; the nearest hostile, item, hazard, ally in its frame with
distance, bearing, unsigned bearing, closing speed, health and a descriptor) and the shared
choices, in three worlds: the duel arena, the forage puzzle, and a continuous sheep world.
Specialists first, 300 episodes each, three seeds:

```
  forage specialist    eaten 19.0, 17.9, 18.1 a match     (the old forage harness's best creature: 10.8; its mean 3.0)
  sheep specialist     harm 1.8, 1.8, 3.5 a minute        (a creature that walks toward things: ~30)
  arena specialist     dealt 7.5, 133.6, 7.0; wins 0, 20, 1 of 30
```

The layout alone solved the puzzle: "approach the item" is one policy when the item slot holds
the switch until food appears and the food after, and the creature finds it on every seed. The
raw layouts of the earlier harnesses were the puzzle's difficulty, not the puzzle. Structure
again -- and the structure is general, since the same slots read a wolf, a bot and a bullet.

Then one mind, 900 episodes with the world drawn at random each time:

```
  seed 1   arena 0 (1 win)    forage 0.03    sheep 1.3     -- it learned to flee, everywhere
  seed 2   arena 98 (2 wins)  forage 18.8    sheep 27.3    -- it learned to approach, everywhere
  seed 3   arena 0 (0 wins)   forage 0.03    sheep 0.7     -- it learned to flee, everywhere
```

One weighted sum cannot hold "close to a hostile is good" in the arena and "close to a hostile
is death" in the sheep world at once; it picks the sign the early rows favoured and applies it
to every world. The multi-world creature is the mixture case for real, and the fix is not
another expert but a sense that says which world it is in, and an interaction between that
sense and the hostile's distance -- which the residual search can find if the sense exists.

**With the world flags.** Three seeds each; the check is 30 duels, 30 forage matches, 30 sheep
minutes:

```
                                   arena (wins)        forage (eaten)   sheep (harm)
  flags + residual search  seed 1  151, 24 of 30       18.4             30.7
                           seed 2  149, 25 of 30       0.2              3.7
                           seed 3  0, 2 of 30          0.1              3.8
  flags + vague instincts  seed 1  139, 12 of 30       18.6             29.9
                           seed 2  31, 0 of 30         17.4             31.1
                           seed 3  148, 17 of 30       18.0             31.1
```

Two of three worlds per seed, never all three: the ones that forage and fight charge the wolves;
the ones that flee the wolves flee the bot and the switch. The arena numbers are the best duels
of the session -- 24 and 25 wins of 30, from a creature that also solves the puzzle -- so the
shared layout is not the limit. What is missing is the one interaction "hostile distance,
inverted in the sheep field", and neither the free search nor the vague instinct produced it in
900 episodes. Testing a precise instinct that declares it.

**The precise instinct** (the sign of hostile distance declared per world, at confidence 50):
seeds 1 and 2 fight (12 and 15 wins) and forage (19 a match) and still charge the wolves
(harm 31); seed 3 flees everything. The free search, reported, acquired nothing about the
worlds: its pairs are about hazards and bearings. So the sign of distance was not the missing
piece. The missing piece is the options' own weights: "target the hostile and approach" earns
a large constant from the arena rows, and that constant is not gated by world, so in the field
the creature approaches the wolf because approaching has always paid. What the three-world
creature needs is option weights per world -- the option blocks of wave 3, which taxed the
arena when spread over twelve senses, restricted to the three world flags: 63 features that
say what each option is worth here.

**Three fixed experts in the three worlds:** seeds 1 and 2 fight (13 and 8 wins) and forage
(17-18) and charge the wolves (harm 31); seed 3 flees everything. Same two-of-three as one
model; the experts did not split by world. (The nearest-rows chooser gave results identical to
the recent-error one, which means it never ran: its row buffer was switched off by an
ordering bug in the constructor. Fixed and rerunning.)

**Grown experts** (one at birth, a copy spawned on a break, cap four): all three seeds grew to
four and switched between them thousands of times. Sheep 3.1, 2.1, 2.5 harm a minute on every
seed (the first creature to flee wolves on all seeds), forage 3.6, 17.1, 3.0, arena 0 wins on
all three. A different two-of-three: the experts kept the fleeing and the foraging and lost the
fight, and a chooser that switches six thousand times in nine hundred episodes is not choosing
a world, it is thrashing on noise. The gate needs to be slow and sticky, and the experts need
to own their worlds, which is what the per-world option weights say more directly.

**Option weights per world** (each of the 21 options gets its own weight over the three world
flags: 63 more features), three seeds, 900 episodes:

```
  seed 1   arena dealt 73, 2 wins     forage 18.9    sheep 1.3
  seed 2   arena dealt 135, 19 wins   forage 0.1     sheep 3.3
  seed 3   arena dealt 107, 2 wins    forage 18.4    sheep 5.1
```

Seeds 1 and 3 are the first creatures that do all three: they solve the puzzle, they flee the
wolves as well as the sheep specialists did, and they fight, if not yet well. The missing piece
was exactly the options' constants: with "approach" allowed a different worth in each world,
the creature stops carrying the arena's lessons into the field. Three worlds cost 900 episodes
where one costs 300, so the arena is under-trained here; a longer run is going.

**Sticky grown experts** (the chooser decides every 200 thinks): seed 1 grew one expert and
kept two worlds (21 wins, forage 18.5, wolves charged); seed 2 grew to four and does all three
weakly (8 wins, forage 8.4, sheep 4.4); seed 3 flees and half-fights. **Fixed three experts
with the nearest-rows chooser, now running:** seed 1 won 29 duels of 30, the best duel of the
session by far, and foraged 17.9, and charged the wolves, switching experts seven thousand
times. So far the experts, fixed or grown, reach two worlds and sometimes a weak third; the
per-world option weights reach all three on two seeds of three. The blocks are cheaper and
say the same thing more directly: what an option is worth depends on where you are.

Fixed three experts with the nearest-rows chooser, all seeds: seed 1 won 29 duels of 30 and
foraged 17.9 (wolves charged); seeds 2 and 3 do all three weakly (7 and 5 wins, forage 3.1 and
12.1, sheep 2.9 and 6.9). With the chooser reading the memory rather than the recent error,
the experts do split by world sometimes. Testing the two together: per-world option weights
and the experts.

**Per-world option weights, six seeds:**

```
  seed   arena (dealt, wins of 30)   forage (eaten)   sheep (harm)
  1      73, 2                       18.9             1.3
  2      135, 19                     0.1              3.3
  3      107, 2                      18.4             5.1
  4      43, 1                       9.2              1.8
  5      136, 13                     7.3              2.4
  6      116, 23                     19.4             1.2
```

Five seeds of six do all three worlds; seed 6 does all three well -- 23 duel wins, 19 meals,
wolves at 1.2 a minute -- from one mind of 117 plus 63 features, in 900 episodes split three
ways. The three-world creature is the general one: the shared entity layout reads any world,
the per-context option weights let the same options mean different things in different
places, and everything else is unchanged.

Per-world weights at 1800 episodes: all three seeds do all three worlds (forage 17.6-18.7,
wolves 2.0-2.9, duels 4, 6, 6 wins with 51-132 dealt). Consistent, and the duel side does not
improve with the extra episodes: a duel learned from birth without an opponent model sits at
its plateau, as it did in the duel-only harness. Per-world weights plus three experts: 21, 5, 6
wins, forage 0, 0.4, 13.7, wolves 3.5, 0.9, 1.4 -- the experts add nothing to the weights and
cost the puzzle on two seeds. The general creature is the per-world weights alone; the next
thing it lacks is what the duel lacked, a model of its opponent.

## 57. The general creature

Per-world option weights plus the opponent model (the hazard tier predicting the bot's parry
and shot), one mind in three worlds, 900 episodes drawn at random, three seeds:

```
  seed   duels (dealt, wins of 30)   forage (eaten a match)   sheep (harm a minute)
  1      110, 12                     19.2                     1.9
  2      154, 27                     16.9                     2.9
  3      96, 13                      18.2                     1.2
```

Every seed does all three, and does them about as well as the specialists did each alone
(the forage specialists 18-19; the sheep specialists 1.8-3.5; the duel with the opponent model
in its own harness a mean of 13.5 wins). One mind of 180 features, 0.5 ms a think, from
scratch in 900 episodes with a third of them in each world. What made it: the shared entity
layout to read any world, option weights per context so the same options can mean different
things, and a model of the specific opponent where one matters.

**Health-dependent caution** (the taken weight times 1 + k(1 - health)): k=2: 438, 382, 305 =
1125; k=4: 419, 354, 553 = 1326; base 1852; no team wins. A creature that grows cautious as it
is hurt fights less and wins less, by every measure this arena has; it would show its worth
only where survival is counted and it is not the thing being scored here. The mechanism costs
nothing and works as designed; the arena does not reward it.

## 58. A library of specialists does not help the general creature

Three worlds, one mind, same slot senses. The three specialists (arena-only, forage-only, sheep-only creatures) were
distilled into a library and the general creature valued each option by the best of the library (GPI).

| variant, 3 seeds | arena wins of 30 | forage meals | sheep harm a minute |
|---|---|---|---|
| per-world option weights only (section 56/57) | 12 / 27 / 13 | 17–19 | 1.2–2.9 |
| library alone | 2 / 0 / 0 | 6.7 / 8.2 / 10.3 | 11.6 / 5.5 / 11.9 |
| library + per-world weights | 26 / 18 / 0 | 10.6 / 10.8 / 9.2 | 2.9 / 3.0 / 3.5 |

The library's best-of value is over-optimistic (the max of three noisy specialists picks whichever is wrong upward), so
it wrecks the forage and sheep worlds and even the arena unless the per-world weights are there to mask it. Kept off.
Critique A's "successor features + GPI" is therefore not a win here either: the general creature already learns
all three worlds from one model, and a library only adds a max over errors.

## 59. Shared dynamics with per-option residuals loses

Critique B's cheapest structural idea: one dynamics model shared by every option (trained on every row), plus a
small diagonal residual model per option. Arena curriculum, sums of the four learners' damage a match, 3 seeds:

| variant | seed 1 | seed 2 | seed 3 | total |
|---|---|---|---|---|
| per-option effects (default) | | | | 1852 |
| shared dynamics + residuals (ESHARED) | 476 | 510 | 524 | 1510 (−18%) |

The wins fell too (1 / 0 / 4 of 30). The shared model absorbs the average of all options, which is the wrong physics
for each of them, and the diagonal residual cannot pull it back fast enough. The per-option effects already share
what matters through SHARE_E (the same effects models across creatures), so the "sharing" was there; what the
options need is their own curvature. Kept off. Thinking cost was unchanged (~700–770 us a think).

## 60. The attention gate with the readings' errors as features

The attention model (THINK_META=0.5) predicts the gain of a big think from the senses, how long the last picks were
held, and the last gain. Critique B suggested it should also see how wrong each reading's prediction has been lately.
Arena curriculum, 3 seeds, sums of the four learners' damage:

| gate | total | held ticks | wins of 30 |
|---|---|---|---|
| gate 0.5 | 495 / 595 / 616 = 1706 | 51–57% | 0 / 1 / 3 |
| gate 0.5 + readings' errors | 300 / 634 / 485 = 1419 | 63–72% | 0 / 6 / 3 |

With the errors it holds more (which is the cheaper behaviour) but one creature collapsed (4 damage a match on seed 1)
and the total fell 17%. The error features make the gate hold longest exactly when the model is wrong, since a high
recent error tends to predict a low gain from a re-think (the re-think was also wrong), which is backwards. Kept off.

## 61. Spawning from the source's whole outcome model (weights and full covariance)

Instead of the distilled file (a hundred weights at confidence 50, plus declared pair features, effects priors and
memories), the spawn was given the source creature's whole outcome model: its weights and its full 123×123 covariance,
divided by a strength. Arena curriculum, seeds 4–6, sums of the four learners' check damage:

| start | seed 4 | seed 5 | seed 6 | mean | wins of 30 |
|---|---|---|---|---|---|
| blank + curriculum (section 45) | 625 | 526 | 566 | 572 | 7 / 2 / 4 |
| distilled file, confidence 50 (section 45) | 815 | 736 | 742 | 764 | 17 / 18 / 15 |
| whole model, strength 0.1 | 641 | 597 | 618 | 619 | 5 / 2 / 8 |
| whole model, strength 1 | 654 | 603 | 650 | 636 | 8 / 4 / 9 |

The whole covariance is a weaker start than the distilled file. It carries the source's certainty about every feature
including the ones that were noise to it, so the spawn spends its early matches unlearning; the distilled file only
carries the weights that mattered, the pair features that were acquired, the effects priors and the memories. The
covariance is not what makes a creature. Storage: keep saving the distilled form (<100 KB), not the 3.7 MB brain.

**File plus covariance.** Giving the spawn the distilled file *and* the source's whole covariance (seeds 4–6):
603 / 609 / 589, mean 600, wins 2 / 4 / 4 of 30 — below the file alone (764) and no better than the covariance alone
(636). The source's certainty is the harmful part: it stops the spawn from moving the weights it was handed.

## 62. The A/b split: pooling the covariance, and rebirth that keeps it

A pasted critique proposed splitting the model into the covariance (which situations were seen) and the weights
(what was concluded), pooling only the covariance across creatures, and on rebirth keeping the covariance and
wiping the weights. Its falsifiable claim: covariance-pooling would beat both no pooling and full pooling.
Arena curriculum, 3 seeds, sums of the four learners' damage:

| arm | seed 1 | seed 2 | seed 3 | total | vs baseline |
|---|---|---|---|---|---|
| no pooling (baseline) | | | | 1852 | |
| covariance pooled, private weights | 116 | 444 | 313 | 873 | −53% |
| covariance pooled at a tenth | 577 | 430 | 563 | 1570 | −15% |
| fully pooled (every creature learns every row) | 522 | 590 | 110 | 1222 | −34% |
| rebirth: keep covariance, wipe weights | 539 | 525 | 458 | 1522 | −18% |
| rebirth: keep covariance ×10, wipe weights | 629 | 483 | 557 | 1669 | −10% |

The claim failed in the direction predicted as its failure mode: a pooled covariance is a geometry none of the four
inhabits, and it makes each creature confident about directions it never visited, so its own rows move it too
little. Pooled at a tenth it merely loses less. Keeping the covariance on rebirth has the same problem: a wiped
creature with a tight covariance relearns slowly, not quickly; loosening it tenfold recovers most but not all of
the full reset. The full reset stays. The critique's general point (conclusions are world-specific, geometry is
not) may still hold across worlds; on one arena the geometry is exactly what each creature must own.

## 63. Generated worlds: measuring learning, not skill, and the first transfer result

`tabgen.lua` draws a world from a seed: whether a hostile, an item and a hazard exist, how they move (chase, orbit,
turret, flee, wander; drifting or homing hazards; items that respawn, drift, or need a switch), how hard they hit,
act ranges and cooldowns, arena size, episode length. Every world is read through the same slot senses and acted on
through the same choices, with no world flags. Each world comes with a random policy and a greedy policy that knows
the rules; the creature's score is rows-to-threshold, the rows before its rolling ten-episode score reaches halfway
from random to greedy. Worlds 18, 20, 24 and 28 are held out: never tuned on, only scored.

Newborn creatures (150 episodes, one world each): threshold reached on 7 of 12 worlds, between 3,300 and 18,400
rows; never on worlds 5, 13, 14, 18, 28 (the ones with a switch, a shooting turret, or a fast wanderer).

**Transfer.** A creature trained for 400 episodes on eight other worlds, then dropped into a held-out world:

| held-out world | newborn: rows to threshold, last-10 score | after 8 worlds: rows to threshold, last-10 score | greedy |
|---|---|---|---|
| 18 turret that parries and shoots, item, hazard | never, 2 | 4,200, 206 | 285 |
| 20 shooting turret, drifting item | 9,600, 288 | 5,400, 824 | 640 |
| 24 drifting item that respawns | 12,000, 560 | 8,800, 550 | 554 |
| 28 slow chaser, item behind a switch | never, 26 | 3,300, 316 | 282 |

On every held-out world the travelled creature reached the threshold sooner and ended higher, and on two of the
four it ended above the greedy hand policy that knows the rules. This is the first number that speaks to the actual
goal (a system that learns new situations fast), and it is a win for carrying content across worlds that share
structure: the slot layout lets what was learned about "a hostile" or "an item" apply to the next world's hostile
or item. The pasted critique expected content transfer to be worth nothing off-world; here it was worth the
difference between never learning and beating the hand policy.

**Three seeds, four arms** (runs101; rows to threshold, median over the seeds that reached it; mean of the last ten
episodes over all three seeds; the first table above was a single seed and the run seed was accidentally the clock):

| held-out world | newborn | distilled file | method-only file | trained live on 8 worlds |
|---|---|---|---|---|
| 18 | 3/3 reached, 15,300 rows, 145 | 2/3, 10,350, 142 | 1/3, 3,900, 120 | 2/3, 4,200, 138 |
| 20 | 3/3, 6,300, 717 | 2/3, 7,500, 676 | 2/3, 15,750, 638 | 3/3, 3,000, 866 |
| 24 | 2/3, 10,800, 373 | 2/3, 15,600, 373 | 2/3, 10,800, 363 | 2/3, 10,000, 373 |
| 28 | 1/3, 7,500, 192 | 2/3, 24,300, 133 | 1/3, 5,400, 154 | 2/3, 3,000, 286 |

Sober version of the single-seed result: a creature carrying live weights from eight other worlds reaches the
threshold in two to three times fewer rows when it reaches it, and ends higher on two worlds, but it collapses on a
seed just as newborns do (one seed in three never learns a world). The distilled file and the method-only file are
no better than a newborn here: forty weights at confidence 50 per reading are the arena's way of carrying content,
and five acquired pair features are too little method to matter. The reliability problem (a seed that never
learns) is the bigger loss than the speed, and it is the problem rebirth solved on the arena; tabgen has no rebirth.

**Rebirth below random** (a world-independent rule: after every 20 episodes, if the rolling score is below the
random policy's, forget the conclusions): no change. It fired one to four times on the collapsed seeds of worlds 24
and 28 and they stayed collapsed, so those failures are not false early conclusions; the creature never finds the
behaviour at all (a slow creature and a drifting item on a small map). That is an exploration failure.

**Twenty exploration episodes instead of five**: worse on every held-out world (world 20: 1/3 reached and 228
against 717; world 24: 184 against 373). Random rows are not exploration; they teach the creature that nothing it
does matters, and it takes longer to unlearn that than the five-episode start costs.

## 65. Transfer against training variety

Same 400 training episodes spread over 4, 8 or 16 worlds, then a held-out world (2 seeds for 4 and 16, 3 for 8):

| held-out | newborn | 4 worlds | 8 worlds | 16 worlds |
|---|---|---|---|---|
| 18 | 15,300 rows, 145 | 3,600, 222 | 4,200, 138 | 3,600, 222 |
| 20 | 6,300, 717 | 3,150, 713 | 3,000, 866 | 4,500, 878 |
| 24 | 10,800, 373 | 9,200, 491 | 10,000, 373 | 8,800, 536 |
| 28 | 7,500, 192 | 3,450, 288 | 3,000, 286 | 3,000, 186 |

Every travelled creature reaches the threshold in two to four times fewer rows than a newborn and usually ends
higher; how many worlds it travelled makes no visible difference at this budget. What transfers is having lived in
any world with the same slots: the weights on "the item is there and near" and "the hostile is closing" are the
same weights everywhere. Variety past four worlds is not the resource at 400 episodes; rows in the new world are.

**Uncertainty bonus (set OMECTAU) on the held-out worlds**: world 28 went from 1/3 to 3/3 reached (326 against
192), but worlds 20 and 24 collapsed (350 against 717; 0/3 reached against 2/3). The bonus keeps the creature trying
options whose value is uncertain, which finds the switch on world 28 and keeps it from ever settling on the
drifting item of world 24. A net loss as a default, as it was on the arena.

## 66. Vague instincts on the held-out worlds

A ten-line file of world-independent instincts at confidence 2 (toward food, away from hazards, toward the hostile
and hit it), given to newborns on the held-out worlds, 3 seeds:

| held-out | newborn | with instincts |
|---|---|---|
| 18 turret that parries and shoots | 3/3 reached, 15,300 rows, 145 | 0/3, never, 41 |
| 20 shooting turret, drifting item | 3/3, 6,300, 717 | 2/3, 7,350, 643 |
| 24 drifting item | 2/3, 10,800, 373 | 3/3, 16,800, 500 |
| 28 slow chaser, switch | 1/3, 7,500, 192 | 3/3, 3,900, 348 |

The food and hazard instincts fix the two worlds where newborns collapsed (every seed now learns them). The
"approach the hostile and hit it" instinct is fatal on the two turret worlds: a turret with 150 hp that parries and
shoots is not something to approach, and the instinct held at confidence 2 takes the creature many rows to unlearn
while it dies at the turret's feet. Next: the file without the hostile lines.

**Files carrying all weights** (top 500 instead of 40) at confidence 10 and 50, spawned on the held-out worlds:
confidence 10 lost everywhere (98 / 452 / 193 / 153 against 145 / 717 / 373 / 192); confidence 50 won world 18
(3/3 reached, 4,500 rows, 185) and lost the other three. Neither is the transfer that live weights give; a file
resets the covariance, and the spawn re-learns the geometry from scratch while trusting stale conclusions.

**Food-and-hazard instincts only** (the same file without the hostile lines): no help anywhere (178 / 601 / 364 /
93). So the earlier gain on worlds 24 and 28 with the full file was seed noise, not the instincts. Instinct files at
confidence 2 do not move the held-out worlds either way; what they cannot fix is what follows.

## 67. What a collapsed seed actually does

World 24 (a drifting item that respawns, slow creature), seed 3, watched episode by episode:

```
 ep  score eaten | target=item approach hold | mean item dist | w(eaten, itemdist)   rows
  1   120    6   |   57%        18%     24%  |    16.5        |   -1.97              800
  5    20    1   |   53%        21%     18%  |    13.5        |   -1.28             4000
  6    20    1   |   87%         6%      2%  |    26.1        |   -0.83             4800
  7     0    0   |  100%         0%      0%  |    32.1        |   -0.77             5600
 40     0    0   |  100%         0%      0%  |    28.3        |   -0.50            30400
```

Seed 1, same world, is at 28 meals an episode by episode 12 with approach at 100%. The collapsed creature knows the
right thing (its value model says a near item means eating: the itemdist weight is negative from the first episode)
and it targets the item every tick. What it never does after the five random episodes is choose *approach*. The
move it takes is judged by the effects tier: each move option has its own model of what it does to the senses, and
that model only learns from ticks on which the move was chosen. Five random episodes gave "approach" too few rows
on this seed, its predicted effect on the item's distance stayed near zero, so the planner saw no reason to pick it,
so it never got another row. A behaviour that is never tried is never learned, and nothing in the creature says
"try what you have not tried". The value is not the problem; the physics of an untaken option is.

Fixes being tested, all world-independent: a bonus for options taken rarely (UCB), a small lifelong chance of a
random combination (EPS 2% and 5%), and a physics instinct ("approach closes the distance to the target").

**Results of the three fixes** (3 seeds; the EPS arm was invalid the first time, the knob was overwritten, rerunning):

| held-out | newborn | untried bonus 0.5 | untried bonus 2 | physics instinct |
|---|---|---|---|---|
| 18 | 3/3, 15,300, 145 | 1/3, 4,200, 102 | 1/3, 7,500, 85 | 2/3, 10,200, 124 |
| 20 | 3/3, 6,300, 717 | 1/3, 7,500, 452 | 2/3, 5,550, 512 | 3/3, 4,200, 920 |
| 24 | 2/3, 10,800, 373 | 3/3, 9,600, 511 | 3/3, 9,600, 531 | 1/3, 9,600, 194 |
| 28 | 1/3, 7,500, 192 | 1/3, 4,800, 136 | 1/3, 5,100, 148 | 1/3, 7,500, 163 |

The untried-option bonus fixes world 24 (every seed learns it now, and higher) and costs the three others, where
keeping on trying bad options against a turret is expensive. The physics instinct wins world 20 (920, above the
greedy policy) and loses world 24, the world it was written for. Neither is a default yet; weaker bonuses are running.

**The diagnosis above was wrong, and the trace that corrects it.** With the physics instinct loaded, the failing
seed behaved identically, and printing the approach option's effects model showed it well learned (700 rows, the
right sign). What the creature does from episode 6 is *orbit* 100% of the time, at 25–35 units from the food:

```
 ep  score | moves: hold appr retr orbit centre | option flags' weight in the eaten model
  5    20  |  18%  21%  22%  19%   18%          |  -0.00 -0.00 -0.01  0.04  0.01
  6    20  |   2%   6%   0%  88%    2%          |  -0.02 -0.02 -0.02  0.08  0.00
  7     0  |   0%   0%   0% 100%    0%          |  -0.02 -0.02 -0.02  0.08  0.00
 40     0  |   0%   0%   0% 100%    0%          |  -0.02 -0.02 -0.02  0.06  0.01
```

The value model has a direct weight on each option's flag as well as on the senses. In the five random episodes
orbit happened to precede a few meals, so its flag earned +0.08 (×20 for the eaten preference = 1.6 points), more
than the projected gain of approaching (a small predicted fall in item distance times a weight of −0.7 times 20).
Once orbit is chosen every tick its flag is always 1, indistinguishable from the constant, so the rows can never
correct it; and the other flags get no rows at all. A spurious option preference locks itself in. This is not an
exploration failure and not a physics failure; it is the flag terms.

Two fixes, both world-independent, on the same seed: **NOFLAG** (no option flags in the value; an option is judged
only by its predicted consequences) gives 76% approach from episode 6 and 16–26 meals; **FLAGDECAY=0.002** (the
flag weights decay toward zero each row unless the rows keep supporting them) recovers by episode 10 and reaches
23 meals. Running on all held-out worlds and on the arena.

**Lifelong randomness (2%, 5%) and weaker untried-option bonuses (0.1, 0.2)**, once the knob actually applied:
no consistent direction on any world (eps 2%: 94 / 922 / 194 / 235 against 145 / 717 / 373 / 192; bonus 0.2:
128 / 941 / 435 / 269). Each helps one world and hurts another. Consistent with the corrected diagnosis: the
failure is not a lack of trying, so more trying only adds noise.

**Both fixes lose everywhere else.** Held-out worlds, 3 seeds (mean final): no flags −3 / 118 / 300 / 157 against
145 / 717 / 373 / 192; decay 0.002: 82 / 384 / 231 / 128 (more seeds reach the threshold, lower ceilings); decay
0.0005: 60 / 638 / 261 / 201. On the arena both are catastrophic: 78–140 damage for the four against 1852. The
option flags carry most of what the arena creature knows (that a melee lands is not something the projected senses
say; the flag says it), and on the held-out worlds a flag that fades is a flag that cannot hold a real preference.
The lock-in is real on the one seed, but removing the flags costs far more than it saves. Next: keep the flags but
make them harder to earn from a handful of random rows (a tighter starting covariance on the flag columns), and
the uncertainty bonus at a third of its strength, which is the principled answer to a flag no row can falsify.

**Tighter flag start and weaker uncertainty bonus** (held-out worlds, 3 seeds, mean final; arena total of 3 seeds):

| arm | 18 | 20 | 24 | 28 | arena |
|---|---|---|---|---|---|
| newborn | 145 | 717 | 373 | 192 | 1852 |
| flag ridge 20 | 73 | 658 | 100 | 39 | 1479 |
| flag ridge 100 | 84 | 490 | 561 (3/3) | 278 | 1647 |
| uncertainty bonus 0.3 | 135 | 350 | 20 | 326 (3/3) | |

Flag ridge 100 fixes world 24 outright and lifts 28, loses 18 and 20 and 11% of the arena. The uncertainty bonus
at any strength fixes 28 and destroys 24. Every fix so far trades worlds; none is a default. With three seeds and
finals that swing threefold between seeds of the same arm, the benchmark cannot resolve a 30% effect, so the next
step is more seeds on the one candidate that did not lose the arena much.

**Nine seeds: flag ridge 100 is not a fix.** Newborn against flag ridge 100, mean final over 9 seeds: world 18
187 vs 115, world 20 704 vs 583, world 24 314 vs 322, world 28 207 vs 229. The three-seed gains on 24 and 28 were
noise. Off. What nine seeds do show clearly is that the collapse is a coin flip decided in the first episodes:
world 24's finals are 16, 18, 22, 26 and then 532–570, nothing between; world 20's are 215–325 and then 904–948.
A newborn either locks in or does not, and the flags' starting covariance does not change the odds.

**Sampled flags (Thompson)**: a disaster at both strengths (held-out finals 42–180 against 187–704; arena 186–309
of 1852). The noise is scaled by the flag's covariance times the preference, and for a flag that is always on the
covariance never shrinks, so the creature never stops dithering. Off.

**Significance-gated flags** (next): keep every flag weight, but count it in a decision only when it is larger than
FLAGSIG standard deviations of its own uncertainty (the covariance diagonal times the reading's residual variance).
A flag no row can falsify has a large uncertainty and is ignored, so the decision falls to the consequences; the
arena's flags, with thousands of rows behind them, pass the gate untouched.

**Significance-gated flags**: removes the collapses and the successes alike. Six seeds, mean final: 54 / 228 / 138
/ 76 against the newborn's 187 / 704 / 314 / 207, with every seed landing in a narrow band a third of the way up;
arena 114–230 of 1852. Any attenuation of the option flags (removal, decay, tighter start, sampling, gating) costs
far more than the lock-in it prevents. The flags *are* the creature's policy memory; one-step consequences alone
cannot carry a policy. The fix has to be in the data the flags are fit to, not in how they are read.

## 68. The reliability fix: rebirth that explores again

The below-random rebirth rule did nothing earlier because a reborn creature went straight back to choosing greedily
on empty weights, and locked in again at once. With the five exploration episodes repeated after each rebirth
(REBIRTH_BELOW_RANDOM=1 REEXPLORE=1), checked every 20 or every 10 episodes, six seeds on the held-out worlds:

| held-out | newborn (9 seeds) | rebirth + re-explore, every 20 | every 10 |
|---|---|---|---|
| 18 | 9/9 reached, 187 | 6/6, 175 | 6/6, 178 |
| 20 | 7/9, 704 | 6/6, 804 | 6/6, 789 |
| 24 | 5/9, 314 (four seeds at 16–26) | 5/6, 456 | 6/6, 551 (all seeds 532–588) |
| 28 | 4/9, 207 | 4/6, 265 | 5/6, 303 |

World 24's coin flip is gone: every seed learns it. World 28 goes from under half to five of six. World 20 loses its
low seeds. World 18 is unchanged (one seed at 4 on both: its rolling score is not below random, so the rule never
fires; a different failure). The rule is world-independent: it needs only the random policy's score as a floor,
which any world can measure by running a few random episodes. It is the same mechanism that won on the arena
(section 45): a bad early draw is not repaired by more rows, it is repaired by throwing the dice again, and the
throw has to include the exploration that seeded the draw. Every-10 is the setting.

**Arena: random matches after a rebirth** (REEXPLORE=3 and 8, curriculum, 3 seeds): 1519 and 1550 against 1852.
On the arena a reborn creature has teammates and a curriculum to learn from, and random matches only cost it
ground. The re-explore rule stays a rule for a creature alone in a new world, not for the arena.

## 69. The port

`C:\Roblox Packages\Instinct\mind\` — RLS.luau, Mind.luau (the OMECA(H) mind: outcomes, memory, effects, couplings,
acquisition, hazards; knowledge files; distill; save/load with diagonal covariances), Senses.luau (the slot
layout), Coach.luau (exploration at birth, rebirth-below-random with re-exploration). Nothing that lost is carried
over. `scripts/mind.luau` runs it headless in the prototype's world 2 / world 24 for a check against the numbers
above.

**Two-step lookahead on the held-out worlds** (PLAN2=max, 6 seeds, mean final): 188 / 818 / 274 / 221 against the
newborn's 187 / 704 / 314 / 207. A win on world 20, a loss on 24, noise elsewhere; not a default.

**Port check (Lune, `scripts/mind.luau`).** The Luau mind in the prototype's world 2 reaches the threshold at
episode 14–15 (4,200–4,500 rows) and ends at the greedy policy's level (216–220 of 220–234), the same pace as the
LuaJIT prototype. On world 24 with the seed that collapsed in the prototype it reaches the threshold at episode 11
and ends at 658 of 680. A think costs 115–132 us under Lune. A creature saved as plain data (weights and covariance
diagonals) and reloaded scores the same as before it was saved (232–236 and 624). The port is faithful.

**Sticky exploration** (STICKY=0.9: while exploring, hold the last random combination another tick with chance
0.9). Needed in the Roblox room: a body whose drive is re-rolled ten times a second jitters in place and never
finds a meal, and with the hold it crosses the room at full speed. On the prototype's held-out worlds it is not a
win: alone it loses (76 / 566 / 458 / 152 against 187 / 704 / 314 / 207), and with the rebirth rule it is level
with the rebirth rule alone (156 / 916 / 489 / 287 against 178 / 789 / 551 / 303). The prototype's creature turns
to face before it moves, so its random walk covered ground anyway. Sticky stays on in the port (physical bodies)
and off in the prototype.

**First creature in the room (Studio, trial "Learned").** Thirty-five slot senses, ten combinations, one reading
(meals, worth 20), a decision every tenth of a second, windows of 30 seconds, five random windows first. The random
windows scored 92 a window on average (the floor). The first learning window scored 380 (19 meals), with the creature
approaching the food continuously; 266 us a think in Studio, 137 memories, no rebirth needed.
Windows 6–9 scored 380, 320, and 320 again by window 9 (106 meals in all, rolling 204 against the random floor of
92), approaching without a break, 222 us a think, 200 memories (the cap), no rebirth. The room is solved in the
first learning window; the rest is holding it.

## 70. Horizons and the discounted return

Longer fixed horizons on the held-out worlds (6 seeds, mean final; newborn is 24 ticks = 2.4 s):

| horizon | 18 | 20 | 24 | 28 |
|---|---|---|---|---|
| 24 (newborn) | 187 | 704 | 314 | 207 |
| 48 | 96 | 574 | 381 | 123 |
| 72 | 95 | 395 | 295 | 309 |
| 72, discounted 0.97 a tick | 120 | 318 | 250 | 163 |

A longer wait credits every option with whatever happens later regardless of what it did, and the added variance
costs more than the added reach buys; only world 28 (the switch world, where the payoff is genuinely far away)
gains from 7.2 s. The cliff at 2.4 s is not what limits the creature. The bootstrapped return (the increments up
to the horizon plus the discounted predicted value of the state reached, so every later reward counts with no
cliff) is running.

**Bootstrapped discounted return** (BOOT=1: increments to the 2.4 s horizon plus the discounted predicted value of
the state reached, under the best combination there; 6 seeds, mean final against the newborn's 187 / 704 / 314 / 207):
discount 0.97 a tick, 90 / 552 / 254 / 160; discount 0.95, 99 / 775 / 365 / 122. The infinite reach helps the two
item worlds a little at 0.95 and hurts the turret world and the switch world at both rates. A bootstrap adds the
model's own error to every target, and early in life that error is most of the target. Not a default; the fixed
short horizon with the memory of surprises carrying the long consequences remains the best-measured setting.

**Repackaged (0.5.0).** `mind/` is now the package itself: default.project.json points at it, wally includes it,
README and CHANGELOG describe it. The 0.4.0 `src/`, the `next/` rebuild, its docs, tests and scripts are in
`attic/` (kept on disk because most of it was never committed; the user said nobody uses them). In the test
place the new tree is `ReplicatedStorage.Instinct`, "Learned" is the only trial, and the old package copy,
species and trials are in the place folder's own `attic/`.

## 71. Cost in Studio, and what native code generation buys

Profiled inside Studio (Server datamodel, the room's creature: 35 senses, 10 combinations, F = 78 with couplings):

| | interpreted | `--!native` on RLS.luau and Mind.luau |
|---|---|---|
| one outcome update (F = 78) | 290 us | 121 us |
| settle, one tick, with couplings | 1,770 us | 533 us |
| settle, one tick, no couplings | 460 us | 182 us |
| think, with couplings | 68 us | 38 us |
| think, no couplings | 12 us | 16 us |

Learning, not thinking, is the cost: a settle is 10–30 thinks. The couplings tier is two thirds of every settle
(a 35-output model updated every tick) and half of every think, and it has no measured value on the held-out
worlds (running). Native code generation is active in Studio only after the place re-syncs in edit mode; a pure
loop probe showed 3.0x, the mind 3.3x on settles. Per creature at ten decisions a second, native, no couplings:
about 2 ms of CPU a second, so a hundred creatures cost a fifth of one core before error-gated learning and lazy
effects outputs (both running on the held-out worlds) and before parallel actors.

## 72. Many acts: descriptors against private flags

`tabacts.lua`: a chasing hostile and K generated acts (variants of strike, shot, heal, dash with their own range,
damage, cooldown, healing), score = dealt − taken, 150 episodes, 3 seeds. The value model reads an act through its
descriptor (8 graded numbers, plus their interactions with every sense) as well as its private flag; with
DESCR_LEARN the descriptor takes gradient steps on the act's own rows.

| acts | private flags | authored descriptors | authored + revised | unlabelled, learned from zero | greedy |
|---|---|---|---|---|---|
| 8 | −71 | −25 | 68 | 160 | −88 |
| 32 | −101 | −30 | 5 | −114 | −59 |
| 100 | 182 | −48 | 306 | 205 | 177 |

Revisable descriptors beat private flags at every size and beat the greedy policy at 100 acts (the creature found
the best damage-per-cooldown strike among a hundred and used it 131 times). Fixed authored descriptors are worse
than revised ones everywhere: a tag the creature cannot change is a liability, as the user said. Unlabelled acts
learn descriptors from zero at 8 and 100 acts but not at 32. A sparse fifty-tag vocabulary (ten tags an act,
interactions with nine senses, 616 inputs) was poor on its first seeds and costs four times the think time; the
compact graded descriptor is the better shape. Think cost with descriptors at 100 acts: about 1.1 ms in LuaJIT
(800 combinations), so a creature should hold a dozen acts, not a hundred; the vocabulary can be hundreds.

**Lazy effects outputs** (EMASK=learn: an effects model fits only the outputs it already explains, the rest every
tenth row): worse on every held-out world, 6 seeds (153 / 553 / 191 / 166 against 187 / 704 / 314 / 207). An
output the model does not yet explain is exactly the one that needs the rows. Off.

**`const` locals** (a keyword this Studio build accepts): the probe loop ran 83 us plain, 74 us with const, 31 us
native, 29 us native with const. A tenth alone, nothing on top of native code generation. Native is the lever.

**Fifty-tag vocabulary, three seeds** (ten tags an act, interactions with nine senses): 48 / −75 / 103 at 8 / 32 /
100 acts against 68 / 5 / 306 for the compact learned descriptor and −71 / −101 / 182 for flags, at 567 / 1,068 /
1,573 us a think against 461 / 636 / 1,103. Better than flags at 8 and 32 acts, worse than the compact descriptor
everywhere and dearer. A sparse tag set is a fine authoring format; what the model should see is a short graded
descriptor derived from it (range, damage, cooldown, healing, kind), which the creature then revises.

**Couplings, timers and error gating** (held-out worlds, 6 seeds, mean final; the newborn baseline is OMECTA):

| set | 18 | 20 | 24 | 28 |
|---|---|---|---|---|
| OMECTA (baseline) | 187 | 704 | 314 | 207 |
| OMECA (no timers) | 145 | 385 | 228 | 134 |
| OMEA (no timers, no couplings) | 106 | 491 | 198 | 62 |
| OMECTA + error-gated learning | 108 | 531 | 187 | 85 |

Two surprises. The timers tier, written for the arena (ticks until the zone arrives, the target's bearing and
distance trend since the last think), matters on the generated worlds even though its zone input is nonsense
there: what it carries is *trends*, the change of a sense since the last think. Dropping it costs more than
dropping the couplings. And error-gated learning (skip the update on rows already predicted within 2 points) loses
on every world: the rows the model predicts well are still the rows that keep it calibrated. Off.

Next: a generic trend tier (every sense's change since the last think, no model, no cost) in place of the timers,
with and without the couplings; if trends carry what couplings carry, the dearest tier goes.

## 73. Knowledge that crosses act sets

A creature trained on one set of 32 tagged acts (world 1) was distilled to tag-level priors only (`tagN`,
`tagN*sense`; its act flags name acts the spawn does not have and are dropped), and a spawn with a *different* set
of 32 acts (world 2) was given that file. 150 episodes, 3 seeds, final score (greedy −108 / 14 / −3):

| creature on the new act set | seed 1 | seed 2 | seed 3 | mean |
|---|---|---|---|---|
| newborn, private flags | 152 | 39 | 66 | 86 |
| newborn, tags | 8 | 186 | 314 | 169 |
| spawn with tag priors from the other act set | 140 | 110 | 300 | 183 |

The spawn is the only arm with no weak seed, and it beats the flag newborn twice over, on acts it has never seen,
from a source creature that was itself mediocre (its finals were −1, −108 and −116 on its own acts). Tag-level
knowledge is what a species file and a game-wide instinct file should be written in: it applies to any creature's
version of a strike or a heal, whatever the act's id. Private flags stay as a creature's own corrections.

**A generic trend tier** (TREND=1: every sense's change since the last think, times 5, as inputs; no model):

| set | 18 | 20 | 24 | 28 |
|---|---|---|---|---|
| OMECTA (baseline, arena timers) | 187 | 704 | 314 | 207 |
| OMECA | 145 | 385 | 228 | 134 |
| OMECA + trend | 134 | 538 | 371 | 175 |
| OMEA + trend (no couplings) | 148 | 369 | 108 | 160 |

Trends recover most of what the arena timers gave (and beat the baseline on world 24); couplings still matter on
top of trends (world 24 collapses without them). So the port gets both: the trend tier as the principled form of
the timers, and the couplings kept. The cost is inputs: F grows by one per sense for trends, which native code
generation makes affordable.

## 74. The Look room, instincts, and a drought drive

**Look trial (Studio).** Ten rays in a 120° fan, 80 studs; the item slot fills only while a ray sees the orb;
moves hold / forward / back and turn left / right. A newborn's random windows found one meal in five and the
greedy creature then pinned itself on a wall (three meals in six windows). Two additions, both world-independent:
a held exploration move is re-rolled when the senses have not changed since the last decision, and a nudge in any
phase (ten unchanging decisions in a row: try one other combination). With a game-wide instinct file (seeing food
is good, being near it better, forward at food, turn toward food: four priors at confidence 3 on three declared
pair features) the first greedy window scored 140 (seven meals) against a random floor of 4. Instincts set the
floor: born competent enough to find the orb, and everything after that is learning.

**A drought drive** (DROUGHT=k: a bonus for candidates whose projected effect changes the senses, scaled by how
long since the last gain, reset on a gain): held-out worlds, 6 seeds, mean final 50 / 559 / 265 / 143 at k = 5
and 158 / 652 / 202 / 154 at k = 20, against the newborn's 187 / 704 / 314 / 207. A loss at both strengths: the
prototype's creature already turns and moves enough to see change, and the drive only adds noise to the
comparison. The nudge (the zero-change case) stays; the graded drive does not.
By window 8 the Look creature scored 360 in a window (18 meals), 45 meals in all, seeing the orb on 41% of
decisions, 178 memories, no rebirth. Think cost in that room is 780–940 us before the effects cache (55 senses,
trends doubling the inputs, a beam of nine each re-predicting every option's effects); the cache computes each
option's predicted change once per think and sums, which the headless check confirms is behaviour-neutral.
Look, final: by window 15 the creature had 148 meals, a rolling score of 280 (14 meals a window) against the
random floor of 4, seeing the orb on 54% of decisions, 200 memories, no rebirth, 531 us a think with the cache.

## 75. Diet: the world owns the want

Three orbs (red, blue, green) and three body levels that drain at different rates; utility per colour is
−20·shortfall² below 1 and −5·excess² above; the trial hands the mind fresh preferences every decision (the marginal
worth of one more meal of each colour), and the mind's three readings (meals of each colour) are learned once from
the Look room's senses plus the three levels. Instincts: the forage file written once per colour. Random windows
averaged −38.8 utility; the second greedy window scored −1.0 (a perfect diet is 0): meals R5 B5 G6 by window 7,
the shortest colour pursued, an over-full colour worth −1.2 a meal and left alone. State-dependent wants need no
learning machinery at all: the value model is fixed knowledge of how to get each colour, re-weighed by the body.
Think cost 1.1 ms in that room (74 senses, trends doubling them, a beam of nine): the price of the ray fan.
Window 12: last window −0.4, meals R9 B11 G15, and with all three levels above 1 (R1.33 B1.25 G1.50, every colour
worth less than nothing) the creature holds and turns in place until the drain brings one back under: satiety
without a rule for it. Levels then hover between 0.95 and 1.35.
Seen in the Diet room: with all three orbs bunched on the far side and none in the fan, every "there" input is
zero, the move values are flag noise, "back" won by nothing, and the creature backed into a corner with all three
levels at zero until the drain made a colour worth enough that the fan eventually caught it. Two fixes: the nudge
now holds its random combination for a second instead of one decision (one decision handed straight back to the
same greedy choice moves nothing), and a look-around instinct (a small prior on turning, cancelled by a pair
feature the moment anything is in view) in the Diet and Look files.

**Diet-room cost.** 71 senses, trends and couplings: 220 value inputs. The couplings' predicted drift depends only
on the last change, so it was the same for every extension in a think and was being recomputed ten times (once per
beam candidate): cached once per settle, a think fell from 1,110 us to 189 (157 without couplings, 160 without
trends). The settle is now the cost, 2,250 us a tick, 1,150 of it the couplings model updating 71 outputs from 72
inputs every tick; the effects models take 149 inputs each. Testing: couplings updated every fourth tick, and
effects models fed the raw senses only.
Profiled in isolation in Studio (Diet senses, 3,000 ticks): think 430–525 us and settle 2,000–2,400 us a tick, flat
over time (memories 0, pending 24, recent capped at 1,500, F 220, heap 20–29 MB). Nothing in the mind grows; the
trial's rising lifetime average is the frame around it (raycasts, physics, collection pauses landing inside the
timed think). The honest per-creature cost of this room is ~2.8 ms a decision, 28 ms a second at ten decisions a
second, almost all of it learning, and it scales with the square of the sense count: the ray fan's forty numbers
are what make it dear. A fan of six rays with a colour code instead of three flags would be twenty numbers.

**Two learning-cost cuts, both losses** (held-out worlds, 6 seeds, mean final against 187 / 704 / 314 / 207):
couplings updated every fourth tick 134 / 322 / 257 / 170; effects models fed the raw senses only (no drift, no
trends) 112 / 472 / 110 / 112. The tiers want every row and every input. Cost is to be controlled by the sense
count (the mind's learning cost grows with its square) and the decision rate, not by starving the models.

## 76. Breaking the square: block-local models

The learning cost was the square of the sense count: one covariance over every input, effects models predicting
every sense from every input for every option, couplings predicting every sense from every sense. The structure
the senses already have (slots) is the answer: covariance is kept within a group (a slot's seven numbers, the self
readings, the option flags, the acquired inputs) and not across; each effects and couplings output is predicted
from its own group and the self group only. Cross-group facts that matter are what the acquisition search builds
as explicit pair features. Settle cost per decision in LuaJIT, full against block-local (BLOCKS=1):

| senses | full | block-local |
|---|---|---|
| 38 | 243 us | 83 us |
| 150 | 2,283 us | 527 us |
| 318 | 8,837 us | 1,210 us |

Linear now, about 4 us a sense a decision. Think cost is unchanged (it was already linear in the senses once the
effects were cached). Whether block-local learns as well as full is running on the held-out worlds.

**But block-local everywhere loses the learning** (held-out worlds, 6 seeds, mean final 37 / 628 / 164 / 77 against
187 / 704 / 314 / 207). The cross-group covariance carries something. Split next: effects and couplings local with
the outcome model full, and the outcome model local with the option flags kept in the self group's block (a flag
cut off from the bias cannot be told apart from it, which is the lock-in of section 67 built in).

**The splits** (held-out worlds, 6 seeds, mean final against the full model's 187 / 704 / 314 / 207):

| local models | 18 | 20 | 24 | 28 |
|---|---|---|---|---|
| outcome only, flags with the self group | 96 | 549 | 284 | 176 |
| effects and couplings only (outcome full) | 166 | 517 | 254 | 174 |
| both | 101 | 257 | 365 | 110 |

Every form of locality costs learning; effects-and-couplings local costs the least (about a sixth) and holds most
of the cost saving, since the effects models were most of the square. Next: effects local with the couplings
kept full, to see whether the couplings' cross-group terms are the part being missed.
Effects-and-couplings local, all six seeds: 166 / 517 / 214 / 154, a quarter below the full model on average.
Effects local with the couplings kept full: 94 / 685 / 132 / 61, no better. Cost on an idle machine, settle a
decision: 150 senses full 2,287 us, effects+couplings local 680; 318 senses full 8,537, effects+couplings local
2,507, of which the outcome model's own full covariance (F = 659) is most. Every locality costs a quarter or more
of the learning; the next idea keeps full covariance but only among what is present.

## 77. Full covariance among what is present: the sparse update

An input that reads zero contributes nothing to a row, and its weight does not move. The exact update still
touches its cross-covariance with everything present; the sparse update (SPARSE=1) skips it, keeping full
covariance among the inputs present together and nothing else. With empty slots encoded as all zeros (EMPTY0=1,
instead of "there 0, distance 2"), an absent slot costs nothing. Settle a decision, idle LuaJIT:

| senses (slots present) | full | sparse | sparse + local effects |
|---|---|---|---|
| 150 (4 of 20) | 2,220 us | 220 us | 437 us |
| 318 (4 of 44) | 8,627 us | 473 us | 1,047 us |

The cost is the square of what is present, not of what could be. Whether learning suffers is running on the
held-out worlds (where nearly every slot is present, so the approximation there is mild and the change to the
empty-slot encoding is what is really being tested).

**Sparse by slot, and the accidental ridge.** A first sparse rule that skipped any zero input broke learning
outright (39 / −11 / 109 / 24 on the held-out worlds): the option flags are zero on every row but the chosen
option's, so their cross-covariance never updated and the covariance went inconsistent. The right rule skips a
*slot* whose "there" reading is 0, with all its numbers and copies; bias, self, flags, descriptors and acquired
inputs are always in. That path is numerically identical to the full update when nothing is absent. It still lost
on world 2 (112 against 236) until the reason surfaced: the old encoding of an absent slot ("there 0, distance
2") had been acting as a ridge, a constant input of 2 in every row adding 4 to the gain's denominator per absent
slot, damping every update. Skip those inputs and the damping goes. With an explicit ridge instead (the prior
covariance 1/ridge), sparse with zero-encoded empty slots learns world 2 at ridge 4 as well as the full model and
at ridge 12 faster (threshold at episode 12 against 18). Running on the held-out worlds: sparse at ridge 4 and 12,
and the full model at ridge 12 (the ridge alone may be the win).
Ported: `RLS.update` skips inputs the mind has marked absent (`m.absent`, set per model before each update from
the sense groups' "there" readings); `Senses.encode` reads an empty slot as zeros; the mind's ridge defaults to 4
when groups are given. Headless world 2: sparse 228 of 220 in 9.0 s, full 218 in 16.6 s.

**Sparse by slot fails wherever presence alternates.** Held-out worlds, 6 seeds, mean final: ridge 4 31 / 10 / 284 /
−46, ridge 12 17 / 41 / 397 / −53, against 187 / 704 / 314 / 207 (the full model at ridge 12: 116 / 500 / 355 /
140, so the ridge alone is not a win either). Only world 24, whose item is always present, survives. The mechanism
is the flag failure at slot scale: while a slot is absent, its cross-covariance with everything present is not
updated, so when the slot returns those terms are stale and too large, and the first rows with it back move its
weights wildly. Skipping is sound only for inputs that never come back. The port's default goes back to the full
update; sparse stays an option for slots that are absent for good. Next: reset a returning slot's cross-covariance
to zero on return (full covariance among what is present, block-diagonal toward what was absent), which makes the
approximation consistent at the price of relearning the slot's couplings each time it reappears.

**Sparse with reset on return**: 89 / 653 / 284 / 123 against 187 / 704 / 314 / 207. Consistent now, and a quarter
below the full model, like the effects-local split. The picture after every variant:

| learning update | cost per decision at 318 senses (LuaJIT) | learning on the held-out worlds |
|---|---|---|
| full covariance (the baseline) | 8.5 ms | 187 / 704 / 314 / 207 |
| effects and couplings local, outcome full | 2.5 ms | 166 / 517 / 214 / 154 |
| everything local | 1.2 ms | 37 / 628 / 164 / 77 |
| sparse by slot, reset on return | ~1 ms | 89 / 653 / 284 / 123 |
| sparse by slot, no reset | ~1 ms | 31 / 10 / 284 / −46 |

Every way of making the cost linear costs about a quarter of the learning on these worlds, and two of them cost
far more. The quarter is not noise: it recurs across three unrelated approximations, which says the cross-terms
between what is present, what was present, and the option flags are doing real work. The package ships the full
update as the default with the three linear variants as options (blocks for locality, sparse for slots absent for
good, sparse with reset for slots that come and go), and the honest budget guidance: full covariance below about
sixty senses a creature; above that, choose which quarter to give up.

## 78. Two exact ways to pay less: read less, and share the physics rows

Neither approximates the covariance. **OVALUE=raw**: the outcome model reads the raw senses only; the couplings'
drift and the trends stay inputs to the effects and couplings but are zeroed for the value (a test of whether the
value needs them; if not, its inputs fall by two thirds and its cost by nine tenths at large sense counts).
**ESUB=p**: the effects and couplings, which are shared across a kind, learn from a share p of each creature's due
rows; a kind of a hundred creatures at p = 0.25 still sees twenty-five creatures' worth, and each creature pays a
quarter for the dearest models. Running on the held-out worlds (a single creature, the pessimistic case) at 0.5
and 0.25, and on the four-creature arena at 0.25 (the same total rows the shared models saw before).

**Results** (held-out worlds, 6 seeds, mean final; baseline 187 / 704 / 314 / 207, mean 353):

| arm | 18 | 20 | 24 | 28 | mean |
|---|---|---|---|---|---|
| value reads raw senses only | 167 | 829 | 386 | 132 | 378 |
| physics learns from 1 row in 2 | 136 | 526 | 283 | 214 | 290 |
| physics learns from 1 row in 4 | 100 | 356 | 356 | 190 | 250 |

Subsampling the shared physics loses even when the kind's total rows are kept (the four-creature arena at one in
four: 1,459 against 1,852): a creature's own rows at the moments it acts are not interchangeable with its
teammates'. Off. But the outcome model does not need the extras as its own inputs: reading the raw senses only,
with the drift and trends left to the effects and couplings (where the projection still carries them into the
value), it matches the baseline (378 against 353 on the mean, better on two worlds, worse on two). That cuts the
outcome model's inputs by two thirds and its cost by about nine tenths at large sense counts, exactly, with no
approximation of anything. Implementing it as a real reduction of the model (not a zeroing) next.

**The effects tier is the square.** With the outcome model reading raw senses only, F fell from 659 to 338 at
318 senses but the settle only from 8.2 to 7.3 ms: the effects models (per option, every sense predicted from
every input) are most of the cost. Two exact reductions of them: **ESHAREP** (one covariance for every effects
model, since their inputs are the same senses; per-option weights; the critique's "one regression with option
blocks"): world 2 168 against 164, settle 0.8x. **EONLY=2,4** (effects models only for the move and act choices):
world 2 collapsed to 46, because choosing a target changes what the slots read, so the target choice has real
effects. Both are running on the held-out worlds. (Cost figures taken while the machine was loaded are only good
as ratios.)

**Effects-tier cuts, six seeds** (mean final against 187 / 704 / 314 / 207; arena total against 1,852):

| arm | 18 | 20 | 24 | 28 | arena |
|---|---|---|---|---|---|
| shared covariance across effects models | 174 | 551 | 113 | 159 | 1,354 |
| effects for move and act only | 105 | 649 | 182 | 194 | |
| both | 190 | 518 | 102 | 163 | |
| outcome model reads raw senses only | 158 | 352 | 289 | 111 | 1,758 |

All losses; world 24 (the drifting item) collapses under every effects cut, and the arena loses a quarter under
the shared covariance. The raw-only outcome model is within noise on the arena (−5%) but loses on the held-out
worlds, and a one-seed dissection found why it differs from the zeroed version that had looked fine: with the
extras gone, the acquisition search has fewer dead inputs to waste its budget on, finds more, and the creature
does *worse* with more acquired features. That points at acquisition itself being a net loss on these worlds;
running the held-out set without it, with the full and the raw-only outcome model.

**Without acquisition** (6 seeds): 140 / 562 / 365 / 123 (mean 298 against 353); raw-only outcome model without
acquisition 122 / 404 / 252 / 118. So acquisition is a modest net gain, not a loss, and the raw-only outcome model
loses either way; the zeroed version's 378 was a favourable draw of six seeds. Closing this line: after block
locality, three sparse rules, shared physics rows, a raw-only value model, a shared effects covariance and
move-only effects, no cut of the learning update has held its learning on the held-out worlds. The full update
stays. The sense budget stands (section 77), and the cheapest true lever left is the one the game owns: what
fills the slots, and how often a creature decides.

## 79. Deciding less often

Every other lever changed the models; this one changes only how often they run. Held-out worlds, 6 seeds, mean
final (baseline 187 / 704 / 314 / 207, mean 353):

| decide every | 18 | 20 | 24 | 28 | mean | rows to threshold (median, where reached) |
|---|---|---|---|---|---|---|
| tick (0.1 s) | 187 | 704 | 314 | 207 | 353 | 6,900 / 6,300 / 9,600 / 5,850 |
| 2 ticks (0.2 s) | 148 | 442 | 368 | 245 | 301 | 5,850 / 2,175 / 5,800 / 5,025 |
| 3 ticks (0.3 s) | 142 | 636 | 193 | 297 | 317 | 2,100 / 1,500 / 4,400 / 3,300 |

A decision every 0.3 s costs a third of the compute of every 0.1 s and lands within the seed noise on three
worlds of four (the newborn's own finals span 4 to 242 on world 18 and 215 to 948 on world 20). It also reaches
the threshold in far fewer rows, since each row now spans three ticks of consequence. Of everything tried for
cost, this is the only cut that does not attack the models, and the guidance is: creatures that are not in a
fight decide every 0.2 to 0.3 s.

## 80. Slot-equivariant effects (proposed in the ledger by another model)

One law per option for how the self and world readings change (inputs: those readings and their trends), and one
law per option, shared across every slot, for how a slot's seven readings change (inputs: the self readings, the
slot's own readings, their trends, and the slot's kind as a one-hot). Every present slot's rows train the same law;
absent slots are skipped, exactly, since there is nothing to predict. Parameters no longer grow with the slot
count; cost grows with the slots present. EQUIV=1 in tabmind3.lua, needs o.blocks (self group first).

| senses (slots present) | full effects, settle a decision | equivariant | think, full -> equivariant |
|---|---|---|---|
| 38 (4) | 160 us | 80 us | 113 -> 113 |
| 150 (4 of 20) | 2,053 us | 460 us | 193 -> 147 |
| 318 (4 of 44) | 8,917 us | 1,990 us | 417 -> 230 |

World 2, seed 1: 174 against the full model's 164. What remains of the square at 318 senses is the outcome model's
own covariance (F = 659), about three quarters of the 1,990 us. Six seeds on the held-out worlds are running; if
they hold, the effects square is gone without dropping a cross-term, because the law was never per slot.

**Six seeds, first version:** 122 / 750 / 126 / 49 against 187 / 704 / 314 / 207. Wins the item world, loses the
three with hostiles or a switch. The self law read only the self readings, so it could not predict that health
falls when a hostile is near, and the slot law could not see where the other slots were. The equivariant remedy is
pooling: a fixed-size summary of every present slot, sums of each field by kind, as an input to both laws
(EQUIV_POOL, on by default now). Running.
**With the pool, six seeds: 155 / 815 / 216 / 152** against 187 / 704 / 314 / 207 (means 335 against 353): the
first cut of the learning update that holds its learning on the held-out worlds. Settle at 318 senses 2,370 us
against 8,917; parameters fixed whatever the slot count. Kept (EQUIV=1 with the pool). The arena harness has no
slot layout, so it cannot be run there. What remains quadratic is the outcome model's own covariance, and the
same trick applies to it: the value's slot inputs become sums over the present slots of field-by-kind and
field-by-option terms, a fixed-size vector, so the value is one linear model whose size does not grow with the
slots either (OVALUE=pool, next).

## 81. A pooled outcome model

The value's slot inputs become sums over the present slots: each field by kind, from every copy the mind holds
(raw, drift, trend), plus each field by the chosen options. One linear model of fixed size (F = 247 here) whatever
the slot count; with equivariant effects the whole learning update is then flat in the senses (settle 2.8 ms at
318 senses against 8.9 full, and constant beyond). Learning: world 2 seed 1 scored 68 at ridge 1, 138 at ridge
4, 194 at ridge 12 (the full model 164–236 on that seed). The reason is the one section 77 found: absent slots in
the raw model each carry a constant "distance 2" that damps every update, and the pooled model has no such
constants, so it needs its ridge set explicitly. Held-out worlds at ridge 12 and 30 running.
**Six seeds** (held-out, mean final; full model 187 / 704 / 314 / 207, mean 353; equivariant effects with the
full value 155 / 815 / 216 / 152, mean 335):

| pooled value + equivariant effects | 18 | 20 | 24 | 28 | mean |
|---|---|---|---|---|---|
| ridge 12 | 151 | 640 | 243 | 184 | 305 |
| ridge 30 | 140 | 774 | 352 | 122 | 347 |

At ridge 30 the whole learning update is flat in the sense count and lands at parity with the full model on the
mean (347 against 353), within the seed spread on every world. That is the scaling answer: the effects tied across
slots with a pooled context, the value reading pooled slot terms, and an explicit ridge in place of the damping the
absent slots used to supply. What still grows with the senses is the couplings model (n outputs from n inputs);
the same tying applies to it and is next.

## 82. Tied couplings, and the ridge that must not be shared

CEQUIV=1 ties the couplings across slots the same way (one law for the self readings' drift from their last
change and the pooled slots' last change, one law shared across slots for a slot's drift). With that, every
learned model is flat in the sense count: settle 287 / 320 / 350 us at 150 / 318 / 738 senses (full covariance:
2,053 / 8,917 / far more). The first run of the flat mind scored 32 on world 2 and it was the ridge: the pooled
value needs ridge 30 but the same number had been applied to the physics models, which want 1. Tied couplings
alone at ridge 1 score 216 on world 2. With the outcome model given its own ridge (ORIDGE=30, everything else at
1) the flat mind scores 204 on world 2 (greedy 206). Six seeds on the held-out worlds running. The package has the
same split (`valueRidge`), and its headless check with equivariant effects and the pooled value lands at 220 of 220.

**Six seeds, the fully flat mind** (equivariant effects, pooled value at ridge 30, tied couplings, physics at
ridge 1): **94 / 842 / 388 / 213**, mean 384 against the full model's 187 / 704 / 314 / 207 (mean 353), and
against 140 / 774 / 352 / 122 without the tied couplings. Above the full model on three worlds of four; the turret
world (18) is the one it loses, by half. Settle cost 287 / 320 / 350 us at 150 / 318 / 738 senses in LuaJIT: flat.
That is the scaling answer this session was after: parameters tied across slots, presence pooled by kind, and the
value's ridge set explicitly; nothing dropped, nothing subsampled.

## 83. Overlapping rows weighted 1/H (Bingo's calibration), and the separable pick search (Lume, Bingo)

Bingo showed the outcome covariance is ~44x overconfident because consecutive rows share H-1 of their H ticks,
and proposed weighting an outcome row 1/H (effects rows 1/STEP): the update's denominator starts at H instead of
1. Free calibration of P, they argued, since the true weight error was unchanged offline. On the flat mind, 3 seeds,
held-out rows to threshold (flat's 6 seeds: 94 / 842 / 388 / 213, mean 384):

| | 18 | 20 | 24 | 28 | mean |
|---|---|---|---|---|---|
| outcome rows 1/H | 186 | 664 | 403 | 164 | 354 |
| effects rows 1/STEP | 148 | 818 | 260 | 120 | 337 |
| both | 97 | 507 | 397 | 304 | 326 |

Better on the turret world, worse on 20 and 28, and below on the mean, every arm: the smaller early gain is
what the newborn pays. The calibration may still be right about P's *claims* (spread, confidence), but this
benchmark is rows to threshold and it does not move. Not adopted; OWEIGHT / EWEIGHT stay in the prototype.

The separable pick search is in the package (0.5.6): the value is linear in phi and phi is additive in the picks,
so worth(combination) = base(target) + one number a chosen option, plus the acquired features that pair two
choices, evaluated per combination (none arise from acquisition, which always pairs a raw sense). Checked
against the full worth() on every combination scored over 60,000 thinks: max error 1.4e-14. Think cost in Lune,
20 combinations a target, dense mind: 200 combinations 1,197 -> 438 us; 2,000 combinations 11,791 -> 1,840 us;
14,000 combinations (700 acts) 278,320 -> 15,411 us (18x). Flat mind at 2,000: 51,878 -> 2,796 us.

Bingo's three exact identities are in the package's RLS.update (0.5.7): zero-skipping in the matvec when a fair
share of the inputs are zero, the symmetric downdate done once a pair and mirrored, and a row counted k times as
one closed-form update. Against the textbook update: 7e-16 on the weights, 3e-16 on the covariance. Settle in
Lune, a quarter of the slots present: 37 senses 1,016 -> 754 us; 149 senses 14,587 -> 8,273; 317 senses
73,449 -> 34,267 dense and 5,435 -> 3,953 flat. (Lune is about four times slower than LuaJIT on this code.)

## 84. A fixed random projection of the senses (Lume's learned sense code, the cheapest test)

Lume proposed reading a learned code of B ~ 12-24 numbers instead of the senses, and found a *random* code of 16
beat the dense mind on worlds 2 and 24. Here on the held-out worlds, 6 seeds, OMECA (the timers tier reads raw
sense positions and cannot run on a code, so the dense arm is OMECA too; the OMECTA newborn's 187/704/314/207 is
shown for scale). PROJ=B in tabgen: a Gaussian matrix drawn once, scaled 1/sqrt(B), no groups, no slot layout.

| | 18 | 20 | 24 | 28 | mean |
|---|---|---|---|---|---|
| OMECA dense (37 senses) | 145 | 385 | 228 | 134 | 223 |
| projection to 16 | 140 | 808 | 544 | 305 | 449 |
| projection to 24 | 95 | 441 | 316 | 230 | 270 |

Sixteen random numbers made of the senses learn twice as well as the senses themselves, and every seed of world
24 reached its threshold (532-564) where the dense mind's seeds split 18-544: the reliability problem, mostly
gone, for the price of a matrix multiply. 24 dims is half as good, so this is not monotone in B, and Lume found 12
collapses. Cost is B squared and fixed whatever the game offers. What it cannot do: name a sense, so instincts
declared on senses have no place to land, and the slot machinery (equivariant, pooled, groups) is off. Next: is it
the compression (B < n) or the mixing (every input always live)? A square random rotation (PROJ=37) and PROJ=12
are running.

**Compression or mixing?** Six seeds, OMECA: a square random rotation (PROJ=37) reads 116 / 720 / 223 / 188 (mean
312) and a code of 12 reads 138 / 693 / 550 / 127 (377), against 16's 449 and dense's 223. Mixing alone gets
world 20; compression gets world 24 (12 and 16 both reach it on every seed, 37 does not). Sixteen is the sweet
spot of the three; 12 loses world 28. The projection is robust to the matrix drawn (three more seeds all reach
world 2 in 20 episodes). But the code must be *all* there is: appending raw senses beside it (six self readings;
five item and host slot senses; or a slots-only projection with the ten self readings raw, at 12, 16 or 20)
collapses or is fragile on world 2 (0, 4 / 216, 6-86). Whatever raw senses do to the newborn, the code escapes
it by not having any.

## 85. The row calibration, measured where it ships (Bingo's row weights, 1/H and 1/STEP)

Section 83 called the calibration a loss on three seeds of the held-out battery; Kestrel then showed those
differences sit inside the battery's noise floor (world 24's finals are bimodal: sd 264 over nine seeds, so three
seeds cannot separate anything under about 600), and Bingo measured the same weighting on the package's own
harness at six seeds with a halving of rows to threshold. Paired on eight seeds in the package harness
(`scripts/mind`, worlds 2 and 24), reporting what Kestrel asked for, reached and the score when reached:

| | world 2 reached | median episode | world 24 reached | median episode | score when learned |
|---|---|---|---|---|---|
| dense | 7/8 | 16 | 5/8 | 11 | 224 / 672 |
| dense, calibrated | 7/8 | 14 | **8/8** | 11 | 222 / 683 |
| code 16 | 8/8 | 12.5 | 7/8 | 11 | 217 / 658 |
| code 16, calibrated | 7/8 | 12 | **8/8** | 11 | 224 / 648 |

Same score when it learns, and the seeds that used to fail world 24 now learn it. One scalar on two models, so
it is the default from 0.6.2 (`calibrated = false` turns it off). The held-out three-seed verdict in 83 stands
corrected as unresolved, not negative.

## 86. Posterior-sampled exploration (Kestrel's RLSVI): noise on the outcome targets, drawn once an episode

RLSVI=sigma in tabmind3: every outcome row's target carries sigma times the reading's spread times a Gaussian
drawn once an episode per reading, shrinking as 1/sqrt(1 + rows/300); the greedy policy then acts on a draw from
the model's own uncertainty. Held-out battery, six seeds, on the OMECTA newborn (reached / seeds, then the
finals), against the newborn's 9/9, 7/9, 5/9, 4/9:

| | 18 | 20 | 24 | 28 |
|---|---|---|---|---|
| sigma 0.5 | 3/6 (mean 123) | 4/6 (581) | 4/6 (378) | 1/6 (94) |
| sigma 1.5 | 1/6 (82) | 3/6 (405) | 3/6 (272) | 4/6 (291) |

Fewer seeds reach the threshold at either scale on three worlds of four (world 24 at 0.5 is the one that does not lose); the held draw did not do what the
bonuses and the dither could not. With Kestrel's noise floor in mind this is "no sign of a gain", not a proof of
harm, but it is the seventh exploration idea to read below the newborn, and the line stays closed. RLSVI stays in
the prototype.

## 87. Centred one-hot flags (Bingo): a reparametrisation, measured paired in the package harness

Each flag read as (picked - 1/options) removes the direction in which a choice's flags are collinear with the
bias. Package option `centredFlags = true`, separable scoring adjusted (exact, 1.8e-14). Paired on eight seeds
with the row calibration on in both arms (reached, median episode, score when learned):

| | world 2 | world 24 |
|---|---|---|
| dense, calibrated | 7/8, 14, 222 | 8/8, 11, 683 |
| dense, calibrated, centred | 8/8, 13, 221 | 7/8, 11, 658 |
| code 16, calibrated | 7/8, 12, 224 | 8/8, 11, 648 |
| code 16, calibrated, centred | 6/8, 12, 229 | 6/8, 11.5, 675 |

Inside the noise for the dense mind, two seeds worse on each world for the code. The prior it changes is not
the one that limits the newborn. Kept as an option, off.
