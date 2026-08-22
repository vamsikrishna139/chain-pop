# Unbound — Play Store Launch Plan

> **Status date:** 2026-08-16 · branch `new_improvements` · Flutter 3.47.0 / Dart 3.13
> **Package:** `com.adbkv.chainpop` · display name **Unbound** · version `1.0.0+1`
>
> This is the end-to-end launch plan. Part 1 is measured state (verified against
> the working tree today, not copied from other docs). Parts 2–6 are the plan.
> Where this file and `docs/PRODUCTION_AUDIT.md` disagree, this file is newer;
> where this file and the code disagree, the code wins.

---

## Part 1 — Where the app actually is (verified 2026-08-16)

### What is genuinely done

| Area | Evidence |
|---|---|
| `flutter analyze` clean | 2 infos, 0 errors/warnings (a deprecated banner-size call, one `print` in a test) |
| Android identity | `applicationId`/namespace `com.adbkv.chainpop`, label **Unbound** (`android/app/build.gradle.kts:52`, `AndroidManifest.xml:4`) |
| SDK levels | compileSdk **36**, targetSdk **36**, minSdk **24** (Flutter 3.47 defaults) — meets and exceeds the current Play target-API bar |
| Upload keystore | exists at `game/jks/upload-keystore.jks` + `key.properties`, resolved by `signingPropsFile()` |
| R8 / shrinking | `isMinifyEnabled` + `isShrinkResources` + `proguard-rules.pro` with Play-Core and Firebase keeps |
| AdMob production identity | app id `ca-app-pub-6510329237083952~7569862231`; production rewarded/interstitial/banner unit ids in `lib/services/ads/admob_config.dart` |
| GDPR/UMP consent | `requestAdsConsentIfApplicable()` runs **before** `MobileAds.initialize()` (`lib/main.dart:85-89`), 10 s timeout, re-openable from in-app Privacy & Ads |
| Premium suppression | RevenueCat + `PremiumAdServiceDecorator`; entitlement id `Unbound Pro` |
| Play Games Services | real `games-ids.xml` (app id `127337983333`), 48 achievements, `setSteps`-only sink, auth + bootstrap + isolation tests |
| Privacy policy text | `docs/privacy.md`, hosted at `sites.google.com/view/unbound-policy/home`, wired into `ChainPopLegal` and both settings sheets |
| Interstitial gating | three independent gates (session streak, lifetime engagement, frustration suppression) — genuinely more player-respecting than typical |
| Solvability | structural invariant (retrograde construction + relay softlock proof), not a search result |

### What is still open — verified unfixed today

Every P0 in `docs/PRODUCTION_AUDIT.md` (2026-08-12) is **still open**. Re-checked
individually today:

| Id | Issue | Verified today |
|---|---|---|
| P0-1 | No analytics | `grep logEvent lib/` → exactly one hit, `logAppOpen()` in `firebase_bootstrap.dart:28` |
| P0-2 | Crash reporting dark | `android/app/google-services.json` still `project_id: chain-pop-placeholder-replace-me`; no `lib/firebase_options.dart` |
| P0-3 | Rewarded ad can hang forever | `google_mobile_ad_service.dart` — `await done.future` with no `.timeout(...)`, `ad.show` not in try/catch |
| P0-4 | Countdown runs during rewarded ads | `game_ad_coordination.dart` only *reads* `isPaused`; never sets it around a show |
| P0-5 | A won level can be destroyed mid-finale | `game_screen.dart:962` gates the toolbar on `_hasWon` only, never `_engine.hasWon` |
| P0-6 | Corrupt Hive box kills startup | `hive_chain_pop_persistence.dart:58` — bare `Hive.openBox`, no try/catch |
| P0-7a | Release build silently falls back to **debug signing** | `build.gradle.kts:83-87` `?: signingConfigs.getByName("debug")` |
| P0-7b | Test device id ships in release | `kAdmobTestDeviceIds` applied unconditionally at `main.dart:86-88` — **this is why you see dummy ads** |
| P0-7c | No portrait lock | no `android:screenOrientation`, `grep SystemChrome lib/` → 0 hits |
| P0-7d | Test double ships in release bundle | `lib/services/ads/recording_ad_service.dart` still under `lib/` |
| P0-8 | Money path untested | `grep -rl "Premium\|RevenueCat\|Subscription" test/ integration_test/` → **zero files** |
| P0-9 | Missing RevenueCat key fails silently | key only from `--dart-define`; no bootstrap assertion; the `addCustomerInfoUpdateListener` is still inside the `getCustomerInfo` try block |
| — | No CI | `.github/` does not exist |
| — | `flutter test` unusable as a gate | corpus report harnesses still untagged in the default test path |

### New finding: the working tree is red, and it is a *visual* regression

The uncommitted UI redesign (12 files, +1781/−2011, sourced from the
`unbound-ui-changes/` AI Studio prototype) breaks **37 widget tests** in the fast
suite (218 pass / 37 fail, 9 s). Two of the three failure classes are real, not
stale expectations:

