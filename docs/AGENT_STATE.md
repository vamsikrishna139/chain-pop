# AGENT_STATE — Board Presence, Density & Progression

Execution log for the locked plan *"Board Presence, Density & Progression —
Evidence-Backed Plan"*. One section per phase: what changed, the corpus delta,
any deviation (justified + reversible), and the next gate.

Corpus instrument: `report_hard_100_test` / `report_medium_100_test` /
`report_daily_10_test` (the last now runs 30 consecutive date keys, so the
corpus is 230 boards). Production 200 ms budget. CSVs in `docs/playtests/`.

**Corpus noise floor.** Re-running the unchanged tree reproduced 206/210 rows
byte-for-byte. Four Hard rows (L255, L276, L603, L1277) differ run-to-run
because the 200 ms budget escape hatch is wall-clock dependent and picks a
different candidate. Medium and Daily are fully deterministic. Treat ≤4 changed
Hard rows as noise; anything larger is a real delta.

---

## Immersion — code facts re-verified against the working tree

All 19 E-facts in the plan hold as written. Confirmed directly:

| Fact | Confirmed at |
|---|---|
| E1/E2 | `board_layout.dart:117-144`; single literal `targetFill: 0.80` at `chain_pop_game.dart:366` |
| E5 | `node_component.dart:67-70` — `size: Vector2.all(cellSize * 0.82)`, default `PositionComponent` hit rect |
| E6 | `director.dart:535-554` — `0.32 + rand·0.12`, then `clamp(lo, hi)` with `lo = max(profile.min, difficulty.minNodes)` |
| E7 | `LevelConfiguration.targetNodeCount` is read only by the generator's retry rescale, never by the Director's node-count draw |
| E8/E9/E10 | `level_configuration.dart:323-332` (span saturates at 8), `:335-349` (hard clamp `(6, sector>=5 ? 9 : 8)`, same range both axes) |
| E11 | `visual_composition.dart:99-115` — blobVsGrid `< 0.50` reject, occupancy `< 0.35` reject |
| E13/E14 | `level_generator.dart:984-987` waveZeroWidth **descending**; `_spatialDensity` is the last tie-break |
| E16 | `generateDailyChallenge` passes no `timeBudget` → `budgetWatch`/`budgetFallback` are both dead on that path |
| E17 | `LevelMetrics.compute(level)` at `:733` runs on the pre-enrichment board; `_enrichLevel` runs at `:522` |

`flutter analyze`: **No issues found.** Baseline suite green.

**One correction to the plan's own numbers:** the real runtime reserves are
**172 / 110** on 390×844 (not the estimated ~167/110), and **184 / 110** on
430×932. Measured by pumping a real `GameScreen` — see P0.

---

## P0 — measurement baseline (test-only) ✅

**Changed**
- `test/game/levels/generation/board_report_utils.dart`
  - Reference insets corrected from the `ChainPopGame` constructor defaults
    (140/92 — placeholders that only survive until the first post-frame HUD
    measurement) to the **real** ones the app applies. Band on 390×844 is
    **342×538**, not 342×588.
  - Added a second reference device (430×932, band 382×614) via
    `ReferenceDevice`.
  - Added `FitterVariant` + `fitCellPx()`: re-scores any board under alternative
    fitter parameters (per-axis fills, bbox-vs-grid focus, grid cap on/off)
    **without touching app code**.
  - New per-board metrics: `bboxOccupancy`, `largestEmptyRowRun`,
    `largestEmptyColRun`, `largestEmptyRegion` (4-connected), `isolatedNodeCount`,
    `meanLocalDensity` (occupied 8-neighbours / 8), `tapPx`. All wired into the
    per-level line, the summary table and the CSV.
  - `printFitterSweep()` — the Experiment A instrument.
- `test/screens/playfield_insets_reference_test.dart` **(new)** — pumps a real
  `GameScreen` at both reference sizes and asserts the harness constants match
  what `GamePlayfieldInsetController` actually hands the engine. This is the
  guard that stopped the drift from being invisible.
- `test/game/levels/generation/board_report_baseline_test.dart` **(new)** —
  asserts `FitterVariant.current` reproduces the shipped
  `BoardLayoutMetrics.fitCellSizeForBoundsCappedToGrid` exactly across
  4–12 grids on both devices, plus unit coverage of the composition metrics.

**Corpus delta (measurement only — no board changed)**

| | before (140/92) | after (172/110) |
|---|---|---|
| Hard screen-empty p50 | 85.5 % | 84.1 % |
| Hard board cover p50 | 37.2 % | 40.7 % |
| Hard cell px p50 | 34.2 | 34.2 |

Cell size is unchanged because the width axis binds either way; only the band
denominator moved. Matches the plan's predicted ~40 % / ~84 %.

**Deviation:** none.

---

## Experiment A — offline fitter sweep ✅

Same 210 boards, four fitter parameterisations, two devices, zero app changes.

**390×844 (reference device)**

| variant | cell p50 | cover p50 | cover ≥55 % | tap ≥44 pt |
|---|---|---|---|---|
| current 0.80/0.80 | 34.2 | 40.7 % | Hard 3/100 | Hard 13/100 |
| **perAxis 0.94/0.98** | **40.2** | **56.2 %** | **Hard 90/100, Med 97/100, Daily 10/10** | Hard 28/100 |
| grid-focused 0.94/0.98 | 40.2 | 56.2 % | Hard 90/100 | Hard 28/100 |
| bbox uncapped 0.94/0.98 | 40.2 | 56.2 % | Hard 90/100 | Hard 29/100 |

**430×932:** perAxis gives cell 44.9, cover 55.0 %, tap ≥44 pt on **97/100** Hard.

**Conclusions that drive the plan**

1. **P1 alone clears the cover gate on the reference device** — median 56.2 %
   against a ≥55 % target, on 90 % of Hard boards. No generation change needed
   for DoD #1.
