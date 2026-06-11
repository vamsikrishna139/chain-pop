import '../generation/archetype.dart';
import '../generation/diversity_ledger.dart';
import '../generation/level_seed.dart';
import '../generation/metrics.dart';
import '../generation/motifs.dart';
import '../generation/silhouettes.dart';
import '../level.dart';

/// Phase 6 §9 — *lightweight* analytics.
///
/// Per the v2 plan, this layer is **emit-only**: it builds a structured
/// event per shipped level and per-attempt telemetry snapshots, then hands
/// the payload to whichever sink the host app already runs. There is no
/// remote-config weights endpoint, no server-side job runner, no live
/// dashboarding — those were explicitly deferred to keep this from becoming
/// a multi-week backend project.
///
/// Two payload types ship:
///   * [GenerationEmissionEvent] — one per shipped level (success path).
///   * [GenerationSessionSnapshot] — one per `LevelGenerator.generate` call
///     once it returns, capturing the cumulative counters since the last
///     reset. Useful for "QA breakdown by archetype" reports.
class GenerationEmissionEvent {
  /// Stable id for the emitted level (the [LevelData.levelId]).
  final int levelId;

  /// Archetype that produced this level.
  final GenerationArchetype archetype;

  /// Silhouette family the Director / seed used.
  final SilhouetteId silhouette;

  /// Seed id when the level was hand-pinned, otherwise null.
  final String? seedId;

  /// Whether the level passed the §6 in-band check on its primary attempt.
  final bool inBand;

  /// Whether the diversity-ledger considered the fingerprint novel.
  final bool novelFingerprint;

  /// Logic / tempo / uniqueness metrics computed once before emit.
  final LevelMetrics metrics;

  /// 23-bit fingerprint that landed in the diversity ledger window.
  final LevelFingerprint fingerprint;

  /// Number of Director Renegotiations consumed before this emission.
  final int renegotiations;

  /// Primary visible motif on the shipped level, if any.
  final MotifId? dominantMotifId;

  /// True when a [MotifId.lockCluster] block survived construction.
  final bool lockClusterPlaced;

  /// [LevelMetrics.criticalUnlockDepth] when [lockClusterPlaced] is true.
  final int clusterCud;

  /// Per-shipped-level construction telemetry (not K-loop cumulative).
  final int crunchPick;
  final int blkOffered;
  final int blkPicked;
  final int solvabilityRetries;
  final int? winRetry;

  /// Ray-dependency topology on the shipped board.
  final int chainDepthMax;
  final int maxHubInDegree;
  final double avgUnlockFanout;
  final bool pathsCapped;

  const GenerationEmissionEvent({
    required this.levelId,
    required this.archetype,
    required this.silhouette,
    required this.seedId,
    required this.inBand,
    required this.novelFingerprint,
    required this.metrics,
    required this.fingerprint,
    required this.renegotiations,
    this.dominantMotifId,
    this.lockClusterPlaced = false,
    this.clusterCud = 0,
    this.crunchPick = 0,
    this.blkOffered = 0,
    this.blkPicked = 0,
    this.solvabilityRetries = 0,
    this.winRetry,
    this.chainDepthMax = 0,
    this.maxHubInDegree = 0,
    this.avgUnlockFanout = 0,
    this.pathsCapped = false,
  });

  /// Plain-old map suitable for sending to any flat-payload sink (Firebase
  /// Analytics, Amplitude, an in-process collector, etc.).
  Map<String, Object?> toMap() => <String, Object?>{
        'levelId': levelId,
        'archetype': archetype.name,
        'silhouette': silhouette.name,
        'seedId': seedId,
        'inBand': inBand,
        'novelFingerprint': novelFingerprint,
        'renegotiations': renegotiations,
        'metrics.nodeCount': metrics.nodeCount,
        'metrics.waveDepth': metrics.waveDepth,
        'metrics.averageBranchingFactor':
            metrics.averageBranchingFactor.toStringAsFixed(3),
        'metrics.firstLegalMoveCount': metrics.firstLegalMoveCount,
        'metrics.criticalUnlockDepth': metrics.criticalUnlockDepth,
        'metrics.forcedSequenceRatio':
            metrics.forcedSequenceRatio.toStringAsFixed(3),
        'metrics.frontierVariance':
            metrics.frontierVariance.toStringAsFixed(3),
        'metrics.viablePathCount': metrics.viablePathCount,
        'fingerprint.bits': fingerprint.bits,
        'dominantMotifId': dominantMotifId?.name,
        'lockClusterPlaced': lockClusterPlaced,
        'clusterCud': clusterCud,
        'crunchPick': crunchPick,
        'blkOffered': blkOffered,
        'blkPicked': blkPicked,
        'solvabilityRetries': solvabilityRetries,
        'winRetry': winRetry,
        'topology.chainDepthMax': chainDepthMax,
        'topology.maxHubInDegree': maxHubInDegree,
        'topology.avgUnlockFanout':
            avgUnlockFanout.toStringAsFixed(2),
        'topology.pathsCapped': pathsCapped,
      };
}

