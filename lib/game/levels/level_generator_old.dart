import 'dart:math';
import 'package:flutter/material.dart';
import 'level.dart';
import 'level_solver.dart';

/// Generates solvable Chain Pop puzzles using the **backward-generation algorithm**.
///
/// ### Why this can NEVER produce a deadlock
///
/// The core insight is: we decide the *removal order* before we assign any
/// direction.  When assigning a direction to the node at position [i] in that
/// order, only nodes [i+1 .. N-1] are still on the board (the player has
/// already removed 0 .. i-1).  We ray-cast every candidate direction and
/// reject any that would point toward one of those "future" nodes.
///
/// Therefore:
///   - Node 0 is always free (nothing has been placed "in its way" yet).
///   - Removing node 0 never creates a new block for node 1 (node 1's direction
///     was chosen to avoid nodes 2..N, not node 0).
///   - By induction, every node in the sequence is free when its turn arrives.
///
/// The `LevelSolver.isSolvable()` gate is a double-safety net.  If (due to an
/// extremely dense grid) we cannot find a valid direction even after 50 retries,
/// we fall back to a guaranteed-solvable diagonal layout.
class LevelGenerator {
  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Generate a level for [levelId].
  ///
  /// Uses [levelId] as the primary random seed so the same ID always produces
  /// the same puzzle.  Each retry uses an independently seeded RNG so it
  /// doesn't re-explore the exact same dead-end.
  static LevelData generate(int levelId) {
    final int gridSize = _getGridSize(levelId);
    final int targetNodes = _getTargetNodeCount(levelId);

    for (int attempt = 0; attempt < 50; attempt++) {
      // Each attempt gets its own seed so retries explore different configs.
      final rng = Random(levelId * 31337 + attempt * 999983);
      final level = _buildLevel(levelId, gridSize, targetNodes, rng);
      if (level != null && LevelSolver.isSolvable(level)) {
        return level;
      }
    }

    // Should be unreachable in practice due to the backward guarantee.
    return _safeFallback(levelId, gridSize);
  }

  // ---------------------------------------------------------------------------
  // Core backward-generation
  // ---------------------------------------------------------------------------

  static LevelData? _buildLevel(
      int levelId, int gridSize, int nodeCount, Random rng) {
    // Step 1 – pick N unique grid positions.
    final positions = <Point<int>>[];
    final used = <String>{};
    int safety = 0;
    while (positions.length < nodeCount && safety++ < 50000) {
      final p = Point(rng.nextInt(gridSize), rng.nextInt(gridSize));
      if (used.add('${p.x},${p.y}')) positions.add(p);
    }
    if (positions.length < nodeCount) return null; // Grid too small

    // Step 2 – shuffle → this IS the solution / removal order.
    //   index 0  = first node the player taps   (must be free from the start)
    //   index N-1 = last node the player taps
    final solutionOrder = List<Point<int>>.from(positions)..shuffle(rng);

    // Step 3 – assign directions using the backward guarantee.
    final nodes = <NodeData>[];
    final palette = _palette();

    for (int i = 0; i < solutionOrder.length; i++) {
      final pos = solutionOrder[i];

      // Only nodes that will still be on the board when the player taps [i].
      final futurePositions = solutionOrder.sublist(i + 1);

      final dir = _pickSafeDirection(pos, gridSize, futurePositions, rng);
      if (dir == null) return null; // All 4 directions hit future nodes → retry

      nodes.add(NodeData(
        id: i,
        x: pos.x,
        y: pos.y,
        dir: dir,
        color: palette[rng.nextInt(palette.length)],
      ));
    }

    return LevelData(
      levelId: levelId,
      gridWidth: gridSize,
      gridHeight: gridSize,
      nodes: nodes,
    );
  }

  // ---------------------------------------------------------------------------
  // Direction helpers
  // ---------------------------------------------------------------------------

  /// Returns a shuffled direction that does NOT ray-cast into any of
  /// [futurePositions].  Returns null only when all four directions hit a
  /// future node (only possible on an extremely dense grid).
  static Direction? _pickSafeDirection(
    Point<int> pos,
    int gridSize,
    List<Point<int>> futurePositions,
    Random rng,
  ) {
    // Early exit: if there are no future nodes, every direction is safe.
    if (futurePositions.isEmpty) {
      final dirs = Direction.values.toList()..shuffle(rng);
      return dirs.first;
    }

    // Build a fast lookup set.
    final futureSet = <String>{
      for (final p in futurePositions) '${p.x},${p.y}'
    };

    final shuffled = Direction.values.toList()..shuffle(rng);
    for (final dir in shuffled) {
      if (!_rayHitsFutureSet(pos, dir, gridSize, futureSet)) {
        return dir;
      }
    }
    return null; // All 4 blocked – caller will retry with different positions
  }

  /// Ray-cast from [pos] in [dir] until the grid edge.
  /// Returns true if the ray passes through any position in [futureSet].
  static bool _rayHitsFutureSet(
    Point<int> pos,
    Direction dir,
    int gridSize,
    Set<String> futureSet,
  ) {
    int x = pos.x;
    int y = pos.y;
    while (true) {
      switch (dir) {
        case Direction.up:    y--; break;
        case Direction.down:  y++; break;
        case Direction.left:  x--; break;
        case Direction.right: x++; break;
      }
      if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return false;
      if (futureSet.contains('$x,$y')) return true;
    }
  }

  // ---------------------------------------------------------------------------
  // Safe fallback (only reached if the grid is pathologically dense)
  // ---------------------------------------------------------------------------

  /// Trivially solvable layout: every node is alone in its column pointing up,
  /// so nothing can ever block anything.
  static LevelData _safeFallback(int levelId, int gridSize) {
    final count = gridSize; // one node per column
    final nodes = <NodeData>[];
    final palette = _palette();
    for (int i = 0; i < count; i++) {
      nodes.add(NodeData(
        id: i,
        x: i,
        y: gridSize - 1,
        dir: Direction.up,
        color: palette[i % palette.length],
      ));
    }
    return LevelData(
      levelId: levelId,
      gridWidth: gridSize,
      gridHeight: gridSize,
      nodes: nodes,
    );
  }

  // ---------------------------------------------------------------------------
  // Configuration helpers
  // ---------------------------------------------------------------------------

  static List<Color> _palette() => const [
    Color(0xFF60EFFF),
    Color(0xFF00FF87),
    Color(0xFFFF5F6D),
    Color(0xFFFFC371),
    Color(0xFFA18CD1),
    Color(0xFF4FACFE),
  ];

  /// Grid grows with level ID so puzzles become physically larger.
  static int _getGridSize(int levelId) {
    if (levelId < 5)  return 4;
    if (levelId < 10) return 5;
    if (levelId < 20) return 6;
    if (levelId < 40) return 7;
    return 8;
  }

  /// Node count grows with level ID for increasing difficulty.
  /// Capped at 70 % grid area to keep the grid sparse enough for the
  /// backward algorithm to always find 4 viable directions per node.
  static int _getTargetNodeCount(int levelId) {
    final gridSize = _getGridSize(levelId);
    final maxAllowed = ((gridSize * gridSize) * 0.7).floor();
    final desired = (4 + (levelId * 1.5).floor());
    return desired.clamp(4, maxAllowed);
  }
}
