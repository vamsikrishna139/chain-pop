import 'dart:math';

import 'difficulty_mode.dart';
import 'dependency_graph.dart';
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

/// Target shape for a level's temporal arc (opening → crunch → release).
class TemporalArcSpec {
  final MetricRange<int> openingMoves;
  final MetricRange<int> crunchMoves;
  final MetricRange<int> releasePeak;

  const TemporalArcSpec({
    required this.openingMoves,
    required this.crunchMoves,
    required this.releasePeak,
  });
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

  /// Optional temporal-arc targets; populated on Hard (Tier 2+ validation).
  final TemporalArcSpec? arcSpec;

  const DifficultyProfile({
    required this.tier,
    required this.nodeCount,
    required this.waveDepth,
    required this.averageBranchingFactor,
    required this.firstLegalMoveCount,
    required this.criticalUnlockDepth,
    required this.forcedSequenceRatio,
    required this.tempoShape,
    this.arcSpec,
  });

  /// Threshold above which the node-banded FSR cap begins to apply.
  /// Below this node count, FSR is uncapped (tier bands still apply).
  static const int fsrCapNodeThreshold = 28;

  /// FSR cap at exactly [fsrCapNodeThreshold] nodes — the gentle end.
  static const double fsrCapAtThreshold = 0.65;

  /// FSR cap at [fsrCapNodeCeiling] nodes — the strict end.
  static const double fsrCapAtCeiling = 0.35;

  /// Node count at which the FSR cap reaches its minimum ([fsrCapAtCeiling]).
  static const int fsrCapNodeCeiling = 55;

  /// Returns the maximum allowed FSR for a given [nodeCount].
  ///
  /// Below [fsrCapNodeThreshold] the cap is effectively infinite (returns 1.0).
  /// Between threshold and ceiling the cap interpolates linearly from
  /// [fsrCapAtThreshold] (0.65) down to [fsrCapAtCeiling] (0.35).
  /// Above the ceiling the cap stays at [fsrCapAtCeiling].
  static double fsrCapForNodeCount(int nodeCount) {
    if (nodeCount <= fsrCapNodeThreshold) return 1.0;
    if (nodeCount >= fsrCapNodeCeiling) return fsrCapAtCeiling;
    final t = (nodeCount - fsrCapNodeThreshold) /
        (fsrCapNodeCeiling - fsrCapNodeThreshold);
    return fsrCapAtThreshold + (fsrCapAtCeiling - fsrCapAtThreshold) * t;
  }

  /// Honest Hard/Expert opening band (first legal moves / wave-zero width).
  ///
  /// Recalibrated from the original `[3, 5]` target after Phase B proved
  /// that ≤5 is structurally unreachable with retrograde construction:
  /// ray-free nodes can only be capped by lower-id blockers, but low ids are
  /// placed last and rarely land on the needed rays (geometric starvation).
  /// Measured Hard/Daily openings cluster at ~8–11; see
  /// `docs/OPENING_BAND_DECISION.md`.
  static const MetricRange<int> hardExpertOpeningBand = MetricRange(3, 11);

  /// Soft topology targets for Hard-band candidate ranking (B3).
  static const MetricRange<int> hardChokePointBand = MetricRange(1, 2);

  /// Preferred hub fan-in window for Hard levels.
  static const MetricRange<int> hardHubInDegreeBand = MetricRange(2, 4);

  /// §6 Easy band. Relaxed tempo (flat).
  static const DifficultyProfile easy = DifficultyProfile(
    tier: DifficultyTier.easy,
    nodeCount: MetricRange(8, 14),
    waveDepth: MetricRange(2, 4),
    averageBranchingFactor: MetricRange(5.0, 8.0),
    firstLegalMoveCount: MetricRange(7, 11),
    criticalUnlockDepth: MetricRange(2, 5),
    forcedSequenceRatio: MetricRange(0.25, 0.65),
    tempoShape: TempoProfileShape.relaxed,
  );

