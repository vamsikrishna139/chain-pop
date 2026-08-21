# Hard ×500 Autoplay Playtest — 2026-06-15

**Device:** Pixel 8a (akita), USB, debug build with `--dart-define=AUTOPLAY=true`
**Harness:** `lib/dev/autoplay_harness.dart` — solver-driven (`LevelSolver`), one removable
node tapped every 55ms, gameplay timers suppressed, silent audio, no-op ads.
**Plan:** 50 Easy + 50 Medium warmup, then **500 Hard** (600 total). Level ids swept 1..N.
**Raw data:** `autoplay_raw_2026-06-15.log`, `hard_solvetimes_2026-06-15.dat` (level, ms).

> What "ms" measures: wall-clock autoplay time per level ≈ (sequential solver taps × 55ms)
> + win-settle. It is a good proxy for **structural solve depth** (removal-wave count /
> parallelism) and device render cost. It is **not** a measure of human-perceived
> difficulty or fun — the bot can't feel juice, readability, or tension.

## Headline results

| Mode   | Wins | Stuck | avg ms | max ms |
|--------|------|-------|--------|--------|
| Easy   | 50   | 0     | 715    | 1484   |
| Medium | 50   | 0     | 1026   | 1483   |
| Hard   | 500  | 0     | 2130   | 15752  |

**600/600 cleared, zero stuck, zero softlocks.** The solvability invariant held across
the entire 500-hard sweep — including the relay/locked-node mechanics. This is the
strongest takeaway: the generator is not shipping unsolvable or soft-lockable hard levels.

## Hard difficulty progression — essentially FLAT

Solve-time distribution across the 500 hard levels is extremely tight:

```
p50=2192ms  p75=2308ms  p90=2393ms  p95=2452ms  p99=2586ms
min=1442ms (L18)   max=15752ms (L302, isolated outlier — see below)
```

Per-100 band means (L302 excluded, it inflates its band):

```
L1-100   : mean 2031ms   max 2552ms
L101-200 : mean 2037ms   max 2543ms
L201-300 : mean 2098ms   max 2601ms
L301-400 : mean ~2180ms  (raw 2317ms is the L302 spike)
L401-500 : mean 2165ms   max 2601ms
```

**There is no intra-Hard ramp.** Level 1 of Hard and level 500 of Hard are
indistinguishable in structural workload. This matches the known design intent (Hard
ships ~25 nodes/8×8 by a load-bearing floor), but for a 500-level *campaign* it means a
player gets the same structural challenge at L450 as at L50.

### Two structural families
The histogram is bimodal: a "lighter" cluster (~1500–1750ms, ~110 levels) and the
"standard" mass (~2000–2500ms, ~390 levels). So Hard isn't monolithic — there's a
breather/standard mix — but the split is not arranged into any rising pattern; it reads
as noise rather than rhythm.

### Milestone levels read as breathers, not climaxes
The synthetic milestones (every 50: mod-100→0 sparse-sniper, mod-100→50 max-density)
are consistently in the *lighter* band, not the heavier one:

```
L50 1466  L100 1447  L150 1486  L200 1752  L250 1482
L300 2073  L350 1789  L400 1734  L450 1567  L500 2110
```

If milestones are meant to be memorable peaks, they currently solve *faster* than
their neighbors — i.e. they play as breathers. Either intentional pacing relief or a
missed opportunity for a climax beat.

## Anomaly: L302 = 15752ms (6× the next-slowest)

L302 is a complete singleton — neighbors L298–L306 are all 1500–2400ms. The device log
ring buffer had rotated past its timestamp, but the GC samples that remained show tiny
pauses (~6.6ms) and a healthy heap (90% free, 23/256MB), so memory pressure is unlikely.
Most probable cause: a one-off scheduler / Choreographer stall starving the 55ms autoplay
timer, **not** an intrinsic property of that level. It still solved (well under the 30s
watchdog).
→ **Action:** re-run L302 in isolation to confirm transient; if it reproduces, profile
that seed for a frame-time cliff on heavier boards (matters more on low-end devices).

## Observations

1. **Robustness is excellent** — 0 stuck across 600 levels, including relays. Ship-grade
   on the solvability dimension.
2. **Flat Hard curve** — biggest design question. Structurally uniform from L1 to L500.
3. **Milestones are anti-climactic** (lighter than neighbors).
4. **Tight variance** is good for fairness but contributes to sameness over a long session.
5. **One perf hitch (L302)** worth a targeted look.

## Suggested improvements

- **Add a gentle intra-Hard progression.** Not raw node count (that floor is load-bearing
  per design) but *depth*: nudge removal-wave count / reduce early parallelism as level id
  climbs, or rotate motif/constraint density. Goal: L450 should feel a notch deeper than L50.
- **Make milestones land as beats.** If breathers are intended, lean in visually so they
  read as deliberate relief; if peaks are intended, raise their depth above neighbors.
- **Profile L302's seed** for the frame hitch; add a perf-budget assertion if a cliff exists.
- **Human pass still needed.** Autoplay proves *solvable + structurally uniform*. It cannot
  judge readability, ray-preview clarity, animation juice, or perceived difficulty — do a
  short manual session for those before launch.

## Limitations of this method
Solver autoplay = optimal/greedy removal of any currently-removable node. It does not
explore *wrong* moves a human would make, so it never measures how punishing a mistake is,
how legible the next move is, or how the level *feels*. Treat these notes as a structural
+ solvability QA pass, complementary to (not a substitute for) human playtesting.
