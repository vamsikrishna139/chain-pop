import 'dart:io';

import 'package:chain_pop/game/daily_challenge.dart';
import 'package:chain_pop/services/daily_challenge_play_policy.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyChallengePlayPolicy', () {
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('chain_pop_daily_policy_');
      Hive.init(dir.path);
      await StorageService.init();
    });

    setUp(() async {
      await StorageService.clearProgress();
    });

    test('isInFreeCalendarWindow is today only', () {
      const policy = DailyChallengePlayPolicy.standard;
      final today = DateTime(2026, 5, 13);
      final yesterday = DateTime(2026, 5, 12);
      final tomorrow = DateTime(2026, 5, 14);

      expect(policy.isInFreeCalendarWindow(today, today), isTrue);
      expect(policy.isInFreeCalendarWindow(yesterday, today), isFalse);
      expect(policy.isInFreeCalendarWindow(tomorrow, today), isFalse);
    });

    test('mayBePlayable: past days need unlock or rewarded hook', () {
      const noAds = DailyChallengePlayPolicy.standard;
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);

      expect(noAds.mayBePlayable(today, today), isTrue);
      expect(noAds.mayBePlayable(past, today), isFalse);

      final dayKey = DailyChallenge.dateKeyLocal(past);
      expect(StorageService.isDailyUnlockedViaAd(dayKey), isFalse);
    });

    test('mayBePlayable: ad-unlocked day in storage', () async {
      const noAds = DailyChallengePlayPolicy.standard;
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);
      await StorageService.markDailyUnlockedViaAd(DailyChallenge.dateKeyLocal(past));
      expect(noAds.mayBePlayable(past, today), isTrue);
    });

    test('mayBePlayable: without unlock but policy has showRewardedAd', () {
      final policy = DailyChallengePlayPolicy(showRewardedAd: () async => true);
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);
      expect(policy.mayBePlayable(past, today), isTrue);
    });

    test('needsRewardedUnlockBeforePlay: today and future are false', () {
      final policy = DailyChallengePlayPolicy(showRewardedAd: () async => true);
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);
      expect(policy.needsRewardedUnlockBeforePlay(today, today), isFalse);
      expect(policy.needsRewardedUnlockBeforePlay(DateTime(2026, 5, 20), today), isFalse);
      expect(policy.needsRewardedUnlockBeforePlay(past, today), isTrue);
    });

    test('needsRewardedUnlockBeforePlay: false when already unlocked', () async {
      final policy = DailyChallengePlayPolicy(showRewardedAd: () async => true);
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);
      await StorageService.markDailyUnlockedViaAd(DailyChallenge.dateKeyLocal(past));
      expect(policy.needsRewardedUnlockBeforePlay(past, today), isFalse);
    });

    test('needsRewardedUnlockBeforePlay: false without ad hook', () {
      const policy = DailyChallengePlayPolicy.standard;
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);
      expect(policy.needsRewardedUnlockBeforePlay(past, today), isFalse);
    });

    test('ensureCanStart today returns true without storage or ads', () async {
      const policy = DailyChallengePlayPolicy.standard;
      final today = DateTime(2026, 5, 13);
      expect(await policy.ensureCanStart(today, today), isTrue);
    });

    test('ensureCanStart past day without ads returns false', () async {
      const policy = DailyChallengePlayPolicy.standard;
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);
      expect(await policy.ensureCanStart(past, today), isFalse);
    });

    test('ensureCanStart past day calls ad and persists on success', () async {
      var calls = 0;
      final policy = DailyChallengePlayPolicy(
        showRewardedAd: () async {
          calls++;
          return true;
        },
      );
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);
      final dayKey = DailyChallenge.dateKeyLocal(past);

      expect(await policy.ensureCanStart(past, today), isTrue);
      expect(calls, 1);
      expect(StorageService.isDailyUnlockedViaAd(dayKey), isTrue);

      expect(await policy.ensureCanStart(past, today), isTrue);
      expect(calls, 1);
    });

    test('ensureCanStart past day does not persist when ad not completed', () async {
      final policy = DailyChallengePlayPolicy(
        showRewardedAd: () async => false,
      );
      final today = DateTime(2026, 5, 13);
      final past = DateTime(2026, 5, 10);
      final dayKey = DailyChallenge.dateKeyLocal(past);

      expect(await policy.ensureCanStart(past, today), isFalse);
      expect(StorageService.isDailyUnlockedViaAd(dayKey), isFalse);
    });

    test('ensureCanStart rejects future days', () async {
      final policy = DailyChallengePlayPolicy(
        showRewardedAd: () async => true,
      );
      final today = DateTime(2026, 5, 13);
      final future = DateTime(2026, 5, 20);
      expect(await policy.ensureCanStart(future, today), isFalse);
    });
  });
}
