import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../game/levels/generation/difficulty_mode.dart';
import '../../game/world_registry.dart';
import '../crash_reporting.dart';
import '../storage/chain_pop_storage.dart';
import '../storage/storage_locator.dart';
import 'achievement_catalog.dart';
import 'achievement_counters.dart';
import 'achievement_rules.dart';
import 'achievement_sink.dart';
import 'achievement_stats.dart';
import 'day_key.dart';
import 'game_event.dart';

/// Combo length that earns Chain Reaction.
const int _kChainReactionStreak = 5;

/// Levels per sector, and Guardians per sector — see `world_registry`.
const int _kLevelsPerSector = 125;
const int _kGuardianInterval = 25;
const int _kGuardiansPerSector = _kLevelsPerSector ~/ _kGuardianInterval;

/// Records gameplay into local aggregates, then projects those aggregates onto
/// Play Games.
///
/// Local-first and ordered: Hive is written before anything is queued, so a
/// crash mid-sync loses nothing and a replay of the queue is always safe. The
/// sink is absolute ([AchievementSink.setSteps]), so re-sending is a no-op
/// rather than a double count.
///
/// Every method is safe to call when signed out, offline, or with no sink at
/// all — progress accrues locally and flushes on the next [sync].
final class AchievementTracker {
  AchievementTracker({
    ChainPopStorage? storage,
    AchievementSink sink = const NoOpAchievementSink(),
    DateTime Function()? now,
    String? Function(AchievementDef)? playGamesIdResolver,
  })  : _storageOverride = storage,
        _sink = sink,
        _now = now ?? DateTime.now,
        _resolveId = playGamesIdResolver ?? _defaultIdResolver;

  static String? _defaultIdResolver(AchievementDef def) =>
      def.playGamesId ?? playGamesIds[def.id];

  final ChainPopStorage? _storageOverride;
  final DateTime Function() _now;

  /// Maps a catalog entry to its Play Console id, or null when it has not been
  /// published yet. Injectable so the sync path is testable before any real
  /// Play Console setup exists.
  final String? Function(AchievementDef) _resolveId;

  AchievementSink _sink;

  ChainPopStorage get _store => _storageOverride ?? StorageLocator.instance;

  /// Swaps the sink at runtime — used when Play Games sign-in completes and the
  /// real sink replaces the no-op one.
  void installSink(AchievementSink sink) {
    _sink = sink;
  }

  /// Fires whenever achievements unlock, with the newly earned entries.
  /// The UI listens to raise a toast.
  final StreamController<List<AchievementDef>> _unlocks =
      StreamController<List<AchievementDef>>.broadcast();

  Stream<List<AchievementDef>> get unlocked => _unlocks.stream;

  Future<void> dispose() => _unlocks.close();

  // ── Event intake ──────────────────────────────────────────────────────────

  /// Applies [event] to local aggregates, then evaluates the catalog.
  Future<void> record(GameEvent event) async {
    switch (event) {
      case CampaignLevelWon():
        await _applyCampaignWin(event);
      case DailyChallengeCompleted():
        await _applyDailyCompleted(event);
      case ComboReached():
        await _applyCombo(event);
    }
    await _evaluateAndSync();
  }

