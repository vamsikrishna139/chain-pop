import 'metrics.dart';
import '../level.dart';

/// §4.6 / Phase 7 — MAP-Elites support.
///
/// The runtime generator already produces thousands of varied levels; this
/// archive is the **content-volume tool** the plan defers to Phase 7. It is
/// built **offline** (`tools/map_elites_runner.dart`) and ships as a JSON
/// asset under `assets/level_banks/`. Daily / Specials sample by date /
/// curated slice from the loaded archive.
///
/// The feature grid is `(waveDepth × avgBranchingFactor)` per §9 Phase 7.
/// We expose the bucketing helpers + composite quality score so the
/// offline runner and the unit tests stay in sync.

/// Bucketing — feature space layout.
class MapElitesFeature {
  /// Wave-depth bucketing: 0..7 → wave depth 1..2, 3, 4, 5, 6, 7, 8, ≥ 9.
  static int waveDepthBucket(int waveDepth) {
    if (waveDepth <= 2) return 0;
    if (waveDepth >= 9) return 7;
    return waveDepth - 2;
  }

  static const int waveDepthBucketCount = 8;

  /// Avg-BF bucketing: 0..5 → BF < 1.5, 1.5..2.0, 2.0..2.5, 2.5..3.0,
  /// 3.0..3.5, ≥ 3.5.
  static int avgBranchingFactorBucket(double avgBf) {
    if (avgBf < 1.5) return 0;
    if (avgBf >= 3.5) return 5;
    return ((avgBf - 1.5) / 0.5).floor().clamp(0, 4) + 1;
  }

  static const int avgBranchingFactorBucketCount = 6;

  /// Total cell count = `waveDepthBucketCount * avgBranchingFactorBucketCount`.
  static int get totalCells =>
      waveDepthBucketCount * avgBranchingFactorBucketCount;

  /// Flat `cellId` for the (waveBucket, bfBucket) pair.
  static int cellId(int waveBucket, int bfBucket) =>
      waveBucket * avgBranchingFactorBucketCount + bfBucket;

  /// Inverse of [cellId].
  static (int wave, int bf) decodeCell(int cellId) => (
        cellId ~/ avgBranchingFactorBucketCount,
        cellId % avgBranchingFactorBucketCount,
      );
}

/// Composite quality score (§9 Phase 7 "composite quality score").
/// Mixes evaluator-level hits + tempo smoothness + uniqueness signal.
/// Values land roughly in `[0, 1]`; ties are broken by raw branching
/// factor (the offline runner saves only the best per cell).
double mapElitesQualityScore(LevelMetrics m) {
  // Pieces:
  //  1. tempo smoothness (penalise levels whose pacing curve cliffs).
  //  2. uniqueness signal — viablePathCount > 1 indicates non-degenerate.
  //  3. legal-move opener — first-legal-move count of 2..5 is good.
  //  4. forced-sequence ratio — penalise extremes (too forced / too open).
  final tempoTerm = m.tempoProfile.isEmpty
      ? 0.5
      : 1.0 - _tempoVolatility(m.tempoProfile).clamp(0.0, 1.0);
  final pathTerm = m.viablePathCount > 1 ? 1.0 : 0.4;
  final openerTerm = (m.firstLegalMoveCount >= 2 && m.firstLegalMoveCount <= 5)
      ? 1.0
      : 0.5;
  final fsr = m.forcedSequenceRatio;
  final fsrTerm = 1.0 - (fsr - 0.25).abs().clamp(0.0, 0.5) * 2;
  return (0.30 * tempoTerm) +
      (0.25 * pathTerm) +
      (0.20 * openerTerm) +
      (0.25 * fsrTerm);
}

double _tempoVolatility(List<int> profile) {
  if (profile.length < 2) return 0.0;
  var total = 0.0;
  for (var i = 1; i < profile.length; i++) {
    total += (profile[i] - profile[i - 1]).abs();
  }
  return total / (profile.length - 1) / 5.0;
}

/// One entry in the archive — the level + its bucket + the quality score.
class MapElitesEntry {
  final int waveBucket;
  final int bfBucket;
  final double qualityScore;
  final LevelData level;
  const MapElitesEntry({
    required this.waveBucket,
    required this.bfBucket,
    required this.qualityScore,
    required this.level,
  });

  int get cellId => MapElitesFeature.cellId(waveBucket, bfBucket);
}

/// Immutable in-memory archive (built offline; loaded at runtime by
/// `LevelBank`). The runtime never mutates the archive; new candidates land
/// in the offline runner.
class MapElitesArchive {
  final int version;
  final Map<int, MapElitesEntry> _entriesByCell;

  const MapElitesArchive._({
    required this.version,
    required Map<int, MapElitesEntry> entriesByCell,
  }) : _entriesByCell = entriesByCell;

  factory MapElitesArchive.empty({int version = 1}) =>
      MapElitesArchive._(version: version, entriesByCell: const {});

  factory MapElitesArchive.fromEntries(List<MapElitesEntry> entries,
      {int version = 1}) {
    final byCell = <int, MapElitesEntry>{};
    for (final e in entries) {
      final existing = byCell[e.cellId];
      if (existing == null || e.qualityScore > existing.qualityScore) {
        byCell[e.cellId] = e;
      }
    }
    return MapElitesArchive._(version: version, entriesByCell: byCell);
  }

  /// Returns the populated cells, in insertion order.
  Iterable<MapElitesEntry> get entries => _entriesByCell.values;

  int get length => _entriesByCell.length;
  bool get isEmpty => _entriesByCell.isEmpty;

  /// Coverage = populated cells ÷ feature grid size. The Phase 7 acceptance
  /// target is ≥ 0.80.
  double get coverage =>
      _entriesByCell.length / MapElitesFeature.totalCells.toDouble();

  /// Returns the entry at [cellId] or null when the cell hasn't been filled
  /// by the offline runner.
  MapElitesEntry? entryForCell(int cellId) => _entriesByCell[cellId];

  /// Picks a deterministic entry for [dayKey] — used by Daily. Falls back
  /// to the nearest populated cell when the hash lands on an empty one so
  /// the player never sees "no level".
  MapElitesEntry? pickForDailyKey(int dayKey) {
    if (_entriesByCell.isEmpty) return null;
    final keys = _entriesByCell.keys.toList()..sort();
    final idx = dayKey.abs() % keys.length;
    return _entriesByCell[keys[idx]];
  }
}
