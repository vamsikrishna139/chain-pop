import 'package:flutter/foundation.dart';

/// Production AdMob **application** ID for **Android** (`AndroidManifest` /
/// `android/app/build.gradle.kts`). There is no iOS production app registered yet.
const String admobProductionAppIdAndroid =
    'ca-app-pub-6510329237083952~7569862231';

/// Google demo **iOS** application ID (`Info.plist` `GADApplicationIdentifier`).
/// Matches official iOS **test** ad units below; replace when you create an iOS app in AdMob.
const String admobIosNativeAppId = 'ca-app-pub-3940256099942544~1458002511';

/// Google demo application IDs (Android) when [kAdmobUseSampleUnits] is true.
const String admobSampleAppIdAndroid =
    'ca-app-pub-3940256099942544~3347511713';

/// Set `--dart-define=ADMOB_USE_SAMPLE_UNITS=true` to use Google’s demo ad **units**
/// on **Android** (“Test ad”). **iOS** always defaults to Google’s official test unit IDs
/// until you pass real units via `ADMOB_*_IOS` defines.
///
/// When using sample **units** on Android, set the **Android** app id to the demo id in
/// `android/local.properties` (`admob.android.application.id=…`), or builds can mismatch.
/// iOS `GADApplicationIdentifier` stays on [admobIosNativeAppId] until release iOS setup.
const bool kAdmobUseSampleUnits = bool.fromEnvironment(
  'ADMOB_USE_SAMPLE_UNITS',
  defaultValue: false,
);

/// Google’s official iOS **test** ad units (safe default until real iOS AdMob units exist).
const String admobIosOfficialTestRewardedUnit =
    'ca-app-pub-3940256099942544/1712485313';
const String admobIosOfficialTestInterstitialUnit =
    'ca-app-pub-3940256099942544/4411468910';
const String admobIosOfficialTestBannerUnit =
    'ca-app-pub-3940256099942544/2934735716';

/// Ad unit IDs: Android production or Google samples; iOS always official test defaults
/// unless overridden with `ADMOB_*_IOS` defines.
const String rewardedAndroidUnit = String.fromEnvironment(
  'ADMOB_REWARDED_ANDROID',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-6510329237083952/7930771570',
);
const String rewardedIosUnit = String.fromEnvironment(
  'ADMOB_REWARDED_IOS',
  defaultValue: admobIosOfficialTestRewardedUnit,
);

const String interstitialAndroidUnit = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_ANDROID',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-6510329237083952/6340541047',
);
const String interstitialIosUnit = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_IOS',
  defaultValue: admobIosOfficialTestInterstitialUnit,
);

const String bannerAndroidUnit = String.fromEnvironment(
  'ADMOB_BANNER_ANDROID',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-6510329237083952/9243853247',
);
const String bannerIosUnit = String.fromEnvironment(
  'ADMOB_BANNER_IOS',
  defaultValue: admobIosOfficialTestBannerUnit,
);

/// Reference app id strings for logs (matches active manifest / plist).
String admobAppIdMetaForLogs() {
  return switch (defaultTargetPlatform) {
    // iOS plist uses [admobIosNativeAppId] until a production iOS AdMob app exists.
    TargetPlatform.iOS => admobIosNativeAppId,
    _ => kAdmobUseSampleUnits ? admobSampleAppIdAndroid : admobProductionAppIdAndroid,
  };
}

/// Device ids that receive **test** creatives on production units (from logcat:
/// “Use RequestConfiguration… setTestDeviceIds”).
const List<String> kAdmobTestDeviceIds = <String>[
  'DC579E05100486C86E738D1DA7D9B9FD',
];
