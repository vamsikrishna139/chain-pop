import 'dart:math' as math;

import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/diversity_ledger.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';

/// Default §4.5 emission window copied for rolling Hamming summaries.
const int kDiversityFingerprintWindowSize = 20;

int popcount(int x) {
  var v = x;
  var c = 0;
  while (v != 0) {
    c += v & 1;
    v = v >> 1;
  }
  return c;
}

/// Tracks longest streak and histogram of streak lengths along [sequence].
Map<String, Object> streakDistribution<T>(Iterable<T> sequence) {
  final list = sequence.toList(growable: false);
  if (list.isEmpty) {
    return {'max': 0, 'histogram': <int, int>{}};
  }
  final hist = <int, int>{};
  var maxRun = 1;
  var run = 1;
  void flush() {
    hist[run] = (hist[run] ?? 0) + 1;
    maxRun = math.max(maxRun, run);
  }

  for (var i = 1; i < list.length; i++) {
    if (list[i] == list[i - 1]) {
      run++;
    } else {
      flush();
      run = 1;
    }
  }
  flush();
  return {'max': maxRun, 'histogram': hist};
}

typedef DistinctWindowStats = ({
  int minDistinct,
  int maxDistinct,
  double avgDistinct,
  int latticeOnlyWindows,
});

DistinctWindowStats macroBucketWindowStats({
  required List<SilhouetteVisualFamily> macroSequence,
  required int window,
}) {
  if (macroSequence.isEmpty || window <= 0) {
    return (minDistinct: 0, maxDistinct: 0, avgDistinct: 0.0, latticeOnlyWindows: 0);
  }
  if (macroSequence.length < window) {
    return (minDistinct: 0, maxDistinct: 0, avgDistinct: 0.0, latticeOnlyWindows: 0);
  }
  final distinctCounts = <int>[];
  var latticeWindows = 0;
  for (var i = 0; i <= macroSequence.length - window; i++) {
    final slice = macroSequence.sublist(i, i + window).toSet();
    distinctCounts.add(slice.length);
    final onlyLattice = slice.length == 1 &&
        slice.single == SilhouetteVisualFamily.geometricLattice;
    if (onlyLattice) latticeWindows++;
  }
  final sum = distinctCounts.fold<int>(0, (a, b) => a + b);
  return (
    minDistinct: distinctCounts.reduce(math.min),
    maxDistinct: distinctCounts.reduce(math.max),
    avgDistinct: sum / distinctCounts.length,
    latticeOnlyWindows: latticeWindows,
  );
}

Map<SilhouetteId, int> silhouetteIdHistogram(
  Iterable<GenerationEmissionEvent> events,
) {
  final m = <SilhouetteId, int>{};
  for (final e in events) {
    m[e.silhouette] = (m[e.silhouette] ?? 0) + 1;
  }
  return m;
}

Map<SilhouetteVisualFamily, int> silhouetteMacroHistogram(
  Iterable<GenerationEmissionEvent> events,
) {
  final m = <SilhouetteVisualFamily, int>{};
  for (final e in events) {
    final f = silhouetteVisualFamily(e.silhouette);
    m[f] = (m[f] ?? 0) + 1;
  }
  return m;
}

List<SilhouetteVisualFamily> macroSequence(List<GenerationEmissionEvent> events) =>
    [for (final e in events) silhouetteVisualFamily(e.silhouette)];

double medianOfSortedInts(List<int> sorted) {
  if (sorted.isEmpty) return double.nan;
  final m = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[m].toDouble();
  }
  return (sorted[m - 1] + sorted[m]) / 2.0;
}

double percentileInts(List<int> values, double p01) {
  if (values.isEmpty) return double.nan;
  final s = [...values]..sort();
  if (s.length == 1) return s.first.toDouble();
  final rank = (p01 * (s.length - 1)).floor().clamp(0, s.length - 1);
  return s[rank].toDouble();
}

/// Mirrors ledger recording order: for each emitted fingerprint bit pattern,
/// when the deque already has at least one prior emission, computes the
/// minimum raw Hamming separation to fingerprints currently in the window,
/// **before** the new fingerprint is appended (matching pre-record checks).
///
/// [windowSize] defaults to §4.5's last-20 ledger window.
({
  List<int> minDistances,
  double median,
  double p90,
}) rollingMinHammingDistances({
  required List<int> fingerprintBits,
  int windowSize = kDiversityFingerprintWindowSize,
}) {
  final deque = <int>[];
  final mins = <int>[];
  for (final bits in fingerprintBits) {
    if (deque.isNotEmpty) {
      var minDist = 1 << 30;
      for (final prev in deque) {
        minDist = math.min(minDist, popcount(bits ^ prev));
      }
      mins.add(minDist);
    }
    deque.add(bits);
    if (deque.length > windowSize) {
      deque.removeAt(0);
    }
  }
  if (mins.isEmpty) {
    return (minDistances: mins, median: double.nan, p90: double.nan);
  }
  final sorted = [...mins]..sort();
  return (
    minDistances: mins,
    median: medianOfSortedInts(sorted),
    p90: percentileInts(sorted, 0.90),
  );
}

/// Hard milestone ids per [LevelGenerator._getMilestoneType]: `easy` skips;
/// thereafter `mod 100 → 50` yields max-density, `mod 100 → 0` sparse sniper,
/// modulo 25/75 seeded elsewhere.
bool matchesHardSyntheticMilestoneId(int levelId) =>
    levelId >= 25 && (levelId % 100 == 0 || levelId % 100 == 50);
