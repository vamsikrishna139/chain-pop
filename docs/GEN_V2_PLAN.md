# Gen V2 — plan, contract and gates

Gen V2 is the second generator contract for **Hard campaign boards** and the
**Daily** (`generationVersion: 2`). Gen V1 (`generationVersion: 1`) stays in
the tree unchanged and keeps producing every board a player has already been
able to reach.

The code links here from `level_manager.dart`, `level_configuration.dart`,
`level_generator.dart`, `chain_pop_persistence.dart`, `main.dart` and the
`test/game/levels/generation/v2/` gate tests.

---

## 1. What changes for a player

| Area | V1 (≤ 1.0.0+9) | V2 (1.0.0+10) |
|---|---|---|
| Hard frame | square 8×8-ish | portrait **7×9** (65%) or **7×10** (35%); relief positions 1–3 of each world short, climax 20–25 tall |
| Hard nodes | ~20–30 | **28–40** (median 30–36), at most 0.88 nodes per mask cell |
| Hard pacing | flat | 25-level world sawtooth: relief 1–3, ramp 4–14, build-up 15–19, climax 20–24, Guardian 25; lock-finale twist at position 17 |
| Directives (all modes, V2 levels only) | `levelId % pool` | every directive once per block of five levels, seeded per block (bosses unchanged) |
| Daily | V1, 1–3 relays | **one relay at most on every date** (past dates included); V2 boards from **2026-12-01** |
| 3 stars (campaign, all modes) | directive met | directive met **and at most 1 jam**; applies to replays of old levels too (stars already earned are kept). Daily and tutorial grading unchanged |

Easy and Medium **boards** are unchanged: `isGenV2Dense` is Hard-only. Their
directive rotation does change on levels at or above the cut-over.

Product sign-off (2026-11-18): the Daily relay cap on all dates (so v9 and v10
players see different Daily boards during the rollout) and the 1-jam 3-star
rule are accepted. The tutorial's START CAMPAIGN sends the player to their
own selected mode.

## 2. Determinism contract

A V2 board is a pure function of `(levelId, mode)` (campaign) or the date key
(Daily):

* **A fresh `LevelGenerator.neutral()` per level.** V2 never reads or writes
  the shared diversity ledger, so boards do not depend on play order. That is
  also what makes it safe to build them on a worker isolate and to prefetch
  the next level.
* **Work budget, never wall clock.** `LevelManager.genV2WorkBudget = 48`
  constructions (campaign), `dailyWorkBudget = 64` (Daily). A wall-clock
  budget would ship a different board on a slow phone than on a fast one.
* **Own seed stream.** V2 dense boards XOR the primary seed with `0x2B992DDF`,
  so a V2 board is never a near-copy of the V1 board for the same id.

## 3. Cut-over (who gets V2)

Decided **once per mode** at the first launch of a V2 build and stored in Hive
(`gen_v2_from_<mode>`), see `LevelManager.resolveGenV2FromLevel`:

* No progress in the mode (nothing past L1 unlocked, no stars on L1): V2 from
  **level 1**.
* Otherwise: V2 from **highestUnlocked + 1**. Every level the player could
  already have seen keeps its V1 board.
* A stored value is never recomputed.
* **Reset Game Data** and **Delete my data** (`resetLocalProgress`) set every
  mode back to V2-from-1, in memory and storage, with no restart.

Daily: `genV2DailyFromKey`, default `kGenV2DailyLaunchKey = 20261201`. A
month boundary keeps each calendar month on one generator. Test builds can
override it with `--dart-define=GEN_V2_DAILY_FROM=yyyymmdd`.

The served-level cache is keyed by version, so V1 and V2 boards never mix.

## 4. Runtime

* `LevelManager.getLevelAsync` builds V2 campaign boards on a worker isolate
  (`Isolate.run`); the cache lookup, the V1/V2 decision, fallback reporting
  and the cache write stay on the main isolate. V1 stays synchronous (shared
  ledger). If an isolate cannot be spawned the board builds in place.
