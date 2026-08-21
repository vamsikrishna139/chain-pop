# Unbound V2 — Master Plan

**Date:** 2026-08-19 · **Branch:** `new_improvements` · **Status:** plan only, no code changed

**Supersedes:** `docs/DEEP_TECH.md` (eight speculative drafts) and `docs/BOARD_STRATEGY_PLAN.md`
(the measured audit). This is the single plan of record. Both remain readable as source
material; neither should be implemented from directly.

---

## 0. How to read this

`DEEP_TECH.md` is strong design thinking written **without measurement**. The audit is
measurement written **without a design frame**. They fit together well:

- **DEEP_TECH supplies the conceptual frames** — Tension Budget, scoring-first, the Strategy
  Composer, graceful degradation, the Fairness Firewall. These are genuinely better than what
  the audit proposed and are adopted wholesale.
- **Measurement supplies the facts and the ordering** — which problems are real, which are
  imagined, and what will actually break.

Where they conflict, measurement wins, and §2 lists every conflict explicitly. Three of
DEEP_TECH's central assumptions are false against the real engine, and building on them would
waste a phase each.

**Evidence base:** 600 levels autoplayed on a Pixel 8a (600 wins, 0 stuck) · 900 boards
profiled headlessly (300/mode) · 500-level Hard diversity benchmark · engagement and deception
research reports.

---

## 1. Ground truth

The five facts everything else is built on. Full derivations in `BOARD_STRATEGY_PLAN.md`.

| | Finding | Evidence |
|---|---|---|
| **F1** | **"Finishes in a jiffy" is Medium, not Hard.** Medium boards with cores: median **6** taps to win, min **2**. Without cores: median **20**. 44% end in ≤6 taps. Hard is healthy (min 6, p50 11, 1% ≤6). | 100 boards/mode |
| **F2** | **Easy ships zero mechanics, forever.** `progression_profile.dart:93-95` returns early with all counts 0. All 100 Easy boards have `tapFrac` exactly 1.000 and zero cascades. | corpus |
| **F3** | **The mask fallback is 0% / 0% / 8%, not 99%.** But the 8% clusters — Hard L45–56 has five full-rect 8×8 boards in twelve levels. Cause: `minCells = minNodes` = 25 on Hard (`director.dart:506`). | 300 levels/mode |
| **F4** | **Variety is fine numerically, poor perceptually.** 157–182 distinct cell-sets but only **23–40 topology classes** (recalibrated; originally reported as 14–30 under a definition that is no longer reproducible — see `docs/playtests/topology_class_calibration.md`); Hard is 68% lattice, 2% archipelago; macro-runs to 13 levels; rolling min-Hamming median **3.00** vs the ledger's own threshold of 5. | 500-level benchmark |
| **F5** | **The density knob is dead.** Hard node count is the constant 25 (194/200 levels); the fill-ratio expression is inert on 187/200. All real density variance comes from mask size (25→64 cells). | 200 levels |

**F1's root cause is the single most important line in this document:** the core band
`[0.35, 0.65]` (`level_enrichment.dart:38-44`) is enforced in **removal-wave percentile**.
Waves are *parallel* — one wave retires many nodes — so on a shallow board, wave-50% is tap
two. At the dead centre of the intended band the median is still 6 taps and the minimum is 2.
The band is being honoured; it is measuring the wrong quantity.

**Device latency**, Pixel 8a, full level lifecycle: Easy p50 650 ms · Medium 993 ms · Hard
2197 ms, p99 3142 ms. The five boards over 3.5 s are levels 225, 250, 350, 425, 450 — all
multiples of 25, the seeded boss/milestone path. Headless generation: Hard p95 260 ms against
a 200 ms budget; Daily p95 1353 ms, max 4834 ms against 400 ms.

---

## 2. Reconciliation — DEEP_TECH vs. measurement

### 2.1 Adopted wholesale (DEEP_TECH is right and better than the audit)