1. **`RenderFlex overflowed by 10.0 pixels on the right` in the gameplay HUD —
   on every tutorial step (0–9), on both the tall and the small phone profile**
   (`test/screens/tutorial_ui_diagnostic_test.dart`). This is a visible yellow-
   and-black overflow stripe in debug and clipped content in release. It would
   ship in the first screenshot a reviewer sees.
2. **The header reserve grew 22 px** — `kRefTopReserved` measured 194 vs the
   calibrated 172 on 390×844, and 206 vs 184 on 430×932
   (`test/screens/playfield_insets_reference_test.dart`). That silently
   invalidates the board-presence calibration recorded in `docs/AGENT_STATE.md`
   (the P0–P4 board-presence work was tuned against 172/110), and it is a live
   source of the mid-play board rebuild described in the audit's lifecycle
   section.
3. Stale expectations: `main_menu_screen_test` looks for a `Tutorial` label the
   redesign removed, plus `quick_win_transition_test` and the achievements
   screen tests.

**Decide this before anything else**: finish and re-green the redesign, or stash
it and launch on the committed UI. Do not launch with (1) unresolved.

### Runtime facts worth knowing before the console work

- **Merged release permissions** (from the last release build):
  `INTERNET`, `ACCESS_NETWORK_STATE`, `VIBRATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE`,
  `com.google.android.gms.permission.AD_ID`, `com.android.vending.BILLING`,
  `ACCESS_ADSERVICES_{AD_ID,ATTRIBUTION,TOPICS}`, `BIND_GET_INSTALL_REFERRER_SERVICE`.
  None are runtime-prompted permissions — the app asks the user for **nothing** at
  runtime, which is the easiest possible Data Safety story. `AD_ID` must still be
  declared in the console.
- **No user accounts, no cloud save.** All progress is device-local Hive.
  Play Games sign-in is the only identity, and it is Google's, not yours.
- **Assets are small** (≈1 MB). The 61 MB `app-release.apk` is the universal APK;
  the AAB will ship far smaller per-device.
- **The release AAB builds and signs correctly on this machine** (verified today):
  `flutter build appbundle --release --dart-define=REVENUECAT_GOOGLE_API_KEY=… --obfuscate --split-debug-info=build/debug-info`
  → 59.4 MB AAB, `jarsigner -verify` → *jar verified*, signed by
  `CN=Vamsi Krishna, O=Chain Pop`. R8 survives the Play Games + Firebase +
  AdMob plugin set.
  - The 59.4 MB is **not** the download size: 33 MB is the ProGuard map and
    ~60 MB (uncompressed) is native debug symbols, both stripped by Play. Real
    per-device payload is roughly `libflutter.so` + `libapp.so` + dex ≈ 30 MB
    uncompressed for arm64.
  - Two toolchain deprecation warnings to act on before they become blockers:
    AGP **8.11.1** (Flutter will require ≥ 9.0.1) and Kotlin **2.2.20**
    (will require ≥ 2.3.20).
- **Startup does a network round-trip before the first frame**: Firebase init →
  Hive → RevenueCat `getCustomerInfo()` → UMP consent (up to 10 s) →
  `MobileAds.initialize()`, then a ~1.5 s splash animation.

### Honest verdict

The **game** is in better shape than the **release surface**. Nothing blocking is
architectural; the blockers are (a) credentials you have to paste in, (b) about a
day of small, local, testable code fixes, and (c) console paperwork. The single
most dangerous property today is that three separate failures — debug signing,
dead Crashlytics, missing RevenueCat key — are all **silent**: a bad build looks
exactly like a good one.

---

## Part 2 — Engineering work before you can ship (priority ordered)

Effort tags: **S** ≈ under an hour, **M** ≈ half a day, **L** ≈ multi-day.

### Wave 0 — cannot ship without these