* **Nothing on the V2 path may touch `dart:ui` engine objects** (`Path`,
  `Picture`, `Paragraph`, …): they throw off the root isolate, and the
  in-place fallback above hides that by quietly building on the UI thread.
  Until 2026-11-18 the pentagon mask did exactly that (`Path.contains`); it
  now uses `polygonContainsPoint`, a float32-exact port of
  `SkPath::contains`. `layout_mask_isolate_test.dart` sweeps V2 on a worker
  isolate.
* `prefetchLevel` builds the next V2 level 800 ms after a level opens, so
  **Next** opens on the first frame. Concurrent requests for one level share
  one build. V1 is never prefetched.
* A level that opens without a cached board shows "Building level…".
* A generation failure ships a real fallback board and reports
  `level_generation_fallback` (analytics) plus a Crashlytics non-fatal.

## 5. Gates

All in `test/game/levels/generation/v2/` unless noted. A red gate is a
finding to record here, never a threshold to loosen in place.

| Gate | What | Threshold | Test |
|---|---|---|---|
| G1a | V1 boards never move | byte-identical to the pre-V2 snapshot | `v1_frozen_test.dart` (`v1_snapshot.json`) |
| G1b | V2 determinism | reverse-order regeneration of L1–100 identical | `gen_v2_gate_test.dart` |
| G2 | Latency (Hard L1–300 + 60 Dailies) | **p95 ≤ 300 ms, max ≤ 1,500 ms** | `gen_v2_gate_test.dart` |
| G3 | Validity + solvability | 0 failed layouts, 0 stuck in 3 random autoplay routes | `gen_v2_gate_test.dart` |
| G4 | Density / ergonomics | min nodes ≥ 28, median 30–36, median cover ≥ 70%, ≥ 95% of boards with ≥ 44 px cells | `gen_v2_gate_test.dart` |
| G5 | Difficulty band | ≥ 90% in band (evaluator scaled for node count) | `gen_v2_gate_test.dart` |
| G7 | Cut-over + cache | who gets V2; served cache never mixes versions; reset; rollback bound | `gen_v2_cutover_test.dart`, `gen_v2_async_test.dart` |
| G10 | Shape | ≤ 5% of boards with a dark rectangle > 25% of the frame | `gen_v2_gate_test.dart` |
| — | Shipped path | `LevelManager.getLevel` == the board the gates measure | `gen_v2_shipped_path_test.dart` |
| — | Twists | micro-twist levels carry their preset mechanics | `gen_v2_twist_test.dart` |

No test in this tree carries the IDs G6, G8 or G9.

`gen_v2_gate_test.dart` is tagged `corpus`; run it explicitly
(`flutter test test/game/levels/generation/v2/gen_v2_gate_test.dart`) or as
part of the full sweep (`flutter test`, nothing excluded).

M1 depth metrics (core-relevant tap fraction, taps/nodes, opening histogram,
void-region fraction, nodes per mask cell) are printed by the gate test and
not yet gated.

### G2 latency — why 300 ms still holds

Generation moved to a worker isolate and the next level is prefetched, so a
slow build no longer freezes the UI. The limit was kept anyway: the cases
prefetch cannot cover (level select, first level after a cold start) show
"Building level…" for the whole build, and a cheap phone is several times
slower than the dev Mac the gate runs on. 300 ms p95 on the Mac is what keeps
that wait near the 1.5 s device target.

Record (M1 Pro, `flutter test`, JIT with asserts):

| Date | Hard p50 / p95 / max | Daily p50 / p95 / max | Note |
|---|---|---|---|
| 2026-11-17 | 181 / **390** / 770 ms | 225 / 316 / 601 ms | red: p95 over 300 |
| 2026-11-18 | 80 / **183** / 320 ms | 108 / 156 / 281 ms | green after removing per-candidate set copies in `CandidateScorer` and the O(n³) key-map rebuild in `RetrogradeConstructor._enforceOpeningTarget`. Boards byte-identical (fingerprints of V2 Hard L1–300, V1 all modes L1–60, 40 Dailies × both versions). |

Device numbers are in §7.

## 6. Rollout and rollback

**Rollout.** Ship 1.0.0+10 as a staged rollout (10–20% first). Watch the
`level_generation_fallback` event and Crashlytics non-fatals
(`Level generation fell back …`), ANRs, crash-free rate and reviews against
the 1.0.0+9 baseline before widening.

