# Generator Input Closure Audit

## Goal
Enumerate every value capable of changing generated output, then classify each. This ensures we understand exactly what can change a board, declaring the determinism contract.

## Classes
- **Explicit input**: Values explicitly passed or derived for generation.
- **Persistent state**: State saved across app launches.
- **Session state**: Mutable state across a play session. Must be promoted into the contract.
- **Ephemeral state**: Internal, telemetry, or cache state that does NOT affect generation output.
- **Forbidden hidden state**: Hidden state that affects output but isn't part of the contract.
  An entry may only leave this class by being removed, promoted into the contract, or placed
  outside the contract's declared scope — never by being re-labelled.

## Audit Table

| Candidate | Location | Class | Justification / Action |
|---|---|---|---|
| `levelId`, `mode` | Call args | Explicit input | Passed directly to the generator. |
| `generationVersion`, `recipeId` | New, T0.0c | Explicit input | Being added to the contract to ensure regeneration safely. |
| Primary seed / `Random` derivation | `director.dart`, `level_seed.dart` | Explicit input | Seed is explicitly derived from `levelId` and/or `dayKey`. |
| `_diversityLedger` | `level_generator.dart` | Session state | Carries history of generated boards to avoid repetition. Promoted to session context. |
| `_silhouetteSessionTracker` | `level_generator.dart` | Session state | Carries history of used silhouettes to avoid consecutive repetition. Promoted to session context. |
| `_pendingEmission` | `level_generator.dart` | Ephemeral state | Stages analytics/telemetry data during generation; discarded or committed at end. Does not affect generation output. |
| `_lastWinningBlockingRetryIndex` | `level_generator.dart` | Ephemeral state | Only used for telemetry logging, no reads for generation logic. |
| `_retrogradeAttemptCount` | `level_generator.dart` | Ephemeral state | Telemetry counter, does not affect generation logic. |
| `_sightlineCache` | `level_generator.dart` | Ephemeral state | Purely geometric cache, deterministic based on grid dimensions. |
| `LevelManager._generator` | `level_manager.dart` | Session state | Static/global variable. Must be made re-creatable for session boundaries. |
| `enableDiversityGating` | Constructor flag | Explicit input | Toggles ledger *rejection* only — see the correction below; it does **not** neutralise session state. |
| Seeded-level registry | `seed_registry.dart` | Explicit input | Pure function of `levelId`, providing manual level overrides. |
| `timeBudget` (the value) | Call arg | Explicit input | Passed by `LevelManager`; `null` in the generation test suites. |
| **Elapsed wall-clock vs `timeBudget`** | `level_generator.dart:501,514,599` | **Ephemeral state — *outside* the contract's scope** | Found in `Forbidden hidden state`; resolved by scoping the contract to `timeBudget == null` rather than by removal. See "Wall-clock is an input on the budgeted path" below. |

**Acceptance criterion: zero entries remain in `Forbidden hidden state`.**

One candidate did land there during the audit — elapsed wall-clock on the budgeted path — and it
is the reason this document exists rather than being a formality. It is resolved below by
**scoping the contract to `timeBudget == null`**, not by removal: the budget is load-bearing for
player-facing load latency, and buying determinism by deleting it is the wrong trade. Inside the
contract's scope it cannot vary, so its final class is Ephemeral. Every other value is Explicit,
Session or Ephemeral.

## Wall-clock is an input on the budgeted path

The first pass of this audit missed this, and the plan's own DoD instrument would not have caught
it: it proposes verifying "no board changed" **by CSV diff**, but the corpus CSVs are not
reproducible, so that diff cannot distinguish a real regression from ordinary run-to-run noise.

### Evidence

`report_hard_100_test.dart` was run twice against **identical code**, minutes apart. Two of the
100 boards came out different — not just `genMs`, but `nodes`, `maskCells`, `bboxW/H`, `waves`,
`fsrPct`, `inBand` and more.

### Mechanism

`generateFromConfiguration` takes a `timeBudget`, and when it is non-null a `Stopwatch` decides
control flow in three places:

| Site | Effect of being over budget |
|---|---|
| `level_generator.dart:501-506` | Ships `budgetFallback`/`mechanicShortFallback` immediately, abandoning the attempt loop |
| `level_generator.dart:513-515` | Fast-forwards `regimeAttempt` to `maxAttempts - 4`, which changes node-count scaling and the archetype regime |
| `level_generator.dart:599-603` | Ships the first valid enriched level, skipping the wave-band preference entirely |