| # | Work | Effort | Why it blocks |
|---|---|---|---|
| 0.1 | **Decide the UI redesign**: finish + re-green, or `git stash` it | M | 10 px HUD overflow ships into your own store screenshots; 22 px header drift invalidates the board calibration |
| 0.2 | **Real `google-services.json`** for `com.adbkv.chainpop` from the production Firebase project; add a release-mode check that `crashReportingReady == true` | S | Without it Crashlytics + Analytics are dead, and every P0 fix below is unverifiable in the wild |
| 0.3 | **Analytics service** (`AnalyticsService` behind `AnalyticsLocator`, mirroring `AdsLocator`) + ~15 events at the call sites the audit already enumerated | M | You cannot run a staged rollout you cannot measure. Ship the funnel: `level_start/complete/fail/retry`, `tutorial_start/complete`, rewarded lifecycle, `interstitial_shown`, `purchase_*`, `daily_*` |
| 0.4 | **Gate `kAdmobTestDeviceIds` behind `kDebugMode`** | S | This is why your APK shows dummy ads; it also makes production ad validation impossible |
| 0.5 | **Fail the release build loudly** when the release signing config is missing (replace the `?: signingConfigs.getByName("debug")` fallback with a `throw GradleException` for release) | S | A clean checkout / CI silently produces a debug-signed AAB Play will reject or, worse, that you upload with the wrong key |
| 0.6 | **Portrait lock**: `android:screenOrientation="portrait"` + `SystemChrome.setPreferredOrientations` | S | The Flame board layout was never designed for landscape; a reviewer rotating the device is a rejection risk and a 1-star review generator |
| 0.7 | **Rewarded-ad timeout + try/catch** (`done.future.timeout(45s, () => false)`, wrap `ad.show`) | S | An SDK that delivers no terminal callback strands the player forever; an ad throw is currently logged as a *fatal* crash |
| 0.8 | **Pause the countdown during rewarded ads** (`adInFlight` flag set/restored in `finally`) | S | Players lose levels while watching an ad they chose to watch to win — the highest-goodwill-cost defect in the app |
| 0.9 | **Gate the toolbar / hint / pause on `_hasWon \|\| _engine.hasWon`** | S | A won level can be restarted during the ~1.75 s cascade finale and the win never records |
| 0.10 | **Harden `Hive.openBox`**: try → `deleteBoxFromDisk` → reopen once, and report | S | A corrupt box is a dead splash screen with no message and no crash report |
| 0.11 | **RevenueCat**: assert a non-empty key in release; move `addCustomerInfoUpdateListener` out of the `getCustomerInfo` try block | S | A build without the define ships with the paid product permanently broken and silent; an offline launch strands a paying customer with ads all session |
| 0.12 | **Money-path tests**: make `RecordingAdService` grant-configurable and move it to `test/`; test premium bypasses all four ad types, a grant reaches the engine, a failure consumes no budget | M | The purchase and reward paths have literally zero coverage today |
| 0.13 | **Make `flutter test` a usable gate**: tag the four corpus report harnesses (`@Tags(['corpus'])` + `dart_test.yaml` exclusion) | S | Today the suite doesn't finish in 40 min, so nothing can enforce green |
| 0.14 | **CI** (`.github/workflows/ci.yaml`): `flutter analyze` + tagged-out `flutter test` on push | S | Wave 0 regressions are otherwise invisible |

### Wave 1 — ship-quality, do during the closed-test period

| # | Work | Effort | Payoff |
|---|---|---|---|
| 1.1 | **In-app "Reset / delete my data"** in Privacy & Ads (wipes Hive, offers the Play Games account-data link) | S | Satisfies GDPR/CCPA deletion for the only data you hold, and it's the honest answer to "Right to Deletion" your policy already promises |
| 1.2 | **Stuck-state detection** — poll `hasAvailableHint()` after each extraction/undo, surface "no moves left → undo or watch a hint" | M | The worst UX moment in the game *and* the highest-intent rewarded impression, both fixed by one change |
| 1.3 | **Canonical-order hints** (lowest-id removable node instead of list order) | S | Players currently pay an ad for an arbitrary suggestion |
| 1.4 | **Stop charging for unsolicited ghost hints** | S | Two idle pauses silently spend both free hints |
| 1.5 | **Per-world accents + rename worlds 5–9** | S | Levels 1–125 currently share one cyan palette and world names that promise mechanics that aren't there |
| 1.6 | **Haptics on win / cascade / star / combo** | S | Two haptic events exist in a game whose whole fantasy is tactile |
| 1.7 | **Colorblind coverage for meaning-carrying colours** (core ring, blocker flash, relay, ray) | M | Today colorblind mode remaps only the 6-slot node palette — the mechanical colours are untouched |
| 1.8 | **Low-end physical device pass**: FPS, cold start, thermals, safe areas, ad transitions | M | Android vitals (ANR/crash rate) decide whether Play promotes or buries you |
| 1.9 | **Toolchain**: AGP → ≥ 9.0.1, Kotlin → ≥ 2.3.20 | S | Flutter is about to stop supporting the current versions |

### Wave 2 — post-launch, driven by the data Wave 0 gives you

Milestone-seed fallthrough observability (16/40 milestones ship as ordinary
boards), portal fix-through, pre- vs post-enrichment band drift, Director-internal
deadline for seeded/daily generation, DiversityLedger persistence, reduced-motion
setting. All are already specified in `docs/PRODUCTION_AUDIT.md`; none block
launch.

### Security / hardening review (done today, findings below)

The attack surface is genuinely small — no accounts, no server of your own, no
user-generated content, no runtime permissions, no deep links, no exported
components of your own beyond the launcher activity. Scanned and found:

| Finding | Severity | Action |
|---|---|---|
| **No secrets in the repo.** `grep` for `AIza…`, `goog_…`, `appl_…`, PEM blocks across `lib/`, `android/`, `tools/` → zero hits. RevenueCat keys arrive by `--dart-define`, which is correct (and the RC *public* SDK key is designed to be extractable anyway). | ✅ | none |
| **`.gitignore` does not exclude `key.properties` / keystores**, and `android/app/google-services.json` is tracked. The keystore lives outside the repo today, which is what saves you. | Medium | Add `**/key.properties`, `*.jks`, `*.keystore` to `.gitignore` before anyone clones or you add a second machine. `google-services.json` is not a secret and may stay tracked. |
| **No `android:allowBackup` / `dataExtractionRules` declared** → Android's default is backup **on**, so Hive progress silently syncs to the player's Google Drive and restores on a new device. | Low, but decide it | Either embrace it (add `dataExtractionRules.xml` excluding nothing) or set `allowBackup="false"`. Undeclared means "whatever the platform default is this year." |
| **Amazon IAP `ResponseReceiver` is merged into your manifest** by `purchases_flutter`, along with `androidx.work` services. | Low | Harmless; strip with a manifest `tools:node="remove"` only if you want a clean permission/component list for reviewers. |
| **`extractNativeLibs="false"`, no cleartext traffic, targetSdk 36** → modern defaults are all in place. | ✅ | none |
| **WebView is only the UMP consent form**; `launchUrl` targets are three constants, never user input. | ✅ | none |
| **Obfuscation is on** (`--obfuscate --split-debug-info`) — keep `build/debug-info/` per release or Crashlytics stack traces are unreadable. | ⚠️ process | Archive the symbols directory with the same version tag as the AAB |

