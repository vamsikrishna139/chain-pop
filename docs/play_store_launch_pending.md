# Unbound: Arrow Puzzle — codebase snapshot & Play Store pending work

Merged from the **hybrid/chain-pop engineering review** and a **launch checklist**. Use this file as the single “what’s left before Play” list.

---

## 1. Codebase snapshot (current state)

These items are already in solid shape **in-tree** for Android:

| Area | Status |
|------|--------|
| **Architecture** | Clear split: Flame/game (`lib/game`) vs Flutter UI (`lib/screens`). Ads behind `AdService`; premium via RevenueCat + `PremiumAdServiceDecorator`. |
| **Generation** | Director-driven / retrograde generation path is wired with broad generator tests under `test/game/levels/generation/`. |
| **Monetization & consent** | RevenueCat init → if not premium: UMP consent → `MobileAds.instance.initialize()` → `AdService.bootstrap()`. Premium skips Mobile Ads init at cold start. |
| **In-app purchases** | `purchases_flutter` + `RevenueCatSubscriptionService`. Entitlement id: **`Unbound Pro`** (`lib/config/subscription_config.dart`) — must match RevenueCat dashboard. |
| **Android identity** | `applicationId` / namespace `com.adbkv.chainpop`; display name **Unbound**. |
| **`INTERNET` (release-safe)** | Declared on **`main`** manifest (`android/app/src/main/AndroidManifest.xml`). |
| **Release shrinking** | R8/minify + `proguard-rules.pro`. |
| **Launcher icons** | `flutter_launcher_icons` from `assets/branding/app_icon.png`. |
| **Legal URL hook** | `lib/config/chain_pop_legal.dart` → `https://sites.google.com/view/unbound-policy/home`; override with `--dart-define=CHAINPOP_PRIVACY_POLICY_URL=...`. |
| **Privacy in-app** | Home settings + in-game settings → **Privacy & Ads** (UMP, rights sheet, policy link). |
| **`flutter test` (Dart suite)** | Run before each release; integration tests (`integration_test/`) are separate. |

### Release build defines (required for IAP)

Pass RevenueCat public SDK keys at build time (never commit keys into source):

```bash
flutter build appbundle --release \
  --dart-define=REVENUECAT_GOOGLE_API_KEY=goog_xxx \
  --obfuscate --split-debug-info=build/debug-info
```

iOS builds additionally need:

```bash
--dart-define=REVENUECAT_APPLE_API_KEY=appl_xxx
```

Optional overrides: `MOCK_ADS=true`, `CHAINPOP_PRIVACY_POLICY_URL=...`, `ADMOB_USE_SAMPLE_UNITS=true`.

### Corrections vs a generic checklist

1. **AdMob Android “test vs prod”**  
   **`lib/services/ads/admob_config.dart` defaults Android to production-style IDs** (`kAdmobUseSampleUnits` defaults to **false**). Confirm units in AdMob Console belong to your app.

2. **Portrait lock**  
   **Not currently set** on `MainActivity`. Add `android:screenOrientation="portrait"` if you want portrait-only on Play.

3. **`google-services.json`**  
   Replace placeholder with Firebase file for **`com.adbkv.chainpop`** for production Crashlytics/Analytics.

4. **RevenueCat console**  
   Create entitlement **`Unbound Pro`**, lifetime (or chosen) product, and offerings. Keys via `--dart-define` above.

5. **Signing**  
   `android/app/build.gradle.kts` resolves signing from env / `local.properties` / `game/jks/key.properties`. Back up upload keystore off-machine.

---

## 2. Pending Play Store checklist (remaining work)

### Phase A — Credentials & native config

- [ ] **Firebase:** Real **`google-services.json`** for `com.adbkv.chainpop`.
- [ ] **RevenueCat:** Entitlement **`Unbound Pro`**, products, offerings; Google Play / App Store products linked.
- [ ] **Build:** Release AAB/APK with `REVENUECAT_GOOGLE_API_KEY` (and Apple key for iOS).
- [ ] **AdMob:** Confirm production app + unit IDs.
- [ ] **Upload keystore:** Backed up; `key.properties` resolves correctly.
- [ ] **Portrait (optional):** Lock orientation if required by product.

### Phase B — Release build

```bash
flutter build appbundle --release \
  --dart-define=REVENUECAT_GOOGLE_API_KEY=goog_xxx \
  --obfuscate --split-debug-info=build/debug-info
```

Retain **`build/debug-info/`** for Crashlytics symbolication.

### Phase C — Privacy, policy & Play Console

- [ ] **Hosted privacy policy** at the URL in `ChainPopLegal` (covers ads, analytics, crash, **RevenueCat IAP** — see `docs/privacy.md`).
- [ ] **Data Safety & ads declarations** aligned with Firebase + Mobile Ads + billing.
- [ ] **Content rating** (IARC).
- [ ] **Store listing:** Unbound branding, 512×512 icon, feature graphic, screenshots.
- [ ] **Internal testing:** Cold start, consent, free vs premium (no ads / instant rewarded), purchase + restore.
- [ ] **Production rollout:** Upload `.aab`, complete questionnaires, rollout.

---

## 3. One-line verdict

The **game, premium path, and Android build wiring are production-shaped** for Play; outstanding work is **Firebase/AdMob/RevenueCat console setup**, **release build defines**, keystore backup, optional orientation lock, and **Play Console listing + compliance**.
