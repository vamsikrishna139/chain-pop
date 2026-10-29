import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../theme/app_colors.dart';
import '../daily_challenge.dart';
import 'level.dart';
import 'generation/generation.dart';

/// Thin adapter that bridges the game engine (which expects a simple
/// `LevelData`) with the [LevelGenerator] Result-based API.
///
/// The manager resolves generation results and always returns a valid
/// [LevelData] — either the generated level or a safe fallback.
class LevelManager {
  static LevelGenerator generator = LevelGenerator.neutral();

  /// Receives the campaign diversity history after each level [getLevel]
  /// serves, so it can be persisted (W2.4). Bootstrap points this at storage;
  /// it stays null in tests, which keeps every generation suite pure.
  ///
  /// Without it the ledger is session-only: novelty reset on every launch, so
  /// a returning player could be served a board they had just played.
  static void Function(List<int> bits)? onDiversityLedgerChanged;

  /// Told about every generation failure that [getLevel] or the Daily papered
  /// over with a fallback board (W2.5). Bootstrap reports it as a Crashlytics
  /// non-fatal plus an analytics event; null in tests. Always invoked on the
  /// calling isolate, including for a Daily generated on a worker isolate.
  static void Function(String kind, int id, String reason)?
      onGenerationFallback;

  /// Seeds [generator]'s diversity ledger from persisted [bits]. Call once at
  /// startup, before the first [getLevel]. Never touches the Daily, which
  /// generates from a fresh generator by contract.
  static void restoreDiversityLedger(List<int> bits) {
    if (bits.isEmpty) return;
    generator.diversityLedger.restore(bits);
  }

  /// Latency budget for on-load campaign generation. A small tail of seeds
  /// otherwise burn the full attempt budget (~1s) chasing the ideal
  /// removal-wave band; past this the generator ships the best valid level it
  /// already found. Bounds the "Building level…" wait without affecting the
  /// common path or the (budget-free) generation test suites.
  static const Duration generationBudget = Duration(milliseconds: 200);

  /// Work budget for the Daily Challenge, in constructions (K-loop iterations
  /// plus renegotiations; see `LevelGenerator.generateFromConfiguration`).
  ///
  /// **Why work, not time (W2.2).** This used to be a 400 ms stopwatch, and the
  /// over-budget escape ships whichever valid board it holds when the clock
  /// trips — so a slow or busy phone shipped a different Daily than a fast one,
  /// breaking "same board for everyone on a date". Counting constructions trips
  /// at the same point on every device.
  ///
  /// **Why 64.** Measured unbounded over all 365 keys of 2027
  /// (`daily_work_budget_probe_test.dart`): p50 17, p90 59, p95 69, p100 172
  /// constructions at ~5.5 ms each on a dev Mac. 64 leaves ~92% of dates
  /// exactly as unbounded generation would make them and caps the tail near
  /// the old 400 ms on desktop. A slower phone takes proportionally longer
  /// instead of getting a different board; that runs in the isolate.
  ///
  /// `null` would mean fully unbounded (40 attempts × 8 K × 4 renegotiations),
  /// which measured 5.5 s on one key before any budget existed.
  static const int dailyWorkBudget = 64;

  /// Returns a valid, solvable [LevelData] for [levelId].
  ///
  /// Uses the full generation pipeline from [LevelGenerator]. If generation
  /// fails, or ships a board that breaks the layout invariants, a playable
  /// fallback board is returned and the failure is reported through
  /// [onGenerationFallback] — never thrown, and never assert-only.
  ///
  /// Layout validation runs in release too (W2.5). It used to be assert-only,
  /// so release builds skipped the bounds, duplicate-cell and play-cell checks
  /// entirely; they are cheap next to generation itself.
  static LevelData getLevel(int levelId, {DifficultyMode? mode}) {
    final result = generator.generate(
      levelId,
      mode: mode,
      timeBudget: generationBudget,
    );

    final String failure;
    if (result.isSuccess) {
      final level = result.value;
      final layoutMsg = LevelData.layoutValidationMessage(level);
      if (layoutMsg == null) {
        onDiversityLedgerChanged?.call(generator.diversityLedger.serialize());
        return level;
      }
      failure = 'invalid layout: $layoutMsg';
    } else {
      failure = _describe(result.error);
    }
    _reportFallback('campaign', levelId, failure);
    return fallbackLevel(levelId, mode: mode ?? DifficultyMode.easy);
  }

