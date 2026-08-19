import '../level.dart';
import 'metrics.dart';

/// Tap-depth core quality. Pure; no RNG. Computed on the ENRICHED board.
///
/// T0.1 of `docs/IMPLEMENTATION_PLAN_V2.md`. The win fires when every core has
/// been extracted (`chain_pop_game.dart`), so the honest measure of "how much
/// of this board does the player actually have to play" is the size of the
/// prerequisite closure of the core set — a *sequential* tap count, not the
/// *parallel* wave depth the legacy `CoreWaveRatio` band was built on.
///
///     CoreTapDepth = |closure(cores)|
///       where closure(C) = C ∪ ⋃_{c ∈ C} prerequisiteClosure(c)
///
/// The prerequisite relation is [computeRayPrerequisites] — the same relation
/// `computeCriticalUnlockDepth` uses, so the two cannot drift.
///
/// Complexity is O(n²) worst case on n ≤ 42 nodes: negligible beside
/// retrograde construction.
class CoreMetrics {
  /// Taps that must precede (and include) the last core.
  final int coreTapDepth;

  /// Nodes on the board.
  final int totalNodes;

  /// `coreTapDepth / totalNodes` — the unit the `[0.35, 0.65]` band should
  /// have been measuring all along (T1.1).
  final double coreTapFraction;

  /// Share of the board irrelevant to reaching the cores — the exact
  /// complement of [coreTapFraction]. Reported separately because it is the
  /// quantity a reader of the corpus CSVs actually wants to reason about
  /// ("how much of this board is filler?").
  final double coreIsolation;

  /// Largest number of nodes that a single removal makes newly extractable.
  ///
  /// One tap removes exactly one node in this game, so this is an *unlock*
  /// count, not a chain of removals: nodes whose entire remaining prerequisite
  /// set was that one node.
  final int maxSingleTapCascade;

  /// Longest prerequisite chain terminating at any core.
  final int coreCriticalDepth;

  const CoreMetrics({
    required this.coreTapDepth,
    required this.totalNodes,
    required this.coreTapFraction,
    required this.coreIsolation,
    required this.maxSingleTapCascade,
    required this.coreCriticalDepth,
  });

  static const CoreMetrics empty = CoreMetrics(
    coreTapDepth: 0,
    totalNodes: 0,
    coreTapFraction: 0.0,
    coreIsolation: 0.0,
    maxSingleTapCascade: 0,
    coreCriticalDepth: 0,
  );

  static CoreMetrics compute(LevelData enriched) {
    if (enriched.nodes.isEmpty) return empty;

    final prereqs = computeRayPrerequisites(enriched);
    final cores = <int>[
      for (final n in enriched.nodes)
        if (n.isCore) n.id,
    ];

    // 1. CoreTapDepth = |closure(cores)|.
    final closure = <int>{};
    final stack = <int>[...cores];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (!closure.add(id)) continue;
      for (final p in prereqs[id] ?? const <int>[]) {
        if (!closure.contains(p)) stack.add(p);
      }
    }

    final totalNodes = enriched.nodes.length;
    final coreTapDepth = closure.length;
    final coreTapFraction = coreTapDepth / totalNodes;

    // 2. Everything outside the closure is filler.
    final coreIsolation = (totalNodes - coreTapDepth) / totalNodes;

    // 3. Widest single-removal unlock: how many nodes were waiting on exactly
    //    one node, and that node alone.
    final unlockFanOut = <int, int>{};
    for (final entry in prereqs.entries) {
      final pre = entry.value;
      if (pre.length != 1) continue;
      unlockFanOut[pre.first] = (unlockFanOut[pre.first] ?? 0) + 1;
    }
    var maxSingleTapCascade = 0;
    for (final count in unlockFanOut.values) {
      if (count > maxSingleTapCascade) maxSingleTapCascade = count;
    }

    // 4. Longest prerequisite chain terminating at a core.
    final depths = computeChainDepths(enriched);
    var coreCriticalDepth = 0;
    for (final c in cores) {
      final d = depths[c] ?? 0;
      if (d > coreCriticalDepth) coreCriticalDepth = d;
    }

    return CoreMetrics(
      coreTapDepth: coreTapDepth,
      totalNodes: totalNodes,
      coreTapFraction: coreTapFraction,
      coreIsolation: coreIsolation,
      maxSingleTapCascade: maxSingleTapCascade,
      coreCriticalDepth: coreCriticalDepth,
    );
  }
}