### Notifications — deliberately *not* in Wave 0

There is no notification package in `pubspec.yaml` today, and that is the right
call for launch. Notifications are a retention lever, and you have no retention
data yet. Post-launch, the cheapest version is **local** notifications
(`flutter_local_notifications`) for a daily-challenge reminder — no server, no
FCM, no token handling. Android 13+ requires the runtime `POST_NOTIFICATIONS`
permission, so ask for it *after* a player has completed a daily challenge, never
at first launch. Only add FCM if you later want server-driven campaigns; it adds
a Data Safety disclosure and a token lifecycle for a benefit you can't yet
measure.

---

## Part 3 — Play Console & compliance (everything the console will ask you)

Sources for this part are Google's own 2026 documentation; the numbers below were
verified against live help pages on 2026-08-16.

### 3.1 The two dates that actually constrain you

| Date | Requirement | Your state |
|---|---|---|
| **2026-08-31** | New apps and all updates must target **API 36** | ✅ **Already compliant** — Flutter 3.47 defaults `targetSdk = 36`. Pin it explicitly in `build.gradle.kts` so a Flutter downgrade can't silently drop you to 35. Extensions run to Nov 1, 2026 if you ever need one. |
| **2027-02-01** | 16 KB page-size support for 64-bit native libs | Very likely fine (Flutter 3.47 + AGP 8.11 + current plugins), but **verify in Play Console → App bundle explorer** after your first upload rather than assuming. |

### 3.2 Android 16 behaviour changes that hit *this* game

Targeting 36 is not free — three Android 16 changes land directly on a
full-screen Flame board with a top HUD and bottom toolbar:

1. **Edge-to-edge is mandatory and cannot be opted out of at targetSdk 36.**
   The app draws behind the status and nav bars. Your HUD/toolbar insets must
   come from `MediaQuery.viewPadding` / `SafeArea` — which the header already
   uses — but this interacts badly with the 22 px header drift and the 10 px
   overflow found in Part 1. **Test on a notch device with gesture navigation
   before you ship.**
2. **Predictive back**: at targetSdk 36 the system animates back and
   `onBackPressed`/`KEYCODE_BACK` are no longer delivered. Verify the pause
   overlay, level exit, and settings sheets all still dismiss correctly.
3. **Orientation locks are ignored on `sw600dp`+ screens** (tablets, foldables)
   — *unless* the manifest declares `android:appCategory="game"`. Since Wave 0
   adds a portrait lock, **add `android:appCategory="game"` in the same edit**
   or your portrait lock silently does nothing on tablets.

### 3.3 App content declarations — the full list

Every one of these must be completed before a production release can be
submitted. The three "doesn't apply" ones still block you if left blank.

| Declaration | Your answer | Notes |
|---|---|---|
| **Privacy policy URL** | your hosted policy | Must name the developer entity exactly as the store listing does, and must disclose AdMob, Firebase Analytics/Crashlytics, RevenueCat, Play Games by name or as a linked list |
| **Ads** | **Yes, contains ads** | Banners + interstitials make this mandatory. (Rewarded-only apps could say no; you have both.) Google verifies independently and will label you anyway. |
| **App access** | All functionality available without special access | True — no login wall. Make sure the game is fully playable **signed out of Play Games**, or the reviewer and the pre-launch crawler hit a dead end. |
| **Content rating (IARC)** | Category **Game**; no violence/sex/language/drugs; **ads = yes**; **digital purchases = yes**; no location, no user-to-user comms | Expect ESRB *Everyone* / PEGI 3 with "In-Game Purchases". Then set AdMob `maxAdContentRating: MaxAdContentRating.g` so the *ads* match the rating — this is an actively enforced pairing. |
| **Target audience** | **13+ only** (13–15, 16–17, 18+) | Do **not** tick any under-13 bucket: it triggers Families policy, bans the standard Ads SDK, and kills personalized ads. **But** Google also judges your *art*: a bright cartoon icon with an under-13 look gets reclassified. Unbound's neon-geometric identity is on the safe side of that line — keep it there. |
| **Advertising ID** | **Yes — Advertising/marketing + Analytics** | `AD_ID` is already merged into your manifest by the Ads SDK (confirmed in Part 1). Saying "no" while the permission ships is a warning/blocker. |
| **Financial features** | "My app doesn't provide any financial features" | Mandatory even though it doesn't apply |
| **Health apps** | No health features | Mandatory even though it doesn't apply |
| **Government apps** | No | Mandatory |
| **News apps** | No | Mandatory |
| **EU DSA trader status** | **You are a trader** | Ad revenue alone makes you one. Mandatory since 2025-02-17; failure blocks EU distribution. **Your verified name + address get published on the EU store listing.** |

