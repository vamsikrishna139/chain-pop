import '../generation/archetype.dart';
import '../generation/diversity_ledger.dart';
import '../generation/level_seed.dart';
import '../generation/metrics.dart';
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
      };
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
}) {
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
  );
}
