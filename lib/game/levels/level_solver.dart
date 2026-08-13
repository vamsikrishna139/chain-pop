import 'grid_cell_key.dart';
import 'level.dart';

/// Result of tracing a node's facing ray across the board.
class RayTraceResult {
  /// Grid cell where the ray stops (blocker cell or last in-bounds cell).
  final int endX;
  final int endY;

  /// When the ray hits another node before exiting the grid.
  final int? blockerNodeId;

  const RayTraceResult({
    required this.endX,
    required this.endY,
    this.blockerNodeId,
  });

  bool get hitsBlocker => blockerNodeId != null;
}

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
    final positions = <int>{for (final n in nodes) gridCellKey(n.x, n.y)};
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
        positions.remove(gridCellKey(n.x, n.y));
      }
    }
  }

  /// Returns a map of node ID to its parallel-removal wave index.
  ///
  /// Solves the level in waves (similar to [countRemovalWaves]) and records the
  /// wave index at which each node is extracted. If a node cannot be cleared,
  /// its ID will not be in the map.
  static Map<int, int> nodeWaveIndices(LevelData level) {
    final nodes = level.nodes.map((n) => n.clone()).toList();
    final positions = <int>{for (final n in nodes) gridCellKey(n.x, n.y)};
    final waveIndices = <int, int>{};
    var waves = 0;

    while (true) {
      final wave = [
        for (final n in nodes)
          if (_canRemoveWithSet(n, positions, level)) n,
      ];
      if (wave.isEmpty) {
        break;
      }
      for (final n in wave) {
        waveIndices[n.id] = waves;
        nodes.remove(n);
        positions.remove(gridCellKey(n.x, n.y));
      }
      waves++;
    }
    return waveIndices;
  }

  /// Finds the first currently-removable node for the hint system.
  ///
  /// Rays are clipped to [gridWidth] × [gridHeight] so down/right scans stay
  /// correct on large boards.
  static NodeData? getHint(
    List<NodeData> activeNodes,
    LevelData level,
  ) {
    final positions = <int>{
      for (final n in activeNodes) gridCellKey(n.x, n.y),
    };
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
    final others = <int>{};
    for (final o in allNodes) {
      if (o.id != node.id) others.add(gridCellKey(o.x, o.y));
    }
    return _canRemoveWithSet(node, others, level);
  }

  /// Like [canRemove] but uses a pre-built occupancy set ([gridCellKey] ints).
  ///
  /// Caller must exclude [node]'s own cell key from [otherPositions] so the ray
  /// is not blocked by itself. Each call is O(grid span); batching rebuilds
  /// with one set is O(n × grid span) instead of O(n²).
  static bool canRemoveWithPositions(
    NodeData node,
    Set<int> otherPositions,
    LevelData level,
  ) {
    return _canRemoveWithSet(node, otherPositions, level);
  }

  /// Traces [node]'s facing ray to the grid edge or the first blocking node.
  static RayTraceResult traceRay(
    NodeData node,
    List<NodeData> activeNodes,
    LevelData level,
  ) {
    final idByCell = <int, int>{};
    for (final n in activeNodes) {
      if (n.id != node.id) {
        idByCell[gridCellKey(n.x, n.y)] = n.id;
      }
    }

    var x = node.x;
    var y = node.y;
    final gw = level.gridWidth;
    final gh = level.gridHeight;

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
      if (x < 0 || x >= gw || y < 0 || y >= gh) {
        return RayTraceResult(endX: x, endY: y, blockerNodeId: null);
      }
      final blockerId = idByCell[gridCellKey(x, y)];
      if (blockerId != null) {
        return RayTraceResult(
          endX: x,
          endY: y,
          blockerNodeId: blockerId,
        );
      }
      
      // Portal check
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
    // If it exceeds hops (infinite loop), treat as blocked (unsolvable)
    return RayTraceResult(endX: x, endY: y, blockerNodeId: -1);
  }

  // ── Internal helper ──────────────────────────────────────────────────────

  /// Walks the ray cell-by-cell across the full grid: blocked by another node;
  /// clear only when the ray leaves the bounding rectangle.
  static bool _canRemoveWithSet(
    NodeData node,
    Set<int> otherPositions,
    LevelData level,
  ) {
    if (node.kind == NodeKind.locked && _lockedNeighborsRemain(node, otherPositions, level)) {
      return false;
    }
    if (node.phaseGroup > 0 && _earlierPhaseRemains(node, otherPositions, level)) {
      return false;
    }
    var x = node.x;
    var y = node.y;
    final gw = level.gridWidth;
    final gh = level.gridHeight;

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
      if (x < 0 || x >= gw || y < 0 || y >= gh) return true;
      if (otherPositions.contains(gridCellKey(x, y))) return false;
      
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
    return false; // Loop detected, considered blocked
  }

  static bool _lockedNeighborsRemain(
    NodeData node,
    Set<int> otherPositions,
    LevelData level,
  ) {
    for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
      final nx = node.x + dx;
      final ny = node.y + dy;
      if (nx < 0 || nx >= level.gridWidth || ny < 0 || ny >= level.gridHeight) {
        continue;
      }
      if (otherPositions.contains(gridCellKey(nx, ny))) return true;
    }
    return false;
  }

  static bool _earlierPhaseRemains(
    NodeData node,
    Set<int> otherPositions,
    LevelData level,
  ) {
    for (final other in level.nodes) {
      if (other.phaseGroup < node.phaseGroup &&
          otherPositions.contains(gridCellKey(other.x, other.y))) {
        return true;
      }
    }
    return false;
  }
}