### 3.4 Data Safety form — your exact answers

"Collected" = leaves the device (including via any SDK). Hive is device-local, so
it declares as **nothing**.

| Source | Data types to declare | Collected | Shared | Purpose |
|---|---|---|---|---|
| AdMob | Device or other IDs (AAID, App Set ID), App activity → product interactions, App info & performance → diagnostics, **IP address** | Yes | **Yes** | Advertising, Analytics, Fraud prevention |
| Firebase Analytics | Device or other IDs, App activity, App info & performance | Yes | No (service provider) | Analytics |
| Crashlytics | App info & performance → crash logs / diagnostics; install UUID | Yes | No | Crash reporting |
| RevenueCat | **Financial info → Purchase history** | Yes | No | App functionality |
| Play Games Services | Personal info → other (gamertag/avatar); App activity → achievements/scores | Yes | No | App functionality, Analytics |
| Hive local progress | — | **No** | — | — |
| "Encrypted in transit?" | **Yes** — all four SDKs use TLS | | | |
| "Way to request data deletion?" | **Yes** (see 3.5) | | | |

> **The single most common enforcement hit for indie games** is declaring "no
> data shared" while an ads SDK ships the advertising ID. Declare Device IDs as
> *collected **and** shared* for advertising. Non-negotiable.

### 3.5 Data deletion — what actually applies to you

Play's **account deletion** policy binds apps that *let users create an account
in the app*. You don't: progress is local Hive, Play Games uses the player's
existing Google account, and RevenueCat's app-user id is anonymous. So the
mandatory in-app deletion flow and deletion URL **do not apply**.

The Data Safety form's *"do you provide a way to request deletion"* question is
separate, though, and answering **Yes** is cheap insurance. Do both of these:

1. **A one-page "Delete your Unbound data" page** on the same site that hosts
   your privacy policy, stating: local progress is removed on uninstall; Play
   Games data is deletable at `play.google.com/games/profile` and
   `myaccount.google.com`; purchase and diagnostic records can be deleted by
   emailing `adbkv.apps@gmail.com`; and what you retain for fraud/legal reasons.
2. **An in-app "Reset my data" button** (Wave 1.1) under Privacy & Ads that wipes
   the Hive box. Your privacy policy already promises a right to deletion —
   right now the app has no way to honour it.

### 3.6 Developer account requirements — check this first, it sets your timeline

- **Identity verification**: personal accounts need legal name, address, phone,
  and a government ID; the address is verified.
- **Your home address becomes public.** Once you have a payments/merchant profile
  (required for IAP) and once you declare EU DSA trader status, the address on
  the payments profile is displayed on the store listing. **Decide before you
  create the merchant profile** whether that should be a home address, a
  registered business address, or a virtual/agent address — changing it later is
  painful.
- **⚠️ The 12-tester / 14-day closed test gate.** Personal Play Console accounts
  **created after 2023-11-13** must run a closed test with **≥ 12 testers
  continuously opted in for ≥ 14 unbroken days**, then apply for production
  access (**~7 days review**). If your account is new — which it almost certainly
  is if you just paid the fee — **this is your critical path**: ~3–5 weeks from
  first closed-test upload to public launch. "Opted in" means the tester accepted
  *and installed*; a tester who drops out resets the clock.
- **Android developer verification** (the sideloading programme, live 2026-09-30
  in BR/ID/SG/TH) auto-registers ~99% of Play-distributed apps. No action
  expected.

### 3.7 Store listing assets — exact specs

| Asset | Spec | Status |
|---|---|---|
| App icon | **512×512**, 32-bit PNG with alpha, ≤ 1024 KB | ❌ not made (you have a 584 KB source `app_icon.png` to derive from) |
| Feature graphic | **1024×500**, JPEG or 24-bit PNG, **no alpha** | ❌ |
| Phone screenshots | min 2 to publish; **use ≥ 4 at ≥ 1080 px, 9:16** to qualify for Play's promotional surfaces | ❌ |
| 7" tablet screenshots | 4 (recommended 1920×1200) | ❌ — needed for tablet-optimised treatment |
| 10" tablet screenshots | 4 (recommended 2560×1600) | ❌ |
| Promo video | one YouTube URL, **ads disabled on the video**, first 30 s representative gameplay | optional, high value for games |
| App name | ≤ 30 chars | "Unbound: Arrow Puzzle" fits |
| Short description | ≤ 80 chars | ❌ |
| Full description | ≤ 4000 chars | ❌ |

Metadata hazards that get indie games rejected: keyword stuffing, competitor
names, "#1"/"Best" in the title, emoji or ALL-CAPS in the name, store badges
inside screenshots, and **screenshots that show a build you are not submitting**.

### 3.8 Regions

Launch broad, with two deliberate exclusions to consider:

- **Vietnam** — Decree 147/2024 requires licensing for "online electronic games";
  Play Games leaderboards arguably make you one. Cheapest de-risk is to exclude
  Vietnam at launch.
