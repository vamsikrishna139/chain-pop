# Chain Pop Production Audit

> **What this file is.** The master state of the release. Every claim below was
> read out of the working tree, not out of a strategy doc, and carries a
> `file:line` cite so it can be re-checked or invalidated. When this document
> and any other doc in `docs/` disagree, **this one is newer** — but when this
> document and the *code* disagree, the code wins and this file is stale.
>
> **Audit basis:** branch `new_improvements`, working tree at commit `c747e4f`
> plus uncommitted changes. 140 files / 25,743 LOC in `lib/`, 100 test files.
>
> **Scope decisions taken by the product owner during this audit** (these shape
> the priorities and are not re-litigated below):
> 1. **Easy stays deliberately mechanic-free.** `MechanicBudget(coreCount: 0)`
>    for Easy at every level id is intentional design, not a bug. Consequence
>    accepted: no cores, no cascade finale, no Integrity HUD on Easy, ever.
> 2. **Android ships first.** iOS blockers are recorded but non-blocking.
> 3. **Portals get fixed through**, not disabled.
> 4. **UI Reskin (2026-08-14):** Playfield reference band `topReserved` shifted from 172/184 to 194.0/206.0 and `bottomReserved` to 102.0 to accommodate the new telemetry capsule and toolbar layouts. (Note: Corpus runs before and after this shift are not directly comparable due to layout differences).

---

## Overall Status

**NOT READY.** Two independent reasons, either of which is sufficient:

1. **The product is unobservable.** Exactly one analytics event exists in the
   entire codebase, and crash reporting is wired to a placeholder Firebase
   project, so it silently reports nothing. Shipping in this state means
   launching with no ability to tell whether anything is working — no funnel,
   no crash rate, no ad performance, no retention signal.
2. **Two defects can take value away from a player who did nothing wrong**: a
   won level can be destroyed before the win is recorded (P0-5), and the
   countdown keeps running while the player watches a rewarded ad (P0-4).

