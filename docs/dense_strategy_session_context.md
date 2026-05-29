# Dense Strategy — Session Context

**Project:** `/Users/bvamsi139/Documents/AI projects/game/hybrid/chain-pop`  
**App:** `chain_pop` (Flutter)  
**Date:** May 2026  
**Goal:** Increase systemic tension (density, forced ordering, lock clusters) for **Hard campaign** and **Daily Challenge** retention — without hurting readability.

---

## 1. Problem statement

Hard levels (e.g. Level 47) felt too easy: sparse boards, many opening moves, low cognitive load. The strategy doc (`~/Downloads/densestrategy.txt`) identified:

- **Density alone ≠ depth** — need interdependence, not clutter
- **Target:** 70% intuition / 30% planning; localized crunch zones; “almost solvable” failures
- **Three pillars:** density, dependency depth (CUD), lock clusters
- **Daily Challenge** is the top retention surface — must ship Hard + Daily together

---

## 2. Canonical workspace

| Item | Path |
|------|------|
| Repo (only) | `Documents/AI projects/game/hybrid/chain-pop` |
| Plan | `.cursor/plans/dense_strategy_implementation.plan.md` |
| Strategy source | User’s `densestrategy.txt` (Downloads) |
| Out of scope | Other `chain-pop` copies under `~/Documents`, `~/Downloads`, worktrees |

---

## 3. Existing pipeline (before this work)

```mermaid
flowchart LR
    Config[LevelConfiguration] --> Director
    Director --> Retrograde[RetrogradeConstructor]
    Retrograde --> Metrics[LevelMetrics]
    Metrics --> Evaluator[DifficultyProfile.passes K=8]
    Evaluator --> Ledger[DiversityLedger]
    Ledger --> Solver[LevelSolver wave gate]
```

**Already in codebase (not new):**

| Capability | Location |
|------------|----------|
| Retrograde construction (solvability) | `retrograde_constructor.dart` |
| `criticalUnlockDepth` (CUD) — dependency depth | `metrics.dart` (ray prerequisite graph) |
| Hard CUD band 4–8 | `difficulty_profile.dart` |
| `LevelSolver` | `level_solver.dart` |
| Motif injection @ 55% occupancy | `retrograde_constructor.dart` |
| `clusterKey` motif (2×2 + key) | `motifs.dart` |

**Root causes of sparse Hard boards:**

- High **isolation penalty** (1.6 Clean Authored, 1.3 Strong Motif)
- **22% Relaxed Free Flow** on Hard
- **Node count** sampled from band (20–30) ignoring silhouette size → ~21% grid fill
- Daily: **Medium structural params** + **Expert evaluator** (split-brain)

---

## 4. Implementation plan (phases)

### Phase 1 — Parameter tuning ✅

- Hard archetype weights: 0% Relaxed Free Flow; Strong Motif 40%; Organic Messy 30%; Clean Authored 22%
- Isolation **0.5** + temperature cap **1.0** for Hard/Expert (`director.dart`)
- 70% dense silhouette bias (ring/cross/diamond/rectangle)
- `_refinePlanMaskDensity` when mask > 1.15× target
- `forDailyChallenge()` uses **Hard** structural params (UI still Medium)
- Dev seeds: `lib/game/levels/seeds/dense_validation_seeds.dart` (levels 30–39, `useDenseValidationSeeds` in `seed_registry.dart`)

### Phase 2 — Lock cluster motif ✅

- `MotifId.lockCluster`, `_LockCluster` (5–7 center-biased cells)
- Mandatory lock cluster for Hard/Expert in `_reserveMotifs`
- Lock inject @ **40%** occupancy; generic motifs @ **55%**
- Telemetry: `lockClusterPlaced`, `dominantMotifId`, `clusterCud` in `generation_analytics.dart`

### Phase 3 — CUD + tempo ✅

- K-loop ranks in-band by CUD → FSR → density
- `tempoShape` gates in `DifficultyProfile.passes()` (dramatic / compression)
- Phase-based scorer bias in `candidate_scorer.dart`
- Optional viable path count 2–8 for Hard/Expert final pick

**Tests:** 250/250 generation tests passing after full build.

---

## 5. Post-implementation metrics (before Downloads merge)

Snapshot: `test/game/levels/generation/dense_strategy_snapshot_test.dart`

| Metric | Target | Actual (L47, pre-merge) |
|--------|--------|-------------------------|
| Grid fill | 70–80% | **21%** |
| Opening moves | 1–3 | **13** |
| FSR | 20–40% | **4%** |
| CUD | ≥ 4 | **4** ✓ |
| Evaluator in-band | pass | **false** (0/10 Hard samples) |

**Verdict:** Phase 1–3 improved generation *bias* but not player-facing tension — node count ignored silhouette size.

---

## 6. Downloads `director.dart` comparison

Compared `~/Downloads/director.dart` vs hybrid `lib/game/levels/generation/director.dart`.

**99% identical.** Only meaningful difference: `_pickTargetNodeCount`.

