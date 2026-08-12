# Unbound: Arrow Puzzle — Full Architecture & Game-State Reference

**Repo:** `vamsikrishna139/chain-pop` · **Dart package:** `chain_pop` · **App name:** Unbound: Arrow Puzzle
**Android id:** `com.adbkv.chainpop` · **Version:** `1.0.0+1` · **Stack:** Flutter 3.3+ / Flame 1.37 / Hive 2.2
**Doc generated from source at commit `7ab95dd`** ("feat: adaptive strategy, immersive pacing & relay softlock safety").

This file is the single end-to-end reference for the repo: what the game is, how every subsystem
works, why the current design was chosen, and where the code disagrees with the older docs.
Section 1 is a self-contained **context prompt** you can paste into a fresh LLM session; sections
2–16 are the deep reference.

---

## Table of contents

1. [Section 1 — Copy-paste context prompt (current game state)](#1-copy-paste-context-prompt-current-game-state)
2. [System map](#2-system-map)
3. [The core rules (authoritative)](#3-the-core-rules-authoritative)
4. [Data model](#4-data-model)
5. [Level generation — end to end](#5-level-generation--end-to-end)
6. [Layout / silhouette generation](#6-layout--silhouette-generation)
7. [Metrics, evaluator bands and diversity](#7-metrics-evaluator-bands-and-diversity)
8. [Enrichment: cores, locked nodes, relays](#8-enrichment-cores-locked-nodes-relays)
9. [Runtime engine (Flame)](#9-runtime-engine-flame)
10. [Board layout math (screen fitting)](#10-board-layout-math-screen-fitting)
11. [Flutter UI layer & screen flows](#11-flutter-ui-layer--screen-flows)
12. [Session systems: pacing, goals, streaks](#12-session-systems-pacing-goals-streaks)
13. [Monetization: ads, consent, premium](#13-monetization-ads-consent-premium)
14. [Persistence](#14-persistence)
15. [Testing & tooling](#15-testing--tooling)
16. [Key decisions, known gaps, and doc drift](#16-key-decisions-known-gaps-and-doc-drift)

---

## 1. Copy-paste context prompt (current game state)

> **Project.** `chain-pop` is a Flutter + Flame mobile puzzle game shipped as **"Unbound: Arrow
> Puzzle"** (Android id `com.adbkv.chainpop`). It is a minimalist **extraction logic puzzle**: a grid
> holds nodes, each carrying one cardinal arrow. A node can be extracted only when its arrow's ray
> travels to the edge of the bounding grid without crossing another node. Tapping a blocked node
> "jams" it: −1 life (3 lives per attempt) and −8 network integrity. Clearing the board (or, on
> Hard/Expert boards, restoring all 3 **core** nodes, which triggers an auto-cascade of the
> remainder) wins the level. Stars: 3 for 0 jams, 2 for 1–2 jams, 1 otherwise. Every mode is on a
> countdown timer; running out offers a rewarded-ad "continue" on Hard/Daily.
>
> **Levels are procedurally generated at load time and provably solvable by construction.** The
> generator builds boards **backwards** (retrograde): starting from the empty/solved board it places
> nodes one at a time, and only ever chooses a direction whose ray is clear *at placement time*.
> Because removing a node can only free rays (monotonicity), the reversed placement order is a valid
> player solution — deadlock is impossible. The canonical solution is node **ID order 0,1,2,…N-1**.
>
> **Generation pipeline** (`lib/game/levels/generation/`): `LevelConfiguration.fromLevelId` picks
> grid span (clamped 6–8 / 6–9 by mode), archetype and target node count → a **Director** samples a
> generation archetype (cleanAuthored / organicMessy / strongMotif / relaxedFreeFlow / experimental),
> a **silhouette** (8 ids × a pool of concrete mask shapes), scorer weights and pre-reserved
> **motifs** → the **RetrogradeConstructor** fills the silhouette from a **FrontierSet** using a
> softmax **CandidateScorer** (unlock-fanout + MRV − isolation, per-archetype temperature), with a
> bounded rollback stack → a post-placement **direction-reassignment pass** flips crunch-window nodes
> (IDs 35%–65% of the sequence) to point at *lower-ID* nodes, which is the only flip direction that
> preserves ID-order solvability, creating forced-sequence pressure → `_enforceOpeningTarget`
> compresses the opening wave to the tier cap (Hard/Expert **3–5**, Medium 4–8, Easy 5–10) → the
> **evaluator** (`DifficultyProfile.passes`) checks branching factor, first-legal-move count,
> critical unlock depth, forced-sequence ratio, wave depth, an FSR-vs-node-count cap, and (Hard/Expert)
> wave-zero width 3–5 → a **visual composition** gate rejects ugly boards (aspect, occupancy,
> singletons, connected components) → the **DiversityLedger** rejects fingerprints within Hamming
> distance 5 (8 within the same visual family) of the last 20 emissions → `LevelValidator` re-simulates
> ID-order removal (including relay row rotations) → the level ships. Up to K=8 evaluator iterations
> per attempt, ≤3 Director renegotiations per iteration, ≤40 outer attempts, with a **200 ms latency
> budget** in `LevelManager` after which the best already-valid board ships.
>
> **Special node kinds** are stamped after generation by `enrichLevel`: **cores** (3, Hard/Expert,
> highest IDs, spread apart), **locked** nodes (Hard level ≥26; extractable only when all four
> orthogonal neighbours are empty), **relay** nodes (Hard level ≥51; popping rotates every arrow in
> its row 90° CW — the only non-monotone mechanic, so candidates are proved soft-lock-safe by a
> closure argument before being accepted).
>
> **Content framing.** 4 campaign worlds of 25 levels (Gateway / The Lock / Relay Storm / Labyrinth),
> boss levels every 25, 8 hand-authored showcase seeds (30, 35, 40, 45, 50, 55, 75, 100), 3 pinned
> opening seeds (1–3), milestone seeds at `id % 100 == 25` (diamond) and `== 75` (ring), plus
> procedural milestones at `== 50` (max density) and `== 0` (sparse sniper). A **Daily Challenge**
> generates one deterministic board per local calendar date, framed as a "NETWORK INCIDENT", evaluated
> against the Expert tier band. An 8-step hand-authored tutorial teaches pops → ordering → waves →
> bigger boards → cores → relay → locked.
>
> **App shell.** Splash → MainMenu (difficulty segmented control, progression card, Daily card) →
> LevelSelect (telescoping 20/100/500 pagination) → GameScreen (Flame `GameWidget` + Flutter HUD,
> win panel, pause overlay, bottom toolbar with hint / axis-guides / zoom / undo / restart).
> Persistence is Hive (`chain_pop_storage` box, schema v2): per-mode unlock frontier, per-level stars,
> daily stars, daily ad-unlocks, settings, tutorial flag, lifetime clears and lifetime gameplay
> seconds. Monetization is behind an `AdService` interface (Google Mobile Ads on device, no-op on
> web/desktop/`MOCK_ADS`), wrapped by a `PremiumAdServiceDecorator` fed by RevenueCat entitlement
> **`Unbound Pro`**; UMP consent runs before SDK init. Rewarded placements: continue-after-lives,
> hint, undo, daily past-day unlock. One interstitial between campaign levels gated by session win
> streak (4/3/2 by mode) **and** lifetime engagement (≥5 clears or ≥600 s) **and** a frustration gate
> (suppressed after 2 failed runs in 3 minutes).
>
> **Known state of the tuning work.** Three generations of strategy documents live in `docs/`
> (`master_gameplay_strategy.md`, `dense_strategy_session_context.md`, `topology_first_session_context.md`).
> The mechanical layer is the live problem: the opening-width cap and the reassignment pass shipped and
> work, but Hard boards historically ship **out of band** (the K-loop deliberately falls back to the
> best novel out-of-band candidate rather than failing), forced-sequence ratio is low, and the
> temporal-arc gate is currently commented out in `DifficultyProfile.passes`. MAP-Elites exists as an
> offline archive tool but ships an **empty bank that is not registered in `pubspec.yaml`** and is never
> loaded at runtime. Several older docs quote grid caps and fill ratios that the code no longer uses —
> trust the code.
>
> **Test suite:** 87 Dart test files (≈70 unit/widget under `test/`, plus `integration_test/`), heavily
> concentrated on the generation subsystem (solvability, deadlock sweep over 1000 levels, corpus
> benchmarks, property tests, perf budgets) plus ads policy, storage, session systems and screen tests.

---

## 2. System map

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ App shell (lib/main.dart)                                                    │
│   Firebase (Core/Crashlytics/Analytics) → Hive → StorageService.init()       │
│   → RevenueCat (SubscriptionLocator) → UMP consent → MobileAds.initialize()  │
│   → AdService (AdsLocator) → runApp(ChainPopApp)                             │
│                                                                              │
│   SplashScreen ──► MainMenuScreen ──► LevelSelectScreen ──► GameScreen        │
│                          └────────► DailyChallengeCalendarScreen ──► GameScreen
│                          └────────► Tutorial (fixed LevelData) ──► GameScreen │
├──────────────────────────────────────────────────────────────────────────────┤
│ Content pipeline (lib/game/levels/)                                          │
│   LevelManager.getLevel(id, mode)   LevelManager.getDailyChallenge(date)     │
│        │                                    │                                │
│        └──────────► LevelGenerator.generate / generateDailyChallenge ◄───────┘
│                         │                                                    │
│   LevelConfiguration ──► Director ──► RetrogradeConstructor ──► enrichLevel   │
│         (grid, nodes)     (plan)       (+ CandidateScorer,        (cores,     │
│                                          FrontierSet,             locked,     │
│                                          SightlineTable,          relay)      │
│                                          Motifs)                             │
│                         ▼                                                    │
│   LevelMetrics ─► DifficultyProfile ─► visual composition ─► DiversityLedger  │
│                                                       └─► LevelValidator ──► LevelData
├──────────────────────────────────────────────────────────────────────────────┤
│ Runtime (lib/game/)                                                          │
│   ChainPopGame (FlameGame): board layout, zoom/pan, extraction, undo,        │
│     integrity, cores, cascade finale, ambient/restoration layers             │
│     ├─ NodeComponent      ├─ BoardMaskComponent   ├─ RayPreviewComponent      │
│     ├─ AmbientBackground  ├─ RestoredNetwork      ├─ RelaySweep / Combo /     │
│     └─ ArrowAxisGuide     └─ ExtractionBurst          restored trails         │
│   LevelSolver: canRemove / traceRay / waves / hints                          │
├──────────────────────────────────────────────────────────────────────────────┤
│ Services (lib/services/)                                                     │
│   storage/ (Hive)  ads/ (AdService + policies)  subscription/ (RevenueCat)   │
│   game_audio  session_pacing  session_goals  session_campaign_streak         │
│   daily_challenge_play_policy  crash_reporting                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

Directory sizes (Dart, `lib/`): generation subsystem ≈ 6.6k lines, runtime engine ≈ 1.3k,
screens ≈ 3.8k, services ≈ 2k.

---

## 3. The core rules (authoritative)

Defined in `lib/game/levels/level_solver.dart` — this is the single source of truth used by the
generator, the validator, the metrics, and the runtime.

### 3.1 Extraction

A node at `(x, y)` facing `dir` is extractable iff, stepping one cell at a time along `dir`, the ray
leaves the **bounding rectangle** (`gridWidth × gridHeight`) without entering a cell occupied by
another active node.

Two consequences that are easy to get wrong and are asserted throughout the codebase:

* **`playCells` voids do not stop a ray.** An irregular silhouette only restricts *where nodes may
  sit*; rays cross voids freely. `LevelSolver` walks the full rectangle.
* **Removing a node can never block anything.** This "monotonicity of ray obstacles" is what makes
  retrograde construction sound, and what makes `LevelSolver.isSolvable` exact for relay-free boards
  regardless of move order.

### 3.2 Node kinds (`NodeKind`)

| Kind | Extra rule | Where introduced |
|---|---|---|
| `normal` | none | everywhere |
| `locked` | additionally requires **all four in-bounds orthogonal neighbours empty** | Hard campaign, level ≥ 26 (world "The Lock") |
| `relay` | on extraction, **every node in its row rotates 90° clockwise** | Hard campaign, level ≥ 51 (world "Relay Storm") |

`Direction.rotatedCw / rotatedCcw` (in `level.dart`) are shared by gameplay, undo, the validator, and
the soft-lock proof, so rotation semantics can never drift between them.

### 3.3 Win, loss, and scoring

| Rule | Value | Source |
|---|---|---|
| Lives per attempt | 3 | `GameScreenConstants.maxLives` |
| Jam penalty | −1 life, −8 integrity, streak reset | `ChainPopGame.reportJam` |
| Core restored | +5 integrity | `registerExtraction` |
| Win | all nodes cleared **or** all cores restored | `checkWinCondition` |
| Core win with nodes left | cascade finale: remaining nodes auto-pop in a ripple ordered by Manhattan distance from the last core, then `onWin` | `_startCascadeFinale` |
| Integrity on win | snapped to 100 | `checkWinCondition` |
| Stars | 0 jams → 3, 1–2 jams → 2, else 1 | `DifficultyExt.starsForJams` |
| Repeated jams on one node | after the 2nd jam, the blocking node flashes red | `_flashBlockerFor` |

Integrity is currently **presentational** — it is displayed on Hard/Daily (and from tutorial step 5)
and moved by jams/cores, but no timer or hint penalty is wired to it yet (that was the Week-4 plan in
`master_gameplay_strategy.md`).

### 3.4 Timers

`lib/screens/game/game_time_limit.dart`. Every mode counts **down**; pops never add time.

| Mode | Formula | Clamp |
|---|---|---|
| Easy | `(20·N + 90) · max(0.82, 1 − 0.0012·L)` | 120–240 s |
| Medium | `4.0·N·(1 + 0.18·ln N) · max(0.75, 1 − 0.008·L)` | 45–180 s |
| Hard | `2.8·N·(1 + 0.12·ln N) · max(0.60, 1 − 0.004·L)` | 25–150 s |
| Daily | Medium formula at a fixed virtual level index of 40 | 45–180 s |
| Tutorial | 60 s (step 4: 45 s) | — |

A **surge** level (every 4th consecutive campaign win in a session) multiplies the limit by 0.7 with
a 20 s floor and shows a `⚡ SURGE` label.

---

## 4. Data model

```dart
enum Direction { up, down, left, right }
enum NodeKind  { normal, locked, relay }

class NodeData {                     // immutable; x/y never change after placement
  final int id;                      // ID order == canonical solution order
  final int x, y;
  final Direction dir;
  final Color color;                 // resolved from AppColors.nodePalette
  final int colorSlot;               // palette index; enables colorblind remap
  final NodeKind kind;
  final bool isCore;
}

class LevelData {
  final int levelId;                 // campaign level, tutorial index, or dayKey
  final int gridWidth, gridHeight;   // bounding rectangle — rays use this
  final Set<String>? playCells;      // "x,y" silhouette; null == full rectangle
  final List<NodeData> nodes;
  static String? layoutValidationMessage(LevelData);  // bounds/dupes/mask check
}
```

Node colours are **depth tints**, not gameplay signals: after construction the generator computes
`LevelSolver.nodeWaveIndices` and assigns palette slots by relative wave depth (early waves warm,
mid green/cyan, late blue/purple). `colorSlot` is preserved so `ChainPopGame.effectiveNodeColor`
can swap in the Okabe–Ito colourblind palette at render time without regenerating the level.

Hot-path occupancy uses a packed int key: `gridCellKey(x, y) = (x & 0xffff) | (y & 0xffff) << 16`.

---

## 5. Level generation — end to end

### 5.1 Entry points

```dart
LevelManager.getLevel(levelId, mode: …)     // campaign; 200 ms time budget
LevelManager.getDailyChallenge(date)        // dayKey = YYYYMMDD, Expert tier
LevelGenerator.generateFromConfiguration(…) // tests, tools, explicit configs
```

`LevelManager` is the safety wrapper: on any failure it asserts in debug and returns a
**one-node emergency fallback** (4×4 grid, single up-facing node) so no crash reaches the player.

### 5.2 The outer loop (`generateFromConfiguration`)

1. Validate the config (3×3 ≤ grid ≤ 20×20, 3 ≤ nodes ≤ min(area, 400)).
2. **Seed path** (`applyMilestones` on): if a pinned `LevelSeed` exists for this id
   (`seedRegistry` opening seeds 1–3, `showcaseSeedFor`, `milestoneSeedFor`), build the plan from the
   seed instead of sampling. Opening seeds are skipped for Hard/Expert configs.
3. **Milestone path**: `id % 100 == 50` → max density, `id % 100 == 0` → sparse sniper (Medium/Hard,
   id ≥ 25 only). `== 25` / `== 75` are handled by seeds (diamond / ring).
4. **Normal path**: up to `maxAttempts = 40` attempts. Each attempt seeds
   `Random(primarySeed·31337 + attempt·999983)`, progressively **downscales the node target** (−15%
   every 2 attempts, floored at `difficulty.minNodes` / `minimumTargetNodeCount`), and in the last 10
   attempts forces the `cleanAuthored` archetype. The archetype is otherwise **locked once per
   generate() call** to avoid selection bias across retries.
5. Each successful attempt is enriched (`enrichLevel`), re-validated (`LevelValidator`), and then
   checked against the **removal-wave band** (`removalWaveBounds`); the band widens at the halfway
   point (±1/+4) and again in the last 4 attempts (−2/+10). Out-of-band-but-valid boards are retained
   as `budgetFallback`.
6. **Latency budget** (200 ms from `LevelManager`): once exceeded, the loop jumps to the most-relaxed
   regime and ships the first fully valid board, bypassing only the wave-band *preference* —
   solvability and layout invariants are never relaxed. Without a budget (tests) behaviour is
   byte-identical to the unbudgeted path.
7. Exhaustion returns a typed `GenerationError` — Phase 3 deliberately removed the old
   "always emit a monotone strip" fallback; `monotoneFallbackHitCount` remains as a regression sensor
   and should stay 0.

### 5.3 The K-loop (`_attemptDirectorDrivenGeneration`)

K = 8 evaluator iterations. Per iteration:

```
Director.choosePlan (or choosePlanFromSeed)
  → up to maxRenegotiations = 3 renegotiate() cycles on construction failure
      (−10% nodes; on odd depths also swap silhouette within the archetype family;
       greedy-path failures use renegotiateAfterGreedyFailure: −2..−3 nodes first)
  → RetrogradeConstructor.construct()  (or the legacy greedy path for Experimental)
  → LevelMetrics.compute
  → DifficultyProfile.passesFsrCap        (hard reject)
  → evaluateVisualComposition             (hard reject, counted by reason)
  → profile.passes(metrics)               → in-band or not
  → computeLevelFingerprint → DiversityLedger.isNovel   (reject → keep as non-novel fallback)
  → collect as in-band candidate / novel-out-of-band / non-novel fallback
```

Selection order after the loop:

1. **In-band candidates**, ranked by `_compareInBandCandidates`:
   silhouette streak score (session tracker) → *(Hard/Expert)* **lower wave-zero width** →
   temporal-arc score → critical unlock depth → midgame FSR → spatial density.
   For Hard/Expert the top 5 are re-scored with `viablePathCount`; the first with **2–8 uncapped
   viable paths** wins (a proxy for "has real choices but is not a free-for-all").
2. Else the best **novel out-of-band** candidate (logged as an out-of-band success).
3. Else the **non-novel fallback**, which is still recorded in the ledger.
4. Else a typed error.

Telemetry for every emission is **staged, not committed**, inside the K-loop
(`_PendingDirectorEmission`) and only flushed by the outer loop when the level actually ships — so
archetype/motif/seed counters and analytics events stay exactly aligned with shipped levels.

### 5.4 The Director (`director.dart`)

Produces an immutable `GenerationPlan`: archetype + spec, silhouette id + mask, target node count,
tier, profile, legacy-greedy flag, motif placements.

**Archetype distribution** (`GenerationArchetypeSpec.distributionForDifficulty`):

| Archetype | Easy | Medium | Hard/Expert | Temp | Weights (fanout / MRV / isolation) |
|---|---|---|---|---|---|
| cleanAuthored | 30% | 25% | 22% | 0.55 | 1.4 / 0.8 / 1.6 |
| organicMessy | 22% | 35% | 30% | 1.6 | 0.9 / 0.4 / 0.9 |
| strongMotif | 12% | 20% | **40%** | 0.9 | 1.1 / 0.6 / 1.3 (motif budget 2) |
| relaxedFreeFlow | 31% | 15% | **0%** | 1.2 | 1.0 / 0.3 / 0.7 |
| experimental | 5% | 5% | 8% | 2.0 | −0.4 / 0.2 / 0.2 (50% legacy greedy) |

Hard/Expert overrides applied on top (`_applyDensityOverrides`): isolation penalty clamped to ≤0.5
and temperature clamped to ≤1.0, because high isolation/temperature were the measured cause of
sparse, scattered Hard boards.

**Silhouette choice:** sampled from the archetype's preferred pool, with a 40% bias toward the
"dense" set (ring / cross / diamond / rectangle) on Hard/Expert. `_refinePlanMaskDensity` then swaps
to a tighter dense silhouette if the mask area exceeds 1.15× the node target.

**Target node count** (`_pickTargetNodeCount`):
* Hard/Expert: `mask.length × uniform(0.28, 0.40)`, clamped into the tier band. In practice the band
  floor (25) dominates on the 49–64-cell masks Hard uses, so Hard ships ≈25 nodes — the source
  comments flag this as deliberate and load-bearing (raising it trips the FSR-vs-nodeCount cap, seed
  byte-stability, and the perf budget).
* Easy/Medium: uniform inside the tier band.

**Motif reservation** (`_reserveMotifs`): reservation cells are capped at 40% of the node target.
Hard/Expert try a `cascadeHub` first **45% of the time** (deliberately de-escalated from the old
always-first behaviour, which caused plus-shape monotony), then draw from `sampleMotifForTier`
(Hard/Expert weights: 40% cascadeHub, 30% lockCluster, 15% diamondIntersection, else escapeChord).

**Motif catalogue** (`motifs.dart`): `lockCluster` (5–7 centre-biased crunch cells), `escapeChord`,
`diamondIntersection`, `clusterKey`, `staircase`, `cascadeHub` (5-node inward cross used as a
"gravity well" for cascades). `threeSpokeWheel` is reserved in the enum but not implemented.
Motif placement is **atomic** — either the whole block fits or none of it does.

### 5.5 The Retrograde Constructor (`retrograde_constructor.dart`)

**Phase A — coordinate placement (clear rays only).** Up to 8 attempts of:

* Enumerate candidates over the `FrontierSet` (empty silhouette cells adjacent to a placement or on
  the silhouette boundary) — O(frontier), not O(empty cells).
* For each frontier cell, classify each direction as clear (via the precomputed `SightlineTable`) or
  blocking. `_directionPoolForZone` returns clear directions when any exist; blocking only as a last
  resort. Deliberate blocking is **not** done here — see Phase B.
* `CandidateScorer.pick` samples via softmax over
  `w_fanout·unlockFanout + w_mrv·(4 − clearDirs) − w_isolation·isolationPenalty`, with occupancy-phase
  weight modulation and a crunch-window (occupancy 0.35–0.65) blocking bonus / opening penalty.
* Dead ends trigger the **rollback stack**: pop 3 placements, blacklist the offending cell, retry;
  give up after 5 consecutive or 20 total rollbacks.
* With motifs present, `_constructDeferredMotifs` runs instead: bulk cells fill first while motif
  cells are treated as ray obstacles, then motifs inject once occupancy passes their threshold —
  **40% for lock clusters, 55% for everything else**. A motif that cannot be placed degrades
  gracefully (the transaction is rolled back to the bulk prefix and abandoned).
* The forward placement list is reversed into **removal order** and validated by
  `_validatesRemovalOrderIdSequence`.

**Phase B — post-placement direction reassignment.** This is the architectural centrepiece
documented in `topology_first_session_context.md`. For nodes in the crunch window (IDs 35%–65%):

> Node `i` may be flipped to point at node `j` **only when `j < i`.**
> At removal step `i`, nodes `0..i-1` are already gone, so the ray is clear then — but early in the
> puzzle `j` is still present, so node `i` is blocked. That is forced-sequence pressure that
> *cannot* break ID-order solvability. Pointing at a higher-ID node would deadlock the validator.

Flip probability ladder: **0.72 → 0.45 → 0.25**, retrying until the sequence re-validates; the
winning rung is recorded as `winningBlockingRetryIndex`. Target selection is scored by
`chainDepth·2 + blockerFanIn·1.5 + isBlocked·2 + spatialProximity·0.5 + 1/(i−j)`, with a hub-fan-in
cap (3, or 5 for the cascade-hub liberation node) to avoid one node becoming everyone's blocker.
Motif reservation cells are never flipped.

**Phase C — opening compression** (`_enforceOpeningTarget`): while the wave-zero width exceeds the
tier cap, flip ray-free nodes (highest ID first) to point at lower-ID nodes, re-validating each flip.
20 passes max, and it stops if the opening would fall below the tier minimum.

| Tier | min opening | max opening |
|---|---|---|
| easy | 5 | 10 |
| medium | 4 | 8 |
| hard | 3 | **5** |
| expert | 3 | **5** |

### 5.6 Legacy greedy path

Only the Experimental archetype (50% of its rolls) uses it, to preserve "happy accidents": pick N
random positions inside the silhouette → `tryGreedyEliminationOrder` (randomized greedy forward
simulation, 96 trials, honestly returns `null` on exhaustion rather than faking an order) → assign
each node a direction avoiding all *future* nodes, with a `DirectionBiasType` weighting.

---

## 6. Layout / silhouette generation

Two layers cooperate:

**`SilhouetteId`** (8 values, 3 fingerprint bits): `rectangle, ring, archipelago, corridor,
organicBlob, asymmetric, diamond, cross`.

**`silhouetteShapePool`** maps each id to a pool of concrete `LayoutMaskKind` renderings, which is
what breaks the "plus / square / L on repeat" feel:

| Silhouette | Concrete shapes |
|---|---|
| rectangle | full board (`playCells == null`) |
| ring | donut, cShape, hollowDiamond |
| archipelago | bespoke 3-cluster builder, scatteredHoles |
| corridor | bespoke band, zigzag, spiral |
| organicBlob | randomBlob |
| asymmetric | lShape, vShape, pentagon, zigzag |
| diamond | diamond, hollowDiamond |
| cross | cross, xShape |

`buildSilhouetteMask` draws the concrete kind from the pool using the main RNG on the procedural
path, and additionally seeds a **level-isolated jitter RNG** (`levelId·1000003 + id·131 + kind·17`)
that perturbs intra-shape parameters (diamond radius, cross arm thickness, donut hole) *without*
consuming from the main stream — so node placement, metrics and seed byte-stability are unaffected
while outlines still vary per level. Hand-authored seeds pass `varied: false`, taking the canonical
first pool entry and drawing no extra entropy at all.

If a mask comes back smaller than `difficulty.minNodes`, the Director falls back to the **full
rectangle** (and fires the optional `onMaskRectangleFallback` hook used by tooling).

`silhouetteToPlayCells` converts the packed mask back to `Set<String>?`, returning `null` when the
mask is the whole rectangle so the legacy "no mask" path stays intact.

**`SilhouetteVisualFamily`** groups ids for diversity purposes: rectangle/diamond/cross/ring are all
`geometricLattice`; organicBlob/asymmetric are `organic`; archipelago and corridor stand alone. The
`SilhouetteSessionTracker` keeps the last 5 emitted families and applies a
`−2.5 × consecutiveGeometric` penalty (from a streak of 2) plus a `+1.5` boost to non-geometric
candidates during K-loop ranking — the direct fix for "every Hard board is another cross blob".

**Grid dimensions** (`level_configuration.dart`): the span is derived from an estimated node count
(`_packedGridSpan`: ≤20 → 6, ≤25 → 7, else 8; Easy 6 or 7), adjusted per `LevelArchetype`
(claustrophobic −1, openField/sniper +2, corridor 1.35×/0.70× on alternating axes, fortress ≥5),
then **hard-clamped on both axes**: Easy 6–8, Medium 6–9, Hard 6–8. Daily additionally caps each
span at 8. Node count is a log-growth base modulated by an archetype density multiplier
(claustrophobic 1.35 … sniper 0.45) and a 3-term sinusoid in `levelId` for wave-like variation.

**Daily config** (`forDailyChallenge`): derives structural parameters from **Hard** (not Medium) —
the UI label and timer stay Medium on purpose — enforces `kDailyChallengeMinFillRatio = 0.55`, and
biases hard toward irregular masks (95% probability, 10 extra tries).

---

## 7. Metrics, evaluator bands and diversity

### 7.1 `LevelMetrics` (`metrics.dart`)

| Metric | Definition |
|---|---|
| `nodeCount` | board size |
| `waveDepth` | `LevelSolver.countRemovalWaves` — parallel "remove everything free" rounds |
| `tempoProfile` | legal-move count at each step of the canonical ID-order solve |
| `averageBranchingFactor` | mean of `tempoProfile` |
| `firstLegalMoveCount` | `tempoProfile.first` |
| `wavePeelingProfile` | width of each parallel removal wave |
| `waveZeroWidth` | `wavePeelingProfile.first` — **the turn-one choice count**, the primary Hard gate |
| `forcedSequenceRatio` (tFSR) | weighted score over the wave profile: width 1–3 → 1.0, 4 → 0.8, ≤6 → 0.5, ≤8 → 0.2, else 0.1, averaged |
| `criticalUnlockDepth` | longest prerequisite chain in the ray-dependency graph (single in-order DP sweep — valid because ID order is a topological order) |
| `frontierVariance` | stddev of the tempo profile |
| `viablePathCount` | opt-in bounded DFS over the move tree (branch cap 512, expansion cap 6000) |

`LevelTopologyMetrics` adds `chainDepthMax`, `maxHubInDegree`, `avgUnlockFanout` for analytics.

### 7.2 `DifficultyProfile` bands

`DifficultyTier` is separate from `DifficultyMode` specifically so Daily/Specials can target
**Expert** while the underlying config and UI stay on another mode.

| Tier | nodes | waveDepth | avg BF | first legal | CUD | FSR | tempo shape |
|---|---|---|---|---|---|---|---|
| easy | 8–14 | 2–4 | 5.0–8.0 | 7–11 | 2–5 | 0.25–0.65 | relaxed |
| medium | 14–22 | 3–5 | 3.0–8.0 | 4–11 | 3–8 | 0.35–0.65 | mildRise |
| hard | 25–50 | 5–8 | 3.0–8.0 | **3–5** | 5–12 | 0.45–0.90 | dramatic (arc spec) |
| expert | 28–55 | 6–10 | 3.0–9.0 | **3–5** | 6–14 | 0.50–0.85 | compression |

Universal cap: `nodeCount > 28 ⇒ FSR ≤ 0.40`. Hard/Expert additionally require
`3 ≤ waveZeroWidth ≤ 5`. **Node count is not itself gated** by `passes()` (the Director owns it), and
the temporal-arc gate is currently **commented out** pending playtest calibration —
`passesTemporalArc` / `temporalArcScore` still run for *ranking*.

### 7.3 Visual composition gate (`visual_composition.dart`)

Skipped for Easy. Rejects with a typed reason (each counted separately in telemetry):

* **aspect** — node bbox aspect outside 0.55–1.75 (skipped when the mask itself is elongated)
* **blobVsGrid** — node bbox covers < 50% of the grid area (skipped for small-bbox masks)
* **occupancy** — nodes / bbox area < 0.35 (0.22 for boards under 15 nodes)
* **singleton** — more isolated nodes than `max(2, maskComponents)`
* **components** — more 4-connected node clusters than `max(2, maskComponents)`

Allowances scale with the mask's own connected-component count, so archipelago silhouettes are not
punished for being archipelagos.

### 7.4 Diversity ledger (`diversity_ledger.dart`)

A 26-bit packed fingerprint:

| Bits | Field |
|---|---|
| 0–2 | silhouette id |
| 3–4 | wave-depth bucket (≤2 / ≤4 / ≤6 / 7+) |
| 5–6 | avg-BF bucket (<2 / <3.5 / <5 / ≥5) |
| 7–9 | dominant motif id |
| 10–13 | direction histogram (bit set when a direction exceeds 30% of nodes) |
| 14–22 | 3×3 spatial density (bit set when a third-cell is >50% occupied, relative to mask capacity) |
| 23–25 | silhouette **visual family** |

Novelty = Hamming distance ≥ 5 against every entry in the last-20 window, raised to **8** when the
candidate shares a visual family with the window entry (optionally only for the newest N entries via
`recentStrictMarginCount`). A 100-entry historical tail plus `serialize`/`restore` exist for
cross-session persistence, which is **not yet wired to storage**.

---

## 8. Enrichment: cores, locked nodes, relays

`level_enrichment.dart` runs after construction, before final validation.

**Cores** (Hard/Expert, ≥6 nodes): pick 3 nodes from the **highest IDs down** (i.e. the nodes removed
last / hardest to reach), skipping any within Manhattan distance 2 of an already-picked core.

**Locked** (Hard mode, level ≥ 26; 1 node, or 2 from level 45): only cells with all four neighbours
in-bounds, not a core, and with **no neighbouring node of equal-or-higher ID** — that guarantees the
canonical ID-order solution still works, since all four neighbours are gone by the time the locked
node's turn arrives.

**Relay** (Hard mode, level ≥ 51; at most 1): the only mechanic that can strand a board, so
acceptance is proved, not assumed. `_relayIsSoftlockSafe` computes the closure `must` of nodes that
*must* already be gone for the relay to be poppable (occupants of its ray, transitively their rays,
plus locked-node neighbours), then checks that the board `allNodes \ must`, with the relay removed
and its row rotated, is still solvable. By monotonicity that is the **worst reachable** poppable
state, so one `isSolvable` call proves safety for every possible pop timing — O(n) instead of an
exhaustive playout. Candidates are additionally re-run through `LevelValidator`; if none survive, the
level ships without a relay.

---

## 9. Runtime engine (Flame)

`ChainPopGame extends FlameGame with ScaleDetector, ScrollDetector` (`chain_pop_game.dart`).

**Level source.** `GameScreen` generates the level once and passes it as `preloadedLevel` — the
engine never double-generates. `levelData` is seeded eagerly in the constructor because the Flutter
HUD reads `usesCoreWin` / `totalCores` before `onLoad`.

**Extractable set.** `_rebuildExtractableIds` runs after every extraction/undo: one occupancy set,
one ray walk per node — O(n × span) — so each `NodeComponent` can query `isExtractable(id)` in O(1)
per frame. The **delta** (`_newlyExtractable`) drives `telegraphFreed()`, a one-shot ring pulse on
nodes that just became free, making cause→effect legible.

**Extraction path.** `NodeComponent` tap → `canExtract` → pop animation + `registerExtraction`
(streak++, integrity/core bookkeeping, relay row rotation, undo stack push, extractable rebuild,
neighbour nudges, combo text at streak ≥3, restoration-trail cell, burst, ambient ripple, win check)
or `reportJam` (streak reset, −8 integrity, blocker flash after the 2nd jam on the same node).

**Undo** is LIFO over `_undoStack`; relay undo rotates the row counter-clockwise, which is exact
because LIFO guarantees the row holds precisely the nodes present when the relay popped.

**Cascade finale.** On a core win with nodes remaining, the rest are scheduled to auto-pop in a
ripple (0.05–0.09 s steps, ordered by distance from the last core), with a rising pop pitch, and
`onWin` fires ~0.5 s after the last pop. `GameTimerController` explicitly refuses to expire a level
whose engine has already won, so the finale can't be killed by the countdown.

**Camera.** Zoom 1.0–2.75 via pinch (`ScaleUpdateDetails.scale` is cumulative — the code captures a
`_pinchBaseZoom` rather than multiplying per frame) or scroll; pan is clamped to the zoomed grid plus
32 px; both animate back to base with exponential smoothing. Layout is skipped for game-size deltas
under 1.5 px to prevent flicker, and mid-animation (popping/jamming) nodes are **re-parented** across
a relayout instead of being dropped.

**Presentation components:** `AmbientBackgroundComponent` (world gradient, motes, streak reactive),
`BoardMaskComponent` (silhouette tiles), `RestoredNetworkComponent` (trail of vacated cells, reseeded
from `_restoredCells` across relayouts), `ArrowAxisGuideComponent` (row/column guides, HUD toggle),
`RayPreviewComponent` (dotted exit ray on touch-down/long-press), `ExtractionBurstComponent`,
`ComboTextComponent`, `RelaySweepComponent`, plus per-node ghost trails, blocker flash, kind badges
(gold core ring, green relay ring, padlock) and hint pulse in `NodeComponent`.

**Dev autoplay:** `autoSolveStep()` extracts a solver-recommended node; driven by
`--dart-define=AUTOPLAY` and `lib/dev/autoplay_harness.dart`.

---

## 10. Board layout math (screen fitting)

`lib/game/board_layout.dart` is pure, testable geometry (`test/game/board_layout_test.dart`).

* `OccupiedBounds.fromLevel(level, pad: 1)` — bounding box of actual nodes plus 1 cell of padding,
  clamped to the grid.
* `fitCellSize` — largest cell that fits the band, capped at 96 px; a `minPreferredCell` (26 px) is
  applied **only if the whole grid still fits at that size**, so it can never force overflow (the bug
  a naive `.clamp(min, max)` would introduce).
* `fitCellSizeForBounds` — zooms into the occupied bbox to hit a `targetFill` (0.80 in the engine).
* `fitCellSizeForBoundsCappedToGrid` — the one the engine actually uses: the bbox zoom capped so
  `cell × gridWidth ≤ bandW` and `cell × gridHeight ≤ bandH`. Without the cap, a sparse board (e.g.
  the tutorial's single node in a 4×4) inflates until the grid spills off-screen.
* The engine biases the view toward the occupied region but clamps that offset to the slack
  `(band − grid) / 2`, so every grid edge stays on screen at base zoom.

The vertical band is defined by `topReserved` / `bottomReserved`, which are **measured from the real
Flutter HUD** each frame by `GamePlayfieldInsetController` (`RenderBox` of the header/footer keys,
clamped to 96 px–55% and 64 px–50% of screen height) and pushed into the engine via
`configurePlayfieldInsets` (which no-ops below a 1 px epsilon).

---

## 11. Flutter UI layer & screen flows

| Screen | Role |
|---|---|
| `SplashScreen` | Animated "escaping arrow" logo + floating dust, then pushes `MainMenuScreen` |
| `MainMenuScreen` | Material 3 hub: segmented difficulty, progression card (frontier level + star mastery), Daily Challenge card, tutorial entry |
| `LevelSelectScreen` | Telescoping pagination: individual 20-level pages ≤100, 100-groups 100–500, 500-groups with drill-down beyond; auto-opens the chapter containing the frontier level, floating "Jump to Lvl N", per-mode unlock glow |
| `DailyChallengeCalendarScreen` | Current local month grid; today free, future locked, past days rewarded-unlock; banner ad slot |
| `GameScreen` | The game: Flame widget + HUD + toolbar + overlays |

### 11.1 `GameScreen` composition

`GameScreen` is one `State` split across four `part` files so each concern is testable in isolation:

| Part | Responsibility |
|---|---|
| `game_playfield_sync.dart` | HUD measurement → engine insets, tutorial hint Y |
| `game_timer_controller.dart` | countdown tick, ghost-hint timer, easy-mode HUD tick |
| `game_ad_coordination.dart` | preloads, hint/undo rewarded flows, game-over & time-up dialogs, rewarded continue |
| `game_flow_controller.dart` | win handling, stars/unlock persistence, quick-win vs full panel, auto-advance, navigation |

Widgets: `GameHeaderHud` (back, world/incident label, mission line, lives, cores/integrity,
`PhaseProgressBar`, timer, pause), `GameBottomToolbar` (hint with Ad badge, axis guides, zoom,
reset view, undo, restart), `GamePauseOverlay` (with a banner ad slot), `WinPanel`,
`WinCelebrationOverlay` (confetti), `QuickWinBanner`, `SessionGoalChip`, `GameSettingsSheet`,
`GameDialogs`, `LivesDisplay`, `TimerPauseChip`, `PrivacyRightsSheet`.

### 11.2 Win flow

```
engine win → GameFlowController.handleWin()
  flush lifetime gameplay seconds → stop stopwatch → win SFX
  stars = starsForJams(3 − livesRemaining)
  tutorial  → set tutorialCompleted on the last step
  daily     → saveDailyStars(dayKey, stars); no auto-advance
  campaign  → streak++ / pacing++ / session goal, incrementLifetimeCampaignClears,
              saveStars, unlockLevel(level + 1)
  quick win? (cleared < 20 s, not boss/showcase/tutorial/daily, no interstitial due)
      yes → QuickWinBanner 1.5 s → next level
      no  → WinPanel + confetti, 0.7 s delay then a 5 s auto-advance countdown
next level → CampaignBetweenLevelsAds.maybePresentForCampaignTransition → pushReplacement
```

The win overlay lives **inside the screen's own `Stack`**, not as a modal route — a deliberate
decision that removes every Navigator-pop race that the old overlay route suffered from.
`_goingNext` guards against double-advance from the timer plus a tap.

### 11.3 Tutorial

8 hand-authored `LevelData` boards (`tutorial_levels.dart`, `tutorialStepCount = 8`): single pop →
ordered pair → parallel wave → 5×5 mixed → 6×6 recap → **cores** → **relay** → **locked**. Each step
carries bespoke hint copy in `_tutorialHintText()`; steps 0–1 pulse the only legal node after 2 s
(instead of the usual 4 s ghost hint) and keep re-pulsing until the player acts. Integrity appears in
the HUD from step 5 so its reaction to jams and cores is visible while it is being explained.

---

## 12. Session systems: pacing, goals, streaks

Three isolate-static counters, each with an injectable façade so tests never depend on the static:

| System | Rule |
|---|---|
| `SessionPacing` | every 4th consecutive campaign win makes the **next** level a timed surge (0.7× countdown, 20 s floor) |
| `SessionGoals` | one rotating session goal — Win 3 levels / Reach a ×6 combo / Clear a SURGE — shown as `SessionGoalChip`, with a one-shot completion toast |
| `SessionCampaignStreak` | campaign wins toward the between-level interstitial; threshold 4 (easy) / 3 (medium) / 2 (hard) |

Gameplay cadence (pacing/goals) and ad cadence (streak) are kept in **separate** classes on purpose,
so tuning one can never silently change the other. All three reset when the player returns to the
main menu.

---

## 13. Monetization: ads, consent, premium

**Boot order** (`main.dart` → `_bootstrapThirdPartySdks`): RevenueCat init → if not premium and not
`MOCK_ADS` and on Android/iOS: UMP consent → test-device `RequestConfiguration` →
`MobileAds.instance.initialize()` → `createDefaultAdService()` → `AdsLocator.install` →
`ads.bootstrap()` (preloads only). Premium users skip Mobile Ads initialisation entirely.

**`AdService`** is the seam: `GoogleMobileAdService` on device, `NoOpAdService` on web/desktop/mock
and in tests, `RecordingAdService` for assertions, all wrapped by `PremiumAdServiceDecorator` — for
premium users rewarded ads report "ready" and "earned" instantly (features stay unblocked), and
interstitials/banners are bypassed.

**Placements** (`AdPlacements`): `continue_after_lives`, `undo`, `hint`, `between_levels_streak`,
`daily_unlock_past`, `daily_challenge_calendar_banner`, `game_pause_banner`.

**Policies:**

* `UndoAdPolicy` / `HintAdPolicy` — 2 free per attempt, then rewarded with a 90 s cooldown. On Hard
  and Daily the hint free budget is **0** (rewarded-first), and the toolbar shows an "Ad" badge; a
  one-time coach dialog explains this the first time.
* `CampaignBetweenLevelsAds` — requires session streak ≥ threshold **and** lifetime engagement
  (`≥5 clears` or `≥600 s` gameplay) **and** no frustration suppression; the streak resets only after
  an ad is actually presented.
* `CampaignInterstitialFrustrationGate` — 3-minute sliding window; ≥2 failed runs suppresses
  interstitials, a win clears it.
* `DailyChallengePlayPolicy` — today is free; earlier days in the month need a one-time rewarded
  unlock persisted per `dayKey`; future days are locked.

**Premium** (`subscription/`): RevenueCat `purchases_flutter`, entitlement id **`Unbound Pro`**, keys
supplied via `--dart-define=REVENUECAT_GOOGLE_API_KEY / REVENUECAT_APPLE_API_KEY`.
`NoOpSubscriptionService` is used on web.

---

## 14. Persistence

Hive box `chain_pop_storage`, schema version **2**, all device-local and unencrypted.
Layering: `ChainPopPersistence` (contract) → `HiveChainPopPersistence` (impl) → `ChainPopStorage`
(app-facing interface) → `StorageLocator` (install/uninstall) → `StorageService` (static facade) and
`ChainPopProgressStore` (progress-only, injectable into `GameScreen` for deterministic tests).

| Key prefix | Contents |
|---|---|
| `selected_difficulty` | last chosen mode |
| `unlocked_<mode>` | highest playable level index on that track (per-mode frontier) |
| `stars_<mode>_<level>` | best stars |
| `daily_stars_<dayKey>` | daily stars |
| `daily_ad_unlock_<dayKey>` | rewarded unlock flag |
| `tutorial_completed` | onboarding flag |
| `lifetime_campaign_clears`, `lifetime_gameplay_seconds` | ad engagement gates |
| `settings_sound / haptics / colorblind / aim_ray / ambient_motion` | `GameSettings` |
| `hint_reward_coach_seen` | one-time coach dialog |

Lifetime gameplay seconds are flushed as **deltas** on pause, app background, win, retry and dispose,
so an OS kill loses at most a small window rather than a whole level.

---

## 15. Testing & tooling

87 Dart test files. Highlights:

| Area | Files |
|---|---|
| Solvability & regression | `deadlock_test.dart` (1000-level sweep), `regression_test.dart`, `solver_compatibility_test.dart`, `relay_softlock_test.dart`, `relaysafe_soundness_test.dart` |
| Generation subsystem | ~40 files under `test/game/levels/generation/` — director, retrograde constructor, scorer, motifs, silhouettes, layout masks, metrics, diversity ledger, MAP-Elites, corpus benchmark, property tests, **performance budget**, generation budget, board-variety inspection, `dense_strategy_snapshot_test.dart` (informational metric snapshot) |
| Runtime & layout | `chain_pop_game_test.dart`, `board_layout_test.dart`, `node_component_test.dart`, `board_mask_component_test.dart` |
| Screens | game-screen campaign load, time limit, quick-win transition, phase progress bar, main menu, level select, tutorial UI diagnostic |
| Services | ads locator, between-levels ads, frustration gate, hint/undo policies, daily play policy, storage, session goals/pacing/streak, SFX |
| Integration | `integration_test/chain_pop_smoke_test.dart`, `campaign_interstitial_regression_test.dart` (+ VM-runnable suites under `test/integration/`) |

**Performance budget** (asserted in tests): ≤50 nodes → 100 ms, ≤100 → 500 ms, ≤400 → 2000 ms.

**Tools:** `tool/dense_strategy_snapshot.dart` (standalone metric snapshot with full tempo arrays),
`tools/map_elites_runner.dart` (offline MAP-Elites archive builder →
`assets/level_banks/map_elites_v1.json`), `run_emulator_tests.sh`, `run_visual_emulator.sh`.

> No Flutter/Dart toolchain is installed in this documentation environment, so nothing here was
> re-executed; the test inventory is read from source. `docs/topology_first_session_context.md`
> records the last full-suite run as 263 pass / 1 fail in the corpus/director area.

---

## 16. Key decisions, known gaps, and doc drift

### 16.1 Decisions worth remembering

1. **Retrograde construction over search.** Solvability is a construction invariant, not a solver
   result — no NP-hard search in the hot path.
2. **Strict ID-order as the canonical solution.** Simple, cheap to validate, and it makes CUD a
   single DP sweep — but it is also the documented bottleneck: it suppresses convergence, shared
   gates and midgame locking, which is why FSR stays low. Partial-order validation is the identified
   next architectural step and is explicitly *not* done yet.
3. **Blocking is applied after placement, never during.** Construction-time blocking always collapsed
   to the clear-only retry rung; the `j < i` reassignment pass is the version that survives
   validation.
4. **Ship-something-valid over ship-nothing.** The K-loop prefers in-band, then novel out-of-band,
   then non-novel — and `LevelManager` has a one-node emergency fallback. Players never see a
   generation failure.
5. **Telemetry is staged and committed only on ship**, so counters can't drift from reality.
6. **Ads are behind an interface with a premium decorator**, so gameplay code never imports an ad SDK
   and tests default to no-op.
7. **Win overlay inside the screen's Stack** rather than a route — removes pop races.
8. **Session pacing and ad cadence are deliberately decoupled.**
9. **Relay safety is proved, not sampled** — the monotonicity closure argument in
   `_relayIsSoftlockSafe` is the only reason a non-monotone mechanic is safe to ship.

### 16.2 Open gaps

* **Hard/Expert boards often ship out of band.** `passes()` is strict (opening 3–5, FSR bands, CUD),
  but the K-loop falls back rather than failing, so the effective distribution is looser than the
  table suggests. FSR around 4% vs a 12–30% ambition is the headline unresolved metric.
* **Temporal-arc gating is commented out** in `DifficultyProfile.passes` (still used for ranking).
* **Integrity has no mechanical consequence yet** — the timer/hint penalties described in
  `master_gameplay_strategy.md` §6.3.2 are not implemented.
* **MAP-Elites is inert at runtime**: `assets/level_banks/map_elites_v1.json` contains
  `"entries": []`, the `assets/level_banks/` directory is **not listed in `pubspec.yaml`**, and no
  runtime code calls `LevelBank`. It is offline tooling plus tests only.
* **Diversity ledger persistence is unwired** — `serialize`/`restore` exist, nothing calls them, so
  diversity resets every process launch.
* **Dead code**: `LevelConfiguration._baseGridSize`, `LevelGenerator._runPlannedOnce`,
  `DifficultyProfile._matchesTempoShape`, and the `kHardEffectiveFill*` / `kDailyEffectiveFill*`
  constants are all defined but unreferenced.
* **`useDenseValidationSeeds = false`** — the L30–39 dev seeds are off in shipped builds (correct for
  production; remember to flip it for playtests).
* **`MotifId.threeSpokeWheel`** is enumerated but has no implementation.
* **Launch checklist** (`docs/play_store_launch_pending.md`): real `google-services.json`, RevenueCat
  console setup, AdMob production units confirmation, keystore backup, optional portrait lock
  (`MainActivity` is currently unlocked), hosted privacy policy and Play Console listing.

### 16.3 Where the docs disagree with the code

Trust the code; these are stale:

| Claim in docs | Actual code |
|---|---|
| `README.md` difficulty table (Easy 4×4–6×6, Hard up to 16×16) | grid spans are clamped 6–8 (Easy/Hard) and 6–9 (Medium) |
| `README.md` folder tree lists `win_overlay.dart` | no such file; win UI is `game/widgets/win_panel.dart` + overlays |
| `README.md` "backward-generation: pick N random positions, shuffle" | that is only the legacy greedy path used by the Experimental archetype; the main path is the Director + retrograde constructor |
| `topology_first_session_context.md`: Hard grid caps 8–10, Daily 9–11 | Hard 6–8, Daily span capped at 8 |
| `dense_strategy_session_context.md`: Hard/Expert fill 70–80%, daily min fill 0.80 | fill ratio is 0.28–0.40, `kDailyChallengeMinFillRatio = 0.55` |
| `dense_strategy_session_context.md`: CascadeHub mandatory-first on Hard | now a 45% roll (`_reserveMotifs`) |
| `master_gameplay_strategy.md`: `_maxOpeningByTier` hard 9 / expert 15 | already fixed to 5 / 5 |
| `difficulty_mode.dart` doc comments (medium 45% density, hard 40%) | `DifficultyParameters` uses 0.60 medium / 0.75 hard, nodes 10–45 / 25–100 |
| `layout_generation_strategy.md`: rollback limit 20 | `maxTotalRollbacks = 4 × maxRollbackDepth = 20` — matches, but `maxRollbackDepth` is 5 consecutive |

---

## Quick reference — file index

| Concern | File |
|---|---|
| Core rules / solver | `lib/game/levels/level_solver.dart` |
| Data model | `lib/game/levels/level.dart` |
| Generation entry | `lib/game/levels/level_manager.dart`, `generation/level_generator.dart` |
| Plan sampling | `generation/director.dart`, `generation/archetype.dart` |
| Construction | `generation/retrograde_constructor.dart`, `candidate_scorer.dart`, `frontier_set.dart`, `sightline_table.dart` |
| Shapes | `generation/silhouettes.dart`, `generation/layout_mask.dart` |
| Motifs | `generation/motifs.dart` |
| Quality | `generation/metrics.dart`, `difficulty_profile.dart`, `visual_composition.dart`, `diversity_ledger.dart`, `level_validator.dart` |
| Config | `generation/level_configuration.dart`, `difficulty_parameters.dart` |
| Seeds | `lib/game/levels/seeds/*` |
| Enrichment | `generation/level_enrichment.dart` |
| Runtime | `lib/game/chain_pop_game.dart`, `lib/game/components/*` |
| Screen fitting | `lib/game/board_layout.dart` |
| Worlds / framing | `lib/game/world_registry.dart`, `lib/game/daily_challenge.dart`, `lib/theme/world_theme.dart` |
| Game screen | `lib/screens/game_screen.dart` + `lib/screens/game/*` |
| Services | `lib/services/**` |
| Analytics | `lib/game/levels/analytics/generation_analytics.dart` |
