# T2.8 — the fallback-record fix, measured alone. **NO-GO, reverted.**

**Date:** 2026-08-21 · **Branch:** `new_improvements`
**Instrument:** `p2_selection_funnel_report_test.dart`, L1–300 per mode, production budget
**Baseline:** [`p2b_funnel_baseline.md`](p2b_funnel_baseline.md) (T2.5)
**Outcome:** reverted. The behaviour is back to recording; only the comment changed.

---

## The change

`level_generator.dart` carried a comment claiming the `non-novel` last-resort
path emits *"WITHOUT recording it in the ledger — this keeps the window's 'all
pairs distance ≥ 5' invariant intact"*, and then recorded twenty lines later, on
**286 of 300 Hard levels**.

The P2b plan called this the highest-leverage single suspect: every near-duplicate
written into the 20-wide window should make the next candidate less likely to
clear the threshold, sending the next level down the same branch — a
self-reinforcing low-variety fixed point held in place by one line.

T2.8 removed the `record()` call, changing nothing else.

## The result

| | Hard | Medium | Easy |
|---|---|---|---|
| `non-novel` exits | 286 → **285** | 256 → **275** | 239 → **264** |
| novel candidates / level | 0.07 → **0.06** | 0.27 → **0.20** | 0.57 → **0.42** |
| rankable / level | 0.05 → **0.05** | 0.17 → **0.13** | 0.06 → **0.04** |
| no-choice levels | 99.7% → 99.3% | 97.0% → 97.7% | 99.7% → 99.7% |
| `in-band` exits | 12 → 13 | 36 → **28** | 16 → **11** |

**Flat on Hard, and worse on both other modes** — Medium's non-novel exits rose
by 19 and its rankable rate fell by a quarter.

The plan pre-committed the response before the run: *"if `non-novel` exits do
not fall, the change did nothing and should be reverted rather than kept for
tidiness."* Applied as written.

## Why it backfires

Skipping the record stops the window turning over. It does not become a window
of *novel* boards; it becomes a window of *older* boards — and since Hard
fingerprints are strongly correlated regardless of age, an aged entry is no
easier to clear than a fresh one. What is lost is the eviction churn: recording
a near-duplicate at least displaced the oldest entry, which occasionally removed
whichever neighbour was blocking the next candidate. T2.8 removed that with
nothing in exchange.

## What this costs the diagnosis

The feedback loop was the plan's named prime suspect and **it is not the cause**.
It was a real code/comment disagreement, but the comment was the wrong half —
the code was doing the more useful thing by accident. The comment has been
corrected in place to describe what the code does and to record this
measurement, so the next reader does not re-run the experiment.

This is the second time in this project that a one-line change with an obvious
story has failed under isolated measurement — after `T2.1 is free` and
`T2.2 minCells 0.6`, it is now three. Isolating it cost one sweep.

**Consequence for the bundle:** with T2.9 demoted by T2.5's Easy control and
T2.8 reverted here, the entire P2b thesis now rests on T2.6 + T2.7 — the
fingerprint's usable entropy and the threshold derived from it. There is no
second lever behind them.
