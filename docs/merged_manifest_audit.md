# Merged Manifest Audit — Unbound (com.adbkv.chainpop)

Date: 2026-09-03
Branch: `new_improvements`
Purpose: evidence for the Play Store launch gate — what permissions actually
ship, who injects them, and whether the `tools:node="remove"` block in the
source manifest is justified.

## 1. How this evidence was produced

Commands run (from the repo root unless noted):

```
cd android && ./gradlew :app:processDebugManifest
cd android && ./gradlew :app:processReleaseMainManifest
```

Both succeeded. (Full release *assembly* still fails by design: there is no
keystore on this machine, so `signingConfigs["release"]` is invalid and the
build type throws `Release signing config 'release' is missing or invalid.`
Manifest processing does not need the keystore, so the release manifest is
still verifiable.)

Artifacts read:

| Artifact | Path (relative to repo root) |
| --- | --- |
| Merged manifest, debug | `build/app/intermediates/merged_manifests/debug/processDebugManifest/AndroidManifest.xml` |
| Merged manifest, release | `build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml` |
| Manifest-merger blame, debug | `build/app/outputs/logs/manifest-merger-debug-report.txt` |
| Manifest-merger blame, release | `build/app/outputs/logs/manifest-merger-release-report.txt` |

Note the Flutter/AGP output tree for this project is at the repo-root `build/`
directory (`android/build` is a symlink target of the Flutter `build` dir), not
`android/app/build`.

The debug and release permission sets are **identical** (verified by diffing the
sorted `uses-permission` lines of the two merged manifests — no differences).

## 2. Every `<uses-permission>` in the merged manifest

12 permissions ship. Source attributions come from the merger blame report
(`ADDED from` = first declaration; other modules `MERGED` the same element).

