# Relay soft-lock — root cause and fix

**Date:** 2026-08-21 · **Branch:** `new_improvements` · **Blocker: cleared**
**Found by:** `autoplay_600_test`, red after T2.6+T2.7 moved which boards ship.

---

## Symptom

4 stranded play-throughs of 1,800: `medium L501` (all 3 routes) and
`hard L592` (1 of 3). Both boards carry exactly one relay. "Stranded" here is a
genuine reachable dead end — the harness drives the real `ChainPopGame` and
stops when no node is extractable and the level is not won.

## Reproduction

The autoplay harness shares **one generator across the whole campaign**, and
the diversity ledger is session state — so a board depends on every board
before it. Generating L592 in isolation produces a *different* board and does
not reproduce. Sequential generation reproduces it exactly, including the tap
order.

Replaying `hard L592` route 0 with a solvability check after every tap:

```
tap1 id5  left=24 solvable=true
...
tap6 id1  left=19 solvable=true
tap7 id2*RELAY left=18 solvable=false   <- here
```

Popping the relay is what destroys solvability.

## Root cause

`_relayIsSoftlockSafe` proves the relay safe against the hardest reachable
state in which it can be popped: `allNodes \ must`, where `must` is the closure
of nodes that must already be gone. For L592 the relay faces left with a clear
ray, so `must` is **empty** — the worst case is the full board.

Evaluating that worst case two ways:

| worst case post-relay-pop | `isSolvable` |
|---|---|
| **phase groups stripped** — what the proof saw | **true** → relay accepted |
| **as shipped** — what the player got | **false** → strandable |

`enrichLevel` assigned phase groups at `level_enrichment.dart:993`, **after**
the relay block at :916–991. A phase gate strictly tightens legal tap order, so
the proof was performed on a board that never shipped.

This is the §0.3 pattern exactly: *a correctness check that does not sit at the
last choke point is not a check.* The predicate's own soundness argument is
fine — it was being handed the wrong board.

## Fix

Move the phase-gate assignment **above** the relay block, so the relay proof
runs against the board that ships.

Phase assignment itself is unchanged: `chunkSize` reads `result.length`, and
the relay block substitutes node *kinds* without adding or removing nodes.
Relays that cannot be proven safe under phase gating are now rejected, and the
level ships without a relay — the behaviour the block already had for that case.

## Verification

- `autoplay_600_test`: **5400/5400 won, 0 stranded** across all three modes
  (was 4 stranded).
- Funnel re-measured on the fixed tree and unchanged — Hard rankable 0.56,
  `non-novel` 166, mortality 49.8% `components` / 22.0% CUD. Relay placement is
  enrichment-time and does not touch selection, as expected.

## New guard: `relay_softlock_regression_test.dart`

`autoplay_600_test` is `@Tags(['report'])`, so **the harness that catches
soft-locks does not run on an ordinary `flutter test`**. That is how a
reachable soft-lock survived to ship into a corpus. The new test is the same
engine and method, medium + hard, in the **default suite**.

It is pinned at the full 600 levels deliberately. A 150-level prefix runs four
times faster and **passes on the broken tree** — verified before committing to
the range, because a regression test that does not fail on the defect it names
is worse than none. At 600 it reproduces all four failures and prints
`relays=1, phaseGroups=2` on every one, which is the defect's fingerprint.
Cost: 48s.

## Still open: the two-relay path is unsound, and unreachable

`relay_softlock_property_test`'s two-relay case still fails — it finds boards
that soft-lock despite `_relayIsSoftlockSafe` returning true. That is a
separate defect in the predicate, not the ordering bug fixed here; the test
runs with `phaseGateCount: 0`, so this fix does not touch it.

**It cannot reach a player.** Measured across all three modes × 600 levels,
every shipped board has **0 or 1** relays — easy 600×0, medium and hard 250×0
and 350×1. Nothing budgets two.

Documented at the call site rather than guarded with an `assert(false)`: the
property test drives that exact path to demonstrate the defect, and an
assertion would replace its useful failure with a crash. Anything that starts
budgeting two relays must fix the predicate first.

The one-relay case of the same file reports `Tested 0 boards` — its 5×5 config
never yields a single-relay board, so that half asserts nothing. Left as-is;
the file already documents that its exhaustive search does not terminate at
campaign scale, and the new regression test now covers the single-relay case on
real campaign boards instead.
