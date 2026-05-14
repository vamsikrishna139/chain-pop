import 'ad_service.dart';
import 'package:flutter/widgets.dart';

/// Test double and fallback when ads are mocked, unsupported, or disabled.
final class NoOpAdService implements AdService {
  void Function()? _listener;

  void _notify() => _listener?.call();

  @override
  Future<void> bootstrap() async {}

  @override
  void setInventoryListener(void Function()? onChanged) {
    _listener = onChanged;
  }

  @override
  void clearInventoryListenerIfSame(void Function()? listener) {
    if (identical(_listener, listener)) _listener = null;
  }

  @override
  bool isRewardedReady(String placement) => false;

  @override
  Future<void> preloadRewarded(String placement) async {
    _notify();
  }

  @override
  Future<void> preloadInterstitial() async {}

  @override
  Future<bool> showRewarded({required String placement}) async => false;

  @override
  Future<bool> showInterstitialIfReady({required String placement}) async =>
      false;

  @override
  Widget buildDailyChallengeBanner(BuildContext context) =>
      const SizedBox.shrink();

  @override
  Widget buildGamePauseBanner(BuildContext context) => const SizedBox.shrink();
}