**Why a plain downgrade is not clean.** v10 stores `gen_v2_from_<mode>` on
first launch. v9 ignores the key and generates V1 everywhere, so a player who
played V2 Hard levels would see those boards change under them, and stars
earned on a V2 board would sit on a different V1 board. Re-upgrading later
resumes V2 from the stored cut-over.

**Rollback = fix forward with the switch.** `LevelManager.kGenV2Enabled`
(`--dart-define=GEN_V2_ENABLED=false`). A 1.0.0+11 built with the switch
off:

* per mode, stores `gen_v2_until_<mode>` once: the player's
  `highestUnlocked` (or `from - 1` when they never reached a V2 level).
  Levels in `[from, until]` keep their V2 board; everything after is V1;
* turns the V2 Daily off (`genV2DailyFromKey = null`);
* after Reset / Delete my data, makes the player all-V1 (`until = 0`).

A stored bound is never recomputed, including by a later build that turns V2
back on. That keeps the levels a player played under the rollback on V1. A
re-enable that resumes V2 past the bound would need a second cut-over range;
that has not been built.

Remote Config was considered as a server-side switch and not added: it is a
new SDK (installation IDs; privacy policy, Data safety form and
`docs/sdk_inventory.md` would all change) for a decision that the switch
above already makes reversible within one release cycle.

## 7. Device evidence

2026-11-18, profile builds of `new_enhances` at 96b36ae (sample ad units).
"First" = the first board built after a cold start.

**Pixel 8a** (on-device generation, worker isolate, same call as the app):

| Run | p50 | p95 | max |
|---|---|---|---|
| Hard V2 L1–150 | 140 ms | 305 ms | 553 ms |
| Daily V2, 60 dates from 2026-12-01 | 201 ms | 289 ms | 532 ms |

0 worker-isolate failures. In the app, the first Hard level after a cold
start opened in 120–331 ms.

**Cheap-phone emulator** (2 vCPU, 2 GB, 720×1600; the host was at load
40–110 from other work, so these are pessimistic and noisy): Hard V2
benchmark p50 135 / p95 307 / max 1,367 ms. Cold opens of L202–210 took
119–2,288 ms. The first build after a cold start took 2.9–13.7 s on that
host and has not been reproduced on a real device; **re-measure on a real
budget phone before widening the rollout.** One ANR, "stuck fence / GPU
hang", came from the emulator's host-GPU passthrough under that load, not
from app code.

**Checks passed**

* Hard L1–20 tour (autoplay) on the emulator: every board fits at 720 px
  wide with no toolbar or banner overlap. Every **Next** opened from the
  prefetch cache (`cached in 0 ms`, 36 of 36).
* The same V2 board for a level on the emulator and the Pixel, and after a
  restart.
* Upgrade v9 → v10 keeps progress and stars. Levels the player could already
  reach stay V1; V2 starts at the frontier.
* Fresh install: Hard L1 is a 7-wide V2 board.
* Reset Game Data and Delete my data: Hard L1 is V2 without a restart.
* Rollback build (`GEN_V2_ENABLED=false`): played V2 levels keep their board.
  After a reset L1 is V1. A later V2-enabled build keeps that player on V1
  until the next reset, which brings V2 back.
* Daily: with `GEN_V2_DAILY_FROM=20261115` Nov 18 is a 7×9 V2 board; the
  default build serves the V1 board for the same date. The calendar renders.
  Ticks and stars after completing a V2 Daily were checked by tests only.
* Offline: no banner and no reserved gap; the toolbar sits at the bottom.
* Main-menu Back: "Press back again to exit", then exit within 2 s.

**Found while testing**

* Fixed: the pentagon mask threw on the worker isolate, so those levels
  silently built on the UI thread (§4).
* **Needs a product call:** V1 boards (Easy, Medium, and Hard below the
  cut-over) can change on replay after an app restart. This comes from
  W2.4 in this PR (5454e59), which persists the diversity ledger. Before
  that, the ledger restarted empty, so a level replayed first after launch
  got the same board every time. Stars are kept per level id, so no progress
  is lost; only the board looks different. V2 boards are not affected.