Neither is architectural. Both are small, local, and testable. The underlying
architecture is in good shape and is *not* the bottleneck — see
[Architecture Assessment](#architecture-assessment).

The honest summary is: **the machine is well built and almost entirely
uninstrumented.** The generation subsystem has had years of care applied to it;
the release surface around it has had comparatively little.

### Maturity by dimension (0–100)

| Dimension | Score | One-line reason |
|---|---:|---|
| Core gameplay | 78 | The extraction loop is sound and solvability is proven by construction. |
| Gameplay clarity | 62 | Rays, waves and blocker flash are good; phase gates and portals have no visual language at all. |
| Game feel | 58 | Strong visual layer, thin haptic/audio layer (2 haptic events total in the app). |
| Level quality | 62 | Solvability guaranteed; bands measured on a board the player never sees (P2-1); 40% of milestone levels lose their authored seed (P1-10). |
| Difficulty coherence | 60 | Opening band honestly recalibrated to `[3,11]`; node count is never band-gated. |
| Retention systems | 55 | Pacing/goals/streaks all exist and work; progression *reads* as flat for 125 levels (P1-1). |
| Monetization quality | 50 | Gating philosophy is genuinely good; the reward path is untested and can hang. |
| Technical stability | 65 | No known crash loops; several unguarded async/lifecycle edges. |
| Observability | 8 | One event. No crash delivery. |
| Store readiness | 40 | Android is close; signing can silently fall back to debug. |
| Accessibility | 45 | Settings exist and are read, but each covers less than its label implies. |

### Top 5 strengths to protect

1. **Solvability as a construction invariant.** Retrograde construction plus
   ID-order canonical solution means solvability is not a search result that
   might fail — it is structural. Do not trade this for topology.
2. **Relay softlock safety is a proof, not a sample.** `_relayIsSoftlockSafe`
   (`lib/game/levels/generation/level_enrichment.dart:340-404`) is a closure
   argument over the transitive `must` set, fuzz-corroborated against
   exhaustive search across 4000 boards
   (`test/game/levels/relaysafe_soundness_test.dart:125`). This is the single
   most valuable piece of engineering in the repo.
3. **The interstitial gating philosophy.** Three independent gates — session
   streak, lifetime engagement, and frustration suppression
   (`lib/services/ads/campaign_between_levels_ads.dart:20-52`) — plus quick-win
   suppression when an ad is due. This is more player-respecting than most
   shipped puzzle games. Do not weaken it.
4. **Measurement-first generator culture.** Bands were recalibrated to `[3,11]`
   because 276 instrumented candidates proved `[3,5]` structurally
   unreachable, rather than by widening a number to make a test pass. See
   `docs/OPENING_BAND_DECISION.md`.
5. **Dependency-injected seams throughout.** `AdsLocator`, `StorageLocator`,
   `SubscriptionLocator`, `GameScreenControllerHost`, injectable session
   trackers. The code is testable where it matters; it just isn't tested yet
   in the places that carry money.

### Top 5 risks

1. **Launching blind** (P0-1, P0-2). No funnel, no crash rate.
2. **Losing a won level** (P0-5). Restart is live during the cascade finale.
3. **The reward path has never been executed by a test** (P0-8). `RecordingAdService.showRewarded` always returns `false`, so no test has ever observed a successful grant.
4. **Silent release-build degradation** (P0-7, P0-9): debug signing and a dead purchase system both fail without any error.
5. **Progression reads as flat, and gets flatter with depth** (P1-1, P1-2, P1-10): one palette and one directive for the first 125 levels, world names that promise mechanics the budget never delivers, and 16 of 40 milestone levels silently shipping as ordinary boards.

### Product thesis for the next 30 days

> Instrument the game, stop it from ever taking a win or a fair timer away
> from a player, and make the first 125 levels *look and feel* like they are
> going somewhere. Do not add mechanics; make the ones that exist legible.

---

## Baseline health (verified this audit)

```bash
flutter analyze   # 1 error
flutter test      # exceeded 25 min wall time without completing
```

- **`flutter analyze` → 1 error**: unused local `waves` at
  `test/hard_1000_playfeel_report_test.dart:40`
  (`unused_local_variable`). Prior docs claiming "0 issues" predate the
  untracked report harnesses.
- **`flutter test` is not usable as a gate.** The full run exceeded **40
  minutes** without producing output. Measured breakdown:
  - A representative non-corpus subset (`test/services`, `test/models`,
    `test/theme`, `test/utils`, plus the solver and enrichment suites) is
    **119 tests in 5.8 s — all passing.** The ordinary suite is healthy and
    fast.
  - `test/game/levels/generation/corpus_benchmark_test.dart` alone takes
    **67 s** and **fails 1 of 4 tests** (see below).
  - `test/analyze_1000_levels_test.dart` did not complete within several
    minutes on its own.

  So the cost is concentrated in the corpus harnesses, which live in the
  default test path rather than behind a tag:
  `test/analyze_1000_levels_test.dart`,
  `test/hard_1000_playfeel_report_test.dart`,
  `test/game/levels/generation/campaign_depth_report_test.dart`,
  `test/game/levels/generation/corpus_benchmark_test.dart`. These are
  diagnostic *reports*, not assertions. **Action:** tag them
  (`@Tags(['corpus'])` + a `dart_test.yaml` exclusion) so `flutter test`
  returns in seconds and can be enforced pre-commit, with the corpus run kept
  as an explicit opt-in.

- **One genuine test failure**, in `corpus_benchmark_test.dart:47`:

  ```
  Milestone telemetry seed annotations milestone-overload on synthetic max-density IDs
    Expected: 'milestone-overload'
      Actual: <null>
  ```

  This is **not a stale expectation** — it is a correct canary catching a real
  content defect. Chasing it produced **P1-10**, the most substantive new
  finding in this audit. Do not "fix" it by relaxing the assertion.
- **No CI.** `.github/workflows` does not exist. Nothing enforces analyze or
  test on push.
- One skipped test in the repo: `test/widget_test.dart:74`
  (`skip: true, // Flaky/Hangs due to fakeAsync Timer orchestration`).
  Nothing under `test/game/levels/**` is skipped.

---

## P0 Issues — release blockers

### P0-1 · Analytics does not exist

**Evidence.** `grep -rn "logEvent\|FirebaseAnalytics" lib/` returns exactly two
hits, both the same call:
`lib/bootstrap/firebase_bootstrap.dart:28` → `FirebaseAnalytics.instance.logAppOpen()`.
There is no analytics service, no event constants, and no `logEvent` call
anywhere in `lib/`.

Of the 25 events named as the minimum set in the production prompt, **24 are
missing**: `session_start`, `session_end`, `tutorial_start`,
`tutorial_complete`, `level_start`, `level_complete`, `level_fail`,
`level_retry`, `node_tap`, `node_jam`, `hint_shown`, `hint_used`, `undo_used`,
`rewarded_ad_requested`, `rewarded_ad_started`, `rewarded_ad_completed`,
`rewarded_ad_failed`, `interstitial_eligible`, `interstitial_shown`,
`interstitial_failed`, `daily_started`, `daily_completed`, `purchase_started`,
`purchase_completed`, `purchase_failed`. Only `app_open` ships.

**Why this is P0 and not P1.** Every other improvement in this document is a
hypothesis. Without instrumentation there is no way to confirm or reject any of
them after launch, which makes the entire post-launch iteration loop — the
thing the production plan is built around — inoperable.

**Mitigating factor: the work is small.** All the state these events need
already exists at well-defined call sites, and is *already being written* to
`debugPrint` via `adDebug()` in debug builds only
(`lib/services/ads/ad_debug_log.dart:4-8`). The call sites:

| Event group | Existing call site |
|---|---|
| level complete / stars | `lib/screens/game/game_flow_controller.dart:38` |
| level fail / time up | `lib/screens/game/game_ad_coordination.dart:60`, `:107` |
| rewarded lifecycle | `lib/services/ads/google_mobile_ad_service.dart:199-231` |
| rewarded call sites | `lib/screens/game/game_ad_coordination.dart:184`, `:237` |
| interstitial gating | `lib/services/ads/campaign_between_levels_ads.dart:28-50` |
| purchases | `lib/screens/widgets/purchases_settings_section.dart:14`, `:32` |

**Recommended shape.** A single `AnalyticsService` interface behind an
`AnalyticsLocator`, mirroring the existing `AdsLocator`/`StorageLocator`
pattern, with a no-op implementation for tests. Do **not** instrument
`node_tap` — it is per-tap volume for no product decision. `node_jam` is worth
having (it is the difficulty-pain signal).

**Verify.** A test asserting the recording implementation receives
`level_start` → `level_complete` for a scripted win, and
`rewarded_ad_requested` → `rewarded_ad_completed` for a scripted grant.

---

### P0-2 · Crash reporting silently reports nothing

**Evidence.** `android/app/google-services.json` is a placeholder:
`project_id: "chain-pop-placeholder-replace-me"`,
`project_number: "000000000001"`,
`api_key: "REPLACE_ME_FIREBASE_ANDROID_API_KEY"`.

`Firebase.initializeApp()` therefore throws, is caught and swallowed
(`lib/bootstrap/firebase_bootstrap.dart:34-39`), and `crashReportingReady`
stays `false` (`lib/services/crash_reporting.dart:5-21`). Every downstream
`recordError` is a no-op. There is no `firebase_options.dart`; initialization
depends entirely on the native config file.

**Consequence.** Today, zero crashes and zero non-fatals reach Crashlytics —
including the two non-fatals that are correctly wired (ad preload failure at
`google_mobile_ad_service.dart:135`, `:182`; campaign generation failure at
`lib/screens/game_screen.dart:513`).

**Action.** Real `google-services.json` from the production Firebase project.
This is a credential step only the owner can perform. Add a release-build
assertion that `crashReportingReady` is true, so this can never silently
regress.

---

### P0-3 · A rewarded ad can hang the player forever

**Evidence.** `lib/services/ads/google_mobile_ad_service.dart` — the show path
ends in:

```dart
await ad.show(
  onUserEarnedReward: (_, __) { earned = true; ... },
);
final result = await done.future;   // no timeout
```

`done` is completed only from `onAdDismissedFullScreenContent` and
`onAdFailedToShowFullScreenContent`. Both are correctly guarded with
`if (!done.isCompleted)`, so **duplicate callbacks are safe and the reward
cannot be granted twice** — that part is right. The gap is that if the SDK
delivers neither terminal callback (a real failure mode on some Android
WebView/ad-renderer combinations), `done.future` never resolves and the
awaiting UI path is stuck with no feedback and no way out.

The awaiting callers are `lib/screens/game/game_ad_coordination.dart:184`
(undo) and `:237` (hint).

Separately, `await ad.show(...)` is **not** wrapped in try/catch. A throw
escapes `showRewarded`, escapes `handleHint`/`handleUndo` (neither catches),
and lands in `PlatformDispatcher.onError` (`lib/main.dart:42-47`), where it is
recorded as a **fatal** crash — for what is a recoverable ad failure.

**Action.** `done.future.timeout(const Duration(seconds: 45), onTimeout: () => false)`,
plus a try/catch around `show` that completes `false`. On timeout or throw the
player must be told the ad failed and **must not** have any budget consumed
(today they are not charged, which is correct — preserve that).

---

### P0-4 · The countdown keeps running during a rewarded ad

**Evidence.** The countdown skips a tick only under these conditions
(`lib/screens/game/game_timer_controller.dart:16-20`):

```dart
if (!_host.mounted || _host.hasWon || _host.isPaused) return;
if (_host.game?.hasWon ?? false) return;
```

`handleHint` and `handleUndo` (`game_ad_coordination.dart:164-201`, `:213-245`)
never set `isPaused`. Backgrounding does not help: the lifecycle handler only
flushes playtime (`lib/screens/game_screen.dart:598-606`); it does not stop the
timer.

**Consequence.** A player watching a 30-second rewarded ad for a hint loses 30
seconds of their level, and on a tight board can lose the level *while watching
the ad they chose to watch to help them win it*. This is precisely the
"monetization creates artificial frustration" pattern the production directive
forbids, and it is the highest-goodwill-cost defect in the audit.

**Note what is already correct:** the countdown *does* guard against expiring
a level already won by the engine (`:19-20`, the cascade-finale case). So the
pattern for the fix already exists in the same function.

**Action.** Set `isPaused` (or a dedicated `adInFlight` flag, to avoid showing
the pause overlay) around every rewarded show, and restore it in a `finally`
so an ad failure cannot leave the game permanently paused. The same treatment
is needed for the rewarded-hints coach dialog
(`game_ad_coordination.dart:31-57`), which today shows a blocking `AlertDialog`
on every hard/daily level start while the clock ticks — note that
`handleGameOver` and `handleTimeUp` *do* cancel the countdown before showing
their dialogs, so this is an inconsistency, not an unknown.

---

### P0-5 · A won level can be destroyed and the win never recorded

**Evidence.** On a core-win, `checkWinCondition` sets engine `hasWon = true`
and starts the finale (`lib/game/chain_pop_game.dart:743-746`):

```dart
if (coresRestored >= totalCores) {
  hasWon = true;
  networkIntegrity = 100;
  if (_boardLaidOut && activeNodes.isNotEmpty) {
    _startCascadeFinale();
```

`onWin()` does not fire until `_finaleWinAt`, which is
`0.15 + (n-1) * step + 0.5` seconds with `step` clamped to `[0.05, 0.09]`
(`:770-773`) — i.e. up to ~1.75s later. Flutter's `_hasWon` is only set when
`onWin()` lands (`lib/screens/game/game_flow_controller.dart:92`).

The bottom toolbar is gated on Flutter's `_hasWon`, not the engine's
(`lib/screens/game_screen.dart:943`: `if (!_hasWon)`). So for that whole
window the toolbar is live on an already-won level:

- **Restart** → `resetForRetry` → `engine.restart()` cancels the finale, and
  **the win is never recorded**. Direct progress loss.
- **Hint** → `showHint()` has no `hasWon` guard
  (`lib/game/chain_pop_game.dart:830-841`), so it fires mid-finale.
- **Pause** → `_togglePause` checks `_hasWon`/`isGameOver`, both still false,
  so it passes its guard and freezes the finale mid-ripple.

Undo *is* correctly blocked (`chain_pop_game.dart:682`).

**Action.** Gate the toolbar (and `showHint`, and `_togglePause`) on
`_hasWon || _engine.hasWon` rather than `_hasWon` alone. One expression,
several call sites. Then a regression test: start a finale, tap restart,
assert the win is still recorded.

---

### P0-6 · A corrupt Hive box kills startup before `runApp`

**Evidence.** `lib/services/storage/hive_chain_pop_persistence.dart:50`:

```dart
_box = await Hive.openBox<dynamic>(boxName);
```

No try/catch. The throw propagates through `StorageService.init()` →
`bootstrapChainPop()` → `main()` (`lib/main.dart:49-52`), and nothing catches
it. The user gets a dead native splash with no message and no recovery path,
and — because of P0-2 — no crash report either.

**Note what is already right:** every individual *value* read is defensively
coerced and clamped (`coerceHiveInt`/`coerceHiveBool`,
`hive_chain_pop_persistence.dart:55-60`, `:139-146`, `:159-166`). The
per-value hardening is good; the box-level open is not hardened at all.

**Action.** Wrap the open; on failure `deleteBoxFromDisk` and re-open once, so
a corrupt box costs the player their progress but not the app. Report the
event. A player with a bricked app is worse than a player with reset progress.

---

### P0-7 · Android release configuration can silently degrade

Three separate silent-failure modes:

**a. Debug signing fallback.** `android/app/build.gradle.kts:83-87`:

```kotlin
signingConfig =
    signingConfigs
        .findByName("release")?.takeIf { it.storeFile?.exists() == true }
        ?: signingConfigs.getByName("debug")
```

On the owner's machine `../../jks/key.properties` resolves, so a local release
build is properly signed. On CI or any clean checkout, `flutter build appbundle
--release` produces a **debug-signed** bundle with no error and no warning.

**b. A test device id ships in the release request config.**
`lib/services/ads/admob_config.dart:82-84`:

```dart
const List<String> kAdmobTestDeviceIds = <String>[
  'DC579E05100486C86E738D1DA7D9B9FD',
];
```

Applied unconditionally at `lib/main.dart:83-84` — including release builds.
That device receives test creatives against production ad units. Harmless to
revenue at scale, but it means the owner's own device cannot validate that
real ads serve in production.

**c. No portrait lock on either platform.** No `android:screenOrientation` in
`android/app/src/main/AndroidManifest.xml` (the `<activity>` block at `:7-28`
has none), `MainActivity.kt` is a bare `FlutterActivity`, and
`grep -rn "SystemChrome" lib/` returns **nothing**. The app is fully rotatable,
and the Flame board layout / HUD inset machinery has never been designed for
landscape.

Also: **`RecordingAdService` — a test double — ships in the release bundle**
(`lib/services/ads/recording_ad_service.dart:6`). It is only referenced from
tests, but it lives in `lib/`, so it is compiled in.

**Action.** Fail the release build loudly when the release signing config is
absent; gate `kAdmobTestDeviceIds` behind `kDebugMode`; add
`SystemChrome.setPreferredOrientations` for portrait; move
`RecordingAdService` to `test/`.

---

### P0-8 · The money path has zero test coverage

**Evidence.** No file under `test/` or `integration_test/` references Premium,
Subscription, RevenueCat, or purchases. `PremiumAdServiceDecorator` — the class
that decides whether a *paying customer* sees ads — is completely untested.

Worse, `RecordingAdService.showRewarded` **always returns `false`**
(`lib/services/ads/recording_ad_service.dart:43`). Since that is the only test
double available, **no test in the repo has ever exercised a successful
rewarded grant** for hint, undo, continue, or daily unlock. The entire "the
player watched an ad and got the thing" path is unverified.

Two live bugs follow directly from that lack of coverage, both in the
premium/SDK-init interaction (`lib/services/ads/premium_ad_service_decorator.dart:26-31`,
`lib/main.dart:77-92`):

- **Premium resolves late** (offline or slow network): `main.dart:77` reads
  `isPremium.value` before RevenueCat has answered, so `MobileAds.initialize()`
  runs for a paying customer.
- **Premium flips false in-session** (entitlement expiry): `bootstrap()` was
  skipped at startup, so no preloads exist *and* MobileAds was never
  initialized. A subsequent `showRewarded` calls `RewardedAd.load` against an
  uninitialized SDK.

And a third, in `lib/services/subscription/revenue_cat_subscription_service.dart:43-49`:
`addCustomerInfoUpdateListener` is registered *inside the same try block* as
the initial `getCustomerInfo()`. If that call fails — the exact offline case —
the listener is never registered, so **premium state cannot recover for the
rest of the app run**. A paying customer who launches offline sees ads until
they force-quit.

**Action.** Give `RecordingAdService` a configurable grant result. Then test:
premium bypasses all four ad types; a successful grant reaches the engine for
each of hint/undo/continue/daily; an ad failure consumes no budget; late
entitlement resolution still suppresses ads. Move the listener registration
out of the try.

---

### P0-9 · A missing RevenueCat key breaks purchases silently

**Evidence.** API keys come only from `--dart-define`
(`revenue_cat_subscription_service.dart:28`, `:33`). If the define is absent,
`Purchases.configure` is never called, the service stays permanently
non-premium (`:50-55`), and the "Remove Ads" button returns `unavailable` and
shows "Purchase could not be completed"
(`lib/screens/widgets/purchases_settings_section.dart:21-25`). There is no
build-time assertion anywhere.

A release built without the define ships with the paid product permanently
broken, and nothing in the build or the logs says so.

**Action.** Assert at bootstrap in release builds that the key is non-empty and
`configure` succeeded; fail fast. Entitlement id is already correct
(`lib/config/subscription_config.dart:4` → `'Unbound Pro'`).

---

## P1 Issues — high-impact improvements

### P1-1 · The campaign's world framing is a lie, and 125 levels share one palette

This is the largest *perceived*-quality gap in the game, and most of it is data
rather than logic.

**a. Accent is per-sector, not per-world.** Worlds 1–5 all use
`Color(0xFF00E5FF)` (`lib/game/world_registry.dart:55, 64, 73, 82, 91`);
worlds 6–9 all use `Color(0xFFFFB020)`. Because `WorldTheme.fromAccent` derives
*every* colour in the theme from the accent
(`lib/theme/world_theme.dart:41-56`), "world themes" are **one identical cyan
palette for campaign levels 1–125**. The first palette change a player ever
sees is at level 126.

**b. The world names promise mechanics the budget never delivers.** Sector 1
(levels 1–125) returns `MechanicBudget(coreCount: 0)` for Medium
(`lib/game/levels/generation/progression_profile.dart:98`). So:

| World | Levels | Name promises | Actually contains |
|---|---|---|---|
| 1 | 1–25 | Gateway | plain boards |
| 2 | 26–50 | **The Lock** | **no locked nodes** (`lockCount: 0`) |
| 3 | 51–75 | **Relay Storm** | **no relays** (`relayCount: 0`) |
| 4 | 76–100 | Labyrinth | plain boards |
| 5 | 101–125 | **`'World 5'`** | plain boards |

**c. Worlds 5–9 are named `'World 5'`…`'World 9'`** — placeholder strings
shipping as content (`world_registry.dart:87`, `:96`, `:105`, `:114`, `:123`).

**Recommended fix, in effort order.** Give each world its own accent (a
one-line-per-world data change, ~9 lines, zero logic risk, and the highest
perceived-variety return in this document). Rename worlds 5–9. Then either move
the promised mechanics earlier (see P1-2) or rename worlds 2 and 3 so the
framing matches the content — the current state, where the name sets an
expectation the level cannot meet, is worse than a neutral name.

**Verify.** `test/theme/world_theme_test.dart` already exists; extend it to
assert distinct accents across worlds 1–5 and no placeholder `'World N'` names.

---

### P1-2 · Medium waits until level 126 for its first mechanic

Given the decision that Easy stays pure, **Medium is the only place a mechanic
can be taught in the early game** — and today it teaches nothing for 125
levels. `progression_profile.dart:97-109`: sector 1 → nothing; the first lock
is level 126; the first relay is level 251.

Cores gate three separate systems, so their absence compounds:
- the cascade finale (`lib/game/chain_pop_game.dart:204`, `:745`) — the game's
  biggest payoff moment,
- the Integrity HUD (`lib/screens/game_screen.dart:878`),
- the `CASCADE` directive, which silently degrades to `SWIFT` when
  `coreCount == 0` (`lib/game/levels/level_directive.dart:56-60`).

Combined with the sector-1 directive pool being `[cascade, swift]`
(`level_directive.dart:35`), a Medium player sees **the same directive, the same
palette, and no mechanics** for their first 125 levels.

**Recommended fix.** Introduce cores on Medium in sector 1 — around level
12–15, after the ordering concept has landed — and pull the first lock to
roughly level 40 and the first relay to roughly level 60, aligning with the
"The Lock"/"Relay Storm" world names that already exist. This is a change to
the `budgetFor` table only. Note the coupling: `enrichLevel` needs enough
board to place a core in the `[0.35, 0.65]` removal-wave band
(`lib/game/levels/generation/level_enrichment.dart:38-39`), so verify against
Medium's `nodeCount` floor of 14 before committing to a level number.

**Watch out for:** `generateFromConfiguration` checks a lock/relay floor but
**not** a core floor (`lib/game/levels/generation/level_generator.dart:536`).
Raising core budgets without adding a core-floor check means core-short boards
ship silently. Add the check with the change.

---

### P1-3 · The idle auto-hint silently spends the player's free hints

**Evidence.** `lib/screens/game/game_timer_controller.dart:62`, inside the
idle ghost-hint timer:

```dart
final showed = _host.engine.showHint();
if (!showed) return;
if (_host.gateHintsWithAds) _host.hintAdPolicy.recordFreeHint();
```

On Easy campaign, `gateHintsWithAds` is true and `freeBudget` is 2
(`lib/screens/game_screen.dart:478-480`). The ghost hint fires after 4 seconds
of inactivity (`GameScreenConstants.ghostHintDelaySeconds`). So **two idle
pauses consume both of the player's free hints**, with no UI signal that
anything was spent — after which the hint *button* demands a rewarded ad.

**Partially mitigated:** the timer self-suppresses once the budget is gone
(`:57-59` checks `needsRewardedForNextHint()`), so the auto-hint never itself
triggers an ad. The harm is narrower than it first appears but still real: the
player's free allowance is consumed by a hint they did not ask for.

**Action.** Don't charge for unsolicited hints — drop the `recordFreeHint()`
call, or give the ghost hint its own separate small budget. One line.

---

### P1-4 · No stuck-state detection

`hasAvailableHint()` exists (`lib/game/chain_pop_game.dart:826-827`) and is
called from exactly one place: the hint button path
(`game_ad_coordination.dart:205`). Nothing monitors for a board with no legal
moves.

A player who has undone into a dead end, or hit an ordering mistake they can't
see, waits for the countdown to expire — **up to 240 seconds on Easy**
(`lib/screens/game/game_time_limit.dart:67-78` clamps to `[120, 240]`, and
Easy's 8–14 node counts land at the 240s cap for essentially every level).
Four minutes of dead waiting.

This is simultaneously the worst UX moment in the game and the **highest-intent
rewarded-ad moment** in it — a player who knows they're stuck is the most
willing they will ever be to watch an ad for help. It is completely unhandled.

**Action.** Poll `hasAvailableHint()` after each extraction and each undo; on
false, surface a "no moves left" affordance offering undo or a rewarded hint.
This is the one place in the audit where a player-respecting UX fix and the
revenue fix are the *same* change.

---

### P1-5 · Hint quality is arbitrary

`LevelSolver.getHint` (`lib/game/levels/level_solver.dart:95-105`) returns the
first node in `activeNodes` **list order** that happens to be removable:

```dart
for (final n in activeNodes) {
  if (_canRemoveWithSet(n, positions, level)) return n;
}
```

Not the canonical next id, not the move that unlocks the most, not the move on
the critical path. On hard/daily the free hint budget is 0
(`game_screen.dart:478-480`), so **the player is asked to watch an ad for a
list-order accident.**

**Action.** Return the lowest-id removable node (which is the canonical
solution order, and therefore always progress-safe), or better, the removable
node that frees the most nodes. The canonical-order version is a two-line
change and a strict improvement. Note the docstring at `:90` already says
"first currently-removable" — it is honest about being arbitrary.

---

### P1-6 · Portals are broken end-to-end (four separate defects)

The owner has chosen to fix these through rather than disable portals. All four
must be addressed together; fixing any subset leaves the system incoherent.

**a. The cell-key decode is wrong, in two places.** `gridCellKey` packs
`(x & 0xffff) | ((y & 0xffff) << 16)` (`lib/game/levels/grid_cell_key.dart:6-7`).
Both decode sites use base-1000 arithmetic:

- `lib/game/levels/generation/retrograde_constructor.dart:191`:
  `PortalPair(c1 % 1000, c1 ~/ 1000, c2 % 1000, c2 ~/ 1000)`
- `lib/game/levels/generation/sightline_table.dart:83-84`:
  `cx = outKey % 1000; cy = outKey ~/ 1000;`

Cell (3,4) packs to 262147, which decodes to (147, 262) — far out of bounds. In
`sightline_table.dart` the ray then terminates as if it left the board, so
**candidate enumeration believes rays are clear when they are not.**

**b. Every shipped level silently loses its portals.** `enrichLevel` rebuilds
the `LevelData` without `portalPairs`
(`lib/game/levels/generation/level_enrichment.dart:23-29`), and
`LevelData.portalPairs` defaults to `const []`. The constructor *does* place
portals and *does* pass them through
(`retrograde_constructor.dart:174-198`, `level_generator.dart:1247`, `:1285`),
and then enrichment drops them. **No shipped campaign level has portals**,
despite sectors ≥ 6 budgeting them
(`progression_profile.dart:108`, `:123`).

**c. Nothing renders a portal.** `PortalPair` is consumed by the solver
(`level_solver.dart:176-188`, `:230-242`), the ray preview
(`ray_preview_component.dart:86-92`) and the axis guide
(`arrow_axis_guide_component.dart:83-91`) — but `BoardMaskComponent` ignores
`portalPairs` entirely. A portal would be **invisible** until the player
long-presses a node whose ray happens to cross it. Shipping an unrenderable
mechanic is not shippable.

**d. The relay softlock proof does not cover portals.** `_rayCellKeys` follows
`level.portalPairs` (`level_enrichment.dart:408-444`), but the probe
`LevelData` that `_relayIsSoftlockSafe` is evaluated against omits
`portalPairs` (`:263-269`, `:290-296`). So the proof is computed on a
portal-free board and applied to one that may have portals. The same gap
exists for phase gates, which are applied *after* relays (`:309-320`) while
`LevelSolver._canRemoveWithSet` does honour `phaseGroup` (`level_solver.dart:207`).

**Why nothing has broken yet.** `_validatesRemovalOrderIdSequence` re-checks
the removal order on a portal-free probe
(`retrograde_constructor.dart:965-988`), so solvability survives — at the cost
of extra construction failures on sector-6+ Hard boards.

**Scope.** This is its own workstream, in this order: (1) fix both decodes;
(2) preserve `portalPairs` through `enrichLevel`; (3) render portal cells in
`BoardMaskComponent`; (4) extend `_relayIsSoftlockSafe`'s probe to carry
portals **and** phase gates, and extend
`test/game/levels/relaysafe_soundness_test.dart` — which today mirrors a
portal-free single-relay `isRelaySafe` — to fuzz with both enabled.
`test/game/levels/relay_softlock_property_test.dart:47-50` currently passes
`phaseGateCount: 0, portalPairCount: 0` explicitly; that must change rather
than be worked around. (5) A tutorial step, since portals are otherwise
untaught. **Do not weaken the relay invariant to make portals fit** — it is the
most valuable proof in the codebase (see Strengths).

---

### P1-7 · Haptics cover two events in the entire app

`grep -rn "Haptics\." lib/` returns exactly two hits, both in
`lib/game/components/node_component.dart`:
- `:632` — successful pop → `HapticsType.medium`
- `:642` — jam → `HapticsType.heavy`

Nothing on: win, star award, cascade finale, combo threshold, hint, undo,
restart, game over, time up, or any UI button. No `canVibrate()` capability
check, and the futures are not awaited.

For a game whose entire fantasy is tactile — extract, cascade, unravel — the
cascade finale having no haptic signature is the clearest missed feel
opportunity in the audit. Cheap to fix, no regression risk.

---

### P1-8 · Accessibility settings are each narrower than their label

All five settings in `lib/models/game_settings.dart:3-22` are persisted, have a
toggle, and are genuinely **read** at the point of use — verified individually.
The problem is scope, not wiring.

| Setting | Read at | Actual coverage |
|---|---|---|
| `soundEnabled` | `chain_pop_game.dart:211` + ambient + menus | **Complete.** |
| `hapticsEnabled` | `node_component.dart:631`, `:641` | Complete — but governs only 2 events (P1-7). |
| `colorblindFriendly` | `chain_pop_game.dart:238` (`effectiveNodeColor`) | Remaps only the 6-slot node palette. **Not** the core gold ring (`node_component.dart:374`), blocker-flash red (`:347`), relay green (`:439`), or ray amber (`ray_preview_component.dart:35-36`) — i.e. not the colours that carry *mechanical* meaning. |
| `showAimRay` | `node_component.dart:655` | Touch-down preview only; long-press ray intentionally ignores it. |
| `ambientMotion` | `ambient_background_component.dart:145-146` | Gates only mote **translation**. Twinkle (`:193`), extraction ripples (`:198-209`), streak edge glow (`:211-215`), scanlines (`:217-221`) and the red breathing vignette (`:224-232`) all keep animating with it off. |

**There is no reduced-motion setting at all.**
`grep -rn "reducedMotion\|reduceMotion\|disableAnimations" lib/` → 0 hits; no
`MediaQuery.disableAnimations` or `accessibleNavigation` read anywhere. So the
88-particle 2.9s confetti burst, the jam shake, ghost trails, the cascade
ripple, node nudge/pulse effects, the relay sweep and the coach-mark bounce are
all unconditional.

**Action (highest value first).** Extend `colorblindFriendly` to the
meaning-carrying colours — this is an accessibility *correctness* issue, since
core/relay/blocker identity is currently colour-only for those players. Then
make `ambientMotion` govern all ambient animation as its label implies, and add
a real reduced-motion setting that also respects the platform flag.

---

### P1-9 · Network integrity is decoration wearing a mechanic's clothes

`networkIntegrity` (`lib/game/chain_pop_game.dart:191`) starts at 100, gains 5
per core, loses 8 per jam (`:583`, `:711`), and is read by exactly three
places, all cosmetic:
- `ambient_background_component.dart:166` (scanline shimmer below 60)
- `ambient_background_component.dart:223` (red vignette below 30)
- `game_header_hud.dart:87-104` (the text readout)

**No win, lose, star, or gating logic reads it.** The `INTEGRITY` directive
doesn't either — it grades on `jamCount <= 1`
(`lib/game/levels/level_directive.dart:89-90`). It is also snapped back to 100
on win (`chain_pop_game.dart:744`) and on restart (`:852`), so it does not even
persist within a session.

The production directive explicitly says not to implement the old strategy
doc's timer/hint penalties just because the doc says so, and to instead decide
whether the concept earns its place.

**Recommendation: soften, don't mechanize.** It already functions well as a
readable jam-pressure meter that drives atmosphere — the ambient response to
low integrity is genuinely good feedback. Relabel it so it stops implying a
mechanical consequence it doesn't have, and keep the atmospheric coupling.
Adding real penalties would make failure *less* fair, which is the opposite of
what the difficulty findings call for. **This supersedes**
`CHAIN_POP_PRODUCTION_PLAN.md` Phase 1's instruction to "wire up the network
integrity penalties" — see [Doc drift](#appendix-doc-drift).

---

### P1-10 · 40% of milestone levels silently lose their authored identity

**Found by chasing the one failing test in the repo** (see Baseline health), then
measured directly. This was not in any prior doc.

**Evidence.** `milestoneSeedFor` (`lib/game/levels/seeds/seed_registry.dart:33-45`)
assigns one of four authored seeds to every 25th level: `mod 25` → diamond,
`mod 50` → overload, `mod 75` → ring, `mod 0` → sniper. I instrumented all 40
milestone slots from L25 to L1000 on Hard and observed the emitted
`seedId`:

```
milestone slots: shipped=24  lost=16
L150 L250 L350 L450 L550 L650 L750 L850 L950   (overload — every slot except L50)
L225 L425 L525 L625 L725 L825 L925             (diamond — every slot from 225 up)
```

All 16 report `success=true` with `seedId=NULL` — the level ships, but as an
**ordinary procedural board**, not the authored milestone. `ring` and `sniper`
never fail.

**Mechanism.** In the seeded path
(`lib/game/levels/generation/level_generator.dart:407-436`), each attempt is
rejected when the enriched board misses the mechanic floor:

```dart
if (lockCount < budget.lockCount || relayCount < budget.relayCount) {
  _discardPendingEmission();
  continue;
}
```

…and after `maxAttempts`:

```dart
// Seed path failed (e.g. silhouette starvation on a tiny grid):
// fall through to the regular pipeline so the level still ships.
_discardPendingEmission();
```

The mechanic budget grows by sector (`progression_profile.dart:119-125`: locks
at sector 2, relays at 3, two locks at 4…), while `diamond` and `overload` pin
a silhouette with **no grid override**, so they stay on the ordinary 6×6–9×9
board. The diamond silhouette in particular wastes its corners, leaving too few
cells to place 3 cores + 2 locks + a relay. `sniper` survives precisely because
it pins a 10×10 grid (`milestone_seeds.dart:51-52`), and `ring` has a
large enough mask.

So the failure is not random — it is **systematic and worsens with campaign
depth**, exactly where a player most needs the campaign to feel authored.

**Why the fallthrough hid it.** The fallthrough is a deliberate safety net and
the right default — a milestone that can't generate should still ship a
playable level. But it is completely silent: no counter, no assert, no
telemetry (and per P0-1, no analytics at all). Nobody measured how often it
fires.

**Related, already known:** the overload seed's docstring
(`milestone_seeds.dart:23-37`) documents that it "does not currently feel like
an 'overload'" because it pins only the silhouette, and that the planned fix
(`targetNodeCount: 36`) is withheld because it exposes the unbounded seeded
Director path (P2-4) — measured at 66s and 181s on slots 750 and 950. That note
describes the *quality* of the milestone; this finding is that on 9 of its 10
slots the seed isn't applied at all.

**Action.** Two independent fixes, both small:
1. **Make the fallthrough observable** — count it, and assert in debug that a
   seeded level actually shipped its seed. This is the durable fix; the silence
   is the real defect.
2. **Give diamond and overload the headroom they need** — a grid override, as
   `sniper` already has, or relax the mechanic floor for seeded milestones.

Fix (1) first: it converts this class of bug from invisible to loud, and P2-4's
latency bound is a prerequisite for the fuller overload fix.

**Verify.** The probe above, promoted to a real test asserting every milestone
slot ships its own `seedId`. Note this will fail today for 16 slots — that is
the point, and it should be a `TODO`-referenced expected-fail rather than
skipped.

---

## P2 Issues — correctness and hygiene

### Level quality / generation

**P2-1 · Difficulty bands are measured on a board the player never sees.**
`LevelMetrics.compute(level)` runs at
`lib/game/levels/generation/level_generator.dart:734` on the **raw retrograde
output**. Cores, locks, relays and phase gates are added afterwards by
`enrichLevel` at `:523`. Locks and gates change `firstLegalMoveCount`,
`waveZeroWidth`, FSR, CUD and wave depth (`level_solver.dart:204-209`), and
**no band is re-checked post-enrichment** — only ID-order solvability
(`LevelValidator`) and the removal-wave count.

This is the most important finding in the generation subsystem: *every
difficulty guarantee in the system is a guarantee about a different board than
the one that ships.* It also means the Hard/Expert opening-band work in
`c747e4f` — which was careful, honest work — is guarding a pre-enrichment
number.

**Recommended investigation before any change:** compute both pre- and
post-enrichment metrics across a corpus and measure the drift. If it is small,
document it and move on. If it is large, the band check belongs after
enrichment. Do not move the check without measuring first — the whole band
system is calibrated against pre-enrichment numbers, so moving it will
invalidate the calibration.

**P2-2 · Node count is never band-gated.** `DifficultyProfile.passes` omits it
by design (`difficulty_profile.dart:56-61`, confirmed at `:219-249` — the
method checks BF, opening, CUD, FSR, wave depth and the FSR cap, but not
`nodeCount`). Compounding it, the Director's renegotiation floors use
`config.difficulty.minNodes` (Easy 4 / Medium 10) rather than
`profile.nodeCount.min` (8 / 14) — `director.dart:240`, `:291-295` — and
`_pickTargetNodeCount` returns `hi.clamp(1, mask.length)` when `hi <= lo`
(`:546`, `:553`), silently below tier minimum on a small mask.

**P2-3 · Several config knobs are validated but never read.** The retry
node-count scaling at `level_generator.dart:482-507` builds a `scaledConfig`
whose only difference is `targetNodeCount` — which
`Director._pickTargetNodeCount` never reads (`director.dart:535-555`). Same for
`minimumTargetNodeCount`, `irregularMaskProbability`,
`irregularLayoutExtraTries` (`level_configuration.dart:189-191`, validated at
`:228-234`), and the `kHardEffectiveFillMin/Max` constants (`:62-68`). Either
wire them or delete them; right now they read as active tuning and are inert.

**P2-4 · Seeded and daily generation are unbounded.** The 200ms budget
(`level_manager.dart:19`) explicitly does not cover the seeded path — see the
honest note at `level_generator.dart:456-462` — and
`generateDailyChallenge` takes no `timeBudget` parameter at all (`:595-604`).
Measured milestone worst case is ~2.2s
(`test/game/levels/generation/milestone_latency_test.dart:57`), and a pinned
`targetNodeCount: 36` measured **66s and 181s**
(`lib/game/levels/seeds/milestone_seeds.dart:23-37`). The real fix is a
deadline inside the Director, as that note says.

**P2-5 · `_guardHardExpertOpening` throws `StateError` in production.**
`level_generator.dart:1677-1689`, called at `:802`, `:837`, `:870`, outside the
constructor's try. **Defensive only in practice** — I verified every call site
is pre-filtered (in-band candidates passed `passes()` which includes the
opening band at `difficulty_profile.dart:239`; both out-of-band paths are
guarded by `_openingWithinHardExpertBand` immediately before). So this is
lower severity than it first reads, but it is still an uncaught production
throw on the level-load path and should be a debug assert plus a graceful
release-mode rejection.

**P2-6 · Release builds skip layout validation entirely.**
`_assertGeneratedLayout` (`level_generator.dart:1691-1694`) and
`LevelData.layoutValidationMessage` (`level.dart:135-155`) are assert-only, and
`level_manager.dart:36`, `:56` wrap them in `assert`. In release, bounds
checks, duplicate-position checks and playCell checks do not run.

**P2-7 · The emergency fallback is a 1-node 4×4 board, and no test reaches it.**
`level_manager.dart:70-86`. In debug, `assert(false, 'Level generation failed')`
at `:42`/`:60` **crashes the app** on any generation error; in release it
silently ships a one-node board. No test drives `generateFromConfiguration` to
its `'Director exhausted $maxAttempts attempts'` return (`:576-588`) or to the
fallback itself.

**P2-8 · Temporal-arc enforcement is commented out.**
`difficulty_profile.dart:242-247` — disabled "until wave profile pacing is
calibrated by human playtesting". `passesTemporalArc` survives only as a
ranking input (`level_generator.dart:990-993`). Either calibrate it or delete
the arc specs.

**P2-9 · Dead and unwired generation code.**
- **MAP-Elites**: `map_elites.dart` and `level_bank.dart` have no `lib/`
  caller — only the barrel (`generation.dart:24`, `:26`) and their tests. The
  production directive says leave it as offline tooling unless proven. **Leave
  it**, but consider moving it out of `lib/` so it stops shipping.
- **DiversityLedger persistence**: `serialize`/`restore` exist
  (`diversity_ledger.dart:237-250`) and nothing calls them. The ledger lives on
  a `static final` generator (`level_manager.dart:12`), so **novelty resets
  every app launch** — a returning player can be served a board they just
  played. Cheap to wire now that both halves exist; this is the one dead
  system with a clear player-facing payoff.
- **`analyticsSink` defaults to noop** (`level_generator.dart:139`) and no
  production caller injects one, so every generation telemetry event built at
  `:920-941` goes nowhere. Ties into P0-1.
- **`computeSearchEffort` runs on every metrics computation**
  (`metrics.dart:124`) — an unbounded backtracking DFS — and nothing reads the
  result ("Measured only; not yet used for gating", `:55-57`). This is pure
  latency cost on the level-load path. Gate it behind a flag.
- **`ChainPopGame.isExtractable`** (`chain_pop_game.dart:541`) has no
  production caller, and its docstring at `:34`/`:61-63` claims
  `NodeComponent` queries it per frame for extractable/blocked visuals — while
  `node_component.dart:283` says the opposite ("legal moves are not
  telegraphed"). The code is right and the docstring is stale; confirm
  not-telegraphing is still the intent, then fix the comment.
- `rollIrregularLayout` (`layout_mask.dart:100`) — no `lib/` caller.
- `useDenseValidationSeeds = false` (`seeds/seed_registry.dart:10`) makes all
  10 seeds in `dense_validation_seeds.dart` unreachable.

### Runtime lifecycle

- **`setState` without `mounted` in the jam path.** `_handleFoul`
  (`lib/screens/game_screen.dart:645-654`) calls `setState` unguarded, while
  its sibling `_handleNodeRemoved` (`:656-658`) does check. Reached from the
  engine `onJam` callback.
- **A dangling ray preview permanently freezes ambient motion.** `_setupBoard`
  rebuilds every `NodeComponent` but never touches `_rayPreview`
  (`chain_pop_game.dart:128`). If a relayout fires while a finger is down, the
  component that would have delivered `onTapUp` is gone, `hideRayPreview()`
  never runs, `rayPreviewActive` stays true, and
  `ambient_background_component.dart:146` freezes mote drift for the rest of
  the level.
- **A ≥1px inset delta rebuilds the whole board mid-play.**
  `configurePlayfieldInsets` (`chain_pop_game.dart:228-234`) resets zoom/pan
  and calls `_setupBoard`, recreating every node, the mask picture, the
  restored layer and the coach mark. Every one-shot timer on a recreated node
  (`_nudgeTimer`, `_freedTimer`, `_blockerFlashTimer`, `_highlightTimer`,
  `_arrowSpin`) is silently lost. The header height changes when the Integrity
  readout appears/disappears (`game_header_hud.dart:87`), which is a live
  source of such deltas on hard/daily.
- **`_openSettings` pauses the engine without setting `_isPaused`**
  (`game_screen.dart:743-777`), so the ambient bed keeps playing and the pause
  overlay never shows.
- **Classic-win overlay races the last node's fly-off.** For non-core levels
  `checkWinCondition` fires the instant `activeNodes` empties
  (`chain_pop_game.dart:753-756`), i.e. at tap time, while the final node is
  still travelling at 1500 px/s.
- **`pushReplacement` overlaps two audio controllers.**
  `game_flow_controller.dart:235`, `:260` — the outgoing `dispose()` runs
  concurrently with the incoming `startAmbientIfEnabled`, against a
  process-global pool that **never calls `AudioPlayer.dispose()`**
  (`game_audio.dart:250-262`).
- **Cascade-finale pitch is silently truncated.** The finale ramps to 1.6
  (`chain_pop_game.dart:791-794`) against a `[0.85, 1.5]` clamp in
  `play` (`game_audio.dart:106`).
- **Relay audio is a repurposed clip fired out of order.** The relay rotation
  plays `GameSfx.hint` at rate 1.25 (`chain_pop_game.dart:675`) from *inside*
  `registerExtraction`, i.e. dispatched before the pop SFX for the same tap,
  onto a different player. Relative audibility is non-deterministic.
- **Injected vs static session trackers diverge.**
  `_interstitialLikelyDue` reads the static `SessionCampaignStreak.wins`
  (`game_flow_controller.dart:170`) while the win records through the
  injectable `_host.streak` (`:65`). With an injected tracker the static never
  advances, so `_shouldQuickWin` always takes the quick-win branch.
- **`worldForLevel(0)` resolves to sector 8.** Daily passes `level: 0`
  (`daily_challenge_calendar_screen.dart:84`); Dart's Euclidean modulo makes
  `((0-1) % 1000) + 1 == 1000` → World 40 (`world_registry.dart:507-522`). Not
  on a live path today (every daily consumer branches on `isDailyChallenge`
  first) but a latent trap.
- **The dev autoplay timer is unguarded.** `Timer.periodic(55ms)` at
  `game_screen.dart:577-581`, no `hasWon`/`isGameOver`/`isPaused` check,
  relying entirely on `autoSolveStep`'s internal guard.

### Structure and hygiene

- **GameScreen decomposition (Phase E) is half-done.** The four controllers
  *are* standalone classes behind `GameScreenControllerHost` — `grep "^part "
  lib/` returns zero hits, so the old `part`-file coupling is genuinely gone.
  But `game_screen.dart` is still **1022 lines**: ~220 lines of pure `@override`
  forwarding (193–412) and a ~218-line inline `build()` (803–1021).
  Controllers still call the host to reach *sibling* controllers (`:386-401`).
  Vestigial `library;` at line 1.
- **Three overlapping storage paths coexist.** `StorageLocator`; the legacy
  static `StorageService` facade, still used by `lib/main.dart:50`,
  `level_manager.dart`, `progress_format.dart`,
  `daily_challenge_play_policy.dart` and
  `campaign_between_levels_ads.dart:33`; and `ChainPopProgressStore`. The guard
  test only forbids the facade in three named screens
  (`test/storage_isolation_test.dart:24-33`). `_migrateToV2` is an empty
  placeholder (`hive_chain_pop_persistence.dart:64-80`).
- **A test-only API sits on the production interface.**
  `seedLifetimeEngagementGateForTests()` is declared in `ChainPopPersistence`
  (`chain_pop_persistence.dart:81`) and implemented un-annotated
  (`hive_chain_pop_persistence.dart:287-293`).
- **Startup blocks the first frame on a network round-trip.** `main.dart:29-53`
  awaits, before `runApp`: Firebase init, Hive open, a RevenueCat
  `getCustomerInfo()` call, the entire UMP consent flow (up to 10s,
  `ump_consent.dart:46-53`), and `MobileAds.initialize()`. In the EEA the
  consent dialog appears over the native splash before any Flutter UI. Then
  `SplashScreen` runs its own ~1.5s animation. Also `FlutterError.onError` is
  installed *after* Firebase init (`:34-47`), so errors during init are not
  captured, and there is no `runZonedGuarded`.
- **`bootstrap()` fires 5 ad preloads at cold start** regardless of screen
  (`google_mobile_ad_service.dart:73-78`).
- **Banner load failures never retry** — they collapse to `SizedBox.shrink()`
  (`daily_challenge_banner_slot.dart:135-138`).
- **`NoOpSubscriptionService.isPremium` returns a new `ValueNotifier` per
  getter call** (`no_op_subscription_service.dart:6`), so a
  `ValueListenableBuilder` binds to a throwaway object. Web-only path.
- **`MOCK_ADS=true` builds cannot use hints on hard/daily.**
  `NoOpAdService.isRewardedReady` is always `false`
  (`no_op_ad_service.dart:24`) and hard/daily have `freeBudget: 0`, so hints
  are permanently unreachable behind an "Ad loading…" snackbar.

### Test gaps that matter

Ranked by production risk, not by count:

1. **A successful rewarded grant** — never executed by any test (P0-8).
2. **Premium / subscription** — zero tests exist.
3. **Post-enrichment band conformance** — nothing asserts a *shipped* level's
   metrics land in its tier's bands. `difficulty_quality_audit_test.dart`
   checks only the opening ceiling and an in-band rate.
4. **Portals** — zero tests. Neither `%1000` decode site is covered;
   `sightline_table_test.dart` exercises only the portal-free path.
5. **Relay safety under phase gates and portals** —
   `relay_softlock_property_test.dart:47-50` explicitly zeroes both.
6. **The core-count floor** — `level_generator.dart:536` checks locks and
   relays but not cores, and nothing tests that shipped levels have their
   budgeted cores.
7. **`bootstrapChainPop()` failure modes** — Firebase down, Hive corrupt.
8. **Lifecycle** — no test for the `didChangeAppLifecycleState` playtime flush.
9. **Daily generation latency** — unbounded and unbounded-by-test.
10. **The emergency fallback path** — never reached by a test.

---

## Deferred Work (P3)

Recorded deliberately, not to be actioned this cycle:

- **MAP-Elites runtime integration.** The directive is explicit: leave it as
  offline tooling unless it demonstrably improves shipped level quality.
- **The `[3,5]` opening-band redesign** (Option B in
  `docs/OPENING_BAND_DECISION.md`). The `[3,11]` recalibration shipped in
  `c747e4f` is the honest number, and the geometric-starvation root cause makes
  Option B a large, uncertain-payoff construction rewrite.
- **Cloud save / accounts.** Explicitly out of scope; local Hive is correct for
  this product.
- **GameScreen Phase E completion** beyond what the P2 lifecycle fixes
  require. The `part`-file coupling — the actual problem — is already gone.
- **Portal visual polish** beyond a legible cell (P1-6 scope is legibility, not
  beauty).
- **Landscape support.** Portrait lock (P0-7c) is the decision; landscape
  layout is not on the roadmap.

---

## Wave sequencing

Each item carries the directive's hypothesis discipline: Problem / Evidence /
Change / Expected / Verify. Waves are ordered so that **Wave 0 finishes before
Wave 1 begins** — instrumentation first, so Wave 1's effects are measurable.

### Wave 0 — must ship before public launch

| # | Item | Effort | Regression risk | Flaggable |
|---|---|---|---|---|
| P0-1 | Analytics service + the ~15 events that carry a decision | M | Low | Yes |
| P0-5 | Gate toolbar/hint/pause on `engine.hasWon` | S | Low | No |
| P0-4 | Pause the clock during rewarded ads | S | Low | No |
| P0-3 | Rewarded timeout + try/catch | S | Low | No |
| P0-6 | Harden `Hive.openBox` with recover-and-reset | S | Medium | No |
| P0-7 | Fail loud on missing release signing; gate test device id; portrait lock; move `RecordingAdService` to `test/` | S | Low | No |
| P0-8 | Configurable `RecordingAdService`; premium + grant tests; move the RevenueCat listener out of the try | M | Low | No |
| P0-9 | Release assertion on the RevenueCat key | S | Low | No |
| P0-2 | Real `google-services.json` **(owner action)** | — | — | — |
| — | Tag the corpus harnesses so `flutter test` is a usable gate; add CI | S | Low | No |
| — | Fix the analyze error at `hard_1000_playfeel_report_test.dart:40` | S | None | No |

**Decision gate.** If P0-1's event volume looks noisy in the Firebase debug
view, cut `node_jam` before cutting anything in the level or ad funnels.

### Wave 1 — immersion and session-length multipliers

| # | Item | Effort | Regression risk | Flaggable |
|---|---|---|---|---|
| P1-1 | Per-world accents; rename worlds 5–9; reconcile world names with content | S | Low | Yes |
| P1-2 | Move Medium's first core/lock/relay into sector 1; add the missing core floor check | M | **Medium** — touches generation | Yes |
| P1-3 | Stop charging for unsolicited ghost hints | S | None | No |
| P1-4 | Stuck-state detection + recovery affordance | M | Low | Yes |
| P1-5 | Canonical-order hints | S | Low | Yes |
| P1-7 | Haptics on win / cascade / combo / star | S | None | Yes |
| P1-9 | Relabel integrity; do **not** add penalties | S | None | No |
| P1-10 | Make the seeded-path fallthrough observable (counter + debug assert) | S | Low | No |
| P1-10 | Grid headroom for the diamond/overload milestone seeds | S | Low | Yes |

**Decision gate on P1-2.** This is the only Wave 1 item that touches
generation. Measure the shipped Medium corpus before and after: if the core
placement band can't be satisfied at Medium's node counts, move the onset later
rather than relaxing the `[0.35, 0.65]` band — the band is what makes the
cascade finale a payoff instead of a mop-up.

### Wave 2 — correctness, portals, accessibility

| # | Item | Effort | Regression risk |
|---|---|---|---|
| P2-1 | **Measure** pre- vs post-enrichment metric drift, then decide | M | — (investigation) |
| P1-6 | Portals fix-through, all five steps, invariant preserved | **L** | **High** |
| P1-8 | Colorblind coverage for meaning-carrying colours; real reduced-motion | M | Low |
| P2-9 | Wire DiversityLedger persistence; flag-gate `computeSearchEffort` | S | Low |
| P2-4 | Director-internal deadline for seeded + daily paths | M | Medium |
| P2-5/6/7 | Graceful release-mode generation failure instead of assert-only | S | Low |
| — | Lifecycle fixes: `mounted` guard, dangling ray preview, `_openSettings` pause state, static/injected streak divergence | S | Low |

---

## Launch Gate

| Gate | Status | Blocking item |
|---|---|---|
| Core loop stable | ✅ | — |
| First 10 levels polished | ⚠️ | Levels 4–10 are pure procedural (only 1–3 are seeded); no mechanics on Easy by design |
| Tutorial covers every mechanic | ✅ | 10 steps as of 2026-08-12: phase gate (8) and an all-types graduation board (9) close the gap that left Daily players meeting untaught mechanics |
| Difficulty progression coherent | ⚠️ | P2-1 (bands measured pre-enrichment), P2-2 (node count ungated) |
| No unfair softlocks | ⚠️ | P1-4 — no stuck-state detection; the board isn't softlocked but the player is stranded |
| Special mechanics understandable | ⚠️ | Phase gates now taught (tutorial steps 8–9, added 2026-08-12) but still have no badge — only a near-black colour crush (`node_component.dart:258-259`). P1-6 portals remain invisible. |
| Retry flow good | ✅ | — |
| Solvability proven | ✅ | Construction invariant + relay proof |
| Generation latency acceptable | ⚠️ | P2-4 — seeded/daily unbounded; measured 2.2s worst case vs a 200ms budget |
| Fallback safe | ⚠️ | P2-7 — 1-node board in release, `assert(false)` in debug |
| Hard/Expert quality acceptable | ✅ | Honestly recalibrated in `c747e4f` |
| No major repetitive patterns | ⚠️ | P1-10 — 16 of 40 milestone levels ship as ordinary procedural boards |
| All primary flows polished | ⚠️ | P0-5 win-window; P2 lifecycle edges |
| Accessibility settings work | ⚠️ | P1-8 — each is narrower than its label; no reduced motion |
| Game feel intentional | ⚠️ | P1-7 — 2 haptic events total |
| Rewarded ads reliable | ❌ | P0-3 (can hang), P0-8 (untested) |
| Interstitials controlled | ✅ | Three-gate policy is sound — protect it |
| Premium works | ❌ | P0-8 (untested, two live bugs), P0-9 (silent failure) |
| Consent works | ✅ | UMP runs before `MobileAds.initialize()` |
| Rewards cannot duplicate | ✅ | Completer guarded on both terminal callbacks |
| Ads cannot destroy progress | ❌ | P0-4 — the clock runs during the ad |
| No P0/P1 crashes | ⚠️ | P0-6 startup; P2-5 uncaught throw (defensive in practice) |
| Persistence safe | ⚠️ | P0-6 — unhardened box open |
| Lifecycle safe | ⚠️ | P2 lifecycle list |
| Startup acceptable | ⚠️ | Network round-trip + up to 10s UMP before first frame |
| Low-end devices tested | ❌ | Not done this audit — needs a physical-device pass |
| Core funnel observable | ❌ | **P0-1** |
| Crashes observable | ❌ | **P0-2** |
| Production keys / signing | ❌ | P0-7a, P0-2, P0-9 |
| Privacy / data safety | ⚠️ | `docs/privacy.md` exists; needs a hosted URL and a Play Data Safety form |
| Store assets / listing | ❌ | Not started |

### Final decision

**NOT READY.** After Wave 0 the honest status becomes **READY FOR SOFT
LAUNCH** — at that point the game is observable, cannot take a win or a fair
timer from a player, and the money path is tested. Full production readiness
additionally needs Wave 1 (so the first 125 levels don't read as flat), a
physical low-end-device pass, and the store listing.

The reason this is not "READY AFTER P0 FIXES" is P0-1: you cannot validate a
soft launch you cannot measure, so the analytics work is load-bearing for
every decision that follows it.

---

## Appendix: doc drift

Resolved in favour of the code, per the directive's priority order. These docs
should be corrected or marked historical rather than followed:

| Doc | Claim | Reality |
|---|---|---|
| `docs/SESSION_CONTEXT_AND_HANDOFF.md` | Dated 2026-06-14; §5 presents the opening band as an **open decision** | Resolved — Option A (`[3,11]`) shipped in `c747e4f`. Mark the file historical. |
| `docs/SESSION_CONTEXT_AND_HANDOFF.md` §2 | "`flutter analyze` = 0 issues; `flutter test` = 541 passed" | 1 analyze error; the suite no longer completes in a usable time. |
| `docs/SESSION_CONTEXT_AND_HANDOFF.md` §6 | Latent `clamp(min>max)` crash in `_calculateNodeCount` | **Not reproducible** — I checked every `clamp` site in the generation subsystem and all are bound-guarded (`director.dart:546`/`:553` short-circuit on `hi <= lo`; `level_configuration.dart:380-390` is max-guarded). Either it was fixed or the analysis was wrong. |
| `docs/SESSION_CONTEXT_AND_HANDOFF.md` §6 | Phase E "not started" | The four controllers *are* standalone; no `part` files remain. ~440 lines of forwarding + inline build remain (P2). |
| `README.md` | Difficulty tables: Hard 6×6–16×16, 5–60 nodes, 40% density | Stale. Real grids are 6×6–9×9 (`level_configuration.dart:323-349`); real Hard band is 25–42 nodes (`difficulty_profile.dart:131-187`). |
| `CHAIN_POP_PRODUCTION_PLAN.md` Phase 1 | "Wire up the network integrity penalties (timer and hint reductions)" | **Countermanded** by the newer directive §15 and by this audit's P1-9. Do not implement. |
| `CHAIN_POP_PRODUCTION_PLAN.md` Phase 4 | "Enable `useDenseValidationSeeds` if required" | It is `false` and its 10 seeds are unreachable; no evidence it should be on. |
| `docs/play_store_launch_pending.md:15` | "Premium skips Mobile Ads init at cold start" | True **only** when the entitlement resolves before `main.dart:77` reads it (P0-8). |
| `docs/play_store_launch_pending.md:71` | Portrait lock "optional" | Accurate that it's unset; this audit rates it a blocker (P0-7c) since the board layout was never designed for landscape. |
| `lib/game/chain_pop_game.dart:34`, `:61-63` | `NodeComponent` queries `isExtractable` per frame for extractable/blocked visuals | False. No production caller; `node_component.dart:283` states legal moves are deliberately not telegraphed. |
| `AndroidManifest.xml:32-33` | Comment: "sample app ID … Replace before release" | Stale — the placeholder resolves to the **production** AdMob app id (`build.gradle.kts:18-21`). |
| `lib/game/levels/generation/diversity_ledger.dart:150-152` | "Persistence is not wired in Phase 3" | Still accurate, and still unwired (P2-9). |

### iOS items (deferred by decision, recorded for completeness)

- `GADApplicationIdentifier` is **Google's test app id**
  `ca-app-pub-3940256099942544~1458002511` (`ios/Runner/Info.plist:53-54`).
- Bundle id is still the Flutter template default `com.example.chainPop`
  (`ios/Runner.xcodeproj/project.pbxproj:375`, `:554`).
- No `NSUserTrackingUsageDescription` and no ATT request anywhere.
- `SKAdNetworkItems` has 10 entries — the minimal Google set, not the full
  AdMob mediation list.
- No `GoogleService-Info.plist`, so Firebase init throws and is swallowed.
- `ios/Podfile` platform line is commented out.
- Orientation allows portrait + both landscapes on iPhone, all four on iPad.
- Rewarded/interstitial/banner defaults in `admob_config.dart:29-34` are Google
  test units on iOS.

---

## Last Audit

**2026-08-12** — initial full audit. Branch `new_improvements`, working tree at
`c747e4f` + uncommitted changes.

**Method.** Three parallel subsystem sweeps (generation/solver, runtime/feel/UX,
services/monetization/store), followed by direct verification of every P0 cite
and the load-bearing P1/P2 cites against the working tree, plus a measured
test-baseline pass.

**Corrections made during verification** — recorded so the cites can be
trusted:
- Release signing is `build.gradle.kts:83-87`, not `:98-102`.
- The shipped test device id is `admob_config.dart:82-84`.
- The `passes()` opening-band check is `difficulty_profile.dart:239`.
- The phase-gate colour crush is `node_component.dart:258-259`.
- **One inherited finding rejected as non-reproducible**: the
  `clamp(min > max)` crash in `_calculateNodeCount` claimed by
  `SESSION_CONTEXT_AND_HANDOFF.md` §6. Every `clamp` site in the generation
  subsystem is bound-guarded.
- **`_guardHardExpertOpening` downgraded** from an inherited P0 to P2-5: all
  three call sites are pre-filtered, so the throw is defensive in practice.

**New finding produced by this audit** (not present in any prior doc):
**P1-10** — 16 of 40 milestone levels silently ship as ordinary procedural
boards. Found by refusing to dismiss the single failing test as stale, then
instrumenting all 40 milestone slots.

**Not covered by this audit, and owed:**
- A physical-device pass: FPS on low-end Android, startup time, thermal
  behaviour, ad transition smoothness, safe areas and notch handling.
- Interactive playtesting. Every gameplay-feel judgement here is read from
  code, not from playing. The `docs/playtests/` directory exists and should be
  the home for that evidence.
- A full `flutter test` count. The suite does not complete in 40+ minutes; the
  measured non-corpus subset (119 tests / 5.8 s, all passing) is the usable
  signal until the corpus harnesses are tagged.
