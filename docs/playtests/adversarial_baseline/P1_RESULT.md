# P1 — frozen-corpus result

**Date:** 2026-08-19 · **Branch:** `new_improvements` · **Scope:** T1.1, T1.2, T1.3
(T1.4 measured and dropped — see below) · **Instrument:** the 300-board frozen
adversarial corpus of T0.4, evaluated exactly once, never tuned against.

The pre-P1 Gen V1 baseline is archived verbatim in
[`genv1_pre_p1/`](genv1_pre_p1/). The CSVs beside this file are the **post-P1**
baseline, and the three guards now protect that.

---

## The headline, and the number that actually matters

| | severity (n=100) | representative (n=100) | Hard control (n=100) |
|---|---|---|---|
| `tapsToWin` min | 2 → **7** | 2 → **7** | 4 → **7** |
| p25 / **p50** / p75 | 4/**6**/8 → 9/**11**/13 | 4/**5**/8 → 9/**11**/14 | 9/**10**/11 → 9/**10**/12 |
| **≤ 6 taps** | 61 % → **0 %** | 67 % → **0 %** | 1 % → **0 %** |
| `captureRate` p50 | 0.58 → **1.00** | 0.54 → **1.00** | 0.63 → **0.64** |
| nodes, median delta | **0** | **0** | **0** |

`captureRate` is the one to read. F1 was never a claim that Medium boards were
too small — it was a claim that the selector was leaving depth on the table, and
the baseline said so: the selector captured 0.58 of the depth its own boards
already offered. It now captures all of it. The p50 rising 6 → 11 is a
consequence, not the finding.

**Hard is where P1 was asked to do nothing, and it did nothing.** p50 stayed at
10, node counts are identical on all 100 boards, and `captureRate` moved 0.01.

## Per-quintile — the acceptance instrument

An improved mean over a static Q1 is a rejected result (T0.4§f). Q1 is where the
disease lived.

| Q | n | taps min/p50/max | capture p50 | nodes p50 |
|---|---|---|---|---|
| Q1 | 20 | 2/4/4 → **7/10/12** | 0.40 → **1.00** | 15 → **15** |
| Q2 | 20 | 4/5/5 → **8/10/17** | 0.60 → **1.00** | 16 → 18 |
| Q3 | 20 | 5/6/6 → **7/11/15** | 0.52 → **0.94** | 20 → 19 |
| Q4 | 20 | 6/7/8 → **7/11/17** | 0.61 → **0.81** | 19 → 19 |
| Q5 | 20 | 8/10/22 → **10/13/22** | 0.77 → **1.00** | 18 → 19 |

Q1 moved furthest and its median node count did not move at all. That is the
single cleanest refutation of the "node counts inflated, so `coreTapDepth` rose
while cores stayed last-popped" impostor.

## §e classification

Machine-computed per board, mutually exclusive.

| Class | severity | representative | Hard |
|---|---|---|---|
| FIXED | 93 | 85 | 86 |
| INCIDENTAL *(coreless boards — no core decision to get right)* | 7 | 15 | 14 |
| UNFIXABLE | **0** | **0** | **0** |
| SELECTOR-OPTIMAL, BOARD-LIMITED | **0** | **0** | **0** |
| SELECTOR-FAILED | **0** | **0** | **0** |

Every board with cores reached its mode floor. The baseline predicted 3 severity
and 5 representative boards would be geometrically incapable; T1.2's escalation
escape valve cleared all of them.

---

## The plan was wrong about geometry, and the guards caught it

§0.1 of `IMPLEMENTATION_PLAN_V2.md` states that changing core selection cannot
change board geometry, because `_climaxBandCoreIds` is pure and draws no
randomness. Both halves are true. **The conclusion is false.**

`enrichLevel` runs *inside* the generator's accept/reject loop, and the generator
re-validates the **enriched** board before accepting a candidate. Cores steer the
mechanics placed around them — locks exclude cores, relays must avoid core rows
— so a different core set produces different lock and relay placement and can
flip a candidate from accepted to rejected. The next attempt then builds
different geometry.

**42 of 300 boards moved this way: 34 Medium, 8 Hard.** The named list is
`kP1GeometryMovers` in `adversarial_corpus.dart`, and the drift check skips
exactly those and nothing else, so a *new* mover is still a failure.

This does not invalidate the result, and the reason is in the numbers rather
than in an argument: node-count deltas run in both directions with median 0 and
mean +0.2, every Hard board kept its node count exactly, and `captureRate` — a
per-board ratio that is immune to board size — went 0.58 → 1.00.

## Costs, stated plainly

| | before | after |
|---|---|---|
| `enrichLevel` p95 | — | **0.17 ms** (budget 5 ms) |
| Medium generation p50 / p95 | 17 / 64 ms | 21 / 107 ms |
| Hard generation p50 / p95 | 77 / 314 ms | 82 / 309 ms |
| Daily generation p50 / p75 | 217 / 311 ms | 231 / 405 ms |
| Tiny-budget (1 ms) Hard p50 / p95 / max | 41 / 135 / 1252 ms | 41 / 163 / 1258 ms |

