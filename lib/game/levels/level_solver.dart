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
    final gw = level.gridWidth;
    final gh = level.gridHeight;
    final positions = <String>{for (final n in nodes) '${n.x},${n.y}'};
    var waves = 0;

    while (true) {
      final wave = [
        for (final n in nodes)
          if (_canRemoveWithSet(n, positions, gw, gh)) n,
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
    int gridWidth,
    int gridHeight,
  ) {
    final positions = <String>{for (final n in activeNodes) '${n.x},${n.y}'};
    for (final n in activeNodes) {
      if (_canRemoveWithSet(n, positions, gridWidth, gridHeight)) return n;
    }
    return null;
  }

  /// Public API: returns true if [node] can be extracted from [allNodes].
  ///
  /// O(n) per call — called once per tap, acceptable.
  static bool canRemove(NodeData node, List<NodeData> allNodes) {
    for (final other in allNodes) {
      if (other.id == node.id) continue;
      switch (node.dir) {
        case Direction.up:
          if (other.x == node.x && other.y < node.y) return false;
        case Direction.down:
          if (other.x == node.x && other.y > node.y) return false;
        case Direction.left:
          if (other.y == node.y && other.x < node.x) return false;
        case Direction.right:
          if (other.y == node.y && other.x > node.x) return false;
      }
    }
    return true;
  }

  // ── Internal helper ──────────────────────────────────────────────────────

  /// Position-set variant of [canRemove].
  ///
  /// Walks the ray cell-by-cell until the grid edge and checks the O(1) Set.
  static bool _canRemoveWithSet(
    NodeData node,
    Set<String> positions,
    int gridWidth,
    int gridHeight,
  ) {
    switch (node.dir) {
      case Direction.up:
        for (var y = node.y - 1; y >= 0; y--) {
          if (positions.contains('${node.x},$y')) return false;
        }
      case Direction.down:
        for (var y = node.y + 1; y < gridHeight; y++) {
          if (positions.contains('${node.x},$y')) return false;
        }
      case Direction.left:
        for (var x = node.x - 1; x >= 0; x--) {
          if (positions.contains('$x,${node.y}')) return false;
        }
      case Direction.right:
        for (var x = node.x + 1; x < gridWidth; x++) {
          if (positions.contains('$x,${node.y}')) return false;
        }
    }
    return true;
  }
}
