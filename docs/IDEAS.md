# Every idea, and what it measured

**Shared document.** More than one model writes here. Conventions: read the whole file before proposing; add a
proposal as a row under *Proposed, untested* with your name and date; move it to *Kept* or *Tried and dropped*
only with a number from a run and a section in `FINDINGS.md`; never rewrite or delete another writer's row;
append a note under it if you disagree. The log is the evidence; this file is the index.

One line per idea: what it was, the number it got, the verdict, and the section of `docs/FINDINGS.md` (the full
running log) with the detail. Read this before proposing anything; most obvious ideas are here with a number.

**How to read the numbers.** *Arena* = the abilities arena (`tabffa3.lua`), sum of four learners' check damage
per seed, curriculum baseline 1,852 over three seeds (or 588 a seed over eight). *Held-out* = the generated worlds
never tuned on (`tabgen.lua`, worlds 18 / 20 / 24 / 28), mean of the last ten episodes over six seeds, baseline
187 / 704 / 314 / 207. *Duel* = one creature against a scripted fighter, wins of 30. Lower is worse everywhere.

## Kept (the creature as shipped)

| idea | number | section |
|---|---|---|
| One linear outcome model with a flag per option, recursive least squares, one covariance | the baseline | 21, 24 |
| Twelve-tick decision step (STEP=12) | arena 335 -> 421 a seed | 37 (wave 5-6) |
| Rebirth when a creature falls behind its teammates (full reset of the value) | arena 421 -> 585 (8 seeds) | 37 (wave 9-13) |
| Curriculum: weak bots first, then the full bots | arena ~588 a seed with more team wins | 38 (wave 23-24) |
| Shared effects models across a kind | arena 628 (6 seeds); memory 3.7 MB -> 0.5 MB a creature | 50 |
| Distilled knowledge file for spawns (top weights at confidence 50, memories) | spawns 764 vs 572 blank; generations compound | 39-40 |
| Memory of surprises, radius x2 | +4 team wins | 32 |
| Attention gate (learned when to think) | 27-39% of thinks for 91-92% of the damage | 48 |
| Opponent-event model (target parry / shoot as hazards) | duel 10.4 -> 13.5 mean wins; three worlds all solved | 55 |
| Slot senses, no world flags (one mind, three worlds) | all three worlds on every seed | 56-57 |
| Per-context option weights (three worlds) | all three on 5/6 seeds | 56 |
| Rebirth below a random floor, then explore again (the coach) | world 24: 5/9 -> 6/6 seeds learn; 28: 4/9 -> 5/6 | 68 |
| Sticky exploration (hold a random move ~1 s) | needed for a physical body; neutral in the prototype | 74 |
| Stuck nudge (unchanged senses for ten decisions -> try another combination, hold it) | corner escape in the Look room | 74 |
| Revisable act descriptors (tags the creature revises) | 8/32/100 acts: 68/5/306 vs flags -71/-101/182 | 72 |
| Tag-level knowledge across act sets | spawn on unseen acts 183 mean vs flag newborn 86 | 73 |
| Trend inputs (each sense's change since the last decision) | OMECA 145/385/228/134 -> +trend 134/538/371/175 | 70 |
| `--!native` on RLS and Mind | 3x in Studio | 71 |
| Effects cache per think | Diet room think 1,110 -> 189 us | 74 |
| Instinct files (vague priors at confidence 2-3) | Look room: 3 meals in 6 windows -> 7 in the first greedy window | 74 |
| The world owns the want (preferences re-set each tick from body state) | Diet: -38.8 random -> -0.4 (0 is perfect) | 75 |
| Deciding every 0.3 s instead of 0.1 s | held-out 142/636/193/297 vs 187/704/314/207 at a third of the cost | 79 |
| Slot-equivariant effects with a pooled slot context (one law per option shared across slots, plus sums of each field by kind) | held-out 155/815/216/152 vs 187/704/314/207; settle 8.9 -> 2.4 ms at 318 senses; parameters fixed in the slot count | 80 |

## Tried and dropped

| idea | number | section |
|---|---|---|
| Spread (uncertainty) bonus, curiosity | arena loss; held-out fixes 28, collapses 24 (any strength) | 24, 37, 66 |
| Improvement bonus, revelation bonus | arena losses | 24, 34 |
| Hazards on non-opponent events | loss | 31 |
| Per-context option weights on the arena (general) | loss | 32 |
| Pair features from picks only, sense tags, act tags at 9 acts | losses | 37, 46 |
| Bullet senses | loss | 38 (wave 22) |
| Forgetting (any mode) in training | broke the covariance / loss | 37 |
| Memory sharing, inheritance between creatures | loss (554 vs 588) | 38 |
| Live species value model (4 and 8 learners) | loss | 45 |
| Split diagonal residual, replay of best matches | losses | 37, 38 |
| Fast think between big thinks (two versions) | loss | 47 |
| Slow tier chain, hierarchical think, pruning search, macro memories | losses | 37 |
| Experience lookahead (all, gated, arena) | loss | 53 |
| Mixtures of experts (fixed, grown; three experts and a chooser) | losses | 54 |
| Two-step lookahead (PLAN2=max), longer chains | arena loss; held-out neutral (188/818/274/221) | 37, 70 |
| Diagonal effects covariance | -31% | 49 |
| Health caution (PREF_HP) | -30 to -40% | 57 |
| Teacher warm-up instead of random | loss | 38 (wave 29) |
| Fuller hand priors on the arena | loss | 44 |
| Library of specialists (best-of-library value, GPI) | three worlds: 2/0/0 wins alone | 58 |
| Shared dynamics with per-option residuals (ESHARED) | 1,510 vs 1,852 | 59 |
| Attention gate with readings' errors as features | 1,419 vs 1,706 | 60 |
| Spawn from the source's whole covariance (any strength; also on top of the file) | 619-636 vs 764 | 61 |
| Covariance pooling across creatures (full, tenth), fully pooled rows | 873 / 1,570 / 1,222 vs 1,852 | 62 |
| Rebirth keeping the covariance (x1, x10) | 1,522 / 1,669 vs 1,852 | 62 |
| Distilled or method-only files on held-out worlds | no better than a newborn | 63 |
| More training worlds (4 vs 8 vs 16) | no difference at 400 episodes | 65 |
| Twenty exploration episodes instead of five | worse everywhere | 66 |
| Below-random rebirth without re-exploration | no change | 66 |
| Vague instincts on the held-out worlds (food only, food + hostile) | noise; hostile instinct fatal on turret worlds | 66 |
| No option flags, flag decay, tighter flag start, sampled flags, significance-gated flags | all uniformly worse; arena 78-309 vs 1,852 | 67 |
| Untried-option bonus, lifelong randomness (2%, 5%) | each fixes one world, hurts another | 67 |
| Physics instinct ("approach closes distance") | wins 20, loses 24 | 67 |
| Longer fixed horizons (4.8 s, 7.2 s, discounted) | 96/574/381/123 and worse | 70 |
| Bootstrapped discounted return (0.95, 0.97) | 99/775/365/122 and worse | 70 |
| Error-gated learning, lazy effects outputs, couplings every 4th tick, raw-sense effects | all losses | 71, 77 |
| Fifty-tag sparse vocabulary (10 tags an act) | below the compact descriptor, dearer | 72 |
| Drought drive (urge for sense change after no gain) | 50/559/265/143 and 158/652/202/154 | 74 |
| Block-local covariance (everything; outcome only; effects only; both) | 37/628/164/77; 96/549/284/176; 166/517/214/154; 101/257/365/110 | 76 |
| Sparse by value (any zero skipped) | breaks learning (flags) | 77 |
| Sparse by slot, no reset / with reset on return | 31/10/284/-46 ; 89/653/284/123 | 77 |
| Ridge 12 on the full model | 116/500/355/140 | 77 |
| Shared physics learns from 1 row in 2 / in 4 | 136/526/283/214 ; 100/356/356/190; arena 1,459 | 78 |
| Outcome model reads raw senses only | 158/352/289/111; arena 1,758 | 78 |
| Shared covariance across effects models; effects for move+act only; both | 174/551/113/159 ; 105/649/182/194 ; 190/518/102/163 | 78 |
| No acquisition | 140/562/365/123 | 78 |
| Deciding every 2 ticks | 148/442/368/245 | 79 |

## Open, with the evidence so far

- Learning cost is the square of the sense count and every linear-cost variant costs about a quarter of the
  learning (76-78). The sense budget is about sixty a creature at full quality; the decision rate is the one free
  lever (79).
- Newborn reliability: one seed in three still learns a world late even with the coach (67-68).
- Knowledge transfer works through live weights and tag-level priors, not through distilled weight files on new
  worlds (63, 73).
- Where the tick actually goes, profiled on world 2 at 37 senses and 80 combinations (`scripts/prof_mind.luau`,
  Lune; Studio native about 3x): think 155 us, settle 506 us, 661 us a tick. Of the learning, the thirteen effects
  models (F=112, NR=37, four updated a tick) are 73%, the outcome model 22%, the couplings 5%. The effects
  covariance is the cost, and 49, 59, 62 and 78 all say it is the part that will not be shared or thinned.

### Proposed, not yet measured

Three ideas that survive a read of the tables above. All must beat the held-out baseline 187/704/314/207.

- **Slot-equivariant effects.** One law a slot-*kind*, weights tied across the slot groups `Senses.groups` already
  names, each slot read in its own relative frame. Effects outputs fall from every sense to one slot's worth plus
  the globals, and every slot's rows train the same parameters: about 4x fewer effects parameters and 4x the rows a
  parameter, so it should *raise* learning if the law really is one law, and flatten the slots and lose if they
  differ in kind. Untried: 56-57 kept slot *senses*, not tied weights, and 76-77 partitioned the covariance, never
  the weights. Note this ties weights and leaves each model its own covariance, which is what 78 says not to touch.
  It also opens the cheap route to bonds: a few learned numbers a remembered individual, carried in the slot as
  extra senses and read by the shared law, so the physics stays general and the relationship stays specific.

- **Separable pick search.** `phiO` makes the value additive in the picks: option flags are one-hot per choice and
  the descriptor terms sum over choices (`acc[q]` is a sum), so value = base(X) + sum over choices of w[option],
  exactly. Only acquired features pairing two flags from *different* choices break it, and those are enumerable. So
  the best combination is the per-choice argmax, once per target option, plus a correction over the cross terms and
  a feasibility repair; k-best per-choice lists feed the beam unchanged. This is an identity, not a prune -- 37
  killed approximate pruning and hierarchical think, but this returns the same combination, so learning cannot
  move and only the clock should change. The first pass then costs the target options rather than their product,
  so a thousand combinations cost what twenty do. Measure against the attention gate (48), which already skips
  60-70% of thinks and so caps what this can be worth.

- **Deferred learning, not lazier learning.** Rows already settle a horizon late; nothing requires the four effects
  updates, the outcome update and the couplings update to land on one tick. Push them as jobs and drain to a
  microsecond budget a tick: cost becomes the budget, flat and independent of the sense count, and a spike becomes
  a backlog instead of a dropped frame. Distinct from every neighbouring loss -- error-gated learning, lazy effects
  outputs, couplings every 4th tick (71, 77) and shared physics from 1 row in 2 or 4 (78) all *discard* rows, and a
  draining queue discards none. The risk is exactly that: under sustained load a queue that never drains decays
  into the subsampling 78 measured at about a quarter of the learning, so the test has to report the backlog
  alongside the score.

## Proposed, untested

| idea | proposed by | date | note |
|---|---|---|---|
| Low-rank (Frequent Directions) sketch of the effects covariance, rank ~32 | Claude | 2026-09-04 | deferred: slot-equivariant effects (below) removes the effects square exactly; the sketch would only be needed for the outcome model |
| Slot-equivariant effects (proposed above under "Proposed, not yet measured") | another model; built by Claude | 2026-09-04 | KEPT with a pooled slot context: held-out 155/815/216/152 vs 187/704/314/207, settle 8,917 -> 2,370 us at 318 senses; the first cut that held its learning; without the pool 122/750/126/49; FINDINGS 80 |
| Effects models read senses + trends, not the couplings' drift (inputs 3n -> 2n) | Claude | 2026-09-04 | crashed on a size mismatch; superseded by the equivariant effects, which read no drift either |
