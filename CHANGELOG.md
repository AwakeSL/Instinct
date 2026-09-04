# Changelog

## 0.5.7

- Three exact shortcuts in `RLS.update` (Bingo's rows in the ledger): zero inputs are skipped in the matvec
  when a fair share of the inputs are zero, the covariance downdate is done once per entry pair and mirrored,
  and a row counted several times (`reps`) is one closed-form update. Against the textbook update: max weight
  difference 7e-16, covariance 3e-16 (`scripts/check_rls.luau`). Settle in Lune: 37 senses 1,016 -> 754 us;
  149 senses 14,587 -> 8,273 us; 317 senses 73,449 -> 34,267 us dense, 5,435 -> 3,953 us flat
  (`scripts/bench_settle.luau`).

## 0.5.6

- Separable pick search (on by default, `separable = false` to disable): the first pass scores every
  combination as a base plus one number per chosen option instead of a full prediction each, exactly (max error
  1.4e-14 against the full scoring). Think at 700 acts x 20: 274 ms -> 3.7 ms in Lune. The beam takes its
  candidates by selection rather than a full sort, ties drawn at random.
- `scripts/bench_think.luau` measures think against the act count; `CHECKSEP=1 lune run scripts/mind` checks the
  separable scoring against the full one.

## 0.5.5

- Tied couplings under `equivariant = true`: one drift law for the self readings and one shared across slots,
  both reading the pooled last change by kind. With the equivariant effects and the pooled value every model is
  now flat in the number of slots (settle 287 / 320 / 350 us at 150 / 318 / 738 senses in LuaJIT). Held-out
  learning 94 / 842 / 388 / 213 rows to threshold against the full model's 187 / 704 / 314 / 207 (FINDINGS 82).
- Saves carry `CG`/`CS` instead of `Cm` when equivariant.

## 0.5.4

- **Learning flat in the sense count, as options.** `equivariant = true` (with `groups`): one effects law per
  option for the self readings and one shared across every slot, both reading a pooled summary of the present
  slots by kind; held-out 155/815/216/152 against 187/704/314/207, settle 8.9 -> 2.4 ms at 318 senses (FINDINGS
  80). `pooledValue = true`: the outcome model's slot inputs are sums over present slots of field-by-kind and
  field-by-option terms, a fixed size whatever the slot count; with the equivariant effects, held-out 140/774/352/122
  (FINDINGS 81). `valueRidge` (30 with the pooled value) is separate from `ridge` (1 for the physics): sharing
  one number between them breaks learning (FINDINGS 82). The slot-equivariant effects were proposed in
  docs/IDEAS.md by another model.

## 0.5.3

- **Linear-cost learning, as options.** `blocks` (effects and couplings local to a slot's group and the self,
  `localOutcome` for the outcome model too) and `sparse` with `groups` (absent slots skipped; `sparseReset`
  for slots that come and go). Each costs about a quarter of the learning on held-out worlds; the full update
  stays the default. `Senses.groups` builds the groups for a slot layout. A README section gives the measured
  costs and the sense budget that follows.
- `ridge` is an option on the mind.

## 0.5.2

- **A nudge.** Ten decisions in a row with unchanged senses (a body against a wall) and the creature tries one
  other combination and holds it for as long as the stuck spell lasted, in any phase; while exploring, a held random move is re-rolled the moment the senses stop
  changing. Both came out of the first creature that had to look for its food.
- **Effects cache.** Each option's predicted change of the senses is computed once per think and summed per
  candidate, instead of re-predicted for every candidate in the beam.
- Curious pairs no longer force a feature search before the creature has a thousand rows.

## 0.5.1

- **Descriptors.** `o.descriptors[optionIndex] = { ... }` with `o.descrDim` gives options (acts, usually) a
  graded descriptor; the value reads an option through it and through its interactions with `o.descrSenses`,
  as well as through its private flag, and with `o.descrLearn > 0` the creature revises each descriptor on the
  option's own rows. Measured on 8, 32 and 100 generated acts: revisable descriptors beat private flags at every
  size and beat the greedy policy at 100; fixed descriptors are worse than revisable ones. Tag-level weights
  are named `tagN` and `tagN*sense` in knowledge files and distilled files, and a file distilled from one act
  set transfers to a creature with a different act set (FINDINGS 72, 73).
- **Trends.** Every sense's change since the last decision is an input (`o.trend`, on by default); it recovers
  what the arena's hand-written timers gave, on worlds the timers were never written for.
- **`--!native`** on RLS.luau and Mind.luau: about 3x in Studio on settles and thinks.
- **Sticky exploration** (`o.sticky`, 0.9): a random combination is held for a while, so a physical body
  crosses the room instead of jittering in place.
- The coach takes its random floor from the exploration episodes (`floor = "explore"`).

## 0.5.0

The package is now the learned mind, ported from the offline prototype (`C:\lua code`, FINDINGS.md sections
32-70). Everything before it -- the (value, spread) beliefs of 0.4.0 and the prediction rebuild in `next/` --
is in `attic/`, kept only for reference. Nothing of the old authoring surface survives.

A creature is one linear model of what each reading will accumulate over a short horizon, from its senses and
its picks, fit online by recursive least squares; per-option models of what each act does to the senses, so it
can look one step ahead; a memory of surprising good moments that it replays when the senses come near; a
search that invents pair features where it keeps being wrong; and a coach that gives it random windows at
birth and throws the dice again when it does worse than a random policy. Instincts are knowledge files of
revisable priors. Save and load are plain data.

- `Instinct.Mind` -- the mind. `new`, `think`, `note`, `settle`, `rebirth`, `learnFrom`, `distill`, `save`,
  `load`, `shareEffects`.
- `Instinct.Senses` -- the slot layout every world is read through: the self, then one slot per role in the
  creature's own frame with the same seven descriptors. What makes learning transfer between worlds.
- `Instinct.Coach` -- exploration at birth, and rebirth-below-random with re-exploration.
- `Instinct.RLS` -- the model, for anyone who wants to build on it.
- `scripts/mind.luau` -- the headless check, in the prototype's worlds.

## 0.4.0

Two ways for a creature to act on what it does not know.

### `narrows` on an action

`watch` was declared in the authoring doc with `narrows = "subject"` and the field was never parsed,
so the action did nothing at all. Curiosity rose and had no outlet -- and since 0.2.0 it was worse
than nothing, because the creature would have learned that watching is useless.

An action declaring `narrows` now tightens every belief the creature holds about its target while it
is performed. Curiosity closes its own loop from there: the emotion reads the widest belief held
about a subject, so tightening those beliefs lowers it with nothing having to say so.

The claim is comparative, not absolute. Ordinary experience narrows a belief anyway, because every
prediction that comes due updates it. Attending to something deliberately tells the creature much
more, much faster.

### `venture`, and why an option worth nothing is not worth nothing

An action predicted to cancel nothing was skipped outright. That made "worth nothing" a life
sentence: the option is never picked, so it is never tested, so the belief that killed it can never
be revised. It is why a creature walled into a pocket freezes -- every direction that points at what
it wants is blocked, and the ones that are open score exactly zero -- and why a creature whose
movement is rewired cannot find its way back.

`venture` values an option for what trying it would teach: the widest spread held on any of its own
predictions, against the same yardstick Emotions measures novelty by, scaled by how badly the
creature needs an answer. An option promising nothing is now admitted as an experiment, and wins
only when nothing that makes a claim has stood up. An experiment does not have to clear `caution`,
because it is not claiming it will work.

Uncertainty below a floor counts as none, so a creature does not fidget over options it has settled.

**Defaults to 0, and must.** A creature that freezes under steep caution, or refuses to chain with no
patience, is doing something the package specifies and the suite asserts; an experiment admitted
regardless of caution would quietly undo both. Venturing is a disposition a species is given, not a
correction applied to everything.

### Tests

`test/CuriositySpec.luau`, 8 cases: looking tightens what is believed about the thing looked at and
settles the curiosity that caused it; a creature whose looking does not narrow learns far less from
the same time spent; and only the thing attended to is narrowed.

`test/VentureSpec.luau`, 6 cases: with no venture an option promising nothing is never tried; with
it the creature tries what it knows least about; an option it is already sure of is not worth an
experiment; and something that plainly works still beats something merely unknown.

282 cases, 19 specs.

### Still open

- **Acquired features (stage 8).** No composition or search machinery exists. `venture` makes a
  creature willing to try an unknown action; it does not let one work out a new way of seeing.
- **Predicted gains still move nothing**, so the newborn "drawn to water" cannot exist.
- **`of = "target"` predictions still do not learn.**

## 0.3.0

Needs can look ahead. A creature can want something before it is short of it.

### `after` on an `expects` entry

```lua
expects = { fullness = { 0.90, spread = 0.05, after = 30 } }
```

A need was a snapshot: `prior.value - held`, with `after = 0` hardcoded on the error it produced.
So a creature acted only once it was already short, and nothing could make it act in advance. With
a horizon the need is measured against where it is *heading* instead of where it is.

Defaults to 0, which is the previous behaviour exactly.

### The trajectory is learned, not authored

Projecting needs a rate, and that rate is a belief like everything else -- `drift|<quantity>`, held
with a spread, updated from what the creature observes happening to itself.

- **A newborn does not know it gets hungry.** It has no drift belief at all, so it cannot
  anticipate, and only starts to once it has felt itself run down.
- **The forecast carries the belief's uncertainty, widened by the horizon**:
  `sqrt(spread^2 + (drift.s * after)^2)`. Being unsure how fast you empty makes a distant forecast
  worth very little, and a wide enough one falls under the salience floor and is ignored. Foresight
  is therefore not switched on -- it sharpens as the creature learns its own body, and reaches less
  far the less certain it is.
- **Only declines are sampled.** Rises are the creature being fed or healed and say nothing about
  how fast it runs down unattended; averaging them in would cancel the drift to zero.

### Tests

`test/ForesightSpec.luau`, 12 cases: a creature that has never declined does not anticipate; one
that has learns the rate and holds an error while sitting exactly on its prior; the same life with
no horizon holds none; a longer horizon finds a bigger shortfall; a creature that has only ever
been filled learns no drift.

268 cases, 17 specs.

### Still open

- **This is anticipation, not deliberation.** The creature acts earlier; it does not weigh acting
  now against acting later. It will walk to food while full, and then eat rather than wait, because
  nothing compares the value of an action against the value of the same action performed later.
- **Predicted gains still move nothing.** `predictedErrors` skips any `delta >= 0` and
  `cancelsThreat` accumulates `math.max(-was, 0)`, so an instinct promising a benefit is inert on
  both paths. The newborn "drawn to water" in the authoring doc still cannot exist.

## 0.2.0

A creature can now learn what its own actions do. Everything in 0.1.0 that learned about the
world — kind and subject beliefs, taming and trauma, blame, acquired features — is unchanged.

### Action beliefs are checked against what followed

`action|<name>|<of>|<quantity>` beliefs were created for scoring and never once observed, so a
creature stayed wrong about its own punch however often it threw one. `think` now commits the
predictions of whatever the creature is doing to the pending run, through the same
`state.expect` that commits a prediction about a kind. The horizon check that resolves them was
already generic and is untouched.

This runs on every exit that keeps an action, not only where one is chosen, because a creature
holding an action across many ticks has to keep re-checking it. `state.expect` de-duplicates by
key, so at most one row per belief is outstanding and a fresh one is filed once the previous
resolves.

- `stats().learned` now counts action outcomes as well as instinct ones.
- Only `of = "self"` predictions are checked. See *Still open* below.

### `believes` is read

A species' `believes` block was validated, compiled, stored on the creature and never consulted.
`Think.predictsOf` now merges it over the action's own predictions: an entry replaces the
action's for the same `(of, quantity)` and is otherwise added. So an action that predicts nothing
on its own can be given a prediction by the species — which is what makes an action whose whole
point is how it makes the creature feel work at all.

The merge is per creature and cached, since neither side changes after spawn. `extract` reports
the merged set, so a creature's `believes` round-trips.

### `when`, partially

`when` was compiled and stored but never read. `Think.whenHolds` now evaluates
`when = { target = "blamed" }` against the resolved target. **Any other condition means the
prediction does not apply**, rather than applying unconditionally — an unrecognised condition can
never make a creature act on something it never meant.

### Tests

`test/ActionLearnSpec.luau`, 13 cases: the belief is checked more than once; an action that never
delivers loses the belief that it does; one that keeps being right narrows and stays near what
the world reports; `adaptability` sets the rate; `believes` overrides and adds; an unevaluable
`when` does not apply.

256 cases, 16 specs.

### Still open

- **`of = "target"` predictions do not learn.** `state.expect` takes self predictions only, and
  the horizon check reads `state.level`, which is the creature's own. Learning what a blade does
  to somebody else needs the check to read the target's perceived quantity instead. The archery
  case — a bow that narrows with practice — is on the far side of that, because it predicts about
  the target rather than the self.
- **Blame goes quiet for a quantity under a pending row.** `Blame.unexplained` skips a quantity
  already covered, so an action that predicts one suppresses association-forming for it while it
  runs. Arguably right — if an action already explains the change, do not blame a bystander — but
  it is now reachable far more often than it was.

## 0.1.0

Initial release.
