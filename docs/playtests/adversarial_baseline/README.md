# T0.4 — The Frozen Adversarial Corpus

**Frozen 2026-08-19 against `generationVersion: 1`. Selection is final.**

> ## The corpus is a scientific instrument. Selection happens exactly once.
>
> **The corpus evaluates; it never tunes.** Tuning the generator until specific
> frozen ids pass converts the instrument into an optimiser and voids the
> result. If a threshold anywhere in this apparatus is changed *after* someone
> has looked at which frozen ids failed, the experiment is over and has to be
> re-run on `kReportSampleIds` and a fresh draw.

---

## Why this exists

T0.3 measured F1 at **66 % of Medium boards won in ≤ 6 taps, p50 6**. A defect
that large has to have its *shape* measured before the core algorithm is
touched, because a random corpus cannot tell a real fix from three impostors
that all produce the same improved headline number:

| What actually happened after P1 | Defect fixed? | Random corpus sees it? |
|---|---|---|
| The trivial boards got genuinely deeper cores | ✅ | no |
| Node counts grew, so `coreTapDepth` rose while cores stayed last-popped | ❌ intact, hidden | no |
| The whole distribution shifted up — Medium is now bloated | ⚠️ overshoot | no |

Only a **per-stratum before/after diff on identical level ids** separates them.

**Why the selection is statistically sound.** Selecting the worst N cases by a
*noisy* measure makes them improve on re-measurement even under a no-op change —
regression to the mean, which fakes a win. That does not apply here:
`tapsToWin` is deterministic per `(levelId, mode, generationVersion)` under the
T0.0 contract, so there is no noise to regress. **The corpus is only trustworthy
because T0.0b passed.**

---

## Selection procedure

| View | n | Question it answers | Selection |
|---|---|---|---|
| Medium severity | 100 | did we fix the *disease*? | empirical `tapsToWin` quintiles over a 600-board pool, 20 per quintile |
| Medium representative | 100 | did we *bloat the patient*? | uniform over L1–1500, unfiltered |
| Hard control | 100 | over-correction control, **never an optimisation target** | uniform |

- **Pool seed `20260819`**, disjoint from `kReportSampleSeed` (`20260813`), so
  the T0.3 canary's 100 ids stay a genuine held-out set. Asserted, not assumed —
  see `adversarial_corpus_guards_test.dart`, *"the four id sets are mutually
  disjoint"*.
- **All generation at `timeBudget: null`.** On the budgeted path elapsed
  wall-clock decides control flow (T0.0a), so a budgeted corpus would drift with
  machine load.
- **No sector filter and no core-count filter.** The earlier sketch in
  `T0_EXIT_GATE.md` restricted Medium to "boards with cores, sectors 3+". That
  filter is a bug: the shallowest boards are overwhelmingly sector 2,
  single-core, and Medium sector 2 keeps `coreCount: 1` after T1.3 — so those
  boards are fixed by T1.1/T1.2 or not at all. A corpus that excludes them
  cannot see the fix. The eligible population is every board that can ship to a
  player.
- **`tapsToWin` is the sole selection key.** `coreTapFraction`,
  `coreCriticalDepth`, `coreIsolation`, `maxSingleTapCascade`, `coreCount`,
  `nodes`, `sector`, `waveDepth` and `topologyClass` are recorded as
  **covariates**, never as selection keys. Five keys cannot be quintiled at once.
- **Equal 20-per-quintile allocation, not a weighted tail.** With most of Medium
  at ≤ 6 taps, Q1–Q3 already sit inside the pathological region; shrinking Q4/Q5
  to over-weight Q1 would leave n = 10 in exactly the strata that detect
  over-correction, which is the *other* thing P1 can break.
- **Cause diversity inside each quintile.** Members are bucketed by
  `(sector band × coreCount)` and taken round-robin, so Q1 is not twenty
  near-identical sector-2 single-core boards testing one failure mode twenty
  times.
- **The representative view is a plain uniform draw.** `sector` is a pure
  function of `levelId` via `worldForLevel`, so a uniform draw reproduces
  campaign sector prevalence *by construction*; explicit sector stratification
  could only distort it.

Provenance: `test/game/levels/generation/adversarial_corpus_selection_test.dart`
(checked in **for provenance, not reuse**).

### Quintile boundaries at freeze time

Cuts are **rank-based**, not value-based. With most of Medium tied at a handful
of small tap counts, value cuts would leave quintiles empty and the n = 20
requirement unmeetable. Adjacent quintiles therefore share a boundary value; the
split inside a tied value is by ascending `levelId`, which is stable and
independent of everything P1 touches.