The choke point itself is free. The generation cost is **candidate rejections**,
not compute: different cores mean different mechanics mean a different number of
attempts. Daily feels it most because `generateDailyChallenge` passes no time
budget at all. The tiny-budget distribution did not move — one board in a hundred
ran past 500 ms before P1 and one does after, which is why
`generation_budget_test` now asserts on attempt count with wall clock as a coarse
backstop.

---

## Two deviations from the plan, both deliberate

### T1.4 (Easy gets a core) was measured and dropped

Easy boards are 8–14 nodes with almost no prerequisite structure. The best
`coreTapDepth` any spread-legal selection can reach on them:

| cores | p50 | max |
|---|---|---|
| 1 | **3 taps** | 7 |
| 2 | 5 taps | 12 |

A core-win fires when the last core is extracted, so one core turns an eleven-tap
clear-all board into a ~3-tap board — F1 in miniature, and squarely against
T1.4's own gate of *Easy p50 ≥ 9, ≤6-tap share 0 %*. No core count fixes it: the
ceiling is a property of the geometry. Easy stays coreless at p50 11 taps, and
teaching the core-win there needs deeper Easy **boards** first — a generation
change, not an enrichment one. Recorded at the code site in
`progression_profile.dart`.

### Sector 2 ships 1–3 cores, not strictly 1

T1.3's stated curve is *sector 1 → 0, sector 2 → 1, sector 3+ → 3*. The nominal
budget still says exactly that. But sector-2 boards are small and flat, and one
core cannot reach the Medium tap floor on most of them, so T1.2's escalation
valve adds cores until it can. Over 400 sampled Medium levels:

| | 1 core | 2 cores | 3 cores |
|---|---|---|---|
| sector 2 (nominal 1) | 23 | 36 | 8 |
| sectors 3–8 (nominal 3) | — | — | all |

Sectors 3–8 are already at the cap and never escalate. Capping escalation at +1
was measured too: it leaves 8 of 67 sector-2 boards geometrically short and drops
Medium's minimum back to 3 taps, failing the `min ≥ 6` gate. The climb is what
holds the gate.

---

## The defect P1 introduced, and the guard that now exists for it

**L427 Medium stopped generating at all.** Not a worse board — no board.

T1.3's third core is the cause, through the same coupling as the geometry
movement. `_markSpecialNodes` keeps relays out of **core rows**, because a relay
rotates its whole row and can spin a core into a permanent face-off. Three cores
block three rows; on a cramped board that can leave no legal relay position, and
the generator treated a mechanic-budget shortfall as a reason to discard the
candidate and retry. Every one of the forty attempts was discarded and
`generate` returned `Result.error`.

Exactly one level in 1..1500 hit it. One is enough: a campaign level that cannot
be produced is a worse defect than any triviality this phase set out to fix, and
**nothing in the suite would have caught it** — the corpus tests sample, and the
`report_*` harnesses print generation failures without asserting on them. It
surfaced only because the T0.4 selection harness happened to re-run and hit L427
inside its 600-board pool.

**Fix** (`level_generator.dart`): at attempt exhaustion, ship a retained valid
board instead of erroring, ranked `budgetFallback` (valid and solvable, wave
count outside the ideal band) then `mechanicShortFallback` (valid and solvable,
missing a mechanic). Both were already being retained and thrown away. The typed
error survives for the case where nothing valid was ever built, so callers can
still tell "imperfect" from "nothing". The over-budget escape path is untouched —
its opt-in gating is what keeps campaign Hard from shipping mechanic-short boards
under a live budget.

**Guard**: `campaign_generation_coverage_test.dart` — L427 by name, plus every
7th level in 1..1500 across all three modes, asserting both that generation
succeeds and that the result is solvable.

Full sweep after the fix: **4,500 boards (1..1500 × 3 modes), 0 generation
failures, 0 unsolvable.** L427 Medium now ships as 15 nodes / 3 cores / 1 relay /
**0 locks against a budget of 2** — the mechanic-short degradation, working as
intended and visibly rather than silently.

---

## Anti-overfit

Selection was **not** re-run. The frozen ids are unchanged; only the measured
values beside them are. The held-out sequence was honoured:

```
frozen corpus  →  T1.1–T1.3  →  evaluate frozen corpus
               →  kReportSampleIds (never seen by selection) — all gates green
               →  one fresh draw — still outstanding, see below
```

The canary (`core_triviality_test.dart`) runs on `kReportSampleIds`, which is
disjoint from every corpus view, and is green on all three modes:
Medium ≤6-tap **0 %** / min **7** / p50 **11**; Easy min **8** / p50 **11**;
Hard p50 **10** / min **7**.

## Fresh draw — the last held-out population

100 ids drawn from a fixed seed (`20260820`), disjoint from all 300 corpus ids
and from `kReportSampleIds`. Drawn once; the seed is pinned in
`p1_fresh_draw_test.dart` and re-rolling it would be the same error as tuning
against the corpus.

| mode | min | p50 | ≤6-tap share | gate |
|---|---|---|---|---|
| Easy | 8 | 12 | 0.0 % | ✅ |
| Medium | 6 | 11 | **1.0 %** | ✅ |
| Hard | 7 | 10 | 0.0 % | ✅ |

