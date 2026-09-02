abstract class AnalyticsService {
  Future<void> logEvent(String name, {Map<String, Object>? parameters});

  // Funnel events
  Future<void> logAppOpen();
  Future<void> logSessionStart();
  Future<void> logSessionEnd();

  Future<void> logTutorialStart();
  Future<void> logTutorialComplete();

  Future<void> logLevelStart({required Map<String, Object> params});
  Future<void> logLevelComplete({required Map<String, Object> params});
  Future<void> logLevelFail({required Map<String, Object> params});
  Future<void> logLevelRetry({required Map<String, Object> params});
  Future<void> logLevelAbandon({required Map<String, Object> params});

  Future<void> logUndoUsed({required Map<String, Object> params});
  Future<void> logHintUsed({required Map<String, Object> params});

  Future<void> logRewardedOfferShown({required String placement});
  Future<void> logRewardedStarted({required String placement});
  Future<void> logRewardedCompleted({required String placement});
  Future<void> logRewardedFailed(
      {required String placement, required String error});

  Future<void> logInterstitialCandidate({required String placement});
  Future<void> logInterstitialShown({required String placement});
  Future<void> logInterstitialClosed({required String placement});

  Future<void> logPurchaseStarted({required String productId});
  Future<void> logPurchaseSuccess({required String productId});
  Future<void> logPurchaseFailed(
      {required String productId, required String error});
  Future<void> logPremiumRestored();

  Future<void> logDailyOpen({required String dateStr});
  Future<void> logDailyComplete(
      {required String dateStr, required Map<String, Object> params});

  Future<void> logAchievementUnlock({required String achievementId});
}