  Future<void> _applyCampaignWin(CampaignLevelWon e) async {
    final s = _store;

    await s.bumpAchievementCounter(
      AchievementCounter.nodesCleared,
      e.nodeCount,
    );
    await s.bumpAchievementCounter(
      AchievementCounter.coresExtracted,
      e.coreCount,
    );
    await s.bumpAchievementCounter(AchievementCounter.locksOpened, e.lockCount);
    await s.bumpAchievementCounter(
      AchievementCounter.relaysCleared,
      e.relayCount,
    );
    await s.bumpAchievementCounter(
      AchievementCounter.phaseGatesCleared,
      e.phaseGateCount,
    );
    await s.bumpAchievementCounter(
      AchievementCounter.portalsTraversed,
      e.portalPairCount,
    );

    // Jam-free run: persisted, because the session-scoped streak resets on
    // relaunch and Perfect Ten is meant to survive that.
    if (e.isJamFree) {
      final next =
          s.achievementCounter(AchievementCounter.currentJamFreeRun) + 1;
      await s.setAchievementCounter(
        AchievementCounter.currentJamFreeRun,
        next,
      );
      await s.raiseAchievementCounter(
        AchievementCounter.bestJamFreeRun,
        next,
      );
    } else {
      await s.setAchievementCounter(AchievementCounter.currentJamFreeRun, 0);
    }

    if (e.isThreeStar) {
      await s.orAchievementCounter(
        AchievementCounter.directiveThreeStarMask,
        1 << e.directive.index,
      );
      if (isBossLevel(e.levelId)) {
        await s.orAchievementCounter(
          AchievementCounter.flagsMask,
          AchievementFlag.guardianPerfect,
        );
        // The only moment a sector's Guardian tally can change, so the 120-read
        // scan is confined to it rather than run on every win.
        await _refreshBestSectorGuardians();
      }
    }

    if (e.mode == DifficultyMode.hard) {
      if (e.networkIntegrity >= 100) {
        await s.orAchievementCounter(
          AchievementCounter.flagsMask,
          AchievementFlag.untouchable,
        );
      }
      if (e.isJamFree && e.undosUsed == 0 && e.hintsUsed == 0) {
        await s.orAchievementCounter(
          AchievementCounter.flagsMask,
          AchievementFlag.masterPlanner,
        );
      }
    }

    final family = e.silhouetteFamily;
    if (family != null) {
      await s.orAchievementCounter(
        AchievementCounter.silhouetteFamilyMask,
        1 << family.index,
      );
    }

    await _advancePlayStreak(e.dayKey);
  }

  Future<void> _applyDailyCompleted(DailyChallengeCompleted e) async {
    final s = _store;

    // `dailyCompleted` is maintained by `saveDailyStars` on the unplayed →
    // played transition, so it is deliberately not bumped here — doing both
    // would double-count every Daily.
    if (e.isArchived) {
      await s.bumpAchievementCounter(AchievementCounter.dailyArchived, 1);
    }

    if (_isCalendarMonthComplete(e.challengeDayKey)) {
      await s.orAchievementCounter(
        AchievementCounter.flagsMask,
        AchievementFlag.calendarCloser,
      );
    }

    await _advancePlayStreak(e.todayDayKey);
  }

  Future<void> _applyCombo(ComboReached e) async {
    if (e.streak < _kChainReactionStreak) return;
    await _store.orAchievementCounter(
      AchievementCounter.flagsMask,
      AchievementFlag.chainReaction,
    );
  }

  // ── Streaks ───────────────────────────────────────────────────────────────

  /// Advances the consecutive-play-days run for a level completed on [dayKey].
  ///
  /// Three cases matter and one is a trap. Same day: already counted, do
  /// nothing. Next calendar day: extend. Any later day: the run broke, restart
  /// at 1. The trap is a day *earlier* than the last recorded one, which means
  /// the device clock moved backwards — that neither extends nor breaks the
  /// run, so a timezone hop or a manual clock change can neither farm the
  /// streak achievements nor destroy honest progress.
  Future<void> _advancePlayStreak(int dayKey) async {
    if (!DayKey.isValid(dayKey)) return;

    final s = _store;
    final last = s.achievementCounter(AchievementCounter.lastPlayDayKey);

    if (last != 0 && DayKey.isValid(last)) {
      if (dayKey == last) return;
      if (dayKey < last) return;
    }

    final current = s.achievementCounter(AchievementCounter.currentPlayStreakDays);
    final extended = last != 0 && DayKey.isValid(last) && DayKey.isNextDay(last, dayKey);
    final next = extended ? current + 1 : 1;

    await s.setAchievementCounter(
      AchievementCounter.currentPlayStreakDays,
      next,
    );
    await s.raiseAchievementCounter(
      AchievementCounter.bestPlayStreakDays,
      next,
    );
    await s.setAchievementCounter(AchievementCounter.lastPlayDayKey, dayKey);
  }

  bool _isCalendarMonthComplete(int dayKey) {
    if (!DayKey.isValid(dayKey)) return false;
    // A month still in progress can never be complete; checking guards against
    // awarding it for, say, a three-day-old month with three days played.
    final today = DayKey.fromDate(_now());
    for (final key in DayKey.monthKeys(dayKey)) {
      if (key > today) return false;
      if (_store.dailyStarsForDayKey(key) <= 0) return false;
    }
    return true;
  }