| Quintile | `tapsToWin` range | pool n |
|---|---|---|
| Q1 | 2 – 4 | 120 |
| Q2 | 4 – 5 | 120 |
| Q3 | 5 – 6 | 120 |
| Q4 | 6 – 8 | 120 |
| Q5 | 8 – 28 | 120 |

### Realised composition

| View | Sectors | Core counts |
|---|---|---|
| Medium severity | S1 7 · S2 19 · S3 31 · S4 8 · S5 29 · S6 5 · S7 1 | 0 → 7 · 1 → 19 · 2 → 74 |
| Medium representative | S1 15 · S2 19 · S3 12 · S4 19 · S5 8 · S6 7 · S7 9 · S8 11 | 0 → 15 · 1 → 19 · 2 → 66 |
| Hard control | S1 16 · S2 22 · S3 11 · S4 15 · S5 7 · S6 10 · S7 12 · S8 7 | 3 → 100 |

Recorded so under-representation stays **visible** rather than assumed away.
Two things to read honestly:

- The severity view is skewed toward S3 and S5 and thin at S6–S8. That is not a
  sampling error — it is where the shallow boards are, and the severity view is
  *supposed* to be skewed toward the disease. The representative view carries
  the unbiased sector picture.
- Seven severity boards and fifteen representative boards are **coreless**
  (Medium sector 1 ships `coreCount: 0`). On those the win is clear-all,
  `tapsToWin == nodeCount`, and they land in Q5 by construction. They are kept
  because they can ship to a player, and their `captureRate` is 1.0 by
  definition — there was no core-selection decision to get wrong.

---

## The freeze key

Frozen on **`(levelId, mode, generationVersion)`**, not `levelId` alone: a
future `generationVersion: 2` re-rolls content and must not be allowed to
silently redefine which board a frozen id means. `kAdversarialCorpusGenerationVersion`
records the value it was frozen at, and both the guards test and the baseline
test assert it still matches the running generator.

### One generator per board — and why that is load-bearing

Every corpus generation constructs a fresh **`LevelGenerator.neutral()`**.

The T0.0a closure audit classifies `_diversityLedger` and
`_silhouetteSessionTracker` as **session state** — promoted into the contract,
not eliminated from it. A `LevelGenerator` reused across a batch therefore emits
boards that are a function of the whole preceding sequence. The T0.0b probe is
consistent with this and says so explicitly: it declines to assert that a warmed
generator reproduces a fresh one's boards, because a warmed generator *is a
different input*.

The first T0.4 baseline run used a shared instance and was caught by exactly
that: **L1411/medium came out with 17 nodes and `tapsToWin: 8` inside the
ascending 600-id selection sweep, and 18 nodes and `tapsToWin: 4` inside the
300-entry corpus sweep.** Same id, same mode, same code, different board.

A freeze key of `(levelId, mode, generationVersion)` is only well-defined if the
board really is a function of it, so the corpus generates from neutral session
state and nothing else. The `report_*_100` harnesses keep their shared instance
deliberately — they measure the *sequence* a session actually produces, which is
a different and equally legitimate question. It is why a corpus row and a report
row for the same id can differ, and why the two are never compared.

This is proven on every baseline run rather than asserted in prose: `freezeNodes`
is recorded per severity board during selection and re-measured during the
baseline sweep, which visits the same ids in a completely different order.
**100/100 agree.**

---

## Baseline — Gen V1, 2026-08-19

### Distributions

| | severity (n=100) | representative (n=100) | Hard control (n=100) |
|---|---|---|---|
| `tapsToWin` min | 2 | 2 | 4 |
| p25 / **p50** / p75 | 4 / **6** / 8 | 4 / **5** / 8 | 9 / **10** / 11 |
| p95 / max | 12 / 22 | 19 / 23 | 14 / 19 |
| nodes min / p50 / max | 10 / 18 / 25 | 12 / 17 / 25 | 25 / 25 / 28 |
| **≤ 6 taps** | **61 %** | **67 %** | **1 %** |
| below mode floor | 45 | 51 | 1 |
| `captureRate` p25 / p50 / p75 | 0.45 / **0.58** / 0.70 | 0.40 / **0.55** / 0.78 | 0.53 / **0.64** / 0.71 |
| geometrically UNFIXABLE | **3** | **5** | **0** |

Mode floors, from T0.4§f's hard-gate row and fixed *before* P1 exists: Medium 6,
Hard 6, Easy 7 ("≤ 6-tap share = 0 %" written as a floor).

### Severity by quintile

