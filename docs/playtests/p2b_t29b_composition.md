# T2.9b — the Medium composition regression. **Partly fixed; gate still red.**

**Date:** 2026-08-22 · **Tree:** T2.6 + T2.7 + relay fix + T2.9b
**Authoritative instrument:** `composition_calibration_test` (`--tags report`)

---

## Where it stands

| shipped composition p10 | post-P2 | after T2.6+T2.7 | **after T2.9b** | gate |
|---|---:|---:|---:|---:|
| Medium | 0.6514 | 0.6181 | **0.6269** | **≥ 0.63** ❌ |
| Hard | 0.6948 | 0.6764 | 0.6764 | ≥ 0.65 ✅ |

**Medium is still 0.0031 under the floor.** About a quarter of the gap closed.

## The structural finding, which matters more than the fix

Composition by exit path, Medium L1–300, before T2.9b:

| exit path | n | composition p10 | below 0.63 |
|---|---:|---:|---:|
| **`non-novel`** — the *last resort* | 76 | **0.7201** | 3 |
| `in-band` | 175 | 0.6016 | 26 |
| `novel-out-of-band` | 49 | **0.5615** | **18** |

**The last-resort path is the best-composed path in the generator.** It is the
only exit that selects purely on composition — `visual.score > nonNovelComposition`
— whereas `in-band` ranks composition behind silhouette diversity and banded,
and `novel-out-of-band` picks the best of a small, low-quality pool.

So P2b's central goal and the T2.4b floor are **anti-correlated by
construction**. Driving `non-novel` exits down — the DoD's headline item — moves
levels off the composition-maximising path by definition. This is not a bug
introduced by T2.6/T2.7; it is a property of the exit ordering that was
invisible while 95% of levels took the fallback.

## What T2.9b changed

Exit priority is `in-band` > `novel-out-of-band` > `non-novel`, which ranks
novelty above both the band and composition. On the measured evidence that
ordering is backwards on quality for the middle path: 16% of Medium levels were
producing 38% of the sub-floor boards.

T2.9b makes `novel-out-of-band` **yield to the non-novel fallback when its own
candidate is below the composition floor and the fallback's is above it**. Both
paths ship an out-of-band board either way, so the band is not traded — only
novelty is, and only where the novel board is measurably badly composed and a
better-composed alternative is already in hand.

| Medium | before | after |
|---|---:|---:|
| sub-floor boards | 47/300 | **36/300** |
| `novel-out-of-band` sub-floor | 18/49 | **5/38** |
| `non-novel` exits | 82 | 97 |
| rankable / level | 1.02 | 0.99 |

**Hard is untouched** — 124 `in-band` / 166 `non-novel` / 10 `novel-out-of-band`,
identical, and none of its 10 novel-OOB boards were sub-floor. The DoD's
`non-novel` budget is a Hard budget, and this does not spend it.

## Why it is not enough, and what is left

The remaining sub-floor pressure is on the **`in-band`** path: 27 of 173 Medium
boards, essentially unchanged by T2.9b (26 → 27).

An in-band ranking key was tried first — "meets the floor" placed above
silhouette diversity — and was **measured inert and reverted**: the shipped p10
did not move by a single digit. The reason is supply, not ordering. Medium has
≤1 rankable candidate on 71% of levels, so on the levels that ship a sub-floor
in-band board there was no better in-band candidate to promote. A comparator
can only reorder what exists.

That leaves three options, and the choice is a design decision rather than a
measurement:

1. **Let a sub-floor in-band candidate lose to an above-floor non-novel one.**
   Symmetric with T2.9b and would likely clear the gate. Cost: trades
   *band-correctness* for composition, which is a materially bigger concession
   than trading novelty — the band is the difficulty contract.
2. **Re-derive the T2.4b floor on the new population.** Defensible, because
   "shipped p10" is a descriptive statistic of the old 95%-fallback selection
   regime rather than an independent quality bar. Also the exact circularity
   trap flagged for min-Hamming in T2.10b, so it needs the same scrutiny.
3. **Fix it upstream** — generate fewer candidates that compose badly, rather
   than choosing better among bad ones. The `components` work. Largest scope,
   and the only option that raises the floor rather than reallocating it.

## Method note

Do **not** read composition p10 off `LevelGenerator.visualScoresAccepted`: it is
capped by `_kVisualScoreSampleCap` and never cleared by `resetCounters`, so it
holds the first N accepted boards and reads identically across unrelated
variants. Recomputing `evaluateVisualComposition` over the shipped sweep also
gives a slightly different figure from the calibration test (0.6153 vs 0.6269),
so quote the calibration test — it is the instrument the gate was set on.
