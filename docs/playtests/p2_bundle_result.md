# P2 — the bundle result

**Landed 2026-08-21 on `new_improvements`.** T2.1 + T2.3 + T2.4c as one
re-baselining event, behind T2.0. **T2.2 is a no-go**, and the part of it that
survived runs opposite to the direction the plan proposed.

Evidence: `p2_variety_pre_bundle.md` (before), `p2_variety_post_bundle.md`
(after), `composition_calibration.md` (the T2.4b gate, re-measured),
`adversarial_baseline/p1_final/` (the pre-bundle corpus capture).

---

## What shipped

| task | status |
|---|---|
| **T2.1** — jitter to the nine builders that dropped it | shipped, from `T2.1_parked.patch` |
| **T2.2** — `minCells` 25 -> 15 | **NO-GO.** Broke Hard's node floor. A different, opposite correction shipped in its place |
| **T2.3** — `kMaskAreaSlack` 1.15 -> 1.5 + organic archetypes exempt | shipped |
| **T2.4c** — four composition rules reject -> rank | shipped, **with `components` re-hardened** per the plan's own risk table |

Corpus re-pinned once: `6a19bb9b24d846e3` / 164,846 bytes ->
`52f44d1b347398a1` / **165,623**. `level_seed_test` and
`milestone_identity_test` green throughout — no seeded or milestone board moved.

---

## T2.2 — rejected, on measurement

The plan proposed flooring the mask at `max(8, (minNodes * 0.6).round())` — 15
on Hard — arguing "the mask only needs room for the target, and
`_pickTargetNodeCount` already clamps `hi = min(profile.nodeCount.max,
mask.length)`".

The premise is true. The conclusion does not follow, **for the third time in
this plan**: that clamp does not reject an undersized mask, it silently lowers
the target through the floor, because `lo = max(profile.nodeCount.min,
minNodes)` is 25 on Hard and the routine returns `hi` when `hi <= lo`.

Measured over Hard L1-200:

| `kMaskCellFloorRatio` | levels under the 25-node floor | smallest board |
|---|---|---|
| 0.6 (as specified) | **34 / 200** | 15 nodes on a 16-cell mask |
| 1.0 (shipped) | **0 / 200** | — |

Hard's node floor is load-bearing for the evaluator's FSR-vs-nodeCount cap and
the per-level perf budget. What 0.6 bought did not come close to paying for
that: lattice share 72.2% -> 69.2%, Hard L45-56 rect boards 4 -> 2, and Hard
topology classes 38 -> 33, i.e. *worse* on the DoD's own headline measure.

`kMaskCellFloorRatio` ships as a named constant at 1.0 so the experiment is
re-runnable rather than re-arguable.

### The correction that did ship — in the opposite direction

The floor was `config.difficulty.minNodes`. That is not what a board needs.
On Medium, `minNodes` is 10 while the profile band starts at **14**, so a mask
of 10-13 cells cleared the floor and then produced a board *below its own
difficulty band*.

Latent until T2.1, because masks that small were barely reachable before jitter
reached the nine builders. Afterwards **L194/medium shipped 13 nodes and was won
in 3 taps**, taking `core_triviality_test`'s F1 gate red — the gate P1 exists to
hold, and the only P1 result this bundle disturbed.

The floor is now `max(profile.nodeCount.min, difficulty.minNodes)`: Medium
10 -> 14, Easy 4 -> 8, Hard unchanged at 25. F1 restored to Medium min 7 taps,
0% at <= 6.

**Seeded plans keep the old floor**, deliberately. A seed carries its own
`difficultyTier` and it need not match the mode the slot ships on —
`milestone-diamond` is a Hard-tier seed emitted on Medium slots. Flooring by the
seed's tier demanded 25 cells of a Medium 8x8 diamond that has ~24 and collapsed
slots 325, 625, 825 and 925 to the rectangle fallback. The seeded path also does
not have the defect being fixed: it clamps `target.clamp(1, mask.length)` itself.

---

