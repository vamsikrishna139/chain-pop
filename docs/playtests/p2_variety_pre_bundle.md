# P2 variety — the pre-bundle reading

Captured **2026-08-21** at `cec01ec` (T0 + P0 + P1 + T2.0 + T2.4a/b landed;
T2.1 parked, T2.2 / T2.3 / T2.4c not started), by

```
flutter test --tags report test/game/levels/generation/p2_variety_report_test.dart
```

This is the "before" half of the bundle's controlled comparison. It exists
because three of the F4 numbers the P2 definition of done is written against
**do not reproduce on the tree that ships** — the same class of error as the
topology `14`, F1's `44%` and T2.4b's reject volumes, for the fourth time:

| DoD figure | plan says | measured here | verdict |
|---|---|---|---|
| Hard lattice share | 68% | **73.0%** | worse than published |
| shipped mask fallback | 8% | **22.2%** | **~3x worse than published** |
| Hard L45-56 full-rect | 5 | **9** | worse than published |
| Hard topology classes | 23 | 22 | reproduces (±1, budgeted path) |
| longest same-silhouette run | 6 | **6** | reproduces exactly |
| rolling min-Hamming median | 3.00 | **3.00** | reproduces exactly |

The two sequence measures reproduce to the digit and the two share measures do
not, which rules out "different corpus" as the explanation and points at the
same thing T2.2 exists to fix: the 25-cell `minCells` floor. The attempt-level
tally below is the proof — **diamond alone eats 3,517 of 6,067 rectangle
substitutions**, and T2.1's measurement already recorded diamond as 60/60 short
at a floor of 25 and 0/60 short at 15.

**The DoD targets are not restated downward.** The bundle is scored against
these measured numbers as its baseline; where a target was written against a
figure that does not reproduce, both are reported.

## Raw

```
===== P2 VARIETY REPORT — corpusVersion: 1, generationVersion: 1, strategyVersion: 0, seedContractVersion: 1, topologyDefinitionVersion: 1 =====
topologyDefinitionVersion: 1
sequential run: Hard L0..499, prod budget
topology sample: 300 ids/mode, seed 7, ids 1..1500, prod budget

--- sequential Hard, n=500 ---
lattice share: 73.0% (DoD < 50%, from 68%)
  geometricLattice   365  73.0%
  organic             88  17.6%
  archipelago          9  1.8%
  corridor            38  7.6%
silhouette ids: diamond=166 ring=95 asymmetric=60 rectangle=54 cross=50 corridor=38 organicBlob=28 archipelago=9
longest same-silhouette run: 6 (DoD <= 3, from 6)  hist={1: 358, 6: 1, 2: 45, 3: 12, 5: 2}
longest same-family run:     16  hist={1: 130, 13: 1, 7: 6, 2: 37, 3: 21, 6: 4, 5: 7, 8: 1, 4: 12, 14: 2, 9: 1, 10: 1, 16: 1}
worst 5-level window families: 1 (DoD >= 2)  avg=2.06 pureLattice=89
  W=10 min=1 max=4 avg=2.58 pureLattice=22
  W=20 min=2 max=4 avg=3.12 pureLattice=0
rolling min-Hamming median: 3.00 (DoD >= 5, from 3.00)  p90=6.00 min=0
shipped mask fallback: 111/500 = 22.2%  (DoD < 0.5%, from 8%)
director rectangle substitutions (attempt-level): 6067  diamond=3517 ring=1396 cross=530 archipelago=244 corridor=186 organicBlob=103 asymmetric=91
gen latency ms: p50=58 p75=86 p95=186 p100=279  (DoD p95 <= 260)

--- topology classes (300 ids/mode) ---
easy    n=300  distinct topologyClass=40  fullRect=16.7%  shipped composition p10=n/a
  top classes: 4/0/1x38 5/0/1x32 6/0/1x29 3/0/1x25 2/0/1x17 6/0/0x16
medium  n=300  distinct topologyClass=24  fullRect=7.3%  shipped composition p10=0.6259
  top classes: 2/0/1x55 1/0/2x54 1/1/2x29 2/1/1x27 1/0/3x23 1/2/2x18
hard    n=300  distinct topologyClass=22  fullRect=22.7%  shipped composition p10=0.6595
  top classes: 1/1/1x46 1/1/2x36 2/1/2x34 2/0/1x31 2/0/2x25 1/0/2x24
(Gen V1 calibrated baseline: Easy 40 / Medium 25 / Hard 23; DoD Hard >= 30)
(composition p10 here is the 100-id-style read; the T2.4b GATE is the 300-id seed-20260821 sample in composition_calibration_test)

--- Hard L45-56 (the visible symptom) ---
L45=RECT L46=RECT L47=RECT L48=25c L49=RECT L50=RECT L51=RECT L52=RECT L53=26c L54=33c L55=RECT L56=RECT
full-rect boards in L45-56: 9  (DoD: not five; was 5)
```
