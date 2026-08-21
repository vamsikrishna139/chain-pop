# Unbound V2 — Implementation Plan (FINAL)

**Date:** 2026-08-19 · **Branch:** `new_improvements` · **Status:** finalised, approved for
implementation · **Supersedes:** the 2026-08-19 draft of this file

Companion to `docs/MASTER_PLAN_V2.md` (the *what* and *why*). This document is the *how*:
exact files, functions, signatures, tests, gates and rollback per task.

**Revision note.** This version incorporates a ground-truth code verification pass against
`lib/game/levels/generation/*`. Seven corrections were folded in; five of them change what gets
built, not merely how it is described. They are listed in §10 so a reader of the draft can see
exactly what moved and why. Two claims in the draft were **wrong about the code** and are
corrected here (§0.3, §1 T0.2). Do not implement from the draft.

---

## Decisions taken — 2026-08-19

Both open questions are closed.

### Decision 1 — Determinism: **YES, keyed by an explicit input closure**

Review split three ways: two positions argued "remove the requirement — the engine never
promised it"; one argued "make it a formal contract keyed by generation version". **The third is
adopted.**

**The evidence — and its limit.** Two tests bracket the question:

| Test | Construction | Level | Result |
|---|---|---|---|
| `level_seed_test.dart:59` | **two fresh** `LevelGenerator()`s | **75 — a *seeded* milestone** (`seed_registry.dart:40` → `ringMilestoneSeed`) | passes, node-for-node |
| `level_generator_test.dart:195` | **one shared** generator, called twice | 42 — procedural | passes for id 42 only |

> **Correction to the draft.** The draft cited the first row as proof that the engine "is already
> fully deterministic given its complete input". It is not proof. Level 75 is a **seeded** level:
> the seed pins silhouette, archetype and tier and may supply `seedRng`, so that test exercises
> the seeded path only. **No existing test demonstrates fresh-generator byte-determinism on the
> ordinary procedural path.**

The diagnosis is still very likely correct — `LevelGenerator` carries `_diversityLedger` and
`_silhouetteSessionTracker` (`level_generator.dart:127-139`), mutable state that every emission
records into and every candidate gate reads from, and `LevelManager` holds the generator as
`static final` (`level_manager.dart:12`), one instance per process, never reset. But *likely
correct* is not *established*, and the plan must not rest a freeze on an untested premise.

**Therefore determinism is a hypothesis that T0.0 tests, not a premise the plan assumes.**
T0.0 is now an audit with a pass/fail outcome, and §8's gate table reflects that.

**The contract, adopted:**

```
Board = f(levelId, mode, generationVersion, recipeId, explicitly-declared generation inputs)
```

Anything else that can change the output is either a bug to remove or state to promote into the
contract. That is the whole content of the T0.0 audit.

- `recipeId` defaults to `neutral`. Under `neutral`, a given
  `(levelId, mode, generationVersion)` is **byte-identical forever**.
- Session adaptivity (P4+) selects a *recipe*; it never silently mutates the meaning of a
  published level id.
- Every input is explicit and logged.

**Resolving the dissent.** One reviewer re-affirmed "remove the requirement — even if the engine
*could* be deterministic with controlled inputs, it isn't in production, so free the
architecture." That is half right and the half it gets right is already in the contract:
**production does not get determinism, the neutral construction does.** Live play runs a warm
ledger and always did. But "remove the requirement" leads to a harmful action item — rewriting
`level_generator_test.dart:195` to assert mere validity — and byte-identity under
`LevelGenerator.neutral()` is the **only instrument** that can prove P1 moved no geometry, that
P2 moved only what it intended, and that P3's composer is genuinely neutral. Deleting the
instrument to avoid measuring is not freeing the architecture. The requirement stays, scoped to
the neutral construction.

**Add `generationVersion` now, at 1.** It costs one field and buys safe content regeneration,
analytics continuity, bug reproduction and rollback.

**Consequence that tightens the plan:** post-P4 a level id maps to a board *family*, not a board.
Reproducing a player's board then requires the logged `recipeId`. **P4 therefore cannot ship
before telemetry** — it joins P6 behind the telemetry gate.

### Decision 2 — Regeneration window: **land T0 → P0 → P1 → P2 before the closed test**

Unanimous. P1 fixes bugs (Medium collapsing, Easy inert); P2 unlocks variety already paid for.
Shipping the broken version spends a 12-tester/14-day feedback window confirming defects we have
already measured, and contaminates the signal: after a mid-test regeneration you cannot tell
whether a complaint was fixed, replaced, or merely re-rolled.

Seed changes are free exactly once — before any tester has progress, notes or screenshots.

**Sharpened:** the gate is not "code merged". It is **T0 + P0 + P1 + P2 complete, validated, and
the corpus frozen**. A merged-but-unvalidated P2 is worse than no P2, because it moves seeds
without proving what it moved.

**Discipline: do not squeeze P3+ into this window** merely because seeds are already moving.

**Content-baseline freeze:** after P2 re-baselining, freeze the corpus as **Generation Version 1**.
Post-test generator changes create a new `generationVersion` rather than silently rewriting the
experience.

```
NOW → T0 input-closure audit + determinism contract + genVersion
    → P0 instruments → P1 core+Easy → P2 variety
    → regenerate/re-baseline corpus → FREEZE Gen V1 → CLOSED TEST
    → telemetry → P3 → P4 → P5 → P6
```

---

## 0. Five code facts that reshape the plan

Established by reading the call sites, not inferred. Each changes a phase's risk or design.

### 0.1 Core placement consumes no randomness — but it *does* move some boards

> **CORRECTED 2026-08-19, after P1 shipped. The original text of this section was wrong, and
> T0.4's guards are what proved it. It is kept below, struck through in prose, because the
> mistake is instructive: a true premise carried an unexamined step to a false conclusion.**

The premise stands. `_markCoreNodes` → `_climaxBandCoreIds` (`level_enrichment.dart`) is a **pure
function** of the solved board. No `Random` is threaded in, and the code confirms the docstring.

~~**Consequence:** changing core selection leaves board geometry, node positions, directions and
the RNG stream completely unchanged. Only `isCore` flags move.~~ **This does not follow.**

`enrichLevel` runs **inside the generator's accept/reject loop**, and the generator re-validates
the *enriched* board before accepting a candidate:

```
level_generator.dart   final enriched = _enrichLevel(result.value, scaledConfig, targetTier);
                       final validationResult = _validator.validate(enriched);
                       if (!validationResult.isValid) { _discardPendingEmission(); continue; }
```

Cores steer the mechanics placed around them — `_markSpecialNodes` excludes cores from lock
candidates and keeps relays out of **core rows**, because a relay can rotate a core into a
permanent face-off. So a different core set means a different lock and relay placement, which
means a candidate that used to be accepted can now be rejected, and the *next* attempt builds
different geometry.

**Measured:** P1 moved **42 of the 300** frozen corpus boards this way — 34 Medium, 8 Hard. The
named list is `kP1GeometryMovers` in `adversarial_corpus.dart`.

**What survives of the original consequence, and it is the part that mattered:** core selection
still draws no randomness and still never reaches board *planning*, so the movement is not
directional. Node-count deltas run both ways with **median 0, mean +0.2**, every Hard board kept
its node count exactly, and `captureRate` — a per-board ratio immune to board size — went
0.58 → 1.00. The impostor T0.4§c was built to catch (node inflation faking the metric) is
excluded by the data rather than by the premise.

**Consequence for anyone reading this plan later:** a change confined to enrichment is *not*
automatically geometry-neutral. Prove it against the corpus; do not assume it.

### 0.2 No quality gate can see cores — this is F1's architectural root cause

```
level_generator.dart:772   metrics = LevelMetrics.compute(level)      ← pre-enrichment
level_generator.dart:778   visual  = evaluateVisualComposition(level) ← pre-enrichment
level_generator.dart:409   enriched = _enrichLevel(...)               ← cores applied HERE
level_generator.dart:529   enriched = _enrichLevel(...)               ← and HERE
```

Cores are applied **after** the board is scored and selected. No evaluator, FSR rule, visual
check or diversity gate has ever seen a core. A board cannot currently be rejected for bad core
placement because at judgement time it has none.

**Consequence:** the fix is *not* "add a core rule to the evaluator" — that would require
enriching every candidate, multiplying solver cost across the whole K-loop. Because core
selection is pure and cheap, the correct fix is a **post-enrichment repick loop**: if core
quality is poor, re-pick cores on the same board. It never regenerates, so contract C1
(zero-fallback) holds by construction.

```
                      CHEAP (adopted)                    EXPENSIVE (rejected)
   generate board                              every candidate
        → enrich                                    → fully enrich
        → select cores                              → solve
        → compute core metrics                      → core metrics
        → repick cores (bounded)                    → reject and regenerate
```

### 0.3 There are TWO legacy core fallbacks, and both bypass any naive floor

> **Correction to the draft.** The draft named one escape hatch. There are two.

```
_climaxBandCoreIds  (level_enrichment.dart:168-176)
    pass 1: one core per third of the strict band  [0.35, 0.65]
    pass 2: top up from the full strict band
    pass 3: top up from the RELAXED band           [0.25, 0.78]   ← already exists
    still short? →  picks.clear();  sort by DESCENDING id;  take(count)   ← HATCH #1

_markCoreNodes      (level_enrichment.dart:81-83)
    coreIds.length < budget.coreCount  →  _legacyCoreIds(...)  (descending id)  ← HATCH #2
```

Both hatches produce **highest-id = last-popped** cores, which is *precisely* the F1 pathology
they are supposed to prevent, and they fire on exactly the adversarial boards that most need the
floor. A quality check placed beside either one still leaks through the other.

Note also that **the relaxation pass reviewers proposed adding already exists** (pass 3, constants
`_kCoreBandLoRelaxed = 0.25` / `_kCoreBandHiRelaxed = 0.78` at `:41-42`). T1.2 must not re-add it;
it must sit *downstream of everything*, including both hatches. See T1.2.

### 0.4 The candidate portfolio already exists

`level_generator.dart:695-900` already collects `inBandCandidates`, ranks via
`_selectBestInBandCandidate`, and keeps layered fallbacks (`novelOutOfBand`, `nonNovelFallback`).
P3 is an **evolution of an existing loop**, not a new architecture. The work is converting hard
`continue` rejections into scores, and adding tiering.

### 0.5 The `report_*` tests cannot gate anything — they assert nothing

> **Correction to the draft.** The draft's P1 DoD delegated the Easy gate to a
> `report_easy_100_test.dart`. That file does not exist — but creating it would not have worked
> either.

```
$ grep -c "expect(" report_medium_100_test.dart report_hard_100_test.dart report_all_modes_100_test.dart
report_medium_100_test.dart:0
report_hard_100_test.dart:0
report_all_modes_100_test.dart:0
```

