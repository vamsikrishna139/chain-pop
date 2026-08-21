# Topology-class calibration (T0.2)

`topologyClass` is the F4 measure: the count of *distinct* values over a corpus is what
`MASTER_PLAN_V2.md` and `IMPLEMENTATION_PLAN_V2.md` §P2 quote as **Easy 30 / Medium 18 /
Hard 14**, with a P2 target of **Hard ≥ 25**.

The plan specifies the triple but not its encoding:

> `topologyClass` = `(components, enclosedHoles, bboxFillBucket)` — the triple the audit probes
> used to get 14/18/30.

`components` and `enclosedHoles` are unambiguous (4-connected, computed in
`CompositionMetrics`). `bboxFillBucket` is not — the bucket width determines the class count
directly, so it had to be pinned by measurement before any P2 gate could read this column.

## Measurement

300 sampled ids per mode (`sampleLevelIds(count: 300, minId: 1, maxId: 1500, seed: 7)`),
generated at the production time budget, counting distinct triples under several bucket widths.

| Bucket width | Easy | Medium | Hard |
|---|---|---|---|
| halves (2) | 29 | 19 | **21** |
| thirds (3) | 35 | 19 | **17** |
| **quartiles (4) — adopted** | **40** | **25** | **23** |
| fifths (5) | 44 | 29 | 26 |
| tenths (10) | 64 | 45 | 37 |
| no fill term at all | 21 | 11 | 12 |

## Two findings, and the second one matters

**1. Quartiles are adopted.** Tenths are far too fine to be "coarse" in any perceptual sense;
halves collapse the sparse/dense distinction that F4 is largely about. Quartiles split at
0.25 / 0.50 / 0.75 occupancy — sparse, open, dense, solid — which is the granularity at which
two boards stop looking like the same kind of shape.

**2. No bucket width reproduces 30/18/14, and the shape of the disagreement rules out
"wrong bucket" as the explanation.** The published numbers rank **Easy > Medium > Hard**
(30/18/14) with Hard far the worst. Every row above ranks the modes the same way, but no row
gets Hard as low as 14 while Easy is as high as 30: at halves, Hard is 21 against Easy's 29.
A bucket-width mismatch would move all three modes together; this does not. So the original
probe differed in something else — a different id sample, `components` taken on the silhouette
mask rather than the placed nodes, 8-connectivity, or a different corpus size. **That probe is
not in the repository and its definition is not recoverable from it.**

## Consequence for P2 — flagged, not silently resolved

Under the definition adopted here, **Hard already measures 23** distinct topology classes
against a P2 target of "≥ 25 (from 14)". Landing P2 and declaring that target met would
therefore prove almost nothing: most of the apparent gain is the measure changing, not the
generator improving.

This is a plan question, not an implementation one, so it is recorded rather than decided:

- The numbers above are the **Gen V1 baseline under the T0.2 definition**. P2 must be judged
  against *these*, not against 30/18/14.
- P2's DoD needs a restated Hard target relative to the 23 baseline before T2.2/T2.3/T2.4c land.
- The other F4 measures in the P2 DoD — lattice share, longest same-silhouette run, rolling
  min-Hamming, mask fallback rate — are computed by existing code and are unaffected by this.
