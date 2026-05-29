import 'dart:math';

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
  static const DifficultyProfile hard = DifficultyProfile(
    tier: DifficultyTier.hard,
    nodeCount: MetricRange(25, 50),
    waveDepth: MetricRange(5, 8),
    averageBranchingFactor: MetricRange(3.0, 8.0),
    firstLegalMoveCount: MetricRange(4, 10),
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
  static const DifficultyProfile expert = DifficultyProfile(
    tier: DifficultyTier.expert,
    // Widened for 70–80% silhouette fill on Daily / Expert boards.
    nodeCount: MetricRange(28, 55),
    waveDepth: MetricRange(6, 10),
    averageBranchingFactor: MetricRange(3.0, 9.0),
    firstLegalMoveCount: MetricRange(4, 15),
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
    if (metrics.nodeCount > fsrCapNodeThreshold &&
        metrics.forcedSequenceRatio > fsrCapValue) {
      return false;
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

  static bool _matchesTempoShape(
    List<int> tempo,
    TempoProfileShape shape,
  ) {
    if (tempo.length < 4) return true;
    switch (shape) {
      case TempoProfileShape.relaxed:
      case TempoProfileShape.mildRise:
        return true;
      case TempoProfileShape.dramatic:
        final n = tempo.length;
        final midStart = max(1, n ~/ 4);
        final midEnd = max(midStart + 1, (3 * n) ~/ 4);
        final lastStart = max(midEnd, (4 * n) ~/ 5);
        final openAvg = _avg(tempo.sublist(0, midStart));
        final midPeak =
            tempo.sublist(midStart, midEnd).reduce((a, b) => a > b ? a : b);
        final lastAvg = _avg(tempo.sublist(lastStart));
        return midPeak > openAvg &&
            midPeak > lastAvg &&
            lastAvg <= openAvg + 0.5;
      case TempoProfileShape.compression:
        final n = tempo.length;
        final half = max(1, n ~/ 2);
        final firstHalf = _avg(tempo.sublist(0, half));
        final secondHalf = _avg(tempo.sublist(half));
        if (secondHalf >= firstHalf - 0.25) return false;
        final openEnd = max(1, n ~/ 5);
        final openSlice = tempo.sublist(0, openEnd);
        if (openSlice.length > 1) {
          final spread =
              openSlice.reduce((a, b) => a > b ? a : b) -
                  openSlice.reduce((a, b) => a < b ? a : b);
          if (spread <= 0 && firstHalf - secondHalf < 1.0) return false;
        }
        return true;
    }
  }

  static double _avg(List<int> values) {
    if (values.isEmpty) return 0;
    return values.fold<int>(0, (a, b) => a + b) / values.length;
  }

  /// True iff [metrics] satisfies the FSR cap rule. Useful as a standalone
  /// gate even when the full per-tier band check would be too strict.
  static bool passesFsrCap(LevelMetrics metrics) {
    if (metrics.nodeCount <= fsrCapNodeThreshold) return true;
    return metrics.forcedSequenceRatio <= fsrCapValue;
  }
}
