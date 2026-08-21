# T0 exit gate

T0's purpose is to establish the **complete input contract** for board generation. It is not
done when the code is written; it is done when every claim in the contract is machine-checked.
This is the boundary that must be green before P1 touches core-placement behaviour.

Status as of 2026-08-19. Gen V1, `generationVersion: 1`.

| # | Gate | Evidence | Status |
|---|---|---|---|
| 1 | Input closure documented | `generator_input_closure.md`, field-by-field enumeration + completeness proof | ✅ |
| 2 | Zero `Forbidden hidden state` | Wall-clock resolved by scoping the contract to `timeBudget == null`; every other value Explicit / Session / Ephemeral | ✅ |
| 3 | `generationVersion` exists | `generation_version.dart`, folded into seed derivation (dead at v1 by design) | ✅ |
| 4 | `contentIdentity` exists | Stamped on every emission event and every CSV row | ✅ |
| 5 | `recipeId` schema exists | `contentIdentityFor(..., recipeId)`, defaults `neutral` until P4 | ✅ |
| 6 | Procedural determinism passes | Probe 5 — 100 ids × 3 modes, two fresh generators, byte-identical | ✅ |
| 7 | Seeded determinism passes | `level_seed_test.dart` (level 75, milestone seed) | ✅ |
| 8 | Same-generator repeat documented | Probes 1/3/4 — a warm ledger is a declared input, so boards may differ | ✅ |
| 9 | Fresh-generator repeat passes | Probe 2; `level_generator_test.dart`; `level_generator_properties_test.dart` Property 2 | ✅ |
| 10 | Hidden-state independence asserted | 4 probes: session reset, write-only counters, inert telemetry, no mode leak | ✅ |
| 11 | T0 metrics compile and are inert | `core_metrics.dart` — no `lib/` caller; `flutter analyze` clean | ✅ |
| 12 | 360-board corpus byte-identical | `corpus_identity_test.dart`, pinned `boards=360 bytes=164853 hash=-5474c579aa0323d5`, verified against the pre-T0 worktree | ✅ |
| 13 | Topology definition versioned | `kTopologyDefinitionVersion = 1`, exact formula in `corpus_version.dart` | ✅ |
| 14 | Baseline topology recorded | Easy 40 / Medium 25 / Hard 23 at 300 ids/mode — `topology_class_calibration.md` | ✅ |
| 15 | CoreMetrics tests pass | `core_metrics_test.dart`, 6 cases incl. the F1 divergence fixture | ✅ |

## Known-red tests, classified

The plan's standing gate is "full suite green, minus explicitly documented expected-red
canaries". These are the documented ones. All four were verified red at the pre-T0 commit
`34081f7`, so none is a T0 regression.

| Test | Class | Disposition |
|---|---|---|
| `corpus_benchmark` milestone-overload | **A — known unrelated production issue.** 16 of 40 milestone levels fall through to ordinary procedural boards | Tracked; plan §P3 requires it fixed before Tier-3 portfolio work. Do not relax the assertion — it is the canary. |
| `milestone_latency` | **B — known performance defect.** 44890 ms vs a 3000 ms bar on the seeded Director path | Deferred; same root cause as the row above. Wall-clock sensitive, so it passes on a quiet machine. |
| `deadlock_test` | **C — shared-generator lifecycle.** Director exhausts 40 attempts on a warm process-wide generator | Deferred by decision. **Intermittent, and that is diagnostic**: it fails under CPU contention and passes on a quiet machine, because `LevelManager` generates on the *budgeted* path where elapsed wall-clock decides control flow. It is the production-path nondeterminism the audit documents, surfacing as a flake — not a new bug. Revisit after P1. |
| `level_generator_properties_test` Property 2 | **D — T0.0c scope.** Shared generator asserting byte-identity | **Fixed.** Now constructs fresh per call; assertions unchanged. |

## Not yet done — required before P1 lands

| Item | Why it blocks | Owner decision |
|---|---|---|
| T0.3 red canary (`core_triviality_test.dart`) | Every P1 gate lives in it; it must be committed knowingly red | Next task |
| P1 core adversarial corpus | The random corpus is not stratified on core quality, so it cannot answer "did we fix the trivial-Medium problem, or just move the distribution?" | Specified below |

### P1 core adversarial corpus — specification

Before `_markCoreNodes` changes, capture a stratified baseline so P1 can be judged on the
population it is meant to fix rather than on an average.

- **Population:** 200 Medium boards with cores (sectors 3+), plus 100 Hard as the
  over-correction control.
- **Stratify by** `coreTapDepth`, `coreCriticalDepth`, `coreIsolation`,
  `maxSingleTapCascade`, and taps-to-win, into quintiles.
- **The bottom quintile is the artifact that matters** — those are the F1 boards. P1 must move
  that quintile, not merely lift the mean.
- **Emit before and after**, same ids, same modes, and diff per stratum. A P1 that improves the
  mean while leaving the bottom quintile intact has not fixed the bug.
