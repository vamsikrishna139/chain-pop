import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

import '../analytics/analytics_locator.dart';
import '../analytics/analytics_service.dart';
import '../storage/chain_pop_persistence.dart';
import '../storage/storage_locator.dart';

/// Central coordinator for in-game review prompt eligibility, pacing, and handling.
///
/// Follows platform compliance rules (Apple Guideline 5.6.1 and Google Play In-App
/// Review API guidelines): zero sentiment gating, no incentives, respect for quotas,
/// and silent failure handling.
class ReviewCoordinator {
  final ChainPopPersistence _persistence;
  final AnalyticsService _analytics;
  final InAppReview _inAppReview;
  final int cooldownDays;
  final int cooldownClears;

  ReviewCoordinator({
    ChainPopPersistence? persistence,
    AnalyticsService? analytics,
    InAppReview? inAppReview,
    this.cooldownDays = const int.fromEnvironment('REVIEW_COOLDOWN_DAYS', defaultValue: 14),
    this.cooldownClears = const int.fromEnvironment('REVIEW_COOLDOWN_CLEARS', defaultValue: 15),
  })  : _persistence = persistence ?? StorageLocator.instance,
        _analytics = analytics ?? AnalyticsLocator.instance,
        _inAppReview = inAppReview ?? InAppReview.instance;

  static const int minCampaignClears = 15;
  static const int minSessionCount = 3;
  static const int minGameplaySeconds = 1200; // 20 minutes
  static const int maxPromptsPerYear = 3;

  /// Evaluates whether the player is currently eligible for an in-game review prompt.
  bool shouldShowPrompt({
    required int level,
    required int stars,
    required bool isWin,
    required bool isDailyChallenge,
    required bool isTutorial,
    required int winStreak,
    required bool isInterstitialDue,
    DateTime? nowOverride,
  }) {
    final now = nowOverride ?? DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    debugPrint(
      'ReviewCoordinator: evaluating level=$level stars=$stars streak=$winStreak '
      'interstitialDue=$isInterstitialDue clears=${_persistence.lifetimeCampaignClears} '
      'sessions=${_persistence.sessionCount} seconds=${_persistence.lifetimeGameplaySeconds} '
      'disabled=${_persistence.reviewPromptPermanentlyDisabled} lastPromptMs=${_persistence.reviewLastPromptEpochMs} '
      'cooldownDays=$cooldownDays cooldownClears=$cooldownClears',
    );

    // 1. Permanent suppression (User tapped "Never")
    if (cooldownDays > 0 && _persistence.reviewPromptPermanentlyDisabled) {
      debugPrint('ReviewCoordinator: rejected - reviewPromptPermanentlyDisabled');
      return false;
    }

    // 2. Mode suppression: only campaign levels are eligible
    if (isDailyChallenge || isTutorial) {
      debugPrint('ReviewCoordinator: rejected - isDailyChallenge/isTutorial');
      return false;
    }

    // 3. Must be an immediate win moment
    if (!isWin) {
      debugPrint('ReviewCoordinator: rejected - not a win');
      return false;
    }

    // 4. Emotional peak: 3 stars or an active win streak of at least 2
    if (stars < 3 && winStreak < 2) {
      debugPrint('ReviewCoordinator: rejected - emotional peak not met (stars=$stars, streak=$winStreak)');
      return false;
    }

    // 5. Interstitial conflict: do not show if an interstitial ad is due
    if (isInterstitialDue) {
      debugPrint('ReviewCoordinator: rejected - interstitialDue');
      return false;
    }

    // 6. Campaign progress depth: Level 15 completed
    if (_persistence.lifetimeCampaignClears < minCampaignClears) {
      debugPrint('ReviewCoordinator: rejected - lifetimeCampaignClears ${_persistence.lifetimeCampaignClears} < $minCampaignClears');
      return false;
    }

    // 7. Session count depth: at least 3 distinct sessions
    if (_persistence.sessionCount < minSessionCount) {
      debugPrint('ReviewCoordinator: rejected - sessionCount ${_persistence.sessionCount} < $minSessionCount');
      return false;
    }

    // 8. Cumulative active playtime: at least 20 minutes
    if (_persistence.lifetimeGameplaySeconds < minGameplaySeconds) {
      debugPrint('ReviewCoordinator: rejected - lifetimeGameplaySeconds ${_persistence.lifetimeGameplaySeconds} < $minGameplaySeconds');
      return false;
    }

    // 9. Annual quota ceiling: <= 3 prompts in rolling 365 days
    const oneYearMs = 365 * 24 * 60 * 60 * 1000;
    final recentPrompts = _persistence.reviewPromptHistoryEpochMs
        .where((ts) => (nowMs - ts) < oneYearMs)
        .length;
    if (cooldownDays > 0 && recentPrompts >= maxPromptsPerYear) {
      debugPrint('ReviewCoordinator: rejected - annual quota exceeded ($recentPrompts >= $maxPromptsPerYear)');
      return false;
    }

    // 10. Cooldown since last prompt
    final lastPromptMs = _persistence.reviewLastPromptEpochMs;
    if (lastPromptMs > 0 && cooldownDays > 0) {
      final cooldownMs = cooldownDays * 24 * 60 * 60 * 1000;
      if ((nowMs - lastPromptMs) < cooldownMs) {
        debugPrint('ReviewCoordinator: rejected - day cooldown not elapsed (${nowMs - lastPromptMs} < $cooldownMs)');
        return false;
      }
    }

    if (lastPromptMs > 0 && cooldownClears > 0) {
      final lastClears = _persistence.reviewLastPromptLevelClears;
      if ((_persistence.lifetimeCampaignClears - lastClears) < cooldownClears) {
        debugPrint('ReviewCoordinator: rejected - clear cooldown not elapsed (${_persistence.lifetimeCampaignClears - lastClears} < $cooldownClears)');
        return false;
      }
    }

    debugPrint('ReviewCoordinator: ALL CHECKS PASSED! Showing prompt!');
    return true;
  }

