# SDK Inventory — Unbound

Versions below are the **resolved** versions from `pubspec.lock`, not the caret
ranges in `pubspec.yaml`. Re-verify after any `flutter pub upgrade`.

## Why the "Role" column exists

Google Play's Data Safety form draws a hard line that governs every answer:

- **Service provider** — a vendor processing data *on our behalf*, under our
  instructions, for our purposes. Play's answer is **"collected, not shared."**
- **Third party** — an independent party that uses the data for its own purposes
  (e.g. serving and measuring ads across its own network). Play's answer is
  **"collected AND shared."**

**Google Mobile Ads is a THIRD PARTY.** Every other data-touching SDK in this app
is a service provider. Under-declaring the AdMob sharing answer is the single most
common Data Safety rejection cause for this exact SDK stack, so the Device-IDs and
approximate-location rows in `docs/store_listing.md` must be marked *shared*.

Note on Firebase Analytics: it is a service provider **as configured today**. If
Google Signals / Google Ads linking is ever enabled on the Firebase project
(`unbound-667b8`), that data becomes shared with Google for its own advertising
purposes and the Data Safety answer must change.

---

## Data-collecting SDKs

| SDK | Locked version | **Role** | Play Data Safety answer | Purpose | Data collected | Identifiers | Retention | Privacy URL |
|-----|----------------|----------|-------------------------|---------|----------------|-------------|-----------|-------------|
| Google Mobile Ads (`google_mobile_ads`) | **8.0.0** | **THIRD PARTY** | **Collected AND shared** | Banner / interstitial / rewarded advertising | IP address, user agent, device and app info, ad interaction data, coarse geography derived from IP | Advertising ID (AAID) | Per Google / ad-network policy | [Google Privacy Policy](https://policies.google.com/privacy) |
| User Messaging Platform (UMP) | bundled in `google_mobile_ads` 8.0.0 | Service provider (consent infrastructure) | Not a separate declaration | GDPR/consent collection before ad init | Consent status, consent string | None beyond the ads stack | Stored on device + Google | [Google Privacy Policy](https://policies.google.com/privacy) |
| Firebase Analytics (`firebase_analytics`) | **12.4.2** | Service provider | Collected, not shared | Product analytics (session, level, ad-funnel, purchase and daily events) | App usage events, device model, OS version, IP address (for coarse geo) | App Instance ID; Advertising ID where linked | Configurable in the Firebase console (2 or 14 months) | [Firebase Privacy](https://firebase.google.com/support/privacy) |
| Firebase Crashlytics (`firebase_crashlytics`) | **5.2.3** | Service provider | Collected, not shared | Crash and non-fatal error reporting | Stack traces, device state, OS, app version | Crashlytics Installation UUID | ~90 days | [Firebase Privacy](https://firebase.google.com/support/privacy) |
| **Google Play Games Services (`games_services`)** | **5.3.0** | Service provider (Google, on our behalf, under our Play developer account) | Collected, not shared — **optional**, only when the player signs in | Achievement sync (49 catalog entries, 2000-point budget) | **PGS player ID and display name** (from the `GameAuth.player` stream), **achievement unlock state and step counts** | PGS player ID | Held by Google against the player's Google account | [Google Privacy Policy](https://policies.google.com/privacy) |
| RevenueCat (`purchases_flutter`) | **10.1.0** | Service provider | Collected, not shared | Purchase validation and entitlement (`Unbound Pro`) | Purchase history, store receipts, country, device/app metadata | RevenueCat anonymous App User ID | Until deletion is requested | [RevenueCat Privacy](https://www.revenuecat.com/privacy/) |
| Google Play Billing | via `purchases_flutter` 10.1.0 | Service provider | Collected, not shared | In-app purchase transaction | Purchase token, product ID, order state. **Card/payment details never reach the app** — checkout is entirely inside Google Play | Google account (held by Google) | Per Google Play policy | [Google Privacy Policy](https://policies.google.com/privacy) |
| Firebase Core (`firebase_core`) | **4.10.0** | Service provider | No independent collection | Initialisation only for Analytics + Crashlytics | — | — | — | [Firebase Privacy](https://firebase.google.com/support/privacy) |

### Play Games Services — why it must be declared

It is genuinely shipped, not aspirational:

- `pubspec.yaml` → `games_services: ^5.3.0`, resolved to 5.3.0 in `pubspec.lock`.
- `lib/main.dart` calls `PlayGamesBootstrap.install()` during `bootstrapChainPop()`.
- `lib/services/achievements/play_games_auth.dart` subscribes to
  `gs.GameAuth.player`, which yields a `PlayerData` carrying the **player ID and
  display name**.
- `lib/services/achievements/play_games_achievement_sink.dart` writes achievement
  progress to Google via `Achievements.setSteps` / `Achievements.unlock`, and reads
  remote progress back via `loadAchievements`.
- The manifest declares `com.google.android.gms.games.APP_ID`.

Sign-in is Android-only (`PlayGamesBootstrap._supported`) and is attempted
automatically at startup but is not required to play — the achievement tracker
runs locally either way. That is why the Data Safety answer for **Personal info →
User IDs** is *optional* rather than *required*.

---

## Non-data-collecting dependencies (for completeness)

| Package | Locked version | Note |
|---------|----------------|------|
| `flame` | 1.37.0 | Game/render engine. Local only. |
| `hive` / `hive_flutter` | 2.2.3 / 1.1.0 | Local-only encrypted-at-rest-by-OS key/value store — all game progress lives here and never leaves the device. |
| `webview_flutter` | 4.13.1 | Required by the UMP consent form on Android. No independent collection. |
| `url_launcher` | 6.3.2 | Opens the privacy policy URL and the `mailto:` support link. |
| `google_fonts` | 8.1.0 | **No network access**: `GoogleFonts.config.allowRuntimeFetching = false` in `lib/main.dart` and fonts are bundled under `assets/google_fonts/`. Nothing is fetched from Google's font servers at runtime. |
| `audioplayers` | 6.6.0 | Local asset playback. |
| `haptic_feedback` | 0.5.1+2 | Device haptics. |
| `path_provider` | 2.1.5 | Transitive (Hive storage path). |

---

## Corrections made to the previous revision of this file

- Added the missing **Google Play Games Services (`games_services` 5.3.0)** row —
  it ships, it collects a PGS player ID and display name, and it transmits
  achievement progress.
- Added the **Role** column and the service-provider vs third-party rule that
  drives every Data Safety answer.
- Re-checked every version against `pubspec.lock`: Google Mobile Ads 8.0.0,
  Firebase Analytics 12.4.2, Firebase Crashlytics 5.2.3, RevenueCat 10.1.0 all
  confirmed correct. `firebase_core` 4.10.0 added.
- Corrected the RevenueCat and Firebase Analytics "Data Shared" cells: both were
  previously written as sharing with Google, which mis-states them as third
  parties. They are service providers, so Play's answer is "collected, not
  shared."
- Removed "Payment information" from the Play Billing collected-data cell as
  phrased: the app never touches payment instruments; Google Play's own checkout
  handles them.
