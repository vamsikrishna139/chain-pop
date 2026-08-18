import '../../game/levels/generation/difficulty_mode.dart';
import '../../game/levels/generation/silhouettes.dart';
import '../../game/levels/level_directive.dart';

/// Gameplay facts worth recording, emitted once each at the moment they happen.
///
/// Deliberately a description of *what the player did*, not of what any
/// achievement needs — the rule engine is what maps events onto the catalog, so
/// adding an achievement never requires a new event, and the same stream feeds
/// analytics without either consumer knowing about the other.
sealed class GameEvent {
  const GameEvent();
}

/// A campaign level was won. Carries the full per-level tally so the tracker
/// never has to reach back into the engine.
final class CampaignLevelWon extends GameEvent {
  const CampaignLevelWon({
    required this.mode,
    required this.levelId,
    required this.starsEarned,
    required this.directive,
    required this.jamCount,
    required this.undosUsed,
    required this.hintsUsed,
    required this.networkIntegrity,
    required this.nodeCount,
    required this.coreCount,
    required this.lockCount,
    required this.relayCount,
    required this.phaseGateCount,
    required this.portalPairCount,
    required this.dayKey,
    this.silhouetteFamily,
  });

  final DifficultyMode mode;
  final int levelId;
  final int starsEarned;
  final LevelDirective directive;
  final int jamCount;
  final int undosUsed;
  final int hintsUsed;

  /// 0–100 at the moment of the win. 100 means no jam ever landed.
  final int networkIntegrity;

  final int nodeCount;
  final int coreCount;
  final int lockCount;
  final int relayCount;
  final int phaseGateCount;
  final int portalPairCount;

  /// Local day of the win, in the same encoding the Daily Challenge uses.
  final int dayKey;

  /// Null when the board's silhouette is not known (seeded and tutorial levels
  /// do not carry one). Nothing is recorded in that case rather than guessing.
  final SilhouetteVisualFamily? silhouetteFamily;

  bool get isJamFree => jamCount == 0;

  bool get isThreeStar => starsEarned >= 3;
}

/// A Daily Challenge was completed.
final class DailyChallengeCompleted extends GameEvent {
  const DailyChallengeCompleted({
    required this.challengeDayKey,
    required this.todayDayKey,
    required this.starsEarned,
  });

  /// The day the challenge belongs to.
  final int challengeDayKey;

  /// The day it was actually played.
  final int todayDayKey;

  final int starsEarned;

  /// Played later than its own date — the Daily Archivist condition.
  bool get isArchived => todayDayKey > challengeDayKey;
}

/// The extraction combo reached [streak] on a single chain.
final class ComboReached extends GameEvent {
  const ComboReached(this.streak);

  final int streak;
}