  /// Called when the soft prompt is displayed to the player.
  Future<void> onPromptShown({required int level}) async {
    final historyCount = _persistence.reviewPromptHistoryEpochMs.length + 1;
    await _analytics.logReviewPromptShown(
      level: level,
      promptCount: historyCount,
    );
  }

  /// Handles player tapping "Rate Chain Pop".
  Future<void> onRateTapped({
    required int level,
    DateTime? nowOverride,
  }) async {
    final nowMs = (nowOverride ?? DateTime.now()).millisecondsSinceEpoch;
    await _persistence.recordReviewPromptPresentation(nowMs);
    await _persistence.setReviewLastPromptEpochMs(nowMs);
    await _persistence
        .setReviewLastPromptLevelClears(_persistence.lifetimeCampaignClears);
    await _persistence.setReviewHasEverTappedRate(true);

    await _analytics.logReviewPromptAction(action: 'rate', level: level);
    await _analytics.logReviewNativeRequested(level: level);

    try {
      if (await _inAppReview.isAvailable()) {
        unawaited(_inAppReview.requestReview());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('InAppReview.requestReview failed: $e');
      }
    }
  }

  /// Handles player tapping "Remind Me Later" or dismissing sheet.
  Future<void> onLaterTapped({
    required int level,
    DateTime? nowOverride,
  }) async {
    final nowMs = (nowOverride ?? DateTime.now()).millisecondsSinceEpoch;
    await _persistence.recordReviewPromptPresentation(nowMs);
    await _persistence.setReviewLastPromptEpochMs(nowMs);
    await _persistence
        .setReviewLastPromptLevelClears(_persistence.lifetimeCampaignClears);

    await _analytics.logReviewPromptAction(action: 'later', level: level);
  }

  /// Handles player tapping "Don't Ask Again (Never)".
  Future<void> onNeverTapped({required int level}) async {
    await _persistence.setReviewPromptPermanentlyDisabled(true);
    await _analytics.logReviewPromptAction(action: 'never', level: level);
  }
}