2. **The riskier variants buy nothing.** Releasing the grid cap or fitting to the
   full grid instead of the occupied bbox produces the *same* cell size to one
   decimal, because the grid cap is already the binding term on almost every
   board. P1 therefore ships the conservative variant: keep bbox focus, keep
   `cappedToGrid`, change only the fills. This removes a whole class of
   clipping risk the plan had allowed for.
3. **Tap targets are a column-count problem, not a fill problem.** At 390 pt an
   8-column board yields 40.2 px however the fitter is tuned — 44 pt is
   unreachable without dropping to ≤7 columns. Layout gets 28/100 Hard boards to
   44 pt; the other 72 are 8-wide. This is exactly the trade the plan flagged,
   and it makes **P5 the only route to full tap compliance on 390 pt phones**.
   P2 still triples the effective target (28 px → 40.2 px) and is worth shipping
   on its own.
4. Residual gap after P1: cover 56 % vs the 70–85 % P5 ambition. That gap is
   entirely board *aspect*, as the plan predicted — it cannot be closed by the
   fitter.

**Deviation:** none. Experiment A confirms the plan's arithmetic (predicted
cell 34.2 → 40.2 and cover 40 % → 56 % at 8×8; measured exactly that).

---

## P1 — per-axis layout fitter ✅

**Changed**
- `lib/game/board_layout.dart` — `kBoardWidthFill = 0.94`, `kBoardHeightFill =
  0.98` as named top-level constants; `fitCellSizeForBounds` and
  `fitCellSizeForBoundsCappedToGrid` take `widthFill` / `heightFill`, with
  `targetFill` retained as an optional both-axes convenience so every existing
  single-fill caller and test keeps working unchanged.
- `lib/game/chain_pop_game.dart:366` — the `targetFill: 0.80` literal is gone;
  the call site now passes the two named constants.
- `test/game/board_layout_test.dart` — new `per-axis board fill (P1)` group.

**Invariant preserved.** `cappedToGrid` is untouched; the new property test
sweeps grids 4×4–12×12 × bboxes from a 3×3 tutorial board to the full grid ×
four device bands (320×568, 360×800, 390×844, 430×932) and asserts
`cell × gridW ≤ bandW` and `cell × gridH ≤ bandH` every time. `maxCell` stays
96; `minPreferredCell` unchanged.

**Corpus delta (390×844)**

| | before | after |
|---|---|---|
| cell px p50 | 34.2 | **40.2** |
| board cover p50 | 40.7 % | **56.2 %** |
| Hard boards ≥55 % cover | 3/100 | **90/100** |
| node count, opening, FSR, CUD, waves, in-band, latency | — | **unchanged** |

**Deviation from plan:** the plan allowed for a bbox-focused-vs-grid-focused
choice and for relaxing the grid cap. Experiment A showed all three variants
produce the same cell size to one decimal, so P1 ships the most conservative
one — bbox focus and grid cap both retained. Strictly less risk than the plan
budgeted for.

**Rollback:** set `kBoardWidthFill` and `kBoardHeightFill` to `0.80`.

---

## P2 — tap targets ✅

**Changed**
- `lib/game/components/node_component.dart` — `containsLocalPoint` override.
  The painted sprite stays `cellSize × 0.82`; the *hit* region becomes the full
  cell, which is the largest region that cannot steal a tap from a neighbour
  (nodes sit at cell centres, so full-cell regions tile the board exactly).
  Intervals are half-open and shifted by a sub-pixel `_hitBoundaryEpsilon` so a
  tap on a shared grid line resolves to exactly one node.
- `test/game/components/node_hit_box_test.dart` **(new)**.

**Why the epsilon.** With plain half-open intervals, probes at exact multiples
of the cell size fall on a seam where `(x + 0.5) * cell` and `x * cell` disagree
in the last float bit, and the tap is dropped by *both* neighbours. Shifting the
whole tiling down by 0.01 px keeps it gap-free and overlap-free while moving no
perceptible boundary.

**Verified.** On a fully packed 8×8 board, the centre and all four corners of
every cell (320 probes) resolve to exactly one node, and that node is the
correct one. Every interior grid line and four-way corner (147 probes) resolves
to exactly one node. A sparse board still leaves genuine gaps unclaimed, so
empty cells do not swallow taps. Tutorial coach-mark and long-press ray-preview
paths re-verified via the existing widget suite (59 screen tests green).

**Delta:** effective target 28 px → **40.2 px** on an 8-column board,
**45.9 px** at 7 columns.

**Documented limitation, per the plan.** 44 pt is *unreachable* on an 8-column
board at 390 pt regardless of fitter tuning (342 × 0.94 / 8 = 40.2). 28/100 Hard
boards reach 44 pt on 390 pt; 97/100 do on 430 pt. Full compliance on small
phones requires width ≤ 7 — that is P5, and it is gated on Experiment B.

---

## P3 — Daily generation budget ✅ (partial; residual documented)

**Changed**
- `lib/game/levels/level_manager.dart` — `dailyGenerationBudget = 400 ms`
  (campaign budget × 2), passed by `getDailyChallenge`.
- `lib/game/levels/generation/level_generator.dart` —
  `generateDailyChallenge` takes an optional `timeBudget`; generation suites
  leave it null so their results stay byte-identical.
- `lib/game/levels/generation/level_generator.dart` — **`mechanicShortFallback`**
  (see below).
- `test/game/levels/generation/report_daily_10_test.dart` — extended to 30
  consecutive date keys, writes `report_daily_30.csv`, and now gates latency.
- `test/game/levels/generation/daily_budget_probe_test.dart` **(new)** —
  re-runnable worst-case probe.