/// Construction telemetry from a single retrograde build (one K-loop winner).
class ConstructionTelemetry {
  final int blockingDirCandidatesOffered;
  final int blockingDirCandidatesPicked;
  final int crunchZoneBlockingPicked;
  final int releaseZoneFallbackPicked;
  final int constructionSolvabilityRetries;
  final int? winningBlockingRetryIndex;

  const ConstructionTelemetry({
    this.blockingDirCandidatesOffered = 0,
    this.blockingDirCandidatesPicked = 0,
    this.crunchZoneBlockingPicked = 0,
    this.releaseZoneFallbackPicked = 0,
    this.constructionSolvabilityRetries = 0,
    this.winningBlockingRetryIndex,
  });

  static const ConstructionTelemetry zero = ConstructionTelemetry();
}

/// Cumulative session snapshot. The host app can poll this every N levels
/// to drive the weekly QA-by-archetype report without storing every event.
class GenerationSessionSnapshot {
  final int retrogradeAttempts;
  final int retrogradeInBandSuccesses;
  final int retrogradeOutOfBandSuccesses;
  final int evaluatorRejections;
  final int diversityRejections;
  final int legacyAttempts;
  final int renegotiations;
  final int monotoneFallbackHits;
  final Map<GenerationArchetype, int> archetypeEmissions;
  final Map<String, int> seedEmissions;
  final int strongMotifEmissions;
  final int strongMotifEmissionsWithMotif;
  final int blockingDirCandidatesOffered;
  final int blockingDirCandidatesPicked;
  final int crunchZoneBlockingPicked;
  final int releaseZoneFallbackPicked;
  final int constructionSolvabilityRetries;
  final int winningBlockingRetryIndex0;
  final int winningBlockingRetryIndex1;
  final int winningBlockingRetryIndex2;
  final int maxAttemptsExhaustedCount;
  final int rejectAspectCount;
  final int rejectOccupancyCount;
  final int rejectComponentsCount;
  final int rejectSingletonCount;
  final int rejectBlobVsGridCount;

  const GenerationSessionSnapshot({
    required this.retrogradeAttempts,
    required this.retrogradeInBandSuccesses,
    required this.retrogradeOutOfBandSuccesses,
    required this.evaluatorRejections,
    required this.diversityRejections,
    required this.legacyAttempts,
    required this.renegotiations,
    required this.monotoneFallbackHits,
    required this.archetypeEmissions,
    required this.seedEmissions,
    required this.strongMotifEmissions,
    required this.strongMotifEmissionsWithMotif,
    this.blockingDirCandidatesOffered = 0,
    this.blockingDirCandidatesPicked = 0,
    this.crunchZoneBlockingPicked = 0,
    this.releaseZoneFallbackPicked = 0,
    this.constructionSolvabilityRetries = 0,
    this.winningBlockingRetryIndex0 = 0,
    this.winningBlockingRetryIndex1 = 0,
    this.winningBlockingRetryIndex2 = 0,
    this.maxAttemptsExhaustedCount = 0,
    this.rejectAspectCount = 0,
    this.rejectOccupancyCount = 0,
    this.rejectComponentsCount = 0,
    this.rejectSingletonCount = 0,
    this.rejectBlobVsGridCount = 0,
  });

  /// Convenience: motif visibility rate for the Strong-Motif archetype.
  /// Returns `null` when no Strong-Motif emissions have occurred yet.
  double? get strongMotifVisibilityRate {
    if (strongMotifEmissions == 0) return null;
    return strongMotifEmissionsWithMotif / strongMotifEmissions;
  }

  /// Total emitted levels.
  int get totalEmissions =>
      archetypeEmissions.values.fold<int>(0, (a, b) => a + b);