| # | Idea | Why it's right |
|---|---|---|
| §30 | **Scoring-first, not rejection-first** | The most important engineering change in either document, and measurement *validates* it: 2,614 components rejects and 1,044 singleton rejects on Hard, 1,338 occupancy rejects on Medium. The rejection-first validator **is** the variety killer of F4. |
| §6 | **Three core metrics, not one** | Extends F1 correctly. Depth alone is insufficient — a late core on an 85-irrelevant-node board is still a bad puzzle. |
| §7 | **MeaningfulDecisionCount** | Difficulty is decision structure, not dependency length. Partially exists already as `viablePathCount` / `averageBranchingFactor` / `choice_rhythm.dart`. |
| §10 | **Tension Budget replaces Density Bouncing** | This *rescues* goal (3). F5 proves raw density has no headroom; tension distributes across density / depth / branching / deception / novelty / cascade, so the goal survives the dead knob. |
| §8–9 | **Strategy Composer + Compatibility Matrix** | Composability was an explicit goal. The matrix is what keeps the search space small — i.e. what keeps generation fast. |
| §36 | **Graceful strategy degradation** | This is *the* zero-fallback mechanism. Reduce the weakest strategy and re-score rather than discard the board. |
| §5 | **Fairness Firewall** | Independently confirmed by the deception research: induce **slips** (right plan, wrong hand), never **mistakes** (wrong plan, missing info). "I should have seen that", never "I couldn't have known". |
| §12 | **Novelty Budget — one axis at a time** | Directly addresses F4's perceptual problem rather than its numerical one. |
| §35 | **Fallback is a designed known-good archetype** | Correct framing. A safe recipe, not "99 failures → random level". |
| §50 | **The don't-build list** | Adopted verbatim; see §7. |

### 2.2 Overridden by measurement

| DEEP_TECH claim | Measured reality | Consequence |
|---|---|---|
| `CoreWave >= 80%`, and `CoreWaveRatio` as a primary metric | Wave percentile **does not bound tap count** (F1). At wave-50% the min is still 2 taps. | `CoreWaveRatio` is demoted to a secondary signal. **Tap depth is the primary metric.** Building on wave ratio repeats the existing bug with a bigger number. |
| Latency targets P50 < 10 ms, P95 < 25 ms, P99 < 50 ms | Hard headless p50 **82 ms**, p95 **260 ms**. Device lifecycle p50 **2197 ms**. | Off by 8–25×. These targets are unreachable without replacing retrograde construction. Real targets in §3.2. |
| "Retrograde generation is cheap, so generate 3–5 candidates" | It is the dominant cost. Daily p95 is 1353 ms, max 4834 ms; the budget **cannot preempt a single in-flight construction**. | Portfolio size must be **tiered**, and Tier 3 must never land on milestone levels — those are already the 4.1 s outliers. |
| "Shape Vault: start with 20–30 curated silhouettes" | 13 mask kinds already exist and are reachable. **Nine of fourteen builders silently ignore their `jitter` parameter** — corridor yields 7 distinct outlines in 4,000 rolls, asymmetric 15. | Don't author 20–30 new shapes into a pipeline that cripples the ones it has. Fix jitter first; that alone turns 7 into hundreds, at zero seed cost. |
| Density Bouncing as its own feature | The knob is inert on 187/200 Hard levels; node count is a constant. | Subsumed into Tension Budget. Density is modulated via **mask and grid span**, never node count. |
| Multi-session player model as a near-term phase | Analytics is dark — one event ships, crash reporting is off. | Deferred to P6. There is nothing to learn from until telemetry exists, and an adaptive system tuned on no data is worse than none. |

### 2.3 The one thing both documents got wrong

Neither noticed **F2**. Easy — the mode new players land on — has no cores, locks, relays,
gates or portals at any sector, forever. Every plan in `DEEP_TECH.md` designs adaptive
sophistication for Hard while the on-ramp is 300 levels of "tap every node in a legal order".
This is now P1 work, alongside F1.

---

## 3. Architecture

### 3.1 The pipeline

