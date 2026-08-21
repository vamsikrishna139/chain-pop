# `p1_final/` — the post-P1, pre-P2-bundle corpus capture

Archived **2026-08-21**, immediately before T2.1 + T2.3 + T2.4c landed.

This is the baseline that was live at `cec01ec` — the one re-captured after the
`p1_mid_selector/` attribution, with all 21 guards green. It is archived rather
than overwritten because P2's bundle is a **re-baselining event**: it moved
**209 of the 300 boards' geometry, 106 node counts and 192 ceilings**, and
without this capture the bundle's effect on tap depth could never be re-derived.

## What it is for

Diffing the **bundle's** effect, by pointing `_kBeforeDir` in
`adversarial_corpus_diff_test.dart` at this directory instead of
`genv1_pre_p1/`. Measured that way:

| view | tapsToWin p50 | ≤6 taps | captureRate p50 |
|---|---|---|---|
| Medium severity | 11 → 11 | 0.0% → 2.0% | 1.00 → 1.00 |
| Medium representative | 11 → 11 | 0.0% → 0.0% | 1.00 → 1.00 |
| Hard control | 10 → 11 | 0.0% → 0.0% | 0.64 → 0.65 |

**The 2.0% was a real regression and it was fixed, not accepted.** It was one
board — L194/medium, 13 nodes, won in 3 taps — and it took
`core_triviality_test`'s F1 gate red. The cause was the mask cell floor sitting
at `minNodes` (10) rather than the profile band minimum (14); T2.1's new mask
shapes made those masks reachable for the first time. The shipped tree floors at
`max(profile.nodeCount.min, difficulty.minNodes)` and reads 0.0% again. See
`docs/playtests/p2_bundle_result.md`.

## Read the §e classification with care

Against this directory the classifier reports ~162 `VIOLATION`. That is **not** a
defect count. `classifyBoard` calls any geometry, solution or node-count
movement a violation because P1's contract was "cores only" — P2 moves geometry
deliberately and wholesale, so against this baseline that column counts intended
changes. The tapsToWin and captureRate distributions above are the meaningful
comparison. The `VIOLATION` column is only meaningful against `genv1_pre_p1/`,
which is why that stayed the harness default.