  Map<String, Object?> toMap() => <String, Object?>{
        'retrogradeAttempts': retrogradeAttempts,
        'retrogradeInBandSuccesses': retrogradeInBandSuccesses,
        'retrogradeOutOfBandSuccesses': retrogradeOutOfBandSuccesses,
        'evaluatorRejections': evaluatorRejections,
        'diversityRejections': diversityRejections,
        'legacyAttempts': legacyAttempts,
        'renegotiations': renegotiations,
        'monotoneFallbackHits': monotoneFallbackHits,
        'totalEmissions': totalEmissions,
        'archetypeEmissions': {
          for (final e in archetypeEmissions.entries) e.key.name: e.value,
        },
        'seedEmissions': seedEmissions,
        'strongMotifEmissions': strongMotifEmissions,
        'strongMotifEmissionsWithMotif': strongMotifEmissionsWithMotif,
        'strongMotifVisibilityRate': strongMotifVisibilityRate,
        'blockingDirCandidatesOffered': blockingDirCandidatesOffered,
        'blockingDirCandidatesPicked': blockingDirCandidatesPicked,
        'crunchZoneBlockingPicked': crunchZoneBlockingPicked,
        'releaseZoneFallbackPicked': releaseZoneFallbackPicked,
        'constructionSolvabilityRetries': constructionSolvabilityRetries,
        'winningBlockingRetryIndex0': winningBlockingRetryIndex0,
        'winningBlockingRetryIndex1': winningBlockingRetryIndex1,
        'winningBlockingRetryIndex2': winningBlockingRetryIndex2,
        'maxAttemptsExhaustedCount': maxAttemptsExhaustedCount,
        'rejectAspectCount': rejectAspectCount,
        'rejectOccupancyCount': rejectOccupancyCount,
        'rejectComponentsCount': rejectComponentsCount,
        'rejectSingletonCount': rejectSingletonCount,
        'rejectBlobVsGridCount': rejectBlobVsGridCount,
      };
}

/// Lightweight sink. Implementers forward to whatever the host app uses
/// (Firebase, Amplitude, a custom collector, a file, …). Default
/// implementation is no-op — callers explicitly opt in.
abstract class GenerationAnalyticsSink {
  void emit(GenerationEmissionEvent event);
  void snapshot(GenerationSessionSnapshot snapshot);
}

/// No-op sink. Returned by `noopSink()` for default-construction sites.
class _NoopSink implements GenerationAnalyticsSink {
  const _NoopSink();
  @override
  void emit(GenerationEmissionEvent event) {}
  @override
  void snapshot(GenerationSessionSnapshot snapshot) {}
}

const GenerationAnalyticsSink noopAnalyticsSink = _NoopSink();

/// In-memory sink — collects events for inspection in tests + ad-hoc
/// debugging. Not for production (the list grows unboundedly).
class InMemoryAnalyticsSink implements GenerationAnalyticsSink {
  final List<GenerationEmissionEvent> events = <GenerationEmissionEvent>[];
  final List<GenerationSessionSnapshot> snapshots =
      <GenerationSessionSnapshot>[];

  @override
  void emit(GenerationEmissionEvent event) => events.add(event);

  @override
  void snapshot(GenerationSessionSnapshot snapshot) =>
      snapshots.add(snapshot);

  /// Convenience for ad-hoc inspection / reports.
  Map<GenerationArchetype, double> archetypeInBandRate() {
    final byArchetype = <GenerationArchetype, List<GenerationEmissionEvent>>{};
    for (final e in events) {
      byArchetype.putIfAbsent(e.archetype, () => []).add(e);
    }
    return {
      for (final entry in byArchetype.entries)
        entry.key: entry.value.where((e) => e.inBand).length /
            entry.value.length,
    };
  }
}

/// Helper that builds a [GenerationEmissionEvent] from the bits the
/// `LevelGenerator` already has at emission time. Kept here (rather than
/// inlined in the generator) so the generator stays free of analytics
/// formatting details.
GenerationEmissionEvent buildEmissionEvent({
  required LevelData level,
  required GenerationArchetype archetype,
  required SilhouetteId silhouette,
  required LevelSeed? seed,
  required bool inBand,
  required bool novelFingerprint,
  required LevelMetrics metrics,
  required LevelFingerprint fingerprint,
  required int renegotiations,
  List<MotifId> visibleMotifs = const [],
  ConstructionTelemetry construction = ConstructionTelemetry.zero,
  int chainDepthMax = 0,
  int maxHubInDegree = 0,
  double avgUnlockFanout = 0,
  bool pathsCapped = false,
}) {
  final dominant =
      visibleMotifs.isEmpty ? null : visibleMotifs.first;
  final lockCluster = visibleMotifs.contains(MotifId.lockCluster);
  return GenerationEmissionEvent(
    levelId: level.levelId,
    archetype: archetype,
    silhouette: silhouette,
    seedId: seed?.id,
    inBand: inBand,
    novelFingerprint: novelFingerprint,
    metrics: metrics,
    fingerprint: fingerprint,
    renegotiations: renegotiations,
    dominantMotifId: dominant,
    lockClusterPlaced: lockCluster,
    clusterCud: lockCluster ? metrics.criticalUnlockDepth : 0,
    crunchPick: construction.crunchZoneBlockingPicked,
    blkOffered: construction.blockingDirCandidatesOffered,
    blkPicked: construction.blockingDirCandidatesPicked,
    solvabilityRetries: construction.constructionSolvabilityRetries,
    winRetry: construction.winningBlockingRetryIndex,
    chainDepthMax: chainDepthMax,
    maxHubInDegree: maxHubInDegree,
    avgUnlockFanout: avgUnlockFanout,
    pathsCapped: pathsCapped,
  );
}
