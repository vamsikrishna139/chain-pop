# Topology-First Generation — Full Session Context

**Project:** `chain-pop` (Flutter)  
**Repo:** `/Users/bvamsi139/Documents/AI projects/game/hybrid/chain-pop`  
**Date:** May 2026  
**Goal:** Achieve FLOW → CRUNCH → RELEASE through intentional dependency topology, not cosmetic density tuning.

---

## 1. Executive summary

After Tier 1/2 dense-strategy work failed to move gameplay metrics, we pivoted to a **topology-first architecture**. Diagnostic telemetry proved:

1. **Phase 1 (grid caps) works** — no more 15×7 grids; Hard axes clamped to 8–10.
2. **Crunch blocking during retrograde construction is incompatible with strict ID-order solvability** — the retry loop always collapsed to prob=0.25 (clear-only).
3. **Cross-block removal-order sort was breaking solvability** after blocking was placed (full `List.sort()` on entire ID sequence).
4. **Post-placement direction reassignment** (flip crunch-window nodes to point at lower-ID cells) is the correct fix — it preserves ID-order by construction.

**Current state:** Reassignment pass shipped. Opening improved (19 → 15), FSR slightly up (3% → 4%), crunch blocking survives (`crunchPick≈66`), `winRetry=0` on 8/10 Hard L30–39. Still below Phase 2 gate (FSR > 8%, in-band ≥ 50%).

---

## 2. Problem statement (original)

Hard levels felt like mindless tapping:

| Symptom | Measured value |
|---------|----------------|
| Opening legal moves | ~20–27 |
| FSR (forced-sequence ratio) | ~2–3% |
| Tempo shape | Linear decay (tempoMax = opening, tempoMin = 1) |
| Hard in-band rate | 0/10 on L30–39 |
| Viable paths | 64 everywhere (massively parallel) |

**Root insight:** The generator assigns arrow directions to avoid blocking. Clear-ray retrograde construction structurally caps FSR at ~3% regardless of weight tuning.

**Target experience:** FLOW → CRUNCH → RELEASE through intentional dependency topology — not sparse soup, not hyper-dense lock torture.

---

## 3. Plans attempted

### 3.1 Tier 1 / 2 / 3 hybrid plan (V2)

Three gated phases:

| Phase | Intent | Result |
|-------|--------|--------|
| Tier 1 | Grid caps, Hard bands 4–8, director fill 50–65% | Grid caps ✅; metrics unchanged |
| Tier 2 | Cross-block sort + row/col scorer in crunch zone | Shipped in code; **no metric movement** |
| Tier 3 | `passesTemporalArc()` + ship gate | Wired; 0% in-band; fallback kept |

**Why Tier 1/2 failed:** They targeted the wrong layer. Cross-block row/column ≠ ray dependency. Removal-order sort reorders IDs only — `firstLegalMoveCount` and FSR are computed on the full board before any removal.

### 3.2 Topology-first plan (Track A/B/C)

| Track | Scope | Status |
|-------|-------|--------|
| A | Grid caps + phase-aware blocking + ray intercept scorer | Partially superseded |
| B | Dependency graph engine (DAG before geometry) | **Deferred v4** |
| C | UI: legal move glow, ray preview, progress bar, Hard timer rework | **Complete** |

---

## 4. Architectural diagnosis (definitive)

### 4.1 The real bottleneck: strict ID-order validation

The generator requires:

```
Node 0 removable → Node 1 removable → Node 2 removable → ...
```

This is an extremely strong constraint that suppresses:

- Convergence / shared gates
- Midgame locking
- Dependency overlap
- Bridge structures

**Easy mode works better** (FSR ~12%, opening ~7.5) because sparse boards naturally satisfy strict ID-order. Dense strategic boards need alternate unlock flexibility that the validator suppresses.

### 4.2 Why retrograde crunch blocking failed

During retrograde construction (building backward):

- High occupancy (>0.65) = player's **opening** taps (low IDs) → should use clear dirs
- Mid occupancy (0.35–0.65) = player's **crunch** → should use blocking dirs
- Low occupancy (<0.35) = player's **release** (high IDs)

When blocking dirs were offered during crunch construction, `_validatesRemovalOrderIdSequence` failed because:

- Node N pointing at node M where M > N → at step N, M still present → **deadlock**
- Cross-block sort then reshuffled IDs, breaking the carefully built sequence

Telemetry confirmed:

