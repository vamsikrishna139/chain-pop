# P2b — Make the variety land

**Goal, in player terms:** a player who plays ten Hard levels in a sitting should
not feel they played the same board ten times. That is the engagement problem
F4 named, and it is the one P2's bundle did not solve.

**Status of P2:** 5 of 9 DoD items met. Every *per-board* measure moved a long
way (Hard topology classes 22 → 38, gen p95 186 ms → 126 ms, mask fallback 0%).
Every *sequence* measure did not move at all — longest same-silhouette run
6 → 6, worst 5-level window 1 family → 1 family, rolling min-Hamming median
3.00 → 3.00, lattice share 73.0% → 72.0%.

That split is not a coincidence and it is not four separate problems.

---

## 0. The finding

> ### The generator's entire selection layer is inert. Boards do not get chosen; they get defaulted to.

Measured on Hard L1–300 at the production budget by
`p2_selection_funnel_report_test.dart` (committed with this plan; asserts
nothing, per §0.5 of the parent plan):

| stage | per level | total over 300 levels |
|---|---|---|
| K-loop iterations available | 10 | 3,000 |
| candidates reaching the diversity ledger | **2.51** | 752 |
| …that the ledger judges **novel** | **0.07** | **20** |
| …that are **rankable** (in-band *and* novel) | **0.05** | **14** |

| exit path actually taken | levels |
|---|---|
| `in-band` — the ranked, chosen path | **12** |
| `novel-out-of-band` | 2 |
| **`non-novel` — the last-resort fallback** | **286** |
| (attempts that exhausted and retried) | 90 |

**Ranking had no choice at all on 299 of 300 levels** (≤1 rankable candidate).

Every mechanism the codebase contains for producing variety selects among those
candidates: the diversity ledger's novelty gate, `SilhouetteSessionTracker`'s
`streakPenalty` and `diversityBoost`, T2.4c's composition ranking, and the
tempo / CUD / topology comparator. **All of it is dead code in practice on
Hard.** 95% of Hard campaign levels ship through a branch whose own comment
calls it "last resort".

This is why T2.1 and T2.3 moved the board measures and could not move the
sequence measures. Mask geometry decides what *a* board looks like. Selection
decides *which* board ships, and selection is not running.

### Why nothing is novel

`DiversityLedger.isNovel` requires Hamming distance **≥ 5** against every one of
the 20 entries in the window, rising to **≥ 8** when the visual family matches.
Measured achievable distance, same population:

```
rolling nearest-neighbour Hamming: min=0  p25=2  median=3.00  p75=5  p90=5  max=9
  share under the base threshold of 5 : 74.5%
  share under the same-family 8       : 99.0%
```

Hard is 72% geometric-lattice, so *the same-family threshold of 8 is the one that
usually applies* — and 99.0% of pairs fall under it. The gate is not strict; it
is unreachable.

### Why the distance is that small

The fingerprint has 26 bits and carries **15.8 effective bits on Hard**, but the
shortfall is not spread evenly — it is concentrated in fields that are pinned:

| field | bits | entropy on Hard | why |
|---|---|---|---|
| `waveDepth` bucket | 2 | **0.49** | buckets are `1–2 / 3–4 / 5–6 / 7+`; Hard waves are 5–8, so the high bit is **always 1** |
| `avgBF` bucket | 2 | **0.02** | buckets top out at `>5`; Hard BF is 5.4–8.5, so **both bits are always 1** |
| `dominantMotifId` | 3 | **0.07** | almost every Hard board reports no dominant motif |
| `visualFamily` | 3 | **0.90** | one of three bits is dead; 72% of boards share one family |
| silhouetteId | 3 | 2.84 | healthy |
| direction histogram | 4 | 3.44 | healthy |
| 3×3 spatial density | 9 | 8.03 | healthy |

**Nine of 26 bits contribute 0.58 bits between them.** The novelty threshold was
chosen for a 26-bit space; it is being applied to a ~16-bit one whose useful
dimensions are correlated with each other.