- **South Korea** — GRAC certification is required for games with gambling or
  randomised-reward mechanics. Unbound has none, so Korea is fine as long as you
  never add a spin-the-wheel/loot-box meta without revisiting this.
- **Brazil** — the 2026 Digital ECA bans loot boxes in child-directed games and
  requires the Age Signals API for them. Declaring 13+ keeps you outside it.
- **EU** — DSA trader status (3.3) is mandatory; no geo-blocking by nationality.
- **US billing** — the post-*Epic* external-payment-link programme exists but adds
  reporting obligations from 2026-07-22 and fees from 2026-10-01. **Ignore it**;
  stay on Play Billing via RevenueCat.

### 3.9 Ads policy — audit of your actual placements

Google's Better Ads Experiences policy names *"puzzles, idle games"* as the genre
that must "exercise good judgment" because it has no natural breaks. Your
placements, checked against the policy:

| Placement | Code | Verdict |
|---|---|---|
| Interstitial between campaign levels | `game_flow_controller.dart:286` inside `goNextLevel()`, behind three gates | ✅ Compliant — it fires on the *transition after* the win, not at level start. One nuance: it can fire off the auto-advance timer rather than an explicit tap, so the player didn't press anything immediately before. Consider requiring the Continue tap (or the full auto-advance countdown to elapse) so it never reads as unprompted. |
| Rewarded: hint / undo / continue / daily unlock | `AdPlacements` | ✅ Exempt from disruptive-ad rules — user opt-in. This is also your best revenue. |
| Banner: game screen, pause overlay, daily calendar | `game_screen.dart:995`, `:1010` | ✅ Allowed. Keep clear separation from the toolbar — accidental-click layouts are an AdMob invalid-traffic risk, not just a UX one. |
| App-open ad | none | ✅ Correct — a full-screen ad at launch is the highest-risk placement in the policy. Don't add one. |

**Never** add: ads at level start, ads on exit/back, ads during solving, or a
non-dismissible full-screen ad.

### 3.10 Android vitals — the thresholds that decide your discoverability

| Metric | Bad-behaviour threshold |
|---|---|
| User-perceived **crash rate** | ≥ **1.09%** of daily users (≥ 8% on a single device model) |
| User-perceived **ANR rate** | ≥ **0.47%** of daily active users (≥ 8% on a single model) |

Breaching either reduces your discoverability and can put a warning on your
listing. **ANR is your real risk, not crashes**: the seeded/daily generation path
is unbounded (measured 2.2 s worst case, and 66 s / 181 s on a pinned overload
seed), and anything that blocks the main thread for ~5 s on a low-end phone is an
ANR. 0.47% is a very tight budget, and you currently cannot see either number —
which is exactly why P0-2 and P0-1 are Wave 0.

---

## Part 4 — Ads: why you see dummy ads, and the multi-network plan

### 4.1 The dummy ads are self-inflicted

Your unit IDs are already production (`kAdmobUseSampleUnits` defaults `false`,
units resolve to `ca-app-pub-6510329237083952/…`). The reason you see test
creatives is this, at `lib/main.dart:86-88`, which runs in **every** build mode:

```dart
await MobileAds.instance.updateRequestConfiguration(
  RequestConfiguration(testDeviceIds: kAdmobTestDeviceIds),  // ← DC579E05… = your phone
);
```

Registering a device as a test device is *exactly* the API for "serve test
creatives through my own production units." Fix: gate the list behind
`kDebugMode` — the pattern already exists two files away in `ump_consent.dart`,
whose `testIdentifiers` **is** correctly debug-gated.

> **⚠️ Read this before you remove it.** The moment that line is gone from a
> release build, your device serves **live** ads — and tapping your own live ad
> is a named invalid-traffic violation that can terminate an AdMob account
> permanently. So gate it on `kDebugMode` (debug = safe to tap, release = look
> but never touch), and ideally verify on a spare device that is not signed into
> your AdMob Google account.

### 4.2 The second reason: an unpublished app can't serve real ads

AdMob's app-readiness rules require the app to be **published and publicly
downloadable**, with a store listing, **linked to the AdMob app**. Internal and
closed testing tracks do not satisfy "publicly available." Also:

- A new AdMob account must complete **payment profile + tax + identity
  verification** before any app leaves *Getting ready* (usually ≤ 24 h, but
  documented as up to 2 weeks in rare cases).
- App review after linking: **~2–3 days** to reach *Ready*.
- Fill stays thin for roughly the first **2 weeks** while AdMob builds a traffic
  profile. Do not draw conclusions or change the integration during that window.

So the honest expectation: **real ads only work properly after your public
production release**, and healthy fill is roughly a week after that.

### 4.3 `app-ads.txt` — required, and the classic silent revenue killer

1. You need a **developer website**. Firebase Hosting is free and you already
   have Firebase in this project.
2. Play Console → Store settings → **Developer website** = that exact domain.
3. Host at the **root**: `https://yourdomain/app-ads.txt` (redirects allowed,
   subpaths not).
4. Minimum content — your publisher id from `admob_config.dart`:
   ```
   google.com, pub-6510329237083952, DIRECT, f08c47fec0942fa0
   ```
