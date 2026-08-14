import 'package:flutter/widgets.dart';
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

  PremiumAdServiceDecorator(this._inner);

  bool get _isPremium {
    try {
      return SubscriptionLocator.instance.isPremium.value;
    } catch (_) {
      // If locator fails (e.g., tests), default to false.
      return false;
    }
  }

  @override
  Future<void> bootstrap() async {
    if (_isPremium) {
      return; // Skip inner bootstrap entirely to save traffic/memory.
    }
    return _inner.bootstrap();
  }

  @override
  void setInventoryListener(void Function()? onChanged) {
    // We only attach listeners to the inner service since premium state
    // changes are handled via SubscriptionLocator's own listenable.
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
}
