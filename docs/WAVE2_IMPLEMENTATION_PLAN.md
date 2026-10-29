# Wave 2 — implementation plan (against the 2026-10-29 tree)

Source of scope: `docs/FINAL_PLAY_STORE_LAUNCH_PLAN.md` "Wave 2 — post-launch"
and `docs/PRODUCTION_AUDIT.md` § Wave sequencing → Wave 2. Every item below was
re-checked against the code on `new_improvements` @ `a4e65d4`; line numbers are
from that tree.

Wave 2 is post-launch by decision. None of it blocks the Play release.

## 1. Where each Wave 2 item stands today

| Item | Audit ref | Status in code today |
|---|---|---|
| Milestone-seed fallthrough | P1-10 | **Done.** Fixed 2026-08-20 (relaxed lock pool, `seedMechanicShort` retains the seed). Drop from Wave 2. |
| Director-internal deadline | P2-4 | **Mostly done.** `overBudget` is checked between K-candidates (`level_generator.dart:1151`, `:1187`), the seeded path has its own stopwatch (`:659`), the real hot spot (`computeSearchEffort`) is capped (T2.0), and Daily runs in `Isolate.run`. A single construction still can't be interrupted. Keep only as "re-measure, close if quiet". |
| Daily determinism | — (not named in Wave 2) | **Half done.** The session-state half is fixed (fresh `LevelGenerator.neutral()` per Daily, `level_manager.dart:131`). The wall-clock half is **open**: the 400 ms `dailyGenerationBudget` (`:33`, `:142`) decides which candidate ships. |
| Pre- vs post-enrichment drift | P2-1 | **Open.** Metrics are still computed on the raw board (`level_generator.dart:1204`); enrichment runs afterwards (`:691`, `:885`). No drift measurement exists. |
| Portals fix-through | P1-6 | **Open — all of it except the phase-gate half of (d).** (a) Both base-1000 decodes are still there: `retrograde_constructor.dart:192`, `sightline_table.dart:86-87`. (b) `enrichLevel` still drops `portalPairs` and `silhouetteId` (`level_enrichment.dart:35`, `_withNodes` at `:189`). (c) `BoardMaskComponent` doesn't render portals. (d) The relay probes (`:989`, `:1030`, `:1118`) still omit `portalPairs`. Phase gates now run *before* relays (`:924-956`), so that half of (d) is fixed. (e) No tutorial. |
| `computeSearchEffort` flag-gate | P2-9 | **Open (low value).** It's now capped, but it still runs on every `LevelMetrics.compute` (`metrics.dart:124`) and nothing in `lib/` reads `searchEffortScore`. |
| DiversityLedger persistence | P2-9 | **Open.** `serialize`/`restore` exist (`diversity_ledger.dart:312-326`); nothing calls them. |
| Graceful release-mode failure | P2-5/6/7 | **Open.** `_guardHardExpertOpening` still throws `StateError` (`level_generator.dart:2299-2306`). Layout validation is still assert-only (`level_manager.dart:50`, `:148`). The emergency fallback is still a one-node board (`:162`). |
| Accessibility | P1-8 | **Open.** No reduced-motion setting anywhere (`grep reducedMotion\|disableAnimations lib/` → 0). `colorblindPalette` still remaps only the node palette (`chain_pop_game.dart:243`). |
| Lifecycle fixes | P2 runtime | **Open, mostly.** `_handleFoul` has no `mounted` guard (`game_screen.dart:703`). Finale pitch 1.6 vs clamp 1.5 (`chain_pop_game.dart:803` / `game_audio.dart:107`). `_interstitialLikelyDue` reads the static `SessionCampaignStreak.wins` (`game_flow_controller.dart:293`) while wins go through `_host.streak` (`:140`). `_setupBoard` doesn't clear `_rayPreview` (`chain_pop_game.dart:332`; verify before fixing). |

## 2. Generator-freeze rule

Gen V1 is frozen: after the freeze, a red corpus canary counts as a defect,
not as a reason to re-pin. Three workstreams below **change shipped boards**:

- W2.2 (Daily) changes Daily boards only. The campaign corpus is unaffected, and stars are keyed by `dayKey`, so the shift is invisible to players.
- W2.4 (ledger persistence) changes campaign boards only for returning players. `LevelGenerator.neutral()` corpora are unaffected.
- **W2.7 (portals) changes Hard L626+ in the corpus.** It's an explicit Gen V2 unfreeze and needs a signed-off re-baseline. Don't start it as a "fix".

## 3. Workstreams, in order

Each one is a separate branch and PR.

