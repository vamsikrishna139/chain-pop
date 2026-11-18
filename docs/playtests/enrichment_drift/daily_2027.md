## daily_2027 (tier: expert)

- boards: 365; with locks/relays/phase gates: 365 (100.0%)
- pass band raw: 363 (99.5%); pass band enriched: 320 (87.7%)
- **LEAVE** (pass raw, fail enriched): 44 = **12.1% of raw-passing boards**
- ENTER (fail raw, pass enriched): 1

| metric (enriched − raw) | mean | p5 | p50 | p95 | boards changed |
|---|---|---|---|---|---|
| firstLegalMoveCount | -3.72 | -6 | -4 | -2 | 100.0% |
| waveZeroWidth | -3.72 | -6 | -4 | -2 | 100.0% |
| waveDepth | 2.01 | 0 | 2 | 4 | 94.8% |
| FSR | 0.08 | -0.02 | 0.08 | 0.18 | 99.5% |
| avgBF | -3.26 | -4.36 | -3.21 | -2.14 | 100.0% |
| CUD | 0.00 | 0 | 0 | 0 | 0.0% |

LEAVE by first failing check: FSR=38, avgBF=6

Examples: 20270102 (FSR: raw 0.73 -> enriched 0.88); 20270111 (avgBF: raw 6.08 -> enriched 2.88); 20270125 (FSR: raw 0.79 -> enriched 0.88); 20270130 (FSR: raw 0.72 -> enriched 0.89); 20270204 (FSR: raw 0.73 -> enriched 0.86); 20270214 (FSR: raw 0.80 -> enriched 0.88); 20270228 (FSR: raw 0.77 -> enriched 0.89); 20270305 (FSR: raw 0.78 -> enriched 0.88)