## Device autoplay — the last P1 gate ✅ *(2026-08-21)*

`integration_test/autoplay_600_device_test.dart` on a **Pixel 8a** (release
toolchain, debug APK, `MOCK_ADS=true`), 200 ids per mode over 1..598 at stride
3, each level booting a real `GameScreen` through `LevelManager`, board layout,
`NodeComponent` extraction and the win flow:

| mode | played | won | stranded | never loaded | avg taps | wall clock |
|---|---|---|---|---|---|---|
| Easy | 200 | **200** | 0 | 0 | 5.7 | 104 s |
| Medium | 200 | **200** | 0 | 0 | 8.6 | 130 s |
| Hard | 200 | **200** | 0 | 0 | 11.4 | 170 s |

**TOTAL 600/600, 0 stuck**, `All tests passed!`, exit 0. The harness asserts
`expect(failures, isEmpty)` — it was not weakened to reach this.

The device avg-taps column is an independent corroboration of the headless
tap-depth work rather than a restatement of it: Medium 8.6 and Hard 11.4 are
measured by *counting real extractions through the engine*, on a level sample
(stride 3 over 1..598) that is disjoint from `kReportSampleIds` and from all
three corpus views. Easy at 5.7 is expected and is not a floor violation —
`avg taps` here counts taps to clear the board, which on coreless Easy levels
is a different quantity from the canary's `tapsToWin`.

**Every item in the P1 definition of done is now met.**

---

## Correction — the baseline this file was first measured against was stale *(2026-08-21)*

**What was wrong.** Everything above except this section was computed against a
baseline captured on 2026-08-20 04:19 — part-way through P1. The core selector
was revised after that capture and before the phase was committed (`ff54cf0`),
and the baseline was never re-taken. Measured against the shipped tree it was
stale on **40 of 300 boards**, so the three T0.4 guards and the ceiling
invariant were **red**, and the numbers published above described a generator
revision that never shipped.

Nothing found this at the time because every P1 gate is tagged `slow` and is
therefore excluded from `flutter test --exclude-tags "report || slow"`, which is
what the phase was signed off on. **Run the full sweep at a phase boundary.**

**Attribution.** Core selection, not board planning: 37 of the 40 shipped a
different core set, and a different core set moves lock and relay placement,
which moves which candidate survives validation (plan §0.1). Two alternative
explanations were tested and rejected — the late attempt-exhaustion fallback
(fires on one level in 1..1500, and every other generator-side edit in `ff54cf0`
is on the seeded path), and a harness change (re-measuring with a shared
`LevelGenerator` reproduces the stale baseline *worse*: 76 node mismatches
against 18). The stale CSVs and the full attribution are archived under
[`p1_mid_selector/`](p1_mid_selector/).

**What was done.** The baseline was re-captured from the shipped tree, the
guards are green (21/21), and `kP1GeometryMovers` was recomputed against
`genv1_pre_p1/` — the real pre-P1 "before" — giving **61** named movers, not 42.
Seven ids in the old list are not in the new one: the intermediate selector
moved them and the final one moved them back.

**The result, re-derived on the shipped tree** by
`adversarial_corpus_diff_test.dart` (new, committed, so this can never again be
a hand computation with no harness behind it):

| | severity (n=100) | representative (n=100) | Hard control (n=100) |
|---|---|---|---|
| `tapsToWin` min | 2 → **7** | 2 → **7** | 4 → **7** |
| p25 / **p50** / p75 | 4/**6**/8 → 9/**11**/13 | 4/**5**/8 → 9/**11**/14 | 9/**10**/11 → 9/**10**/13 |
| **≤ 6 taps** | 61 % → **0 %** | 67 % → **0 %** | 1 % → **0 %** |
| `captureRate` p50 | 0.58 → **1.00** | 0.55 → **1.00** | 0.64 → **0.64** |

Per quintile of the severity view, p50 taps and `captureRate`:

| | Q1 | Q2 | Q3 | Q4 | Q5 |
|---|---|---|---|---|---|
| p50 taps | 4 → **9** | 5 → **10** | 6 → **11** | 7 → **11** | 10 → **13** |
| ≤6 taps | 100 % → **0 %** | 100 % → **0 %** | 100 % → **0 %** | 5 % → **0 %** | 0 % → 0 % |
| `captureRate` | 0.40 → **1.00** | 0.63 → **1.00** | 0.55 → **1.00** | 0.61 → **0.86** | 0.82 → **1.00** |

§e classification over all 300: **0 VIOLATION · 266 FIXED · 34 INCIDENTAL
(22 of them coreless, where INCIDENTAL is definitional) · 0 UNFIXABLE ·
0 SELECTOR-FAILED.**

**The conclusion is unchanged.** Q1 moved, the mean did not move alone, node
counts are non-directional (30 boards, median 0, mean **+0.03**, and all 100
Hard boards keep 25 exactly), and no board is selector-failed. P1 is sound; what
was wrong was the evidence, not the fix. It is now measured against the code
that ships, by a harness anyone can re-run.
