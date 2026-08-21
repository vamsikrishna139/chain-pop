# `p1_mid_selector/` — the baseline that was current until 2026-08-21

**What this is.** The three baseline CSVs as they stood before the re-capture of
2026-08-21. They were written on 2026-08-20 04:19, part-way through P1: after
T1.1/T1.2/T1.3 first landed in the working tree, but **before** the core
selector's final revision, which was still uncommitted at the time and shipped
in `ff54cf0` a day later.

**Why they were replaced.** They no longer describe the generator. Measured
against the shipped tree, 40 of the 300 boards differ — the three T0.4 guards
and the ceiling invariant were red, which is exactly what those guards exist to
say. Attribution (2026-08-21):

| quantity | value |
|---|---|
| geometry moved | 40 boards — 22 Medium, 18 Hard |
| core **set** moved | 37 of those 40 |
| core **count** moved | 2 (`132/medium` 3 -> 1, `1206/medium` 2 -> 1) |
| node count moved | 18 — **all Medium**, both directions |
| Hard node counts | 100/100 unchanged at 25 |

The cause is core selection, not geometry planning: a different core set changes
lock and relay placement, which changes which candidate survives validation
(plan §0.1). Two hypotheses were tested and rejected:

* **The attempt-exhaustion fallback** (`budgetFallback` / `mechanicShortFallback`,
  added late in P1). It fires on one level in 1..1500 (L427 Medium) and cannot
  account for 40 boards. The other generator-side edits in `ff54cf0` are all on
  the seeded/milestone path.
* **A harness change** — the corpus measurement moved from one shared
  `LevelGenerator` to `LevelGenerator.neutral()` per board. Re-measuring the
  corpus *with* a shared generator reproduces the baseline **worse**, not
  better: 76 node-count mismatches against 18 for the per-board construction.
  So the baseline was captured with the current harness and the generator is
  what moved.

**Keep them.** They are the only record of the intermediate state, and the
`P1_RESULT.md` numbers as first published were measured against them.

The pre-P1 Gen V1 baseline — the real "before" for the P1 diff — is in
`../genv1_pre_p1/`, and is untouched.
