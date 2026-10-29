# W2.7 — portals fix-through: rollout readiness

Measured 2026-10-30 on `wave2/w2.1-lifecycle`. Portals are built **dark**:
`PortalRollout.enabled` (`progression_profile.dart`) defaults to `false`, and
nothing reaches players until that default is flipped. The flip is the Gen V2
unfreeze and needs the owner's sign-off.

## What was fixed (audit P1-6 a–e)

| | Defect | Fix |
|---|---|---|
| a | Portal cells decoded with base-1000 arithmetic (`% 1000`) in the constructor and `SightlineTable` | `gridCellX` / `gridCellY` in `grid_cell_key.dart`, used at both sites |
| b | `enrichLevel` rebuilt boards without `portalPairs` / `silhouetteId` | `LevelData.copyWith`; every enrichment rebuild goes through `_rebuild` |
| c | Nothing rendered a portal | `BoardMaskComponent` draws a numbered ring at both ends of each pair (number + colour, so it is colourblind-safe) |
| d | Relay-safety probes and constructor validation ran on portal-free copies | Probes keep the board's portals; the property-test search keeps them too |
| e | Untaught | One-time "Portals" explainer on the first portal board (clock held), persisted as `portal_intro_seen` |

Found and fixed along the way:

- **Nodes could be placed on portal cells.** A node there hides the portal and blocks its own warp. With portals live, the constructor excludes portal cells from placement, and only places a pair if the silhouette still has room for the full node target.
- **Portal loops disagreed between the constructor and the solver.** A ray that warps back behind its own node circles forever. `LevelSolver` treats that as permanently blocked; `SightlineTable` treated it as clear, so the constructor could build boards the solver calls unsolvable. Both now say blocked.

## Switch off = Gen V1, byte for byte

The off path is not "no portals". The old, wrongly decoded portals were partly live: cells on row 0 decode correctly, so they steered construction. Simply removing them changed **146 of 1,120** sampled boards: 42 Medium from L639, 90 Hard from L630, and 14 of 120 Dailies.

So with the switch off, the constructor, `SightlineTable` and `enrichLevel` keep their old behaviour on a marked legacy path (`legacyGenV1`). Re-measured against the previous commit: **0 of 1,120 boards differ** (Medium and Hard L501–1000 plus 120 Dailies, full node, kind, core, phase and colour signatures). Delete the legacy branches at the flip.

## Switch on — measured

Medium and Hard L601–1000 were generated in order with no time budget; Dailies used the shipped `dailyWorkBudget`. Raw output is in `docs/playtests/portal_rollout/`.

| population | portal boards | unsolvable | construction failures off → on | gen ms p50 / p99 / max, off → on |
|---|---|---|---|---|
| Medium L601–1000 | 275 / 400 | 0 | 0 → 1 | 17 / 86 / 144 → 18 / 115 / 413 |
| Hard L601–1000 | 339 / 400 | 0 | 185 → 329 | 49 / 225 / 1499 → 55 / 559 / 1917 |
| Daily 2027 | 349 / 365 | 0 | 218 → 415 | 91 / 495 / 656 → 110 / 564 / 634 |

- **Every board generates and every board is solvable**, with no attempt exhaustion.
- **Relay safety holds with portals.** The new slow test (`relay_softlock_property_test`, "portals live") proved all 550 one-relay boards in Medium and Hard L601–1000 safe by exhaustive search, 390 of them carrying a portal. None were inconclusive and none soft-locked.
- **Cost:** about 1.8× the construction failures on Hard and the Daily, because correct sightlines are stricter, as the audit predicted. Total generation time rises about 40% on Hard (25 → 35 s per 400 levels) and about 26% on the Daily. Campaign play runs under the 200 ms `generationBudget`, which these unbudgeted numbers don't apply, so in-game waits stay bounded. The Daily stays inside its p95 / worst-case latency gate.

## Not covered yet

- **No visual check on a device.** The ring rendering and the explainer have only been checked by analysis and tests, not seen on the Pixel. Before flipping, temporarily turn the switch on in a debug build and look at a sector-6 board (Hard L626+).
- `relaysafe_soundness_test` still tests a mirrored, portal-free copy of the relay check. The real pipeline is covered by the new property sweep instead.
- Topology metrics (`DependencyGraph`) don't follow portals. They're telemetry only.

## The flip (needs sign-off)

1. Set `PortalRollout.enabled = true` by default, then delete the `legacyGenV1` paths in the constructor, `SightlineTable` and `enrichLevel`'s `_rebuild`.
2. Shipped boards change from about L630 (Hard) and L639 (Medium), plus most Dailies. Stars are stored per level id and per day key, so player progress is unaffected.
3. Re-baseline the frozen corpus with an explicit sign-off note, and run the 600-level device autoplay over L626–1000.
4. Expect `portalPairCount` in the win analytics to go from always 0 to non-zero.