### W2.1 — Lifecycle hygiene · S · low risk
1. `game_screen.dart:703` `_handleFoul`: add `if (!mounted) return;` before `setState`.
2. `chain_pop_game.dart:803`: cap the finale at `1.5`, or widen the clamp in `game_audio.dart:107` to 1.6. Pick one and keep them equal.
3. `game_flow_controller.dart:293`: read the injected `_host.streak` instead of the static `SessionCampaignStreak.wins`. Expose `wins` on the tracker interface if it's missing.
4. `chain_pop_game.dart` `_setupBoard`: call `hideRayPreview()` when rebuilding nodes. First confirm the relayout-during-touch repro still exists.
5. `_openSettings`: decide whether the settings sheet counts as paused for the ambient bed. If yes, duck ambient while the sheet is open. Otherwise record "intended" in a comment.

**DoD:** widget test for a jam after dispose (no exception). Unit test that `_interstitialLikelyDue` follows an injected tracker.

### W2.2 — Daily board identical on every device · S–M · medium risk
Root cause: three wall-clock reads sit on the Daily path, and any of them can change the output.
- `dailyGenerationBudget` → `budgetWatch` / `seedWatch` (`level_generator.dart:659`, `:790`, `:943`)
- `computeViablePathCount`'s `maxMicroseconds`, used when `includeViablePath: true` (`:1491`). Confirm whether ranking reads it.
- `_EffortBudget.maxMicroseconds` (`search_effort.dart`). Harmless while nothing reads the score; W2.3 removes it from this path anyway.

Steps:
1. Add a deterministic work budget to `generateDailyChallenge`: a fixed `maxAttempts` / candidate count (e.g. `dailyMaxAttempts`) and **`timeBudget: null`**. In `level_manager.dart:140`, drop `timeBudget:` for the Daily.
2. Wherever the Daily path calls `computeViablePathCount`, use an expansion cap only (no microsecond cap).
3. Calibrate the cap: generate 365 date keys (2027) in a `slow`-tagged harness and record attempts used plus wall time on the Pixel 8a profile. Pick the smallest cap where the p99 date still finds an in-band board. Off the main thread is fine (isolate), but keep p99 under ~1.5 s so the "Building…" spinner stays short.
4. Keep the isolate. It handles latency, not correctness.

**DoD / tests:**
- New test: `_generateDaily(k)` with the clock forced to "always over budget" equals the board with "never over budget", for 30 keys. Inject the clock, or simply assert that the Daily path takes no `timeBudget`.
- `daily_determinism_test` passes inside the full loaded suite, not just alone.
- Update `FINAL_PLAY_STORE_LAUNCH_PLAN_HYBRID.md`'s "Daily deterministic" box.

### W2.3 — Stop paying for unread search effort · S · low risk
1. Add `includeSearchEffort` (default `false`) to `LevelMetrics.compute`, mirroring `includeViablePath`. Skip `computeSearchEffort` (`metrics.dart:124`) unless it's set.
2. Pass `true` only from the report/test harnesses that print it. Grep `test/` for `searchEffortScore`.

**DoD:** no test reads a zero score by accident. The generation-latency benchmark shows the saving; record the number in the PR.

### W2.4 — Persist the DiversityLedger · S · low risk
1. Persistence: add a `diversity_ledger_bits` key (List<int>) next to the settings keys in `hive_chain_pop_persistence.dart`.
2. Startup: after Hive opens and before the first `LevelManager.getLevel`, call `LevelManager.generator.ledger.restore(bits)`. Expose the ledger on the generator if it isn't public.
3. Save: after each campaign level is *served* (not won), write `serialize()`. It's capped by `historicalCap`, so the write is small. Debounce it, or write on `AppLifecycleState.paused`.
4. Never touch the Daily (it uses a fresh generator, by contract) or tests (`neutral()`).
5. Include it in "Reset my data".

**DoD:** unit test that a restored ledger rejects a fingerprint served before the "restart". Corpus canaries unchanged.

