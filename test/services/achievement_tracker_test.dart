import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/services/achievements/achievement_catalog.dart';
import 'package:chain_pop/services/achievements/achievement_counters.dart';
import 'package:chain_pop/services/achievements/achievement_sink.dart';
import 'package:chain_pop/services/achievements/achievement_tracker.dart';
import 'package:chain_pop/services/achievements/day_key.dart';
import 'package:chain_pop/services/achievements/game_event.dart';
import 'package:chain_pop/services/storage/hive_chain_pop_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// A campaign win with sensible defaults, so each test states only what it
/// actually cares about.
CampaignLevelWon win({
  int levelId = 1,
  DifficultyMode mode = DifficultyMode.easy,
  int stars = 1,
  LevelDirective directive = LevelDirective.swift,
  int jams = 0,
  int undos = 0,
  int hints = 0,
  int integrity = 100,
  int nodes = 10,
  int cores = 0,
  int locks = 0,
  int relays = 0,
  int gates = 0,
  int portals = 0,
  int dayKey = 20260814,
  SilhouetteVisualFamily? family,
}) =>
    CampaignLevelWon(
      mode: mode,
      levelId: levelId,
      starsEarned: stars,
      directive: directive,
      jamCount: jams,
      undosUsed: undos,
      hintsUsed: hints,
      networkIntegrity: integrity,
      nodeCount: nodes,
      coreCount: cores,
      lockCount: locks,
      relayCount: relays,
      phaseGateCount: gates,
      portalPairCount: portals,
      dayKey: dayKey,
      silhouetteFamily: family,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveChainPopPersistence storage;
  late AchievementTracker tracker;
  late RecordingAchievementSink sink;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('chain_pop_ach_test_');
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
    );
  });

  tearDown(() async => tracker.dispose());

  bool unlocked(String id) => storage.unlockedAchievementIds.contains(id);

  int counter(AchievementCounter c) => storage.achievementCounter(c);

  group('counters', () {
    test('a win accumulates every per-level mechanic tally', () async {
      await tracker.record(
        win(nodes: 24, cores: 3, locks: 2, relays: 1, gates: 1, portals: 2),
      );

      expect(counter(AchievementCounter.nodesCleared), 24);
      expect(counter(AchievementCounter.coresExtracted), 3);
      expect(counter(AchievementCounter.locksOpened), 2);
      expect(counter(AchievementCounter.relaysCleared), 1);
      expect(counter(AchievementCounter.phaseGatesCleared), 1);
      expect(counter(AchievementCounter.portalsTraversed), 2);
    });

    test('tallies sum across wins', () async {
      await tracker.record(win(nodes: 10, cores: 1));
      await tracker.record(win(nodes: 15, cores: 2));
      expect(counter(AchievementCounter.nodesCleared), 25);
      expect(counter(AchievementCounter.coresExtracted), 3);
    });
  });

  group('unlocks', () {
    test('Cold Start needs a cleared level, not a fresh install', () async {
      // The frontier defaults to 1 on a new install; that is "level 1 is
      // playable", not "level 1 was cleared".
      expect(unlocked(AchievementIds.coldStart), isFalse);

      await storage.unlockLevel(DifficultyMode.easy, 2);
      await tracker.record(win(levelId: 1));

      expect(unlocked(AchievementIds.coldStart), isTrue);
    });

    test('nothing unlocks before its threshold', () async {
      await tracker.record(win(nodes: 99));
      expect(unlocked(AchievementIds.hundredDown), isFalse);
      await tracker.record(win(nodes: 1));
      expect(unlocked(AchievementIds.hundredDown), isTrue);
    });

    test('a 3-star win records its directive', () async {
      await tracker.record(
        win(stars: 3, directive: LevelDirective.flawless),
      );
      expect(unlocked(AchievementIds.flawlessExecution), isTrue);
      expect(unlocked(AchievementIds.swiftSolver), isFalse);
    });

    test('a 1-star win records no directive', () async {
      await tracker.record(win(stars: 1, directive: LevelDirective.flawless));
      expect(unlocked(AchievementIds.flawlessExecution), isFalse);
    });

    test('Full Directive needs all five', () async {
      for (final d in LevelDirective.values) {
        expect(unlocked(AchievementIds.fullDirective), isFalse);
        await tracker.record(win(stars: 3, directive: d));
      }
      expect(unlocked(AchievementIds.fullDirective), isTrue);
    });

    test('Untouchable is Hard-only and needs full integrity', () async {
      await tracker.record(win(mode: DifficultyMode.easy, integrity: 100));
      expect(unlocked(AchievementIds.untouchable), isFalse);

      await tracker.record(win(mode: DifficultyMode.hard, integrity: 92));
      expect(unlocked(AchievementIds.untouchable), isFalse);

      await tracker.record(win(mode: DifficultyMode.hard, integrity: 100));
      expect(unlocked(AchievementIds.untouchable), isTrue);
    });

    test('Master Planner needs no jam, no undo and no hint', () async {
      await tracker.record(win(mode: DifficultyMode.hard, hints: 1));
      expect(unlocked(AchievementIds.masterPlanner), isFalse);

      await tracker.record(win(mode: DifficultyMode.hard, undos: 1));
      expect(unlocked(AchievementIds.masterPlanner), isFalse);

      await tracker.record(win(mode: DifficultyMode.hard, jams: 1));
      expect(unlocked(AchievementIds.masterPlanner), isFalse);

      await tracker.record(win(mode: DifficultyMode.hard));
      expect(unlocked(AchievementIds.masterPlanner), isTrue);
    });

    test('Chain Reaction ignores combos below the threshold', () async {
      await tracker.record(const ComboReached(4));
      expect(unlocked(AchievementIds.chainReaction), isFalse);
      await tracker.record(const ComboReached(5));
      expect(unlocked(AchievementIds.chainReaction), isTrue);
    });

    test('Full Spectrum needs all four silhouette families', () async {
      for (final f in SilhouetteVisualFamily.values) {
        expect(unlocked(AchievementIds.fullSpectrum), isFalse);
        await tracker.record(win(family: f));
      }
      expect(unlocked(AchievementIds.fullSpectrum), isTrue);
    });

    test('an unknown silhouette records nothing', () async {
      await tracker.record(win());
      expect(counter(AchievementCounter.silhouetteFamilyMask), 0);
    });

    test('an unlock is permanent once earned', () async {
      // Perfect Ten rides the *best* jam-free run, so a later jam must not
      // revoke it.
      for (var i = 0; i < 10; i++) {
        await tracker.record(win());
      }
      expect(unlocked(AchievementIds.perfectTen), isTrue);

      await tracker.record(win(jams: 3));
      expect(counter(AchievementCounter.currentJamFreeRun), 0);
      expect(unlocked(AchievementIds.perfectTen), isTrue);
    });
  });

  group('jam-free run', () {
    test('a jam resets the current run but not the best', () async {
      await tracker.record(win());
      await tracker.record(win());
      expect(counter(AchievementCounter.currentJamFreeRun), 2);
      expect(counter(AchievementCounter.bestJamFreeRun), 2);

      await tracker.record(win(jams: 1));
      expect(counter(AchievementCounter.currentJamFreeRun), 0);
      expect(counter(AchievementCounter.bestJamFreeRun), 2);
    });
  });

  group('play streak', () {
    test('consecutive days extend the run', () async {
      await tracker.record(win(dayKey: 20260814));
      await tracker.record(win(dayKey: 20260815));
      await tracker.record(win(dayKey: 20260816));
      expect(counter(AchievementCounter.currentPlayStreakDays), 3);
      expect(unlocked(AchievementIds.backAgain), isTrue);
    });

    test('crosses a month boundary correctly', () async {
      // The keys are YYYYMMDD, so 20260831 → 20260901 is only "consecutive"
      // under real calendar arithmetic.
      await tracker.record(win(dayKey: 20260831));
      await tracker.record(win(dayKey: 20260901));
      expect(counter(AchievementCounter.currentPlayStreakDays), 2);
    });

    test('crosses a year boundary correctly', () async {
      await tracker.record(win(dayKey: 20261231));
      await tracker.record(win(dayKey: 20270101));
      expect(counter(AchievementCounter.currentPlayStreakDays), 2);
    });

    test('two wins on one day count once', () async {
      await tracker.record(win(dayKey: 20260814));
      await tracker.record(win(dayKey: 20260814));
      expect(counter(AchievementCounter.currentPlayStreakDays), 1);
    });

    test('a gap restarts the run', () async {
      await tracker.record(win(dayKey: 20260814));
      await tracker.record(win(dayKey: 20260815));
      await tracker.record(win(dayKey: 20260820));
      expect(counter(AchievementCounter.currentPlayStreakDays), 1);
      expect(counter(AchievementCounter.bestPlayStreakDays), 2);
    });

    test('a backwards clock neither extends nor breaks the run', () async {
      await tracker.record(win(dayKey: 20260814));
      await tracker.record(win(dayKey: 20260815));
      expect(counter(AchievementCounter.currentPlayStreakDays), 2);

      // Clock yanked back a week: must not farm the streak, must not destroy it.
      await tracker.record(win(dayKey: 20260808));
      expect(counter(AchievementCounter.currentPlayStreakDays), 2);
      expect(counter(AchievementCounter.lastPlayDayKey), 20260815);

      // And the real next day still extends normally.
      await tracker.record(win(dayKey: 20260816));
      expect(counter(AchievementCounter.currentPlayStreakDays), 3);
    });

    test('an invalid day key is ignored', () async {
      await tracker.record(win(dayKey: 0));
      expect(counter(AchievementCounter.currentPlayStreakDays), 0);
      await tracker.record(win(dayKey: 20260230));
      expect(counter(AchievementCounter.currentPlayStreakDays), 0);
    });
  });

  group('daily challenge', () {
    test('completion is counted once by storage, not twice', () async {
      await storage.saveDailyStars(20260814, 3);
      await tracker.record(
        const DailyChallengeCompleted(
          challengeDayKey: 20260814,
          todayDayKey: 20260814,
          starsEarned: 3,
        ),
      );
      expect(counter(AchievementCounter.dailyCompleted), 1);
      expect(unlocked(AchievementIds.dailyDabbler), isTrue);
    });

    test('improving a day does not inflate the tally', () async {
      await storage.saveDailyStars(20260814, 1);
      await storage.saveDailyStars(20260814, 3);
      expect(counter(AchievementCounter.dailyCompleted), 1);
    });

    test('a same-day play is not archived', () async {
      await tracker.record(
        const DailyChallengeCompleted(
          challengeDayKey: 20260814,
          todayDayKey: 20260814,
          starsEarned: 2,
        ),
      );
      expect(counter(AchievementCounter.dailyArchived), 0);
    });

    test('a past-date play is archived', () async {
      await tracker.record(
        const DailyChallengeCompleted(
          challengeDayKey: 20260801,
          todayDayKey: 20260814,
          starsEarned: 2,
        ),
      );
      expect(counter(AchievementCounter.dailyArchived), 1);
    });

    test('Calendar Closer needs every day of a finished month', () async {
      for (final key in DayKey.monthKeys(20260731)) {
        await storage.saveDailyStars(key, 2);
      }
      await tracker.record(
        const DailyChallengeCompleted(
          challengeDayKey: 20260731,
          todayDayKey: 20260814,
          starsEarned: 2,
        ),
      );
      expect(unlocked(AchievementIds.calendarCloser), isTrue);
    });

    test('a month with a gap does not close it', () async {
      final keys = DayKey.monthKeys(20260731)..removeAt(9);
      for (final key in keys) {
        await storage.saveDailyStars(key, 2);
      }
      await tracker.record(
        const DailyChallengeCompleted(
          challengeDayKey: 20260731,
          todayDayKey: 20260814,
          starsEarned: 2,
        ),
      );
      expect(unlocked(AchievementIds.calendarCloser), isFalse);
    });

    test('the current month cannot close early', () async {
      // "Today" is 14 Aug 2026 in these tests, so August cannot be complete
      // however many of its first days were played.
      for (var d = 1; d <= 14; d++) {
        await storage.saveDailyStars(20260800 + d, 3);
      }
      await tracker.record(
        const DailyChallengeCompleted(
          challengeDayKey: 20260814,
          todayDayKey: 20260814,
          starsEarned: 3,
        ),
      );
      expect(unlocked(AchievementIds.calendarCloser), isFalse);
    });
  });

  group('derived progression', () {
    test('depth reads the deepest of the three tracks', () async {
      await storage.unlockLevel(DifficultyMode.easy, 12);
      await storage.unlockLevel(DifficultyMode.hard, 60);
      expect(tracker.snapshot().highestLevelAnyMode, 60);
      await tracker.record(win());
      expect(unlocked(AchievementIds.journeyBegun), isTrue);
    });

    test('Three Fronts needs level 50 on all three modes', () async {
      await storage.unlockLevel(DifficultyMode.easy, 50);
      await storage.unlockLevel(DifficultyMode.medium, 50);
      await tracker.record(win());
      expect(unlocked(AchievementIds.threeFronts), isFalse);

      await storage.unlockLevel(DifficultyMode.hard, 50);
      await tracker.record(win());
      expect(unlocked(AchievementIds.threeFronts), isTrue);
    });

    test('Guardians are derived from the frontier', () async {
      // Sequential progression means reaching 260 implies all ten Guardians
      // below it were cleared.
      await storage.unlockLevel(DifficultyMode.medium, 260);
      expect(tracker.snapshot().guardiansCleared, greaterThanOrEqualTo(10));
      await tracker.record(win());
      expect(unlocked(AchievementIds.guardianHunter), isTrue);
    });

    test('Guardian 40 needs level 1,000 cleared, not merely reached', () async {
      await storage.unlockLevel(DifficultyMode.hard, 1000);
      await tracker.record(win());
      expect(unlocked(AchievementIds.guardian40), isFalse);

      await storage.unlockLevel(DifficultyMode.hard, 1001);
      await tracker.record(win());
      expect(unlocked(AchievementIds.guardian40), isTrue);
    });

    test('stars aggregate across modes', () async {
      await storage.saveStars(DifficultyMode.easy, 1, 3);
      await storage.saveStars(DifficultyMode.medium, 1, 3);
      await storage.saveStars(DifficultyMode.hard, 1, 2);
      expect(tracker.snapshot().totalStars, 8);
    });

    test('re-clearing a level adds only the improvement', () async {
      await storage.saveStars(DifficultyMode.easy, 1, 1);
      await storage.saveStars(DifficultyMode.easy, 1, 3);
      await storage.saveStars(DifficultyMode.easy, 1, 2);
      expect(tracker.snapshot().totalStars, 3);
    });
  });

  group('Sector Clean', () {
    test('needs all five Guardians of one sector 3-starred', () async {
      // Sector 1 Guardians sit at 25, 50, 75, 100 and 125.
      for (final level in [25, 50, 75, 100]) {
        await storage.saveStars(DifficultyMode.easy, level, 3);
      }
      await tracker.record(win(levelId: 100, stars: 3));
      expect(unlocked(AchievementIds.sectorClean), isFalse);

      await storage.saveStars(DifficultyMode.easy, 125, 3);
      await tracker.record(win(levelId: 125, stars: 3));
      expect(unlocked(AchievementIds.sectorClean), isTrue);
    });

    test('does not pool Guardians across sectors', () async {
      await storage.saveStars(DifficultyMode.easy, 25, 3);
      await storage.saveStars(DifficultyMode.easy, 50, 3);
      await storage.saveStars(DifficultyMode.easy, 150, 3);
      await storage.saveStars(DifficultyMode.easy, 175, 3);
      await storage.saveStars(DifficultyMode.easy, 200, 3);
      await tracker.record(win(levelId: 200, stars: 3));
      expect(unlocked(AchievementIds.sectorClean), isFalse);
    });

    test('a 3-starred Guardian earns Guardian Perfect', () async {
      await tracker.record(win(levelId: 25, stars: 3));
      expect(unlocked(AchievementIds.guardianPerfect), isTrue);
    });

    test('a 3-starred ordinary level does not', () async {
      await tracker.record(win(levelId: 24, stars: 3));
      expect(unlocked(AchievementIds.guardianPerfect), isFalse);
    });
  });

  group('sync', () {
    test('nothing is sent for an entry with no Play Console id', () async {
      // Entries the catalog has not mapped stay local. This held for the whole
      // catalog before Play Console setup; it now guards the per-entry case,
      // e.g. an achievement added to the catalog ahead of its Console entry.
      final unmapped = AchievementTracker(
        storage: storage,
        sink: sink,
        now: () => DateTime.utc(2026, 8, 14),
        playGamesIdResolver: (_) => null,
      );
      addTearDown(unmapped.dispose);

      await unmapped.record(win(nodes: 200));
      expect(sink.stepCalls, isEmpty);
      expect(sink.unlockCalls, isEmpty);
    });

    test('a mapped entry is sent as absolute progress', () async {
      await tracker.record(win(nodes: 200));

      // Incremental entries report the total, never a delta — replaying is
      // then always safe. Node Runner tracks 1,000 nodes at scale 1.
      expect(
        sink.stepCalls,
        contains((id: AchievementIds.nodeRunner, steps: 200)),
      );
    });

    test('a mapped standard entry unlocks outright', () async {
      await tracker.record(win(levelId: 25, stars: 3));
      expect(sink.unlockCalls, contains(AchievementIds.guardianPerfect));
    });

    test('a scaled entry reports steps divided by its scale', () async {
      await tracker.record(win(nodes: 5000));

      // Node Lord tracks 50,000 nodes as 5,000 steps of 10 — Google caps
      // steps at 10,000, and Play Console holds the divided count.
      expect(
        sink.stepCalls,
        contains((id: AchievementIds.nodeLord, steps: 500)),
      );
    });

    test('an unavailable sink is never called', () async {
      sink.available = false;
      await tracker.record(win(nodes: 500));
      expect(sink.stepCalls, isEmpty);
    });

    test('progress still accrues locally while the sink is down', () async {
      sink.available = false;
      await tracker.record(win(nodes: 150));
      expect(counter(AchievementCounter.nodesCleared), 150);
      expect(unlocked(AchievementIds.hundredDown), isTrue);
      // The cursor stays empty, so the first live sink replays from zero
      // rather than starting from "now".
      expect(storage.achievementSyncCursor, isEmpty);
    });
  });

  group('sync connection loss', () {
    // Play Games answers 26502 CLIENT_RECONNECT_REQUIRED once its client goes
    // stale, and then fails every subsequent call the same way at ~1.5s each.
    // The batch must stop rather than grind through the whole catalog.
    final lost = AchievementConnectionLost(Exception('26502'));

    test('a recoverable connection is retried once and the entry lands',
        () async {
      sink.throwOnce = lost;
      sink.recoverSucceeds = true;

      await tracker.record(win(nodes: 200));

      expect(sink.recoverCalls, 1, reason: 'exactly one reconnect attempt');
      // The retry re-sends the same absolute value, so the entry still lands.
      expect(
        sink.stepCalls,
        contains((id: AchievementIds.nodeRunner, steps: 200)),
      );
    });

    test('an unrecoverable connection stops the batch', () async {
      sink.throwOnce = lost;
      sink.recoverSucceeds = false;

      await tracker.record(win(nodes: 200, levelId: 25, stars: 3));

      expect(sink.recoverCalls, 1);
      // Nothing after the failing entry is attempted: no point paying ~1.5s
      // per call for an identical failure.
      expect(sink.stepCalls, isEmpty);
      expect(sink.unlockCalls, isEmpty);
    });

    test('an abandoned batch leaves the cursor untouched so it replays',
        () async {
      sink.throwOnce = lost;
      sink.recoverSucceeds = false;

      await tracker.record(win(nodes: 200));
      expect(storage.achievementSyncCursor, isEmpty);

      // A later sync against a healthy sink replays the entry from local state.
      sink.recoverSucceeds = true;
      await tracker.sync();
      expect(
        sink.stepCalls,
        contains((id: AchievementIds.nodeRunner, steps: 200)),
      );
    });
  });

  group('unlock stream', () {
    test('emits newly earned achievements once', () async {
      final seen = <String>[];
      final sub = tracker.unlocked.listen(
        (defs) => seen.addAll(defs.map((d) => d.id)),
      );

      await tracker.record(win(nodes: 100));
      await Future<void>.delayed(Duration.zero);
      expect(seen, contains(AchievementIds.hundredDown));

      final countAfterFirst = seen.length;
      await tracker.record(win(nodes: 1));
      await Future<void>.delayed(Duration.zero);
      expect(
        seen.where((id) => id == AchievementIds.hundredDown).length,
        1,
        reason: 'an unlock must not re-emit',
      );
      expect(seen.length, greaterThanOrEqualTo(countAfterFirst));

      await sub.cancel();
    });
  });
}
