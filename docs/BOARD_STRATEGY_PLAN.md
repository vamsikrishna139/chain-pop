# Board Strategy Plan — variety, cores, density, attention

**Date:** 2026-08-19 · **Branch:** `new_improvements` · **Status:** plan only, no code changed

Evidence base: 600 levels autoplayed on a Pixel 8a (600 wins, 0 stuck) · 900 boards profiled
headlessly (300/mode) · 500-level Hard diversity benchmark · two deep research reports
(engagement systems; perceptual deception).

Styled version: <https://claude.ai/code/artifact/4adee738-973a-4c67-9f8b-9dc36a0cbca5>

> **Headline.** The "finishes in a jiffy" problem is **Medium, not Hard**, and it has a single
> root cause: the core placement band is enforced in the wrong unit. Hard is healthy. Easy has
> no mechanics at all.

---

## F1 — Cores end Medium levels in a third of the intended time · CRITICAL

Winning fires the instant every core is restored (`chain_pop_game.dart:750`); the rest of the
board auto-pops as decoration. Medium gets 2 cores, Hard 3 (`progression_profile.dart:97-110`).

Measured over 100 boards per mode:

| Mode | Min taps | p25 | p50 | p95 | ≤3 taps | ≤6 taps |
|---|---|---|---|---|---|---|
| Easy | 8 | 9 | 11 | 14 | 0% | 0% |
| **Medium** | **2** | 5 | **8** | 21 | **11%** | **44%** |
| Hard | 6 | 9 | 11 | 20 | 0% | 1% |

Split Medium by whether cores are present and the mechanism is unambiguous:

| Medium boards | n | Median taps to win | Min | Max |
|---|---|---|---|---|
| without cores | 22 | 20 | 14 | 25 |
| with cores | 78 | **6** | **2** | 16 |

**Root cause.** The climax band `[0.35, 0.65]` (`level_enrichment.dart:38-44`,
`_climaxBandCoreIds`) is measured in **removal-wave percentile**. Waves are *parallel* — one
wave can retire a dozen nodes. On a shallow board, wave 50% is tap two. The guarantee is
vacuous exactly where it matters:

| Deepest core's wave percentile | n | Median taps | Min taps |
|---|---|---|---|
| ≈0.3 | 10 | 4 | 2 |
| ≈0.5 — dead centre of the intended band | 26 | **6** | **2** |
| ≈0.7 | 17 | 6 | 5 |

Correction to earlier notes: this climax-band work **is** present on `new_improvements` — it
was merged, not stranded on `new_adaptive`. The band exists and is being honoured. It is
measuring the wrong quantity.

## F2 — Easy ships zero mechanics, at every sector, forever · CRITICAL

`progression_profile.dart:93-95` returns `MechanicBudget(coreCount: 0)` and returns
immediately — every other mechanic count defaults to zero. No cores, locks, relays, phase
gates or portals on Easy at any level, ever.

The corpus agrees: all 100 Easy boards have `tapFrac` of exactly **1.000** — every node needs
its own tap — and **zero** cascade auto-pops. Easy is "tap every node in a legal order", 300
times. Any player who starts on Easy and stays there never meets the game.

## F3 — The fallback you're worried about isn't happening; a different one is · ASSUMPTION CORRECTED

Shipped mask→rectangle fallback rate, per board actually handed to the player over 300 levels
per mode: **Easy 0.0%, Medium 0.0%, Hard 8.0%** (24/300). Not 99%. The scary raw counter
(5,394 callbacks on Hard) is dominated by discarded K-loop candidates and speculative density
probes that never reach a player.

But the 8% is visibly clustered. Hard levels 45–56 contain **five full-rectangle 8×8 boards
inside twelve levels** — that block is the real "it all looks the same" complaint.

**Root cause.** `director.dart:506` sets `minCells = config.difficulty.minNodes`, which is 25
on Hard. That demands a 39% fill on 8×8 and 52% on 8×6, so entire silhouettes are deleted
before they can be evaluated — diamond fails 32% of rolls on 8×8, 86% on 7×7, 100% on 8×6;
archipelago 52%. The mask only ever needs room for the target, and `_pickTargetNodeCount`
already clamps to `mask.length`.

## F4 — Variety is far worse perceptually than numerically · STRUCTURAL

Distinct exact cell-sets over 300 levels: Easy 173, Medium 182, Hard 157 — still climbing at
300, no plateau. On paper that is healthy. What the player perceives is not the exact cell-set:

