import 'dart:math';
import 'package:flutter/material.dart';
import 'level.dart';
import 'level_solver.dart';

class LevelGenerator {
  static final Random _random = Random();

  static LevelData generate(int levelId) {
    final int gridSize = _getGridSize(levelId);
    final int targetNodes = _getTargetNodeCount(levelId);

    // 1. Pick unique random positions for the required number of nodes
    final List<Point<int>> positions = [];
    while (positions.length < targetNodes) {
      final p = Point(_random.nextInt(gridSize), _random.nextInt(gridSize));
      if (!positions.any((existing) => existing.x == p.x && existing.y == p.y)) {
        positions.add(p);
      }
    }

    // 2. Define the exact REMOVAL ORDER (The Solution Sequence)
    // The node at index 0 will be the FIRST one the player removes.
    // The node at the end will be the LAST one the player removes.
    final List<Point<int>> removalOrder = List.from(positions)..shuffle(_random);

    final List<NodeData> finalNodes = [];
    final List<Color> palette = [
      const Color(0xFF60EFFF),
      const Color(0xFF00FF87),
      const Color(0xFFFF5F6D),
      const Color(0xFFFFC371),
      const Color(0xFFA18CD1),
      const Color(0xFF4FACFE),
    ];

    // 3. Assign directions based on the dependency chain
    // For each node 'current' in removalOrder:
    // It can point in any direction as long as NO OTHER node that comes AFTER it
    // in the removalOrder is in its path.
    // Nodes that come BEFORE it will already be gone when the player taps this node.
    for (int i = 0; i < removalOrder.length; i++) {
      final currentPos = removalOrder[i];

      // These are nodes still on the board when the player attempts to remove 'current'
      final futureNodes = removalOrder.sublist(i + 1);

      final Direction validDir = _findValidDirection(
        currentPos,
        gridSize,
        futureNodes,
      );

      finalNodes.add(NodeData(
        id: i,
        x: currentPos.x,
        y: currentPos.y,
        dir: validDir,
        color: palette[_random.nextInt(palette.length)],
      ));
    }

    return LevelData(
      levelId: levelId,
      gridWidth: gridSize,
      gridHeight: gridSize,
      nodes: finalNodes,
    );
  }

  static Direction _findValidDirection(
    Point<int> pos,
    int gridSize,
    List<Point<int>> blockingCandidates,
  ) {
    final List<Direction> shuffledDirs = Direction.values.toList()..shuffle(_random);

    // Check which directions have a clear path (ignoring nodes that will be removed later)
    for (final dir in shuffledDirs) {
      if (!_hitsAny(pos, dir, gridSize, blockingCandidates)) {
        return dir;
      }
    }

    // Fallback: If absolutely crowded, we pick the best possible (should not happen on normal levels)
    return shuffledDirs.first;
  }

  static bool _hitsAny(Point<int> pos, Direction dir, int gridSize, List<Point<int>> others) {
    int cx = pos.x;
    int cy = pos.y;

    while (true) {
      switch (dir) {
        case Direction.up: cy--; break;
        case Direction.down: cy++; break;
        case Direction.left: cx--; break;
        case Direction.right: cx++; break;
      }

      if (cx < 0 || cx >= gridSize || cy < 0 || cy >= gridSize) {
        return false; // Reached edge - clear!
      }

      if (others.any((p) => p.x == cx && p.y == cy)) {
        return true; // Hits a node that is still on the board
      }
    }
  }

  static int _getGridSize(int levelId) {
    if (levelId < 5) return 4;
    if (levelId < 10) return 5;
    return 6;
  }

  static int _getTargetNodeCount(int levelId) {
    return (4 + (levelId * 1.5).floor()).clamp(4, 30);
  }
}
