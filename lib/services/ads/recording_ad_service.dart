import 'package:flutter/widgets.dart';

import 'ad_service.dart';

/// Observing [AdService] for tests (no SDK). Counts interstitial presentations.
final class RecordingAdService implements AdService {
  RecordingAdService({
    this.interstitialResult = true,
    Future<void> Function()? beforeInterstitialReturns,
  }) : _beforeInterstitialReturns = beforeInterstitialReturns;

  final bool interstitialResult;
  final Future<void> Function()? _beforeInterstitialReturns;

  final List<String> rewardedPreloadPlacements = [];
  int preloadInterstitialCalls = 0;
  int betweenLevelsInterstitialShows = 0;
  final List<String> interstitialPlacements = [];

  @override
  Future<void> bootstrap() async {}

  @override
  void setInventoryListener(void Function()? onChanged) {}

  @override
  void clearInventoryListenerIfSame(void Function()? listener) {}

  @override
  bool isRewardedReady(String placement) => false;

  @override
  Future<void> preloadRewarded(String placement) async {
    rewardedPreloadPlacements.add(placement);
  }

  @override
  Future<void> preloadInterstitial() async {
    preloadInterstitialCalls++;
  }

  @override
  Future<bool> showRewarded({required String placement}) async => false;

  @override
  Future<bool> showInterstitialIfReady({required String placement}) async {
    betweenLevelsInterstitialShows++;
    interstitialPlacements.add(placement);
    final hook = _beforeInterstitialReturns;
    if (hook != null) await hook();
    return interstitialResult;
  }

  @override
  Widget buildDailyChallengeBanner(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildGamePauseBanner(BuildContext context) => const SizedBox.shrink();
}