So on the budgeted path the emitted board is a function of **how fast the host machine happened
to be**, which is not a declared input and cannot be made one.

### Resolution — scope, do not remove

The budget is deliberate and load-bearing: it exists to bound worst-case level-load latency for
the player. Removing it to buy determinism is the wrong trade. The contract is therefore scoped:

```
Board = f(levelId, mode, generationVersion, recipeId, declared inputs)   iff timeBudget == null
```

- **`timeBudget: null` — the neutral construction.** Fully deterministic. This is the contract,
  and the only configuration in which byte-identity is a meaningful assertion. All five T0.0b
  probes run here, as do the P1/P2/P3 byte-identity gates.
- **`timeBudget: non-null` — production.** `LevelManager.generationBudget` (campaign) and
  `dailyGenerationBudget` (daily) are both non-null, so **shipped play has never been
  deterministic and cannot be.** This is the same conclusion Decision 1 already reached about the
  warm ledger, reached again by a second, independent route.

### Consequences to carry forward

1. **Do not use a corpus CSV diff as the "no board changed" gate** (T0 DoD, and again after P1/P2
   re-baselining). It has a false-positive rate of roughly 2% per 100 boards. Compare boards
   generated with `timeBudget: null` instead — that is what the T0 verification below did.
2. **A handful of rows drifting between two corpus reports is expected**, not evidence of a
   regression. Reviewers reading `docs/playtests/*.csv` need to know this.
3. **P1/P2 re-baselining should record the budget** used for each corpus run alongside
   `generationVersion`.

## Completeness proof

The table above is the plan's *candidate* list. The audit's acceptance criterion requires
proving that list **complete**, not merely classifying it, so every mutable field reachable
from a generation call was enumerated from source and accounted for below.

### Method

1. Enumerate every instance field of `LevelGenerator` (`level_generator.dart:55-126`).
2. For each, grep every read site and ask: *is it read anywhere on the path that decides
   geometry, node kinds, or candidate selection?* A field that is only ever **written** during
   generation and **read** through a public getter, `snapshotSession()`, or an analytics event
   cannot change a board.
3. Repeat for the two injected collaborators, `_validator` and `_director`.

### Fields not in the candidate list, and why none of them are inputs

| Field(s) | Reads | Class |
|---|---|---|
| `_retrogradeAttemptCount`, `_retrogradeSuccessCount`, `_retrogradeInBandSuccessCount`, `_retrogradeOutOfBandSuccessCount`, `_evaluatorRejectionCount`, `_diversityRejectionCount`, `_legacyAttemptCount`, `_renegotiationCount`, `_blockingDirCandidatesOffered`, `_blockingDirCandidatesPicked`, `_crunchZoneBlockingPicked`, `_releaseZoneFallbackPicked`, `_constructionSolvabilityRetries`, `_winningBlockingRetryIndex0/1/2`, `_maxAttemptsExhaustedCount`, `_rejectAspectCount`, `_rejectOccupancyCount`, `_rejectComponentsCount`, `_rejectSingletonCount`, `_rejectBlobVsGridCount` | Public getters + `snapshotSession()` only | Ephemeral state |
| `_archetypeEmissionCounts`, `_motifEmissionCounts`, `_seedEmissionCounts`, `_strongMotifEmissionCount`, `_strongMotifEmissionsWithMotifCount` | Incremented at `:1143-1156` and `:454`; read only at `:196-233` (getters + `snapshotSession`) and cleared by `resetCounters()`. **No generation branch reads them** — the archetype distribution is sampled by the Director from the seed, never rebalanced against observed counts. | Ephemeral state |
| `_validator` | `final`, injected. `LevelValidator` is a pure predicate over a candidate level. | Explicit input |
| `_director` | `final`, injected. `director.dart` declares **no instance fields** — every decision is a pure function of the `Random` handed in. | Explicit input |

This is the load-bearing claim: **the emission counters are write-only with respect to
generation.** Were any of them read by a candidate gate, the generator's output would depend on
how many levels the instance had already produced through a second channel that
`LevelGenerator.neutral()` does *not* reset (`resetCounters()` is a separate, telemetry-only
seam). They are not, so it does not.