| Perceptual measure | Easy | Medium | Hard |
|---|---|---|---|
| Distinct coarse topology classes | 30 | 18 | **14** |
| Worst 5-level window, distinct visual families | **1** | **1** | **1** |
| Longest same-silhouette run | 3 | 4 | **6** |
| Geometric-lattice share | 46% | 38% | **68%** |
| Archipelago share | 11% | 18% | **2%** |

Hard's four commonest topology classes cover 204 of 300 levels, and macro-structure runs reach
**13 consecutive levels**. The engine's own novelty yardstick confirms it: rolling min-Hamming
distance against the last 20 emissions has a **median of 3.00 against the ledger's own
"distinct enough" threshold of 5**.

**Three root causes, all cheap:**

- **Nine of fourteen mask builders silently ignore the `jitter` parameter**
  (`layout_mask.dart:68-95`). Corridor yields **7** distinct outlines in 4,000 rolls;
  asymmetric yields **15**. Organic blob, which does get jitter, yields 3,827.
- **`_refinePlanMaskDensity` silently overwrites the chosen silhouette** on Hard/Expert
  whenever `mask.length > 1.15 × target`, substituting from a four-entry dense list
  (`director.dart:417-455`). This is what produces the 68% lattice share.
- **The diversity ledger can't see shape.** Its fingerprint packs a 3-bit silhouette id, a 3×3
  density bitmap and a family index (`diversity_ledger.dart:56-73`) — two different 8×8 donuts
  read as novel.

## F5 — Density bouncing has almost no headroom in the knob you'd reach for · ASSUMPTION CORRECTED

Hard's node count is not a distribution. It is the constant **25**: p5 = p50 = p95 = 25, and
194 of 200 levels ship exactly 25. The Director's fill-ratio expression `0.32 + rand·0.12` is
**dead on 187 of 200 Hard levels** — it always clamps up to `lo = 25`. On an 8×8 the
expression can never exceed 28 nodes anyway.

All observed Hard density variance comes from **mask size swinging 25→64 cells**, not from node
count moving at all. And the ceiling is closer than the declared band suggests: the FSR cap is
disabled below 28 nodes (`difficulty_profile.dart:89-98`), so pushing past 28 switches on an
evaluator rule for the first time and boards that pass today start failing.

Meanwhile `kHardEffectiveFillMin/Max = 0.45/0.60` and `kDailyEffectiveFillMin/Max` are already
declared at `level_configuration.dart:63-68` — and **nothing reads them**. They are the
vestigial shape of exactly the feature being asked for.

**Therefore: density bouncing must modulate mask and grid span, not node count.** That is also
where the variance already lives, so it is the cheaper lever *and* the only one with real
headroom.

---

## Device run — Pixel 8a, 600 levels

Solver-driven autoplay, full level lifecycle per level (generate, lay out, solve). 600 wins,
**zero stuck boards** — solvability holds.

| Mode | n | p50 ms | p90 | p95 | p99 | max |
|---|---|---|---|---|---|---|
| Easy | 50 | 650 | 804 | 871 | 1455 | 1475 |
| Medium | 50 | 993 | 1414 | 1495 | 1543 | 1697 |
| Hard | 500 | 2197 | 2402 | 2477 | 3142 | 4113 |

Hard drifts only mildly across 500 levels (p50 2159 ms → 2241 ms), so there is no cumulative
leak. The five boards over 3.5 s are levels **225, 250, 350, 425, 450** — every one a multiple
of 25, i.e. the seeded boss/milestone path. That matches the known unbounded seeded Director
stall and is the one latency risk any new work must not feed.

Headless generation latency for comparison: Hard p95 260 ms against a 200 ms budget; Daily p95
1353 ms, max 4834 ms against a 400 ms budget that cannot preempt a single in-flight retrograde
construction.

---

## Architecture: a strategy layer, not a second generator

**The generator already has a session-state slot.** `DiversityLedger` and
`SilhouetteSessionTracker` are constructor-injected (`level_generator.dart:127-138`), live on a
process-lifetime static (`level_manager.dart:12`), and **already change which boards ship**. A
`SessionContext` is a third parameter of identical shape. Session awareness is a wiring change;
what's missing is *player* state, not session state.

### The shape of a strategy

A `BoardStrategy` is a named, pure modulator with four parts. It never runs its own search — it
biases the search that already exists.

1. **Precondition** — mode, sector, and session-state gates deciding eligibility.
2. **Plan deltas** — bounded nudges to the Director's plan: fill ratio, mask selection weights,
   grid span, mechanic budget, direction entropy.
