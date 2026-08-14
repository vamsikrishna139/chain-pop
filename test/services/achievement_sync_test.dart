import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/services/achievements/achievement_catalog.dart';
import 'package:chain_pop/services/achievements/achievement_sink.dart';
import 'package:chain_pop/services/achievements/achievement_tracker.dart';
import 'package:chain_pop/services/achievements/game_event.dart';
import 'package:chain_pop/services/storage/hive_chain_pop_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

CampaignLevelWon win({int nodes = 10, int dayKey = 20260814}) =>
    CampaignLevelWon(
      mode: DifficultyMode.easy,
      levelId: 1,
      starsEarned: 1,
      directive: LevelDirective.swift,
      jamCount: 0,
      undosUsed: 0,
      hintsUsed: 0,
      networkIntegrity: 100,
      nodeCount: nodes,
      coreCount: 0,
      lockCount: 0,
      relayCount: 0,
      phaseGateCount: 0,
      portalPairCount: 0,
      dayKey: dayKey,
    );

/// Exercises the Play Games projection with the whole catalog mapped.
///
/// The properties here are the reason the design uses `setSteps` rather than
/// `increment`: sync must be re-runnable without ever double-counting, and a
/// failure must retry rather than silently skip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveChainPopPersistence storage;
  late AchievementTracker tracker;
  late RecordingAchievementSink sink;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('chain_pop_sync_test_');
    Hive.init(dir.path);
  });

  setUp(() async {
    storage = HiveChainPopPersistence();
    await storage.open();
    await storage.clearProgress();
    sink = RecordingAchievementSink();
    tracker = AchievementTracker(
      storage: storage,
      sink: sink,
      now: () => DateTime.utc(2026, 8, 14),
      // Pretend every entry has been published.
      playGamesIdResolver: (def) => 'pgs_${def.id}',
    );
  });

  tearDown(() async => tracker.dispose());

  List<({String id, int steps})> stepsFor(String id) => _stepsFor(sink, id);

  group('absolute reporting', () {
    test('reports the running total, never a delta', () async {
      await tracker.record(win(nodes: 40));
      await tracker.record(win(nodes: 35));

      final calls = stepsFor(AchievementIds.hundredDown);
      expect(calls.map((c) => c.steps), [40, 75]);
    });

    test('divides by scale for tiers above the step ceiling', () async {
      await tracker.record(win(nodes: 10000));

      final calls = stepsFor(AchievementIds.nodeLord);
      expect(calls.single.steps, 1000, reason: '10,000 nodes ÷ scale 10');
    });

    test('never reports more steps than declared', () async {
      for (var i = 0; i < 12; i++) {
        await tracker.record(win(nodes: 10000, dayKey: 20260814 + i));
      }
      for (final call in sink.stepCalls) {
        final def = kAchievementsById[call.id]!;
        expect(call.steps, lessThanOrEqualTo(def.steps!), reason: call.id);
      }
    });
  });

  group('idempotency', () {
    test('re-syncing without progress sends nothing', () async {
      await tracker.record(win(nodes: 50));
      final countAfterWin = sink.stepCalls.length;
      expect(countAfterWin, greaterThan(0));

      await tracker.sync();
      await tracker.sync();
      expect(sink.stepCalls.length, countAfterWin);
    });

    test('an unchanged achievement is not re-sent when others advance',
        () async {
      await tracker.record(win(nodes: 100));
      final hundredCalls = stepsFor(AchievementIds.hundredDown).length;

      // Hundred Down is capped now; further wins must not touch it again.
      await tracker.record(win(nodes: 100));
      expect(stepsFor(AchievementIds.hundredDown).length, hundredCalls);
      expect(stepsFor(AchievementIds.nodeRunner).length, greaterThan(1));
    });

    test('a standard achievement unlocks exactly once', () async {
      await storage.unlockLevel(DifficultyMode.easy, 2);
      await tracker.record(win());
      await tracker.record(win());
      await tracker.sync();

      expect(
        sink.unlockCalls.where((id) => id == AchievementIds.coldStart).length,
        1,
      );
    });
  });

  group('failure handling', () {
    test('a throwing sink leaves the cursor for a retry', () async {
      sink.throwOnce = StateError('network down');
      await tracker.record(win(nodes: 50));

      // The very first entry threw, so its cursor must not have advanced.
      final cursor = storage.achievementSyncCursor;
      final attempted = sink.stepCalls.map((c) => c.id).toSet();
      for (final id in cursor.keys) {
        expect(attempted, contains(id));
      }

      final before = sink.stepCalls.length;
      await tracker.sync();
      expect(
        sink.stepCalls.length,
        greaterThan(before),
        reason: 'the failed entry should be retried',
      );
    });

    test('a sync failure never surfaces to the caller', () async {
      sink.throwOnce = StateError('boom');
      await expectLater(tracker.record(win(nodes: 10)), completes);
    });
  });

  group('offline then online', () {
    test('a sink arriving late replays the full local history', () async {
      // Play a while entirely offline.
      final offline = RecordingAchievementSink(available: false);
      final offlineTracker = AchievementTracker(
        storage: storage,
        sink: offline,
        now: () => DateTime.utc(2026, 8, 14),
        playGamesIdResolver: (def) => 'pgs_${def.id}',
      );
      for (var i = 0; i < 5; i++) {
        await offlineTracker.record(win(nodes: 40, dayKey: 20260814 + i));
      }
      expect(offline.stepCalls, isEmpty);
      expect(storage.achievementSyncCursor, isEmpty);
      await offlineTracker.dispose();

      // Sign-in happens: the same local aggregates project forward in full.
      final online = RecordingAchievementSink();
      final onlineTracker = AchievementTracker(
        storage: storage,
        sink: online,
        now: () => DateTime.utc(2026, 8, 14),
        playGamesIdResolver: (def) => 'pgs_${def.id}',
      );
      await onlineTracker.sync();

      expect(
        _stepsFor(online, AchievementIds.nodeRunner).single.steps,
        200,
        reason: '5 wins × 40 nodes, sent as one absolute value',
      );
      // Hundred Down was already satisfied offline, so it arrives capped in a
      // single call rather than replaying each intermediate value.
      final hundred = _stepsFor(online, AchievementIds.hundredDown);
      expect(hundred.single.steps, 100);
      await onlineTracker.dispose();
    });
  });
}

List<({String id, int steps})> _stepsFor(
  RecordingAchievementSink sink,
  String id,
) =>
    sink.stepCalls.where((c) => c.id == id).toList();
