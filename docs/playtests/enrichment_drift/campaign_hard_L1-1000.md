## campaign_hard_L1-1000 (tier: hard)

- boards: 1000; with locks/relays/phase gates: 875 (87.5%)
- pass band raw: 922 (92.2%); pass band enriched: 940 (94.0%)
- **LEAVE** (pass raw, fail enriched): 43 = **4.7% of raw-passing boards**
- ENTER (fail raw, pass enriched): 61

| metric (enriched − raw) | mean | p5 | p50 | p95 | boards changed |
|---|---|---|---|---|---|
| firstLegalMoveCount | -1.61 | -5 | -1 | 0 | 61.8% |
| waveZeroWidth | -1.61 | -5 | -1 | 0 | 61.8% |
| waveDepth | 0.74 | 0 | 0 | 3 | 44.3% |
| FSR | 0.04 | -0.04 | 0.00 | 0.17 | 62.7% |
| avgBF | -1.41 | -3.52 | -1.12 | 0 | 74.2% |
| CUD | 0.00 | 0 | 0 | 0 | 0.0% |

LEAVE by first failing check: waveDepth=41, FSR=1, avgBF=1

Examples: L254 (waveDepth: raw 8 -> enriched 9); L507 (waveDepth: raw 7 -> enriched 10); L531 (waveDepth: raw 7 -> enriched 10); L548 (waveDepth: raw 5 -> enriched 9); L560 (waveDepth: raw 7 -> enriched 10); L660 (waveDepth: raw 5 -> enriched 9); L712 (waveDepth: raw 6 -> enriched 9); L723 (waveDepth: raw 6 -> enriched 9)