## T2.4c — two defects, both caught by pre-committed controls

**1. The p10 floor did its job on the first attempt.** Shipping all four rules
soft put Medium's shipped p10 at 0.4625 and Hard's at 0.5844, against gates of
0.63 / 0.65. The plan's risk table had already named the remedy, before anyone
ran it: *"Re-reject `components` only; keep others soft."* Applied exactly as
written rather than reinvented after seeing the numbers.

**2. A hard rule was silently unreachable.** The reject reason is resolved in a
fixed priority order — aspect, blobVsGrid, occupancy, singleton, components —
and the first cut of T2.4c scanned that one order and returned at the first
failure. That is correct only while every rule is hard. With some soft, a board
failing `singleton` (soft, 4th) **and** `components` (hard, 5th) was named
`singleton`, admitted, and the hard rule never fired.

The tell was that re-hardening `components` did not move its p10 off 0.00 while
Hard's shipped `singleton` violations jumped 5 -> 36: the scattered boards were
still shipping, wearing a different label. Hard rules are now resolved in their
own pass, across the whole set, before any soft rule may name the board. Pinned
by *"a hard rule rejects even when a soft rule fails first in priority order"*
in `visual_composition_test.dart`.

Fixing it also cleared four unrelated-looking failures at once — determinism
probes 1, 3 and 4, and the Daily in-band rate, which had fallen to 80%.

### Final gate

| mode | gate | before bundle | after |
|---|---|---|---|
| Medium | >= 0.63 | 0.6327 | **0.6514** |
| Hard | >= 0.65 | 0.6595 | **0.6948** |

---

## The candidate telemetry, and the question it was added to answer

Plan §T2.0 deferred four counters to this bundle to settle: *did the diversity
ledger stop influencing selection, or did the generator stop producing eligible
alternatives?* They are now on `LevelGenerator` — `candidateCount`,
`novelCandidateCount`, `acceptedNovelCandidateCount`, `fallbackReasonCounts`.

Read on L44 Hard, three consecutive generations on one generator:

```
run 0: cand=2 novel=2 acceptedNovel=0 path={novel-out-of-band: 1}
run 1: cand=2 novel=0 acceptedNovel=0 path={non-novel: 1}
run 2: cand=2 novel=0 acceptedNovel=0 path={non-novel: 1}
```

**The generator stopped producing alternatives.** The ledger is working
correctly and visibly — it demotes the board from `novel-out-of-band` to
`non-novel` the moment the fingerprint enters its window. It simply has nothing
else to choose: 8 of the 10 K-loop iterations are rejected before the ledger
ever sees them, and the 2 survivors are the same board.

That is a real finding about where to spend effort next, and it is the opposite
of the reading the symptom invites.

---

## What P2 did not achieve, and why

Four of the nine DoD items are missed, and they are not near-misses: lattice
share 72.0% against < 50%, longest same-silhouette run 6 against <= 3, worst
5-level window 1 family against >= 2, rolling min-Hamming median 3.00 against
>= 5.

All four are properties of the **emission sequence**, and all four are dominated
by two things the bundle never touched:

* `_pickSilhouette`'s explicit **40% dense-silhouette bias** for Hard/Expert
  (`director.dart`), which decides what is asked for before any of this runs;
* the diversity ledger's **3-bit silhouette field**, which is what the Hamming
  median measures.

T2.3 removed the *substitution* pressure — attempt-level rectangle
substitutions 6,067 -> 2,460, shipped fallback 0%, Hard topology classes
22 -> 38 — and that is the ceiling of what a mask-geometry change can reach.
Moving the sequence measures means changing what the Director asks for, which is
a `_pickSilhouette` / ledger task, not a mask task. It is not in P2 and is not
smuggled into it here.

**Three of the DoD's own "from" figures do not reproduce on the shipping tree**
(lattice 68% vs 73.0% measured, fallback 8% vs 0.0%, L45-56 five vs nine). Both
numbers are reported throughout rather than the plan's silently substituted.
