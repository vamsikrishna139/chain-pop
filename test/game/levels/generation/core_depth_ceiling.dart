// T0.4§d — the achievable-depth ceiling for one board.
//
// A board's geometry decides how deep a core *can* be. A wide, shallow board
// has no node with a large prerequisite closure, so no core selection — however
// good — can produce a deep core on it. Measuring such a board against an
// absolute tap floor therefore says nothing about whether the selector did its
// job; it only says the board was never capable.
//
// So for every frozen corpus board we compute the best `coreTapDepth` reachable
// on that exact geometry with that exact number of cores:
//
//     per node: prerequisite closure as a bitmask     (O(n^2), once per board)
//     ceiling = max over valid k-subsets of popcount(union of their masks)
//
// Subsets are constrained by the same `spreadOk` >= 2 Manhattan rule the real
// selector obeys (`_climaxBandCoreIds` in `level_enrichment.dart`), so the
// ceiling is *feasible* rather than fantasy. It is deliberately NOT constrained
// by the selector's other filters (normal-kind, guarded, in-band): the legacy
// fallback path ignores all three, so any of those nodes really is reachable by
// some core selection.
//
// Two quantities follow, and both are decision-relevant before P1 is written:
//
//   * `captureRate` = actual / ceiling — a score for the *selector* rather than
//     for the population. "Q1 went from capturing 18% of available depth to
//     91%" and "p50 rose 6 -> 10" can diverge; when they do the first is truth.
//   * boards whose `ceiling` is below the mode floor are **geometrically
//     unfixable**. T1.2's bounded repick will burn its attempts and ship the
//     best it saw, silently. If that set is large, T1.2 as specified cannot
//     deliver its invariant and the remedy has to move upstream into candidate
//     rejection. This has to be known before T1.2 is written.
//
// Nothing here touches `lib/`. It is a measuring instrument.
//
// The prerequisite relation is `computeRayPrerequisites` — the same one
// `CoreMetrics` uses — so ceiling and actual are on the same scale by
// construction and cannot drift apart. Like `CoreMetrics` it is blind to
// `kind` and `phaseGroup`, which makes it a pure function of geometry and
// therefore invariant across P1.

import 'package:chain_pop/game/levels/generation/core_metrics.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level.dart';

/// The achievable-depth ceiling of one board, and how much of it the shipped
/// core selection actually captured.
class CoreDepthCeiling {
  const CoreDepthCeiling({
    required this.ceilingTapDepth,
    required this.actualTapDepth,
    required this.coreCount,
    required this.totalNodes,
    required this.exhaustive,
  });

  /// Best `coreTapDepth` any spread-legal [coreCount]-subset can reach.
  ///
  /// For a coreless board this is [totalNodes]: the win is clear-all, so the
  /// board already demands every tap and there is nothing left to capture.
  final int ceilingTapDepth;

  /// What the shipped selection actually reached — `CoreMetrics.coreTapDepth`,
  /// or [totalNodes] on a coreless board, matching `BoardRow.tapsToWin`.
  final int actualTapDepth;

  /// Cores on the board, i.e. the `k` the subset search used.
  final int coreCount;

  final int totalNodes;

  /// False when the board was too large for the 62-bit mask and the search was
  /// skipped. Never happens on shipped boards (max observed node count is 27),
  /// but a silent wrong answer here would corrupt the baseline, so it is
  /// surfaced rather than assumed.
  final bool exhaustive;

  /// Share of the available depth the selector captured, in `[0, 1]`.
  ///
  /// 1.0 when the ceiling is 0 or the board is coreless — in both cases there
  /// was no selection decision to get wrong, so scoring the selector down would
  /// be a lie about a board it never touched.
  double get captureRate {
    if (ceilingTapDepth <= 0) return 1.0;
    final r = actualTapDepth / ceilingTapDepth;
    return r > 1.0 ? 1.0 : r;
  }

