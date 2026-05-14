import 'package:flutter/foundation.dart';

import '../daily_challenge_play_policy.dart';
import 'ad_placements.dart';
import 'ad_service.dart';
import 'ads_locator.dart';
import 'google_mobile_ad_service.dart';
import 'no_op_ad_service.dart';

/// Builds the production [AdService] for the current embedder.
///
/// Returns [NoOpAdService] on web, desktop, or when `MOCK_ADS=true` is passed
/// as a `--dart-define`. Widget / unit tests use [AdsLocator]'s default
/// [NoOpAdService] unless the test calls [AdsLocator.install].
AdService createDefaultAdService() {
  if (kIsWeb) {
    return NoOpAdService();
  }
  const mockAds = bool.fromEnvironment('MOCK_ADS', defaultValue: false);
  if (mockAds) return NoOpAdService();

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return GoogleMobileAdService();
    default:
      return NoOpAdService();
  }
}

/// Daily calendar policy: rewarded unlock for replay on mobile; free-today-only elsewhere.
DailyChallengePlayPolicy createDailyChallengePlayPolicy() {
  if (kIsWeb) return DailyChallengePlayPolicy.standard;
  const mockAds = bool.fromEnvironment('MOCK_ADS', defaultValue: false);
  if (mockAds) return DailyChallengePlayPolicy.standard;

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return DailyChallengePlayPolicy(
        showRewardedAd: () => AdsLocator.instance.showRewarded(
          placement: AdPlacements.dailyUnlockPast,
        ),
      );
    default:
      return DailyChallengePlayPolicy.standard;
  }
}
