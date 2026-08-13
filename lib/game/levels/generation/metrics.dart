import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import '../level_solver.dart';
import 'dependency_graph.dart';
import 'search_effort.dart';

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

  /// Bounded human-like solver effort (expansions + backtracks). Measured only;
  /// not yet used for gating.
  final int searchEffortScore;

  /// Ray-dependency topology: nodes with fan-in ≥ 2.
  final int chokePointCount;

  /// Ray-dependency topology: widest parallel-removal wave.
  final int maxAntichainWidth;

  /// Ray-dependency topology: maximum hub fan-in.
  final int maxHubInDegree;

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
    this.searchEffortScore = 0,
    this.chokePointCount = 0,
    this.maxAntichainWidth = 0,
    this.maxHubInDegree = 0,
  });

  /// Width of the opening parallel-removal wave (turn-one choice count).
  int get waveZeroWidth =>
      wavePeelingProfile.isEmpty ? 0 : wavePeelingProfile.first;

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
    final graph = DependencyGraph.fromLevel(level);
    final effort = computeSearchEffort(level);

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
      searchEffortScore: effort.searchEffortScore,
      chokePointCount: graph.chokePointCount,
      maxAntichainWidth: graph.maxAntichainWidth,
      maxHubInDegree: graph.maxHubInDegree,
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

/// How the *shape* of the player's choice over time reads, as opposed to how
/// much of it there is.
///
/// [LevelMetrics.forcedSequenceRatio] is an aggregate: it says a board is 75 %
/// forced but not whether that is one long corridor with a wide finish, or
/// choice and constraint alternating throughout. Those play completely
/// differently at identical FSR. Choice rhythm splits them apart, computed from
/// the [computeTempoProfile] the metrics already produce — no extra solving.
///
/// **Ranking term only.** Deliberately not a gate: FSR became a liability
/// precisely by being promoted to a gate before there was evidence for the
/// band. Promotion requires corpus + player data (plan §5.5, Experiment F).
class ChoiceRhythm {
  const ChoiceRhythm({
    required this.directionChanges,
    required this.longestForcedRun,
    required this.multiChoiceFraction,
  });

  /// Times the per-step legal-move count reverses direction (opening up after
  /// tightening, or vice versa). Low means monotone; high means it breathes.
  final int directionChanges;

  /// Longest run of consecutive steps offering exactly one legal move — the
  /// longest stretch where the player is not choosing, only executing.
  final int longestForcedRun;

  /// Share of steps offering two or more legal moves.
  final double multiChoiceFraction;

  static const ChoiceRhythm zero = ChoiceRhythm(
    directionChanges: 0,
    longestForcedRun: 0,
    multiChoiceFraction: 0,
  );

  static ChoiceRhythm fromTempoProfile(List<int> tempo) {
    if (tempo.isEmpty) return zero;

    var changes = 0;
    var lastSign = 0;
    for (var i = 1; i < tempo.length; i++) {
      final d = tempo[i] - tempo[i - 1];
      if (d == 0) continue;
      final sign = d > 0 ? 1 : -1;
      if (lastSign != 0 && sign != lastSign) changes++;
      lastSign = sign;
    }

    var run = 0;
    var longest = 0;
    var multi = 0;
    for (final t in tempo) {
      if (t <= 1) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
      if (t >= 2) multi++;
    }

    return ChoiceRhythm(
      directionChanges: changes,
      longestForcedRun: longest,
      multiChoiceFraction: multi / tempo.length,
    );
  }

  /// Higher is better for candidate ranking: reward boards that keep offering
  /// a choice and that vary, penalise long unbroken forced corridors. The
  /// weights are a starting point, not a calibrated model — they only ever
  /// break ties between candidates that already passed the band.
  double get rankingScore =>
      multiChoiceFraction * 2.0 +
      (directionChanges / 10.0).clamp(0.0, 1.0) -
      (longestForcedRun / 5.0).clamp(0.0, 2.0);
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
    var hops = 0;
    while (hops < 50) {
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
      // Portal teleport
      if (level.portalPairs.isNotEmpty) {
        for (final p in level.portalPairs) {
          if (p.x1 == cx && p.y1 == cy) {
            cx = p.x2;
            cy = p.y2;
            break;
          } else if (p.x2 == cx && p.y2 == cy) {
            cx = p.x1;
            cy = p.y1;
            break;
          }
        }
      }
      hops++;
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
  var hops = 0;
  while (hops < 50) {
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
    // Portal teleport
    if (level.portalPairs.isNotEmpty) {
      for (final p in level.portalPairs) {
        if (p.x1 == x && p.y1 == y) {
          x = p.x2;
          y = p.y2;
          break;
        } else if (p.x2 == x && p.y2 == y) {
          x = p.x1;
          y = p.y1;
          break;
        }
      }
    }
    hops++;
  }
  return null; // Hop limit exceeded
}