  /// Depth left on the table by the selector.
  int get headroom => ceilingTapDepth - actualTapDepth;
}

/// The `spreadOk` rule from `_climaxBandCoreIds`: cores must be at least two
/// Manhattan steps apart. Kept as a named predicate so the ceiling and the
/// production selector can be checked against each other by eye.
bool coreSpreadOk(NodeData a, NodeData b) =>
    (a.x - b.x).abs() + (a.y - b.y).abs() >= 2;

/// Computes the achievable-depth ceiling of [enriched].
///
/// [enriched] must be the final, post-enrichment board — the same object
/// `CoreMetrics.compute` is given — so `actualTapDepth` and `ceilingTapDepth`
/// describe the same board.
CoreDepthCeiling computeCoreDepthCeiling(LevelData enriched) {
  final nodes = enriched.nodes;
  final n = nodes.length;
  final coreCount = nodes.where((x) => x.isCore).length;

  if (n == 0) {
    return const CoreDepthCeiling(
      ceilingTapDepth: 0,
      actualTapDepth: 0,
      coreCount: 0,
      totalNodes: 0,
      exhaustive: true,
    );
  }

  // Coreless board: the win condition is clear-all, so every node is a required
  // tap and the ceiling is the board itself. There is no core selection to
  // score, hence captureRate 1.0 by construction.
  if (coreCount == 0) {
    return CoreDepthCeiling(
      ceilingTapDepth: n,
      actualTapDepth: n,
      coreCount: 0,
      totalNodes: n,
      exhaustive: true,
    );
  }

  final actual = CoreMetrics.compute(enriched).coreTapDepth;

  // One 64-bit int per closure. Dart ints are 64-bit two's complement on the
  // VM; staying at or below 62 bits keeps `popcount` off the sign bit.
  if (n > 62) {
    return CoreDepthCeiling(
      ceilingTapDepth: actual,
      actualTapDepth: actual,
      coreCount: coreCount,
      totalNodes: n,
      exhaustive: false,
    );
  }

  final indexOfId = <int, int>{
    for (var i = 0; i < n; i++) nodes[i].id: i,
  };
  final prereqs = computeRayPrerequisites(enriched);

  // Transitive prerequisite closure of each node, including the node itself —
  // the same set `CoreMetrics` unions over the core set.
  final closure = List<int>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var mask = 0;
    final stack = <int>[i];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      final bit = 1 << cur;
      if (mask & bit != 0) continue;
      mask |= bit;
      for (final p in prereqs[nodes[cur].id] ?? const <int>[]) {
        final pi = indexOfId[p];
        if (pi != null && mask & (1 << pi) == 0) stack.add(pi);
      }
    }
    closure[i] = mask;
  }

  var best = 0;
  final chosen = <int>[];

  // Depth-first over spread-legal k-subsets. `start` keeps combinations
  // ordered so each subset is visited once; the spread check prunes whole
  // branches rather than filtering at the leaves.
  void search(int start, int depth, int mask) {
    if (depth == coreCount) {
      final pc = _popcount(mask);
      if (pc > best) best = pc;
      return;
    }
    for (var i = start; i <= n - (coreCount - depth); i++) {
      var ok = true;
      for (final c in chosen) {
        if (!coreSpreadOk(nodes[c], nodes[i])) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      chosen.add(i);
      search(i + 1, depth + 1, mask | closure[i]);
      chosen.removeLast();
    }
  }

  search(0, 0, 0);

  // A board with no spread-legal k-subset at all (every pair adjacent) has no
  // feasible selection; the shipped board is then its own ceiling.
  final ceiling = best == 0 ? actual : best;

  return CoreDepthCeiling(
    ceilingTapDepth: ceiling,
    actualTapDepth: actual,
    coreCount: coreCount,
    totalNodes: n,
    exhaustive: true,
  );
}

int _popcount(int v) {
  var x = v;
  var c = 0;
  while (x != 0) {
    x &= x - 1;
    c++;
  }
  return c;
}