### And why it stays that way — the loop

`level_generator.dart:1240` says, of the non-novel fallback:

> *"Last resort: emit a non-novel candidate **WITHOUT recording it in the
> ledger**. This keeps the window's 'all pairs distance ≥ 5' invariant intact."*

Twenty lines later it calls `_diversityLedger.record(nonNovelFp!)`.

**The comment describes an invariant the code violates, on 286 of 300 levels.**
Every near-duplicate board that ships by fallback is written into the window,
which makes the next candidate less likely to clear the threshold, which sends
the next level down the fallback path too. The system is sitting in a
self-reinforcing low-variety fixed point, and it is held there by one line.

`DiversityLedger.record` only touches the ledger's own window and history —
`SilhouetteSessionTracker.record` is called separately from
`_commitPendingEmission` — so **not** recording here breaks nothing else. This is
the single highest-leverage suspect in this document. It is written up as a
suspect and not as a fix, because the whole point of this project's method is
that a one-line change with an obvious story still gets measured (§0.1, three
times over).

---

## 1. What this plan does *not* do

- **It does not touch mask geometry again.** T2.1 and T2.3 did their job; the
  per-board measures are met.
- **It does not re-open T2.2.** The mask floor question is settled and the
  jitter-range follow-up for `diamond` / `hollowDiamond` is tracked separately.
- **It does not chase "lattice share < 50%" as written.** See §T3.5 — that
  target is probably measuring the wrong thing, and pursuing it directly fights
  a deliberate earlier decision.

---

## 2. The tasks

Ordered by risk. **T3.0 is free. T3.1–T3.4 all move boards and land together as
one re-baselining event**, exactly as P2's bundle did. We are still pre-freeze,
so one more event is available — and it is the *last* one.

### T3.0 — Instrument the funnel · *zero behaviour change, zero seed impact*

**Mostly delivered already** as `p2_selection_funnel_report_test.dart`. Remaining:

**a. `_evaluatorRejectionCount` over-counts and must be split.** It increments on
the `!inBand` branch *even when the candidate then proceeds* to the novelty
check, so "2,371 evaluator rejections" is not a count of anything. Replace with
per-stage counters: `fsrCapRejects`, `compositionHardRejects`, `outOfBandNoted`,
`cudFloorRejects`. Without this we cannot say which gate is starving the funnel,
and every later decision here is a guess about that.

**b. Report the same funnel for Medium and Easy.** Everything above is Hard.
Medium ships 33 topology classes and may not have the problem at all; if it does
not, that is a control that tells us the cause is Hard-specific density.

**Gate:** `corpus_identity_test` green — counters are write-only (T0.0c).

---

### T3.1 — Give the fingerprint back its dead bits · *moves seeds*

**File:** `diversity_ledger.dart`

Re-bucket `waveDepth` and `avgBF` **per tier** instead of on one global scale.
The current cut points were chosen across all modes; on Hard they place every
board in the top bucket, which is how 4 bits come to carry 0.51.

Cut points must be **derived from the measured Hard distribution**, not guessed —
quartiles of the observed range, the same method T0.2 used to settle
`bboxFillBucket`.

**Balance:** this is a measurement change, so per T2.4's hard-won lesson it
**must not** be combined with a threshold change. T3.1 changes what the ruler
measures; T3.2 chooses where the line goes. One commit each.

**Expected:** +3–4 bits of live entropy in the fields where Hard boards genuinely
differ, raising achievable nearest-neighbour distance. **Not** assumed — the
gate is the measured median.

**Gate:** rolling min-Hamming median must rise above 3.00. If it does not, the
premise is wrong and T3.2 must not proceed.

---

### T3.2 — Recalibrate the novelty threshold · *analysis, then one constant*

Directly modelled on T2.4a/b/c, which is the part of P2 that worked.