**Conclusion: the field enumeration is complete.** Every value capable of changing generated
output is in the audit table; everything else enumerated here is telemetry. Note that the one
input this audit initially missed — elapsed wall-clock — was not a *field* at all, which is why a
field-by-field sweep alone was not sufficient to close the question. It was found by observing
that two runs of the same code disagreed.

### `LevelManager.generator` — callers enumerated

T0.0c requires the static generator be re-creatable, and the callers enumerated before changing
it. The field was private (`_generator`) and had **no external references**, so widening it to
`static LevelGenerator generator` broke nothing. What reaches it does so through the two static
entry points:

| Entry point | Production callers | Test callers |
|---|---|---|
| `LevelManager.getLevel` | `chain_pop_game.dart`, `game_screen.dart` | `deadlock_test`, `integration_test`, `relay_softlock_test`, `regression_test`, `widget_test`, `level_manager_test` |
| `LevelManager.getDailyChallenge` | `daily_challenge_calendar_screen.dart` | `dense_strategy_snapshot_test`, `difficulty_quality_audit_test`, `opening_compression_measurement_test`, `report_daily_10_test`, `level_manager_test` |

Every one of these shares a single process-wide generator, and therefore a single warm ledger —
which is the intended production behaviour, not a defect. **Nothing currently assigns to
`LevelManager.generator`**; the seam exists so a session boundary (P4) can install fresh state,
and so a test needing neutrality can opt in explicitly.

## Correction — `enableDiversityGating: false` does not buy determinism

Its doc comment claimed: *"Set to false in tests that expect strict determinism across multiple
`generate()` calls on the same generator."* **That was false**, and one test believed it.

The flag is honoured in exactly one place, the `isNovel` check at `level_generator.dart:831`.
The silhouette tracker is read at `:1138-1140` (`streakPenalty`, `diversityBoost`) and recorded
at `:1169`, none of it guarded by the flag. So a shared generator keeps re-ranking candidates by
how recently each silhouette was emitted, and two `generate(id)` calls can still diverge.

`level_generator_properties_test.dart` "Property 2 — Deterministic Generation" shared one
`enableDiversityGating: false` generator and asserted byte-identity. It failed (verified failing
at the pre-T0 commit as well, so it is long-standing, not a T0 regression). Fixed the same way
T0.0c(d) fixed the two sites in `level_generator_test.dart`: a fresh `LevelGenerator.neutral()`
per call, assertions untouched. The flag's doc comment has been corrected.

**Lesson for the closure audit:** classifying `enableDiversityGating` as `Explicit input` was
correct but insufficient. An input can be correctly classified and still carry a *false documented
contract*, and a downstream test can be built on that falsehood. Where a flag claims to bound
non-determinism, the audit should check the claim against the call sites, not just the class.

## Caveat on the contract — session state does not *always* move the board

The determinism contract says a board is a function of the declared inputs, with the ledger and
silhouette tracker promoted to declared session state. The converse does **not** hold: a warm
ledger does not guarantee a *different* board.

On `levelId = 42` the K-loop has very few in-band candidates, so a second call on the same
generator exhausts them, falls through to `nonNovelFallback`, and re-emits the byte-identical
board. Session state was consulted and changed nothing.

This matters in two places:

- It is why probes 1, 3 and 4 use `id = 44` rather than the plan's `42` (see below).
- Any future test asserting that boards *differ* across calls is asserting a property of the
  candidate population at that id, not of the contract. Such assertions are legitimately
  fragile, and P1/P2 — which deliberately change candidate diversity — may flip them.

## Determinism Probe Results (T0.0b)

*Deviation from the plan, and why.* The plan specified `id=42` for continuity with the existing
test. On `id=42` the K-loop has very few in-band candidates: consecutive calls fall back to
`nonNovelFallback` and emit the exact same board, so probes 1/3/4 cannot observe ledger
rejection there. They use `id=44` instead. **Continuity with 42 is preserved elsewhere** —
`level_generator_test.dart` still asserts fresh-generator byte-identity on 42, which is the
contract-bearing assertion; only the "boards differ" probes moved. See the contract caveat above:
the id-42 behaviour is itself a finding about the contract's limits, not just a test-fixture
detail.

The plan also asked probes to include "ids the audit flagged as unstable". The audit flagged
none — no candidate landed in `Forbidden hidden state` — so there were no such ids to add.