  /// §6 Medium band. Mild rise.
  static const DifficultyProfile medium = DifficultyProfile(
    tier: DifficultyTier.medium,
    nodeCount: MetricRange(14, 22),
    waveDepth: MetricRange(3, 5),
    averageBranchingFactor: MetricRange(3.0, 8.0),
    firstLegalMoveCount: MetricRange(4, 11),
    criticalUnlockDepth: MetricRange(3, 8),
    forcedSequenceRatio: MetricRange(0.35, 0.65),
    tempoShape: TempoProfileShape.mildRise,
  );

  /// §6 Hard band — organic crunch sweet spot.
  ///
  /// Node max trimmed from 50 → 42 to stay within comfortable FSR headroom
  /// against the node-banded cap (cap at 42 ≈ 0.505, floor 0.45).
  static const DifficultyProfile hard = DifficultyProfile(
    tier: DifficultyTier.hard,
    nodeCount: MetricRange(25, 42),
    waveDepth: MetricRange(5, 8),
    averageBranchingFactor: MetricRange(3.0, 8.0),
    firstLegalMoveCount: hardExpertOpeningBand,
    criticalUnlockDepth: MetricRange(5, 12),
    forcedSequenceRatio: MetricRange(0.45, 0.90),
    tempoShape: TempoProfileShape.dramatic,
    arcSpec: TemporalArcSpec(
      openingMoves: MetricRange(4, 10),
      crunchMoves: MetricRange(2, 5),
      releasePeak: MetricRange(5, 12),
    ),
  );

  /// §6 Expert / Daily band. Compression tempo.
  ///
  /// Node max trimmed from 55 → 39 to stay within comfortable FSR headroom
  /// against the node-banded cap (cap at 39 ≈ 0.528, floor 0.50).
  static const DifficultyProfile expert = DifficultyProfile(
    tier: DifficultyTier.expert,
    nodeCount: MetricRange(28, 39),
    waveDepth: MetricRange(6, 10),
    averageBranchingFactor: MetricRange(3.0, 9.0),
    firstLegalMoveCount: hardExpertOpeningBand,
    criticalUnlockDepth: MetricRange(6, 14),
    forcedSequenceRatio: MetricRange(0.50, 0.85),
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
    if (metrics.forcedSequenceRatio > fsrCapForNodeCount(metrics.nodeCount)) {
      return false;
    }
    if (tier == DifficultyTier.hard || tier == DifficultyTier.expert) {
      final w0 = metrics.waveZeroWidth;
      if (!hardExpertOpeningBand.contains(w0)) return false;
    }

    // Temporary: Disable temporal arc enforcement until wave profile pacing is calibrated by human playtesting.
    // if ((tier == DifficultyTier.hard || tier == DifficultyTier.expert) &&
    //     metrics.tempoProfile.isNotEmpty &&
    //     !passesTemporalArc(metrics.tempoProfile)) {
    //   return false;
    // }
    return true;
  }

  /// Validates flow → crunch → release segments on [tempoProfile].
  bool passesTemporalArc(List<int> tempoProfile) {
    final spec = arcSpec;
    if (spec == null || tempoProfile.isEmpty) return true;
    if (tempoProfile.length < 10) return false;

    final n = tempoProfile.length;
    final openEnd = max(1, (n * 0.20).ceil());
    final openAvg = _avg(tempoProfile.sublist(0, openEnd));
    if (openAvg < spec.openingMoves.min || openAvg > 12) return false;

    final crunchStart = (n * 0.35).floor();
    final crunchEnd = min(n, max(crunchStart + 1, (n * 0.65).ceil()));
    final crunchSegment = tempoProfile.sublist(crunchStart, crunchEnd);
    if (crunchSegment.isEmpty) return false;
    final crunchMin = crunchSegment.reduce((a, b) => a < b ? a : b);
    if (crunchMin > spec.crunchMoves.max) return false;

    if (crunchEnd < n) {
      final releaseSegment = tempoProfile.sublist(crunchEnd);
      final releaseMax =
          releaseSegment.reduce((a, b) => a > b ? a : b);
      if (releaseMax < spec.releasePeak.min) return false;
    }
    return true;
  }