  // ── Guardians ─────────────────────────────────────────────────────────────

  /// Recomputes the best per-sector Guardian tally across all modes.
  ///
  /// A sector spans 125 levels and holds five Guardians (every 25th). Sector
  /// Clean wants all five 3-starred within one sector on one mode, so the max
  /// is taken per mode-sector pair rather than pooled across modes.
  Future<void> _refreshBestSectorGuardians() async {
    final s = _store;
    var best = 0;
    for (final mode in DifficultyMode.values) {
      for (var sector = 0; sector < 8; sector++) {
        var count = 0;
        for (var g = 1; g <= _kGuardiansPerSector; g++) {
          final level = sector * _kLevelsPerSector + g * _kGuardianInterval;
          if (s.stars(mode, level) >= 3) count++;
        }
        if (count > best) best = count;
      }
    }
    await s.raiseAchievementCounter(
      AchievementCounter.bestSectorGuardians,
      best,
    );
  }

  // ── Snapshot ──────────────────────────────────────────────────────────────

  /// Assembles the current stats from storage.
  AchievementStats snapshot() {
    final s = _store;

    var deepest = 1;
    var atFifty = 0;
    var atTwoHundred = 0;
    var guardians = 0;
    for (final mode in DifficultyMode.values) {
      final frontier = s.highestUnlocked(mode);
      if (frontier > deepest) deepest = frontier;
      if (frontier >= 50) atFifty++;
      if (frontier >= 200) atTwoHundred++;
      // Progression is sequential, so reaching level N means every Guardian
      // below N was cleared — no separate counter needed.
      guardians += (frontier - 1) ~/ _kGuardianInterval;
    }

    int c(AchievementCounter counter) => s.achievementCounter(counter);

    return AchievementStats(
      highestLevelAnyMode: deepest,
      modesAtLevel50: atFifty,
      modesAtLevel200: atTwoHundred,
      totalStars: c(AchievementCounter.totalStars),
      nodesCleared: c(AchievementCounter.nodesCleared),
      coresExtracted: c(AchievementCounter.coresExtracted),
      locksOpened: c(AchievementCounter.locksOpened),
      relaysCleared: c(AchievementCounter.relaysCleared),
      phaseGatesCleared: c(AchievementCounter.phaseGatesCleared),
      portalsTraversed: c(AchievementCounter.portalsTraversed),
      guardiansCleared: guardians,
      bestSectorGuardiansThreeStarred: c(AchievementCounter.bestSectorGuardians),
      dailyCompleted: c(AchievementCounter.dailyCompleted),
      dailyArchived: c(AchievementCounter.dailyArchived),
      bestPlayStreakDays: c(AchievementCounter.bestPlayStreakDays),
      bestJamFreeRun: c(AchievementCounter.bestJamFreeRun),
      silhouetteFamilyMask: c(AchievementCounter.silhouetteFamilyMask),
      directiveThreeStarMask: c(AchievementCounter.directiveThreeStarMask),
      flagsMask: c(AchievementCounter.flagsMask),
    );
  }

  /// Current state of the whole catalog, for the achievements screen.
  List<AchievementProgress> progress() => evaluateAll(
        snapshot(),
        alreadyUnlocked: _store.unlockedAchievementIds,
      );

  // ── Evaluation and sync ───────────────────────────────────────────────────

  Future<void> _evaluateAndSync() async {
    final newlyUnlocked = await _recordUnlocks();
    if (newlyUnlocked.isNotEmpty && !_unlocks.isClosed) {
      _unlocks.add(newlyUnlocked);
    }
    await sync();
  }

  /// Writes any newly satisfied achievements into the local ledger.
  Future<List<AchievementDef>> _recordUnlocks() async {
    final already = _store.unlockedAchievementIds;
    final earned = <AchievementDef>[];
    for (final p in evaluateAll(snapshot(), alreadyUnlocked: already)) {
      if (p.unlocked && !already.contains(p.def.id)) {
        await _store.markAchievementUnlocked(p.def.id);
        earned.add(p.def);
      }
    }
    return earned;
  }

