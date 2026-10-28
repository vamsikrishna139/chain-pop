import 'dart:collection';

import '../level.dart';
import 'difficulty_profile.dart';
import 'metrics.dart';
import 'motifs.dart';
import 'silhouettes.dart';

/// Diversity Ledger fingerprint (packed integer) from §4.5 + visual-family
/// guardrails.
///
/// Bit layout:
/// - `[ 0.. 2]` (3 bits) — silhouetteId (8 silhouettes; see [SilhouetteId])
/// - `[ 3.. 4]` (2 bits) — waveDepth bucket, **cut per tier** (T2.6)
/// - `[ 5.. 6]` (2 bits) — avgBF bucket, **cut per tier** (T2.6)
/// - `[ 7.. 9]` (3 bits) — dominantMotifId (8 motifs; 0 = none)
/// - `[10..13]` (4 bits) — directionHistogram: one bit per cardinal direction
///   set when that direction makes up more than 30% of node dirs
/// - `[14..22]` (9 bits) — 3×3 spatial density: one bit per third-cell set
///   when that third is more than half occupied
/// - `[23..25]` (3 bits) — [SilhouetteVisualFamily] index (parallel to id;
///   strengthens novelty vs geometric-id hopping)
///
/// Distance between fingerprints = popcount of XOR (Hamming distance).
/// [DiversityLedger.isNovel] applies a stricter threshold when the visual
/// family matches a window entry so “diamond vs cross” jitter cannot read as
/// novelty.
class LevelFingerprint {
  final int bits;
  const LevelFingerprint(this.bits);

  /// Hamming distance to [other].
  int distanceTo(LevelFingerprint other) => _popcount(bits ^ other.bits);

  @override
  bool operator ==(Object other) =>
      other is LevelFingerprint && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;

  @override
  String toString() => 'LevelFingerprint(0x${bits.toRadixString(16)})';
}

/// Threshold below which the directionHistogram bit fires.
const double kFingerprintDirectionThreshold = 0.30;

/// Threshold above which a third-cell's density bit fires.
const double kFingerprintDensityThreshold = 0.50;

/// Maps [MotifId] to the 3-bit dominant-motif fingerprint slot (§4.5 bits 7–9).
int motifIdFingerprintSlot(MotifId id) => id.index & 0x07;

///
/// [silhouette] is the silhouette the Director chose. [dominantMotifId] is
/// always 0 in Phase 3 (no motifs yet); Phase 4 will pass a meaningful id.
LevelFingerprint computeLevelFingerprint({
  required LevelData level,
  required LevelMetrics metrics,
  required SilhouetteId silhouette,
  required DifficultyTier tier,
  int dominantMotifId = 0,
}) {
  var bits = 0;
  bits |= (silhouette.index & 0x07);
  bits |= (_waveBucket(metrics.waveDepth, tier) & 0x03) << 3;
  bits |= (_bfBucket(metrics.averageBranchingFactor, tier) & 0x03) << 5;
  bits |= (dominantMotifId & 0x07) << 7;
  bits |= (_directionHistogramBits(level) & 0x0f) << 10;
  bits |=
      (_spatialDensityBits(level, level.gridWidth, level.gridHeight) & 0x1ff) <<
          14;
  bits |= (silhouetteVisualFamily(silhouette).index & 0x07) << 23;
  return LevelFingerprint(bits);
}

/// T2.6 — per-tier cut points for the wave and branching-factor buckets.
///
/// The originals were one global scale (`wave 1–2 / 3–4 / 5–6 / 7+`,
/// `bf <2 / 2–3.5 / 3.5–5 / >5`) chosen across all modes. Measured on 500
/// levels per mode, that scale puts every Hard board in the top bucket:
///
/// | field | Hard occupancy under the global cuts | entropy |
/// |---|---|---|
/// | waveDepth | 0% / 0% / 89% / 11% | 0.49 of 2 bits |
/// | avgBF | 0% / 0% / 0% / **100%** | **0.02 of 2 bits** |
///
/// So four of the fingerprint's 26 bits carried 0.51 bits between them, and
/// the novelty threshold — chosen for a 26-bit space — was being applied to a
/// ~16-bit one. Cutting per tier at that tier's own quartiles is what gives
/// the bits back. The cut points below are the measured quartiles, not
/// round numbers; the same method T0.2 used to settle `bboxFillBucket`.
///
/// Raw distributions and the derivation: `docs/playtests/p2b_t26_buckets.md`.
///
/// **These cut points are content-defining.** Changing one moves boards, so it
/// is a `generationVersion` concern after the Gen V1 freeze.
const Map<DifficultyTier, List<int>> kWaveBucketCuts = {
  // Easy   observed 2..7,  quartiles 3 / 3 / 4   → {≤2} {3} {4} {≥5}
  DifficultyTier.easy: [2, 3, 4],
  // Medium observed 3..8,  quartiles 4 / 4 / 5   → {≤3} {4} {5} {≥6}
  DifficultyTier.medium: [3, 4, 5],
  // Hard   observed 5..11, quartiles 5 / 5 / 6   → {5} {6} {7} {≥8}
  DifficultyTier.hard: [5, 6, 7],
};