| # | Sequence | Expectation | Result |
|---|---|---|---|
| 1 | one generator: `generate(44)`, `generate(44)` | **differs** — ledger is a declared input | Passed |
| 2 | two fresh generators: `generate(44)` each | **byte-identical** — the contract | Passed |
| 3 | one generator: `44`, `45`, `44` | differs (documents ledger dependence on history) | Passed |
| 4 | one generator: `44` Hard, `44` Medium, `44` Hard | differs; **mode must not leak into the 3rd** beyond ledger effects | Passed |
| 5 | two fresh generators, full sweep of 100 `kReportSampleIds` × 3 modes | **byte-identical** | Passed |

*Probe 5 covers 100 `kReportSampleIds` × 3 modes = 300 board pairs, comparing grid dimensions,
node count, and per-node `x`, `y`, `dir`, `isCore`, `kind`. Runtime ~2m15s; the file is
untagged and runs in the default suite.*

## Corpus-unchanged verification (T0 definition of done)

The DoD requires that no board changed anywhere. Verified empirically rather than by inspection:
a git worktree at the pre-T0 commit and the working tree each generated 120 level ids × 3 modes
(360 boards), emitting full node geometry. The two outputs were byte-identical
(`md5 28940da610125be700dd009800b30020`).

Deliberately **not** done by CSV diff, which the DoD suggests: per the wall-clock finding above,
the corpus CSVs are not reproducible and would have shown ~2 spurious differing boards per 100.
The comparison above generates with `timeBudget: null`, inside the contract, where a single
differing byte is real.

The result is expected by construction — the `generationVersion` fold at
`level_generator.dart:372` is guarded by `if (kGenerationVersion > 1)`, dead at v1 — but the guard
is exactly the kind of thing worth confirming rather than assuming. Note the consequence: **the fold has never executed.** The
first bump to v2 exercises an unproven path and should re-run this comparison expecting a
deliberate, total re-roll.

### Re-verified after T0.1 / T0.2

T0.1 extracted the ray-prerequisite walk out of `computeCriticalUnlockDepth` into the shared
`computeRayPrerequisites` / `computeChainDepths` in `metrics.dart`, so that `CoreMetrics` reads
the same relation instead of a copy. `computeCriticalUnlockDepth` feeds `LevelMetrics`, which
**is** on the live candidate-selection path — so this refactor, harmless as it reads, is exactly
the kind that must be proved rather than argued.

The comparison above was repeated against a worktree at the pre-T0 commit (`34081f7`), 120 ids ×
3 modes = 360 boards, full node geometry (`id, x, y, dir, isCore, kind`):

```
pre-T0    boards=360  bytes=164853  hash=-5474c579aa0323d5
post-T0.2 boards=360  bytes=164853  hash=-5474c579aa0323d5
```

Byte-identical. No geometry moved through T0.0, T0.1 or T0.2.

This is no longer a scratch harness. It is pinned as a permanent regression test —
`corpus_identity_test.dart`, backed by `corpus_identity.dart` — which records **board count,
byte length and hash**, and can name the **first differing board field-by-field** rather than
just reporting that something moved. The population check matters independently: a sweep that
silently shrank would otherwise read as an ordinary hash mismatch.

## Hidden-state independence — asserted, not just classified (T0.0c)

The audit table above *classifies* every mutable field. A classification is a claim about the
code, and a claim is worth what its test is worth, so the two load-bearing claims are now
machine-checked in `determinism_contract_test.dart` (group "Hidden-state independence"):

| Probe | Claim under test | Result |
|---|---|---|
| `neutral()` resets session state | No static or global links two fresh generators, even while a heavily warmed third instance exists (90 emissions across all modes) | Passed |
| emission counters are write-only | `resetCounters()` cannot move a board — no candidate gate reads `_archetypeEmissionCounts` and friends | Passed |
| telemetry getters are inert | Calling `snapshotSession()` and `lastWinningBlockingRetryIndex` between every generation changes nothing — `_pendingEmission` does not feed back | Passed |
| mode sweeps do not leak | Sweeping all modes for an id on one instance leaves a fresh instance's board for that id unchanged | Passed |

**The principle these encode:** no mutable process state may silently influence board identity.
If it does, it must become an explicit input.
