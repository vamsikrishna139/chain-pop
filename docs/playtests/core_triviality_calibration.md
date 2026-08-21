# Core triviality calibration — the T0.3 canary baseline

Measured 2026-08-19 while implementing T0.3 of `docs/IMPLEMENTATION_PLAN_V2.md`.
Gen V1, `generationVersion: 1`, `corpusVersion: 1`.

Purpose: pin down what "taps to win" means, and record the real F1 baseline, because the figures
quoted in the plan draft do not reproduce. P1 must be judged against numbers that do.

## The definition of `taps`

Defined once, as `BoardRow.tapsToWin` in `test/game/levels/generation/board_report_utils.dart`,
so the evidence layer and the gate cannot drift. It mirrors `ChainPopGame.checkWinCondition`
exactly:

| Board | Win condition | Taps |
|---|---|---|
| has cores (`totalCores > 0`) | last core extracted | `CoreMetrics.coreTapDepth` — the prerequisite closure of the core set |
| coreless | every node popped | `nodeCount` |

The second branch is load-bearing. Without it a coreless board reports **0** taps, which inverts
the truth: coreless boards are the *longest* ones, not the shortest. This matters directly for
Easy, which ships 0 cores at every sector until T1.4, and for Medium sectors 1–2.

## Measurement

Population: `kReportSampleIds` — 100 ids drawn from L1–L1500, seed 20260813 — in each of the
three modes. Two independent measurements, which **agree exactly**:

1. a fresh run with `timeBudget: null` (what the canary uses);
2. the committed T0.2 CSVs `report_{easy,medium,hard}_100.csv`, which were produced on the
   budgeted path at `kProdBudget` = 200 ms.

Percentiles use nearest-rank, `((n-1)*f).round()`, matching `printSummary`.

| Mode | n | min | p50 | p95 | max | ≤6-tap share | core-win boards |
|---|---|---|---|---|---|---|---|
| Easy | 100 | 8 | 11 | 14 | 14 | **0.0%** | 0 / 100 |
| Medium | 100 | 2 | 6 | 21 | 25 | **66.0%** | 80 / 100 |
| Hard | 100 | 6 | 10 | 15 | 23 | **1.0%** | 100 / 100 |

## Plan-stated vs measured

| Quantity | Plan said | Measured | |
|---|---|---|---|
| Medium ≤6-tap share | 44% | **66%** | ✗ |
| Medium min taps | 2 | 2 | ✓ |
| Hard p50 taps | 11 | **10** | ✗ |
| Hard min taps | 6 | 6 | ✓ |
| Easy ≤6-tap share | 0% | 0% | ✓ — but for the wrong reason: 0 cores, not good design |
| Easy p50 taps | ≥ 9 | 11 | ✓ |

**F1 is worse than the plan states, not better.** Two thirds of sampled Medium boards are won in
six taps or fewer.

### The 44% is not reproducible

Tried against every plausible encoding of "taps" on the Medium corpus:

| Candidate definition | n | min | p50 | ≤6-tap share |
|---|---|---|---|---|
| `coreTapDepth`, `nodeCount` fallback (**adopted**) | 100 | 2 | 6 | 66.0% |
| `coreTapDepth` raw, coreless counted as 0 | 100 | 0 | 4 | 86.0% |
| `coreTapDepth`, core-win boards only | 80 | 2 | 5 | 82.5% |
| `waveDepth` | 100 | 3 | 5 | 92.0% |
| `criticalUnlockDepth` | 100 | 3 | 4 | 98.0% |
| `nodeCount` (clear-all cost) | 100 | 13 | 17 | 0.0% |

None yields 44%. It is discarded as a baseline on the same grounds §P2 discards the
non-reproducible topology class count `14`.

## Consequences for the canary

- **Hard guard centred on 10**, tolerance unchanged at ±1, giving a symmetric window [9, 11].
  Centring on the quoted 11 gave [10, 12]: it would have permitted a genuine upward drift to 12
  while flagging a benign 9.
- **Medium's P1 target is a larger move than the plan implies** — p50 must go from 6 to 12–14, and
  the ≤6-tap share from 66% to under 5%.
- **Easy's two assertions pass today for the wrong reason.** With 0 cores every Easy board is a
  clear-all win costing `nodeCount` taps, so the floor is trivially satisfied. They become real
  gates the moment T1.4 introduces a core, which is precisely why the plan orders T1.4 after
  T1.2 — the tap floor is Easy's *only* quality gate.

## Determinism note

The canary runs unbudgeted (`timeBudget: null`). On the budgeted path elapsed wall-clock decides
control flow — the production nondeterminism the T0.0a closure audit explicitly scoped out of the
contract — so a gate asserting distribution statistics under a budget would be machine-dependent.
The two paths happen to agree exactly here, but the gate must not depend on that continuing to
hold.

## The shallowest Medium boards

The F1 population, for P1 to be judged against. Note the pattern: sector-2 boards with a single
core sitting 2–3 taps deep on a 14–22 node board, i.e. `coreTapFraction` near 0.10.

| Level | Sector | taps | nodes | cores | coreTapFraction | coreCriticalDepth | waves |
|---|---|---|---|---|---|---|---|
| L1209 | 2 | 2 | 18 | 1 | 0.11 | 2 | 4 |
| L193 | 2 | 2 | 14 | 1 | 0.14 | 2 | 3 |
| L212 | 2 | 2 | 22 | 1 | 0.09 | 2 | 4 |
| L249 | 2 | 2 | 22 | 1 | 0.09 | 2 | 4 |
| L1127 | 2 | 2 | 17 | 1 | 0.12 | 2 | 3 |
| L1133 | 2 | 2 | 20 | 1 | 0.10 | 2 | 5 |
| L192 | 2 | 3 | 20 | 1 | 0.15 | 3 | 5 |
| L224 | 2 | 3 | 22 | 1 | 0.14 | 3 | 6 |
| L236 | 2 | 3 | 13 | 1 | 0.23 | 3 | 4 |
| L1277 | 3 | 3 | 22 | 2 | 0.14 | 2 | 4 |
| L789 | 7 | 3 | 16 | 2 | 0.19 | 3 | 6 |
| L1186 | 2 | 3 | 21 | 1 | 0.14 | 2 | 4 |

Hard's single ≤6-tap board is L366 (sector 3, 6 taps, 25 nodes, 3 cores, `coreTapFraction` 0.24) —
at the boundary, not a pathology, and the reason the Hard guard asserts `minTaps >= 6` rather
than something stricter.