  /// Score for in-band ranking — higher is a better temporal arc fit.
  double temporalArcScore(List<int> tempoProfile) {
    final spec = arcSpec;
    if (spec == null || tempoProfile.isEmpty) return 0;
    if (!passesTemporalArc(tempoProfile)) return 0;

    final n = tempoProfile.length;
    final openEnd = max(1, (n * 0.20).ceil());
    final openAvg = _avg(tempoProfile.sublist(0, openEnd));
    final openTarget = (spec.openingMoves.min + spec.openingMoves.max) / 2;
    final openScore = 1.0 - (openAvg - openTarget).abs() / 8.0;

    final crunchStart = (n * 0.35).floor();
    final crunchEnd = min(n, max(crunchStart + 1, (n * 0.65).ceil()));
    final crunchSegment = tempoProfile.sublist(crunchStart, crunchEnd);
    final crunchFsr = crunchSegment.where((m) => m == 1).length /
        crunchSegment.length;

    var releaseScore = 0.0;
    if (crunchEnd < n) {
      final releaseMax = tempoProfile
          .sublist(crunchEnd)
          .reduce((a, b) => a > b ? a : b);
      releaseScore = releaseMax / spec.releasePeak.max;
    }

    return openScore.clamp(0.0, 1.0) +
        crunchFsr +
        releaseScore.clamp(0.0, 1.0);
  }

  /// Midgame forced-sequence share (35–65% window) for in-band ranking.
  static double midgameFsr(List<int> tempoProfile) {
    if (tempoProfile.length < 4) return 0;
    final n = tempoProfile.length;
    final start = (n * 0.35).floor();
    final end = min(n, max(start + 1, (n * 0.65).ceil()));
    final segment = tempoProfile.sublist(start, end);
    if (segment.isEmpty) return 0;
    return segment.where((m) => m == 1).length / segment.length;
  }

  /// Soft topology preference for Hard/Expert in-band ranking (B3).
  ///
  /// Rewards 1–2 choke points, in-band critical paths, and controlled hub
  /// fan-in. Not a hard gate — used only for candidate ordering.
  double topologySoftScore({
    required int chokePointCount,
    required int criticalPathLength,
    required int maxHubInDegree,
  }) {
    if (tier != DifficultyTier.hard && tier != DifficultyTier.expert) {
      return 0;
    }

    var score = 0.0;

    if (hardChokePointBand.contains(chokePointCount)) {
      score += 2.0 - (chokePointCount - 1.5).abs() * 0.5;
    } else if (chokePointCount == 0) {
      score -= 0.5;
    } else if (chokePointCount > hardChokePointBand.max) {
      score -= (chokePointCount - hardChokePointBand.max) * 0.25;
    }

    if (criticalUnlockDepth.contains(criticalPathLength)) {
      score += 1.0;
      final target =
          (criticalUnlockDepth.min + criticalUnlockDepth.max) / 2.0;
      score += 0.3 *
          (1.0 - (criticalPathLength - target).abs() /
              (criticalUnlockDepth.max - criticalUnlockDepth.min + 1));
    }

    if (hardHubInDegreeBand.contains(maxHubInDegree)) {
      score += 1.0;
    } else if (maxHubInDegree > hardHubInDegreeBand.max) {
      score -= (maxHubInDegree - hardHubInDegreeBand.max) * 0.3;
    }

    return score;
  }

  /// Convenience wrapper over a [DependencyGraph].
  double topologySoftScoreFromGraph(DependencyGraph graph) {
    return topologySoftScore(
      chokePointCount: graph.chokePointCount,
      criticalPathLength: graph.criticalPathLength,
      maxHubInDegree: graph.maxHubInDegree,
    );
  }

  /// Convenience wrapper over [LevelMetrics] topology fields.
  double topologySoftScoreFromMetrics(LevelMetrics metrics) {
    return topologySoftScore(
      chokePointCount: metrics.chokePointCount,
      criticalPathLength: metrics.criticalUnlockDepth,
      maxHubInDegree: metrics.maxHubInDegree,
    );
  }


  static double _avg(List<int> values) {
    if (values.isEmpty) return 0;
    return values.fold<int>(0, (a, b) => a + b) / values.length;
  }

  /// True iff [metrics] satisfies the node-banded FSR cap rule.
  /// Useful as a standalone gate even when the full per-tier band check
  /// would be too strict.
  static bool passesFsrCap(LevelMetrics metrics) {
    return metrics.forcedSequenceRatio <= fsrCapForNodeCount(metrics.nodeCount);
  }
}
