import 'level.dart';

/// Stateless solver utilities for Chain Pop.
///
/// Performance notes:
/// - [canRemove] is O(n) — called once per tap, acceptable.
/// - [isSolvable] / [countRemovalWaves] use parallel “waves” of removal — each
///   wave removes every currently extractable node; typically O(waves × n).
/// - [getHint] builds a position Set once; ray walks are bounded by grid size.
class LevelSolver {
  /// Returns true if the level can be fully cleared from its initial state.
  ///
  /// Uses wave-based removal: all simultaneously removable nodes are cleared in
  /// each wave until the board is empty or no progress is possible.
  static bool isSolvable(LevelData level) => countRemovalWaves(level) >= 0;

  /// Number of parallel-removal waves until the board is empty, or `-1` if stuck.
  ///
  /// Used by [LevelGenerator] to enforce [DifficultyParameters] chain-length
  /// bounds (min/max removal waves ≈ puzzle “depth”).
  static int countRemovalWaves(LevelData level) {
    final nodes = level.nodes.map((n) => n.clone()).toList();
    final positions = <String>{for (final n in nodes) '${n.x},${n.y}'};
    var waves = 0;

    while (true) {
      final wave = [
        for (final n in nodes)
          if (_canRemoveWithSet(n, positions, level)) n,
      ];
      if (wave.isEmpty) {
        return nodes.isEmpty ? waves : -1;
      }
      waves++;
      for (final n in wave) {
        nodes.remove(n);
        positions.remove('${n.x},${n.y}');
      }
    }
  }

  /// Finds the first currently-removable node for the hint system.
  ///
  /// Rays are clipped to [gridWidth] × [gridHeight] so down/right scans stay
  /// correct on large boards.
  static NodeData? getHint(
    List<NodeData> activeNodes,
    LevelData level,
  ) {
    final positions = <String>{for (final n in activeNodes) '${n.x},${n.y}'};
    for (final n in activeNodes) {
      if (_canRemoveWithSet(n, positions, level)) return n;
    }
    return null;
  }

  /// Public API: returns true if [node] can be extracted from [allNodes].
  ///
  /// Walks a straight ray across the full bounding grid until it leaves the
  /// board; [LevelData.playCells] does not shorten the ray (void is not an
  /// exit). O(max(n, grid span)) per call.
  static bool canRemove(NodeData node, List<NodeData> allNodes, LevelData level) {
    final others = <String>{};
    for (final o in allNodes) {
      if (o.id != node.id) others.add('${o.x},${o.y}');
    }
    return _canRemoveWithSet(node, others, level);
  }

  // ── Internal helper ──────────────────────────────────────────────────────

  /// Walks the ray cell-by-cell across the full grid: blocked by another node;
  /// clear only when the ray leaves the bounding rectangle.
  static bool _canRemoveWithSet(
    NodeData node,
    Set<String> otherPositions,
    LevelData level,
  ) {
    var x = node.x;
    var y = node.y;
    final gw = level.gridWidth;
    final gh = level.gridHeight;

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
      if (x < 0 || x >= gw || y < 0 || y >= gh) return true;
      if (otherPositions.contains('$x,$y')) return false;
    }
  }
}
