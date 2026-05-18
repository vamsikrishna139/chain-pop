import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import '../level_solver.dart';

/// Logic + tempo + uniqueness metrics computed over a generated [LevelData].
///
/// Cheap metrics ([nodeCount], [waveDepth], [averageBranchingFactor],
/// [firstLegalMoveCount], [criticalUnlockDepth], [forcedSequenceRatio],
/// [frontierVariance], [tempoProfile]) are always computed. The expensive
/// [viablePathCount] is opt-in — pass `includeViablePath: true` to compute it,
/// otherwise it is reported as `-1` with [viablePathCountCapped] = false.
class LevelMetrics {
  /// Total nodes on the board.
  final int nodeCount;

  /// `LevelSolver.countRemovalWaves(level)` — parallel-removal waves.
  final int waveDepth;

  /// Mean legal-move count across the canonical (ID-order) sequence.
  final double averageBranchingFactor;

  /// Legal moves at step 0 (= the player's opening choice count).
  final int firstLegalMoveCount;

  /// Longest prerequisite chain to any single node (§4.4).
  final int criticalUnlockDepth;

  /// Share of canonical-sequence steps that have exactly one legal move.
  /// Range `[0.0, 1.0]`.
  final double forcedSequenceRatio;

  /// Population standard deviation of the [tempoProfile].
  final double frontierVariance;

  /// The legal-move-count sequence directly. Index 0 = first step, etc.
  /// (§4.4 "Tempo Profile" — rhythm, not just average BF.)
  final List<int> tempoProfile;

  /// Number of distinct removal sequences that solve the level (§4.4
  /// "Viable-Path Count"). `-1` if not computed. When capped, the returned
  /// value equals the cap and [viablePathCountCapped] is true.
  final int viablePathCount;

  /// True iff the bounded DFS hit its cap before fully enumerating.
  final bool viablePathCountCapped;

  const LevelMetrics({
    required this.nodeCount,
    required this.waveDepth,
    required this.averageBranchingFactor,
    required this.firstLegalMoveCount,
    required this.criticalUnlockDepth,
    required this.forcedSequenceRatio,
    required this.frontierVariance,
    required this.tempoProfile,
    required this.viablePathCount,
    required this.viablePathCountCapped,
  });

  /// Computes all metrics. Set [includeViablePath] = true to also run the
  /// bounded DFS — typically only worth it after cheaper gates have passed.
  static LevelMetrics compute(
    LevelData level, {
    bool includeViablePath = false,
    int viablePathBranchCap = 64,
    int viablePathExpansionCap = 6000,
  }) {
    final tempo = computeTempoProfile(level);
    final wave = LevelSolver.countRemovalWaves(level);
    final avgBF = tempo.isEmpty
        ? 0.0
        : tempo.fold<int>(0, (a, b) => a + b) / tempo.length;
    final firstLegal = tempo.isEmpty ? 0 : tempo.first;
    final fsr = tempo.isEmpty
        ? 0.0
        : tempo.where((m) => m == 1).length / tempo.length;
    final variance = _stddev(tempo, avgBF);
    final cud = computeCriticalUnlockDepth(level);

    var paths = -1;
    var capped = false;
    if (includeViablePath) {
      final r = computeViablePathCount(
        level,
        branchCap: viablePathBranchCap,
        expansionCap: viablePathExpansionCap,
      );
      paths = r.$1;
      capped = r.$2;
    }

    return LevelMetrics(
      nodeCount: level.nodes.length,
      waveDepth: wave,
      averageBranchingFactor: avgBF,
      firstLegalMoveCount: firstLegal,
      criticalUnlockDepth: cud,
      forcedSequenceRatio: fsr,
      frontierVariance: variance,
      tempoProfile: tempo,
      viablePathCount: paths,
      viablePathCountCapped: capped,
    );
  }