| # | Permission | Injected by | Legitimate? |
| --- | --- | --- | --- |
| 1 | `android.permission.INTERNET` | App manifest (`android/app/src/main/AndroidManifest.xml`); also merged from `firebase_analytics`, `google_mobile_ads`, `purchases:10.5.0`, `play-services-measurement*`, `play-services-ads-api:25.1.0`, `firebase-crashlytics:20.0.6`, `firebase-installations`, `transport-backend-cct` | Yes — ads, IAP, analytics, crash reporting all require network. |
| 2 | `android.permission.ACCESS_NETWORK_STATE` | `firebase_analytics` (plugin); merged from `play-services-measurement*`, `play-services-ads-api`, `firebase-installations`, `androidx.work:work-runtime:2.7.0`, `transport-runtime`/`transport-backend-cct` | Yes — SDKs check connectivity before uploads/ad requests. Normal permission, no runtime prompt. |
| 3 | `android.permission.WAKE_LOCK` | `firebase_analytics` (plugin); merged from `play-services-measurement*`, `androidx.work:work-runtime:2.7.0` | Yes — required by Firebase/WorkManager background upload jobs. **Not** ours to remove: `audioplayers` does not declare it (see §5), but Firebase and WorkManager do and depend on it. |
| 4 | `android.permission.VIBRATE` | `haptic_feedback` plugin (`io.achim.haptic_feedback`) | Yes — the game's own haptics. **Must not be removed.** Normal permission. |
| 5 | `com.android.vending.BILLING` | `com.android.billingclient:billing:8.3.0` (via `purchases_flutter` / RevenueCat) | Yes — required for the Play Billing subscription/IAP flow. |
| 6 | `com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE` | `play-services-measurement:23.2.0` (merged from `play-services-measurement-impl`) | Yes — Firebase Analytics install-referrer attribution. Signature-bound to Play Store, no user-facing prompt. |
| 7 | **`com.google.android.gms.permission.AD_ID`** | `play-services-measurement-impl:23.2.0`; merged from `play-services-ads-api:25.1.0`, `play-services-measurement-api`, `play-services-ads-identifier:18.0.0`, `play-services-measurement-sdk-api` | **Yes — PRESENT, and legitimate.** See §3. |
| 8 | `android.permission.ACCESS_ADSERVICES_AD_ID` | `play-services-ads-api:25.1.0`; merged from `play-services-measurement-api`, `play-services-measurement-sdk-api` | Yes — Android Privacy Sandbox AdServices equivalent of AD_ID. |
| 9 | `android.permission.ACCESS_ADSERVICES_ATTRIBUTION` | `play-services-ads-api:25.1.0`; merged from `play-services-measurement-api`, `play-services-measurement-sdk-api` | Yes — Privacy Sandbox attribution reporting for ads. |
| 10 | `android.permission.ACCESS_ADSERVICES_TOPICS` | `play-services-ads-api:25.1.0` | Yes — Privacy Sandbox Topics API for ad relevance. |
| 11 | `android.permission.FOREGROUND_SERVICE` | `androidx.work:work-runtime:2.7.0` (transitively via Firebase/GMS) | Yes, but incidental — we schedule no expedited work ourselves. Not removable without risking WorkManager runtime failures inside the GMS/Firebase SDKs. |
| 12 | `com.adbkv.chainpop.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `androidx.core:core:1.17.0` | Yes — an auto-generated `signature`-level permission (declared alongside a matching `<permission android:protectionLevel="signature">`). AndroidX uses it to keep dynamically registered receivers non-exported. Invisible to users. |

Permissions that a dependency *tried* to add but that do **not** ship:

- `android.permission.RECEIVE_BOOT_COMPLETED` — added by `androidx.work:work-runtime:2.7.0`, then **removed by `play-services-ads-api:25.1.0`'s own `tools:node="remove"`**. Not in the final manifest. Nothing in our manifest was involved.

## 3. Advertising ID (`AD_ID`) — confirmation

`com.google.android.gms.permission.AD_ID` **IS present** in both the debug and
release merged manifests (debug line 83, release equivalent). It is injected by
`play-services-measurement-impl:23.2.0` and re-declared by
`play-services-ads-api:25.1.0` and `play-services-ads-identifier:18.0.0`, i.e.
by Firebase Analytics and by google_mobile_ads. It is legitimate and required —
the app serves AdMob ads and runs Firebase Analytics.

**Play Console action:** the Data Safety form must declare **"Yes"** for
Advertising ID, and the app content / ads declaration must state the app
contains ads. Declaring "No" while shipping this permission is an automatic
policy rejection.

## 4. Verdict on the 13 `tools:node="remove"` lines

All 13 are in `android/app/src/main/AndroidManifest.xml` (lines 4–16).

The manifest merger reports each one explicitly. Running
`./gradlew :app:processDebugManifest` emits, for **all thirteen**:

```
uses-permission#<NAME> was tagged at AndroidManifest.xml:0 to remove other
declarations but no other declaration present
```

and the blame report shows each as `ADDED from .../src/main/AndroidManifest.xml`
with **no other contributing source**. That is conclusive: no dependency in the
current dependency graph injects any of them.

| Permission removed | Removed something? | Verdict |
| --- | --- | --- |
| `ACCESS_FINE_LOCATION` | No | No-op |
| `ACCESS_COARSE_LOCATION` | No | No-op |
| `READ_CONTACTS` | No | No-op |
| `WRITE_CONTACTS` | No | No-op |
| `READ_EXTERNAL_STORAGE` | No | No-op |
| `WRITE_EXTERNAL_STORAGE` | No | No-op |
| `RECORD_AUDIO` | No | No-op |
| `CAMERA` | No | No-op |
| `READ_SMS` | No | No-op |
| `SEND_SMS` | No | No-op |
| `RECEIVE_SMS` | No | No-op |
| `CALL_PHONE` | No | No-op |
| `READ_PHONE_STATE` | No | No-op |

**13 / 13 are no-ops.** They remove nothing, and they generate 13 build warnings
on every manifest merge.

### Is any removal stripping something a dependency needs?

**No.** Specifically checked, because these were the plausible risks:

- `VIBRATE` — needed by `haptic_feedback`. It is **not** in the removal list and
  it **does** ship (row 4 above). Safe.
- `WAKE_LOCK` — needed by Firebase Analytics / WorkManager. It is **not** in the
  removal list and it **does** ship (row 3). Safe.
- `audioplayers_android` — its merged manifest
  (`build/audioplayers_android/intermediates/merged_manifest/debug/.../AndroidManifest.xml`)
  declares **no permissions at all** (only `uses-sdk minSdkVersion=19`). Nothing
  for us to preserve.
- Note `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`: `play-services-location:19.0.0`
  is on the classpath (pulled in transitively) but its manifest declares no
  location permissions, so the removals are still no-ops. If a future dependency
  bump starts injecting location permissions, these two lines would become
  load-bearing — but today they are not.

### Recommendation (not yet applied)

Delete all 13 `tools:node="remove"` lines from
`android/app/src/main/AndroidManifest.xml`, leaving only the `INTERNET`
declaration. Rationale:

- The launch plan explicitly forbids blanket `tools:node="remove"`; each removal
  must be justified, and none of these can be.
- They are pure noise: 13 warnings per build, and they give a false sense that
  the manifest is being actively defended.
- They are a future footgun: `tools:node="remove"` silently strips a permission a
  dependency genuinely starts needing after a version bump, producing a runtime
  failure with no build error.

If defence-in-depth against a careless plugin addition is still wanted, the
correct mechanism is this audit re-run in CI (fail the build if the merged
permission set differs from a checked-in golden list), not blanket removals.

**This audit does not apply that deletion** — it is a recommendation for the
manifest owner.

## 5. `<queries>` findings

The merged `<queries>` block (debug manifest lines 23–76) contains:

From our own manifest:
- `PROCESS_TEXT` + `text/plain` — Flutter engine's `ProcessTextPlugin`. Standard.
- `SENDTO` + `mailto:` — support/feedback email links. Justified by `url_launcher`.
- `VIEW` + `https` — privacy policy / store links. Justified by `url_launcher`.

Injected by dependencies:
- `<package android:name="com.google.android.gms" />` and
  `<package android:name="com.android.vending" />` — GMS / Play Store visibility.
- `com.android.vending.billing.InAppBillingService.BIND` and
  `com.google.android.apps.play.billingtestcompanion.BillingOverrideService.BIND`
  — Play Billing (billing:8.3.0).
- `android.support.customtabs.action.CustomTabsService` — Custom Tabs, used by
  `url_launcher_android` / webview.
- `INSERT` + `vnd.android.cursor.dir/event` (calendar), `VIEW` + `sms:`,
  `DIAL` + `tel:` — injected by `url_launcher_android`, which supports those
  schemes generically. Harmless (queries only declare *visibility*, not
  capability), but worth knowing they are not ours.

Nothing here is a policy concern. `<queries>` entries do not require a Play
Console declaration (unlike `QUERY_ALL_PACKAGES`, which is **not** present).

## 6. Exported components

`android:exported="true"` in the merged manifest:

| Component | Source | Assessment |
| --- | --- | --- |
| `com.adbkv.chainpop.MainActivity` | Ours | Correct — it has the LAUNCHER intent filter, so it must be exported. |
| `com.google.android.gms.games.internal.v2.resolution.GamesResolutionActivity` | `play-services-games-v2:21.0.0` | Standard Play Games sign-in resolution activity. Expected. |
| `com.google.android.gms.games.internal.v2.appshortcuts.PlayGamesAppShortcutsActivity` | `play-services-games-v2:21.0.0` | Standard. Expected. |
| `com.amazon.device.iap.ResponseReceiver` | `com.revenuecat.purchases:purchases-store-amazon:10.5.0` | **Noted:** RevenueCat pulls its Amazon Appstore module in transitively even though we only ship to Google Play. The receiver is inert without the Amazon Appstore installed. Not a security issue, but it is dead weight; consider excluding `purchases-store-amazon` from the `purchases_flutter` dependency if APK size matters. |
| `androidx.work.impl.background.systemalarm.SystemAlarmService` / `systemjob.SystemJobService` | `androidx.work:work-runtime:2.7.0` | Standard WorkManager services; `SystemJobService` must be exported for the platform JobScheduler to bind. Expected. |

Every other component in the merged manifest is `android:exported="false"`.
No `<provider>` is exported. No unexpected app-owned exported surface.

## 7. Build-type AdMob app id (verified in this pass)

The AdMob application id is now set per build type in
`android/app/build.gradle.kts`, so debug builds no longer report sample ad unit
traffic against the production AdMob app id:

| Variant | `com.google.android.gms.ads.APPLICATION_ID` in merged manifest |
| --- | --- |
| debug | `ca-app-pub-3940256099942544~3347511713` (Google sample app id) |
| release | `ca-app-pub-6510329237083952~7569862231` (production) |

An explicit `ADMOB_ANDROID_APPLICATION_ID` env var or
`admob.android.application.id` in `local.properties` still overrides both.

## 8. SDK levels

`compileSdk = 36`, `targetSdk = 36`, `minSdk = 24` (from Flutter). Confirmed in
the merged manifest's `<uses-sdk android:minSdkVersion="24"
android:targetSdkVersion="36" />`. Meets the current Play target-API requirement.

## 9. Summary for the launch gate

- 12 permissions ship; every one is attributable to a dependency we intentionally
  use. No surprise permission.
- `AD_ID` ships → Data Safety form must say **Yes** to Advertising ID.
- `QUERY_ALL_PACKAGES` is absent; no sensitive/high-risk permission is present.
- All 13 `tools:node="remove"` lines are no-ops and are recommended for deletion.
  None of them strips anything a dependency needs.
- No unexpected exported components.
