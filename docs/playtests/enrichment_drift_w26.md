# W2.6 — pre- vs post-enrichment metric drift (audit P2-1)

Measured 2026-10-30 on `wave2/w2.1-lifecycle` @ `5454e59`. Measurement only:
no generator change. Harness:
`test/game/levels/generation/enrichment_drift_report_test.dart` (tag `report`).
Per-population raw output is in `docs/playtests/enrichment_drift/`.

## Question

The generator checks each candidate against its tier's `DifficultyProfile`
band using metrics from the **raw** retrograde board. Only after that does
`enrichLevel` add cores, locks, relays and phase gates. Locks and phase gates
change which taps are legal, so how far do the metrics of the board that
actually **ships** sit from the numbers the band was checked on?

## Method

- Campaign Easy, Medium and Hard, L1–1000 each, from a `LevelGenerator.neutral()` per mode, generated in order with no time budget (deterministic, like the corpus). Plus all 365 Daily keys of 2027 at the shipped `dailyWorkBudget`, checked against the Expert band.
- The raw board is reconstructed from the shipped one by resetting `kind`, `isCore` and `phaseGroup`. That reconstruction is exact: enrichment never moves a node or turns an arrow on the shipped board.
- For each board: `LevelMetrics.compute` on raw and on enriched, then `DifficultyProfile.passes` on each.

**Decision rule, fixed before the run.** LEAVE is the share of boards that pass the band raw but fail it enriched, out of all boards that pass raw. If LEAVE is under 5% in every tier, document the drift and close P2-1. If any tier is at or above 5%, open a follow-up to re-check the band after enrichment.

## Results

| population | boards with locks/gates | pass raw | pass enriched | **LEAVE** | ENTER |
|---|---|---|---|---|---|
| Easy L1–1000 | 0% | 25.1% | 25.1% | **0.0%** | 0 |
| Medium L1–1000 | 87.5% | 88.0% | 60.6% | **32.2%** (283) | 9 |
| Hard L1–1000 | 87.5% | 92.2% | 94.0% | **4.7%** (43) | 61 |
| Daily 2027 (Expert) | 100% | 99.5% | 87.7% | **12.1%** (44) | 1 |

Median drift (enriched − raw) on boards that have mechanics:

| metric | Medium | Hard | Daily |
|---|---|---|---|
| first legal moves | −1 (p5 −3) | −1 (p5 −5) | −4 (p5 −6) |
| wave depth | 0 (p95 +3) | 0 (p95 +3) | +2 (p95 +4) |
| forced-sequence ratio | +0.04 (p95 +0.26) | 0.00 (p95 +0.17) | +0.08 (p95 +0.18) |
| avg branching factor | −0.90 | −1.12 | −3.21 |
| critical unlock depth | 0 | 0 | 0 |

What made boards leave the band (first failing check):

- **Medium:** wave depth 128, FSR 88, BF 65, opening 2.
- **Hard:** wave depth 41, FSR 1, BF 1.
- **Daily:** FSR 38, BF 6.

## Reading

- **The drift goes one way: harder.** Locks and phase gates remove opening choices, deepen the removal waves and force more of the sequence. No metric drifts toward easier. So the boards that leave the band are boards that are harder than their tier's ceiling, not easier than its floor.
- **Medium is the outlier.** About a third of Medium boards that pass on paper ship above the Medium ceiling. Most fail on wave depth (raw 5 → enriched 6) or FSR (≈0.80 → 0.86–0.88). Medium is the tier where the band was meant to bite.
- **The Daily is consistently harder than Expert's own numbers.** The opening drops by about 4 moves and BF by about 3 on every Daily, because every Daily carries the sector-8 mechanic budget. 12% end up over the FSR ceiling.
- **Hard is just under the line.** It also gains 61 boards that fail raw but pass enriched, so its pass rate actually rises (92.2% → 94.0%).
- **Easy has no mechanics, so there's no drift.** Separately, only 25% of shipped Easy boards pass the Easy band at all, raw or enriched. That's a generator-supply question, not drift, and it's out of scope here.
- **CUD never moves.** Critical unlock depth is computed structurally from ray dependencies and ignores locks and gates. The metric itself is blind to them.
- **Limitation:** none of these metrics model relay rotation. Relays are scored as plain nodes in both versions, so real drift on relay boards could be larger than reported.

## Decision

**LEAVE ≥ 5% in Medium (32.2%) and Daily (12.1%), so P2-1 is not closed.** Open a follow-up. Per the audit's warning, the band must not simply be moved after enrichment. The whole band system was calibrated on pre-enrichment numbers, and moving the check changes which boards ship (a Gen V1 freeze matter, WAVE2 plan §2). The follow-up has to choose between:

1. **Re-check after enrichment.** Reject or re-roll candidates whose *enriched* metrics leave the band. This is the most honest option, but it costs candidate supply, since a third of Medium would be rejected at today's ceilings. It changes shipped boards and needs a corpus re-baseline.
2. **Shift the raw band by the measured drift.** Score raw boards against a ceiling lowered by the median drift (for example, Medium wave depth −1 and FSR −0.04), so the enriched board lands inside the intended band. This keeps the check where it is but still changes shipped boards.
3. **Re-define the bands as structure-only.** Keep everything and document that the bands describe the board before mechanics, with mechanics adding a known, bounded difficulty on top (the tables above). This doesn't change any boards. It's the right call if playtests already tuned Medium and Daily against the boards that actually ship.

Option 3 is the only one compatible with the freeze. Options 1 and 2 belong with W2.7 (portals), which unfreezes the generator anyway and will move these same metrics again.

## Outcome (2026-10-30)

**Option 3 chosen by the owner.** The bands are defined as describing board structure before mechanics, and the drift above is the documented, by-design difficulty that mechanics add on top. This is recorded on `DifficultyProfile` in `difficulty_profile.dart`. No generator or board change. P2-1 is closed on that basis. Options 1 and 2 stay available for the W2.7 Gen V2 unfreeze, if portals make the drift worth acting on.