All three campaign report tests are **print + CSV diagnostics by construction** ("Diagnostic only
— asserts nothing", `report_all_modes_100_test.dart:5`). They produce the evidence; they cannot
enforce a gate.

Two further facts settle the design:

- `report_all_modes_100_test.dart` **already runs Easy, Medium and Hard** over the same
  `kReportSampleIds`, so the Easy *data* was never missing — only the assertion.
- `board_report_utils.dart` already exposes `runCampaignBatch(...)` and `BoardRow`, directly
  reusable from an assertion test.

**Consequence — this overrides both reviewer proposals.** Neither "create
`report_easy_100_test.dart`" (Option A) nor "widen `report_all_modes_100` with assertions"
(Option B) is correct, because both put gates in files whose stated contract is to be
non-blocking diagnostics. The design is:

| Layer | Files | Role |
|---|---|---|
| Evidence | `report_*_100_test.dart` | print + CSV, **never assert**, all three modes, reviewable diffs |
| Gates | `core_triviality_test.dart` (new) | **all** P1 tap-depth assertions, **all three modes**, one file |

No new report file is created. See T0.2 and T0.3.

---

## 1. Phase T0 — Input closure and the determinism contract

**Goal:** know exactly what can change a board, then declare it. Zero production behaviour change.
This is now its own phase, ahead of P0, because P0's instruments and P1/P2's byte-identity proofs
are worthless if an undeclared input can move a board underneath them.

### T0.0a — Generator Input Closure Audit · *do this first, it is an audit not an edit*

Enumerate **every value capable of changing generated output**, then classify each. Deliverable is
a table committed to `docs/playtests/generator_input_closure.md`, not code.

Known candidates to classify (the audit must prove this list complete, not assume it):

| Candidate | Where | Expected class |
|---|---|---|
| `levelId`, `mode` | call args | Explicit input |
| `generationVersion`, `recipeId` | new, T0.0c | Explicit input |
| primary seed / `Random` derivation | `director.dart`, `level_seed.dart` | Explicit input |
| `_diversityLedger` | `level_generator.dart:127-139` | **Session state → promote** |
| `_silhouetteSessionTracker` | `level_generator.dart:127-139` | **Session state → promote** |
| `_pendingEmission` | `level_generator.dart:~120` | **Suspect — carries across calls** |
| `_lastWinningBlockingRetryIndex` | `level_generator.dart` | **Suspect — carries across calls** |
| `_retrogradeAttemptCount` | `level_generator.dart` | Ephemeral (telemetry only — verify) |
| `_sightlineCache` | `level_generator.dart:~124` | Ephemeral, pure geometry — harmless |
| `LevelManager._generator` | `level_manager.dart:12` | **Static/global → make re-creatable** |
| `enableDiversityGating` | constructor flag | Explicit input |
| seeded-level registry | `seed_registry.dart` | Explicit input (function of `levelId`) |

Classes: `Explicit input` · `Persistent state` · `Session state` · `Ephemeral state` ·
**`Forbidden hidden state`**.

**Anything landing in the last class must be removed or promoted into the contract before T0.0c
is written.** That is the audit's only acceptance criterion.

### T0.0b — The determinism probe · *this is a hypothesis test, and it may fail*

Per Decision 1, procedural determinism is unproven. Probe it directly, over a set of purely
procedural ids across all three modes (include ids the audit flagged as unstable, and 42 for
continuity with the existing test):

| # | Sequence | Expectation |
|---|---|---|
| 1 | one generator: `generate(42)`, `generate(42)` | **differs** — ledger is a declared input |
| 2 | two fresh generators: `generate(42)` each | **byte-identical** — the contract |
| 3 | one generator: `42`, `43`, `42` | differs (documents ledger dependence on history) |
| 4 | one generator: `42` Hard, `42` Medium, `42` Hard | differs; **mode must not leak into the 3rd** beyond ledger effects |
| 5 | two fresh generators, full sweep of 100 `kReportSampleIds` × 3 modes | **byte-identical** |

Probe 5 is the real one — a single id proves nothing about the population.

**If probe 2 or 5 fails**, the ledger is not the only hidden input. Investigate
`_pendingEmission` and `_lastWinningBlockingRetryIndex` first (both carry across calls;
`_sightlineCache` is pure geometry and cannot be the cause). **Do not proceed to P1 with a
failing probe 5** — every downstream byte-identity gate depends on it.

**Deliverable:** `test/game/levels/generation/determinism_contract_test.dart`, plus the probe
results appended to the closure audit doc.

### T0.0c — Declare the contract in code

**a. Introduce `generationVersion`.**

```dart
// lib/game/levels/generation/generation_version.dart
const int kGenerationVersion = 1;
```

Fold it into seed derivation so a future bump deliberately re-rolls content, and stamp it on
every analytics event and every corpus CSV row.

**b. Content identity, logged.** Every generated level records:

```dart
contentIdentity = '$levelId/$mode/v$generationVersion/$recipeId'
```

`recipeId` is `neutral` until P4. There is already a seam for emitting this —
`lib/game/levels/analytics/generation_analytics.dart` defines `GenerationAnalyticsSink` with a
noop default, so this is wiring, not new architecture. When a player reports "level 347 gave me
an impossible core", the recipe is recoverable.

**c. Make session state explicit.**

- Add `LevelGenerator.neutral()` — a named construction guaranteeing empty ledger and tracker,
  for tests and reproduction.
- Make `LevelManager._generator` (`level_manager.dart:12`) re-creatable rather than
  `static final`, so a session boundary can install fresh state. **Enumerate callers first** —
  it is used by tests and `dense_strategy_snapshot`. This is the same edit P4 needs; doing it now
  means P4 inherits it.

**d. Fix the determinism test correctly — do not weaken it.**

`level_generator_test.dart:195` and `:224` must construct a **fresh generator per call** and keep
asserting full node-for-node byte-identity:

```dart
final a = LevelGenerator.neutral().generate(42);
final b = LevelGenerator.neutral().generate(42);
// byte-identical — this is the contract, and the regression instrument
```

Then add a **second, new** test asserting the honest current behaviour: a *shared* generator
legitimately produces different boards across calls, because the ledger is a declared input.
Both facts are documented instead of one being accidental.

> **Explicitly rejected:** rewriting these tests to assert only validity/solvability. That
> discards the byte-identity instrument that P1, P2 and P3 depend on.

### T0 definition of done

- [ ] Closure audit committed; **zero** entries classified `Forbidden hidden state`.
- [ ] Determinism probes 1–5 run; probe 5 green across 300 boards, or the cause found, fixed and
      re-run green.
- [ ] `generationVersion` and `contentIdentity` stamped on analytics + CSV.
- [ ] `LevelGenerator.neutral()` exists; `LevelManager._generator` re-creatable, all callers
      enumerated and updated.
- [ ] **No board changed anywhere** — `generationVersion` participates in seed derivation but is
      constant at 1, so the corpus must be byte-identical. Verify by CSV diff.

---

## 2. Phase P0 — Instruments

**Goal:** make F1 and F4 measurable and regression-proof. Zero production behaviour change.

### T0.1 — Define and implement `TapsToWin` / `CoreTapDepth`

The metric F1 needs does not exist. Wave depth is parallel; taps are sequential.

**Definition.** The win fires when all cores are extracted (`chain_pop_game.dart:751`).
Therefore:

```
CoreTapDepth = |closure(cores)|
  where closure(C) = C ∪ ⋃_{c ∈ C} prerequisiteClosure(c)
```

i.e. the number of extractions that *must* happen before the last core can be taken. Reuse the
prerequisite machinery already in `computeCriticalUnlockDepth` (`metrics.dart:328`) and
`dependency_graph.dart`.

**New file:** `lib/game/levels/generation/core_metrics.dart`

```dart
/// Tap-depth core quality. Pure; no RNG. Computed on the ENRICHED board.
class CoreMetrics {
  final int coreTapDepth;        // taps that must precede the last core
  final int totalNodes;
  final double coreTapFraction;  // coreTapDepth / totalNodes  ← the band unit
  final double coreIsolation;    // share of board irrelevant to reaching cores
  final int maxSingleTapCascade; // largest one-tap unlock cascade
  final int coreCriticalDepth;   // longest prerequisite chain to any core

  static CoreMetrics compute(LevelData enriched);
}
```

`coreTapFraction` is the quantity the `[0.35, 0.65]` band should have been using all along.

**Complexity:** O(n²) worst case on n ≤ 42 nodes — negligible beside retrograde construction.

**Checks:** unit tests over hand-built fixtures — a shallow wide board (the F1 pathology) must
report a low `coreTapFraction` while its `CoreWaveRatio` reads ~0.5. That divergence *is* the
bug, and the test documents it.

### T0.2 — Wire metrics into the corpus reports · *evidence layer only, still no assertions*

**Files:** `test/game/levels/generation/board_report_utils.dart`,
`corpus_benchmark_utils.dart`, and `report_hard_100`, `report_medium_100`,
`report_all_modes_100`.

Add columns to `BoardRow` and `writeCsv`: `coreTapDepth`, `coreTapFraction`, `coreIsolation`,
`maxSingleTapCascade`, `topologyClass`. `topologyClass` = `(components, enclosedHoles,
bboxFillBucket)` — the triple the audit probes used to get 14/18/30.

**Version the corpus artifacts.** Every CSV gets a header comment so benchmarks stay comparable
across phases:

```
# corpusVersion: 1
# generationVersion: 1
# strategyVersion: 0
# seedContractVersion: 1
```

`strategyVersion` stays 0 until P3. Without this, a P3-era CSV silently compares against a
Gen-V1 CSV and the diff is meaningless.

**These files keep asserting nothing** (§0.5). They are the evidence layer. `report_all_modes_100`
already covers Easy, so no new report file is created.

**Balance:** test-tree only. `lib/` gains only `core_metrics.dart`, which nothing calls yet.

### T0.3 — The red canary · *this is where every P1 gate lives*

**New test:** `test/game/levels/generation/core_triviality_test.dart`

This is an assertion test, not a report. It uses `runCampaignBatch(...)` from
`board_report_utils.dart` and covers **all three modes in one file** — the P1 DoD is enforced
here and nowhere else.

```dart
// EXPECTED RED until P1 lands. Documents F1. See docs/IMPLEMENTATION_PLAN_V2.md §T0.3.
group('core triviality', () {
  test('Medium boards are not trivially short', () {
    expect(share(taps <= 6), lessThan(0.05));          // measured today: 0.66
    expect(minTaps,          greaterThanOrEqualTo(6)); // measured today: 2
  });

  test('Easy teaches without collapsing', () {
    expect(share(taps <= 6), equals(0.0));   // must never regress from 0%
    expect(p50Taps,          greaterThanOrEqualTo(9));
  });

  test('Hard stays where it already is', () {
    expect(p50Taps, closeTo(10, 1));         // guards against over-correction
    expect(minTaps, greaterThanOrEqualTo(6));
  });
});
```

> **Baseline calibration — 2026-08-19.** The draft's F1 figures do not reproduce: measured over
> `kReportSampleIds`, Medium's ≤6-tap share is **66%** (not 44%) and Hard's p50 is **10** (not 11).
> The Hard guard is therefore centred on 10 — centring on 11 would permit an upward drift to 12
> while flagging a benign 9. F1 is worse than stated, not better. Full measurement and the
> definition of `taps` in `docs/playtests/core_triviality_calibration.md`.

The Hard case is a **regression guard, green from day one** — Hard shares the code path, so it is
a real risk, not a formality. Only the Medium and Easy cases are expected red.

**Gate:** commit this red, with a comment naming F1 and this document. A knowingly-red canary is
the checkpoint; it must go green in P1 and never regress.

### T0.4 — The frozen adversarial corpus · *the last T0 artifact, and the gate into P1*

**Added 2026-08-19.** T0.3 measured F1 at **66% ≤6-tap, p50 6** — materially worse than the 44%
this plan assumed. A defect that large needs its *shape* measured before the core algorithm is
touched, because the random corpus cannot distinguish the fix from three impostors:

| What actually happened after P1 | Defect fixed? | Random corpus sees the difference? |
|---|---|---|
| The trivial boards got genuinely deeper cores | ✅ | no |
| Node counts grew, so `coreTapDepth` rose while cores stayed last-popped | ❌ F1 intact, hidden | no |
| The whole distribution shifted up — Medium is now bloated | ⚠️ overshoot | no |

All three produce the same headline number. Only a **per-stratum before/after diff on identical
level ids** separates them. That is what T0.4 builds. It is pure measurement — nothing in `lib/`
changes behaviour.

> **Why this design is sound, and why it needed T0.0 first.** Selecting the worst N cases by a
> *noisy* measure makes them improve on re-measurement even under a no-op change — regression to
> the mean, which fakes a win and invalidates every severity-stratified before/after study. It
> does not apply here: `tapsToWin` is deterministic per `(levelId, mode, generationVersion)` under
> the T0.0 contract, so there is no noise to regress. **The corpus is only trustworthy because
> T0.0b passed.**

**Do not confuse this with T1.2's adversarial fixtures.** Same adjective, different instruments,
both required:

| | T0.4 adversarial **corpus** | T1.2 adversarial **fixtures** |
|---|---|---|
| What | 300 real generated boards | ~4 hand-built `LevelData` |
| Answers | "did the population improve, and *where*?" | "can the floor be bypassed?" |
| Method | statistical, frozen before/after | forces each of the four selection paths |
| Fails when | the bottom quintile is unmoved | any path ships a board under the floor |

The fixtures stay in T1.2 and **must not be pulled forward** into T0.4: they assert against
`_ensureCoreQuality`, which T1.2 creates. Written earlier they would have nothing to assert.

#### a. Population — 300 frozen boards

| View | n | Purpose | Selection |
|---|---|---|---|
| Medium severity | 100 | did we fix the *disease* | empirical quintiles of `tapsToWin` over a ~600-board pool, **20 per quintile** |
| Medium representative | 100 | did we *bloat the patient* | uniform over L1–1500, unfiltered |
| Hard control | 100 | over-correction control, never an optimisation target | uniform |

**No sector filter and no core-count filter.** The earlier sketch in
`docs/playtests/T0_EXIT_GATE.md` restricted Medium to "boards with cores, sectors 3+". That filter
is a **bug**: T0.3 found the shallowest boards are overwhelmingly *sector 2, single-core* — L1209,
L193, L212, L249, L1127, L1133 all win in **2 taps**. Sector 2 keeps `coreCount: 1` after T1.3, so
those boards are fixed by T1.1/T1.2 or not at all. A corpus that excludes them cannot see the fix.
The eligible population is **every board that can ship to a player**.

**Equal 20-per-quintile allocation, not a weighted tail.** Over-weighting Q1 is superfluous *and*
harmful here: with 66% of Medium at ≤6 taps, the empirical quintiles put **Q1, Q2 and Q3 entirely
inside the ≤6-tap region** — 60 of the 100 severity boards are already pathological under equal
allocation. Shrinking Q4/Q5 to make room would leave n=10 in exactly the strata that detect
over-correction, which is the *other* thing P1 can break.

**`tapsToWin` is the sole selection key.** Every other metric — `coreTapFraction`,
`coreCriticalDepth`, `coreIsolation`, `maxSingleTapCascade`, `coreCount`, `nodes`, `sector`,
`waveDepth`, `topologyClass` — is recorded as a **covariate**, never a selection key. Five keys
cannot be quintiled simultaneously.

**Within each quintile, sample for cause diversity** across `(sector band × coreCount)`, so Q1 is
not twenty near-identical sector-2 single-core boards testing one failure mode twenty times.

**The representative view is a plain uniform draw** over L1–1500. Sector is a pure function of
`levelId` via `worldForLevel`, so a uniform draw reproduces campaign sector prevalence *by
construction*; explicit sector stratification can only distort it. Record the realised sector
counts in the README so under-representation stays visible.

**Pool seed disjoint from `kReportSampleSeed`**, so the T0.3 canary's 100 ids remain a genuine
held-out set. All generation at `timeBudget: null`.

#### b. Freeze — the detail that makes or breaks the experiment

Frozen on `(levelId, mode, generationVersion)`, **not `levelId` alone** — a future
`generationVersion: 2` must not silently redefine which board the corpus means.

Ids ship as **checked-in literals**. They are never re-derived by re-running the selection.
Severity membership is a function of *current* `tapsToWin`; re-selecting after P1 would pick
different boards and destroy the comparison while appearing to work. Stated as a rule:

```
The corpus is a scientific instrument. Selection happens exactly once.
```

#### c. Three machine-checked guards

1. **Geometry identity** — node positions, directions, mask. `isCore` is **explicitly exempt**;
   the contract being asserted is *"P1 changed core selection, not puzzle geometry"* (§0.1).
2. **Solution-structure identity** — `hash(LevelSolver.nodeWaveIndices)`, which is canonical,
   deterministic and core-independent.
3. **Node-count equality** — exact, not a tolerance. See below.

> **Verified 2026-08-19: node inflation is an exact invariant, not a guardrail.**
> `budget.coreCount` is consumed *only* in `level_enrichment.dart:68-82`, post-generation, and
> `directiveFor` is read only by star grading and UI — never by the generator. Therefore across
> **all** of P1 (T1.1 band, T1.2 floor, T1.3 count 2→3, T1.4 Easy core) node count and geometry
> must be **bit-identical**. A "≤10% median node-count increase" guardrail would be far too loose:
> the assertion is **equality**, and any delta means P1 leaked into geometry. This kills the
> likeliest false positive outright.
>
> *One intended side effect, pre-recorded so it is not mistaken for a regression:* T1.4 moves Easy
> sector 3+ from `coreCount: 0` to `1`, which stops `directiveFor` falling back from `cascade` to
> `swift` (`level_directive.dart:57`). Star goals change on those levels. That is correct.

#### d. Achievable-depth ceiling — per-board, computed at baseline

Boards differ in what they can physically support: a wide shallow board has no deep node, so *no*
core selection can produce a deep core. Measuring such a board against an absolute floor says
nothing about whether the selector did well. So for every frozen board, compute the best
`coreTapDepth` reachable on that exact geometry:

```
per node: prerequisite closure as a bitmask        (O(n²), once per board)
ceiling  = max over valid k-subsets of popcount(union of their masks)
```

Subsets are constrained by the same `spreadOk` ≥ 2 Manhattan rule the real selector obeys, so the
ceiling is *feasible*, not fantasy. Bitmask unions over C(42,3) ≈ 11.5k subsets are microseconds
per board — n ≤ 42 fits one 64-bit int.

Two quantities follow, and both are decision-relevant **now**:

- **`captureRate` = actual `coreTapDepth` / ceiling.** A score for the *selector* rather than the
  population. "Q1 went from capturing 18% of available depth to 91%" and "p50 rose 6 → 10" can
  diverge, and when they do, the first one is the truth.
- **The count of boards whose ceiling is itself below the mode floor.** These are geometrically
  unfixable: T1.2's bounded repick will burn all three attempts and ship the best it saw,
  silently. **If that set is large, T1.2 as specified cannot deliver its stated invariant** and the
  remedy has to move upstream into candidate rejection. This number must be known *before* T1.2 is
  written, not discovered afterwards.

#### e. Post-P1 classification — mutually exclusive, machine-computed

Evaluated per board as a decision tree over the deltas:

```
geometry or node count moved?   → VIOLATION            (guard failed; result invalid)
tapsToWin ≥ floor?
  ├─ yes, cores moved           → FIXED
  ├─ yes, cores unchanged       → INCIDENTAL            (got lucky — investigate)
  └─ no
      ├─ ceiling < floor        → UNFIXABLE             (geometric; needs an escape valve)
      ├─ captureRate ≥ 0.90     → SELECTOR-OPTIMAL, BOARD-LIMITED
      └─ captureRate < 0.90     → SELECTOR-FAILED       (the real bug)
```

`Q1: 34 FIXED / 4 UNFIXABLE / 2 SELECTOR-FAILED` is a work order. `p50 6 → 10` is a rumour.

#### f. Hard gates vs reported signals · *this supersedes the P1 DoD's p50 clause*

The P1 acceptance split, settled here so P1 cannot be gamed and cannot be over-constrained:

| Class | Quantity |
|---|---|
| **Hard gate** | Medium ≤6-tap share < 5% · Medium min `tapsToWin` ≥ 6 · Easy ≤6-tap = 0% · Hard p50 within ±1 of 10 |
| **Hard invariant** | geometry identity · solution identity · node-count equality · 600/600 device autoplay |
| **Reported, not gated** | Medium p25/p50/p75/p95 · `captureRate` per quintile · `coreCriticalDepth` · `coreIsolation` · `maxSingleTapCascade` · gen latency |

**Medium p50 12–14 is demoted from acceptance gate to design aspiration.** Doubling p50 from a
measured 6 to 12–14 is a large prescribed move, and the cheapest way for an implementer to reach
it is node-count inflation — precisely the impostor in the table above. The product goal is
*"eliminate trivial core victories while preserving a good Medium"*, not *"make p50 equal 13"*. If
P1 lands at p50 9–10 with ≤6-tap at 3% and playtests feel good, that is a success and will not be
broken to chase 12. Promote 12–14 to a gate only on evidence — after the corpus diff and the first
human playtest.

#### g. Anti-overfit discipline

The corpus **evaluates**; it never tunes. Tuning the generator until specific frozen ids pass
converts the instrument into an optimiser and voids the result. The held-out sequence:

```
freeze corpus → T1.1–T1.4 → evaluate frozen corpus
              → canary's kReportSampleIds (never seen by selection)
              → one fresh draw → final validation
```

#### h. Deliverables

| Path | Contents |
|---|---|
| `test/.../adversarial_corpus.dart` | frozen id literals + view/quintile/severityRank assignment |
| `test/.../adversarial_corpus_baseline_test.dart` | generates + measures + writes CSVs; **asserts nothing** (`report`-tagged) |
| `test/.../adversarial_corpus_guards_test.dart` | the three guards of §c (**asserts**) |
| `test/.../adversarial_corpus_report.dart` | per-quintile statistics, `captureRate`, §e classification |
| `docs/playtests/adversarial_baseline/{medium_severity,medium_representative,hard_control}_baseline.csv` | frozen baseline, versioned headers |
| `docs/playtests/adversarial_baseline/README.md` | selection procedure · quintile boundaries at freeze time · realised sector counts · the evaluation-only rule |

CSV columns are `BoardRow`'s, plus `view`, `quintile`, `severityRank`, `ceilingTapDepth`,
`captureRate`, `geometryHash`, `solutionHash`, `contentIdentity`.

**Cost:** ~1,200 generations plus negligible ceiling computation — about 5 minutes.

**Optional, and the only item touching `lib/`:** instrument `_markCoreNodes` to report which of
the four paths produced the cores (band / relaxed / hatch #1 / hatch #2). Pure telemetry, no
behaviour change, no RNG draw. T1.3's balance note already asks for this ("log the relaxation rate
before tuning further"), and without it T1.2's choke point is designed blind to how often the
hatches actually fire.

### T0.4 definition of done

- [ ] 200 Medium (100 severity + 100 representative) and 100 Hard frozen as **literals**, keyed on
      `(levelId, mode, generationVersion)`.
- [ ] Sector 2 and single-core boards present in the severity view; no filters applied.
- [ ] All five quintiles populated at n=20; quintile boundaries recorded.
- [ ] Severity, representative, Hard-control and `kReportSampleIds` mutually **disjoint**.
- [ ] Three baseline CSVs committed with version headers; `ceilingTapDepth` and `captureRate`
      populated; `geometryHash` and `solutionHash` recorded.
- [ ] All three guards green at baseline.
- [ ] Count of `ceiling < floor` boards reported — **input to T1.2's design**.
- [ ] README states the evaluation-only rule verbatim.
- [ ] T0.3 canary still red on Medium, green on Hard.
- [ ] Zero production behaviour change (the optional telemetry excepted, and it is inert).

### P0 definition of done

- [ ] `flutter analyze` clean; full suite green **except** the new canary's Medium/Easy cases and
      the known pre-existing `corpus_benchmark` milestone-seed failure.
- [ ] Canary's Hard case **green** from the start.
- [ ] CSVs regenerated with new columns and version headers; committed to `docs/playtests/`.
- [ ] **No diff** in any existing board: re-run `report_hard_100` and diff the CSV's pre-existing
      columns byte-for-byte against baseline. Any change means P0 leaked into production
      behaviour — stop and revert.
- [ ] **T0.4 DoD fully met.** The frozen corpus is the gate into P1: without a baseline captured
      *before* core selection changes, P1's result is unmeasurable and cannot be accepted.

---

## 3. Phase P1 — The two correctness bugs

**Goal:** Medium stops collapsing; Easy stops being mechanically inert. No seed movement (§0.1).

**Order is load-bearing: T1.1 → T1.2 → T1.3 → T1.4.** T1.4 must not land before T1.2, because
Easy's *only* quality gate is T1.2's floor (§0.5, T1.4).

**Entry gate: T0.4's frozen corpus must be committed first.** P1 is the first production-behaviour
change in this plan, and the corpus is the only instrument that can tell a real fix from the three
impostors in §T0.4. Do not begin T1.1 without a captured baseline. T0.4§d's count of
`ceiling < floor` boards is a **design input to T1.2**, not a post-hoc report.

**Acceptance is defined in T0.4§f**, which supersedes the p50 clause in this phase's DoD below:
hard-gate `≤6-tap < 5%` and `min ≥ 6`; treat Medium p50 12–14 as a design aspiration, not a gate.

### T1.1 — Retarget the core band to tap depth

**File:** `lib/game/levels/generation/level_enrichment.dart`

Keep the band constants; change the unit and the selection input.

```dart
// The band is unchanged. What changes is what it measures.
const double _kCoreBandLo = 0.35;   // now of TAP depth, not wave depth
const double _kCoreBandHi = 0.65;
```

Rework `_climaxBandCoreIds` to rank candidates by **prerequisite-closure size** rather than
`waves[n.id] / maxWave`. Everything else — the guarded check (`LevelSolver.canRemove`), the
centrality tie-break, the `spreadOk` ≥ 2 Manhattan rule, the three-slice arc, and **both existing
relaxation passes** — is sound and stays. Only the percentile source changes.

Retain `CoreWaveRatio` as a logged secondary signal — do not gate on it.

### T1.2 — Core-quality floor, downstream of *both* legacy hatches

This is the §0.2 fix, hardened by §0.3. **The floor must be structurally impossible to bypass.**

The draft placed `_ensureCoreQuality` beside the fallback. That leaks: §0.3 documents two
descending-id hatches, one inside `_climaxBandCoreIds` and one in `_markCoreNodes`, and a check
beside either still lets the other through.

**Design: one choke point.** Every core-id set — band pick, relaxed pick, hatch #1, hatch #2 —
converges on a single verifier before it can be written onto nodes.

```dart
List<NodeData> _markCoreNodes(...) {
  ...
  var coreIds = maxWave <= 0
      ? _legacyCoreIds(nodes, budget.coreCount)
      : _climaxBandCoreIds(...);          // may itself have used hatch #1
  if (coreIds.length < budget.coreCount) {
    coreIds = _legacyCoreIds(nodes, budget.coreCount);   // hatch #2
  }

  // THE CHOKE POINT — nothing reaches the board without passing here.
  coreIds = _ensureCoreQuality(coreIds, nodes, level, mode, budget);

  return [for (final n in nodes) n.copyWith(isCore: coreIds.contains(n.id))];
}
```

`_ensureCoreQuality` computes `CoreMetrics` on the candidate enrichment. If `coreTapFraction`
falls below the per-mode floor, it re-picks from the next-best qualifying set. **Bounded at 3
attempts**, then ships the best of what it saw.

**Do not add a relaxation pass** — pass 3 already exists (§0.3). Adding another widens the band
twice and defeats T1.1.

**This never regenerates a board** — contract C1 holds structurally, not by policy.

**The guarantee, stated as an invariant and asserted:**

```
No published board, in any mode, has coreTapFraction below its mode floor
— regardless of which selection path produced its cores.
```

**Required test:** force each of the four paths (band, relaxed, hatch #1, hatch #2) with
hand-built adversarial fixtures and assert the invariant holds on all four. A test that only
exercises the happy path does not test this fix.

### T1.3 — Medium core count 2 → 3 · *two sites, and an invariant*

**File:** `progression_profile.dart`. `coreCount: 2` appears **twice** for Medium:

| Site | Lines | Covers |
|---|---|---|
| explicit `sector == 3` branch | `:100-102` | sector 3 only |
| default `MechanicBudget` | `:103-110` | sectors ≥ 4 — i.e. most of the campaign |

Changing one leaves the other on the old count and produces a nonsensical curve
(sector 3 → 3 cores, sector 4+ → 2). **Update both.**

**Specify the invariant, not just the edit.** Medium's authoritative core rule:

```
sector 1        → 0 cores   (pure on-ramp)
sector 2        → 1 core    (introduce)
sector 3+       → 3 cores   (established)
```

**Required test:** assert `budgetForLevel(mode: medium, sector: s).coreCount == 3` for **all**
`s` in 3..8, not just a spot check. The duplicated-literal class of bug is only caught by
enumerating sectors.

**Balance:** verify Medium's mask can seat 3 cores under the `spreadOk` ≥ 2 rule at Medium's p5
node count (14). If relaxation pass 3 fires often, the spread rule — not the count — is the
binding constraint; log the relaxation rate before tuning further.

### T1.4 — Give Easy a mechanic arc · *lands last, and only after T1.2*

**File:** `progression_profile.dart:93-95`. Replace the unconditional early return:

```dart
if (mode == DifficultyMode.easy) {
  if (sector <= 2) return const MechanicBudget(coreCount: 0); // pure on-ramp
  return const MechanicBudget(coreCount: 1);                  // teach core-win
}
```

Locks, relays, gates and portals stay off on Easy. One core is enough to teach the idea before a
player meets Medium.

**Easy has exactly one quality gate, and it is T1.2's floor.**
`evaluateVisualComposition` returns `pass()` unconditionally for `DifficultyTier.easy`
(`visual_composition.dart:33`), so **T2.4 does not and will not apply to Easy**. There is no
compositional backstop. A single core on a small board is the F1 pathology in miniature, and the
tap floor is the only thing standing between Easy and it.

> **Design rule, recorded so no one later mistakes it for an oversight.** Easy's quality contract
> is deliberately different from Medium/Hard's:
>
> | | Easy | Medium / Hard |
> |---|---|---|
> | Gates | core tap floor · mechanic introduction · clear openings · solvability · basic shape variety | core quality · topology diversity · composition · branching · density · attention strategies |
>
> Easy exists for clarity, confidence, mechanic teaching and gradual novelty — not aggressive
> shape diversity. **If Easy ever fails a variety check, strengthen T1.2; do not extend T2.4 to
> Easy.** Doing so adds on-ramp complexity for no proven player benefit.

**Gate:** Easy's ≤6-tap share must stay at 0%.

### Checks and balances

| Risk | Control |
|---|---|
| Over-correcting Hard | Hard measures healthy (min 6, p50 11). Canary's Hard case asserts p50 within ±1; it shares the code path, so this is a real risk. |
| Easy becomes frustrating | Easy ≤6-tap share must remain 0%; Easy p50 taps must not fall below 9. |
| Floor bypassed by a hatch | Four-path adversarial fixture test (T1.2). |
| **Metric fixed, defect intact** | Node counts inflate so `coreTapDepth` rises while cores stay last-popped. T0.4§c asserts **node-count equality** — exact, since `coreCount` never reaches board planning. |
| **Mean lifted, worst boards untouched** | T0.4 severity view: Q1 must move, per-quintile. An improved mean with a static Q1 is a rejected result. |
| **Board geometrically cannot hold a deep core** | T0.4§d ceiling and `captureRate`. Boards with `ceiling < floor` are counted at baseline and shape T1.2's design. |
| Only half of Medium fixed | Sector-enumerated core-count test, sectors 3..8 (T1.3). |
| Repick loop cost | Assert `enrichLevel` p95 stays under 5 ms; assert repick attempts ≤ 3. |
| Solvability | 600-level device autoplay must return 600/600, 0 stuck. **Non-negotiable.** |
| Cores unreachable | Existing relay soft-lock property test must stay green. |

### Tests to re-baseline

`level_enrichment_test`, `corpus_benchmark_test` (silhouette histograms should be **untouched** —
if they move, geometry moved and something is wrong), `campaign_mechanic_audit_test`,
`difficulty_quality_audit_test`, plus CSV regeneration for `report_medium_100`,
`report_all_modes_100`, `report_hard_100`.

### P1 definition of done

- [ ] `core_triviality_test.dart` **fully green**, all three modes: Medium ≤6-tap < 5% and
      min ≥ 6; Easy ≤6-tap = 0% and p50 ≥ 9; Hard p50 within ±1 of the measured baseline 10.
      Medium p50 is **reported, not gated** — see T0.4§f for why 12–14 is an aspiration.
- [ ] Frozen-corpus diff produced: per-quintile before/after, `captureRate`, and the §T0.4e
      classification. Q1 must move; a fix that lifts the mean while leaving Q1 intact is rejected.
- [ ] All three T0.4 guards green — geometry identity, solution identity, **node-count equality**.
- [ ] Four-path floor invariant test green.
- [ ] Medium core-count = 3 asserted across sectors 3..8.
- [ ] Device autoplay 600/600, 0 stuck.
- [ ] Silhouette and topology histograms **byte-identical** to P0 — proof that no geometry moved.

### P1 outcome — 2026-08-19 · **SHIPPED as T1.1 + T1.2 + T1.3**

Full evidence in `docs/playtests/adversarial_baseline/P1_RESULT.md`. Summary:

| | before | after | gate |
|---|---|---|---|
| Medium ≤6-tap share | 66 % | **0 %** | < 5 % ✅ |
| Medium min taps | 2 | **7** | ≥ 6 ✅ |
| Medium p50 taps | 6 | **11** | reported, not gated |
| Easy ≤6-tap / p50 | 0 % / 11 | **0 % / 11** | 0 % and ≥ 9 ✅ |
| Hard p50 / min | 10 / 6 | **10 / 7** | 10 ±1 ✅ |
| `captureRate` p50 (Medium) | 0.58 | **1.00** | reported |
| §e classification | — | **0 UNFIXABLE, 0 SELECTOR-FAILED** | — |

`enrichLevel` p95 is **0.17 ms** against a 5 ms budget, and repick rungs are bounded at 3.

**Three corrections this phase forced into the plan.**

1. **§0.1 was wrong** — see the corrected section. Enrichment sits inside the accept/reject loop,
   so P1 moved 42 of 300 boards' geometry. Node deltas are non-directional (median 0), so the
   impostor is still excluded; the guards were re-baselined onto the post-P1 corpus with the
   pre-P1 CSVs archived under `genv1_pre_p1/`.
2. **T1.4 is a no-go on measurement, not a skip.** Easy geometry cannot hold a core deep enough
   for Easy's own floor: best achievable `coreTapDepth` with one core is **p50 3 taps** (max 7).
   Adding a core would turn an 11-tap clear-all board into a 3-tap board — F1 in miniature, and
   against T1.4's own gate. Easy stays coreless; teaching the core-win needs deeper Easy *boards*
   first, which is a generation change and out of P1's scope. Reasoning is recorded at the code
   site in `progression_profile.dart` so it is not mistaken for an oversight.
3. **T1.3's sector-2 invariant is softened in practice.** The nominal budget is still
   *sector 2 → 1 core*, but T1.2's escalation valve adds cores on boards too flat to reach the
   floor: of sampled sector-2 boards, 23 keep 1, 36 take 2, 8 take 3. Sectors 3–8 are at the cap
   and never escalate. Capping escalation at +1 was measured and fails the `min ≥ 6` gate
   (8 of 67 boards stay short, min falls to 3).

**One defect P1 introduced, found and fixed.** T1.3's third core blocks a third
row from relay placement, and the generator discarded any candidate that could not seat its full
mechanic budget — so **L427 Medium stopped generating entirely** (1 level in 1500; `Result.error`,
not a worse board). Nothing in the suite would have caught it: the corpus tests sample and the
`report_*` harnesses print generation failures without asserting. Fixed in `level_generator.dart`
by shipping a retained valid board at attempt exhaustion (`budgetFallback`, then
`mechanicShortFallback`) instead of erroring; both were already retained and discarded. New guard:
`campaign_generation_coverage_test.dart`. Post-fix sweep: 1..1500 × 3 modes, **0 failures, 0
unsolvable**.

**Costs.** Medium generation p95 64 → 107 ms; Hard p95 314 → 309 ms (flat); Daily p75 311 → 405 ms.
None of it is compute — it is candidate rejections, since different cores mean different mechanics
mean a different number of attempts. `report_daily_10_test`'s p75 ceiling moved 400 → 500 and
`generation_budget_test` now asserts on attempt count with wall clock as a coarse backstop; the
tiny-budget distribution itself did not move.

**Fresh draw — green.** 100 held-out ids (seed 20260820, disjoint from the corpus and from
`kReportSampleIds`): Medium min 6 / p50 11 / ≤6-tap **1.0 %**; Easy 0 % / p50 12; Hard p50 10 /
min 7. `p1_fresh_draw_test.dart`.

**Device autoplay — closed 2026-08-21.** Pixel 8a, 200 ids/mode over 1..598 stride 3, a real
`GameScreen` booted per level: **600/600, 0 stranded, 0 never-loaded** (Easy 200/200 avg 5.7 taps,
Medium 200/200 avg 8.6, Hard 200/200 avg 11.4). Evidence in
`docs/playtests/adversarial_baseline/P1_RESULT.md`. **The P1 definition of done is now fully met.**

### P1 re-baselined — 2026-08-21 · **the guards were red, and they were right**

**Everything in the P1 outcome above was measured against a baseline captured mid-phase.** The
2026-08-20 04:19 capture predates the core selector's final revision, which shipped in the same
commit a day later. Against the shipped tree that baseline was stale on **40 of 300 boards**, so
the three T0.4 guards and the ceiling invariant were red — the instrument working exactly as
designed, saying "the thing you measured is not the thing you shipped".

It went unnoticed because **every P1 gate is tagged `slow`**, and the phase was signed off on
`flutter test --exclude-tags "report || slow"`. Standing gate 2 means the *full* sweep at each
phase boundary; the fast run is a development loop, not a gate.

| | |
|---|---|
| Cause | core selection — 37 of the 40 shipped a different core set (§0.1's coupling, a third time) |
| Ruled out | the late attempt-exhaustion fallback (one level in 1..1500); a shared-generator harness change (reproduces the stale baseline *worse*: 76 node mismatches vs 18) |
| Done | baseline re-captured from the shipped tree · guards green 21/21 · `kP1GeometryMovers` recomputed against `genv1_pre_p1/`, **42 → 61** boards · stale CSVs archived under `p1_mid_selector/` |
| New harness | `adversarial_corpus_diff_test.dart` — the §e diff, committed, so the P1 numbers are re-derivable instead of hand-computed |

**Re-derived on the shipped tree, and the conclusion is unchanged:** severity p50 6 → 11,
≤6-tap 61 % → 0 %, `captureRate` 0.58 → **1.00**; representative 5 → 11, 67 % → 0 %, 0.55 → 1.00;
Hard p50 **10 → 10**, capture 0.64 → 0.64. Every quintile moved (Q1 p50 4 → 9, 100 % → 0 % ≤6-tap,
capture 0.40 → 1.00). §e over 300 boards: **0 VIOLATION · 266 FIXED · 34 INCIDENTAL · 0 UNFIXABLE ·
0 SELECTOR-FAILED.** Node counts moved on 30 boards, median 0, mean **+0.03**, all 100 Hard boards
unchanged at 25. Full detail in `docs/playtests/adversarial_baseline/P1_RESULT.md`.


### Rollback

Single-file revert of `level_enrichment.dart` + `progression_profile.dart`, plus re-pinning
`corpus_identity_test` and re-capturing the corpus baseline from `genv1_pre_p1/`. No save-data
implications: `isCore` is not persisted, and the boards that moved are regenerated from
`(levelId, mode, generationVersion)` either way.

---

## 4. Phase P2 — Unlock the variety already paid for

**Goal:** Hard topology classes 23 → ≥ 30; lattice share 68% → < 50%; mask fallback 8% → < 0.5%.

*Restated 2026-08-19 by T0.2 calibration: the original `14` is not reproducible under any encoding of the topology triple, so it cannot serve as a baseline. The canonical definition is now `kTopologyDefinitionVersion = 1`; Gen V1 baseline is Hard 23 / Medium 25 / Easy 40 at 300 ids/mode. See `docs/playtests/topology_class_calibration.md`.*

Ordered by risk. **T2.4a–b are free. T2.1, T2.2, T2.3 and T2.4c all move boards and must land
together** as one re-baselining event — behind T2.0.

### T2.0 — Bound the search-effort metric · *ADDED 2026-08-21, prerequisite for every board-moving task*

> **The name this task shipped under was wrong, and the correction is the whole finding.** It was
> scoped as an *in-constructor deadline*, on the strength of `docs/AGENT_STATE.md`'s "the entire
> cost sits inside one retrograde construction". **Profiling says otherwise.** On campaign L777
> Hard (74.6 s total):
>
> | phase | time |
> |---|---|
> | `computeSearchEffort` | **74,419 ms — 99.8%** |
> | retrograde construction (12 calls) | 102 ms |
> | `choosePlan` / `runPlanned` | 12 ms / 106 ms |
> | enrich · validate · waves · visual · CUD · dependency graph | ≤ 8 ms each |
>
> A constructor deadline was built first, measured, and **removed**: it fired zero times and
> could not have helped. `AGENT_STATE`'s claim was measured on Daily key `20260819` and does not
> generalise. The lesson is §0.1's, a third time: *profile before you fix.*

**Moved forward from P3.** The plan gated the in-constructor deadline behind P3 ("fix the
`milestone-overload` seed canary **before** this phase"). T2.1 proved that gate is in the wrong
place: relocating geometry drove Daily key `20260905` to a **873,856 ms single generation**, which
turned a 3:39 suite into a 15-minute hang and would be an instant ANR on device. T2.2, T2.3 and
T2.4c all move boards, so each can land on the same landmine.

**Why no budget could fix it.** `computeSearchEffort` runs *inside* the K-loop's candidate
evaluation, on every candidate, and the outer budget is only consulted between attempts. Key
`20260819` costing **4309 ms at a 200 ms budget and 4409 ms at 400 ms** (AGENT_STATE) is the same
symptom: the clock is never read during the work that is burning the time.

**The actual defect.** `computeSearchEffort` is a full backtracking search — `_solveState` →
`_dfsTieBreak` → `_commitMove` → `_solveState` — and `maxTieDepth: 3` does **not** bound it:
`_dfsTieBreak` recurses through `_solveState`, which re-enters tie-breaking at `depth: 0`, so the
depth counter resets on every commit. On a board with many tied moves it is exponential. Its
neighbour `computeViablePathCount` has carried `branchCap` / `expansionCap` / `maxMicroseconds`
since it was written; `computeSearchEffort` had no global bound of any kind.

**The fix is that same pattern**: `expansionCap: 50000`, `maxMicroseconds: 20000`, a latching
budget, and a `capped` flag on the result so a bounded run can never be mistaken for a solved one.

**Why this is board-neutral, and it is provable rather than argued.** `searchEffortScore` is read
by **nothing in `lib/`** — the only consumers are `board_report_utils.dart`'s CSV columns and
`search_effort_test.dart`. It does not feed the evaluator, the FSR cap, diversity gating or
candidate selection. Capping it therefore *cannot* change which board ships, and
`corpus_identity_test` confirms it: 360 boards byte-identical, `level_seed_test` and
`milestone_identity_test` green.

**Design constraints, in priority order:**

1. **A capped run must never masquerade as a completed one.** `solved` is forced false and
   `capped` is set; the counts become an explicit lower bound.
2. **Caps are parameters, not constants**, so a diagnostic sweep can raise them deliberately.
3. **Boards inside the budget are bit-identical** to their pre-T2.0 measurement — asserted.

**Candidate telemetry — deferred to the bundle, with a reason.** The open question from T2.1's
ledger regression is:

> Did the diversity ledger stop influencing selection, or did the generator stop producing
> eligible alternatives?

**Measured 2026-08-21: the regression is real and independent of T2.0.** With the search-effort cap
in place and T2.1 applied, determinism probes 1 and 3 still fail — back-to-back L44 boards remain
identical. So it is a genuine T2.1 effect, not a symptom of the latency explosion, and the
`candidateCount` / `novelCandidateCount` / `acceptedNovelCandidateCount` / `fallbackReason`
counters belong to the bundle that lands T2.1, where they can be read against a board that is
actually moving. Adding them now would instrument a tree in which T2.1 is parked and the effect
cannot reproduce.

### T2.0 outcome — 2026-08-21 · **SHIPPED**

| campaign level (Hard) | before | after |
|---|---|---|
| L777 | 74,385 ms | **175 ms** |
| L663 | 19,231 ms | **496 ms** |
| L629 | 4,614 ms | **566 ms** |
| worst of the nine known-slow | 75,834 ms | **566 ms** |

| suite-level | before | after |
|---|---|---|
| Daily p95 / p100 | 1,977 ms / 4,752 ms | **511 ms / 535 ms** |
| Daily keys > 800 ms | 2 (`20260819`, `20260906`) | **none** |
| `flutter test --exclude-tags "report \|\| slow"` | 3:39 | **1:41** |

Daily `20260819` is the key that produced a real device ANR and forced the worker-isolate
workaround; it is now bounded. **The isolate is still worth keeping** — it protects the UI thread
generically — but it is no longer load-bearing for this key.

**T2.1's blocker is gone.** With the cap in place and `T2.1_parked.patch` applied, Daily
`20260905` — the 873,856 ms case that started this task — reports p100 **528 ms** and
`report_daily_10_test` **passes**. The landmine that threatened T2.2/T2.3/T2.4c is defused.

**Gates:** `flutter analyze` clean · 759 passed / 0 failed · `corpus_identity_test` green (360
boards byte-identical) · `level_seed_test` + `milestone_identity_test` green · three new
machine-checked cases in `search_effort_test.dart` (bounded time, caps honoured and reported,
in-budget boards bit-identical).

**Not done, deliberately:** the 600-level device autoplay has not been re-run for T2.0. No board
changed, so its result cannot have changed — but it is the one standing gate taken on inference
rather than measurement, and it should be re-run before the Gen V1 freeze.

> **CORRECTED 2026-08-21, after T2.1 was implemented and measured. T2.1 was classified as "free"
> and it is not.** See T2.1 below. The correction is recorded rather than edited away because it
> is the *second* instance of the same reasoning error as §0.1: a true premise about the RNG
> stream carried to a false conclusion about board identity.

### T2.1 — Pass `jitter` to the nine builders that ignore it · *RNG-stream-neutral but content-changing*

**File:** `lib/game/levels/generation/layout_mask.dart`

`buildLayoutMask` (`:58-96`) passes `jitter:` to only 5 of 14 builders (`fullRect` returns null).
Nine have the signature `(int w, int h, Random? random)` and silently drop it:

`_vShape` · `_pentagonCells` · `_cShape` · `_lShapeCells` · `_zigzag` · `_randomBlob` ·
`_checkerboard` · `_scatteredHoles` · `_spiralCells`

Add `{Random? jitter}` to each and use it for shape parameters (arm width, offset, thickness,
hole placement) — following the exact pattern `_diamond` and `_cross` already use.

> **CORRECTED 2026-08-21. The struck-through claim below is wrong, and the error is instructive.**
>
> ~~**Why this is free:** the jitter RNG is seeded from `config.levelId + 1` and **never draws
> from the main `random` stream**. Node placement, metrics and everything downstream stay
> bit-identical.~~
>
> The **premise is true and was verified directly** — `layout_mask_test.dart`'s "jitter consumes
> NOTHING from the main random stream" asserts, for all 14 kinds across 8 grids, that the main
> stream sits at the identical position after a jittered build. Not one extra draw.
>
> **The conclusion does not follow.** The mask *shape* is itself an input to node placement, so
> changing what the nine builders emit changes boards without touching a single RNG draw.
> Measured over the 360-board `corpus_identity` sweep: **134 boards moved (37.2%)** — 49 Easy,
> 39 Medium, 46 Hard; bytes 164846 → 164511. Seeded and milestone boards did **not** move
> (`varied: false` ⇒ `jitterSeed: 0` ⇒ `jitter == null`); `level_seed_test` and
> `milestone_identity_test` are green.
>
> This is the same shape of error as §0.1, and it survived the same way: "no RNG draw" reads like
> "no change" until someone diffs the corpus. **T2.1 therefore joins the T2.2/T2.3/T2.4c
> re-baselining event** rather than shipping standalone, and `corpus_identity_test` is a
> documented expected-red canary from the moment T2.1 lands until that event re-pins it.

Corridor goes from 7 distinct outlines in 4,000 rolls to hundreds; `spiral` goes from **exactly one
outline per grid** — it ignored `random` outright — to 20+ in 200 rolls.

**Balance:** jitter must stay within the mask's existing size envelope — a jittered shape that
drops below `minCells` converts a variety win into a fallback. Assert per-kind null-rate does not
increase.

**Met, strictly**, for all nine builders at Hard's live floor of 25 on 8×8: every one is
non-increasing (`pentagon` 19→14/60, `randomBlob` 12→8/60, `spiral` 0→0/60, the rest 0→0).
`_pentagonCells` and `_spiralCells` needed their jitter ranges biased toward area preservation to
get there; both were tuned before anything shipped, so no seed moved on their account.

> **Pre-existing defect found by this test, and deliberately not fixed here.** `_hollowDiamond` is
> *not* one of T2.1's nine — it already took jitter — and its live `innerRatio` range of 0.30–0.60
> thins the annulus below Hard's 25-cell floor on **24 of 60** 8×8 rolls, against 0 unjittered.
> Roughly 40% of jittered `hollowDiamond` boards therefore ship today as plain rectangles, a
> silent variety loss. Retuning a live jitter range is a seed-moving edit and is not T2.1's to
> make; **T2.2's `minCells` 25 → 15 clears it entirely** (measured: 0/60 short at 15, for every
> kind — including `diamond`, which is 60/60 short at 25 and so is *always* rejected today).
> Pinned by the `PRE-EXISTING: hollowDiamond …` case in `layout_mask_test.dart`.

### T2.2 — Decouple `minCells` from `minNodes`

**File:** `director.dart:511`, `_buildOrFallbackMask`

```dart
- final minCells = config.difficulty.minNodes;          // 25 on Hard
+ final minCells = max(8, (config.difficulty.minNodes * 0.6).round());  // 15 on Hard
```

The mask only needs room for the target, and `_pickTargetNodeCount` already clamps
`hi = min(profile.nodeCount.max, mask.length)`. The 25-cell floor demanded 39% fill on 8×8 and
52% on 8×6, deleting diamond 32% of the time on 8×8, 86% on 7×7, 100% on 8×6.

**This does not touch `minNodes`**, so the FSR rule and the node-count floor are untouched.

**Balance:** smaller masks mean higher node density on the same silhouette. **Land T2.4c before
or with this**, or the extra density converts straight into occupancy/components rejections.

**Required assertion (added 2026-08-21):** T2.2 must explicitly close the `_hollowDiamond` silent
rect-fallback documented in T2.1 — ~40% of jittered 8×8 hollowDiamond masks fall under the 25-cell
floor today (24/60), and 0/60 under a floor of 15. The `PRE-EXISTING: hollowDiamond …` case in
`layout_mask_test.dart` already pins both halves; T2.2 turns the second half into the live
guarantee. If it is *still* pathological after the decoupling, only then consider a shape-specific
correction — do not pre-emptively patch the builder.

### T2.3 — Loosen `_refinePlanMaskDensity`

**File:** `director.dart:416-452`

```dart
- final maxArea = (plan.targetNodeCount * 1.15).ceil();
+ final maxArea = (plan.targetNodeCount * kMaskAreaSlack).ceil(); // 1.15 → ~1.5
```

and exempt organic archetypes from the dense-silhouette substitution entirely. This routine
silently discards the chosen silhouette and swaps in one of `_denseSilhouettes` — it is the direct
cause of Hard's 68% lattice / 2% archipelago split.

**Balance:** this clamp exists to stop sparse Hard boards with large voids ("Dense Strategy Phase
1C"). Relaxing it will lower fill%. Gate on `bboxOccupancy` and `largestEmptyRegion` from the
report utils — the original symptom must not return. Make `kMaskAreaSlack` a named constant so it
can be bisected.

### T2.4 — Composition validator: rejector → scorer, in **three stages**

**File:** `visual_composition.dart` — DEEP_TECH §30 applied where it pays most.

> **Correction to the draft.** The draft converted rejection to ranking in one step, then gated on
> "p10 composition score does not collapse". That control is unusable on the first run: you obtain
> the score distribution only *by* converting, so there is no baseline to compare p10 against.
> Changing the measurement system and the decision system in the same commit is the error. Split
> them.

#### T2.4a — Observe · *zero behaviour change, zero seed impact*

Extend the result type, compute the score, **keep rejecting exactly as today**:

```dart
class VisualCompositionResult {
  final bool passes;       // unchanged semantics in this stage
  final double score;      // 0..1 composition quality  ← NEW, computed but unused
  final VisualCompositionRejectReason? reason;
}
```

Log `score` plus per-rule detail (`components`, `singleton`, `occupancy`, `blobVsGrid`, `aspect`)
into the corpus CSVs for both the accepted and the rejected populations.

#### T2.4a outcome — 2026-08-21 · **SHIPPED**

**Shape of the change.** `evaluateVisualComposition` had five early returns; it now computes all
five rules and resolves the reject reason at the end **in the identical priority order**
(aspect → blobVsGrid → occupancy → singleton → components). Counting all singletons/components
instead of bailing at the first excess yields the same predicates on n ≤ 42.

`VisualCompositionResult` gains `detail` (five 0..1 sub-scores, higher = better), `score` (their
unweighted mean) and `evaluated`. The mean is **deliberately unweighted** — weighting before
seeing the distributions would bake in the assumption T2.4b exists to test.

**`evaluated` is load-bearing, not bookkeeping.** Easy short-circuits to `pass()` without running
the rules, and an empty board does too. Recording those as a perfect 1.0 would pull the accepted
distribution upward and corrupt the very threshold T2.4b is meant to choose. They are flagged and
excluded instead.

**Both populations, as specified.** Accepted boards are scored into the corpus CSVs
(`compScore`, `compEvaluated`, `compAspect`, `compBlobVsGrid`, `compOccupancy`, `compSingleton`,
`compComponents`). Rejected candidates never reach a CSV — they are discarded inside the K-loop —
so `LevelGenerator` now records `visualScoresAccepted` / `visualScoresRejected` (sample-capped at
50k). Without that second list T2.4b would calibrate against the survivors only, which is the
population least able to tell it where the threshold belongs.

**Zero behaviour change, verified not asserted:** `corpus_identity_test` green (360 boards
byte-identical), `visual_composition_test` green including a new case pinning the priority order,
full suite **766 passed / 0 failed**, runtime unchanged at 1:41, `flutter analyze` clean.

**Not done, and correctly so:** nothing reads `score` yet. T2.4b chooses the threshold from these
distributions; T2.4c is the first stage that lets the score change a decision.

#### T2.4b — Calibrate · *analysis, no code change*

Over a representative corpus (300+ levels/mode), establish p10/p25/p50/p75/p90 of `score`, and
critically **the score distribution of boards the current validator already accepts**. That
population defines "known-good". Only now is a p10 floor a meaningful gate, because it has a
baseline.

Deliverable: the distributions committed to `docs/playtests/`, and the chosen p10 threshold
written into the plan before T2.4c is implemented.

#### T2.4b outcome — 2026-08-21 · **CLOSED. These are the numbers T2.4c is gated on.**

Full reasoning in `docs/playtests/composition_calibration_decision.md`; raw distributions in
`docs/playtests/composition_calibration.md` (300 ids/mode, seed `20260821`, 200 ms budget).

**The threshold:**

| mode | shipped p10 (measured) | **gate** |
|---|---|---|
| Medium | 0.6327 | **0.63** |
| Hard | 0.6595 | **0.65** |

> After T2.4c, over the same 300-id/mode sample, the **shipped** population's p10 composition
> score must be ≥ 0.63 (Medium) and ≥ 0.65 (Hard).

It is a **regression guard, not an admission test** — using it to reject candidates below 0.63
would defeat the point of T2.4c. Per-mode rather than one global number because Hard's known-good
sits genuinely higher; a single 0.63 gate would let Hard sag to Medium's level untripped.

**Separation is good enough to rank on:** the gate sits below **91.6%** of currently-rejected
Medium candidates (88.2% Hard) and only **11.0%** of accepted ones (6.0% Hard). Shipped vs
rejected p50: Medium 0.7624 vs 0.4660; Hard 0.7931 vs 0.5486.

**Reject-reason volumes re-measured — the draft's figures do not reproduce, same class of error as
the topology `14` and F1's `44%`:**

| rule | plan's figure | measured Medium | measured Hard |
|---|---|---|---|
| `components` | 2,614 Hard | 843 | **1,602** |
| `singleton` | 1,044 Hard | 355 | **735** |
| `occupancy` | 1,338 Medium | **1,672** | **0** |
| `blobVsGrid` | — | 269 | 232 |
| `aspect` | 28/42 | 38 | 88 |

**Three consequences for T2.4c:**

1. **`occupancy` rejects literally zero of 2,657 Hard candidates.** Hard ships ~25 nodes on 8×8 and
   clears the 0.35 floor by construction, so softening `occupancy` is a **Medium-only** change.
   The plan's table presents it as general; it is not.
2. **`components` is 60% of all Hard rejections** — the single biggest variety lever on Hard,
   confirming the plan's ordering even at a lower absolute count.
3. **`aspect` is the lowest-volume rule in both modes**, which supports keeping it a hard reject.

**The gate is sample-bound.** It must be re-measured by re-running
`composition_calibration_test.dart` on its own 300-id/mode sample (seed `20260821`) — *not* on
`kReportSampleIds`. On the same day, same metric, the 100-id report sample reads Medium p10
**0.6059**, below the 0.63 gate, with nothing wrong: it is a smaller draw of a distribution whose
p10 sits near the gate. Judging T2.4c against the wrong sample would manufacture a regression.

**A metric flaw was found and fixed mid-calibration, and it mattered.** T2.4a scored the `aspect`
and `blobVsGrid` terms even for boards the rules deliberately *exempt* (`skipAspectCheck` /
`skipBlobVsGridCheck` — corridors and intentionally small-bbox masks). Shipped-Medium `aspect` read
p10 = p25 = **0.0000**. Exempted rules now score 1.0. The correction moved Medium's shipped p10
from 0.4926 to **0.6327** and closed an apparent Medium-vs-Hard gap of 0.16 down to 0.03 —
**calibrating on the uncorrected metric would have produced a materially wrong per-mode
threshold.** This is precisely why §T2.4 splits calibration from ranking.

#### T2.4c — Rank · *moves seeds; lands with T2.2/T2.3*

Reclassify the five rules:

| Rule | Today | After | Rationale |
|---|---|---|---|
| `components` | reject | **score** | 2,614 Hard rejects — the dominant weirdness cap |
| `singleton` | reject | **score** | 1,044 Hard rejects |
| `occupancy` | reject | **score** | 1,338 Medium rejects |
| `blobVsGrid` | reject | **score** | wasted-canvas aesthetics, not validity |
| `aspect` | reject | keep reject | low volume (28/42), genuinely broken framing |

Also raise `allowedSingletons` (`:164`) and `allowedComponents` (`:190`) from
`max(2, maskComponents)` to `maskComponents + 2`.

At the K-loop (`level_generator.dart:778`), replace the `continue` with a contribution to
candidate ranking. Hard rejects still `continue`.

**Balance — this remains the highest-risk change in P2.** Controls: (a) score must be a *ranking*
term strong enough that a well-composed candidate still wins when one exists; (b) p10 must not
fall below the T2.4b threshold; (c) manual visual review of 20 sampled Hard boards on device
before and after. Numbers cannot fully judge "looks good"; look at them.

**Easy is unaffected at every stage** — `evaluateVisualComposition` short-circuits to `pass()` for
`DifficultyTier.easy` (`:33`). See T1.4.

### Checks and balances

| Risk | Control |
|---|---|
| Boards become ugly / scattered | T2.4b p10 floor; 20-board device review |
| Latency regression | Hard gen p95 must stay ≤ 260 ms; ideally improves as rejections fall |
| Solvability | 600/600 device autoplay |
| Fallback rate rises | shipped mask→rect must fall 8% → < 0.5%, never rise |
| Milestone boards repainted | seeded path reads `pool.first` — **append only, never reorder** pools |

### Tests to re-baseline

`corpus_benchmark_test` (histograms **will** move — that is the point),
`hard_nodecount_distribution_test`, `board_variety_inspection_test`, `visual_composition_test`
(rewritten for scoring), `report_hard_100_test`, `dense_strategy_snapshot_test`,
`experiment_b_grid_aspect_test`, `level_seed_test` (must stay green — seeded boards must not move).

### P2 definition of done

- [ ] Hard topology classes ≥ 30 (from the calibrated baseline of 23, +30%), measured under
      `topologyDefinitionVersion: 1`; lattice share < 50% (from 68%).
- [ ] Longest same-silhouette run ≤ 3 (from 6); worst 5-level window ≥ 2 families.
- [ ] Rolling min-Hamming median ≥ 5 (from 3.00).
- [ ] Shipped mask fallback < 0.5% (from 8%).
- [ ] Hard L45–56 no longer contains five full-rect boards — the visible symptom.
- [ ] T2.4b distributions committed and p10 threshold chosen **before** T2.4c landed.
- [ ] Gen p95 not worse; device 600/600.
- [ ] `level_seed_test` green — milestone boards unmoved.

---

## 5. Gen V1 freeze

Entered only when T0 + P0 + P1 + P2 are **complete and validated**, not merely merged.

- [ ] All DoDs above checked off.
- [ ] Corpus regenerated; CSVs carry `corpusVersion: 1 / generationVersion: 1 / strategyVersion: 0
      / seedContractVersion: 1`.
- [ ] Byte-identity re-verified under `LevelGenerator.neutral()` across the full sample sweep.
- [ ] Tag the commit. This is the artifact the closed test runs against.

**Seed-freeze rule.** After the freeze, no change may alter a board under
`(levelId, mode, generationVersion=1, recipeId=neutral)`. Generator changes bump
`generationVersion` instead. This is what makes post-test iteration safe.

---

## 6. Phase P3 — Strategy Composer

**Goal:** composable strategies with zero added fallback pressure. Behaviour-neutral at rest.

### T3.1 — The strategy type

**New:** `lib/game/levels/generation/strategy/board_strategy.dart`

```dart
abstract class BoardStrategy {
  String get id;
  bool appliesTo(LevelConfiguration config, SessionContext? session);
  /// Bounded nudges to the plan. Must never widen beyond profile bands.
  GenerationPlan shapePlan(GenerationPlan plan, double strength, Random random);
  /// Preference, not requirement. Added to candidate ranking.
  double score(LevelData level, LevelMetrics m, CoreMetrics cm, double strength);
  /// Post-hoc observation only — NEVER a rejector.
  bool verify(LevelData level, double strength);
}
```

Eight to start: `density`, `depth`, `branching`, `cascade`, `symmetry`, `predictionBreak`,
`falseDependency`, `shapeNovelty`.

### T3.2 — Composer with compatibility matrix

**New:** `strategy/strategy_composer.dart`. Encodes the master plan §3.3 matrix, enforces the
**1–3 strategy limit**, and implements **bounded degradation (max 2 rounds)**: on a low-scoring
candidate, reduce the weakest strategy's strength and re-score rather than discard.

The matrix is a performance feature — it prunes the search space so construction is never asked
for something incoherent.

### T3.3 — Tiered portfolio

**File:** `level_generator.dart`, around the existing K-loop.

| Tier | Applies to | Budget p95 | Candidates |
|---|---|---|---|
| 1 Normal | ordinary campaign | ≤ 200 ms | 1 |
| 2 Important | sector openers, directive levels | ≤ 300 ms | 3 |
| 3 Peak | daily, boss (`id % 25 == 0`) | ≤ 600 ms | 5 |

**Milestone/seeded levels are excluded from portfolio work entirely** — they are already the
device outliers at 4.1 s (levels 225, 250, 350, 425, 450). Add an explicit guard and a test.

### Neutrality — P3's real deliverable

Two tests, not one. The second is the one that catches the subtle failure.

```dart
test('composer at neutral strength reproduces Gen V1 byte-for-byte', () {
  // 300 levels/mode, all strategies at 0 strength, recipeId = neutral.
  // Any diff means the composer is not actually neutral.
});

test('neutral composer consumes NO additional randomness', () {
  // Assert the RNG draw count per generation is identical to Gen V1.
  // A "disabled" feature that still draws from the stream shifts every
  // subsequent board — byte-equality on level N can pass while N+1 silently moves.
});
```

The draw-count test is not redundant with the byte-equality test: a feature that draws and
discards can leave the first board identical and every later board different.

### Checks and balances

| Risk | Control |
|---|---|
| Latency blowup | Device harness, not just headless. Hard p50 must stay ≤ 2.3 s end-to-end |
| Silent behaviour drift | Both neutrality tests above |
| Degradation loops | Hard cap of 2 rounds, asserted |
| Strategies fight each other | Compatibility matrix unit-tested for symmetry and reachability |
| Benchmarks silently incomparable | Bump `strategyVersion` to 1 in CSV headers (T0.2) |

### P3 definition of done

- [ ] Both neutrality tests green across 900 boards.
- [ ] Hard gen p95 ≤ 200 ms; device p50 ≤ 2.3 s.
- [ ] Safe-recipe rate < 0.5%.
- [ ] Milestone exclusion asserted.
- [ ] Fix the pre-existing `milestone-overload` seed canary **before** this phase — Tier 3 must
      avoid a path that is already the latency outlier.

---

## 7. Phase P4 — Tension Budget and session arc

**Goal:** density bouncing, via the only lever with headroom.

> **Gate: P4 requires live telemetry.** Once a session recipe can vary the board, a level id maps
> to a board *family*; reproducing a player's board needs the logged `recipeId`. Without recipe
> logging, every bug-report, QA and support workflow the determinism contract exists to protect
> silently breaks. `contentIdentity` (T0.0c-b) must be stamped on every generation event before
> the first adaptive board ships.

### T4.1 — `SessionContext`, injected not threaded

**New:** `lib/services/session_context.dart`; injected into `LevelGenerator` exactly as
`DiversityLedger` is. **No per-level signature changes.** The `LevelManager._generator` refactor
this needs was already done in T0.0c.

### T4.2 — Session boundary

Read a persisted `last_session_end_ms` in `main.dart` after `StorageService.init()`; write it in
the `paused` branch of `game_screen.dart:607-615`, which already fires at the right moment and
currently does half the job (`resumed` is a bare `break`). One new Hive key.

### T4.3 — Tension Budget

Per-mode budgets across density / depth / branching / deception / novelty / cascade, honouring
`kHardEffectiveFillMin/Max = 0.45/0.60` (`level_configuration.dart:63-68`) — **declared today and
read by nothing.**

**Density contributes via mask size and grid span, never node count.**

> **Hard constraint:** do not push Hard node count past 28. The FSR cap is disabled below 28
> (`difficulty_profile.dart:106-110`); crossing it activates an evaluator rule for the first time
> and mass rejection follows. This is the single most likely way to break the generator.

### T4.4 — Novelty Budget

At most one novelty axis per level — new shape *or* new logic *or* high density, never all three.

### Checks and balances

| Risk | Control |
|---|---|
| Determinism regressions | Neutral default `SessionContext` ⇒ every existing suite byte-identical, **and** zero extra RNG draws (same test shape as P3) |
| Tension ratchets to unfun | Hard ceiling per mode; must reset on session boundary; ≤6-tap and taps-to-win floors still enforced |
| Node count creep | Assert Hard node count ≤ 28 |
| Unreproducible player reports | `contentIdentity` asserted present on every generation event |

---

## 8. Phase P5 — Attention layer

**Prerequisite gate:** confirm single-tap undo is present and frictionless. **Do not start
otherwise** — undo is what separates a fair trap from Valve's removed Portal bug.

Six traps at the retrograde direction-assignment seam, driven by **local direction entropy** — a
generation parameter, not a rendering trick: Long Lane Blocker, Broken Run, Incongruent
Neighbourhood, Continuity Line, Anchored First Tap, Sector Habit Break.

**Machine-checkable gates, asserted in tests:** same-direction run ≤ 4 · detection ≤ 3 s at
29 ms/item · trap node on the solution path · ≤ 2 traps/board · ≥ 70% at zero cost.

**Rejected by name so they cannot creep in:** Occlusion Swap, Lying Secondary Cue (belongs on the
art review checklist explicitly), Illegible Glyph, Late Reveal, Stochastic Node, Timed Trap.

Prefer bonus framing (Closure Gap) over penalty framing wherever the same principle applies.

---

## 9. Phase P6 — Multi-session

**Blocked on telemetry.** Analytics ships one event and crash reporting is dark. Do not build
adaptive systems with no feedback signal.

Three items are already built and merely unwired: `DiversityLedger.serialize/restore` (zero
callers), the computed-but-never-displayed day streak, and `LevelResult` (discarded after star
grading — **nothing tracks losses at all**). Plus concrete-shape bits in the ledger fingerprint so
two 8×8 donuts stop reading as novel.

---

## 10. Execution order and gating

```
T0.0a  Generator Input Closure Audit          ── audit, may block
T0.0b  Determinism probe (hypothesis test)    ── may FAIL; fix before proceeding
T0.0c  Contract in code + genVersion          ── no board changes
T0.1   CoreMetrics                            ── lib/, uncalled
T0.2   Corpus columns + version headers       ── test-tree only, no assertions
T0.3   core_triviality_test  (RED)            ── all P1 gates live here
T0.4   Frozen adversarial corpus + baseline   ── measurement only; GATE INTO P1
────── T0 COMPLETE ──────
T1.1   Core band → tap depth
T1.2   Core floor at the single choke point   ── downstream of BOTH hatches
T1.3   Medium core count, BOTH sites          ── + sector-enumerated test
T1.4   Easy mechanic arc                      ── only after T1.2 is green
       P1 verification: canary green, 600/600, histograms byte-identical,
                        frozen-corpus diff (Q1 moved), then a fresh unseen draw
T2.0   In-constructor deadline + telemetry    ── safety; no board change when in budget
T2.4a  Composition score, shadow mode         ── free, still rejecting
T2.4b  Calibration + threshold selection      ── analysis only
T2.1   Jitter propagation             ┐        (moves 134/360 boards — measured)
T2.2   minCells decoupling            ├─ one re-baselining event
T2.3   Mask density slack             │
T2.4c  Score-first ranking            ┘
       P2 verification + 20-board device review
────── FREEZE GEN V1 ──────
────── CLOSED TEST ──────
       Telemetry
P3 → P4 → P5 → P6
```

| Phase | Seeds move? | Before closed test? | Gate to enter |
|---|---|---|---|
| T0.0a closure audit | no | **yes** | — |
| T0.0b determinism probe | no | **yes** | T0.0a; **zero forbidden hidden state** |
| T0.0c contract in code | no | **yes** | probe 5 green |
| P0 instruments | no | **yes** | T0 DoD |
| T0.4 frozen corpus | no | **yes** | T0.3 canary committed red |
| P1 core + Easy | **no** (§0.1) | **yes** | P0 DoD + **T0.4 baseline frozen** |
| **P2 T2.0 deadline** | **no** (must prove it) | **yes** | P0 DoD |
| P2 T2.4a / T2.4b | no | **yes** | T2.0 landed |
| P2 T2.1 / T2.2 / T2.3 / T2.4c | **yes** | **yes** | T2.4b threshold chosen **+ T2.0 landed** |
| **Freeze Gen V1** | — | **yes** | P1 + P2 DoD, validated not merely merged |
| — CLOSED TEST — | frozen | — | corpus re-baselined and tagged |
| P3 composer | no if neutral | no | P1+P2 DoD; milestone canary fixed |
| P4 tension budget | yes | no | P3 DoD + **telemetry live** |
| P5 attention | yes | no | P3 DoD + undo confirmed |
| P6 multi-session | no | no | **telemetry live** |

**Standing gates for every phase — no exceptions:**

1. `flutter analyze` clean.
2. Full suite green, minus explicitly documented expected-red canaries.
3. 600-level device autoplay: **600/600, 0 stuck**.
4. Hard gen p95 not worse than the previous phase.
5. CSVs regenerated with version headers and committed to `docs/playtests/`.
6. One-file-at-a-time revertability; no phase mixes seed-moving and non-seed-moving work.

---

## 11. What changed from the draft, and why

| # | Change | Cause | Severity |
|---|---|---|---|
| 1 | Determinism demoted from established fact to **T0.0b hypothesis test**; T0.0a input-closure audit added | Cited proof (`level_seed_test:59`) runs level 75, a **seeded** milestone — it never tested the procedural path | High |
| 2 | Easy gate moved out of a report test into `core_triviality_test.dart`; **no new report file** | All three campaign `report_*` tests contain **zero assertions** by design; `report_all_modes_100` already covers Easy. Both reviewer options (new file / widen all-modes) put a gate in a non-blocking diagnostic | High |
| 3 | T1.2 restructured to a **single choke point downstream of both hatches**; four-path adversarial test required | §0.3 — there are **two** descending-id fallbacks, not one; a check beside either leaks through the other. Also: the relaxation pass reviewers asked for **already exists** | **Critical** |
| 4 | T1.3 names **both** `coreCount: 2` sites + sector-enumerated invariant test | Editing one leaves sectors ≥ 4 on the old count — most of the campaign | High |
| 5 | T2.4 split into **a/b/c** (observe → calibrate → rank) | The draft's p10 gate had no baseline on first run: it changed measurement and decision in one commit | **Critical** |
| 6 | Easy's differing quality contract recorded as an explicit design rule | `evaluateVisualComposition` short-circuits for Easy, so T1.2's floor is Easy's *only* gate — this must not read as an oversight later | Medium-high |
| 7 | Added `contentIdentity` logging, CSV version headers, and the P3 **RNG draw-count** neutrality test | A "disabled" feature that still draws from the stream keeps board N identical and moves every board after it | High |

**Two draft statements were factually wrong about the code and are corrected in place:** the
determinism evidence (§Decision 1) and the single-fallback claim (§0.3).

### Added after T0.3 landed — 2026-08-19

| # | Change | Cause | Severity |
|---|---|---|---|
| 8 | F1 baseline recalibrated: Medium ≤6-tap **66%** (not 44%), p50 **6**; Hard p50 **10** (not 11) | T0.3 measured it. The 44% is not reproducible under any encoding of "taps" — same class of error as the topology `14` in §P2 | High |
| 9 | **T0.4 frozen adversarial corpus added** as the gate into P1 | A random corpus cannot distinguish a real fix from node inflation or from a mean-shift that leaves the worst boards intact. At 66% the defect is too large to change the core algorithm unmeasured | **Critical** |
| 10 | Node inflation reclassified from "≤10% guardrail" to **exact equality invariant** | Verified: `budget.coreCount` reaches only `level_enrichment.dart` post-generation, and `directiveFor` is never read by the generator — so all of P1 must be geometry-identical | High |
| 11 | Medium p50 12–14 demoted from acceptance gate to design aspiration (T0.4§f) | Prescribing a 2× move before seeing the distribution creates an optimisation target whose cheapest solution is node inflation — the exact false positive the corpus exists to catch | High |
| 12 | Achievable-depth **ceiling** and `captureRate` added per board | Some geometries cannot hold a deep core at all. Without a ceiling, "selector chose badly" is indistinguishable from "board cannot do better", and the count of `ceiling < floor` boards is a design input to T1.2 | Medium-high |
| 13 | Sector filter removed from the corpus population | The `T0_EXIT_GATE.md` sketch restricted Medium to "cores, sectors 3+" — which excludes the sector-2 single-core 2-tap boards that *are* the defect | **Critical** |

---

## 12. What could go wrong

| Failure | Early signal | Response |
|---|---|---|
| T0.0b probe 5 fails | fresh-generator sweep diverges | Hidden input beyond the ledger — inspect `_pendingEmission`, `_lastWinningBlockingRetryIndex`. **Do not enter P1.** |
| Most Q1 boards are `ceiling < floor` | T0.4 baseline reports a large unfixable set | T1.2's bounded repick cannot fix these. Move the remedy upstream into candidate rejection **before** writing T1.2 — do not let it silently ship "best seen" |
| P1 lifts the mean, Q1 unmoved | frozen-corpus per-quintile diff | Not a fix. The band retarget is landing on boards that were already healthy — re-examine T1.1's percentile source |
| Node counts moved during P1 | T0.4 node-count equality guard red | P1 leaked into geometry, which §0.1 says is impossible. Something upstream reads `coreCount` — find it before trusting any other number |
| Corpus quietly became a tuning target | thresholds changed after inspecting frozen ids | Result is void. Re-validate on `kReportSampleIds` and a fresh draw (T0.4§g) |
| P1 over-corrects Hard | canary Hard case red (p50 moves > 1) | Gate the tap-depth band per mode |
| P1 repick loops | `enrichLevel` p95 > 5 ms | Lower cap to 2; accept best-seen |
| Floor still bypassed | four-path fixture test red | A third path exists — re-run the §0.3 audit before tuning |
| T2.4c makes boards ugly | p10 below the T2.4b threshold | Re-reject `components` only; keep others soft |
| T2.2 raises rejections | occupancy/components rejects rise | T2.4c must land first or together — do not ship T2.2 alone |
| P3 blows latency | device p50 > 2.3 s | Drop Tier 2 to 2 candidates; keep Tier 1 at 1 |
| P3/P4 "neutral" isn't | draw-count test red | Neutral path is drawing from the stream — fix before proceeding |
