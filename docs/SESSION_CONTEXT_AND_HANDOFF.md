# Session Context & Handoff — Chain Pop Refactor / Quality Alignment

> **What this file is.** A complete handoff of the current working session: what was asked, what was done, the current repo state, the open decisions, and the remaining tasks. Read this first if you're picking up the work.
>
> **Companion doc:** [`OPENING_BAND_DECISION.md`](./OPENING_BAND_DECISION.md) — the deep game overview + the one open product decision (the `[3,5]` opening band). This file references it but does not duplicate it.

_Last updated: 2026-06-14._

---

## 1. The big picture (why this work exists)

A codebase review of **Unbound: Arrow Puzzle** (`chain_pop`, a Flutter + Flame logic puzzle) produced a "Good / Bad / Ugly" assessment. The headline findings:

- **Ugly:** the level generator does **not** hit its own difficulty targets (Hard/Expert opening width), yet ships out-of-band levels anyway; an untracked file could break clean checkouts; 52 analyzer issues; an over-engineered generation subsystem.
- **Bad:** `GameScreen` carries too much orchestration via tightly-coupled `part` files; persistence is half-migrated; docs are stale.
- **Good:** solvability-by-construction guarantee, strong test culture (538+ tests), good DI, intent-explaining comments.

A phased implementation plan was created to address these **without** gaming metrics. The work was executed in phases (A–F below).

---

## 2. Current repo state (verified)

- **Branch:** `new_improvements` (2 commits ahead of `origin/new_improvements`).
- **All session work is UNCOMMITTED** (working tree only). Nothing committed, nothing pushed.
- **Health:** `flutter analyze` = **0 issues**; `flutter test` = **541 passed, 3 skipped**; `flutter build apk --debug` = **passes**.
- **Difficulty spec is unchanged from baseline** (all Phase B experiments were reverted).

### Uncommitted changes (by area)

**Kept — Phase A (honest baseline restore) + analyzer cleanup:**
- ~20 files de-linted (unused imports/dead code/const/print): `lib/game/board_layout.dart`, `.../generation/{director,metrics,motifs,visual_composition,candidate_scorer,dense_strategy_snapshot}.dart`, `analysis_options.yaml`, plus several tests.
- `lib/game/levels/generation/retrograde_constructor.dart`: **only** the Phase A `_enforceOpeningTarget` break-bug fix remains (`if (opening <= maxOpening && opening >= minOpening) break;`).
- Deleted stray artifacts `android_emulator_test_results.txt`, `test_out.txt`; `.gitignore` updated to ignore `*_test_results.txt` / `test_out*.txt`.

**Kept — Phase D (storage consolidation):**
- `lib/screens/{main_menu_screen,level_select_screen,daily_challenge_calendar_screen}.dart` migrated off the legacy `StorageService` static facade onto `StorageLocator.instance`.
- New guard test (untracked): `test/storage_isolation_test.dart`.

**Kept — Phase B artifacts (diagnostics only):**
- New (untracked) measurement harness: `test/game/levels/generation/opening_compression_measurement_test.dart` (always passes; re-run anytime).
- New (untracked) `test/game/levels/generation/difficulty_quality_audit_test.dart` — the `[3,5]` gate, **intentionally skipped** (honest: not met).

**New docs (untracked):**
- `docs/OPENING_BAND_DECISION.md`
- `docs/SESSION_CONTEXT_AND_HANDOFF.md` (this file)

**Reverted (left no trace):** the inert opening-window compression pass, the density lift (`minNodes` 25→30), the FSR-cap threshold change (28→40), the grid tightening, and all debug instrumentation.

---

## 3. Phase status

| Phase | Scope | Status |
|---|---|---|
| **A** | Stop the bleeding: revert prior metric-gaming, restore honest baseline, fix analyzer regressions, restore broken unit tests | ✅ Done |
| **B** | Honest opening-width compression (measurement-first) | ✅ Investigated & concluded — see §4 |
| **C** | Re-arm the audit honestly (≥90% in-band, no out-of-band emission) | ⛔ Blocked on the §5 decision |
| **D** | Storage consolidation onto `StorageLocator` | ✅ Done (technical work complete & green) |
| **E** | `GameScreen` extraction (timer / ad / flow / playfield → standalone classes) | ⬜ Not started |
| **F** | Docs sync (README difficulty tables) + comment archaeology (Phase-N notes, dead telemetry) | ⬜ Not started |

### Original PR checklist (legacy numbering)

- [x] PR-0 Git & workspace hygiene
- [x] PR-1 Analyzer warnings (52 → 0)
- [x] PR-2 Fix `_enforceOpeningTarget` break bug
- [~] PR-3 Hard node density — **tried in Phase B, reverted** (made openings worse)
- [~] PR-4 Assertable audit test & calibration — audit exists but **skipped**, pending §5 decision
- [x] PR-5 Storage consolidation (= Phase D)
- [ ] PR-6 GameScreen — extract timer controller (= Phase E)
- [ ] PR-7 GameScreen — extract ad coordinator (= Phase E)
- [ ] PR-8 GameScreen — extract flow & playfield sync (= Phase E)
- [ ] PR-9 Documentation & comment archaeology (= Phase F)

---

## 4. Phase B — what happened (the key technical outcome)

**Goal:** make the generator honestly hit the `[3,5]` Hard/Expert opening band without widening the band.

**Outcome:** proven **structurally unreachable** by tuning. Full detail + evidence in [`OPENING_BAND_DECISION.md`](./OPENING_BAND_DECISION.md). Summary:

