import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../subscription/subscription_locator.dart';
import 'ad_service.dart';

/// Wraps an [AdService] and intercepts calls if the user is premium.
///
/// For premium users:
/// - Rewarded ads are considered instantly "ready" and "shown successfully" (to unblock gameplay features).
/// - Interstitials and banners are bypassed.
/// - Inner service initialization is bypassed.
class PremiumAdServiceDecorator implements AdService {
  final AdService _inner;
  bool _wasPremium = false;

  /// The listenable we actually subscribed to, so [dispose] unsubscribes from
  /// the same object even if the locator is later reinstalled.
  ValueListenable<bool>? _premiumListenable;

  PremiumAdServiceDecorator(this._inner) {
    final sub = SubscriptionLocator.instanceOrNull;
    if (sub != null) {
      _wasPremium = sub.isPremium.value;
      _premiumListenable = sub.isPremium;
      sub.isPremium.addListener(_onPremiumChanged);
    }
  }

  void _onPremiumChanged() {
    final isNowPremium = _isPremium;
    if (_wasPremium == false && isNowPremium == true) {
      disposeLoadedAds();
    } else if (_wasPremium == true && isNowPremium == false) {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        MobileAds.instance.initialize();
      }
      _inner.bootstrap();
    }
    _wasPremium = isNowPremium;
  }

  bool get _isPremium => SubscriptionLocator.instanceOrNull?.isPremium.value ?? false;

  @override
  Future<void> bootstrap() async {
    if (_isPremium) {
      return; // Skip inner bootstrap entirely to save traffic/memory.
    }
    return _inner.bootstrap();
  }

  @override
  void setInventoryListener(void Function()? onChanged) {
    // Inventory listeners belong to the inner service only. Premium-state
    // changes are surfaced separately: this decorator listens to
    // SubscriptionService.isPremium itself (see [_onPremiumChanged]) and UI
    // that must react in place (e.g. the game screen banner) watches that same
    // listenable directly.
    _inner.setInventoryListener(onChanged);
  }

  @override
  void clearInventoryListenerIfSame(void Function()? listener) {
    _inner.clearInventoryListenerIfSame(listener);
  }

  @override
  bool isRewardedReady(String placement) {
    if (_isPremium) {
      // Premium users can always access rewarded features (undo, hint, continue, daily unlock)
      return true;
    }
    return _inner.isRewardedReady(placement);
  }

  @override
  Future<void> preloadRewarded(String placement) async {
    if (_isPremium) return;
    return _inner.preloadRewarded(placement);
  }

  @override
  Future<void> preloadInterstitial() async {
    if (_isPremium) return;
    return _inner.preloadInterstitial();
  }

  @override
  Future<bool> showRewarded({required String placement}) async {
    if (_isPremium) {
      // Premium users instantly "earn" the reward without watching an ad.
      // Use microtask to ensure callers have mounted correctly if they rely on async gaps.
      return Future.microtask(() => true);
    }
    return _inner.showRewarded(placement: placement);
  }

  @override
  Future<bool> showInterstitialIfReady({required String placement}) async {
    if (_isPremium) {
      // No interstitial shown. Return false because no ad was presented.
      return false;
    }
    return _inner.showInterstitialIfReady(placement: placement);
  }

  @override
  Widget buildDailyChallengeBanner(BuildContext context) {
    if (_isPremium) {
      return const SizedBox.shrink();
    }
    return _inner.buildDailyChallengeBanner(context);
  }

  @override
  Widget buildGamePauseBanner(BuildContext context) {
    if (_isPremium) {
      return const SizedBox.shrink();
    }
    return _inner.buildGamePauseBanner(context);
  }

  @override
  Widget buildGameScreenBanner(BuildContext context) {
    if (_isPremium) {
      return const SizedBox.shrink();
    }
    return _inner.buildGameScreenBanner(context);
  }

  @override
  void disposeLoadedAds() {
    _inner.disposeLoadedAds();
  }

  /// Detaches the premium listener installed in the constructor.
  ///
  /// Deliberately **not** part of the [AdService] interface: that interface has
  /// no default implementations, so adding `dispose()` there would force
  /// empty overrides on every implementation (real, no-op, and test doubles)
  /// for a leak that cannot occur in production — the decorator is installed
  /// once into [AdsLocator] and lives for the whole process. This exists for
  /// tests and for any future code that rebuilds the ad stack at runtime.
  void dispose() {
    _premiumListenable?.removeListener(_onPremiumChanged);
    _premiumListenable = null;
  }
}