  /// One solvable board per local calendar day; same layout for every player
  /// on that date. Star progress uses [StorageService.saveDailyStars].
  ///
  /// **Prefer [getDailyChallengeAsync] from UI code.** This runs on the calling
  /// isolate, and [dailyWorkBudget] cannot preempt a single retrograde
  /// construction — so on a pathological date key it blocks for seconds. Called
  /// from a tap handler that is exactly an ANR. See [getDailyChallengeAsync].
  static LevelData getDailyChallenge([DateTime? date]) {
    final when = date ?? DateTime.now();
    final dayKey = DailyChallenge.dateKeyLocal(when);
    return _reportDaily(dayKey, _generateDaily(dayKey));
  }

  /// [getDailyChallenge] off the calling isolate.
  ///
  /// **Why this exists.** The Daily budget (then a 400 ms `Stopwatch`, now
  /// [dailyWorkBudget]) lives *outside* the retrograde constructor, so it
  /// bounds outer attempts but cannot interrupt one construction once
  /// started. Measured on key `20260819`: 4.3 s at a 200 ms budget and 4.4 s at 400 ms — identical, and
  /// only three attempts, so the whole cost is inside a single construction.
  /// On a Pixel 8a that produced a real ANR:
  ///
  /// ```
  /// am_anr: com.adbkv.chainpop — Input dispatching timed out
  ///         (MainActivity is not responding. Waited 5001ms for MotionEvent)
  /// ```
  ///
  /// Moving the work to a worker isolate fixes the freeze for *every* date
  /// without touching generation itself, and stays correct when the in-
  /// constructor deadline is eventually added — that work makes this faster,
  /// not redundant, because a 400 ms main-thread block is still a dropped
  /// frame budget.
  ///
  /// **A second bug this closes.** [generator] is static, so the synchronous
  /// path generates the Daily from whatever session state campaign play left in
  /// the diversity ledger and silhouette tracker. Those are *inputs* (see the
  /// T0.0a closure audit), so the Daily was never actually "the same layout for
  /// every player on that date" — it depended on how much the player had
  /// played first. A worker isolate starts from fresh statics, which makes the
  /// board a pure function of `dayKey` and the doc comment above true. Today's
  /// board for a given date may therefore differ from the previous build's;
  /// nothing is keyed to board bytes (stars are stored per `dayKey`), so this
  /// is a one-time, invisible shift.
  ///
  /// Falls back to generating in place if the isolate cannot be spawned, so a
  /// platform without isolate support degrades to the old behaviour rather than
  /// to no Daily at all.
  static Future<LevelData> getDailyChallengeAsync([DateTime? date]) async {
    final when = date ?? DateTime.now();
    final dayKey = DailyChallenge.dateKeyLocal(when);
    _DailyOutcome outcome;
    try {
      outcome = await Isolate.run(() => _generateDaily(dayKey));
    } catch (_) {
      outcome = _generateDaily(dayKey);
    }
    // Reported here, not inside [_generateDaily]: the worker isolate starts
    // from fresh statics, so [onGenerationFallback] is null over there.
    return _reportDaily(dayKey, outcome);
  }

  static LevelData _reportDaily(int dayKey, _DailyOutcome outcome) {
    final failure = outcome.failure;
    if (failure != null) _reportFallback('daily', dayKey, failure);
    return outcome.level;
  }

