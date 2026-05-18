import 'difficulty_mode.dart';
import 'metrics.dart';

/// Difficulty tier used by the Phase 2 evaluator.
///
/// Distinct from [DifficultyMode] because the plan adds an **Expert** tier
/// for Daily / Special puzzles that the existing `DifficultyMode` enum did
/// not need. Mapping helpers are below.
enum DifficultyTier { easy, medium, hard, expert }

/// Coarse shape of a level's [LevelMetrics.tempoProfile] (§6).
///
/// The evaluator uses these as soft targets — exact-shape matching is the
/// job of the post-Phase-3 director once it owns difficulty band selection.
enum TempoProfileShape {
  /// Flat — Easy levels. Few peaks, few troughs.
  relaxed,

  /// Slow rise from the opening to the midgame — Medium.
  mildRise,

  /// Rise then release — Hard. Memorable arc.
  dramatic,

  /// Sustained tightening to the finale — Expert / Daily.
  compression,
}

/// Inclusive numeric range used in the §6 band table.
class MetricRange<T extends num> {
  final T min;
  final T max;
  const MetricRange(this.min, this.max);

  bool contains(num value) => value >= min && value <= max;
}

/// §6 band specification for a single difficulty tier.
///
/// The plan's bands intentionally do not lock down everything in Phase 2 —
/// node count is still chosen by the legacy `LevelConfiguration` until the
/// Director arrives in Phase 3. [DifficultyProfile.passes] therefore checks
/// the per-step bands (BF, first-legal, CUD, FSR, wave depth) and the
/// FSR-vs-nodeCount cap, but does **not** reject a level for having an
/// out-of-band [LevelMetrics.nodeCount].
class DifficultyProfile {
  final DifficultyTier tier;
  final MetricRange<int> nodeCount;
  final MetricRange<int> waveDepth;
  final MetricRange<double> averageBranchingFactor;
  final MetricRange<int> firstLegalMoveCount;
  final MetricRange<int> criticalUnlockDepth;
  final MetricRange<double> forcedSequenceRatio;
  final TempoProfileShape tempoShape;

  const DifficultyProfile({
    required this.tier,
    required this.nodeCount,
    required this.waveDepth,
    required this.averageBranchingFactor,
    required this.firstLegalMoveCount,
    required this.criticalUnlockDepth,
    required this.forcedSequenceRatio,
    required this.tempoShape,
  });

  /// Hard cap on [LevelMetrics.forcedSequenceRatio] when [nodeCount] exceeds
  /// this threshold — §6 "FSR vs node-count cap". 28 in the plan.
  static const int fsrCapNodeThreshold = 28;

  /// Maximum [LevelMetrics.forcedSequenceRatio] permitted once
  /// `nodeCount > [fsrCapNodeThreshold]`, regardless of tier.
  static const double fsrCapValue = 0.40;

  /// §6 Easy band. Relaxed tempo (flat).
  static const DifficultyProfile easy = DifficultyProfile(
    tier: DifficultyTier.easy,
    nodeCount: MetricRange(8, 14),
    waveDepth: MetricRange(2, 3),
    averageBranchingFactor: MetricRange(5.0, 8.0),
    firstLegalMoveCount: MetricRange(5, 10),
    criticalUnlockDepth: MetricRange(1, 2),
    forcedSequenceRatio: MetricRange(0.0, 0.15),
    tempoShape: TempoProfileShape.relaxed,
  );

  /// §6 Medium band. Mild rise.
  static const DifficultyProfile medium = DifficultyProfile(
    tier: DifficultyTier.medium,
    nodeCount: MetricRange(14, 22),
    waveDepth: MetricRange(3, 5),
    averageBranchingFactor: MetricRange(3.0, 5.0),
    firstLegalMoveCount: MetricRange(3, 5),
    criticalUnlockDepth: MetricRange(2, 4),
    forcedSequenceRatio: MetricRange(0.15, 0.35),
    tempoShape: TempoProfileShape.mildRise,
  );

  /// §6 Hard band — softened per reviewer feedback (BF 2–4 not 1.5–3;
  /// FSR 20–40% not 35–60%). Dramatic tempo.
  static const DifficultyProfile hard = DifficultyProfile(
    tier: DifficultyTier.hard,
    nodeCount: MetricRange(20, 30),
    waveDepth: MetricRange(5, 8),
    averageBranchingFactor: MetricRange(2.0, 4.0),
    firstLegalMoveCount: MetricRange(1, 3),
    criticalUnlockDepth: MetricRange(4, 8),
    forcedSequenceRatio: MetricRange(0.20, 0.40),
    tempoShape: TempoProfileShape.dramatic,
  );

  /// §6 Expert / Daily band. Compression tempo.
  static const DifficultyProfile expert = DifficultyProfile(
    tier: DifficultyTier.expert,
    nodeCount: MetricRange(22, 32),
    waveDepth: MetricRange(6, 10),
    averageBranchingFactor: MetricRange(2.0, 4.0),
    firstLegalMoveCount: MetricRange(2, 4),
    criticalUnlockDepth: MetricRange(5, 10),
    forcedSequenceRatio: MetricRange(0.25, 0.40),
    tempoShape: TempoProfileShape.compression,
  );

  /// Tier lookup.
  static DifficultyProfile forTier(DifficultyTier tier) {
    switch (tier) {
      case DifficultyTier.easy:
        return easy;
      case DifficultyTier.medium:
        return medium;
      case DifficultyTier.hard:
        return hard;
      case DifficultyTier.expert:
        return expert;
    }
  }

  /// Map [DifficultyMode] to the matching tier. Daily/Special callers should
  /// pass [DifficultyTier.expert] explicitly instead.
  static DifficultyTier tierFromMode(DifficultyMode mode) {
    switch (mode) {
      case DifficultyMode.easy:
        return DifficultyTier.easy;
      case DifficultyMode.medium:
        return DifficultyTier.medium;
      case DifficultyMode.hard:
        return DifficultyTier.hard;
    }
  }

  /// True iff [metrics] satisfies this tier's per-step bands AND the
  /// universal FSR-vs-nodeCount cap. Node count itself is *not* checked here
  /// because Phase 2 still gets `targetNodeCount` from the legacy
  /// `LevelConfiguration`; the Director takes that over in Phase 3.
  bool passes(LevelMetrics metrics) {
    if (!averageBranchingFactor.contains(metrics.averageBranchingFactor)) {
      return false;
    }
    if (!firstLegalMoveCount.contains(metrics.firstLegalMoveCount)) {
      return false;
    }
    if (!criticalUnlockDepth.contains(metrics.criticalUnlockDepth)) {
      return false;
    }
    if (!forcedSequenceRatio.contains(metrics.forcedSequenceRatio)) {
      return false;
    }
    if (!waveDepth.contains(metrics.waveDepth)) return false;
    if (metrics.nodeCount > fsrCapNodeThreshold &&
        metrics.forcedSequenceRatio > fsrCapValue) {
      return false;
    }
    return true;
  }

  /// True iff [metrics] satisfies the FSR cap rule. Useful as a standalone
  /// gate even when the full per-tier band check would be too strict.
  static bool passesFsrCap(LevelMetrics metrics) {
    if (metrics.nodeCount <= fsrCapNodeThreshold) return true;
    return metrics.forcedSequenceRatio <= fsrCapValue;
  }
}
