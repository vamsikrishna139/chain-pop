# T2.5 — K-loop mortality baseline

**Date:** 2026-08-21 · **Branch:** `new_improvements` · **Tree:** post-P2 bundle
**Instrument:** `p2_selection_funnel_report_test.dart` (`--tags report`, asserts nothing)
**Population:** L1–300 per mode, production time budget, `LevelGenerator()` default
**Board movement:** none — `corpus_identity_test` and `level_seed_test` green.
Counters are write-only.

This is the reading every later P2b task is scored against. It is taken *before*
T2.8, so T2.8's isolated effect is measurable.

---

## The funnel

| | Hard | Medium | Easy |
|---|---:|---:|---:|
| K-loop iterations entered / level | 10.39 | 9.44 | 9.07 |
| candidates reaching the ledger / level | **2.51** | 3.39 | **9.04** |
| …judged novel / level | 0.07 | 0.27 | 0.57 |
| …**rankable** (in-band *and* novel) / level | **0.05** | 0.17 | **0.06** |
| levels where ranking had no choice (≤1 rankable) | **99.7%** | 97.0% | **99.7%** |

| exit path | Hard | Medium | Easy |
|---|---:|---:|---:|
| `in-band` — the ranked, chosen path | 12 | 36 | 16 |
| `novel-out-of-band` | 2 | 22 | 85 |
| **`non-novel` — the last resort** | **286** | 256 | 239 |
| `exhausted` (attempt retried) | 90 | 40 | 0 |

## K-loop mortality — where the iterations go

Every iteration entered exits through exactly one row. Conserved in all three
modes, which is what makes the table trustworthy.

| exit | Hard | Medium | Easy |
|---|---:|---:|---:|
| construction failed (build / solve / renegotiate) | 3.9% | 0.0% | 0.0% |
| FSR cap reject | 0.0% | 0.3% | 0.0% |
| composition HARD reject — `aspect` | 0.2% | 0.4% | 0.0% |
| **composition HARD reject — `components`** | **49.5%** | **63.1%** | 0.0% |
| **CUD floor reject** (out-of-band candidates only) | **22.3%** | 0.3% | 0.3% |
| reached the ledger | 24.1% | 35.9% | **99.7%** |

Attribution note: `visual.reason` names the first failing rule in the priority
order `aspect → blobVsGrid → occupancy → singleton → components`, hard or soft,
so on a hard reject it can name a *soft* rule that also failed.
`kHardCompositionRules` is `{aspect, components}` and `aspect` is first, so
`reason == aspect ⇒ aspect`, anything else `⇒ components`. This is the exact
trap T2.4c fell into and the reason the attribution is spelled out.

---

## What this changes

### 1. Two gates, not four causes — and neither is construction

`components` and the CUD floor account for **71.8% of Hard iterations**.
Construction failure, the intuitive suspect, is 3.9%. The P2b plan's T2.9
described "the dominant killer" without naming it; it is composition
connectivity, and on Hard the CUD floor is a large Hard-specific second.

### 2. Easy falsifies the supply thesis — this is the important result

Easy short-circuits `evaluateVisualComposition`, so **99.7% of its iterations
reach the ledger**: 9.04 candidates per level, **3.6× Hard's supply**.

It makes no difference. Easy's rankable rate is **0.06/level against Hard's
0.05**, and its no-choice rate is identical at 99.7%.

Novel-per-candidate holds in single digits regardless of supply:

| | Hard | Medium | Easy |
|---|---:|---:|---:|
| novel / candidate | 2.7% | 8.1% | 6.3% |

At Hard's 2.7%, reaching the DoD's **2.0 rankable per level** by supply alone
needs roughly **75 candidates per level**. The K-loop budget is 8.

**T2.9 (candidate supply) therefore cannot deliver the DoD, and is demoted from
a bundle lever to a contingency.** The binding constraint is the novelty gate
itself — T2.6 and T2.7 — exactly as the fingerprint entropy predicted. Easy is
the control that turns that from an argument into a measurement.

### 3. Easy fails differently, and it is not P2b's problem

Easy's novelty rate is 8× Hard's (0.57 vs 0.07 per level) yet its rankable rate
is the same, because **2,491 of its 2,713 ledger-reaching candidates are
out-of-band**. Easy loses at the band, not at novelty. Noted, not chased — the
player-facing variety complaint is about Hard.

### 4. The `components` lever is closed by prior evidence

The obvious reading of row 4 is "soften `components` to a penalty, per T2.9's
principle". T2.4c already ran that experiment: with all rules soft, Medium
composition p10 collapsed to **0.4625** against a 0.63 gate, which is why
`components` was re-hardened. Re-opening it needs a different mechanism than
the one already tried and rejected, not a second attempt at the same one.

---

## Caveat on reproducibility

`kloopBudgetBreaks` is wall-clock dependent (2 on one run, 0 on another), so
iteration totals move by a few counts between runs. Candidate, novel, and
rankable totals were identical across runs. Do not treat single-digit
differences in the iteration column as signal.