3. **Scoring terms** — added weights in the existing candidate K-loop, so a strategy *prefers*
   rather than *demands*.
4. **Verification predicate** — a cheap post-hoc check on the finished board. If it fails, the
   board still ships; only the strategy's telemetry records a miss.

That last point is the whole answer to "it should not fall back". Strategies are **soft**: they
re-weight a search that already produces a valid board, so an unsatisfiable strategy costs a
telemetry miss, not a regeneration. Zero added fallback pressure by construction, and no new
time in the budget.

### The seams

| Seam | Site | What a strategy modulates | Risk |
|---|---|---|---|
| Mask selection | `director.dart:456, 505` | silhouette weights, jitter, minCells | RNG stream shift |
| Density | `director.dart:~560` | fill ratio *and* grid span | node floor is load-bearing |
| Candidate scoring | `level_generator.dart:~1099` | preference terms | low — ranking only |
| Enrichment | `level_enrichment.dart:56` | core / lock / relay placement | solvability invariant |
| Direction assignment | `retrograde_constructor.dart` | local direction entropy (traps) | construction cost |

---

## The attention system — and the one rule that makes it fair

The "three lefts then a right" instinct is a documented effect, and the research handed back a
fairness rule that happens to point the same direction as effectiveness.

**The decisive finding.** In Bilalić, McLeod & Gobet's chess Einstellung eye-tracking work,
when the trap move was *suboptimal but sound*, **47% of 2223-rated experts fell for it — the
same rate as novices**. When the trap move was a *blunder*, **0%** did. Low-cost traps are
simultaneously the ones that work best and the ones players forgive.

The mechanism for "legible at rest, misread at speed" is not a rendering trick — it's **local
direction entropy**. An odd arrow among identical arrows pops out preattentively and can't be
missed; the same arrow among heterogeneous arrows requires serial search at roughly 29 ms per
item. That's a pure board-generation parameter: no art changes, every glyph at full contrast.

The design line, in one sentence: **induce slips, never mistakes** — the player must be able to
reconstruct instantly what they should have noticed. And Chain Pop already owns the ideal trap:
a misread node simply **doesn't fire**. Zero-cost "wait, look again" beat, no new systems.

The taxonomy runs to 28 patterns — 18 fair, 4 borderline with named guardrails, 6 rejected.
Highest-volume fair ones: **Long Lane Blocker**, **Broken Run** (the original idea),
**Incongruent Neighbourhood**, **Continuity Line**, **Anchored First Tap**, **Sector Habit
Break**.

**Rejected, and worth knowing why:**

- **Occlusion Swap** — mutating board state during an animation. Change-blindness data says it
  would work at ~50% catch rates, which is precisely why it must be refused.
- **Lying Secondary Cue** — a glow or tail implying a direction other than the arrow's. Most
  likely to creep in accidentally during art polish, so it belongs on the art review checklist
  by name.
- **Illegible Glyph**, **Late Reveal**, **Stochastic Node**, **Timed Trap**.

**Two hard constraints.** Single-tap undo is a *prerequisite*, not a nice-to-have — Valve
classified a genuine perceptual-set failure in Portal playtests as a bug and removed it; the
only thing separating that from this feature is cost. And every trap node must lie on the
solution path: a red herring wastes time and teaches nothing, whereas a trap is fully truthful
and catches an assumption the player brought.

One more: **don't build covert autopilot-adaptive difficulty.** A placebo study found that
*telling* players the game adapts to them raised immersion whether or not it actually did. No
published method detects flow from touch input alone. The honest framing is strictly dominant —
cheaper, and no backlash risk.

---

## Build order

Sequenced by evidence strength and by how much each one disturbs the seed stream. P0–P2 are
pre-launch; P3 onward is a deliberate regeneration.

### P0 — Instruments first, no behaviour change
*No seed impact · low risk*

Two metrics don't exist and every later phase is graded on them: **taps-to-win** (sequential
move depth, distinct from wave depth) and **largest single-tap cascade**. Add both to the corpus
report utilities and CSVs. Add a per-mode taps-to-win floor assertion so F1 can never regress
silently.

- **Done when:** Hard/Medium/Easy CSVs carry both columns; a canary test fails on today's Medium.

### P1 — Fix the jiffy: retarget the core band to tap depth
*Highest value · moves seeds*

Change `_climaxBandCoreIds` to select on **sequential tap index** rather than removal-wave
percentile, keeping the same `[0.35, 0.65]` band. Add a hard floor: no board ships with
taps-to-win below a per-mode minimum. Raise Medium's core count from 2 to 3 so the spread
constraint bites the way it does on Hard.

