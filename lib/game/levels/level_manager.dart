import 'dart:isolate';

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

  /// Latency budget for on-load campaign generation. A small tail of seeds
  /// otherwise burn the full attempt budget (~1s) chasing the ideal
  /// removal-wave band; past this the generator ships the best valid level it
  /// already found. Bounds the "Building level…" wait without affecting the
  /// common path or the (budget-free) generation test suites.
  static const Duration generationBudget = Duration(milliseconds: 200);

  /// Latency budget for the Daily Challenge.
  ///
  /// Daily legitimately does more work than a campaign level (sector-8 mechanic
  /// budget, two relays, Expert-band ranking), so it gets double the campaign
  /// budget rather than the same one. Before this existed the Daily path passed
  /// **no** budget at all — and `null` means *fully unbounded* (40 attempts × 8
  /// K × 4 renegotiations), not "use a default". A 10-day sample measured one
  /// date key at 5.5 s against a 300 ms median, and because the budget-fallback
  /// branch is unreachable without a clock, a Daily that exhausted its attempts
  /// fell all the way through to the one-node emergency board.
  static const Duration dailyGenerationBudget = Duration(milliseconds: 400);

  /// Returns a valid, solvable [LevelData] for [levelId].
  ///
  /// Uses the full generation pipeline from [LevelGenerator]. If generation
  /// fails for any reason (e.g. invalid configuration), a guaranteed-solvable
  /// fallback is returned rather than throwing.
  static LevelData getLevel(int levelId, {DifficultyMode? mode}) {
    final result = generator.generate(
      levelId,
      mode: mode,
      timeBudget: generationBudget,
    );

    if (result.isSuccess) {
      final level = result.value;
      final layoutMsg = LevelData.layoutValidationMessage(level);
      assert(layoutMsg == null, 'Invalid layout: $layoutMsg');
      return level;
    }

    // Log error and use emergency fallback (a single-node level is always
    // solvable and prevents any crash from reaching the player).
    assert(false, 'Level generation failed: ${result.error}');
    return _emergencyFallback(levelId);
  }

  /// One solvable board per local calendar day; same layout for every player
  /// on that date. Star progress uses [StorageService.saveDailyStars].
  ///
  /// **Prefer [getDailyChallengeAsync] from UI code.** This runs on the calling
  /// isolate, and [dailyGenerationBudget] cannot preempt a single retrograde
  /// construction — so on a pathological date key it blocks for seconds. Called
  /// from a tap handler that is exactly an ANR. See [getDailyChallengeAsync].
  static LevelData getDailyChallenge([DateTime? date]) {
    final when = date ?? DateTime.now();
    return _generateDaily(DailyChallenge.dateKeyLocal(when));
  }

  /// [getDailyChallenge] off the calling isolate.
  ///
  /// **Why this exists.** `dailyGenerationBudget` is a `Stopwatch` living
  /// *outside* the retrograde constructor, so it bounds outer attempts but
  /// cannot interrupt one construction once started. Measured on key
  /// `20260819`: 4.3 s at a 200 ms budget and 4.4 s at 400 ms — identical, and
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
    try {
      return await Isolate.run(() => _generateDaily(dayKey));
    } catch (_) {
      return _generateDaily(dayKey);
    }
  }

  static LevelData _generateDaily(int dayKey) {
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
    final result = LevelGenerator.neutral().generateDailyChallenge(
      dayKey,
      timeBudget: dailyGenerationBudget,
    );

    if (result.isSuccess) {
      final level = result.value;
      final layoutMsg = LevelData.layoutValidationMessage(level);
      assert(layoutMsg == null, 'Invalid daily layout: $layoutMsg');
      return level;
    }

    assert(false, 'Daily generation failed: ${result.error}');
    return _emergencyFallback(dayKey);
  }

  /// Guaranteed-solvable one-node layout — used when unexpected errors occur
  /// during async loads (crash reporting captures the underlying failure).
  static LevelData emergencyFallbackLevel(int levelId) =>
      _emergencyFallback(levelId);

  /// An absolute last-resort fallback: one node pointing up in an empty grid.
  static LevelData _emergencyFallback(int levelId) {
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