- Baseline openings: Hard **8.2**, Daily **8.6** (target 3–5).
- Opening-window compression pass: **inert**.
- Density lift (the approved experiment): made openings **worse** (9.6 → 10.1).
- Instrumented across 276 candidates: raw 14.6 → 10.7 after compression; **0/276 ever reached ≤5**.
- **Root cause:** opening width = count of ray-free nodes; a ray-free node can only be blocked by a **lower-id** node on a clear ray; retrograde construction places low ids **last**, so they rarely land where needed. This is **geometric starvation**, independent of density and of id-assignment.

All Phase B experiments were reverted; only the diagnostic harness + the (skipped) audit remain.

---

## 5. OPEN DECISION (blocks Phase C)

**What:** How to reconcile the `[3,5]` opening spec with the shipped `~8–11` reality. This is a **product call**, documented in full (4 options, pros/cons, gaming-vs-honest distinction) in [`OPENING_BAND_DECISION.md`](./OPENING_BAND_DECISION.md).

**Options in brief:**
- **A (recommended):** set the honest band `~[3,11]`, document why, un-skip the audit against it, assert no level ships above band max.
- **B:** redesign retrograde construction so low-id nodes are deliberate blockers (large, risky, uncertain payoff; preserves the tense `[3,5]` vision).
- **C:** leave audit skipped, document, move on.
- **D:** cut/retire the over-built difficulty machinery instead.

**Status:** user has **not** decided. Until then, **do not edit the difficulty bands** (the plan's explicit STOP-gate instruction).

---

## 6. Pending tasks (concrete)

### Blocked on the §5 decision
- [ ] **Phase C** — once the band is decided:
  - If Option A: set Hard/Expert opening band; un-skip `difficulty_quality_audit_test.dart`; add an assertion that no Hard/Daily level emits with `opening > band.max`; wire out-of-band emission to throw in test/debug builds (`level_generator.dart` ~807–828).
  - If Option B: scope and execute the construction redesign (separate, large effort).

### Independent of the decision (can start now)
- [ ] **Phase E — `GameScreen` extraction** (incremental, one controller per step; live-check each):
  - [ ] Convert `lib/screens/game/game_timer_controller.dart` (`part`) → standalone class.
  - [ ] Convert `lib/screens/game/game_ad_coordination.dart` → standalone class.
  - [ ] Convert `game_flow_controller.dart` + `game_playfield_sync.dart` → standalone classes.
  - [ ] Remove the `patchState(setState)` shim coupling once controllers own their state.
- [ ] **Phase F — docs & archaeology:**
  - [ ] Re-sync `README.md` difficulty tables (currently **stale**: claims Hard 6×6–16×16, 5–60 nodes, 40% density, strip fallback — none match current code). See `OPENING_BAND_DECISION.md` Appendix C.
  - [ ] Prune obsolete "Phase 3/4/5/6" comments and dead telemetry counters (e.g. `_monotoneFallbackHitCount`).

### Housekeeping / risks to address
- [ ] **Commit the clean baseline** (not yet committed; user hasn't asked). Suggested split: (1) analyzer cleanup, (2) storage consolidation + guard test, (3) Phase A generator revert + break-bug fix, (4) docs. Keep the skipped audit + measurement harness with the generator commit.
- [ ] **Latent crash risk (documented, not fixed):** in `level_configuration.dart` `_calculateNodeCount`, `baseCount.clamp(minNodes, min(effMax, maxPossible))` will **throw** if `maxPossible < minNodes` (low-density archetype on a small grid). It does not trigger today (Hard archetypes all have density modifier ≥0.85), but raising `minNodes` or adding a sparse Hard archetype will crash generation. A one-line guard (`max(minNodes, min(...))`) fixes it — was prototyped then reverted to keep the baseline pristine.
- [ ] Consider **Option D** (simplify the generator) as a larger initiative if `[3,5]` is abandoned — it directly addresses the review's biggest finding.

---

## 7. Key decisions & rationale (so they aren't re-litigated)

- **No metric gaming.** Bands must not be widened to force green checks. The earlier session did exactly this (widened opening to `[3,15]`, disabled the FSR cap) and it masked a *regression* (openings rose after a density push). All of that was reverted in Phase A. Any future band change must be the honest, documented recalibration described in the decision doc.
- **FSR-cap vs band contradiction is real.** `nodeCount > 28 ⇒ FSR ≤ 0.40` directly contradicts Hard (`FSR ≥ 0.45`) / Expert (`FSR ≥ 0.50`). Pushing node count above 28 without also moving the cap **crashes daily generation** ("Director exhausted attempts"). This is why density experiments must move both together — and why they're out of scope without sign-off.
- **Measurement-first.** Every generator change was gated by the measurement harness before/after; that's how the density hypothesis was falsified instead of assumed.
- **Live emulator checks were deferred.** The agent environment can't launch an Android emulator; verification used `flutter build apk --debug` + the full test suite. Interactive tap-through gameplay checks are still owed by a human at each phase.

---

## 8. Quick commands

```bash
# Health
flutter analyze
flutter test

# The Phase B diagnostic (re-runnable, always passes; prints opening/FSR/fill distribution)
flutter test test/game/levels/generation/opening_compression_measurement_test.dart

# The (currently skipped) honest gate
flutter test test/game/levels/generation/difficulty_quality_audit_test.dart

# Build sanity (used in lieu of emulator)
flutter build apk --debug
```
