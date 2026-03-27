import 'dart:collection';
import 'level.dart';

/// Stateless solver utilities for Chain Pop.
///
/// Performance notes:
/// - [canRemove] is O(n) — called once per tap, acceptable.
/// - [isSolvable] uses wave-based BFS with a position Set — O(n²) worst case
///   but with much smaller constant than the old break-and-restart loop.
/// - [getHint] builds a position Set once for all O(1) direction checks.
class LevelSolver {
  /// Returns true if the level can be fully cleared from its initial state.
  ///
  /// Uses wave-based removal: instead of restarting from index 0 after every
  /// single removal, all simultaneously removable nodes are cleared in one
  /// "wave". This reduces iterations from O(n²) to O(waves × n).
  static bool isSolvable(LevelData level) {
    final nodes = level.nodes.map((n) => n.clone()).toList();
    final positions = <String>{for (final n in nodes) '${n.x},${n.y}'};

    while (true) {
      // Collect every node that is currently removable in this wave.
      final wave = [
        for (final n in nodes)
          if (_canRemoveWithSet(n, positions)) n,
      ];
      if (wave.isEmpty) break;

      for (final n in wave) {
        nodes.remove(n);
        positions.remove('${n.x},${n.y}');
      }
    }
    return nodes.isEmpty;
  }

  /// Finds the first currently-removable node for the hint system.
  ///
  /// Builds the position set once, then checks each node in O(grid_size) — 
  /// far fewer string comparisons than the old O(n) list scan per node.
  static NodeData? getHint(List<NodeData> activeNodes) {
    final positions = <String>{for (final n in activeNodes) '${n.x},${n.y}'};
    for (final n in activeNodes) {
      if (_canRemoveWithSet(n, positions)) return n;
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
  /// Walks the ray cell-by-cell and checks the O(1) Set instead of scanning
  /// the full node list.  Grid size upper-bound keeps the loop bounded.
  static bool _canRemoveWithSet(NodeData node, Set<String> positions) {
    switch (node.dir) {
      case Direction.up:
        for (int y = node.y - 1; y >= 0; y--) {
          if (positions.contains('${node.x},$y')) return false;
        }
      case Direction.down:
        for (int y = node.y + 1; y <= 20; y++) {
          if (positions.contains('${node.x},$y')) return false;
        }
      case Direction.left:
        for (int x = node.x - 1; x >= 0; x--) {
          if (positions.contains('$x,${node.y}')) return false;
        }
      case Direction.right:
        for (int x = node.x + 1; x <= 20; x++) {
          if (positions.contains('$x,${node.y}')) return false;
        }
    }
    return true;
  }
}