```
Session Director  ──┐   (P5; neutral no-op until then)
                    ▼
              LevelRecipe          strategies @ continuous strength 0..1
                    │
          Strategy Composer        compatibility matrix prunes invalid combos
                    │
           Director plan           mask, grid span, fill, mechanic budget
                    │
      Target-aware construction    retrograde, aiming at the recipe
                    │
        Candidate portfolio        Tier 1: 1 · Tier 2: 3 · Tier 3: 5
                    │
              Soft scoring         density depth branching cascade novelty
                    │              deception symmetry opening
              ┌─────┴─────┐
       score ok?          below floor?
              │                 │
              │        Strategy degradation  ── reduce weakest, re-score
              │                 │              (bounded: max 2 rounds)
              ▼                 ▼
           Ship best      Safe recipe (designed known-good archetype)
```

**Hard rejection only for:** unsolvable · broken geometry · invalid core state · invalid
mechanic state · out of bounds. Everything else scores.

### 3.2 The five contracts

These are the stability guarantees. Any change that violates one is out of scope by definition.

**C1 — Zero-fallback by construction.** Strategies are *soft*: they re-weight a search that
already produces a valid board. An unsatisfiable strategy degrades, then costs a telemetry
miss — never a regeneration. Target: safe-recipe rate **< 0.5%** on ordinary levels (today's
comparable figure is the 8% Hard mask fallback, which P2 removes).

**C2 — Latency, grounded in measurement.** Not DEEP_TECH's numbers.

| Tier | Applies to | Budget (headless p95) | Portfolio |
|---|---|---|---|
| 1 — Normal | ordinary campaign levels | ≤ 200 ms (unchanged) | 1 candidate |
| 2 — Important | sector openers, directive levels | ≤ 300 ms | 3 candidates |
| 3 — Peak | daily, boss (`id % 25 == 0`) | ≤ 600 ms | 5 candidates |

**Milestone/seeded levels are exempt from portfolio work entirely** — they are already the
device outliers at 4.1 s. Tier 3 must be gated off them explicitly.

**C3 — Determinism.** A neutral default `SessionContext` keeps every existing generation suite
byte-identical — the same contract `timeBudget` already honours. Session adaptivity is opt-in
per call site. Note that repeat-call stability is *already* broken today (`generate(130)` and
`generate(7)` differ; `level_generator_test.dart:195` passes only because id 42 happens to be
stable) — see §8.

**C4 — Fairness Firewall.** A strategy may create uncertainty; it may not create *unknowable*
uncertainty. Every trap node must lie on the solution path. Full information visible before
commitment. Single-tap undo is a prerequisite, not a nice-to-have.

**C5 — Solvability.** Untouchable. Levels stay solvable from any reachable state; relays remain
the only soft-lock risk, guarded by `_relayIsSoftlockSafe`. 600/600 device wins is the
regression baseline.

### 3.3 Strategy compatibility matrix

The matrix is a performance feature, not a design nicety — it shrinks the valid search space so
the composer never asks construction for something incoherent.

| Strategy | Combines with | Never with |
|---|---|---|
| Density | almost everything | extreme deception |
| Deep chain | low branching, corridor/spiral | high branching |
| Branching | moderate density, ring/cross | deep chain |
| Cascade | high density | precision |
| Deception | moderate density, moderate depth | extreme density, extreme branching |
| Precision | low branching | cascade |
| Shape novelty | everything | — |

**Composition limit: 1–3 strategies per board, at continuous strength.** More than three is
where DEEP_TECH correctly warns the output becomes junk.

---

## 4. The metric set

Built first, because every later phase is graded on it. Nothing here changes behaviour.

| Metric | Catches | Status today |
|---|---|---|
| **TapsToWin** | F1 — the jiffy problem | **missing — this is the gap** |
| **CoreTapDepth** | core reachable too early (primary core gate) | missing |
| CoreCriticalDepth | meaningful dependencies before the core | partially — `computeCriticalUnlockDepth` |
| CoreIsolationScore | board mostly irrelevant to the core | missing |
| **MaxSingleTapCascade** | one tap collapsing the board | missing |
| MeaningfulDecisionCount | effortless-but-technically-deep boards | partially — `viablePathCount`, `choice_rhythm.dart` |
| TopologyClass | F4 — perceptual sameness | missing (exists only in audit probes) |
| ConcreteShapeHash | ledger can't tell two donuts apart | missing |
| FSR, waveDepth, branching | existing evaluator | present |

