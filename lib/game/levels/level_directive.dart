import '../world_registry.dart';
import 'generation/difficulty_mode.dart';
import 'generation/progression_profile.dart';
import '../../screens/game/game_time_limit.dart';

enum LevelDirective {
  flawless,
  integrity,
  cascade,
  swift,
  unaided,
}

extension LevelDirectiveExt on LevelDirective {
  String get label {
    switch (this) {
      case LevelDirective.flawless:
        return 'FLAWLESS';
      case LevelDirective.integrity:
        return 'INTEGRITY';
      case LevelDirective.cascade:
        return 'CASCADE';
      case LevelDirective.swift:
        return 'SWIFT';
      case LevelDirective.unaided:
        return 'UNAIDED';
    }
  }
}

/// Sector-themed directive pools.
///
/// The sector sets the *character* of the three-star goal and escalates across
/// the campaign; the level id then rotates within that pool. Rotation matters:
/// pinning one directive per sector meant a player chased the identical goal
/// for 125 levels at a stretch (and 375 straight for `flawless` in sectors
/// 6-8), which reads as a single objective rather than a progression. Index 0
/// is each sector's signature directive — the one boss levels pin to.
const Map<int, List<LevelDirective>> _kSectorDirectivePool = {
  1: [LevelDirective.cascade, LevelDirective.swift],
  2: [LevelDirective.cascade, LevelDirective.swift, LevelDirective.unaided],
  3: [LevelDirective.swift, LevelDirective.cascade],
  4: [LevelDirective.unaided, LevelDirective.swift],
  5: [LevelDirective.integrity, LevelDirective.unaided, LevelDirective.swift],
  6: [
    LevelDirective.flawless,
    LevelDirective.integrity,
    LevelDirective.cascade
  ],
  7: [
    LevelDirective.flawless,
    LevelDirective.integrity,
    LevelDirective.unaided
  ],
  8: [LevelDirective.flawless, LevelDirective.integrity, LevelDirective.swift],
};

LevelDirective directiveFor(
    {required int levelId, required DifficultyMode mode}) {
  final sector = worldForLevel(levelId).sector.mechanicBudgetTier;
  final pool = _kSectorDirectivePool[sector] ?? const [LevelDirective.flawless];

  // Boss slots (every 25th level) pin the sector's signature directive so the
  // world finale always tests the thing that world was about.
  final isBoss = levelId % 25 == 0;
  final chosen = isBoss ? pool.first : pool[levelId % pool.length];

  // Cascade requires cores to clear the board under the moves budget; if this
  // mode/sector generates no cores, the goal is unwinnable, so fall back.
  if (chosen == LevelDirective.cascade &&
      budgetFor(levelId: levelId, mode: mode).coreCount == 0) {
    return LevelDirective.swift;
  }
  return chosen;
}

class LevelResult {
  final int levelId;
  final int jamCount;
  final int elapsedSeconds;
  final int undosUsed;
  final int movesTaken;
  final int totalNodes;
  final DifficultyMode mode;
  final bool isTutorial;

  const LevelResult({
    required this.levelId,
    required this.jamCount,
    required this.elapsedSeconds,
    required this.undosUsed,
    required this.movesTaken,
    required this.totalNodes,
    required this.mode,
    this.isTutorial = false,
  });

  bool meetsDirective(LevelDirective directive) {
    switch (directive) {
      case LevelDirective.flawless:
        return jamCount == 0;
      case LevelDirective.integrity:
        return jamCount <= 1;
      case LevelDirective.cascade:
        return movesTaken <= totalNodes ~/ 2;
      case LevelDirective.swift:
        final limit = computeGameTimeLimit(mode, totalNodes, levelId);
        if (limit != null) {
          // Swift is earned by finishing in <= 50% of the mode's computed time limit.
          return elapsedSeconds <= limit ~/ 2;
        }
        // Fallback if no limit (should not happen in normal gameplay)
        return elapsedSeconds <= totalNodes * 2;
      case LevelDirective.unaided:
        return undosUsed == 0;
    }
  }

  /// Calculates stars earned (1-3) based on the level's mode and performance.
  int get earnedStars {
    // Daily challenges don't show a directive on the win panel, so we grade
    // them purely on jams to preserve their legacy star curve.
    if (levelId == 0 || levelId > 10000) {
      if (jamCount == 0) return 3;
      if (jamCount <= 2) return 2;
      return 1;
    }

    if (isTutorial) {
      if (jamCount == 0) return 3;
      if (jamCount <= 2) return 2;
      return 1;
    }

    // Campaign grading: 3 stars if the sector's directive is met, 2 stars if
    // no jams occurred (where possible), 1 star otherwise.
    if (meetsDirective(directiveFor(levelId: levelId, mode: mode))) return 3;
    if (jamCount == 0) return 2;
    return 1;
  }
}
