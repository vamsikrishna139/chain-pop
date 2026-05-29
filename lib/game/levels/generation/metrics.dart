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

  /// Wave-peeling FSR metric. Captures layer-by-layer topological compression.
  /// (Replaces the legacy single-path forcedSequenceRatio).
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

  /// Wave-peeling compression rhythm. Index 0 = opening wave width, etc.
  /// Used for pacing curve analysis.
  final List<int> wavePeelingProfile;

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
    required this.wavePeelingProfile,
  });

  /// Computes all metrics. Set [includeViablePath] = true to also run the
  /// bounded DFS — typically only worth it after cheaper gates have passed.
  static LevelMetrics compute(
    LevelData level, {
    bool includeViablePath = false,
    int viablePathBranchCap = 512,
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

    final wavePeelingProfile = computeWavePeelingProfile(level);
    final forcedSequenceRatio = calculateFSRFromProfile(wavePeelingProfile, level.nodes.length);

    return LevelMetrics(
      nodeCount: level.nodes.length,
      waveDepth: wave,
      averageBranchingFactor: avgBF,
      firstLegalMoveCount: firstLegal,
      criticalUnlockDepth: cud,
      forcedSequenceRatio: forcedSequenceRatio,
      frontierVariance: variance,
      tempoProfile: tempo,
      viablePathCount: paths,
      viablePathCountCapped: capped,
      wavePeelingProfile: wavePeelingProfile,
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

/// Generates the sequence of branching factors for each layer peeled off the dependency graph.
List<int> computeWavePeelingProfile(LevelData level) {
  if (level.nodes.isEmpty) return [];

  final nodes = level.nodes.map((n) => n.clone()).toList();
  final positions = <int>{for (final n in nodes) gridCellKey(n.x, n.y)};
  final waveBranchingFactors = <int>[];

  while (nodes.isNotEmpty) {
    final wave = [
      for (final n in nodes)
        if (LevelSolver.canRemoveWithPositions(n, positions, level)) n,
    ];
    if (wave.isEmpty) break; // unsolvable

    waveBranchingFactors.add(wave.length);

    for (final n in wave) {
      nodes.removeWhere((x) => x.id == n.id);
      positions.remove(gridCellKey(n.x, n.y));
    }
  }
  return waveBranchingFactors;
}

/// Computes the true topological Forced Sequence Ratio using a pre-calculated wave peeling profile.
double calculateFSRFromProfile(List<int> waveBranchingFactors, int totalNodes) {
  if (waveBranchingFactors.isEmpty) return 0.0;

  double totalScore = 0.0;
  for (int bf in waveBranchingFactors) {
    if (bf >= 1 && bf <= 3) {
      totalScore += 1.0;
    } else if (bf == 4) {
      totalScore += 0.8;
    } else if (bf <= 6) {
      totalScore += 0.5;
    } else if (bf <= 8) {
      totalScore += 0.2;
    } else {
      totalScore += 0.1;
    }
  }

  final result = totalScore / waveBranchingFactors.length;
  assert(result >= 0.0 && result <= 1.0, 
    'tFSR out of range: $result for level with $totalNodes nodes');
  return result;
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
  int branchCap = 512,
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

/// Ray-dependency topology on a shipped [LevelData] board.
class LevelTopologyMetrics {
  /// Longest prerequisite chain along ray-block edges (same as CUD).
  final int chainDepthMax;

  /// Maximum fan-in: most nodes pointing at the same target.
  final int maxHubInDegree;

  /// Mean unlock fan-out over nodes that are ray targets.
  final double avgUnlockFanout;

  const LevelTopologyMetrics({
    required this.chainDepthMax,
    required this.maxHubInDegree,
    required this.avgUnlockFanout,
  });

  static LevelTopologyMetrics compute(LevelData level) {
    if (level.nodes.isEmpty) {
      return const LevelTopologyMetrics(
        chainDepthMax: 0,
        maxHubInDegree: 0,
        avgUnlockFanout: 0,
      );
    }

    final positionToId = <int, int>{
      for (final n in level.nodes) gridCellKey(n.x, n.y): n.id,
    };
    final fanIn = <int, int>{};
    final depth = <int, int>{};
    var maxHub = 0;
    var maxDepth = 0;

    final ids = level.nodes.map((n) => n.id).toList()..sort();
    for (final id in ids) {
      final n = level.nodes.firstWhere((node) => node.id == id);
      final target = _firstRayTargetId(n, positionToId, level);
      var d = 1;
      if (target != null) {
        fanIn[target] = (fanIn[target] ?? 0) + 1;
        final td = depth[target];
        if (td != null && td + 1 > d) d = td + 1;
      }
      depth[id] = d;
      if (d > maxDepth) maxDepth = d;
    }

    for (final count in fanIn.values) {
      if (count > maxHub) maxHub = count;
    }

    final avgFanout = fanIn.isEmpty
        ? 0.0
        : fanIn.values.fold<int>(0, (a, b) => a + b) / fanIn.length;

    return LevelTopologyMetrics(
      chainDepthMax: maxDepth,
      maxHubInDegree: maxHub,
      avgUnlockFanout: avgFanout,
    );
  }
}

int? _firstRayTargetId(
  NodeData node,
  Map<int, int> positionToId,
  LevelData level,
) {
  var x = node.x;
  var y = node.y;
  while (true) {
    switch (node.dir) {
      case Direction.up:
        y--;
      case Direction.down:
        y++;
      case Direction.left:
        x--;
      case Direction.right:
        x++;
    }
    if (x < 0 ||
        x >= level.gridWidth ||
        y < 0 ||
        y >= level.gridHeight) {
      return null;
    }
    final hit = positionToId[gridCellKey(x, y)];
    if (hit != null) return hit;
  }
}
