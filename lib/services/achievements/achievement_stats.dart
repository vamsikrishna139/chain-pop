import '../../game/levels/generation/silhouettes.dart';
import '../../game/levels/level_directive.dart';

/// One-off accomplishments that no counter can express.
///
/// Stored as a bitmask so the whole set costs a single Hive key. Bit positions
/// are persisted — **append only, never reorder**.
abstract final class AchievementFlag {
  AchievementFlag._();

  /// Earned 3 stars on a Guardian (every 25th) level.
  static const int guardianPerfect = 1 << 0;

  /// Reached a ×5 extraction combo.
  static const int chainReaction = 1 << 1;

  /// Cleared a Hard level at 100% network integrity.
  static const int untouchable = 1 << 2;

  /// Cleared a Hard level with no undo, no hint and no jam.
  static const int masterPlanner = 1 << 3;

  /// Completed every day of one calendar month's Daily Challenges.
  static const int calendarCloser = 1 << 4;
}

/// Immutable snapshot of everything the rule engine needs.
///
/// Assembled from Hive on demand. Most fields are stored counters; a few
/// ([highestLevelAnyMode], [guardiansCleared], [modesAtLevel50]) are derived
/// from `highestUnlocked`, which is already authoritative because campaign
/// progression is strictly sequential — reaching level N means every level
/// below N was cleared.
final class AchievementStats {
  const AchievementStats({
    this.highestLevelAnyMode = 1,
    this.modesAtLevel50 = 0,
    this.modesAtLevel200 = 0,
    this.totalStars = 0,
    this.nodesCleared = 0,
    this.coresExtracted = 0,
    this.locksOpened = 0,
    this.relaysCleared = 0,
    this.phaseGatesCleared = 0,
    this.portalsTraversed = 0,
    this.guardiansCleared = 0,
    this.bestSectorGuardiansThreeStarred = 0,
    this.dailyCompleted = 0,
    this.dailyArchived = 0,
    this.bestPlayStreakDays = 0,
    this.bestJamFreeRun = 0,
    this.silhouetteFamilyMask = 0,
    this.directiveThreeStarMask = 0,
    this.flagsMask = 0,
  });

  /// Frontier level on the deepest of the three difficulty tracks.
  final int highestLevelAnyMode;

  /// How many of the three modes have reached level 50 / 200.
  final int modesAtLevel50;
  final int modesAtLevel200;

  /// Stars summed across Easy, Medium and Hard.
  final int totalStars;

  /// Nodes on boards that were *won*. A lost or abandoned level contributes
  /// nothing, even if most of its board was cleared.
  final int nodesCleared;

  final int coresExtracted;
  final int locksOpened;
  final int relaysCleared;
  final int phaseGatesCleared;
  final int portalsTraversed;

  /// Guardian (every 25th) levels cleared, summed across modes.
  final int guardiansCleared;

  /// Best count of 3-starred Guardians within any one sector, on any one mode.
  /// A sector holds five Guardians, so this saturates at 5.
  final int bestSectorGuardiansThreeStarred;

  final int dailyCompleted;

  /// Daily Challenges completed on a date later than the challenge's own.
  final int dailyArchived;

  /// Longest run of consecutive days with a completed level — best ever, not
  /// the current run, so breaking a streak never revokes a badge.
  final int bestPlayStreakDays;

  /// Longest run of consecutive jam-free wins, best ever.
  final int bestJamFreeRun;

  /// One bit per [SilhouetteVisualFamily].
  final int silhouetteFamilyMask;

  /// One bit per [LevelDirective], set when that directive was 3-starred.
  final int directiveThreeStarMask;

  /// See [AchievementFlag].
  final int flagsMask;

  bool hasFlag(int flag) => (flagsMask & flag) != 0;

  bool hasDirective(LevelDirective d) =>
      (directiveThreeStarMask & (1 << d.index)) != 0;

  /// Distinct silhouette families seen, 0–4.
  int get silhouetteFamilyCount => _popCount(silhouetteFamilyMask);

  /// Distinct directives 3-starred, 0–5.
  int get directiveCount => _popCount(directiveThreeStarMask);

  static int _popCount(int bits) {
    var n = 0;
    var v = bits;
    while (v != 0) {
      n += v & 1;
      v >>= 1;
    }
    return n;
  }
}
