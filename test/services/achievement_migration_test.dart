import 'dart:io';

import 'package:chain_pop/services/achievements/achievement_counters.dart';
import 'package:chain_pop/services/achievements/day_key.dart';
import 'package:chain_pop/services/storage/hive_chain_pop_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Covers the v2 → v3 schema bump and the calendar helper the streaks rely on.
///
/// The migration only seeds what can be honestly reconstructed. Star totals and
/// Daily completions are recoverable from records that already exist; nodes
/// cleared and the per-mechanic tallies have no history, so they legitimately
/// start at zero rather than being invented.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('chain_pop_mig_test_');
    Hive.init(dir.path);
  });

  Future<HiveChainPopPersistence> openFresh() async {
    final storage = HiveChainPopPersistence();
    await storage.open();
    await storage.clearProgress();
    return storage;
  }

  group('v2 → v3 migration', () {
    test('seeds the star aggregate from existing per-level records', () async {
      final storage = await openFresh();
      final box = storage.boxForTests;

      // Simulate a v2 install: star records present, no aggregate, old marker.
      await box.put('stars_easy_1', 3);
      await box.put('stars_easy_2', 2);
      await box.put('stars_medium_1', 3);
      await box.put('stars_hard_7', 1);
      await box.delete(AchievementCounter.totalStars.storageKey);
      await box.put('_chain_pop_storage_schema', 2);

      await storage.reconcileSchemaMarker();

      expect(storage.achievementCounter(AchievementCounter.totalStars), 9);
      expect(box.get('_chain_pop_storage_schema'), 3);
    });

    test('seeds Daily completions from existing day records', () async {
      final storage = await openFresh();
      final box = storage.boxForTests;

      await box.put('daily_stars_20260801', 3);
      await box.put('daily_stars_20260802', 1);
      // A recorded-but-unplayed day must not count.
      await box.put('daily_stars_20260803', 0);
      await box.delete(AchievementCounter.dailyCompleted.storageKey);
      await box.put('_chain_pop_storage_schema', 2);

      await storage.reconcileSchemaMarker();

      expect(storage.achievementCounter(AchievementCounter.dailyCompleted), 2);
    });

    test('leaves unrecoverable counters at zero', () async {
      final storage = await openFresh();
      final box = storage.boxForTests;
      await box.put('stars_easy_1', 3);
      await box.put('_chain_pop_storage_schema', 2);

      await storage.reconcileSchemaMarker();

      expect(storage.achievementCounter(AchievementCounter.nodesCleared), 0);
      expect(storage.achievementCounter(AchievementCounter.coresExtracted), 0);
      expect(
        storage.achievementCounter(AchievementCounter.bestPlayStreakDays),
        0,
      );
    });

    test('is idempotent across repeated runs', () async {
      final storage = await openFresh();
      final box = storage.boxForTests;
      await box.put('stars_easy_1', 3);
      await box.put('stars_easy_2', 3);
      await box.put('_chain_pop_storage_schema', 2);

      await storage.reconcileSchemaMarker();
      final first = storage.achievementCounter(AchievementCounter.totalStars);

      // Force the migration to run again from the same source data.
      await box.put('_chain_pop_storage_schema', 2);
      await storage.reconcileSchemaMarker();

      expect(
        storage.achievementCounter(AchievementCounter.totalStars),
        first,
        reason: 'a re-run must recompute, not accumulate',
      );
    });

    test('a fresh install lands on v3 with zeroed counters', () async {
      final storage = await openFresh();
      expect(storage.schemaVersionRead, 3);
      for (final c in AchievementCounter.values) {
        expect(storage.achievementCounter(c), 0, reason: c.name);
      }
      expect(storage.unlockedAchievementIds, isEmpty);
      expect(storage.achievementSyncCursor, isEmpty);
    });
  });

  group('counter semantics', () {
    test('bump only adds positive deltas', () async {
      final storage = await openFresh();
      await storage.bumpAchievementCounter(AchievementCounter.nodesCleared, 5);
      await storage.bumpAchievementCounter(AchievementCounter.nodesCleared, 0);
      await storage.bumpAchievementCounter(AchievementCounter.nodesCleared, -3);
      expect(storage.achievementCounter(AchievementCounter.nodesCleared), 5);
    });

    test('raise is a high-water mark', () async {
      final storage = await openFresh();
      await storage.raiseAchievementCounter(
        AchievementCounter.bestJamFreeRun,
        7,
      );
      await storage.raiseAchievementCounter(
        AchievementCounter.bestJamFreeRun,
        3,
      );
      expect(storage.achievementCounter(AchievementCounter.bestJamFreeRun), 7);
    });

    test('or accumulates bits', () async {
      final storage = await openFresh();
      await storage.orAchievementCounter(AchievementCounter.flagsMask, 1 << 0);
      await storage.orAchievementCounter(AchievementCounter.flagsMask, 1 << 3);
      await storage.orAchievementCounter(AchievementCounter.flagsMask, 1 << 0);
      expect(storage.achievementCounter(AchievementCounter.flagsMask), 9);
    });

    test('unlocks deduplicate', () async {
      final storage = await openFresh();
      await storage.markAchievementUnlocked('a');
      await storage.markAchievementUnlocked('a');
      await storage.markAchievementUnlocked('b');
      expect(storage.unlockedAchievementIds, {'a', 'b'});
    });

    test('counter keys are unique', () {
      final keys = AchievementCounter.values.map((c) => c.storageKey).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('counter keys never collide with existing storage prefixes', () {
      // A counter key colliding with `stars_` or `daily_stars_` would be swept
      // into the migration's own scan and corrupt the seed.
      for (final c in AchievementCounter.values) {
        expect(c.storageKey.startsWith('stars_'), isFalse, reason: c.name);
        expect(c.storageKey.startsWith('daily_stars_'), isFalse,
            reason: c.name);
        expect(c.storageKey.startsWith('unlocked_'), isFalse, reason: c.name);
      }
    });
  });

  group('DayKey', () {
    test('decodes and re-encodes', () {
      expect(DayKey.fromDate(DayKey.toDate(20260814)), 20260814);
    });

    test('counts days across a month boundary', () {
      expect(DayKey.daysBetween(20260831, 20260901), 1);
      expect(DayKey.isNextDay(20260831, 20260901), isTrue);
    });

    test('counts days across a year boundary', () {
      expect(DayKey.isNextDay(20261231, 20270101), isTrue);
    });

    test('handles a leap day', () {
      expect(DayKey.isNextDay(20280228, 20280229), isTrue);
      expect(DayKey.isNextDay(20280229, 20280301), isTrue);
      expect(DayKey.daysInMonth(20280201), 29);
      expect(DayKey.daysInMonth(20260201), 28);
    });

    test('reports month lengths', () {
      expect(DayKey.daysInMonth(20260131), 31);
      expect(DayKey.daysInMonth(20260430), 30);
      expect(DayKey.daysInMonth(20261201), 31);
    });

    test('enumerates a full month', () {
      final keys = DayKey.monthKeys(20260215);
      expect(keys.length, 28);
      expect(keys.first, 20260201);
      expect(keys.last, 20260228);
    });

    test('rejects impossible dates', () {
      expect(DayKey.isValid(20260814), isTrue);
      expect(DayKey.isValid(0), isFalse);
      expect(DayKey.isValid(20260230), isFalse);
      expect(DayKey.isValid(20261301), isFalse);
      expect(DayKey.isValid(20260800), isFalse);
      expect(DayKey.isValid(20260229), isFalse, reason: '2026 is not a leap year');
    });

    test('a backwards jump reports a negative span', () {
      expect(DayKey.daysBetween(20260815, 20260808), -7);
      expect(DayKey.isNextDay(20260815, 20260808), isFalse);
    });
  });
}