1. **Observe.** With T3.1 in, re-measure the nearest-neighbour distribution.
2. **Calibrate.** Choose `hammingThreshold` and `sameVisualFamilyHammingMargin`
   from *that* distribution — a threshold that admits a defensible share of
   candidates rather than a round number. Commit the distributions to
   `docs/playtests/` before choosing, as T2.4b did.
3. **Act.** Change the constants.

**Balance:** a threshold that is too low makes novelty meaningless and the ledger
stops protecting anything. The floor: novelty must still reject a board that
differs only in silhouette id from a window entry — pinned by a fixture test.

---

### T3.3 — Stop the fallback poisoning the window · *moves seeds*

Make the code match the invariant its comment already claims: do not
`record()` on the `non-novel` path.

**Balance, and it is real.** The window then contains only boards that were
genuinely novel when emitted, which is what the "all pairs ≥ threshold"
invariant means — but it also means the window fills more slowly and can hold
stale entries longer. Measure both the sequence metrics **and** the funnel: if
`non-novel` exits do not fall, the change did nothing and should be reverted
rather than kept for tidiness.

**This is the change most likely to move the DoD numbers on its own.** It is
also the one most likely to surprise us, because 286/300 levels currently depend
on that branch.

---

### T3.4 — Widen the candidate supply · *moves seeds*

Two independent levers; measure each alone before shipping both.

**a. The archetype lock.** `lockedArchetype` fixes one archetype for all 10
K-loop iterations, "to prevent selection bias". The side effect is that every
candidate for a level is drawn from **one archetype's silhouette pool**, so
within-level silhouette diversity is capped by that pool before the ledger sees
anything. Proposal: keep the lock for the first *N* iterations (preserving the
anti-bias intent, which is real) and re-sample for the remainder. `N` chosen by
measurement.

**b. The retry budget.** `_evaluatorRetryBudget` is 10 and ~7.5 die per level.
P2 bought a lot of latency headroom — Hard gen p95 is **126 ms against a 260 ms
budget** — so a larger budget is now affordable in a way it was not before.
Measure the marginal yield: if iterations 11–16 produce no additional *rankable*
candidates, the budget is not the constraint and this lever is dropped.

**Balance:** latency. Hard gen p95 must stay ≤ 260 ms, and Daily must not
regress — that path has a device-ANR history (`20260819`).

---

### T3.5 — Renegotiate the two targets that are measuring the wrong thing

Not code. A decision, made on evidence, written down before the bundle is
scored — so that the scoring cannot be argued after the fact.

**a. "Hard lattice share < 50%" should be retired as a gate.**

The arithmetic says it is unreachable without undoing an earlier deliberate
decision. Expected lattice share decomposes exactly:

| source | expected Hard lattice share |
|---|---|
| archetype pools alone | **63.5%** |
| + the 40% dense-silhouette bias | **78.1%** |
| measured | 72.0% |

Four of the eight `SilhouetteId` values are lattice, and Hard's two
heaviest archetypes are `strongMotif` (weight 0.40, pool **4/5 lattice**) and
`cleanAuthored` (0.22, pool **4/4 lattice**). Getting under 50% requires
rewriting those pools — and they were written that way on purpose by Dense
Strategy Phase 1A/1C, to stop Hard boards being sparse and shapeless. That was
an engagement win and it should not be spent to move a number.

**More importantly, the metric hides what the player sees.** `silhouetteVisualFamily`
collapses 8 ids into 4 families, but each id renders through
`silhouetteShapePool` as many concrete outlines. Measured over 500 Hard levels:

| silhouette id | distinct outlines | family |
|---|---|---|
| asymmetric | 28 | organic |
| organicBlob | 27 | organic |
| **diamond** | **24** | lattice |
| ring | 16 | lattice |
| cross | 13 | lattice |
| corridor | 11 | corridor |
| archipelago | 8 | archipelago |
| **rectangle** | **4** | lattice |

**131 distinct outlines across 500 levels.** A player meeting 24 different
diamond-family outlines is not playing the same board 24 times. "72% lattice"
counts them as one thing.