5. **UTF-8, no BOM.** A BOM silently breaks parsing.
6. Crawl takes up to 24 h; status shows in AdMob → Apps → app-ads.txt.
7. **Every mediation network you add later appends its own lines.** Forgetting
   this is the classic "I added mediation and revenue went down" bug.

### 4.4 "No ads serving" — diagnostic order

1. demo unit ids? → 2. **your device on the test list?** ← today's answer →
3. AdMob app status *Ready*? → 4. account payment/identity verified? →
5. app-ads.txt *Verified*? → 6. Policy centre clean? → 7. app actually **public**
on Play? → 8. error code (`3` = no fill, normal at low volume; `1` = bad unit/app
id) → 9. manifest `APPLICATION_ID` resolves to `…~7569862231` → 10. UMP
`canRequestAds()` true?

### 4.5 Multi-network: use AdMob **mediation**, not a Dart-side abstraction

This is the important architectural answer to your question. **You do not
integrate multiple ad suppliers in Dart.** With AdMob Mediation, third-party
networks are native *adapters*; the auction happens server-side and inside the
native layer. Adding AppLovin, Meta, Unity and two dozen exchanges requires
**zero changes** to `ad_service.dart`, `google_mobile_ad_service.dart`,
`ads_locator.dart`, or any game code.

A hand-rolled `AdProvider` multiplex in Dart would be strictly worse: it
re-implements a waterfall in the one place that cannot see real bid data, adds
sequential latency instead of one parallel auction, and multiplies your consent
plumbing per SDK. **Your `AdService` interface is already correctly scoped** —
it exists for *substitution at the factory* (swap `GoogleMobileAdService` for
some future `AppLovinMaxAdService`), not for *runtime coexistence*. Keep it as
it is.

**Also: you may run exactly one primary mediator SDK.** AdMob Mediation and
AppLovin MAX cannot both mediate; whichever you pick, the others participate as
bidders inside it.

**Why AdMob mediation specifically, for a solo Flutter dev in 2026:** Google
maintains **first-party Flutter adapter packages** under the verified
`google.dev` publisher — `gma_mediation_applovin`, `_meta`, `_unity`,
`_liftoffmonetize`, `_ironsource`, `_pangle`, `_mintegral`, `_inmobi`, `_moloco`,
`_dtexchange` — all updated within the last month. No competing mediator has
that. (`applovin_max` on pub.dev is published by an *unverified uploader*, which
is a real operational risk if you bet your whole monetization layer on it.)

**Bidding, not waterfall.** Unity's waterfall mediation ended 2026-01-31 and Meta
has been bidding-only since 2021. Configure bidding-only mediation groups.

**Free demand you should turn on immediately:** roughly two dozen bidding
exchanges (Index Exchange, OpenX, PubMatic, Smaato, Media.net, Magnite,
TripleLift, Verve, …) need **no SDK, no Gradle change, no APK size, no Dart
code** — just checkboxes in the AdMob console plus their `app-ads.txt` lines. Do
this on day one regardless of DAU.

**SDK-backed adapters can wait.** Below ~1,000 DAU the incremental revenue from
AppLovin/Meta/Unity adapters is noise against the maintenance cost. Add them one
at a time, 7 days apart, once you have a stable revenue-per-DAU baseline.

### 4.6 If/when you add adapters — the two things that silently cost money

1. **Console-side**: AdMob → Privacy & messaging → European regulations message
   → **"Review your ad partners"** — every mediation partner must be selected
   there, or it will never serve in the EEA.
2. **Code-side**: Google does **not** auto-forward consent to mediated networks.
   You must call each network's API yourself **before**
   `MobileAds.instance.initialize()` — `GmaMediationApplovin.setHasUserConsent`
   / `setDoNotSell`, `GmaMediationUnity.setGDPRConsent` / `setCCPAConsent`, and
   Meta's data-processing-options for California. Put these behind one
   `MediationConsentForwarder` class so `main.dart` stays free of
   network-specific imports.

Also note: **mediated ads carry no "Test Ad" label**, so before testing any
mediated build you must enable test mode in each network's own dashboard.

### 4.7 Plugin upgrade: `google_mobile_ads` 8.0.0 → 9.1.0

Do this **before** adapters (they target 9.x), not during a revenue incident:

- 9.1.0 ships GMA Android 25.4.0 + UMP 4.0.0, ad preloading APIs,
  `ageRestrictedTreatment`, `setConsentSyncId()`.
- `tagForChildDirectedTreatment` / `tagForUnderAgeOfConsent` are deprecated →
  single `ageRestrictedTreatment` property.
- `getAnchoredAdaptiveBannerAdSize` is deprecated → the large-anchored variant.
  You already have this warning in `daily_challenge_banner_slot.dart:53`.
- While you're there: add `maxAdContentRating: MaxAdContentRating.g` (matches
  your IARC rating and keeps gambling/dating creatives out of an E-rated game)
  and gate `MobileAds.initialize()` behind `await canRequestAds()`.

### 4.8 What to expect financially

Directional 2026 benchmarks (third-party aggregates, not guarantees):