**CoreWaveRatio is retained as a secondary signal only.** It is what the engine gates on today
and it is the wrong unit.

---

## 5. Phases

Ordered by evidence strength and by how much each disturbs the seed stream. P0–P2 are
pre-launch. P3+ is a deliberate content regeneration.

---

### P0 — Instruments · *no behaviour change · no seed impact*

Add `TapsToWin`, `CoreTapDepth`, `CoreIsolationScore`, `MaxSingleTapCascade`, `TopologyClass`
to the corpus report utilities and CSVs. Add a per-mode taps-to-win floor assertion that
**fails on today's Medium**, so F1 can never regress silently.

- **Done when:** all three mode CSVs carry the new columns; the canary is red on current Medium
  and the reason is documented in the test.
- **Risk:** none. Test-only.

---

### P1 — The two correctness bugs · *highest value · moves seeds*

**P1a — Retarget the core band to tap depth.** Change `_climaxBandCoreIds` to select on
sequential tap index rather than removal-wave percentile, keeping `[0.35, 0.65]`. Add the three
core gates (`CoreTapDepth`, `CoreCriticalDepth`, `CoreIsolationScore`) as **soft scores with a
hard floor on tap depth only** — per §3.2 C1, the other two must not become rejectors. Raise
Medium's core count 2 → 3 so the spread constraint bites as it does on Hard.

- **Target:** Medium p50 taps-to-win 8 → **12–14**; ≤6-tap share 44% → **< 5%**; min never below 6.
- **Explicitly do not touch Hard.** It measures healthy; the risk here is over-correction.
- **Re-baseline:** `level_enrichment_test`, `report_medium_100`, `corpus_benchmark`.

**P1b — Give Easy a mechanic arc.** Introduce cores on Easy at a late sector with a low count
(1), keeping locks/relays/gates/portals off. Easy should teach the core-win idea before a
player ever reaches Medium, not present it as a surprise.

- **Target:** Easy `tapFrac` p50 drops below 1.0; Easy retains its 0% ≤6-tap rate.
- **Risk:** Easy is the new-player on-ramp. Ship behind the P0 canary and verify the ≤6-tap
  floor holds before and after.

---

### P2 — Unlock the variety already paid for · *large win · partly moves seeds*

Four changes, ordered by value per unit of risk:

1. **Pass `jitter` to the nine builders that ignore it** (`layout_mask.dart:68-95`).
   Stream-neutral by construction, **zero seed impact**, no test should object. Corridor goes
   from 7 distinct outlines to hundreds. *This is the single highest-yield free change in the
   plan.*
2. **Decouple `minCells` from `minNodes`** (`director.dart:506`) — e.g.
   `max(8, (minNodes * 0.6).round())`. Removes essentially all 24 Hard rectangle fallbacks and
   un-deletes half the diamond / archipelago / corridor rolls. Does **not** move the node floor,
   so the FSR rule is untouched — but Hard's RNG consumption shifts, so the Hard corpus needs
   re-baselining.
3. **Loosen `_refinePlanMaskDensity`'s 1.15× clamp** or exempt organic archetypes
   (`director.dart:417-455`). This is what directly attacks the 68% lattice share.
4. **Convert the composition validator from rejector to scorer** (`visual_composition.dart`) —
   DEEP_TECH §30 applied where it pays most. Raise `allowedComponents` / `allowedSingletons`
   from `max(2, maskComponents)` to `maskComponents + 2`, and make occupancy and blobVsGrid
   **soft scores**. 2,614 Hard rejects are components rejects; this is what "weird shapes"
   actually needs.

**Free inventory to switch on:** a thickened `checkerboard` (built, never selected) and
`pickIrregularKind` — a complete unused second selection API that already takes a `preferred`
subset. That is the experimental/backup pool, already plumbed.

**Hard rule:** **append** to shape pools, never reorder. The seeded path reads `pool.first`, so
appending never repaints a milestone board.