**Seeded-path question resolved.** The unbounded seeded/milestone sub-path is
entirely inside `if (applyMilestones)`, and Daily passes `applyMilestones:
false`. It cannot be entered from Daily.

**Passing the budget was not sufficient — root cause found.** With the budget
wired up, 2026-08-19 still took **5.0 s**. `budgetFallback` was unreachable for
a second reason: when over budget the retry regime scales the node count *down*,
which makes a lock/relay shortfall **more** likely, so a starved date key kept
hitting the mechanic-budget `continue` and burned all 40 attempts no matter how
much wall clock had elapsed. Fixed by retaining a mechanic-short board as
`mechanicShortFallback`, ranked strictly below `budgetFallback` (a wave-band
miss is a better level than a mechanic-short one) so the top-of-loop escape has
something valid to ship.

**Corpus delta (30 consecutive date keys)**

| | before | after |
|---|---|---|
| p50 | ~300 ms | **211 ms** |
| p75 | — | **299 ms** |
| p95 | — | 1 773 ms |
| p100 | 5 517 ms | 4 345 ms |
| in-band | 80 % (10-day) | **83 %** (30-day) |

No in-band regression — the risk the plan flagged for a tighter budget did not
materialise.

**⚠ DoD #3 not met — residual is structural.** Two of thirty date keys
(20260819 ≈ 4.3 s, 20260906 ≈ 1.8 s) remain far over budget, and **the budget
value is irrelevant to them**: measured at 200 / 300 / 400 / 600 ms, all four
produce the same ~4.3 s worst case. The reason is that the only clock is a
stopwatch *outside* the constructor, so it can bound attempts, renegotiations
and K-loop iterations but cannot preempt a single retrograde construction —
and on these keys one construction takes ~1.4 s (three of them run). The
existing code comment already anticipates this: *"Bounding the seeded path needs
a deadline inside the Director, not a shared stopwatch here."*

Getting p100 ≤ 450 ms requires a deadline **inside** the
Director/RetrogradeConstructor. That is the plan's §7 stop condition ("a change
that should be reversible cannot be made reversible without larger surgery"), so
it is reported rather than attempted.

The gate is therefore expressed on what the budget does govern — p50 ≤ 300 ms,
p75 ≤ 400 ms — plus a hard cap of **2** construction-bound keys (>800 ms, i.e.
2× budget). A newly-slow date key fails the test; the two known ones do not.

**Note on a scary number that was not real.** An intermediate sweep reported
819 s for 20260905. That was **measurement contention** from test isolates left
over after an earlier run was killed — the key generates in 314 ms in isolation
on an idle machine. Recorded here so it is not mistaken for a finding.

---

## P4 — Medium honest band + choice-rhythm ranking ✅

**Changed**
- `lib/game/levels/generation/difficulty_profile.dart` — Medium
  `forcedSequenceRatio` ceiling `0.65 → 0.85`, plus
  `mediumMeasuredFsrP75 = 0.833` recording the derivation, and a comment
  explaining why the old band was wrong.
- `lib/game/levels/generation/metrics.dart` — new `ChoiceRhythm`
  (`directionChanges`, `longestForcedRun`, `multiChoiceFraction`,
  `rankingScore`), computed from the existing `tempoProfile`, so it costs no
  extra solving.
- `lib/game/levels/generation/level_generator.dart` — `ChoiceRhythm` wired into
  the non-Hard candidate comparison, **ahead of** the near-useless
  `_spatialDensity` tie-break. Ranking term only; it never admits or rejects.
- `test/game/levels/generation/choice_rhythm_test.dart` **(new)** — including
  the case that motivates the metric: two profiles with identical FSR and
  identical multi-choice fraction, one a single long corridor and one
  alternating, ranked apart.

**Ceiling derivation (not a guess).** Medium corpus FSR: min 0.367, p25 0.640,
p50 0.750, **p75 0.833**, p95 0.900, max 0.967. `0.85` is the nearest clean
constant at or above the measured p75. The FSR *cap* curve does not interact:
`fsrCapForNodeCount` returns 1.0 below 28 nodes and Medium ships 13–25.

**⚠ Finding that contradicts the plan — DoD #4 is not reachable via P4.**

The plan states Medium's out-of-band cause is "single: FSR". It is not. Failure
attribution over the 100-board Medium corpus, sweeping only the FSR ceiling:

| FSR ceiling | in-band | remaining failures |
|---|---|---|
| 0.65 (before) | 27/100 | FSR 73, waves 25, BF 7, opening 1 |
| 0.80 | 58/100 | FSR 34, waves 25, BF 7, opening 1 |
| **0.85 (shipped)** | **66/100** | FSR 19, waves 25, BF 7, opening 1 |
| 0.90 | 69/100 | waves 25, FSR 4, BF 7, opening 1 |
| 1.00 (FSR removed entirely) | **69/100** | waves 25, BF 7, opening 1 |

**With FSR removed completely, Medium in-band tops out at 69 %.** 25 boards
exceed `waveDepth` max 5 and 7 exceed `averageBranchingFactor` max 8; those
causes overlap with FSR, so eliminating FSR cannot reach the 85 % target.
P4 delivers the largest single improvement available inside its scope
(27 % → 66 %), but **DoD #4 requires re-banding `waveDepth` as well**, which the
plan did not authorise and which is a different question (is a 6–8 wave Medium
board wrong, or is the band wrong?). Flagged rather than actioned — see
"Open items".

**Boards unchanged.** No generation input moved; only which boards the
evaluator admits, and the tie-break order among boards it already admitted.

**Rollback:** Medium ceiling back to `0.65`; delete the `ChoiceRhythm` clause
from `_compareInBandCandidates`.

---

## Experiment B — grid-aspect sweep → **P5 is NO-GO** ✅

Same 100 ids, forced grids, milestone seeds off so the grid is the only
variable.