| Format | Tier-1 eCPM | Global | Tier-3 |
|---|---|---|---|
| Rewarded video | $15–30 | $8–22 | ~$0.50–2.50 |
| Interstitial | $5–8 | $2.50–5 | ~$0.30–1.20 |
| Banner | $0.50–1.50 | $0.20–0.80 | ~$0.05–0.25 |

Rewarded is 3–6× interstitial per impression *and* better for retention — which
is exactly the shape your monetization already has (hint / undo / continue /
daily unlock). **Lean into rewarded; keep interstitials gated as they are.**
Measure **revenue per DAU**, not eCPM — eCPM rises trivially by showing fewer
ads, which can reduce total revenue.

### 4.9 AdMob payments — start the clock now

| Step | When | Duration |
|---|---|---|
| Payment profile + tax info (W-9 / W-8BEN) | **today** | ~20 min, and it unblocks app readiness |
| Account verification | at signup | ≤ 24 h typical |
| **PIN by physical mail** | balance hits **$10** | **2–3 weeks in the post — the hidden long pole** |
| First payout | balance ≥ **$100** at month end | paid ~21st of the following month |

Realistically **3–4 months from publish to money in the bank**. Doing the profile
and tax steps today is free and shortens that.

---

## Part 5 — The sequenced plan

The critical path is **not** the code. It is: *closed test (14 days) → production
access review (~7 days) → public release → AdMob readiness (~1 week)*. Start the
clock as early as you can, and do Wave 1 work while it runs.

### Week 0 — unblock the long poles (do these first, in this order)

1. **Play Console**: finish identity verification; decide the public address
   before creating the merchant profile; complete the merchant/payments profile
   and tax forms.
2. **AdMob**: payment profile + tax + identity verification.
3. **Firebase**: create the real project for `com.adbkv.chainpop`, download
   `google-services.json`, replace the placeholder → *this single step makes
   Crashlytics and Analytics live*.
4. **RevenueCat**: entitlement `Unbound Pro`, product(s), offering; link the Play
   product; get the `goog_…` public key.
5. **Website + app-ads.txt** on Firebase Hosting; set the Play Console developer
   website field.
6. **Decide the UI redesign** (finish vs stash) — everything visual downstream
   (screenshots, tutorial polish) depends on this answer.

### Week 1 — Wave 0 code + first upload

7. Wave 0 items 0.2–0.14 from Part 2 (roughly 1–2 focused days of work).
8. Build the release AAB with the real defines:
   ```bash
   flutter build appbundle --release --dart-define=REVENUECAT_GOOGLE_API_KEY=goog_xxx --obfuscate --split-debug-info=build/debug-info
   ```
   Archive `build/debug-info/` alongside the AAB, tagged with the version.
9. **Internal testing track**: verify cold start, consent form, real purchase +
   restore, rewarded grant, Play Games achievement sync, and that Crashlytics
   receives a forced test crash.
10. Complete every App content declaration + Data Safety form (Part 3).
11. Produce store assets (Part 3.7) and the listing copy.

### Weeks 2–3 — closed test, 12+ testers, 14 unbroken days

12. Recruit ≥ 12 testers (personal contacts + Android tester communities); make
    sure each **installs**, and keep them opted in.
13. Ship Wave 1 during this window; each build goes to the same closed track.
14. Watch the **pre-launch report** (Robo crawler) for crashes, overflows, and
    accessibility findings; drive it into the game screen with a Robo script if
    coverage is shallow.
15. Do the low-end physical device pass.

### Week 4 — production access + release

16. Apply for production access (~7 days review).
17. Publish the **Play Games Services** configuration — note the achievement
    catalog is frozen at exactly 2000 points and is unpublishable-once-live, so
    re-verify it before pressing publish.
18. Publish to production. **Note: staged rollout is not available for a
    first-time release** — v1.0.0 goes to 100% of selected countries at once,
    which is another reason the closed test must be real.
19. Link the AdMob app to the live listing; wait for *Ready*; enable the zero-SDK
    bidding exchanges; verify app-ads.txt shows *Verified*.

### Weeks 5–8 — stabilise, then optimise

20. Watch Android vitals against the 1.09% crash / 0.47% ANR thresholds and the
    analytics funnel you built in Wave 0. Fix what the data says, not what the
    docs guess.
21. Do not touch the ad integration for 30 days.
22. Then: Wave 2 content work, and SDK-backed mediation adapters once you're near
    ~1,000 DAU.

---

## Part 6 — Priority summary

**If you only do ten things, do these, in order:**

1. Real `google-services.json` (makes everything else observable)
2. Decide the UI redesign; kill the 10 px HUD overflow
3. Gate `kAdmobTestDeviceIds` behind `kDebugMode`
4. Analytics service + the ~15 events that carry a decision
5. Fail the release build loudly on missing signing config
6. Portrait lock **+ `android:appCategory="game"`**
7. Rewarded timeout, clock-pause during ads, and the `engine.hasWon` toolbar gate
   (the three defects that take value from a blameless player)
8. Start Play Console verification + the 12-tester closed test clock
9. Data Safety declaring Device IDs **shared** for advertising
10. Website + `app-ads.txt` + AdMob payment profile

**Deliberately *not* before launch:** notifications, mediation adapters, portals,
cloud save, iOS, MAP-Elites, landscape support.
