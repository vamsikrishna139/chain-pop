# F1 + Daily determinism — correctness stabilisation

**Date:** 2026-08-22 · **Branch:** `new_improvements` · Nothing committed.
**Suite after:** 844 passed, 2 failed — both the deferred, unreachable relay
property fixtures.

---

## Priority 1 — F1: a Medium board winnable in 3 taps

### Trace

One board in the sample, not a distribution collapse: `shareAtMost(6) < 0.05`
still passed; only `minTaps >= 6` failed.

```
trivial boards (<=6 taps), shallowest first:
  L236  S2  taps=3  nodes=16  cores=1  tapFrac=0.19  coreCrit=3  waves=3
```

Core-selection telemetry for that board:

```
mode=medium path=relaxedBand requested=1 selected=1
floorRequired=8 floorAchieved=3 rungs=3 escalated=false coreIds=[6]
```

### Root cause

`_ensureCoreQuality` **knew it had failed**. `required = max(7, ceil(0.45 x 16))
= 8`; it repicked over all three widening rungs, escalated the core count one at
a time to Medium's `maxCores` of 3, and the deepest placement any of that could
reach was **3**. It then returned "best seen" and the board shipped as a
three-tap win.

The board is geometrically flat — `ceiling < floor`. No core placement on it can
satisfy the invariant, so no amount of repicking is the answer.

**§12 of the plan pre-committed this exact remedy for this exact situation:**

> *Most Q1 boards are `ceiling < floor` → T1.2's bounded repick cannot fix
> these. Move the remedy upstream into candidate rejection — do not let it
> silently ship "best seen".*

### Fix

`enrichLevel` gained a per-call `onCoreSelection` channel (the existing
`CoreSelectionTelemetry.sink` is a global static that tests set for their own
purposes, so a caller needing the outcome for a *decision* cannot share it).
The generator's procedural path rejects the candidate and retries when the
floor is unmet.

**Measured before implementing:** **1 of 184** Medium enrichment calls across
L1–300 misses the floor; Hard and Easy never do. So the rejection costs the
K-loop essentially nothing — which mattered, because candidate supply is P2b's
binding constraint.

**Procedural path only.** The seeded milestone path deliberately does not
reject: a lost seed is a lost milestone (`seedFallthroughCounts`), and the same
asymmetry already applies to the node floor there for the same reason.

### Regression fixture

`core_floor_rejection_test.dart` asserts the **mechanism**, not the level id.
`core_triviality_test` asserts the outcome, and an outcome test can go green by
luck — a corpus where no flat board happens to be selected passes it while the
defect is fully present, which is the state the tree was in until T2.6/T2.7
made such a board reachable. The fixture therefore also asserts
`coreFloorRejects > 0`, so it cannot pass vacuously if the rejection is removed.

---

## Priority 2 — Daily determinism

### Root cause, already written down in the codebase

`level_manager.dart:92` documents it exactly:

> *"[generator] is static, so the synchronous path generates the Daily from
> whatever session state campaign play left in the diversity ledger and
> silhouette tracker. Those are inputs (see the T0.0a closure audit), so the
> Daily was never actually 'the same layout for every player on that date'."*

That comment was attached to `getDailyChallengeAsync`, which fixes it **for the
async path only**, via a worker isolate starting from fresh statics. The
synchronous path kept the bug — and it is both a public API and the async
path's own fallback when `Isolate.run` throws, so the isolate could never be
the correctness story.

**Why it surfaced now.** While the novelty gate was unreachable, `isNovel` was
almost always false and every call fell through to the same last-resort
candidate, so the board looked stable. T2.6/T2.7 made the gate reachable and
two calls for one date began returning different boards. The determinism was
being held up by a broken gate.

### Fix

`_generateDaily` uses a **fresh generator** rather than the static one. Smallest
change that makes the contract hold on both paths, and it demotes the isolate
to a latency optimisation rather than a correctness requirement.

### Regression fixture

`daily_determinism_test.dart` asserts the contract that matters to players:
same date, **different campaign histories**, byte-identical board — plus that
repeated calls do not drift, since each call also records into whatever state
it used. `level_manager_test`'s existing "same date twice" is weaker: it calls
twice from one state.

---

## Step 4 — P2b metrics re-measured on the stabilised tree

Both fixes change the candidate population, so the old numbers were stale.

| Hard | before stabilisation | after |
|---|---:|---:|
| `in-band` / `novel-OOB` / `non-novel` | 124 / 10 / 166 | **124 / 10 / 166** |
| rankable / level | 0.56 | **0.56** |
| no-choice levels | 88.3% | **88.3%** |

| Medium | before | after |
|---|---:|---:|
| `in-band` / `novel-OOB` / `non-novel` | 174 / 39 / 97 | **172 / 43 / 95** |
| rankable / level | 0.99 | **1.02** |
| no-choice levels | 73.7% | **72.0%** |

Fingerprint and novelty, Hard:

| | after T2.6/T2.7 | after stabilisation |
|---|---:|---:|
| effective entropy | 18.82 / 26 | **19.14 / 26** |
| rolling min-Hamming median | 5.00 | 5.00 |
| share under distance 5 | 47.3% | **38.7%** |

Composition floor gate: **green** on both tiers (Medium 0.577, Hard 0.65).

Nothing regressed; Medium improved slightly, which is consistent with F1
rejecting flat boards that were also poor on other axes.

---

## Remaining before the single re-baseline

- **20-board visual review** — needs a human.
- **T2.10 target renegotiation** — the sequence-diversity DoD items.
- Then: one re-baseline, re-pin guards, tag Gen V1.

Deferred, with reasons recorded: the two relay property fixtures (unreachable —
every shipped board carries 0 or 1 relays), and upstream `components` work
(post-freeze).