const Map<DifficultyTier, List<double>> kBfBucketCuts = {
  // Easy   observed 1.88..8.04, quartiles 3.60 / 4.30 / 4.93
  DifficultyTier.easy: [3.60, 4.30, 4.93],
  // Medium observed 2.73..9.32, quartiles 4.75 / 5.24 / 5.80
  DifficultyTier.medium: [4.75, 5.24, 5.80],
  // Hard   observed 4.75..9.04, quartiles 6.60 / 7.08 / 7.52
  DifficultyTier.hard: [6.60, 7.08, 7.52],
};

/// Expert shares Hard's cuts — it is the same density regime, and it has no
/// separate measured population to derive its own from.
List<int> _waveCuts(DifficultyTier tier) =>
    kWaveBucketCuts[tier] ?? kWaveBucketCuts[DifficultyTier.hard]!;

List<double> _bfCuts(DifficultyTier tier) =>
    kBfBucketCuts[tier] ?? kBfBucketCuts[DifficultyTier.hard]!;

int _waveBucket(int wave, DifficultyTier tier) {
  final c = _waveCuts(tier);
  if (wave <= c[0]) return 0;
  if (wave <= c[1]) return 1;
  if (wave <= c[2]) return 2;
  return 3;
}

int _bfBucket(double bf, DifficultyTier tier) {
  final c = _bfCuts(tier);
  if (bf < c[0]) return 0;
  if (bf < c[1]) return 1;
  if (bf < c[2]) return 2;
  return 3;
}

int _directionHistogramBits(LevelData level) {
  if (level.nodes.isEmpty) return 0;
  final counts = <Direction, int>{for (final d in Direction.values) d: 0};
  for (final n in level.nodes) {
    counts[n.dir] = (counts[n.dir] ?? 0) + 1;
  }
  final total = level.nodes.length;
  var bits = 0;
  for (final d in Direction.values) {
    if ((counts[d] ?? 0) / total > kFingerprintDirectionThreshold) {
      bits |= 1 << d.index;
    }
  }
  return bits;
}

int _spatialDensityBits(LevelData level, int gridWidth, int gridHeight) {
  if (level.nodes.isEmpty) return 0;
  final w = gridWidth;
  final h = gridHeight;
  final counts = List<int>.filled(9, 0);
  final capacity = List<int>.filled(9, 0);
  for (var y = 0; y < h; y++) {
    final yThird = ((y / h) * 3).floor().clamp(0, 2);
    for (var x = 0; x < w; x++) {
      final xThird = ((x / w) * 3).floor().clamp(0, 2);
      final cell = yThird * 3 + xThird;
      final allowed =
          level.playCells == null ? true : level.playCells!.contains('$x,$y');
      if (allowed) capacity[cell]++;
    }
  }
  for (final n in level.nodes) {
    final yThird = ((n.y / h) * 3).floor().clamp(0, 2);
    final xThird = ((n.x / w) * 3).floor().clamp(0, 2);
    counts[yThird * 3 + xThird]++;
  }
  var bits = 0;
  for (var i = 0; i < 9; i++) {
    if (capacity[i] == 0) continue;
    if (counts[i] / capacity[i] > kFingerprintDensityThreshold) {
      bits |= 1 << i;
    }
  }
  return bits;
}

int _popcount(int x) {
  var v = x;
  var c = 0;
  while (v != 0) {
    c += v & 1;
    v = v >> 1;
  }
  return c;
}

/// Per-session ring buffer of recently-emitted fingerprints, plus a longer
/// historical tail used for cross-session diversity (§4.5).
///
/// Persistence is not wired in Phase 3 — [serialize] / [restore] let a Phase 5
/// or beyond integration save/restore the historical list from user prefs
/// without touching this class.
class DiversityLedger {
  /// Size of the rejection window (§4.5).
  final int windowSize;

  /// Maximum historical fingerprints kept (§4.5).
  final int historicalCap;

  /// Hamming-distance threshold; candidates closer than this to anything in
  /// the window are rejected (§4.5).
  final int hammingThreshold;

  final Queue<int> _recent = Queue<int>();
  final List<int> _historical = <int>[];

