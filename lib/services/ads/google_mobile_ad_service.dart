import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_placements.dart';
import 'ad_service.dart';
import 'daily_challenge_banner_slot.dart';

/// Sample AdMob **application** IDs from Google's docs (debug / CI safe).
///
/// Production: replace manifest / Info.plist entries with your real app IDs.
const String androidSampleAppIdMeta =
    'ca-app-pub-3940256099942544~3347511713'; // Example App ID (Android)
const String iosSampleAppIdMeta =
    'ca-app-pub-3940256099942544~1458002511'; // Example App ID (iOS)

/// Sample **rewarded** units — override via `--dart-define` for production.
///
/// Android test rewarded: `ca-app-pub-3940256099942544/5224354917`
/// iOS test rewarded: `ca-app-pub-3940256099942544/1712485313`
const String rewardedAndroidUnit = String.fromEnvironment(
  'ADMOB_REWARDED_ANDROID',
  defaultValue: 'ca-app-pub-3940256099942544/5224354917',
);
const String rewardedIosUnit = String.fromEnvironment(
  'ADMOB_REWARDED_IOS',
  defaultValue: 'ca-app-pub-3940256099942544/1712485313',
);

/// Sample **interstitial** units — override via `--dart-define` for production.
///
/// Android test interstitial: `ca-app-pub-3940256099942544/1033173712`
/// iOS test interstitial: `ca-app-pub-3940256099942544/4411468910`
const String interstitialAndroidUnit = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_ANDROID',
  defaultValue: 'ca-app-pub-3940256099942544/1033173712',
);
const String interstitialIosUnit = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_IOS',
  defaultValue: 'ca-app-pub-3940256099942544/4411468910',
);

/// Sample **banner** units — override via `--dart-define` for production.
///
/// **Android fallback:** Google's sample banner unit (`ca-app-pub-3940256099942544/6300978111`)
/// when `--dart-define=ADMOB_BANNER_ANDROID` is not set.
///
/// **iOS fallback:** sample banner when `--dart-define=ADMOB_BANNER_IOS` is not set.
const String bannerAndroidUnit = String.fromEnvironment(
  'ADMOB_BANNER_ANDROID',
  defaultValue: 'ca-app-pub-3940256099942544/6300978111',
);
const String bannerIosUnit = String.fromEnvironment(
  'ADMOB_BANNER_IOS',
  defaultValue: 'ca-app-pub-3940256099942544/2934735716',
);

String _rewardedUnitId() => defaultTargetPlatform == TargetPlatform.iOS
    ? rewardedIosUnit
    : rewardedAndroidUnit;

String _interstitialUnitId() => defaultTargetPlatform == TargetPlatform.iOS
    ? interstitialIosUnit
    : interstitialAndroidUnit;

String _bannerUnitId() => defaultTargetPlatform == TargetPlatform.iOS
    ? bannerIosUnit
    : bannerAndroidUnit;

/// Live [AdService] using Google Mobile Ads (Android + iOS).
final class GoogleMobileAdService implements AdService {
  GoogleMobileAdService();

  static Duration get _interstitialCooldown =>
      kDebugMode ? const Duration(seconds: 60) : const Duration(minutes: 5);

  static DateTime? _lastInterstitialShownAt;

  final Map<String, RewardedAd?> _rewardedByPlacement = {};
  final Map<String, Completer<void>> _rewardedLoadsInFlight = {};

  InterstitialAd? _interstitial;

  Future<bool>? _interstitialShowInFlight;

  Completer<void>? _interstitialLoadInFlight;

  void Function()? _inventoryListener;

  bool _bootstrapped = false;

  void _notifyInventory() => _inventoryListener?.call();