- **Target:** Medium p50 taps-to-win 8 → 12–14; ≤6-tap share 44% → under 5%; min never below 6.
- **Re-baseline:** `level_enrichment_test`, `report_medium_100`, `corpus_benchmark`.
- **Watch:** don't over-correct — Hard is already right; leave it alone.

### P2 — Unlock the variety already paid for
*Large win · partly moves seeds*

Four changes, ordered by value per unit of risk:

- **Pass `jitter` to the nine builders that ignore it.** Stream-neutral by construction, zero
  seed impact, no test should object. Corridor goes from 7 distinct outlines to hundreds.
- **Decouple `minCells` from `minNodes`** (`director.dart:506`). Eliminates essentially all 24
  Hard rectangle fallbacks and un-deletes half the diamond/archipelago/corridor rolls. Does
  *not* touch the node floor, so the FSR rule is untouched — but Hard's RNG consumption shifts,
  so the Hard corpus needs re-baselining.
- **Loosen `_refinePlanMaskDensity`'s 1.15× clamp** or exempt organic archetypes. This is what
  directly attacks the 68% lattice share.
- **Raise `allowedComponents`/`allowedSingletons`** from `max(2, maskComponents)` to
  `maskComponents + 2` (`visual_composition.dart:164, 190`) — 2,614 Hard rejects are components
  rejects, and this is what "weird shapes" actually needs.

**Also free:** a thickened `checkerboard` (built, never selected) and `pickIrregularKind` — a
complete unused second selection API that already takes a `preferred` subset. That is the
experimental/backup pool, already plumbed.

**Rule:** **append** to shape pools, never reorder — the seeded path reads `pool.first`, so
appending never repaints a milestone board.

### P3 — Session context and density bouncing
*New subsystem*

Add a `SessionContext` injected into the generator exactly as `DiversityLedger` is — **no
per-level signature changes**. Detect a session boundary in `main.dart` against a persisted
`last_session_end_ms`; write it in the `paused` branch of `game_screen.dart:607-615`, which
already fires at the right moment and currently does half the job.

Then implement density bouncing **on mask and grid span**, per F5, honouring the already-declared
`kHardEffectiveFillMin/Max` constants. Ramp toward the band ceiling as session length grows, and
reset on a new session.

- **Do not:** push Hard node count past 28 — that switches on the FSR cap for the first time and
  mass-rejection follows.
- **Contract:** a neutral default `SessionContext` keeps every existing generation suite
  byte-identical — the same contract `timeBudget` already honours.

### P4 — The attention layer
*Needs undo first*

Start with the six highest-volume fair traps, driven by local direction entropy at the
retrograde direction-assignment seam. Machine-checkable generation gates: same-direction run
length ≤ 4, detection cost ≤ 3 s at 29 ms/item, trap node on the solution path, ≤ 2 traps per
board, ≥ 70% of traps at zero cost.

- **Prerequisite:** single-tap undo, confirmed present and frictionless.
- **Prefer:** Closure Gap and its relatives — the same perceptual principle pointed at a *bonus*
  instead of a penalty. Strictly safer framing.

### P5 — Multi-session and cross-session memory
*Mostly wiring*

Three things already exist and are simply unwired: `DiversityLedger.serialize/restore` has zero
callers, so every launch starts with an empty anti-repeat window; a working consecutive-day
streak is computed and **never shown** in the daily UI; and `LevelResult` carries the full
per-level performance vector and is discarded after grading stars. Nothing tracks losses at all.

Also add concrete-shape bits to the ledger fingerprint so two identical donuts stop reading as
novel (F4).

---

## Two decisions needed before P1

1. **Determinism.** Session-adaptive generation means the same level id no longer always
   produces the same board. Note that this is *already true* — `generate(130)` and `generate(7)`
   return different boards on repeat calls today, and `level_generator_test.dart:195` passes only
   because id 42 happens to be stable. Decide whether repeat-call stability is a real requirement
   or a test asserting something the engine never promised.
2. **Regeneration window.** P1 and most of P2 move seeds, so every existing player's level *n*
   becomes a different board. Pre-launch this is free. It is not free later — so the question is
   whether these land before the closed test, or wait for a deliberate content refresh after it.

---

## Known pre-existing red

Unrelated to this work: the `corpus_benchmark` milestone-seed canary still fails —
`milestone-overload` emits no seed annotation. That is the known milestone-fallthrough bug, not
a regression.
