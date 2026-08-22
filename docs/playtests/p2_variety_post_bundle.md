# P2 variety — the post-bundle reading

Captured **2026-08-21**, after T2.1 + T2.3 + T2.4c landed as the plan's single
re-baselining event (T2.2 is a no-go — see below). Same instrument, same
machine, same sample as `p2_variety_pre_bundle.md`.

```
flutter test --tags report test/game/levels/generation/p2_variety_report_test.dart
```

## The P2 definition of done, scored

| DoD item | plan's "from" | **measured before** | after | verdict |
|---|---|---|---|---|
| Hard topology classes >= 30 | 23 | 22 | **38** | **met** |
| Hard lattice share < 50% | 68% | 73.0% | 72.0% | **missed** |
| Longest same-silhouette run <= 3 | 6 | 6 | 6 | **missed** |
| Worst 5-level window >= 2 families | — | 1 | 1 | **missed** |
| Rolling min-Hamming median >= 5 | 3.00 | 3.00 | 3.00 | **missed** |
| Shipped mask fallback < 0.5% | 8% | **0.0%** | **0.0%** | met (see note) |
| Hard L45-56 not five full-rect | 5 | 9 | 4 | **met** |
| Gen p95 not worse | — | 186 ms | **126 ms** | met |
| `level_seed_test` green | — | green | green | met |

Medium topology classes moved 24 -> 33 as well; Easy is flat at 39 (it is
short-circuited out of composition entirely and T2.3 is Hard/Expert-only, so
only T2.1 touches it).

**Four of nine missed.** They are not near-misses and they are not independent:
lattice share, same-silhouette run, the 5-window and the Hamming median are all
measures of the *emission sequence*, and every one of them is dominated by
something the bundle never touched — `_pickSilhouette`'s explicit 40% dense-
silhouette bias for Hard/Expert, and the diversity ledger's 3-bit silhouette
fingerprint field. T2.3 removed the *substitution* pressure (attempt-level
rectangle substitutions 6,067 -> 2,460, and the shipped fallback rate is 0%),
which is why the topology-class and full-rect numbers moved so far; it did not
and cannot change which silhouette the Director asks for in the first place.

**The "8% -> < 0.5%" fallback target was never measurable as written**, and this
is a measurement correction, not a pass. `playCells == null` means the Director
*chose* `SilhouetteId.rectangle`; a silhouette that was asked for and could not
be built comes back as a full-grid mask that is non-null. The first draft of the
instrument conflated the two and read 22.2% before the bundle. Counted properly
the shipped fallback rate is **0.0% both before and after** — the 8% figure in
the plan describes neither quantity on the tree that ships. What was real is the
attempt-level pressure, and that is what fell 2.5x.

## Composition — the T2.4c control

The T2.4b gate is measured on its own 300-id/mode sample (seed `20260821`) by
`composition_calibration_test`, **not** on the sample below:

| mode | gate | before | after |
|---|---|---|---|
| Medium | >= 0.63 | 0.6327 | **0.6514** |
| Hard | >= 0.65 | 0.6595 | **0.6948** |

Both above the gate and both **better than before the bundle**. That is the
control the plan pre-committed to, and it did real work: see
`p2_bundle_result.md` for the two defects it caught.

## Raw

```
===== P2 VARIETY REPORT — corpusVersion: 1, generationVersion: 1, strategyVersion: 0, seedContractVersion: 1, topologyDefinitionVersion: 1 =====
topologyDefinitionVersion: 1
sequential run: Hard L0..499, prod budget
topology sample: 300 ids/mode, seed 7, ids 1..1500, prod budget

--- sequential Hard, n=500 ---
lattice share: 72.0% (DoD < 50%, from 68%)
  geometricLattice   360  72.0%
  organic            116  23.2%
  archipelago         11  2.2%
  corridor            13  2.6%
silhouette ids: diamond=136 cross=113 organicBlob=62 ring=61 asymmetric=54 rectangle=50 corridor=13 archipelago=11
longest same-silhouette run: 6 (DoD <= 3, from 6)  hist={1: 349, 2: 56, 6: 1, 3: 11}
longest same-family run:     14  hist={4: 10, 1: 117, 6: 7, 2: 45, 3: 21, 7: 3, 9: 3, 5: 5, 14: 1, 8: 6, 13: 1}
worst 5-level window families: 1 (DoD >= 2)  avg=2.00 pureLattice=86
  W=10 min=1 max=4 avg=2.41 pureLattice=9
  W=20 min=2 max=4 avg=2.79 pureLattice=0
rolling min-Hamming median: 3.00 (DoD >= 5, from 3.00)  p90=5.00 min=0
shipped mask FALLBACK (asked for a shape, got the grid): 0/500 = 0.0%  (DoD < 0.5%, from 8%)
shipped rectangle SILHOUETTE (chosen, not a failure): 90/500 = 18.0%
director rectangle substitutions (attempt-level): 2460  diamond=1150 ring=639 cross=235 archipelago=188 corridor=149 asymmetric=59 organicBlob=40
gen latency ms: p50=50 p75=73 p95=126 p100=210  (DoD p95 <= 260)

--- topology classes (300 ids/mode) ---
easy    n=300  distinct topologyClass=39  fullRect=17.0%  shipped composition p10=n/a
  top classes: 5/0/1x39 4/0/1x33 3/0/1x30 6/0/1x21 2/0/2x15 1/0/2x14
medium  n=300  distinct topologyClass=33  fullRect=7.7%  shipped composition p10=0.6193
  top classes: 1/0/2x44 1/1/2x37 1/0/3x35 3/0/1x34 2/0/1x28 1/2/2x15
  shipped rule violations: clean=265 blobVsGrid=22 occupancy=13
  per-term: aspect p10=0.67 p50=1.00  blobVsGrid p10=0.50 p50=0.89  occupancy p10=0.38 p50=0.52  singleton p10=0.75 p50=1.00  components p10=0.33 p50=1.00
hard    n=300  distinct topologyClass=38  fullRect=18.7%  shipped composition p10=0.6764
  top classes: 1/1/2x49 1/2/2x27 1/1/1x27 1/0/2x21 3/0/1x20 2/1/2x18
  shipped rule violations: clean=298 blobVsGrid=2
  per-term: aspect p10=0.56 p50=1.00  blobVsGrid p10=0.73 p50=0.88  occupancy p10=0.42 p50=0.51  singleton p10=0.75 p50=1.00  components p10=0.33 p50=1.00
(Gen V1 calibrated baseline: Easy 40 / Medium 25 / Hard 23; DoD Hard >= 30)
(composition p10 here is the 100-id-style read; the T2.4b GATE is the 300-id seed-20260821 sample in composition_calibration_test)

--- Hard L45-56 (the visible symptom) ---
L45=RECT L46=33c L47=33c L48=33c L49=RECT L50=RECT L51=38c L52=31c L53=26c L54=33c L55=RECT L56=32c
full-rect boards in L45-56: 4  (DoD: not five; was 5)
```
