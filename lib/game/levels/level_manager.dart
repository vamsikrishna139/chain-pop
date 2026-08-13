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
  static final LevelGenerator _generator = LevelGenerator();

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
    final result = _generator.generate(
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
  static LevelData getDailyChallenge([DateTime? date]) {
    final when = date ?? DateTime.now();
    final dayKey = DailyChallenge.dateKeyLocal(when);
    final result = _generator.generateDailyChallenge(
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