| Counter | Value (L30–39, pre-fix) | Meaning |
|---------|-------------------------|---------|
| `blkOffered` | ~316/level | Blocking dirs ARE offered (not culprits #3) |
| `blkPicked` | ~15/level | Some blocking selected |
| `solvRetries` | ~32/level | Retry loop constantly stripping blocking |
| `blockedNodes` | ~18/37 (49%) | Blocking in shipped levels — mostly **release-zone fallback** |
| `crunchPick` | **0.0** | Intentional crunch blocking never survived |
| `winRetry` | **0:0 / 1:0 / 2:10** | 100% shipped at prob=0.25 |

### 4.3 Occupancy inversion — ruled out

Retrograde occupancy mapping was correct. If inverted, shipped levels would have almost no blocked nodes. Instead 49% had blocked rays — zones were reachable; solvability retry was the stripper.

---

## 5. Implementations shipped

### 5.1 Phase 1 — Grid caps ✅

**File:** `lib/game/levels/generation/level_configuration.dart`

- `_clampGridDimensions(w, h, mode)` applied after every archetype path
- Caps: Easy 6–8, Medium 6–9, Hard 8–10, Daily 9–11
- Corridor archetype clamped (no more 15×7)
- Test: Hard L30–500 sweep in `level_configuration_test.dart`

### 5.2 Phase 3 — Evaluator + ship gate (partial) ⚠️

**Files:** `difficulty_profile.dart`, `level_generator.dart`

- Hard bands: opening 4–10, BF 3.0–8.0
- Real `passesTemporalArc()` wired into `passes()` for Hard/Expert
- `maxAttempts` raised to 40
- In-band ranking: temporal arc → CUD → midgame FSR → density
- **Out-of-band fallback retained** (strict in-band-only would fail generation today)

### 5.3 Track C — UI ✅

| Change | File |
|--------|------|
| Legal move glow + blocked opacity (55%) | `node_component.dart` |
| Ray preview on long-press | `ray_preview_component.dart` |
| Phase progress bar (flow/crunch/release colors) | `PhaseProgressBar` |
| Hard timer → optional speed bonus | HUD + win panel |

### 5.4 Four diagnostic fixes

| Fix | Change |
|-----|--------|
| 1 | Removed cross-block `List.sort()` on full removal sequence |
| 2 | `winningBlockingRetryIndex` telemetry (0=0.72, 1=0.45, 2=0.25) |
| 3 | Removed unvalidated construct fallback (L183–185) |
| 4 | Split `crunchZoneBlockingPicked` vs `releaseZoneFallbackPicked` |

### 5.5 Post-placement direction reassignment ✅ (current architecture)

**File:** `lib/game/levels/generation/retrograde_constructor.dart`

**Two-phase construct():**

```
Phase 1: Clear-ray-only coordinate placement (retry up to 8× until ID-order validates)
Phase 2: _applyPhaseAwareDirectionReassignment() at prob 0.72 → 0.45 → 0.25
```

**Solvability invariant for flips:**

Node `i` may point at node `j` on its ray **only when `j < i`**:

- At removal step `i`, nodes `0..i-1` (including `j`) are gone → ray clear at step `i`
- Early in puzzle, `j` still present → node `i` blocked → forced-sequence pressure

**Never** point at higher-ID nodes — that deadlocks ID-order validation.

**Crunch window:** IDs from `(n × 0.35)` to `(n × 0.65)` of removal sequence.  
**Motif reservation cells skipped** during reassignment.

**Construction enumeration:** `_directionPoolForZone` now clear-only; blocking handled exclusively by reassignment pass.

---

## 6. Snapshot results

Run:

```bash
flutter test test/game/levels/generation/dense_strategy_snapshot_test.dart
dart run tool/dense_strategy_snapshot.dart
```

Per-level telemetry columns: `blkOffered`, `blkPicked`, `solvRetries`, `blockedNodes`, `crunchPick`, `releasePick`, `winRetry`.

### Hard L30–39 comparison

| Metric | Pre-topology | After 4 fixes | After reassignment |
|--------|--------------|---------------|-------------------|
| Opening avg | ~19.2 | ~18.4 | **~14.9** |
| FSR avg | ~3% | ~3% | **~4%** (L38: 8%) |
| Fill avg | ~51% | ~47% | ~38% |
| `crunchPick` | 0.0 | 0.0 | **~66.3** |
| `releasePick` | ~11.0 | ~16.0 | ~16.0 |
| `solvRetries` | ~32.2 | ~29.8 | **0.0** |
| `winRetry` | — | 0:0/1:0/2:10 | **0:8/1:0/2:0** |
| In-band | 0/10 | 0/10 | 0/10 |
| Grid axes | 8×8–10×10 | 8×8–10×10 | 8×8–10×10 |

### Interpretation

- **Reassignment works:** `winRetry=0` on 8/10, `solvRetries=0`, `crunchPick>0`
- **Opening improved ~4 moves** — lower-ID blocking creates early dependencies
- **FSR still flat overall** — isolated flips ≠ dependency chains; tempo still mostly linear
- **Phase 2 gate not met:** FSR > 8%, in-band ≥ 50%

---

## 7. Key files

| File | Role |
|------|------|
| `lib/game/levels/generation/retrograde_constructor.dart` | Construct + reassignment pass |
| `lib/game/levels/generation/candidate_scorer.dart` | Placement scoring (clear-ray construction) |
| `lib/game/levels/generation/level_configuration.dart` | Grid caps, daily fill |
| `lib/game/levels/generation/difficulty_profile.dart` | Bands, `passesTemporalArc()` |
| `lib/game/levels/generation/level_generator.dart` | K-loop, ship gate, telemetry |
| `lib/game/levels/generation/metrics.dart` | FSR, tempo profile, opening count |
| `lib/game/levels/analytics/generation_analytics.dart` | Session snapshot telemetry |
| `test/game/levels/generation/dense_strategy_snapshot_test.dart` | Gameplay metrics snapshot |
| `test/game/levels/generation/phase2_blocking_diagnostic_test.dart` | Blocking telemetry diagnosis |
| `test/game/levels/generation/retrograde_constructor_test.dart` | Reassignment + solvability tests |
| `tool/dense_strategy_snapshot.dart` | Standalone snapshot (full tempo arrays) |

---

## 8. Telemetry reference

| Field | Source | Meaning |
|-------|--------|---------|
| `blkOffered` | Reassignment flip opportunities in crunch window | Per-level delta across K=8 attempts |
| `blkPicked` | Flips actually applied | Same |
| `crunchPick` | `crunchZoneBlockingPicked` | Intentional crunch reassignment flips |
| `releasePick` | `releaseZoneFallbackPicked` | Construction-time fallback (now minimal) |
| `solvRetries` | `constructionSolvabilityRetries` | Reassignment prob step-downs |
| `winRetry` | `winningBlockingRetryIndex` | 0=0.72, 1=0.45, 2=0.25, null=baseline only |
| `blockedNodes` | Shipped level ray-block count | Nodes whose dir hits another node |

---

## 9. Test status

| Suite | Status |
|-------|--------|
| `retrograde_constructor_test.dart` (14 tests) | ✅ Pass |
| `dense_strategy_snapshot_test.dart` | ✅ Pass (informational) |
| `phase2_blocking_diagnostic_test.dart` | ✅ Pass |
| `level_generator_test.dart` | ✅ Pass |
| Full `test/game/levels/generation/` | ⚠️ 263 pass, **1 fail** (full suite run timed out; 1 failure in corpus/director area — investigate separately) |

---

## 10. Decision tree (current)

```
Clear-ray construction + reassignment (j < i flips)
  └─ winRetry=0 on most levels?  YES ✅
  └─ crunchPick > 0?               YES ✅
  └─ solvRetries = 0?              YES ✅
  └─ FSR > 8%?                     NO ❌ (~4%)
       └─ Next: chain-dependency preference in reassignment
       └─ Or: partial-order validation (architecture pivot)
       └─ Or: Track B dependency graph (v4)
```

---

## 11. Explicitly NOT doing (yet)

- Raising blocking probability alone (proven dead end without constraint fix)
- Global FSR gate before construction produces crunch naturally
- Removing out-of-band fallback before ≥50% in-band
- Full dependency graph compiler (Track B) until reassignment chain flips tested
- Post-hoc direction reassignment as permanent architecture without chain logic (current pass is prototype, not final)

---

## 12. Recommended next steps

### Short term (Phase 2 continuation)

1. **Chain-dependency preference in reassignment** — when flipping node `i` toward `j`, prefer `j` that itself blocks toward lower IDs (build chains A→B→C)
2. **Raise flip density** — flip more crunch-window nodes per pass
3. **Per-level telemetry normalization** — report flips per shipped level, not accumulated K-loop totals

### Medium term (architecture)

4. **Partial-order validation** — validate `exists valid solve path` + pacing metrics instead of exact ID chain
5. **Dependency motifs** — bridge, gate, fork, delayed release (pre-placement topology)

### Long term (Track B)

6. **Dependency graph generation** — DAG before geometry; spatial embedding realizes graph edges

---

## 13. Emotional target metrics (Hard)

| Metric | Now | Phase 2 target | Final target |
|--------|-----|----------------|--------------|
| Opening avg | ~15 | 10–15 | 5–10 |
| FSR avg | ~4% | **> 8%** | 12–30% |
| Tempo shape | Linear | Mid dip visible | Flow→crunch→release |
| In-band L30–39 | 0/10 | informational | ≥ 5/10 (50%) |
| Hard solve time | ~90s | ~2 min | 3–5 min |

---

## 14. Related docs

- [dense_strategy_session_context.md](./dense_strategy_session_context.md) — earlier dense strategy work
- [layout_generation_strategy.md](./layout_generation_strategy.md) — layout/silhouette strategy
- `.cursor/plans/topology-first_generation_fix_f74c8209.plan.md` — implementation plan (Cursor)

---

## 15. One-sentence verdict

**Strict ID-order solvability suppresses strategic topology; post-placement reassignment with `j < i` blocking constraint is the first fix that survives validation — but isolated flips are not yet enough for FSR > 8%; chain dependencies or partial-order validation is the next leap.**
