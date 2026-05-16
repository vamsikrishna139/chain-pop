import 'package:flutter/foundation.dart';

/// Production AdMob **application** IDs (must match AndroidManifest / Info.plist).
const String admobProductionAppIdAndroid =
    'ca-app-pub-4216543114907932~4253667866';
const String admobProductionAppIdIos =
    'ca-app-pub-4216543114907932~4253667866';

/// Google demo application IDs (fallback when [kAdmobUseSampleUnits] is true).
const String admobSampleAppIdAndroid =
    'ca-app-pub-3940256099942544~3347511713';
const String admobSampleAppIdIos =
    'ca-app-pub-3940256099942544~1458002511';

/// Set `--dart-define=ADMOB_USE_SAMPLE_UNITS=true` to use Google’s demo ad **units**
/// (labeled “Test ad”). Otherwise uses your production unit IDs below.
///
/// When using sample **units**, also set the **app id** to the demo id in
/// `android/local.properties` (`admob.android.application.id=…`) and
/// iOS `GADApplicationIdentifier`, or builds will mismatch and loads can fail.
const bool kAdmobUseSampleUnits = bool.fromEnvironment(
  'ADMOB_USE_SAMPLE_UNITS',
  defaultValue: false,
);

/// Ad unit IDs: production defaults, or Google samples when [kAdmobUseSampleUnits].
const String rewardedAndroidUnit = String.fromEnvironment(
  'ADMOB_REWARDED_ANDROID',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-4216543114907932/1764067448',
);
const String rewardedIosUnit = String.fromEnvironment(
  'ADMOB_REWARDED_IOS',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-4216543114907932/1764067448',
);

const String interstitialAndroidUnit = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_ANDROID',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-4216543114907932/5390268529',
);
const String interstitialIosUnit = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_IOS',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/4411468910'
      : 'ca-app-pub-4216543114907932/5390268529',
);

const String bannerAndroidUnit = String.fromEnvironment(
  'ADMOB_BANNER_ANDROID',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-4216543114907932/5396190695',
);
const String bannerIosUnit = String.fromEnvironment(
  'ADMOB_BANNER_IOS',
  defaultValue: kAdmobUseSampleUnits
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-4216543114907932/5396190695',
);

/// Reference app id strings for logs (matches active manifest / plist).
String admobAppIdMetaForLogs() {
  const useSample = kAdmobUseSampleUnits;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS =>
      useSample ? admobSampleAppIdIos : admobProductionAppIdIos,
    _ => useSample ? admobSampleAppIdAndroid : admobProductionAppIdAndroid,
  };
}

/// Device ids that receive **test** creatives on production units (from logcat:
/// “Use RequestConfiguration… setTestDeviceIds”).
const List<String> kAdmobTestDeviceIds = <String>[
  'DC579E05100486C86E738D1DA7D9B9FD',
];
