## campaign_medium_L1-1000 (tier: medium)

- boards: 1000; with locks/relays/phase gates: 875 (87.5%)
- pass band raw: 880 (88.0%); pass band enriched: 606 (60.6%)
- **LEAVE** (pass raw, fail enriched): 283 = **32.2% of raw-passing boards**
- ENTER (fail raw, pass enriched): 9

| metric (enriched − raw) | mean | p5 | p50 | p95 | boards changed |
|---|---|---|---|---|---|
| firstLegalMoveCount | -1.15 | -3 | -1 | 0 | 61.9% |
| waveZeroWidth | -1.15 | -3 | -1 | 0 | 61.9% |
| waveDepth | 0.76 | 0 | 0 | 3 | 48.3% |
| FSR | 0.07 | -0.04 | 0.04 | 0.26 | 64.7% |
| avgBF | -1.04 | -2.50 | -0.90 | 0 | 76.0% |
| CUD | 0.00 | 0 | 0 | 0 | 0.0% |

LEAVE by first failing check: waveDepth=128, FSR=88, avgBF=65, firstLegalMoveCount=2

Examples: L191 (waveDepth: raw 5 -> enriched 6); L218 (FSR: raw 0.80 -> enriched 0.86); L230 (FSR: raw 0.84 -> enriched 0.87); L259 (waveDepth: raw 4 -> enriched 6); L261 (waveDepth: raw 5 -> enriched 6); L263 (FSR: raw 0.80 -> enriched 0.88); L265 (waveDepth: raw 5 -> enriched 6); L391 (waveDepth: raw 5 -> enriched 6)
