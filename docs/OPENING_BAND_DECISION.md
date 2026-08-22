# Unbound (Chain Pop) — Game Overview & the Opening-Band Decision

> **Purpose of this document.** It does two things:
> 1. Gives a deep, accurate overview of the game and how levels are generated.
> 2. Lays out a single open **product/engineering decision** — what to do about the Hard/Expert "opening width" difficulty target — with the *what, why, pros, and cons* of each option, plus a recommendation.
>
> Everything in the "Problem" and "Evidence" sections is backed by measurements taken directly from the current generator (see [Appendix B](#appendix-b--evidence-log)).

---

## Part 1 — The Game

### 1.1 What it is

**Unbound: Arrow Puzzle** (codename `chain_pop`) is a minimalist, extraction-based logic puzzle built with **Flutter + Flame**.

- **Core fantasy:** a calm, contemplative "untangle the board" puzzle.
- **One rule:** every node holds a directional arrow (up/down/left/right). You may remove a node **only if its arrow's straight-line path to the board edge is unobstructed** by any other node still on the board. Tap in the wrong order and the node **jams** (visual + haptic feedback, no penalty beyond the clock).
- **Goal:** clear the board (or, on "core" levels, restore all core nodes).
- **Guarantee:** every level is **solvable by construction** — deadlocks are mathematically impossible (see §1.4).

Scale: ~23.6k LOC across ~133 lib files, ~10.4k LOC of tests across ~85 files, 540+ passing tests.

### 1.2 The core loop (runtime)

```
Player taps a node
  → ChainPopGame.canExtract(node)
     → LevelSolver.canRemove(node, activeNodes)   // ray-walk along the grid
        → blocked? → JAM animation (after repeated jams on the same node: a blocker-flash hint)
        → clear?   → POP animation → update activeNodes → re-check win
           → win?  → save stars + unlock next level (via StorageLocator)
```

The legality check (`LevelSolver`) is **pure Dart**, isolated from the Flame engine, so the rules are unit-testable without spinning up rendering.

### 1.3 Mechanics & "game feel"

The presentation layer is unusually rich for the genre:

- **Aim-ray preview** on touch-down, so a jam is "a choice, not a surprise."
- **Rising SFX pitch** on extraction streaks; combo text; a **cascade finale** on core wins.
- **"Freed" pulses** that telegraph chain cause → effect.
- **Special node kinds:** `locked` (needs empty neighbors first) and `relay` (rotates its whole row on pop, with proper LIFO undo). `isCore` nodes change the win condition from "clear all" to "restore cores."
- **Accessibility/UX:** colorblind palette, sound/haptics/aim-ray/ambient toggles, undo, ad-gated hints, and a telescoping level-select (20 → 100 → 500 tiers).
- **Modes:** campaign (Easy → Medium → Hard by level id), plus a **Daily Challenge** (Expert tier).
- **Monetization:** interstitials between levels, rewarded-continue, ad-gated hints, and a "Remove Ads" entitlement via RevenueCat.

### 1.4 How levels are generated (this is the key to the problem)

Levels are built **backward** — "retrograde construction" — which is the single best architectural decision in the project.

Conceptually:

1. **Place nodes one at a time** onto a grid silhouette (the allowed-cell mask), in *forward placement order*.
2. **Reverse that order to get the removal order.** Index `0` = removed **first**; index `N-1` = removed **last**.
   - **Critical consequence:** a node's id == its position in the removal order. The node placed **last** gets the **lowest** id (removed first).
3. **Assign each node a direction** whose ray avoids every node still on the board at the moment it should be removed.
4. **Validate** the full removal sequence (`LevelValidator` / `LevelSolver`); retry on failure.

**The solvability invariant** (`_directionClearAtRemovalStep`): at the step when node `i` is removed, ids `0..i-1` are already gone and ids `i..N-1` remain. So node `i`'s ray must be clear of **higher ids**. Equivalently: **a node's ray can only ever be "blocked" (at the start) by a node with a *lower* id.** This fact drives everything below.

The generator wraps this in a large research-grade tuning layer: a **Director**, **MAP-Elites archetypes**, **motifs**, **silhouettes**, **sightline tables**, and a **diversity ledger** (~28 files). It is powerful but complex, and it is the project's biggest long-term maintenance liability.

---

## Part 2 — Difficulty Bands (the spec the generator must hit)

Each difficulty **tier** declares a target *band* for several metrics (`lib/game/levels/generation/difficulty_profile.dart`). A level "passes" only if every metric is in-band. The relevant ones:

| Metric | Meaning |
|---|---|
| `firstLegalMoveCount` / `waveZeroWidth` | **Opening width** — number of legal first moves on turn one (= count of "ray-free" nodes whose arrow already reaches an edge). |
| `forcedSequenceRatio` (FSR) | Fraction of the solve that is forced (only one legal move). Higher = more "on rails" / tense. |
| `nodeCount` | Number of nodes on the board. |
| `waveDepth`, `criticalUnlockDepth`, `averageBranchingFactor` | Shape/length of the dependency structure. |

Current Hard/Expert targets:

| Tier | nodeCount | **opening** | FSR | wave depth |
|---|---|---|---|---|
| Hard | 25–50 | **3–5** | 0.45–0.90 | 5–8 |
| Expert (Daily) | 28–55 | **3–5** | 0.50–0.85 | 6–10 |

There is also a global **FSR cap**: if `nodeCount > 28`, FSR must be `≤ 0.40`, regardless of tier. (This exists to stop huge boards from being tediously over-forced.)

**The audit test** (`test/game/levels/generation/difficulty_quality_audit_test.dart`) is the enforcement mechanism: it would fail the build if Hard/Expert levels fall outside their bands. It is currently **skipped**, because it would fail 100% of the time (see Part 3).

---

## Part 3 — The Problem

### 3.1 Statement

**The generator does not hit its own opening-width target, and never has.** The spec says Hard/Expert openings should be **3–5**. In reality the generator produces **~8–11**. Because the audit would fail forever, it has been **skipped** — so the spec is currently a fiction that nothing enforces.

This is the single unresolved item from the codebase review. It matters because:

- **It's a silent lie.** Code, comments, and (a stale) README claim "tight 3–5 openings" while the game ships 8–11.
- **A skipped test protects nothing.** Even real regressions (opening jumping to 15, or collapsing to 1) go uncaught.

### 3.2 What "opening width" actually is, mechanically

Opening width = the number of nodes that are **ray-free** at the start (arrow already points to an edge with nothing in the way). To *reduce* the opening, you must make a ray-free node **blocked** — i.e., redirect it to point at another node that sits on its ray.

But the solvability invariant (§1.4) says that node can **only** legally point at a node with a **lower id** (one that will be gone by the time this node is removed), *and* the ray beyond it must still be clear of higher ids at removal time.

So: **shrinking the opening requires that each "extra" ray-free node has a lower-id node sitting on one of its four rays, with a clear path.** That is the entire crux.

---

## Part 4 — What We Tried, and the Evidence

A measurement-first investigation ("Phase B"). A re-runnable measurement harness was added at `test/game/levels/generation/opening_compression_measurement_test.dart`.

### 4.1 Baseline (current shipping generator, ~25 nodes)

| Corpus | opening avg | opening range | over-5 | FSR avg | in-band |
|---|---|---|---|---|---|
| Hard L30–59 | **8.2** | 5–11 | 29/30 | 69% | 1/30 |
| Daily sample | **8.6** | 6–12 | 10/10 | 68% | 0/10 |

### 4.2 Lever 1 — Opening-window compression pass (no spec change)

Added a pass that flips ray-free nodes in the opening to point at a lower id, reusing the proven blocking + revalidation machinery. **Result: inert.** Opening avg 8.2 → 8.2 (Hard), 8.6 → 8.6 (Daily). **Zero effect.**

### 4.3 Lever 2 — Density lift (the approved spec experiment)

Hypothesis: denser boards give ray-free nodes more lower-id targets. Lifted Hard `minNodes` 25 → 30, raised the FSR-cap threshold 28 → 40 (to avoid the cap-vs-band contradiction), and tightened the grid to raise fill.

**Result: it made the opening *worse*, not better.**

| Config | fill | opening avg | in-band |
|---|---|---|---|
| Baseline (25 nodes) | 52% | 8.2 | 1/30 |
| +density (30 nodes, 8×8) | 52% | 9.6 | 0/30 |
| +density +tight grid | **63%** | **10.1** | 0/30 |

### 4.4 Instrumented proof (the decisive data)

Instrumenting the live construction path across **276 generated Hard/Expert candidates**:

| Stage | avg opening |
|---|---|
| raw (after crunch reassignment) | **14.6** |
| after opening-window compression | 14.1 |
| after the existing `_enforceOpeningTarget` | **10.7** |
| **candidates that ever reached ≤ 5** | **0 / 276** |

### 4.5 Why density can't fix it (the root cause)

- Opening width = count of ray-free nodes. Adding nodes adds **more** ray-free nodes faster than it adds usable blockers.
- A ray-free node can only be blocked by a **lower-id** node on a clear ray. In retrograde construction, **low ids are placed *last*** — so they are scattered and rarely land on the rays of the nodes that need blocking.
- ~10 of the ~14 ray-free nodes simply have **no valid lower-id target**. This is **geometric starvation**, and it is independent of fill ratio.
- It's also independent of id re-assignment: ray-free status is *pure geometry* (positions + directions), so re-ordering ids cannot change which nodes are ray-free. It can only change which flips are *legal* — and the legal ones are already exhausted at ~10.7.

**Conclusion:** `3–5` openings are **structurally unreachable** by tuning this generator. The only way to truly reach them is to change how nodes are *placed* (a construction redesign), not how many there are.

---

## Part 5 — The Decision

> **The question is not "which band number is better."** It's: **how do you make the spec and the shipped reality agree — by changing reality, or by changing the spec?**

This is fundamentally a **product call**: how much does the original "tight, tense opening" vision matter, versus the cost of chasing it?

### Option A — Enforce the honest range (`~[3,11]`) and un-skip the audit  ✅ *Recommended*

**What:** Set the Hard/Expert opening band to the measured achievable range (e.g. `[3, 11]`), document *why* (this file + the evidence log), and turn the audit back on against the truthful band.

**Why it's defensible (and not "gaming"):** see [the critical distinction](#the-critical-distinction-gaming-vs-honest-recalibration) below. We're describing the game we actually ship and making it enforceable — the opposite of hiding a regression.

**Pros**
- The spec becomes **true** and **enforceable** today.
- The audit, un-skipped, now **catches real regressions** (e.g. an opening that jumps to 15 or collapses to 1).
- Zero gameplay risk, zero generator churn, no threat to the solvability test net.
- Stops the "we target 3–5" lie in code/docs.

**Cons**
- Codifies a **looser opening** (8–11 starting choices) as "intended." The first turn is less tense than the original vision wanted.
- Superficially resembles the band-widening we previously condemned — requires the documentation trail to stay honest.

### Option B — Redesign retrograde construction to actually hit `[3,5]`

**What:** Change *placement* so low-id nodes are deliberately positioned as blockers — e.g. bias the final placements (which become low ids) into a compact, co-linear "capping chain" that sits on the rays of the would-be opening nodes.

**Why:** It's the only path that **keeps the tense `[3,5]` design** as a genuine, met target.

**Pros**
- Preserves the original game-feel vision.
- If it works, the audit passes *honestly* at `[3,5]`.

**Cons**
- **Large, multi-session effort** in the most complex, highest-bus-factor part of the codebase (`retrograde_constructor.dart`, ~1k lines).
- **Uncertain payoff** — capping has a theoretical "net-zero" trap (a capping node can itself become a new opening node unless it too points lower), so even a big effort may not reach `[3,5]`.
- **Risks the solvability guarantee** and the 538-test safety net; high regression surface.
- Deepens investment in machinery the review already flagged as over-engineered for the payoff.

### Option C — Leave the audit skipped; document and move on

**What:** Keep things exactly as they are: skipped audit, findings recorded here, no spec change.

**Pros**
- Zero work, zero risk now.
- Keeps the door open to revisit later.

**Cons**
- The spec stays a known lie; the audit keeps protecting nothing.
- The problem silently rots; the next person re-discovers it from scratch.

### Option D — Cut the difficulty machinery instead

**What:** If `[3,5]` can't be met and the elaborate tuning layer exists largely to chase unmet targets, retire the unused tuning layers and accept a simpler generator.

**Pros**
- Directly attacks the review's biggest finding (complexity/payoff inversion).
- Large reduction in long-term maintenance liability.

**Cons**
- Big, invasive deletion; needs care to keep solvability + variety.
- Separate, larger initiative — not a quick fix to the band question.

---

### The critical distinction: gaming vs. honest recalibration

Widening a band *looks* identical to the metric-gaming previously condemned. It is **only** acceptable under the conditions in the right column:

| Metric gaming (bad) | Honest recalibration (Option A) |
|---|---|
| Widen the band silently to force a green check | Widen the band **only after proving** `[3,5]` is structurally impossible |
| Game actually got **worse** (openings went *up*), hidden by the wider band | Game is **unchanged**; we're describing it truthfully |
| No rationale recorded | Documented with measurements (this file + evidence log) |
| **Masks** a regression | **Enables catching** future regressions |

---

## Part 6 — Recommendation

**Option A.** Set Hard/Expert opening to `[3, 11]`, document the rationale, un-skip the audit against the honest band, and add an explicit assertion that no Hard/Daily level ships *above* the band max (so a future regression is caught). Then move on to the higher-value work (GameScreen decoupling, docs sync, and — if appetite exists — the Option D simplification of the generator).

Pursue **Option B** only if a tense `[3,5]` opening is judged core to the product's identity and worth a dedicated, risky redesign with uncertain payoff.

---

## Appendix A — Where things live

| Concern | File |
|---|---|
| Difficulty bands, FSR cap, `passes()` gate | `lib/game/levels/generation/difficulty_profile.dart` |
| Node-count / density / grid sizing | `lib/game/levels/generation/difficulty_parameters.dart`, `level_configuration.dart` |
| Retrograde construction + opening compression (`_enforceOpeningTarget`) | `lib/game/levels/generation/retrograde_constructor.dart` |
| Generation orchestration (Director, K-loop, emission) | `lib/game/levels/generation/level_generator.dart` |
| Metrics (opening, FSR, wave profile) | `lib/game/levels/generation/metrics.dart` |
| Core legality rule (ray walk) | `lib/game/levels/level_solver.dart` |
| The (skipped) enforcement gate | `test/game/levels/generation/difficulty_quality_audit_test.dart` |
| Re-runnable measurement harness | `test/game/levels/generation/opening_compression_measurement_test.dart` |

## Appendix B — Evidence log

- Baseline Hard L30–59: opening avg **8.2** (range 5–11), FSR avg 69%, **1/30** in-band.
- Baseline Daily sample: opening avg **8.6** (range 6–12), FSR avg 68%, **0/10** in-band.
- Opening-window compression pass: **inert** (no measurable change).
- Density lift to 30 nodes: opening avg **9.6** (worse); +tight grid (63% fill): **10.1** (worse).
- Instrumented run, 276 Hard/Expert candidates: raw **14.6** → compression **14.1** → `_enforceOpeningTarget` **10.7**; **0/276** ever reached ≤ 5.
- All experimental levers were **reverted**; current tree is the honest baseline (`flutter analyze` = 0; `flutter test` = 541 passed, 3 skipped; debug APK builds). No difficulty spec is currently changed.

## Appendix C — Note on the README

`README.md` is **stale** for difficulty: it lists e.g. Hard as "6×6–16×16, 5–60 nodes, 40% density, strip fallback." The code no longer matches (Hard nodes 25–100 in config, tighter grids, no monotone/strip fallback path). Whichever option is chosen, the README difficulty tables should be re-synced as part of the docs cleanup.
