import 'analytics_service.dart';

class NoOpAnalyticsService implements AnalyticsService {
  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {}
  @override
  Future<void> logAppOpen() async {}
  @override
  Future<void> logSessionStart() async {}
  @override
  Future<void> logSessionEnd() async {}
  @override
  Future<void> logTutorialStart() async {}
  @override
  Future<void> logTutorialComplete() async {}
  @override
  Future<void> logLevelStart({required Map<String, Object> params}) async {}
  @override
  Future<void> logLevelComplete({required Map<String, Object> params}) async {}
  @override
  Future<void> logLevelFail({required Map<String, Object> params}) async {}
  @override
  Future<void> logLevelRetry({required Map<String, Object> params}) async {}
  @override
  Future<void> logLevelAbandon({required Map<String, Object> params}) async {}
  @override
  Future<void> logUndoUsed({required Map<String, Object> params}) async {}
  @override
  Future<void> logHintUsed({required Map<String, Object> params}) async {}
  @override
  Future<void> logRewardedOfferShown({required String placement}) async {}
  @override
  Future<void> logRewardedStarted({required String placement}) async {}
  @override
  Future<void> logRewardedCompleted({required String placement}) async {}
  @override
  Future<void> logRewardedFailed(
      {required String placement, required String error}) async {}
  @override
  Future<void> logInterstitialCandidate({required String placement}) async {}
  @override
  Future<void> logInterstitialShown({required String placement}) async {}
  @override
  Future<void> logInterstitialClosed({required String placement}) async {}
  @override
  Future<void> logPurchaseStarted({required String productId}) async {}
  @override
  Future<void> logPurchaseSuccess({required String productId}) async {}
  @override
  Future<void> logPurchaseFailed(
      {required String productId, required String error}) async {}
  @override
  Future<void> logPremiumRestored() async {}
  @override
  Future<void> logDailyOpen({required String dateStr}) async {}
  @override
  Future<void> logDailyComplete(
      {required String dateStr, required Map<String, Object> params}) async {}
  @override
  Future<void> logAchievementUnlock({required String achievementId}) async {}
}