| grid | nodes p50 | open p50 | open max | in-band | gen p95 | cell | cover | gridOcc | fail |
|---|---|---|---|---|---|---|---|---|---|
| 8×8 (control) | 25 | 10 | 11 | **97/100** | 210 ms | 40.2 | 56 % | 39 % | 0 |
| 7×7 | 25 | 11 | 11 | 77/79 | 210 ms | 45.9 | 56 % | 51 % | **21** |
| 7×9 | 25 | 10 | 11 | 94/100 | 241 ms | 45.9 | 72 % | 40 % | 0 |
| 7×10 | 25 | 10 | 11 | 87/100 | 288 ms | 45.9 | 80 % | 36 % | 0 |
| 7×11 | 25 | 10 | 11 | **81/100** | **374 ms** | 45.9 | 88 % | **32 %** | 0 |

**The plan's central prediction is refuted.** P5 rests on "taller grids lengthen
vertical rays → more nodes blocked at the start → the opening **narrows**", and
that is the reason the plan calls portrait "the interesting direction". Measured:
the opening median is **10 at every aspect** and the max stays 11. Aspect does
not move the opening at all — consistent with `OPENING_BAND_DECISION.md`, where
opening width is set by retrograde construction placing low ids last, not by
board geometry.

**The second predicted benefit also fails to appear.** The plan expects node
count to rise to ~27–31 on taller grids "simply because there are more cells".
It stays at **25** from 7×7 through 7×11, because the Director caps Hard/Expert
mask area at `1.15 × target` (E12) and the target is then drawn from that capped
mask — a self-reinforcing pin. So grid occupancy *falls* from 39 % to 32 %: a
taller board is **emptier per cell**, which is the north-star failure the plan
explicitly warns against ("a 7×12 board at 89 % coverage that is harder to scan
is a failure").

**Gate checklist:** cell ≥44 px ✓ · tap ≥44 pt ✓ · opening inside [3,11] ✓ ·
FSR cap ✓ · **in-band ≥97 % ✗ (81 %)** · **p95 ≤200 ms ✗ (374 ms)**.

Two hard gates fail, and the gameplay upside that would justify the risk does
not exist. **P5 is not implemented.** 7×7 is refuted even more strongly than the
plan's §3 argued — it fails generation outright on 21 % of ids.

---

## Experiment C — FSR vs node count → **the plan's blocker is disproven** ✅

Node counts above the clamp were reached by forcing larger grids (the only lever
available to a test, since the count is pinned at the clamp floor otherwise).
Confound stated: larger grids also lengthen rays.

| nodes | n | FSR p50 | FSR p75 | shipped cap | verdict |
|---|---|---|---|---|---|
| 25 | 116 | 0.66 | 0.73 | 1.00 | uncapped |
| 29 | 4 | 0.60 | 0.60 | 0.64 | ok |
| 32 | 4 | 0.54 | 0.54 | 0.61 | ok |
| 34 | 3 | 0.48 | 0.57 | 0.58 | ok |
| 35 | 4 | 0.53 | 0.53 | 0.57 | ok |
| 42 | 6 | 0.47 | 0.48 | 0.49 | ok |

**The plan's single most emphasised finding is wrong.** It predicts that "at 30
nodes the cap is 0.628 — more than half of today's boards would be rejected",
and blocks P7 on that basis. That inference compares the cap at 30 nodes against
FSR measured at **25** nodes. In fact **FSR falls as node count rises** (p50
0.66 → 0.47 from 25 to 42 nodes): more nodes means more parallel removal
options, so a bigger board is *less* forced. The shipped cap curve tracks that
decline rather than fighting it, and measured p75 sits at or under the cap at
every node count from 29 to 42. Over-cap boards were 0–1 per 40.

The FSR cap therefore does **not** block a node-count increase. Margins are thin
at the top (1–4 points at 34/35/42), so widening the curve slightly would add
safety, but no recalibration is *required*.

---

## P7 — node-count progression: implemented, measured, **rolled back** ⛔

With Experiment C clearing the stated blocker, P7 was implemented as the plan
describes: a sector-scaled Hard node floor (sector 1 → 25, sector 8 → 34),
campaign-only, behind two named constants. Seeded levels were unaffected
(`choosePlanFromSeed` uses `seed.targetNodeCount` when pinned).

**It worked on the target metric and failed two rollback triggers.**

| | before | after P7 |
|---|---|---|
| Hard nodes min/p50/p95/max | 25 / 25 / 25 / 27 | 25 / 26 / **34** / 34 |
| Hard in-band | 97/100 | **78/100** ⛔ |
| Hard gen p95 | 264 ms | **314 ms** ⛔ |
| Hard gen max | 1 258 ms | **157 062 ms** ⛔ |

Node-count progression is real (99×25 → a genuine 25–34 spread), but in-band
collapses to 78 % (trigger: <95 %), p95 exceeds 200 ms, and one level (L908)
took **157 seconds** — the same in-construction unboundedness that limits P3,
amplified by bigger boards.

**Reverted in full.** An earlier comment on this exact code path (still in the
git history of `director.dart`) reached the same conclusion from first
principles: *"raising it trips evaluator rule 3, seed byte-stability, and the
generation perf budget. Unpinning node count is a coordinated retune, not a
knob."* The measurement above is the empirical confirmation. The Hard node floor
is load-bearing and cannot be moved by a one-liner: it is a coordinated
retune of the floor **plus** the E12 mask-area cap, the grid-span saturation
(E8) and the removal-wave bands, and it needs an in-constructor deadline first
so a larger board cannot hang. **DoD #5 is not met**, and the blocker is no
longer the FSR cap — it is latency and wave-band fit.

---

## Experiment D — enrichment drift → **accept, no change needed** ✅

Metrics recomputed on the shipped board vs the same board with everything
`enrichLevel` adds stripped back out (it is the sole source of `locked` /
`relay` / `phaseGroup` and only ever `copyWith`s them, so the reconstruction is
exact).

| metric (post − pre) | min | p50 | max | mean |
|---|---|---|---|---|
| opening | −5 | 0 | 0 | −1.02 |
| FSR (pts) | −6.0 | 0.0 | +24.6 | +3.15 |
| waves | 0 | 0 | +4 | +0.52 |
| CUD | 0 | 0 | 0 | 0.00 |
| BF | −4.4 | −0.1 | 0.0 | −0.99 |

Direction matches the prediction (locks and phase gates only add constraints:
the opening narrows, FSR rises, waves deepen), and the magnitude is small — the
median board does not move at all on any metric.

**Decision: accept.** In-band on the board the evaluator judged is 94/100; on
the board the player actually receives it is **95/100**. Drift costs −1 boards,
i.e. enrichment marginally *improves* agreement. Moving the bands to
post-enrichment would add a full re-validation pass to every candidate for no
measured benefit. Re-run `experiment_cd_test.dart` if enrichment changes.

---

## Final corpus state

| | Hard 100 | Medium 100 | Daily 30 |
|---|---|---|---|
| nodes p50 | 25 | 17 | 26 |
| **board cover p50** | **56.2 %** (was 40.7) | **56.2 %** | **56.2 %** |
| **cell px p50** | **40.2** (was 34.2) | 40.2 | 40.2 |
| **tap px p50** | **40.2** (was 28) | 40.2 | 40.2 |
| screen empty p50 | 78.1 % (was 84.1) | 84.2 % | 77.2 % |
| opening p50 | 10 | 7 | 7 |
| FSR p50 | 70 % | 75 % | 81 % |
| **in-band** | 95/100 | **67/100** (was 27) | 25/30 |
| gen p95 / max | 238 / 1 177 ms | 94 / 122 ms | 1 773 / 4 345 ms |

Hard in-band moved 97 → 95, two rows, inside the ±4-row noise floor and above
the <95 % rollback trigger. The plausible mechanism is `mechanicShortFallback`
occasionally shipping a mechanic-short board on the latency tail instead of
retrying — which is the intended trade, and Hard latency improved alongside it
(p95 264 → 238 ms, max 1 258 → 1 177 ms).

## Definition of done — scorecard

| # | Criterion | Status |
|---|---|---|
| 1 | Board cover ≥55 % on the reference device | ✅ 56.2 % median, 90/100 Hard |
| 2 | Tap ≥44 pt on ≤7-column boards; exactly one node per tap | ✅ 45.9 px at 7 cols, test-proven; 8-col boards are 40.2 px and documented |
| 3 | Daily p100 ≤450 ms; campaign p95 ≤200 ms | ⛔ Daily p50/p75 met, p100 4.3 s on 2 keys (in-construction, structural). Campaign p95 238 ms — pre-existing, improved from 264 ms |
| 4 | Medium in-band ≥85 %, boards unchanged | ⛔ 67 % — boards unchanged ✅, but ≥85 % is unreachable via FSR (69 % ceiling even with FSR removed); needs `waveDepth` re-band |
| 5 | Hard node count a function of sector, after Experiment C | ⛔ C passed, P7 implemented and rolled back on two triggers |
| 6 | Difficulty/solvability/relay tests green; no corpus regression | ✅ |
| 7 | Enrichment drift measured, accept-or-fix recorded | ✅ accept |
| 8 | Everything behind named constants, one-line rollback | ✅ |

## Open items (correctly gated, not started)

- **P6** — promote the P0 composition metrics to ranking terms, and flip E13
  (ranking currently prefers the *widest* opening in band). The plan gates P6 on
  Experiment E, which needs human ranking of rendered boards.
- **Medium `waveDepth` re-band** — the remaining 25 Medium out-of-band boards.
  Needs the same "is the band wrong, or is generation wrong?" evidence P4 used
  for FSR.
- **In-constructor deadline** — the shared blocker behind the P3 residual and
  the P7 rollback. Highest-leverage next piece of generation work.
- **Analytics** — layout metrics (`cellPx`, `boardCoverPct`, `gridOccupancy`,
  `bboxOccupancy`, `isolatedNodeCount`, `largestEmptyRun`, `gridW×gridH`) are
  all computed by the harness and ready to attach to the generation analytics
  path. Product outcome signals (time-to-first-tap, abandonment) still do not
  ship, so the presence hypothesis remains unvalidated with real players.

---

# Unbound V2 — `docs/IMPLEMENTATION_PLAN_V2.md`

## T0.4 — the frozen adversarial corpus ✅ *(2026-08-19)*

The last T0 artifact and the **gate into P1**. Pure measurement: three baseline
CSVs, three invariance guards, and the achievable-depth ceiling. Full write-up
in `docs/playtests/adversarial_baseline/README.md`.

**Changed**

| Path | What |
|---|---|
| `test/…/adversarial_corpus.dart` | **new** — 300 frozen id literals (100 severity + 100 representative + 100 Hard control), view / quintile / severityRank / freeze-time node count, quintile boundaries |
| `test/…/adversarial_corpus_selection_test.dart` | **new** — the one-shot selection run. Checked in for provenance, never re-run |
| `test/…/adversarial_corpus_baseline_test.dart` | **new** — generates, measures, writes the CSVs. Asserts no quality, by construction |
| `test/…/adversarial_corpus_guards_test.dart` | **new** — the three guards, corpus structure, disjointness, and 10 unit tests of the §e classifier. 21 tests, all green |
| `test/…/adversarial_corpus_report.dart` | **new** — identity hashes, mode floors, CSV writer/reader, statistics, classification |
| `test/…/core_depth_ceiling.dart` | **new** — §d achievable-depth ceiling by prerequisite-closure bitmask over spread-legal k-subsets |
| `test/…/board_report_utils.dart` | `writeCsv` split into `kBoardCsvHeader` + `boardCsvRow` so the corpus CSV reuses the identical board block. Byte-identical output |
| `lib/…/level_enrichment.dart` | the one `lib/` change — `CoreSelectionTelemetry`, inert (`sink` null in production), no RNG draw, **proven behaviour-free** |

**Zero production behaviour change, proven not asserted.** The 300 baseline CSVs
were regenerated before and after the `lib/` telemetry landed and diff
byte-for-byte on every column except `genMs`.

### Baseline — Gen V1

| | severity | representative | Hard control |
|---|---|---|---|
| `tapsToWin` p50 | 6 | 5 | 10 |
| ≤ 6 taps | 61 % | 67 % | 1 % |
| `captureRate` p50 | **0.58** | **0.55** | 0.64 |
| geometrically unfixable | 3 / 100 | 5 / 100 | 0 / 100 |

Quintiles (severity), taps p50 / capture p50: Q1 4 / 0.40 · Q2 5 / 0.63 ·
Q3 6 / 0.55 · Q4 7 / 0.62 · Q5 10 / 0.82.

### Three findings that change how P1 gets written

1. **F1 is a selection bug, not a geometry bug.** The Medium selector captures
   barely half the depth the boards already offer (`captureRate` p50 0.55–0.58,
   worst cases 0.22–0.30 against ceilings of 9–20). The shallow boards are not
   shallow boards — they are deep boards with badly chosen cores. P1 can fix
   this without touching geometry, which is exactly what §0.1 claims.
2. **The geometrically unfixable set is small: ~4 %** (3 severity, 5
   representative, 0 Hard). T1.2's bounded repick *can* deliver its invariant on
   the rest — but the set is non-empty, so T1.2 needs a declared behaviour for
   it instead of a silent "ship the best I saw". All are small boards (12–19
   nodes), nearly all Medium sector 2 `coreCount: 1`.
3. **The designed core-selection path is the exception.** The intended
   reach-1 → reach-2 → climax arc fires on 13–17 % of Medium boards.
   26–42 % need the band *widened* before three spread-legal guarded candidates
   exist at all. T1.3's balance note asked for the relaxation rate before tuning
   further: it is 31 % (severity) and 42 % (representative).

### Two deviations from the plan, both justified and both narrowing

**1. Guard 2 hashes the mechanic-stripped board, not the shipped one.**
The plan specified `hash(LevelSolver.nodeWaveIndices)` on the enriched board,
calling it "canonical, deterministic and core-independent". The first two hold;
the third does not. `_canRemoveWithSet` short-circuits on `NodeKind.locked` and
on `phaseGroup > 0`, and `_markSpecialNodes` picks locks with `!n.isCore` and
relays with `!coreRows.contains(n.y)` — so moving a core legitimately moves a
lock, and the guard as written would fire on a *correct* P1. Guard 2 now hashes
wave indices over a board with `kind` and `phaseGroup` stripped, which is
genuinely a pure function of geometry. The enriched-board hash is still
recorded, as `enrichedSolutionHash` beside `mechanicHash` and `coreSetHash`, so
lock/relay movement stays visible in the diff without being fatal. Same reason
`kind` is out of guard 1.

**2. Every corpus generation uses a fresh `LevelGenerator.neutral()`.**
Caught by the first baseline run, not by reading: **L1411/medium came out at 17
nodes / 8 taps in the ascending 600-id selection sweep and 18 nodes / 4 taps in
the 300-entry corpus sweep** — same id, same mode, same code. The diversity
ledger and the silhouette tracker are *session state* per T0.0a, so a shared
generator makes the board a function of the whole preceding sequence. T0.4§b
freezes on `(levelId, mode, generationVersion)`, and that key is only
well-defined if the board is a function of it. This is consistent with T0.0b
rather than a contradiction of it — the probe explicitly declines to assert that
a warmed generator reproduces a fresh one's boards.

The corpus now proves this on every run instead of asserting it: `freezeNodes`
is recorded per severity board during selection and re-measured during the
baseline sweep, which visits the same ids in a completely different order.
**100/100 agree.** The `report_*_100` harnesses keep their shared instance
deliberately — they measure the sequence a session produces, a different and
equally legitimate question — which is why a corpus row and a report row for the
same id can differ and are never compared.

### T0.4 definition of done

| # | Criterion | Status |
|---|---|---|
| 1 | 200 Medium + 100 Hard frozen as literals, keyed on `(levelId, mode, generationVersion)` | ✅ |
| 2 | Sector 2 and single-core boards present in severity; no filters | ✅ S2 19, `coreCount: 1` 19, `coreCount: 0` 7 |
| 3 | All five quintiles at n=20; boundaries recorded | ✅ |
| 4 | Severity ⊥ representative ⊥ Hard ⊥ `kReportSampleIds` | ✅ asserted in the guards test |
| 5 | Three baseline CSVs with version headers; `ceilingTapDepth`, `captureRate`, `geometryHash`, `solutionHash` populated | ✅ |
| 6 | All three guards green at baseline | ✅ 21/21 |
| 7 | `ceiling < floor` count reported — input to T1.2's design | ✅ 3 / 5 / 0 |
| 8 | README states the evaluation-only rule verbatim | ✅ |
| 9 | T0.3 canary still red on Medium, green on Hard | ✅ unchanged (66 % / p50 10) |
| 10 | Zero production behaviour change | ✅ 300-board CSV diff, before vs after the telemetry |

### The gate into P1 is now open

The baseline must be **committed to git before T1.1 begins**. Re-running the
baseline test overwrites it, which is how the post-P1 diff is produced — and
also how the entire comparison is lost if the Gen V1 rows were never committed.

---

## Daily Challenge ANR — diagnosed and mitigated *(2026-08-19)*

**Report:** "daily challenges is not launching… the app crashed upon launch",
with a screenshot of *Unbound isn't responding* over the main menu.

**It was neither.** `adb logcat -b events` named the trigger exactly:

```
am_anr: com.adbkv.chainpop — Input dispatching timed out
        (MainActivity is not responding. Waited 5001ms for MotionEvent)
```

An **input** ANR, not a launch failure — cold launch measures `TotalTime: 730ms`.
The menu was simply the last frame painted before the thread froze. Not a
release/R8 issue either: it reproduces in pure Dart with no device.

**Cause.** Daily key `20260819` (today) is pathological — 4469 ms against a
30–760 ms spread across the other 30 August keys. `dailyGenerationBudget` does
not bound it:

| key | budget | elapsed | retrograde attempts |
|---|---|---|---|
| 20260819 | 200 ms | 4309 ms | 3 |
| 20260819 | 400 ms | 4409 ms | 3 |

Identical at both budgets and only three attempts, so the entire cost sits
*inside one retrograde construction* — the known in-constructor deadline
problem. `daily_challenge_calendar_screen` then called `getDailyChallenge`
**synchronously inside the tap handler**, which is what turned a slow frame into
an ANR.

**Fix.** `LevelManager.getDailyChallengeAsync` runs generation on a worker
isolate via `Isolate.run`, with an in-place fallback if no isolate can be
spawned; the calendar awaits it behind a *Building incident…* veil that also
guards re-entrancy. Zero change to generation itself.

**A second bug this closed.** `LevelManager.generator` is static, so the
synchronous path built the Daily from whatever the diversity ledger and
silhouette tracker carried out of campaign play. Those are *inputs* (T0.0a), so
the Daily was never "the same layout for every player on that date" — it
depended on how much the player had played first. A worker isolate starts from
fresh statics, making the board a pure function of `dayKey`.

**Verified on a Pixel 8a** (release build): today's daily opens with the veil
visible and the UI responsive; `am_anr` count since install is zero.

**Still open — the real fix.** The 4.4 s construction is untouched; the isolate
only stops it blocking the UI. The campaign path shares the root cause and is
*not* moved to an isolate: `LevelManager.generator` is session state there, and
a per-call isolate would reset the diversity ledger every level and cost
variety. That makes the in-constructor deadline the prerequisite for both.

---

## Milestone-seed fallthrough — every 25th level ships as its landmark ✅

**2026-08-20.** Three tests were red on `new_improvements`, all pre-existing and
all the same defect: `campaign_mechanic_audit_test` (L150 emits no
`milestone-overload`), `corpus_benchmark_test` (seed annotation null), and
`milestone_latency_test` (slot 725 at 52 s against a 3 s ceiling).

**What was wrong.** Milestone slots pin a hand-authored silhouette. When the
seeded path could not seat the level's full lock/relay budget it discarded the
candidate and retried; after 40 attempts it fell through to the ordinary
procedural pipeline. The level still generated and still played, so nothing in
the suite noticed — **16 of 40 Hard slots and 8 of 40 Medium ones shipped with
no landmark at all**. The main generation path had the same defect and P1 fixed
it (`exhaustedFallback`); the seeded path never got the same treatment.

**Step 0 — instrumentation first, and it decided the rest.** `LevelGenerator`
counted only seeded attempts that *shipped*, which is why this survived: a lost
milestone was indistinguishable from a level that never had a seed. Five
counters now record the funnel per seed id (`attempts`,
`constructionFailures`, `validationFailures`, `mechanicShortfalls`,
`fallthroughs`), exposed through `snapshotSession()`.
`milestone_seed_audit_test` (report-tagged, asserts nothing) prints it for all
40 slots × {Medium, Hard}.

The measurement was unambiguous: **validation failures were zero everywhere**,
and on every lost slot 30–39 of the 40 attempts were mechanic shortfalls. The
shortfall retry was the fix; the other two steps were secondary.

| | before | after |
|---|---|---|
| Hard slots losing the landmark | 16 / 40 | **0 / 40** |
| Medium slots losing the landmark | 8 / 40 | **0 / 40** |
| Hard slot 725 | 42.5 s | **2.4 s** |
| Hard total, 40 slots | 88.2 s | **7.2 s** |

**Step 1 (`level_generator.dart`).** After
`_kSeedMechanicShortfallRetries` (3) shortfalls the seeded path ships the board
from the current attempt instead of discarding it — the staged emission is
still live, so `_commitPendingEmission()` works and the telemetry stays honest.

**Step 2 (`director.dart`).** `GenerationPlan.pinnedSilhouette` marks
seed-derived plans, and renegotiation no longer swaps the silhouette on odd
depths for them (both `renegotiate` and `renegotiateAfterGreedyFailure`). A
milestone could previously ship as some other shape and still be counted as
that seed's emission. Costs nothing measurable: 0/40 lost either way.

**Step 3 — proposed, measured, and NOT applied.** The plan called for an
8-attempt cap on the seeded loop. The audit shows sniper slots fail construction
repeatedly and then *succeed*, at attempt 14 (L100), 15 (L400), 18 (L1000) and
19 (L600). An 8-cap would trade six landmarks for latency that Step 1 had
already removed. The comment at the loop head records this so it is not
re-attempted blind. The visible-failure half of Step 3 shipped as the
`fallthroughs` counter.

**The trade this makes, stated plainly.** Recovered milestones ship with
**0 locks** against a budgeted 1–2 — measured on all ten of them (150, 250, 350,
450, 550, 650, 725, 750, 850, 950); cores seat 3/3 and relays seat in full. It
is all-or-nothing, not shaved: `_canSafelyLock` refuses every non-core node on
that geometry. `corpus_benchmark_test`'s `_expectMechanicsMatchBudget` asserted
exact equality and now asserts `<=` for locks/relays (cores stay exact), which
is the contract `campaign_mechanic_audit_test` always used. **Locks seating 0 on
seeded geometry is a real, separate defect** — the relaxation makes it visible
rather than hiding it, because before this the level quietly stopped being a
milestone and the lock count looked correct.

**Re-baselining.**
- `corpus_identity_test` re-pinned to `6a19bb9b24d846e3` / 164846 bytes.
  Exactly **one** board moved and it was named, not assumed: dumping the corpus
  with and without the change reports `50/medium` alone. The mover is Step 2,
  not Step 1 — reverting `pinnedSilhouette` restores the old hash exactly. Same
  grid, same node count (`50/medium/9x9/28`), different layout.
- Adversarial corpus: **550/medium** (16 → 27 nodes) and **1225/medium**
  (23 → 21) moved, declared in `kMilestoneSeedFixMovers`. 550's node count is
  the tell — 16 was the procedural fallback, 27 is the overload seed's own
  target. 950/medium was expected to move and did not. Baseline re-captured;
  the previous CSVs are archived under
  `docs/playtests/adversarial_baseline/p1_pre_milestone_fix/`.

**New gate.** `milestone_identity_test` — all 40 slots × {Medium, Hard} must
emit their seed. It also checks the shipped silhouette did not collapse to the
rectangle fallback, but only where the mask is renderable at that grid, queried
live rather than hard-coded.

**Found and not fixed (both pre-existing, both out of scope).**
1. **Hard diamonds cannot be diamonds.** `buildSilhouetteMask` returns null for
   the diamond at every Hard milestone grid — Hard's `minNodes` floor (25) is
   above what the diamond carves out of an 8×8 — so the Director's rectangle
   fallback is forced. Hard diamond milestones have always shipped as
   rectangles; the fix only changed whether they ship as diamond *seeds*.
   Raising them means moving Hard's node floor, which is load-bearing
   elsewhere. The new gate is written so it starts enforcing these slots on its
   own if the floor is ever retuned.
2. **`enrichLevel` drops `silhouetteId` and `portalPairs`.** It rebuilds
   `LevelData` with five fields and both are omitted, so every shipped board has
   a null silhouette (read at `game_flow_controller.dart:54`) and no portal
   pairs (read by the solver and two render components). Unrelated to this work
   and not touched.
3. **The in-constructor deadline, again.** `campaign_mechanic_audit_test` takes
   over an hour because single non-milestone Hard levels cost 4–68 s each
   (L629, L651, L663, L696, L717, L755, L759, L777, L827). None are seeded, so
   none are affected by this change — this is the known root cause the Daily
   isolate worked around.

---

## P1 re-baseline — the corpus guards were red on the shipped tree ✅ *(2026-08-21)*

**Trigger.** A verification pass over T0 → P2 ran `flutter test --tags slow`,
which the phase sign-offs had not: 34 passed, 6 failed. Four were the T0.4
guards (geometry, solution structure, node-count equality, ceiling invariant);
two were the pre-existing `relay_softlock_property_test` pair.

**What the guards were saying.** The committed baseline (2026-08-20 04:19) was
captured part-way through P1, before the core selector's final revision, which
shipped in `ff54cf0` a day later. 40 of 300 boards no longer matched. So P1's
published numbers described a generator revision that never shipped.

**Attribution.** Core selection: 37 of the 40 shipped a different core set,
which moves lock/relay placement, which moves which candidate survives
validation (plan §0.1). Rejected alternatives: the late attempt-exhaustion
fallback (one level in 1..1500; every other generator-side edit in `ff54cf0` is
on the seeded path), and a measurement-harness change (re-measuring with a
shared `LevelGenerator` fits the stale baseline *worse* — 76 node mismatches
against 18).

**Changed**
- `docs/playtests/adversarial_baseline/p1_mid_selector/` **(new)** — the stale
  CSVs plus the attribution write-up.
- Baseline re-captured from the shipped tree; guards now **21/21 green**.
- `kP1GeometryMovers` recomputed against `genv1_pre_p1/`: **42 → 61** boards.
  Seven previously-named ids are gone — the intermediate selector moved them and
  the final one moved them back, which is what a computed list looks like.
- `test/game/levels/generation/adversarial_corpus_diff_test.dart` **(new,
  `report`-tagged, asserts nothing)** — the §e before/after diff, so the P1
  result is re-derivable instead of hand-computed.

**Result — unchanged conclusion, correct evidence.** Severity p50 6 → 11,
≤6-tap 61 % → 0 %, `captureRate` 0.58 → 1.00; representative 5 → 11, 67 % → 0 %;
Hard p50 10 → 10. Q1 p50 4 → 9 at 100 % → 0 % ≤6-tap. §e: 0 VIOLATION, 266
FIXED, 34 INCIDENTAL (22 coreless), 0 UNFIXABLE, 0 SELECTOR-FAILED. Node counts
moved on 30 boards, median 0, mean +0.03, Hard unchanged at 25 on all 100.

**Process finding, and it is the durable one.** Every P1 gate — the T0.3 canary,
the guards, the fresh draw, campaign coverage, determinism probe 5 — is tagged
`slow` and is therefore invisible to `flutter test --exclude-tags "report ||
slow"`. Standing gate 2 means the full sweep at a phase boundary.

**Still open, deliberately.** `relay_softlock_property_test` fails on both
cases and has since before P1 (`4d7d561`, seed 28; HEAD, seed 19). The file's own
header documents it as unrunnable as written — an exhaustive ~5^n search. The
two-relay case asserts a real solvability escape (`softlocked despite passing
_relayIsSoftlockSafe`), so it needs a bounded rewrite and a verdict before the
Gen V1 freeze. Not P1's or P2's, but not nothing.