| Q | n | taps min/p50/max | nodes p50 | capture p50 | ceiling p50 | unfixable |
|---|---|---|---|---|---|---|
| Q1 | 20 | 2 / 4 / 4 | 16 | 0.40 | 8 | 2 |
| Q2 | 20 | 4 / 5 / 5 | 16 | 0.63 | 7 | 1 |
| Q3 | 20 | 5 / 6 / 6 | 20 | 0.55 | 11 | 0 |
| Q4 | 20 | 6 / 7 / 8 | 20 | 0.62 | 12 | 0 |
| Q5 | 20 | 8 / 10 / 22 | 19 | 0.82 | 14 | 0 |

**This table, not p50, is the acceptance instrument.** An improved mean with a
static Q1 is a rejected result.

### The achievable-depth ceiling (§d)

For every board, the best `coreTapDepth` any spread-legal `k`-subset could reach
on that exact geometry — prerequisite closures as bitmasks, unioned over subsets
constrained by the same `spreadOk ≥ 2` Manhattan rule the real selector obeys.
`captureRate = actual / ceiling` scores the **selector**, not the population.

Two findings that change how P1 should be written:

1. **The Medium selector captures barely half of the depth already available:
    `captureRate` p50 0.58 (severity) and 0.55 (representative).** The shallow
    boards are, overwhelmingly, *not* geometrically shallow — the selector is
    leaving the depth on the table. F1 is a selection bug, and it is fixable
    without touching board geometry. Worst cases run to `captureRate` 0.22–0.30
    on boards with ceilings of 9–20.
2. **Only 3 / 100 severity and 5 / 100 representative boards have
    `ceiling < floor`, and 0 / 100 Hard.** These are geometrically unfixable:
    T1.2's bounded repick will burn all its attempts and ship the best it saw,
    silently. **At ~4 % this is small enough that T1.2 as specified can deliver
    its invariant on the rest** — but the set is non-empty, so T1.2 still needs a
    declared behaviour for it rather than a silent "best seen". Every one of
    these is a small board (12–19 nodes) and all but two are Medium sector 2,
    `coreCount: 1`.

Ceilings are a pure function of geometry, so they are themselves guarded: if a
ceiling moves while the three guards are green, the ceiling computation changed
and every `captureRate` before and after the diff is on a different scale.

### Core-selection path — which hatch actually ships the cores

T0.4's optional telemetry (`CoreSelectionTelemetry`, inert in production).

| Path | severity | representative | Hard |
|---|---|---|---|
| `strictBandArc` — the intended reach-1 → reach-2 → climax arc | 13 % | 17 % | 0 % |
| `strictBandTopUp` — arc failed, topped up from the full strict band | 48 % | 26 % | 85 % |
| `relaxedBand` — needed the widened `[0.25, 0.78]` band | 31 % | 42 % | 12 % |
| `legacyFallback` — cores *are* the last-popped nodes | 1 % | 0 % | 3 % |
| coreless board | 7 % | 15 % | 0 % |

**The designed behaviour is the exception.** The reach-1 → reach-2 → climax arc
fires on 13–17 % of Medium boards; 26–42 % need the band widened before three
spread-legal guarded candidates can be found at all. T1.3's balance note asked
for the relaxation rate before tuning further — it is 31 % and 42 %. T1.2 should
be designed knowing the strict band is already the minority path, not the norm.

---

## The three guards (§c)

Enforced by `adversarial_corpus_guards_test.dart`. All green at baseline, and
green is the boring case — they exist for the day P1 lands.

| # | Guard | What it kills |
|---|---|---|
| 1 | **Geometry identity** — grid, mask, portals, per-node `(id, x, y, dir)` | "the boards aren't the same boards any more" |
| 2 | **Solution-structure identity** — `nodeWaveIndices` on the mechanic-stripped board | the removal structure of the puzzle moved |
| 3 | **Node-count equality, exact** | node inflation — `coreTapDepth` rises while cores stay last-popped |

**Node-count equality is exact, not a tolerance.** `budget.coreCount` is consumed
only in `level_enrichment.dart`, post-generation, and `directiveFor` is read only
by star grading and the UI — never by the generator. So across all of P1 (T1.1
band, T1.2 floor, T1.3 count 2→3, T1.4 Easy core) node count and geometry must be
**bit-identical**. A "≤ 10 % median increase" guardrail would be far too loose.

### Two deliberate exemptions, and why they are not loopholes

- **`isCore` is exempt from guard 1.** The contract being asserted is "P1 changed
  core selection, not puzzle geometry".