- **Targets:** Hard topology classes 23 → **≥ 30**; lattice share 68% → **< 50%**; longest
  same-silhouette run 6 → **≤ 3**; worst 5-level window ≥ 2 distinct families; rolling
  min-Hamming median 3.00 → **≥ 5** (the ledger's own bar).

---

### P3 — Strategy Composer · *new subsystem · behaviour-neutral by default*

Implement `BoardStrategy` as a named modulator with: precondition · plan deltas · scoring terms
· verification predicate. Implement the composer with the §3.3 compatibility matrix, the 1–3
composition limit, continuous strength, and **bounded degradation (max 2 rounds)**.

Implement the tiered candidate portfolio per C2, with milestone levels excluded.

Start with eight strategies at continuous strength: `density`, `depth`, `branching`, `cascade`,
`symmetry`, `predictionBreak`, `falseDependency`, `shapeNovelty`.

- **Done when:** with all strategies at neutral strength, the corpus is **byte-identical** to
  P2's. That equivalence test is the phase's real deliverable.
- **Risk:** this is where latency regresses. Gate on C2 with the device harness, not just
  headless timings.

---

### P4 — Tension Budget and the session arc · *replaces "density bouncing"*

Add `SessionContext`, injected into the generator exactly as `DiversityLedger` is — **no
per-level signature changes**. Detect a session boundary in `main.dart` against a persisted
`last_session_end_ms`; write it in the `paused` branch of `game_screen.dart:607-615`, which
already fires at the right moment and does half the job today.

Implement per-mode **Tension Budgets** with maximum bands, honouring the already-declared
`kHardEffectiveFillMin/Max = 0.45/0.60` constants that nothing currently reads. Tension ramps
toward the band ceiling as session length grows and resets on a new session. Density
contributes via **mask and grid span**, never node count.

Add the **Novelty Budget**: at most one novelty axis per level (new shape *or* new logic *or*
high density — not all three).

- **Do not:** push Hard node count past 28. The FSR cap is disabled below 28
  (`difficulty_profile.dart:89-98`); crossing it switches on an evaluator rule for the first
  time and mass-rejection follows.
- **Targets:** within-session tension trends upward without the ≤6-tap floor or the latency
  budget moving.

---

### P5 — The attention layer · *needs undo confirmed first*

Six highest-volume fair traps, driven by **local direction entropy** at the retrograde
direction-assignment seam: Long Lane Blocker, Broken Run (the original "three lefts" idea),
Incongruent Neighbourhood, Continuity Line, Anchored First Tap, Sector Habit Break.

The mechanism is *not* a rendering trick. An odd arrow among identical arrows pops out
preattentively and can't be missed; the same arrow among heterogeneous arrows requires serial
search at ~29 ms/item. Pure generation parameter — no art changes, every glyph at full contrast.

Machine-checkable generation gates: same-direction run ≤ 4 · detection ≤ 3 s at 29 ms/item ·
trap on the solution path · ≤ 2 traps/board · ≥ 70% of traps at zero cost.

**Prefer bonus framing over penalty** (Closure Gap and relatives) — same perceptual principle,
strictly safer.

**Rejected traps, by name, so they don't creep in:** Occlusion Swap (mutating state during
animation — would work at ~50% catch rates, which is exactly why it's refused), Lying Secondary
Cue (a glow implying a direction other than the arrow's — belongs on the art review checklist),
Illegible Glyph, Late Reveal, Stochastic Node, Timed Trap.

---

### P6 — Multi-session intelligence · *blocked on telemetry*

**Prerequisite: analytics and crash reporting must ship first.** One event currently ships and
crash reporting is dark; an adaptive system tuned on no data is worse than none.

Three things already exist and are simply unwired:

- `DiversityLedger.serialize/restore` has zero callers — every launch starts with an empty
  anti-repeat window.
- A working consecutive-day streak is computed and **never shown** in the daily UI.
- `LevelResult` carries the full per-level performance vector and is discarded after grading
  stars. **Nothing tracks losses at all.**

Also add concrete-shape bits to the ledger fingerprint so two identical 8×8 donuts stop reading
as novel (F4).

---

## 6. Sequencing summary

| Phase | Seed impact | Ship before launch? | Blocked on |
|---|---|---|---|
| P0 Instruments | none | yes | — |
| P1 Core + Easy | **moves seeds** | yes | P0 |
| P2 Variety | partly (jitter is free) | yes | P0 |
| P3 Composer | none if neutral | optional | P1, P2 |
| P4 Tension Budget | moves seeds | no | P3 |
| P5 Attention | moves seeds | no | P3, undo confirmed |
| P6 Multi-session | none | no | **telemetry** |

---

## 7. Deliberately not building

Adopted from DEEP_TECH §50, plus two from the research:

- **LLM-generated levels.** The deterministic generator is faster, testable, controllable.
- **Massive forward-solver search.** Undermines the retrograde architecture.
- **Random weirdness.** Noise is not variety — that is what the Novelty Budget prevents.
- **Forced jam mechanics.** Especially risky given the Network Integrity penalty.
- **Lives as a retention mechanic.**
- **Dozens of new gameplay mechanics.** The combinatorial potential already exists.
- **A validator that rejects almost everything.** This is the current bug (F4), not a risk.
- **Covert autopilot-adaptive difficulty.** A placebo study found that *telling* players the
  game adapts raised immersion whether or not it did. No published method detects flow from
  touch input alone. The honest framing is cheaper and carries no backlash risk.
- **20–30 newly authored silhouettes** before fixing the jitter bug that cripples the 13
  existing ones.

---

## 8. Decisions taken — 2026-08-19

Both closed. Full reasoning in `IMPLEMENTATION_PLAN_V2.md` → *Decisions taken*.

1. **Determinism — YES, as a formal contract:**
   `Board = f(levelId, mode, generationVersion, recipeId)`, with `recipeId = neutral` by default
   and byte-identical output under it, forever.

   The engine is *already* deterministic given its full input — `level_seed_test.dart:59` proves
   it with two fresh generators. Repeat-call instability comes from one hidden mutable input: the
   `DiversityLedger` / `SilhouetteSessionTracker` carried on the process-lifetime static
   generator. Reproducibility and adaptivity were never actually in tension; the trade only
   appeared because an input was implicit. Declare it and both hold.

   `generationVersion` is introduced now at 1. Session adaptivity selects a *recipe*; it never
   silently rewrites a published level id.

   **Consequence:** P4 moves behind the telemetry gate alongside P6 — adaptive boards are
   unreproducible unless `recipeId` is logged.

2. **Regeneration window — land P0 → P1 → P2 before the closed test**, then freeze the corpus as
   **Generation Version 1** and test against it. Seed changes are free exactly once, before any
   tester has progress or notes; a mid-test regeneration would make it impossible to tell whether
   a complaint was fixed, replaced or re-rolled. P3+ does **not** get squeezed into this window.

---

## 9. Success criteria

Measured against today's real baselines, not aspirations.

| Metric | Today | Target | Phase |
|---|---|---|---|
| Medium ≤6-tap boards | 44% | **< 5%** | P1 |
| Medium min taps-to-win | 2 | **≥ 6** | P1 |
| Medium p50 taps-to-win | 8 | **12–14** | P1 |
| Easy `tapFrac` p50 | 1.000 | **< 1.0** | P1 |
| Hard topology classes / 300 | 23 (calibrated, defn v1) | **≥ 30** | P2 |
| Hard lattice share | 68% | **< 50%** | P2 |
| Longest same-silhouette run | 6 | **≤ 3** | P2 |
| Rolling min-Hamming median | 3.00 | **≥ 5** | P2 / P6 |
| Hard mask fallback (shipped) | 8% | **< 0.5%** | P2 |
| Hard gen p95 (headless) | 260 ms | **≤ 200 ms** | P3 |
| Device stuck rate | 0/600 | **0** — never regress | all |

**Live KPIs once telemetry exists:** levels/session · sessions/day · D1/D7/D30 · completion
rate · jam rate · undo rate · core-triviality rate · shape/topology repetition. Plus a
lightweight voluntary "too easy / good / hard / confusing / fun" prompt after experimental
levels.

---

## 10. Known pre-existing red

Unrelated to this plan: the `corpus_benchmark` milestone-seed canary fails —
`milestone-overload` emits no seed annotation. That is the known milestone-fallthrough bug
(16 of 40 milestone levels ship as ordinary procedural boards). It should be fixed before P3,
because the milestone path is also the latency outlier that Tier 3 must avoid.
