import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';
import '../level_solver.dart';

/// Result of the bounded human-like solver effort measurement.
class SearchEffortResult {
  /// Decision nodes visited during the simulated solve.
  final int expansionCount;

  /// Dead-end retreats during tie-breaking DFS.
  final int backtrackCount;

  /// Whether the human-like solver cleared the board.
  final bool solved;

  const SearchEffortResult({
    required this.expansionCount,
    required this.backtrackCount,
    required this.solved,
  });

  /// Combined effort signal: expansions plus backtracks.
  int get searchEffortScore => expansionCount + backtrackCount;
}

/// Simulates a human-like solve and returns search-effort telemetry.
///
/// Greedily prefers obvious moves (ray-clear, edge-pointing, min-dependents).
/// When multiple moves tie at the top heuristic tier, a bounded depth-2–3 DFS
/// explores alternatives and counts backtracks.
SearchEffortResult computeSearchEffort(
  LevelData level, {
  int maxTieDepth = 3,
}) {
  if (level.nodes.isEmpty) {
    return const SearchEffortResult(
      expansionCount: 0,
      backtrackCount: 0,
      solved: true,
    );
  }

  final remaining = List<NodeData>.from(level.nodes);
  final positions = <int>{for (final n in remaining) gridCellKey(n.x, n.y)};
  var expansions = 0;
  var backtracks = 0;

  final solved = _solveState(
    remaining,
    positions,
    level,
    maxTieDepth: maxTieDepth,
    expansions: expansions,
    backtracks: backtracks,
    onExpansion: () => expansions++,
    onBacktrack: () => backtracks++,
  );

  return SearchEffortResult(
    expansionCount: expansions,
    backtrackCount: backtracks,
    solved: solved,
  );
}

bool _solveState(
  List<NodeData> remaining,
  Set<int> positions,
  LevelData level, {
  required int maxTieDepth,
  required int expansions,
  required int backtracks,
  required void Function() onExpansion,
  required void Function() onBacktrack,
}) {
  if (remaining.isEmpty) return true;

  onExpansion();
  final legal = <NodeData>[];
  for (final n in remaining) {
    if (LevelSolver.canRemoveWithPositions(n, positions, level)) {
      legal.add(n);
    }
  }
  if (legal.isEmpty) return false;
  if (legal.length == 1) {
    return _commitMove(
      legal.first,
      remaining,
      positions,
      level,
      maxTieDepth: maxTieDepth,
      expansions: expansions,
      backtracks: backtracks,
      onExpansion: onExpansion,
      onBacktrack: onBacktrack,
    );
  }

  final ranked = _rankMoves(legal, remaining, level);
  final topScore = ranked.first.$2;
  final topMoves = [
    for (final entry in ranked)
      if (entry.$2 == topScore) entry.$1,
  ];

  if (topMoves.length == 1) {
    return _commitMove(
      topMoves.first,
      remaining,
      positions,
      level,
      maxTieDepth: maxTieDepth,
      expansions: expansions,
      backtracks: backtracks,
      onExpansion: onExpansion,
      onBacktrack: onBacktrack,
    );
  }

  return _dfsTieBreak(
    topMoves,
    remaining,
    positions,
    level,
    depth: 0,
    maxTieDepth: maxTieDepth,
    expansions: expansions,
    backtracks: backtracks,
    onExpansion: onExpansion,
    onBacktrack: onBacktrack,
  );
}

bool _commitMove(
  NodeData move,
  List<NodeData> remaining,
  Set<int> positions,
  LevelData level, {
  required int maxTieDepth,
  required int expansions,
  required int backtracks,
  required void Function() onExpansion,
  required void Function() onBacktrack,
}) {
  final key = gridCellKey(move.x, move.y);
  positions.remove(key);
  final idx = remaining.indexWhere((n) => n.id == move.id);
  final removed = remaining.removeAt(idx);
  final ok = _solveState(
    remaining,
    positions,
    level,
    maxTieDepth: maxTieDepth,
    expansions: expansions,
    backtracks: backtracks,
    onExpansion: onExpansion,
    onBacktrack: onBacktrack,
  );
  remaining.insert(idx, removed);
  positions.add(key);
  return ok;
}

bool _dfsTieBreak(
  List<NodeData> moves,
  List<NodeData> remaining,
  Set<int> positions,
  LevelData level, {
  required int depth,
  required int maxTieDepth,
  required int expansions,
  required int backtracks,
  required void Function() onExpansion,
  required void Function() onBacktrack,
}) {
  if (depth >= maxTieDepth) {
    return _commitMove(
      moves.first,
      remaining,
      positions,
      level,
      maxTieDepth: maxTieDepth,
      expansions: expansions,
      backtracks: backtracks,
      onExpansion: onExpansion,
      onBacktrack: onBacktrack,
    );
  }

  for (final move in moves) {
    final key = gridCellKey(move.x, move.y);
    positions.remove(key);
    final idx = remaining.indexWhere((n) => n.id == move.id);
    final removed = remaining.removeAt(idx);
    final ok = _solveState(
      remaining,
      positions,
      level,
      maxTieDepth: maxTieDepth,
      expansions: expansions,
      backtracks: backtracks,
      onExpansion: onExpansion,
      onBacktrack: onBacktrack,
    );
    remaining.insert(idx, removed);
    positions.add(key);
    if (ok) return true;
    onBacktrack();
  }
  return false;
}

List<(NodeData, int)> _rankMoves(
  List<NodeData> legal,
  List<NodeData> remaining,
  LevelData level,
) {
  final ranked = <(NodeData, int)>[];
  for (final n in legal) {
    var score = 0;
    if (_isRayClear(n, remaining, level)) score += 200;
    if (_isEdgePointing(n, level)) score += 80;
    score += max(0, 20 - _distanceToExit(n, level));
    score += max(0, 12 - _dependentCount(n, remaining, level));
    ranked.add((n, score));
  }
  ranked.sort((a, b) => b.$2.compareTo(a.$2));
  return ranked;
}

bool _isRayClear(
  NodeData node,
  List<NodeData> remaining,
  LevelData level,
) {
  final others = <int>{
    for (final n in remaining)
      if (n.id != node.id) gridCellKey(n.x, n.y),
  };
  return LevelSolver.canRemoveWithPositions(node, others, level);
}

bool _isEdgePointing(NodeData node, LevelData level) {
  return _distanceToExit(node, level) <= 2;
}

int _distanceToExit(NodeData node, LevelData level) {
  return switch (node.dir) {
    Direction.up => node.y,
    Direction.down => level.gridHeight - 1 - node.y,
    Direction.left => node.x,
    Direction.right => level.gridWidth - 1 - node.x,
  };
}

int _dependentCount(
  NodeData node,
  List<NodeData> remaining,
  LevelData level,
) {
  final positionToId = <int, int>{
    for (final n in remaining) gridCellKey(n.x, n.y): n.id,
  };
  var count = 0;
  for (final n in remaining) {
    if (n.id == node.id) continue;
    var x = n.x;
    var y = n.y;
    while (true) {
      switch (n.dir) {
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
        break;
      }
      final hit = positionToId[gridCellKey(x, y)];
      if (hit != null) {
        if (hit == node.id) count++;
        break;
      }
    }
  }
  return count;
}
