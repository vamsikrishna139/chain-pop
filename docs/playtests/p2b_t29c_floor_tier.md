# T2.9c — composition floor as a lexicographic in-band tier. **NO-GO, reverted.**

**Date:** 2026-08-22 · **Tree:** T2.6 + T2.7 + relay fix + T2.9b
**Instrument:** `composition_calibration_test` (the gate), plus a temporary
`floorTierDecided` / `inBandComparisons` counter pair added to answer the one
question the first attempt could not.

---

## What was asked for

Not weight tuning — a **lexicographic tier**: among candidates that already
satisfy the difficulty band *and* the novelty gate, prefer any candidate that
clears its tier's calibrated composition floor over any that does not, ahead of
silhouette diversity and every other engagement term. A preference, never a
guarantee: when no candidate clears the floor, every comparison ties and the
existing order decides.

This preserves the difficulty contract by construction. `_compareInBandCandidates`
only ever sees in-band candidates, so a well-composed **out-of-band** board can
never displace a sub-floor in-band one — it never reaches the comparator.

## What happened

**The tier fires.** It is not inert as a mechanism:

| | levels with ≥2 in-band candidates | comparator calls | decided by the floor tier |
|---|---:|---:|---:|
| Medium | 79 / 300 | 168 | **29 (17%)** |
| Hard | 35 / 300 | 52 | 9 (17%) |

**And it changes nothing measurable:**

| | T2.9b only | **+ floor tier** |
|---|---:|---:|
| Medium composition p10 | 0.6269 | **0.6269** |
| Medium p25 / min | 0.6916 / 0.4567 | **0.6916 / 0.4567** |
| Hard composition p10 | 0.6764 | **0.6764** |
| Hard exit paths | 124 / 166 / 10 | **124 / 166 / 10** |
| Medium exit paths | 174 / 39 / 97 | **174 / 39 / 97** |
| Hard rankable / level | 0.56 | **0.56** |

Every composition percentile and every funnel number is identical, while the
tier is demonstrably changing which candidate wins on ~29 comparisons.

## Why

**The bottom decile is supply-limited, not ordering-limited.** p10 is the 30th
worst board of 300. The tier can only help on a level where an above-floor
in-band alternative already existed — and on those levels the shipped board was
not in the bottom decile to begin with. The levels that populate the bottom
decile are the ones where **every** in-band candidate is sub-floor, and there
the tier ties by construction.

A comparator can only reorder what exists. Medium has ≤1 in-band candidate on
**221 of 300 levels**; the ordering layer simply is not where the bottom decile
is decided.

## Decision

**Reverted.** It moves boards — 29 changed comparisons — and buys nothing
measurable, which before a freeze is strictly negative. Same rule applied to
T2.8: a change that does not move its target is reverted rather than kept for
tidiness or for principle.

`kCompositionFloor` stays, because T2.9b's `novel-out-of-band` yield uses it and
that one *did* move its target (Medium sub-floor 47 → 36, p10 0.6181 → 0.6269).

## What this settles

The reviewed plan pre-committed the branch:

> If B gets 0.618 → ≥0.63 while keeping non-novel exits and rankable healthy —
> ship it. If even strong composition preference cannot recover the gate because
> of pure supply, stop, document the ceiling.

**The ceiling is documented.** Ranking-layer repair has now been attempted twice
— once as a low comparator key, once as a top lexicographic tier with the
instrumentation to prove it fired — and the gate does not move. The remaining
gap is 0.0031 and it lives entirely in levels with no better candidate to pick.

That leaves exactly two options, both previously named, and the choice is a
design decision:

1. **Re-derive the T2.4b floor on the new population**, with the same scrutiny
   applied to the Hamming threshold in T2.7 — the floor is a descriptive
   statistic of the old 95%-fallback regime, not an independent quality bar.
   The circularity risk is real and must be argued explicitly, not edited
   quietly.
2. **Upstream `components`** — generate fewer candidates that compose badly,
   rather than choosing better among bad ones. The only route that raises the
   floor instead of reallocating it, and the largest scope.

**Not available:** softening `components` directly (closed by T2.4c), relaxing
CUD (closed by T2.9a, structurally), letting an out-of-band board displace an
in-band one (spends the difficulty contract), or reverting T2.6/T2.7.
