import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../crash_reporting.dart';
import 'ad_debug_log.dart';
import 'admob_config.dart';
import 'ad_placements.dart';
import 'ad_service.dart';
import 'daily_challenge_banner_slot.dart';

void _logAdMobError(String context, Object error, [StackTrace? st]) {
  developer.log(
    '$context: $error',
    name: 'ChainPop.Ads',
    error: error,
    stackTrace: st,
  );
}

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
    adDebug(
      'bootstrap: preloads only (UMP + MobileAds.initialize in main). '
      'App id (log ref): ${admobAppIdMetaForLogs()} sampleUnits=$kAdmobUseSampleUnits',
    );
    adDebug(
      'bootstrap: compiled units (${defaultTargetPlatform.name}) '
      'rewarded=${_rewardedUnitId()} interstitial=${_interstitialUnitId()} '
      'banner=${_bannerUnitId()}',
    );
    adDebug('bootstrap: scheduling rewarded + interstitial preloads');
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
    if (_rewardedByPlacement[placement] != null) {
      adDebug('preloadRewarded($placement): already loaded');
      return;
    }
    if (_rewardedLoadsInFlight.containsKey(placement)) {
      adDebug('preloadRewarded($placement): awaiting in-flight load');
      return _rewardedLoadsInFlight[placement]!.future;
    }
    final c = Completer<void>();
    _rewardedLoadsInFlight[placement] = c;
    adDebug('preloadRewarded($placement): load() unit=${_rewardedUnitId()}');

    RewardedAd.load(
      adUnitId: _rewardedUnitId(),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          adDebug('preloadRewarded($placement): onAdLoaded');
          _rewardedByPlacement[placement] = ad;
          _rewardedLoadsInFlight.remove(placement);
          if (!c.isCompleted) c.complete();
          _notifyInventory();
        },
        onAdFailedToLoad: (error) {
          adDebug('preloadRewarded($placement): onAdFailedToLoad $error');
          _rewardedLoadsInFlight.remove(placement);
          if (!c.isCompleted) c.completeError(error);
          _notifyInventory();
          _logAdMobError('Rewarded load failed ($placement)', error);
        },
      ),
    );

    try {
      await c.future;
    } catch (e, st) {
      adDebug('preloadRewarded($placement): await failed $e');
      _logAdMobError('Rewarded preload failed ($placement)', e, st);
      recordNonFatal(e, st);
    }
  }

  @override
  Future<void> preloadInterstitial() => _loadInterstitial();

  Future<void> _loadInterstitial() async {
    if (_interstitial != null) {
      adDebug('preloadInterstitial: already loaded');
      return;
    }
    final inflight = _interstitialLoadInFlight;
    if (inflight != null) {
      adDebug('preloadInterstitial: awaiting in-flight load');
      return inflight.future;
    }

    final c = Completer<void>();
    _interstitialLoadInFlight = c;
    adDebug('preloadInterstitial: load() unit=${_interstitialUnitId()}');
    InterstitialAd.load(
      adUnitId: _interstitialUnitId(),
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          adDebug('preloadInterstitial: onAdLoaded');
          _interstitial = ad;
          _interstitialLoadInFlight = null;
          if (!c.isCompleted) c.complete();
          // Interstitial readiness is not surfaced in HUD; skipping notify avoids
          // redundant rebuilds / flicker during dismiss → preload → navigation.
        },
        onAdFailedToLoad: (error) {
          adDebug('preloadInterstitial: onAdFailedToLoad $error');
          _interstitial = null;
          _interstitialLoadInFlight = null;
          if (!c.isCompleted) c.completeError(error);
          _logAdMobError('Interstitial load failed', error);
        },
      ),
    );
    try {
      await c.future;
    } catch (e, st) {
      adDebug('preloadInterstitial: await failed $e');
      _logAdMobError('Interstitial preload failed', e, st);
      recordNonFatal(e, st);
    }
  }

  @override
  Future<bool> showRewarded({required String placement}) async {
    adDebug(
      'showRewarded($placement): pre-show ready=${isRewardedReady(placement)}',
    );
    await preloadRewarded(placement);
    final ad = _rewardedByPlacement.remove(placement);
    _notifyInventory();
    if (ad == null) {
      adDebug('showRewarded($placement): no ad after preload');
      return false;
    }

    final done = Completer<bool>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {
        adDebug('showRewarded($placement): onAdShowedFullScreenContent');
      },
      onAdDismissedFullScreenContent: (shownAd) {
        shownAd.dispose();
        adDebug('showRewarded($placement): dismissed earned=$earned');
        if (!done.isCompleted) done.complete(earned);
        unawaited(preloadRewarded(placement));
      },
      onAdFailedToShowFullScreenContent: (shownAd, error) {
        shownAd.dispose();
        adDebug('showRewarded($placement): onAdFailedToShow $error');
        if (!done.isCompleted) done.complete(false);
        _logAdMobError('Rewarded show failed ($placement)', error);
        unawaited(preloadRewarded(placement));
      },
    );

    await ad.show(
      onUserEarnedReward: (_, __) {
        earned = true;
        adDebug('showRewarded($placement): onUserEarnedReward');
      },
    );

    final result = await done.future;
    adDebug('showRewarded($placement): completed result=$result');
    return result;
  }

  @override
  Future<bool> showInterstitialIfReady({required String placement}) async {
    adDebug('showInterstitialIfReady(placement=$placement): invoked');
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
      adDebug(
        'showInterstitial: skipped (cooldown '
        '${DateTime.now().difference(last).inSeconds}s / '
        '${_interstitialCooldown.inSeconds}s)',
      );
      return false;
    }

    var ad = _interstitial;
    if (ad == null) {
      adDebug('showInterstitial: loading before show');
      await _loadInterstitial();
      ad = _interstitial;
    }
    if (ad == null) {
      adDebug('showInterstitial: no ad available');
      return false;
    }

    adDebug('showInterstitial: presenting');
    _interstitial = null;
    final done = Completer<bool>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (shownAd) {
        _lastInterstitialShownAt = DateTime.now();
        shownAd.dispose();
        adDebug('showInterstitial: dismissed (shown)');
        if (!done.isCompleted) done.complete(true);
        unawaited(_loadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        failedAd.dispose();
        adDebug('showInterstitial: onAdFailedToShow $error');
        if (!done.isCompleted) done.complete(false);
        _logAdMobError('Interstitial show failed', error);
        unawaited(_loadInterstitial());
      },
    );

    await ad.show();
    final out = await done.future;
    adDebug('showInterstitial: completed result=$out');
    return out;
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
