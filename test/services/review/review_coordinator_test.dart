import 'dart:io';

import 'package:chain_pop/services/analytics/no_op_analytics_service.dart';
import 'package:chain_pop/services/review/review_coordinator.dart';
import 'package:chain_pop/services/storage/hive_chain_pop_persistence.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:in_app_review/in_app_review.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveChainPopPersistence persistence;
  late NoOpAnalyticsService analytics;
  late ReviewCoordinator coordinator;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('review_coord_test_');
    Hive.init(tempDir.path);
    persistence = HiveChainPopPersistence();
    await persistence.open();
    StorageService.installForTesting(persistence);
  });

  setUp(() async {
    await persistence.clearProgress();
    analytics = NoOpAnalyticsService();
    coordinator = ReviewCoordinator(
      persistence: persistence,
      analytics: analytics,
      inAppReview: InAppReview.instance,
    );
  });

  tearDownAll(() async {
    StorageService.uninstallForTesting();
  });

  group('ReviewCoordinator Eligibility Rules', () {
    test('suppressed when reviewPromptPermanentlyDisabled is true', () async {
      await persistence.setReviewPromptPermanentlyDisabled(true);

      final eligible = coordinator.shouldShowPrompt(
        level: 15,
        stars: 3,
        isWin: true,
        isDailyChallenge: false,
        isTutorial: false,
        winStreak: 3,
        isInterstitialDue: false,
      );
      expect(eligible, isFalse);
    });

    test('suppressed for daily challenge and tutorial', () {
      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: true,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: false,
        ),
        isFalse,
      );

      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: true,
          winStreak: 3,
          isInterstitialDue: false,
        ),
        isFalse,
      );
    });

    test('suppressed on level loss', () {
      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 0,
          isWin: false,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 0,
          isInterstitialDue: false,
        ),
        isFalse,
      );
    });

    test('suppressed when not a positive moment (stars < 3 and winStreak < 2)',
        () async {
      for (var i = 0; i < 20; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }
      for (var i = 0; i < 5; i++) {
        await persistence.incrementSessionCount();
      }
      await persistence.accumulateLifetimeGameplaySeconds(1500);

      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 1,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 0,
          isInterstitialDue: false,
        ),
        isFalse,
      );
    });

    test('suppressed when interstitial ad is due', () async {
      for (var i = 0; i < 20; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }
      for (var i = 0; i < 5; i++) {
        await persistence.incrementSessionCount();
      }
      await persistence.accumulateLifetimeGameplaySeconds(1500);

      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: true,
        ),
        isFalse,
      );
    });

    test('suppressed when campaign clears < 15', () async {
      for (var i = 0; i < 14; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }
      for (var i = 0; i < 5; i++) {
        await persistence.incrementSessionCount();
      }
      await persistence.accumulateLifetimeGameplaySeconds(1500);

      expect(
        coordinator.shouldShowPrompt(
          level: 14,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: false,
        ),
        isFalse,
      );
    });

    test('suppressed when session count < 3', () async {
      for (var i = 0; i < 20; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }
      await persistence.incrementSessionCount();
      await persistence.incrementSessionCount(); // only 2 sessions
      await persistence.accumulateLifetimeGameplaySeconds(1500);

      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: false,
        ),
        isFalse,
      );
    });

    test('suppressed when gameplay seconds < 1200', () async {
      for (var i = 0; i < 20; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }
      for (var i = 0; i < 5; i++) {
        await persistence.incrementSessionCount();
      }
      await persistence.accumulateLifetimeGameplaySeconds(1100);

      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: false,
        ),
        isFalse,
      );
    });

    test('eligible when all engagement conditions are satisfied', () async {
      for (var i = 0; i < 15; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }
      for (var i = 0; i < 3; i++) {
        await persistence.incrementSessionCount();
      }
      await persistence.accumulateLifetimeGameplaySeconds(1200);

      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 1,
          isInterstitialDue: false,
        ),
        isTrue,
      );
    });
  });

  group('ReviewCoordinator Cooldowns & Actions', () {
    setUp(() async {
      for (var i = 0; i < 15; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }
      for (var i = 0; i < 3; i++) {
        await persistence.incrementSessionCount();
      }
      await persistence.accumulateLifetimeGameplaySeconds(1200);
    });

    test('Later action enforces 14-day and 15-level cooldown', () async {
      final baseTime = DateTime(2026, 1, 1, 12, 0);
      await coordinator.onLaterTapped(level: 15, nowOverride: baseTime);

      expect(persistence.reviewLastPromptLevelClears, 15);
      expect(
          persistence.reviewLastPromptEpochMs, baseTime.millisecondsSinceEpoch);

      // 1 day later, 0 extra clears -> false
      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 1,
          isInterstitialDue: false,
          nowOverride: baseTime.add(const Duration(days: 1)),
        ),
        isFalse,
      );

      // 15 days later, but no extra clears -> false
      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 1,
          isInterstitialDue: false,
          nowOverride: baseTime.add(const Duration(days: 15)),
        ),
        isFalse,
      );

      // 15 days later AND 15 additional clears -> true
      for (var i = 0; i < 15; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }
      expect(
        coordinator.shouldShowPrompt(
          level: 30,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 1,
          isInterstitialDue: false,
          nowOverride: baseTime.add(const Duration(days: 15)),
        ),
        isTrue,
      );
    });

    test('Never action permanently disables review prompts', () async {
      await coordinator.onNeverTapped(level: 15);

      expect(persistence.reviewPromptPermanentlyDisabled, isTrue);
      expect(
        coordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: false,
        ),
        isFalse,
      );
    });

    test('Never holds even when the cooldown debug knobs are zeroed', () async {
      final debugCoordinator = ReviewCoordinator(
        persistence: persistence,
        analytics: analytics,
        inAppReview: InAppReview.instance,
        cooldownDays: 0,
        cooldownClears: 0,
      );
      await debugCoordinator.onNeverTapped(level: 15);

      expect(
        debugCoordinator.shouldShowPrompt(
          level: 15,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: false,
        ),
        isFalse,
      );
    });

    test('player who tapped Rate is never prompted again', () async {
      final baseTime = DateTime(2026, 1, 1, 12, 0);
      await persistence.setReviewHasEverTappedRate(true);
      await persistence
          .setReviewLastPromptEpochMs(baseTime.millisecondsSinceEpoch);
      await persistence.setReviewLastPromptLevelClears(15);
      for (var i = 0; i < 15; i++) {
        await persistence.incrementLifetimeCampaignClears();
      }

      // Both cooldowns have elapsed; the rated flag alone blocks it.
      expect(
        coordinator.shouldShowPrompt(
          level: 30,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: false,
          nowOverride: baseTime.add(const Duration(days: 60)),
        ),
        isFalse,
      );
    });

    test('Annual quota limit (<= 3 per year) blocks 4th prompt', () async {
      final baseTime = DateTime(2026, 1, 1, 12, 0);
      await persistence
          .recordReviewPromptPresentation(baseTime.millisecondsSinceEpoch);
      await persistence.recordReviewPromptPresentation(
          baseTime.add(const Duration(days: 30)).millisecondsSinceEpoch);
      await persistence.recordReviewPromptPresentation(
          baseTime.add(const Duration(days: 60)).millisecondsSinceEpoch);

      // 3 prompts already recorded in the last year
      expect(
        coordinator.shouldShowPrompt(
          level: 50,
          stars: 3,
          isWin: true,
          isDailyChallenge: false,
          isTutorial: false,
          winStreak: 3,
          isInterstitialDue: false,
          nowOverride: baseTime.add(const Duration(days: 90)),
        ),
        isFalse,
      );
    });
  });
}
