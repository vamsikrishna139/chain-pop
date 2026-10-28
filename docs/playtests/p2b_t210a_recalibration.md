# T2.10a — re-deriving the composition floor. **Landed, with a control run.**

**Date:** 2026-08-22 · **Instrument:** `p2b_composition_recalibration_test.dart`
**Method:** fresh corpus → bootstrap lower tail → held-out validation → **plus a
pre-P2b control on the same windows**, which is the step that changed the answer.

---

## The control nobody asked for, and why it mattered

The plan was to re-derive because *the selection regime changed*. That premise
was only half right, and measuring it properly showed the other half.

Medium shipped composition p10, same three windows of one sequential campaign,
**pre-P2b tree vs post-P2b tree**:

| window | pre-P2b | post-P2b | P2b's cost |
|---|---:|---:|---:|
| L1–300 (discovery) | **0.6530** | 0.6153 | −0.0377 |
| L301–800 (calibration) | **0.6097** | 0.6008 | −0.0089 |
| L801–1300 (validation) | **0.6246** | 0.6057 | −0.0189 |

Hard, same treatment:

| window | pre-P2b | post-P2b |
|---|---:|---:|
| L1–300 | 0.6900 | 0.6632 |
| L301–800 | 0.6892 | 0.6754 |
| L801–1300 | 0.6720 | 0.6654 |

**The old Medium floor of 0.63 was never met outside L1–300, even before P2b.**
0.6097 and 0.6246 on the pre-P2b tree are both under it.

So 0.63 was **overfit to the first 300 levels**, not merely to the old
fallback-dominated regime. And P2b's real cost on Medium is **−0.009 to
−0.019**, not the −0.03 it appeared to be when L1–300 was the only window ever
measured.

**Two things I reported earlier were wrong and are corrected here.** The
"0.0031 gap" was an artifact of measuring only L1–300 — on the campaign the gap
against 0.63 is roughly ten times that. And the regression was attributed
entirely to the regime shift; about half of it is the window.

## The derivation

Calibration window L301–800, post-P2b, 500 boards. Bootstrap of the p10, 2,000
resamples:

| | p10 | bootstrap 95% CI | proposed |
|---|---:|---:|---:|
| Medium | 0.6008 | **[0.5880, 0.6164]** | **0.577** |
| Hard | 0.6754 | [0.6673, 0.6892] | 0.657 → *not taken* |

Floor = CI lower bound − **0.01**. The margin is one fifth of
`kCompositionRankBand`, so it is smaller than the granularity at which two
boards read as differently composed — it cannot hide a real regression — and it
is large enough to absorb corpus noise of the size the interval shows.

**Validated on the held-out L801–1300 window it was not derived from:** Medium
p10 0.6057 clears 0.577; 39 of 500 boards fall below.

## What changed, and what deliberately did not

- **Medium: 0.63 → 0.577.**
- **Hard: stays 0.65.** The same method proposed 0.657, which would *tighten* a
  gate that is passing on every post-P2b window (0.6632 / 0.6754 / 0.6654), as a
  side effect of recalibrating a different tier. A recalibration is not a
  licence to move gates that are green.

## The gate is now a test

Until now this "gate" was a number in the plan, checked by eye against a
`report`-tagged sweep that asserts nothing. It could not go red on its own — the
Medium breach was found by hand and could as easily have been missed.

`composition_floor_gate_test.dart` asserts it, on **L301–800, not L1–300**:
gating on the window a threshold was overfit to is how the overfit survives.

It is `slow`-tagged and generates 800 levels per mode (~62s), so it **gates
nothing on an ordinary `flutter test`** — the same weakness that let the relay
soft-lock reach a corpus. It is a **pre-freeze checklist item**, and that is a
real limitation rather than a solved problem:

```
flutter test --tags slow test/game/levels/generation/composition_floor_gate_test.dart
```

Currently green on both tiers.

## Anti-overfit rule, carried forward

The floor was derived on L301–800 and validated on L801–1300. **Do not tune any
selection variable against L301–800 from here on** — that would convert old
threshold overfitting into new threshold overfitting, which is the entire
failure this exercise exists to undo. L801–1300 stays the unseen set.