  @override
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    await MobileAds.instance.initialize();
    if (kDebugMode) {
      debugPrint(
        'AdMob bootstrap (sample IDs). App meta Android: $androidSampleAppIdMeta '
        'iOS: $iosSampleAppIdMeta',
      );
    }
    unawaited(preloadRewarded(AdPlacements.continueAfterLives));
    unawaited(preloadRewarded(AdPlacements.undo));
    unawaited(preloadRewarded(AdPlacements.hint));
    unawaited(preloadRewarded(AdPlacements.dailyUnlockPast));
    unawaited(_loadInterstitial());
  }

  @override
  void setInventoryListener(void Function()? onChanged) {
    _inventoryListener = onChanged;
  }

  @override
  void clearInventoryListenerIfSame(void Function()? listener) {
    if (identical(_inventoryListener, listener)) _inventoryListener = null;
  }

  @override
  bool isRewardedReady(String placement) =>
      _rewardedByPlacement[placement] != null;

  @override
  Future<void> preloadRewarded(String placement) async {
    if (_rewardedByPlacement[placement] != null) return;
    if (_rewardedLoadsInFlight.containsKey(placement)) {
      return _rewardedLoadsInFlight[placement]!.future;
    }
    final c = Completer<void>();
    _rewardedLoadsInFlight[placement] = c;

    RewardedAd.load(
      adUnitId: _rewardedUnitId(),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedByPlacement[placement] = ad;
          _rewardedLoadsInFlight.remove(placement);
          if (!c.isCompleted) c.complete();
          _notifyInventory();
        },
        onAdFailedToLoad: (error) {
          _rewardedLoadsInFlight.remove(placement);
          if (!c.isCompleted) c.completeError(error);
          _notifyInventory();
          debugPrint('Rewarded load failed ($placement): $error');
        },
      ),
    );

    try {
      await c.future;
    } catch (_) {
      /* preload best-effort */
    }
  }

  @override
  Future<void> preloadInterstitial() => _loadInterstitial();

  Future<void> _loadInterstitial() async {
    if (_interstitial != null) return;
    final inflight = _interstitialLoadInFlight;
    if (inflight != null) return inflight.future;

    final c = Completer<void>();
    _interstitialLoadInFlight = c;
    InterstitialAd.load(
      adUnitId: _interstitialUnitId(),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _interstitialLoadInFlight = null;
          if (!c.isCompleted) c.complete();
          // Interstitial readiness is not surfaced in HUD; skipping notify avoids
          // redundant rebuilds / flicker during dismiss → preload → navigation.
        },
        onAdFailedToLoad: (error) {
          _interstitial = null;
          _interstitialLoadInFlight = null;
          if (!c.isCompleted) c.completeError(error);
          debugPrint('Interstitial load failed: $error');
        },
      ),
    );
    try {
      await c.future;
    } catch (_) {
      /* preload best-effort */
    }
  }

  @override
  Future<bool> showRewarded({required String placement}) async {
    await preloadRewarded(placement);
    final ad = _rewardedByPlacement.remove(placement);
    _notifyInventory();
    if (ad == null) return false;

    final done = Completer<bool>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {},
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        if (!done.isCompleted) done.complete(earned);
        unawaited(preloadRewarded(placement));
      },
      onAdFailedToShowFullScreenContent: (shownAd, error) {
        shownAd.dispose();
        if (!done.isCompleted) done.complete(false);
        debugPrint('Rewarded show failed: $error');
        unawaited(preloadRewarded(placement));
      },
    );

    await ad.show(
      onUserEarnedReward: (_, __) {
        earned = true;
      },
    );

    return done.future;
  }

  @override
  Future<bool> showInterstitialIfReady({required String placement}) async {
    final inflight = _interstitialShowInFlight;
    if (inflight != null) return inflight;

    final run = _showInterstitialBody();
    _interstitialShowInFlight = run;
    try {
      return await run;
    } finally {
      if (identical(_interstitialShowInFlight, run)) {
        _interstitialShowInFlight = null;
      }
    }
  }

  Future<bool> _showInterstitialBody() async {
    final last = _lastInterstitialShownAt;
    if (last != null &&
        DateTime.now().difference(last) < _interstitialCooldown) {
      return false;
    }

    var ad = _interstitial;
    if (ad == null) {
      await _loadInterstitial();
      ad = _interstitial;
    }
    if (ad == null) return false;

    _interstitial = null;
    final done = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shownAd) {
        _lastInterstitialShownAt = DateTime.now();
        shownAd.dispose();
        if (!done.isCompleted) done.complete(true);
        unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        failedAd.dispose();
        if (!done.isCompleted) done.complete(false);
        debugPrint('Interstitial show failed: $error');
        unawaited(_loadInterstitial());
      },
    );

    await ad.show();
    return done.future;
  }

  @override
  Widget buildDailyChallengeBanner(BuildContext context) =>
      DailyChallengeBannerSlot(
        adUnitId: _bannerUnitId(),
        debugPlacementTag: AdPlacements.dailyChallengeCalendarBanner,
      );

  @override
  Widget buildGamePauseBanner(BuildContext context) => DailyChallengeBannerSlot(
        adUnitId: _bannerUnitId(),
        debugPlacementTag: AdPlacements.gamePauseBanner,
        fadeInDuration: const Duration(milliseconds: 320),
      );
}