**The exception is `rectangle`, and that is the real complaint** — 4 outlines,
18% of shipped Hard boards, and it is the plain full grid. That is what
"levels 45–56 all look the same" actually is.

**Proposed replacement gates, which track what a player perceives:**

- **Plain-rectangle share < 8%** on Hard (from 18.0%).
- **Distinct outlines in any rolling 10-level window ≥ 7** (a session's worth).
- Lattice share stays **reported as a diagnostic**, gating nothing.

**b. "Rolling min-Hamming median ≥ 5" is not an independent target.**

5 *is* the ledger's own base threshold. The DoD is asking the fingerprint
distribution to arrive exactly where the gate already sits — so after T3.2
re-derives that threshold, this item is circular and must be restated in terms
of the new one, or dropped.

---

## 3. The gates, pre-committed

Written before the bundle runs. P2 proved this is what makes the difference:
T2.4c's p10 floor caught two real defects precisely because it and its remedy
existed on paper first.

| Risk | Control |
|---|---|
| Novelty becomes meaningless | fixture test: a board differing only in silhouette id from a window entry must still be non-novel |
| Variety bought with sparseness | `bboxOccupancy` / `largestEmptyRegion` must not regress — the Dense Strategy Phase 1C symptom |
| Composition regresses | the T2.4b p10 floor, unchanged: Medium ≥ 0.63, Hard ≥ 0.65 |
| **F1 returns** | `core_triviality_test`: Medium min ≥ 6 taps, ≤6-tap share < 5%. **This broke once already in P2** |
| **Hard node floor breached** | `hard_nodecount_distribution_test`: 200/200 at ≥ 25 nodes. **Nearly broke once already** |
| Milestones repainted | `level_seed_test` + `milestone_identity_test` green — non-negotiable |
| Latency | Hard gen p95 ≤ 260 ms; Daily p100 ≤ 800 ms |
| Solvability | 600/600 device autoplay |

---

## 4. Definition of done

- [ ] `non-novel` exit share **< 25%** of Hard campaign levels (from **95.3%**).
- [ ] Rankable candidates ≥ **2.0** per level (from **0.05**); levels with no
      choice **< 40%** (from **99.7%**).
- [ ] Longest same-silhouette run **≤ 3** (from 6).
- [ ] Worst 5-level window **≥ 2** visual families (from 1).
- [ ] Plain-rectangle share **< 8%** on Hard (from 18.0%).
- [ ] Distinct outlines per rolling 10-level window **≥ 7**.
- [ ] Every gate in §3 green.
- [ ] Corpus re-baselined **once**, CSVs committed, `corpus_identity_test`
      re-pinned in the same commit.

**The first two items are the plan.** The rest follow from them if the thesis is
right, and if they do not, the thesis was wrong and that is worth knowing
plainly rather than patching the symptoms individually.

---

## 5. Sequencing

```
T3.0  Funnel instrumentation, per-stage      ── free, no board moves
      ↓
T3.1  Fingerprint re-bucketing               ┐
T3.2  Threshold recalibration                │  one re-baselining event,
T3.3  Stop recording non-novel fallbacks     │  measured lever by lever,
T3.4  Archetype lock + retry budget          ┘  shipped together
      ↓
T3.5  Target renegotiation, written down before scoring
      ↓
      Gen V1 freeze
```

**Measure each lever alone before shipping the bundle.** P2's own history is the
argument: T2.2 looked obviously right, shipped inside a bundle, and was only
caught because the node-floor gate happened to exist. Four levers landing at
once with no per-lever reading is four ways to be wrong at the same time.

---

## 6. Still outstanding from P2, unchanged

- 600-level device autoplay (owed by T2.0 *and* the P2 bundle).
- T2.4c control (c): 20-board on-device visual review.
- `relay_softlock_property_test`, failing since before P1 — its two-relay case
  claims a genuine dead-end escape, which bears on the solvability invariant.
- `diamond` / `hollowDiamond` jitter-range bias toward area preservation, the
  surviving half of T2.2's original complaint.