- **`kind` and `phaseGroup` are exempt from guards 1 and 2.** This one is a
  correction to the plan, which specified `hash(nodeWaveIndices)` on the shipped
  board and described it as *"canonical, deterministic and core-independent"*.
  The first two hold; the third does not. `_canRemoveWithSet` short-circuits on
  `kind == NodeKind.locked` and on `phaseGroup > 0`, and lock and relay placement
  are themselves functions of the core set (`_markSpecialNodes` filters on
  `!n.isCore` and excludes core rows). Wave indices on the *enriched* board
  therefore move whenever P1 legitimately moves a lock — the guard would have
  fired on a correct P1.

  Guard 2 hashes the mechanic-stripped board instead, which restores the property
  the guard was meant to have: a pure function of geometry, genuinely invariant
  across P1. The enriched-board version is still recorded, as
  `enrichedSolutionHash`, alongside `mechanicHash` and `coreSetHash` — so lock
  and relay movement is **visible in the diff without being fatal**.

**One intended side effect, pre-recorded so it is not mistaken for a regression:**
T1.4 moves Easy sector 3+ from `coreCount: 0` to `1`, which stops `directiveFor`
falling back from `cascade` to `swift`. Star goals change on those levels. That is
correct, and no guard watches `directive`.

---

## Post-P1 classification (§e)

Machine-computed per board, mutually exclusive, as a decision tree over the
baseline→current deltas (`classifyBoard`, unit-tested in the guards file):

```
geometry, solution structure, or node count moved?  → VIOLATION  (result invalid)
tapsToWin ≥ mode floor?
  ├─ yes, core set moved                            → FIXED
  ├─ yes, core set unchanged                        → INCIDENTAL   (got lucky — investigate)
  └─ no
      ├─ ceiling < floor                            → UNFIXABLE    (geometric; needs an escape valve)
      ├─ captureRate ≥ 0.90                         → SELECTOR-OPTIMAL, BOARD-LIMITED
      └─ captureRate < 0.90                         → SELECTOR-FAILED   (the real bug)
```

`Q1: 34 FIXED / 4 UNFIXABLE / 2 SELECTOR-FAILED` is a work order.
`p50 6 → 10` is a rumour.

The 0.90 threshold (`kBoardLimitedCaptureThreshold`) is fixed here, before P1
exists, so it cannot be moved to reclassify an unwelcome result.

---

## Hard gates vs reported signals (§f)

| Class | Quantity |
|---|---|
| **Hard gate** | Medium ≤ 6-tap share < 5 % · Medium min `tapsToWin` ≥ 6 · Easy ≤ 6-tap = 0 % · Hard p50 within ±1 of 10 |
| **Hard invariant** | geometry identity · solution identity · node-count equality · 600/600 device autoplay |
| **Reported, not gated** | Medium p25/p50/p75/p95 · `captureRate` per quintile · `coreCriticalDepth` · `coreIsolation` · `maxSingleTapCascade` · gen latency · core-selection path |

**Medium p50 12–14 is a design aspiration, not an acceptance gate.** Doubling p50
from a measured 6 is a large prescribed move, and the cheapest way to reach it is
node-count inflation — precisely the impostor guard 3 exists to catch. If P1
lands at p50 9–10 with ≤ 6-tap at 3 % and playtests feel good, that is a success
and will not be broken to chase 12.

---

## Anti-overfit discipline (§g)

```
freeze corpus → T1.1–T1.4 → evaluate frozen corpus
              → canary's kReportSampleIds (never seen by selection)
              → one fresh draw → final validation
```

---

## Files

| Path | Contents |
|---|---|
| `test/…/adversarial_corpus.dart` | frozen id literals, view / quintile / severityRank / freeze-time nodes |
| `test/…/adversarial_corpus_selection_test.dart` | the one-shot selection run — provenance only |
| `test/…/adversarial_corpus_baseline_test.dart` | generates, measures, writes these CSVs; **asserts no quality** |
| `test/…/adversarial_corpus_guards_test.dart` | the three guards + the §e classifier's unit tests |
| `test/…/adversarial_corpus_report.dart` | hashes, ceiling wiring, statistics, classification |
| `test/…/core_depth_ceiling.dart` | the §d achievable-depth ceiling |
| `*_baseline.csv` | the frozen baseline, versioned headers |

### Regenerating

```
flutter test --tags report test/game/levels/generation/adversarial_corpus_baseline_test.dart
```

Roughly 20 s for 300 boards. **This overwrites the committed baseline.** After
P1 that is exactly how the diff is produced — but the Gen V1 baseline must be
committed to git first, or the before/after comparison is gone for good.

### CSV columns

Corpus bookkeeping — `view`, `quintile`, `severityRank`, `tapsToWin`,
`ceilingTapDepth`, `captureRate`, `headroom`, `belowFloor`, `unfixable`,
`geometryHash`, `solutionHash`, `enrichedSolutionHash`, `mechanicHash`,
`coreSetHash`, `corePath`, `coreSelectionAttempts` — followed by the full
`kBoardCsvHeader` block, so a baseline row is a superset of a `report_*_100` row
and both slice with the same tools. `readBaseline` looks columns up **by name**,
never by index.