### W2.5 — Graceful release-mode generation failure · S · low risk
1. `_guardHardExpertOpening` (`level_generator.dart:2299`): `assert` in debug. In release, return a rejection that the caller treats like any failed candidate, never a `StateError`.
2. Run `LevelData.layoutValidationMessage` in release too (it's cheap). On failure, treat it as a generation failure and record a non-fatal to Crashlytics.
3. Replace the one-node `_emergencyFallback` with a known-good board: generate one of the `seed_registry` boards with a fixed salt and no budget, and fall back to the one-node board only if that throws. Log every fallback as a non-fatal plus an analytics event.
4. Add a test that drives `generateFromConfiguration` to `'Director exhausted …'` and asserts the fallback path (audit P2-7: no test reaches it today).

### W2.6 — Measure enrichment drift (P2-1) · M · investigation only
Do this **before** W2.7, because portals change the same metrics.
1. A `slow`-tagged harness over `LevelGenerator.neutral()`, L1–1000 × {Medium, Hard, Expert}: compute `LevelMetrics.compute` on the raw board and on the enriched board.
2. Report, per tier, the deltas in `firstLegalMoveCount`, `waveZeroWidth`, `waveDepth`, FSR, BF and CUD, plus the % of boards that pass `DifficultyProfile.passes` raw but fail it enriched.
3. Decision rule, written down before running: if fewer than 5% of boards in any tier leave band, document the drift and close. Otherwise open a follow-up to re-check the band post-enrichment. That's a generator change, so it falls under §2.

**DoD:** the report is committed under `docs/playtests/`, with the decision recorded.

### W2.7 — Portals fix-through (P1-6) · L · high risk · Gen V2
Build it dark: first add a flag so `ProgressionProfile.clampPortal` (`progression_profile.dart:90`) returns 0. The rest lands behind the flag, and it flips only at the end.

1. **Decode (a).** Add `gridCellX(key)` / `gridCellY(key)` to `grid_cell_key.dart` (`key & 0xffff`, `(key >> 16) & 0xffff`). Use them at `retrograde_constructor.dart:192` and `sightline_table.dart:86-87`. Unit test: round-trip every cell on a 10×10 grid, including the audit's (3,4) → 262147 case.
2. **Preserve fields (b + d).** Add `LevelData.copyWith` and use it at every rebuild site: `level_enrichment.dart:35` and `:189`, plus the probes at `:989`, `:1030` and `:1118`. `portalPairs` and `silhouetteId` then survive enrichment, and the relay proof sees the board that ships. Audit `level.dart` for any other field the hand-built constructors drop.
3. **Render (c).** Draw paired portal glyphs on their cells in `BoardMaskComponent`, with a shared index or colour per pair. Under `colorblindFriendly`, add a number or shape, not just colour. Keep the existing node/arrow look unchanged.
4. **Proofs.** In `relay_softlock_property_test.dart:168-169`, replace `phaseGateCount: 0, portalPairCount: 0` with fuzzed non-zero values. Extend `relaysafe_soundness_test.dart` to fuzz with portals and gates together. **Don't weaken `_relayIsSoftlockSafe` to make portals fit.**
5. **Tutorial (e).** A one-time coach mark the first time a board with `portalPairs.isNotEmpty` loads (Hard L626 is the first). Persist the "seen" bit with the other tutorial flags.
6. **Turn it on and measure.** Flip the flag, then run the 600-level device autoplay over L626–1000 Hard, check generation latency (the decode fix makes sightlines *stricter*, so expect more construction failures on sector-6+), and re-baseline the adversarial corpus with an explicit sign-off note.
7. Analytics: `game_flow_controller.dart:77` already reports `portalPairCount`. It has always been 0, so watch it go non-zero after rollout.

**DoD:** every proof test is green with portals on, autoplay is clean, portals are visible and taught, and the corpus re-baseline is signed off.

### W2.8 — Accessibility (P1-8) · M · low risk
1. **Colorblind for meaning-carrying colours.** Core gold ring (`node_component.dart`), blocker-flash red, relay green, and ray amber (`ray_preview_component.dart`). Under `colorblindPalette`, add a non-colour cue: ring dash pattern, a flash outline, a relay glyph. Only when the toggle is on; the default look doesn't change.
2. **`ambientMotion` gates all ambient animation:** twinkle, extraction ripples, streak edge glow, scanlines and the breathing vignette in `ambient_background_component.dart`, not just mote drift.
3. **New `reducedMotion` setting.** Add the field to `GameSettings`, a Hive key, and a toggle in `game_settings_sheet.dart`. It defaults to `MediaQuery.disableAnimations` on first run. It gates confetti, jam shake, ghost trails, cascade ripple, nudge/pulse, relay sweep and the coach-mark bounce, swapping in instant or fade versions so information isn't lost.

**DoD:** a widget test per gate. A manual pass on the Pixel with the system "Remove animations" setting on.

## 4. Sequencing summary

W2.1 → W2.2 → W2.3 → W2.4 → W2.5 are small and independent; each can ship in any point release.
W2.6 must finish before W2.7. W2.8 can run alongside anything.
W2.7 is the only large, high-risk item and the only one that unfreezes the generator.
Re-order by post-launch data (the launch plan's intent): for example, if Hard retention past L600 is poor, W2.7 moves up; if accessibility complaints arrive, W2.8 does.