  /// Pushes everything whose local state has moved past its sync cursor.
  ///
  /// Safe to call at any time — on sign-in, on app resume, after every event.
  /// Nothing is sent for an achievement that has not changed, and a failure
  /// leaves the cursor untouched so the next call retries exactly that entry.
  /// Pulls the backend's own view and rewinds any cursor that has run ahead of
  /// it, so the next [sync] re-pushes those entries.
  ///
  /// Without this a cursor that drifts ahead — Play Games resetting tester
  /// progress on an unpublished title, or a push acknowledged locally and then
  /// lost — strands the achievement permanently: [sync] skips every entry whose
  /// cursor already meets the desired value, so it is never retried.
  Future<void> reconcile() async {
    if (!_sink.isAvailable) return;

    final remote = await _sink.remoteProgress();
    if (remote == null) return;

    final cursor = _store.achievementSyncCursor;
    var rewound = 0;
    for (final entry in cursor.entries) {
      final actual = remote[entry.key];
      if (actual == null || actual >= entry.value) continue;
      await _store.setAchievementSyncCursor(entry.key, actual);
      rewound++;
    }
    if (rewound > 0) {
      debugPrint('[Sync] rewound $rewound cursor(s) behind the backend');
    }
  }

  Future<void> sync() async {
    if (!_sink.isAvailable) return;

    final cursor = _store.achievementSyncCursor;
    var sent = 0;
    var failed = 0;
    Object? firstFailure;
    // At most one reconnect attempt per sync: if it did not take, every
    // remaining entry would pay ~1.5s to fail identically.
    var recovered = false;
    AchievementConnectionLost? connectionLost;
    for (final p in progress()) {
      final def = p.def;
      // An entry with no Play Console id is tracked locally but never sent.
      // Pre-publish that is every entry, which is what lets the whole system
      // ship and be played against before any Google setup exists.
      if (_resolveId(def) == null) continue;

      final desired = switch (def.kind) {
        AchievementKind.standard => p.unlocked ? 1 : 0,
        AchievementKind.incremental => def.stepsFor(p.current),
      };
      if (desired <= 0) continue;
      if ((cursor[def.id] ?? 0) >= desired) continue;

      try {
        await _push(def, desired);
        await _store.setAchievementSyncCursor(def.id, desired);
        sent++;
      } on AchievementConnectionLost catch (e) {
        // The write is not lost: the games client buffers it and flushes on
        // reconnect. What matters is that every remaining entry would fail the
        // same way, so try once to re-establish the connection and, failing
        // that, abandon the batch. The cursor stays behind, so the next sync
        // (or the next cold start) replays everything untouched.
        if (!recovered && await _sink.recover()) {
          recovered = true;
          try {
            await _push(def, desired);
            await _store.setAchievementSyncCursor(def.id, desired);
            sent++;
            continue;
          } on AchievementConnectionLost {
            // Fall through to abandoning the batch.
          }
        }
        connectionLost ??= e;
        if (kDebugMode) debugPrint('[Sync] ${def.id} connection lost, stopping');
        break;
      } catch (e) {
        // Leave the cursor behind so this entry is retried next time. Never
        // let a sync failure surface into gameplay — but never swallow it
        // silently either: a totally quiet sync failure is exactly what made
        // the original Play Games breakage impossible to see.
        failed++;
        firstFailure ??= e;
        if (kDebugMode) debugPrint('[Sync] ${def.id} failed: $e');
      }
    }
    if (failed > 0) {
      // One report per sync, not per entry: a disconnected games client fails
      // every achievement at once and would otherwise flood crash reporting.
      debugPrint('[Sync] sent=$sent failed=$failed — $firstFailure');
      recordNonFatal(
        StateError('Achievement sync failed for $failed entries: $firstFailure'),
        StackTrace.current,
      );
    }
    // A lost connection is deliberately NOT reported: it is transient, it costs
    // no data, and it recurs on every sync until the process restarts — one
    // report per level completion per user would bury real faults.
    if (connectionLost != null) {
      debugPrint('[Sync] sent=$sent, deferred the rest: $connectionLost');
    }
  }

  Future<void> _push(AchievementDef def, int desired) =>
      def.kind == AchievementKind.standard
          ? _sink.unlock(def)
          : _sink.setSteps(def, desired);
}