  static double _stddev(List<int> values, double mean) {
    if (values.length < 2) return 0.0;
    var sum = 0.0;
    for (final v in values) {
      final d = v - mean;
      sum += d * d;
    }
    return sqrt(sum / values.length);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top-level helpers (kept as functions to avoid colliding with the
// like-named instance fields on [LevelMetrics]).
// ─────────────────────────────────────────────────────────────────────────────

/// Per-step legal-move count along the canonical (ID-order) removal sequence.
/// This is the raw signal that backs both [LevelMetrics.tempoProfile] and the
/// derived BF / FSR / variance numbers.
List<int> computeTempoProfile(LevelData level) {
  if (level.nodes.isEmpty) return const <int>[];

  final sorted = List<NodeData>.from(level.nodes)
    ..sort((a, b) => a.id.compareTo(b.id));
  final remaining = List<NodeData>.from(sorted);
  final positions = <int>{
    for (final n in remaining) gridCellKey(n.x, n.y),
  };

  final tempo = <int>[];
  for (final next in sorted) {
    var legal = 0;
    for (final n in remaining) {
      final key = gridCellKey(n.x, n.y);
      positions.remove(key);
      final canRemove =
          LevelSolver.canRemoveWithPositions(n, positions, level);
      positions.add(key);
      if (canRemove) legal++;
    }
    tempo.add(legal);
    positions.remove(gridCellKey(next.x, next.y));
    remaining.removeWhere((m) => m.id == next.id);
  }
  return tempo;
}

/// Longest prerequisite chain in the dependency graph. A node `m` is a
/// prerequisite of `n` iff `m` sits on `n`'s initial ray (and therefore must
/// be removed before `n` becomes extractable).
///
/// Because the level's `id` ordering is a valid removal order, every
/// prerequisite of `n` has a smaller `id` — so the depth DP is a single
/// in-order sweep without recursion or cycle handling.
int computeCriticalUnlockDepth(LevelData level) {
  if (level.nodes.isEmpty) return 0;

  final byId = <int, NodeData>{for (final n in level.nodes) n.id: n};
  final positionToId = <int, int>{
    for (final n in level.nodes) gridCellKey(n.x, n.y): n.id,
  };
  final prereqs = <int, List<int>>{};
  for (final n in level.nodes) {
    final list = <int>[];
    var cx = n.x;
    var cy = n.y;
    while (true) {
      switch (n.dir) {
        case Direction.up:
          cy--;
        case Direction.down:
          cy++;
        case Direction.left:
          cx--;
        case Direction.right:
          cx++;
      }
      if (cx < 0 ||
          cx >= level.gridWidth ||
          cy < 0 ||
          cy >= level.gridHeight) {
        break;
      }
      final id = positionToId[gridCellKey(cx, cy)];
      if (id != null) list.add(id);
    }
    prereqs[n.id] = list;
  }

  final ids = byId.keys.toList()..sort();
  final depth = <int, int>{};
  var maxDepth = 0;
  for (final id in ids) {
    final pre = prereqs[id] ?? const <int>[];
    var d = 1;
    for (final p in pre) {
      final pd = depth[p];
      if (pd != null && pd + 1 > d) d = pd + 1;
    }
    depth[id] = d;
    if (d > maxDepth) maxDepth = d;
  }
  return maxDepth;
}

/// Bounded DFS over the move tree. Returns `(count, capped)` — when capped,
/// `count` is at most [branchCap] (so callers can treat capped levels as
/// "many paths"). Easy levels typically resolve well below the caps; Hard /
/// Expert levels with low viable-path counts should produce small, accurate
/// numbers.
(int, bool) computeViablePathCount(
  LevelData level, {
  int branchCap = 64,
  int expansionCap = 6000,
  bool bailOutOnTime = false,
  int maxMicroseconds = 8000,
}) {
  if (level.nodes.isEmpty) return (1, false);

  final initialPositions = <int>{
    for (final n in level.nodes) gridCellKey(n.x, n.y),
  };
  final remaining = List<NodeData>.from(level.nodes);

  var count = 0;
  var expansions = 0;
  var capped = false;
  final sw = bailOutOnTime ? (Stopwatch()..start()) : null;

  bool dfs(List<NodeData> rem, Set<int> positions) {
    if (sw != null && sw.elapsedMicroseconds > maxMicroseconds) {
      capped = true;
      return true;
    }
    if (count >= branchCap || expansions >= expansionCap) {
      capped = true;
      return true;
    }
    if (rem.isEmpty) {
      count++;
      return false;
    }
    expansions++;
    final legal = <NodeData>[];
    for (final n in rem) {
      final key = gridCellKey(n.x, n.y);
      positions.remove(key);
      final ok = LevelSolver.canRemoveWithPositions(n, positions, level);
      positions.add(key);
      if (ok) legal.add(n);
    }
    for (final n in legal) {
      final key = gridCellKey(n.x, n.y);
      positions.remove(key);
      final removedIdx = rem.indexWhere((m) => m.id == n.id);
      final removed = rem.removeAt(removedIdx);
      final stop = dfs(rem, positions);
      rem.insert(removedIdx, removed);
      positions.add(key);
      if (stop) return true;
    }
    return false;
  }

  dfs(remaining, initialPositions);
  return (count, capped);
}