  /// The Daily board for [dayKey], plus why it is a fallback board if it is.
  static _DailyOutcome _generateDaily(int dayKey) {
    // The Daily contract is `dayKey -> identical board`, for every player and
    // on every call. It is generated from a **fresh generator**, never the
    // static [generator].
    //
    // [generator] is static and its `DiversityLedger` and
    // `SilhouetteSessionTracker` are mutable session state, which the T0.0a
    // closure audit classifies as generation *inputs*. So the synchronous path
    // produced a board that depended on how much campaign play preceded it —
    // and, because each Daily call also records into that state, two calls for
    // the same date returned different boards.
    //
    // The doc on [getDailyChallengeAsync] already identified this and fixed it
    // for the async path only, by way of a worker isolate starting from fresh
    // statics. The synchronous path — the one `getDailyChallenge` uses and the
    // one the async path falls back to when `Isolate.run` throws — kept the
    // bug, and it was invisible because the novelty gate was unreachable: with
    // `isNovel` almost always false every call fell through to the same
    // last-resort candidate, so the board looked stable. T2.6/T2.7 made the
    // gate reachable and the non-determinism surfaced immediately.
    //
    // A fresh generator is the smallest change that makes the contract hold on
    // both paths, and it makes the isolate an optimisation for latency rather
    // than a correctness requirement.
    // No `timeBudget`: anything wall-clock here makes the board depend on the
    // device. See [dailyWorkBudget].
    final result = LevelGenerator.neutral().generateDailyChallenge(
      dayKey,
      workBudget: dailyWorkBudget,
    );

    final String failure;
    if (result.isSuccess) {
      final level = result.value;
      final layoutMsg = LevelData.layoutValidationMessage(level);
      if (layoutMsg == null) return (level: level, failure: null);
      failure = 'invalid layout: $layoutMsg';
    } else {
      failure = _describe(result.error);
    }
    // The Daily is generated against the Expert band from a Hard config.
    return (
      level: fallbackLevel(dayKey, mode: DifficultyMode.hard),
      failure: failure,
    );
  }

  /// Used when unexpected errors occur during async loads (the caller reports
  /// the underlying failure). Same board as [fallbackLevel].
  static LevelData emergencyFallbackLevel(int levelId,
          {DifficultyMode mode = DifficultyMode.easy}) =>
      fallbackLevel(levelId, mode: mode);

  /// A real, playable board to ship when generation for [levelId] failed.
  ///
  /// Level 1 of [mode], generated from a fresh generator with no budget and
  /// relabelled as [levelId] — the cheapest level of that mode, and the most
  /// exercised one, so it is the board least likely to fail too. Only if that
  /// also fails does the player get the one-node board. It used to be the
  /// one-node board every time: a level that is won with one tap.
  @visibleForTesting
  static LevelData fallbackLevel(int levelId, {required DifficultyMode mode}) {
    try {
      final r = LevelGenerator.neutral().generate(1, mode: mode);
      if (r.isSuccess && LevelData.layoutValidationMessage(r.value) == null) {
        final l = r.value;
        return LevelData(
          levelId: levelId,
          gridWidth: l.gridWidth,
          gridHeight: l.gridHeight,
          nodes: l.nodes,
          playCells: l.playCells,
          portalPairs: l.portalPairs,
          silhouetteId: l.silhouetteId,
        );
      }
    } catch (e, st) {
      debugPrint('LevelManager: fallback generation threw: $e\n$st');
    }
    return _oneNodeBoard(levelId);
  }

  static String _describe(GenerationError e) => '${e.type}: ${e.message}';

  static void _reportFallback(String kind, int id, String reason) {
    debugPrint('LevelManager: $kind $id generation fell back — $reason');
    onGenerationFallback?.call(kind, id, reason);
  }

  /// An absolute last-resort fallback: one node pointing up in an empty grid.
  static LevelData _oneNodeBoard(int levelId) {
    return LevelData(
      levelId: levelId,
      gridWidth: 4,
      gridHeight: 4,
      nodes: [
        NodeData(
          id: 0,
          x: 1,
          y: 3,
          dir: Direction.up,
          color: AppColors.nodeDefault,
          colorSlot: 5,
        ),
      ],
    );
  }
}

typedef _DailyOutcome = ({LevelData level, String? failure});