  /// Extra Hamming distance required when the candidate shares a
  /// [SilhouetteVisualFamily] with a window entry (locks out geometric
  /// shape-hopping that barely perturbs the packed bits).
  final int sameVisualFamilyHammingMargin;

  /// When non-null, only fingerprints among the newest
  /// [recentStrictMarginCount] entries in the window apply
  /// [sameVisualFamilyHammingMargin]; older window entries gate with
  /// [hammingThreshold] alone (relaxing intra-family tightening for stale
  /// comparisons). Null preserves legacy behaviour (every window entry uses
  /// the full intra-family threshold).
  final int? recentStrictMarginCount;

  DiversityLedger({
    this.windowSize = 20,
    this.historicalCap = 100,
    // T2.7 — recalibrated from the post-T2.6 nearest-neighbour distribution,
    // not chosen as round numbers. Observed on Hard L1–500 after the per-tier
    // re-bucketing (min=0 p25=4 median=5 p75=6 p90=7 max=12):
    //
    //   threshold | share of levels admitted as novel
    //       3     | 89.4%
    //       4     | 75.2%   <- base, the measured p25
    //       5     | 52.7%   (the old base)
    //       6     | 29.1%   <- same-family, 4 + margin 2
    //       8     |  5.6%   (the old same-family, 5 + 3)
    //
    // The same-family threshold is the one that actually applies on Hard —
    // 72% of Hard boards are geometric-lattice — and at 8 it admitted 5.6% of
    // candidates. That is not a strict gate, it is an unreachable one, and it
    // is why 286 of 300 Hard levels shipped by last resort.
    //
    // **The floor this cannot cross.** The margin exists so pure silhouette
    // hopping ("diamond vs cross jitter") cannot read as novelty. Within a
    // visual family the family bits are identical, so a silhouette-only
    // difference is at most **3** bits — see `diversity_ledger_test`, which
    // pins this. A same-family threshold of 6 keeps double that headroom
    // while admitting 5.2x more candidates than 8 did.
    //
    // Derivation: `docs/playtests/p2b_t27_threshold.md`.
    this.hammingThreshold = 4,
    this.sameVisualFamilyHammingMargin = 2,
    this.recentStrictMarginCount,
  });

  /// True iff [fingerprint] is far enough from every entry in the window.
  bool isNovel(LevelFingerprint fingerprint) {
    final mySilhouette = SilhouetteId
        .values[(fingerprint.bits & 0x07) % SilhouetteId.values.length];
    final myFamily = silhouetteVisualFamily(mySilhouette);
    final windowList = _recent.toList(growable: false);
    for (var j = windowList.length - 1; j >= 0; j--) {
      final fp = windowList[j];
      final distanceFromNewest = windowList.length - 1 - j;
      final applyMargin = recentStrictMarginCount == null ||
          distanceFromNewest < recentStrictMarginCount!;
      final otherSil =
          SilhouetteId.values[(fp & 0x07) % SilhouetteId.values.length];
      final otherFamily = silhouetteVisualFamily(otherSil);
      final dist = _popcount(fp ^ fingerprint.bits);
      final strictFamily = applyMargin && otherFamily == myFamily;
      final need = strictFamily
          ? hammingThreshold + sameVisualFamilyHammingMargin
          : hammingThreshold;
      if (dist < need) return false;
    }
    return true;
  }

  /// Records [fingerprint] as the most-recently-emitted. Evicts oldest when
  /// the window or historical cap is exceeded.
  void record(LevelFingerprint fingerprint) {
    _recent.addLast(fingerprint.bits);
    while (_recent.length > windowSize) {
      _recent.removeFirst();
    }
    _historical.add(fingerprint.bits);
    while (_historical.length > historicalCap) {
      _historical.removeAt(0);
    }
  }

  /// Clears both the window and the historical tail (for tests).
  void clear() {
    _recent.clear();
    _historical.clear();
  }

  Iterable<LevelFingerprint> get window =>
      _recent.map((b) => LevelFingerprint(b));
  Iterable<LevelFingerprint> get historical =>
      _historical.map((b) => LevelFingerprint(b));

  /// Returns a flat list of historical bit values suitable for prefs storage.
  List<int> serialize() => List<int>.from(_historical);

  /// Replaces the historical tail (and seeds the window with its end) with
  /// [bits]. Useful after deserialising from prefs.
  void restore(List<int> bits) {
    _historical
      ..clear()
      ..addAll(bits.take(historicalCap));
    _recent
      ..clear()
      ..addAll(_historical.length > windowSize
          ? _historical.sublist(_historical.length - windowSize)
          : _historical);
  }
}
