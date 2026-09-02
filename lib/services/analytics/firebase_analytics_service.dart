import 'package:firebase_analytics/firebase_analytics.dart';

import 'analytics_service.dart';

class FirebaseAnalyticsService implements AnalyticsService {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    await _analytics.logEvent(name: name, parameters: parameters);
  }

  @override
  Future<void> logAppOpen() => _analytics.logAppOpen();

  @override
  Future<void> logSessionStart() => logEvent('app_session_started');

  @override
  Future<void> logSessionEnd() => logEvent('app_session_ended');

  @override
  Future<void> logTutorialStart() => _analytics.logTutorialBegin();

  @override
  Future<void> logTutorialComplete() => _analytics.logTutorialComplete();

  @override
  Future<void> logLevelStart({required Map<String, Object> params}) =>
      _analytics.logLevelStart(
          levelName: params['levelId']?.toString() ?? 'unknown');

  @override
  Future<void> logLevelComplete({required Map<String, Object> params}) =>
      _analytics.logLevelEnd(
          levelName: params['levelId']?.toString() ?? 'unknown', success: 1);

  @override
  Future<void> logLevelFail({required Map<String, Object> params}) =>
      _analytics.logLevelEnd(
          levelName: params['levelId']?.toString() ?? 'unknown', success: 0);

  @override
  Future<void> logLevelRetry({required Map<String, Object> params}) =>
      logEvent('level_retry', parameters: params);

  @override
  Future<void> logLevelAbandon({required Map<String, Object> params}) =>
      logEvent('level_abandon', parameters: params);

  @override
  Future<void> logUndoUsed({required Map<String, Object> params}) =>
      logEvent('undo_used', parameters: params);

  @override
  Future<void> logHintUsed({required Map<String, Object> params}) =>
      logEvent('hint_used', parameters: params);

  @override
  Future<void> logRewardedOfferShown({required String placement}) =>
      logEvent('rewarded_offer_shown', parameters: {'placement': placement});

  @override
  Future<void> logRewardedStarted({required String placement}) =>
      logEvent('rewarded_started', parameters: {'placement': placement});

  @override
  Future<void> logRewardedCompleted({required String placement}) =>
      logEvent('rewarded_completed', parameters: {'placement': placement});

  @override
  Future<void> logRewardedFailed(
          {required String placement, required String error}) =>
      logEvent('rewarded_failed',
          parameters: {'placement': placement, 'error': error});

  @override
  Future<void> logInterstitialCandidate({required String placement}) =>
      logEvent('interstitial_candidate', parameters: {'placement': placement});

  @override
  Future<void> logInterstitialShown({required String placement}) =>
      logEvent('interstitial_shown', parameters: {'placement': placement});

  @override
  Future<void> logInterstitialClosed({required String placement}) =>
      logEvent('interstitial_closed', parameters: {'placement': placement});

  @override
  Future<void> logPurchaseStarted({required String productId}) =>
      logEvent('purchase_started', parameters: {'productId': productId});

  @override
  Future<void> logPurchaseSuccess({required String productId}) =>
      logEvent('purchase_success', parameters: {'productId': productId});

  @override
  Future<void> logPurchaseFailed(
          {required String productId, required String error}) =>
      logEvent('purchase_failed',
          parameters: {'productId': productId, 'error': error});

  @override
  Future<void> logPremiumRestored() => logEvent('premium_restored');

  @override
  Future<void> logDailyOpen({required String dateStr}) =>
      logEvent('daily_open', parameters: {'date': dateStr});

  @override
  Future<void> logDailyComplete(
          {required String dateStr, required Map<String, Object> params}) =>
      logEvent('daily_complete', parameters: {'date': dateStr, ...params});

  @override
  Future<void> logAchievementUnlock({required String achievementId}) =>
      _analytics.logUnlockAchievement(id: achievementId);
}