| | Hybrid (before merge) | Downloads |
|---|----------------------|-----------|
| Hard/Expert nodes | Sample `DifficultyProfile` band (20–30) | **70–80% of `mask.length`** |
| Easy/Medium | Band sample | Band sample |

Downloads comment: old `_refinePlanMaskDensity` couldn’t help when target ≈ 25 and maxArea ≈ 29 on large grids.

---

## 7. Downloads merge (latest change) ✅

### Code

**`director.dart` — `_pickTargetNodeCount`**

```dart
if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
  if (hi <= lo) return hi.clamp(1, mask.length);
  final fillRatio = 0.70 + random.nextDouble() * 0.10;
  final densityTarget = (mask.length * fillRatio).round();
  return densityTarget.clamp(lo, hi);
}
```

**`difficulty_profile.dart` — widened bands**

- Hard: `nodeCount` **25–50** (was 20–30)
- Expert: `nodeCount` **28–55** (was 22–32)

### Measured impact (after merge)

| Metric | Before | After (L47) |
|--------|--------|-------------|
| Nodes | 25 | **50** |
| Grid fill (11×11) | 21% | **41%** |
| CUD | 4 | **5** |
| Opening moves | 13 | 27 |
| FSR | 4% | 2% |
| In-band | false | false |

**Takeaway:** Visual density **~2×** on grid fill; crunch/FSR/opening **not fixed** yet.

---

## 8. Key files touched (cumulative)

| Phase | Files |
|-------|--------|
| 1 | `archetype.dart`, `director.dart`, `level_configuration.dart`, `seed_registry.dart`, `dense_validation_seeds.dart` |
| 2 | `motifs.dart`, `director.dart`, `retrograde_constructor.dart`, `diversity_ledger.dart`, `generation_analytics.dart` |
| 3 | `level_generator.dart`, `difficulty_profile.dart`, `candidate_scorer.dart`, `metrics.dart` |
| Merge | `director.dart` (`_pickTargetNodeCount`), `difficulty_profile.dart` (bands) |

---

## 9. Daily Challenge

- Entry: `LevelManager.getDailyChallenge()` → `LevelGenerator.generateDailyChallenge(dayKey)`
- Same pipeline as campaign; `targetTier: expert`, `maxAttempts: 32`, milestones off
- Structural: Hard params + `kDailyChallengeMinFillRatio = 0.80` + irregular masks
- UI/timer: still `DifficultyMode.medium` — intentional
- Play policy: `lib/services/daily_challenge_play_policy.dart` (unchanged)

---

## 10. What still doesn’t work (honest)

| Gap | Why |
|-----|-----|
| Low FSR (~2%) | Construction/evaluator don’t enforce forced-ordering during build |
| High opening moves (20–30) | More nodes can *increase* early choices |
| 0% in-band Hard | K-loop ships out-of-band fallbacks; FSR/opening/tempo bands rarely met |
| Daily grid still huge | 55 nodes on 18×18 ≈ 17% fill — mask vs full grid mismatch |
| “One more try” loop | Needs FSR + narrow openings, not density alone |

---

## 11. Recommended next steps

1. **Play-test** Hard 30–39 with `useDenseValidationSeeds = true` in `seed_registry.dart`
2. **Cap grid size** for Hard (8×8–10×10) so fill % matches visual pressure
3. **Stricter evaluator** — don’t ship Hard/Daily out-of-band on FSR/opening (or relax bands to achievable targets)
4. **Construction-time FSR** — bias retrograde scorer toward cross-blocking midgame

---

## 12. Commands

```bash
cd "/Users/bvamsi139/Documents/AI projects/game/hybrid/chain-pop"

# Full generation tests
flutter test test/game/levels/generation/

# Gameplay metrics snapshot (prints to console)
flutter test test/game/levels/generation/dense_strategy_snapshot_test.dart

# Corpus Hard histogram
flutter test test/game/levels/generation/corpus_benchmark_test.dart --plain-name "N=100"
```

---

## 13. Success metrics (4-week targets from plan)

| Metric | Baseline (est.) | Target |
|--------|-----------------|--------|
| Hard time-on-level | ~90s | 3–5 min |
| Hard attempt-to-clear | ~1.0× | 2.0–2.5× |
| Daily D1 return | baseline | +5–10% |
| Hint usage (Hard/Daily) | ~0% | 25–35% |
| Generation fallback | — | < 5% |

---

## 14. Chat arc (timeline)

1. User shared dense strategy analysis + asked for implementation plan  
2. Plan created; workspace locked to hybrid `chain-pop`  
3. Full plan built in parallel (Phases 1–3, 265+ tests)  
4. User asked if gameplay actually improved → metrics proved gap (21% fill, 0% in-band)  
5. Compared Downloads `director.dart` → only `_pickTargetNodeCount` differed  
6. User approved merge → 70–80% silhouette fill + widened node bands  
7. Post-merge: ~2× grid fill on L47; FSR/opening still weak  
8. This context document

---

*Generated from agent session. Do not edit the plan file for history — this doc is the session record.*
