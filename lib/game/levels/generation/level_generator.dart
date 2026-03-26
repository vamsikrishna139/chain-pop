import 'dart:math';
import 'package:flutter/material.dart';
import '../level.dart';
import 'difficulty_mode.dart';
import 'generation_error.dart';
import 'level_configuration.dart';
import 'level_validator.dart';
import 'result.dart';

/// Generates deterministic, deadlock-free puzzle levels using the **backward
/// generation algorithm**.
///
/// ## Algorithm Overview
///
/// The backward generation algorithm guarantees solvability by construction:
///
/// 1. **Select positions** — Pick N unique random positions on the grid.
/// 2. **Define solution order** — Shuffle positions to create a removal sequence.
///    Index 0 = first node the player removes, index N-1 = last.
/// 3. **Assign directions** — For each node at index `i`, only nodes at indices
///    `i+1..N-1` are still on the board. Assign a direction whose ray does **not**
///    pass through any of those "future" nodes.
/// 4. **Validate** — Run [LevelValidator] as a safety net before returning.
/// 5. **Fallback** — If all retries fail, return a guaranteed-solvable diagonal layout.
///
/// Because each direction is chosen to avoid future nodes, it is mathematically
/// impossible to create a deadlock.
///
/// ## Usage
///
/// ```dart
/// final generator = LevelGenerator();
///
/// // Auto-derive difficulty (level 15 → medium)
/// final result = generator.generate(15);
///
/// // Explicit difficulty mode
/// final hard = generator.generate(5, mode: DifficultyMode.hard);
///
/// if (result.isSuccess) {
///   final level = result.value;
/// } else {
///   print('Failed: ${result.error}');
/// }
/// ```
class LevelGenerator {
  final LevelValidator _validator;

  /// Creates a [LevelGenerator] with an optional custom [validator].
  LevelGenerator({LevelValidator? validator})
      : _validator = validator ?? LevelValidator();

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates a deterministic [LevelData] for the given [levelId].
  ///
  /// The level ID is used as the primary random seed so the same ID always
  /// produces the same puzzle.  Difficulty mode can be auto-derived or
  /// explicitly specified.
  ///
  /// Attempts generation up to 3 times. On persistent failure returns a
  /// simple, guaranteed-solvable fallback level.
  ///
  /// Parameters:
  /// - [levelId] — Unique level identifier, used as random seed.
  /// - [mode] — Optional difficulty override. Auto-derived if omitted:
  ///   levels 0-9 = easy, 10-29 = medium, 30+ = hard.
  ///
  /// Returns a [Result] containing either a valid [LevelData] or a
  /// [GenerationError] describing what went wrong.
  Result<LevelData, GenerationError> generate(
    int levelId, {
    DifficultyMode? mode,
  }) {
    final config = LevelConfiguration.fromLevelId(levelId, mode: mode);

    final validation = config.validate();
    if (!validation.isValid) {
      return Result.error(
        GenerationError.invalidConfiguration(validation.message),
      );
    }

    // Each attempt uses a different seed derived from levelId and attempt index
    // so retries genuinely explore different configurations.
    for (int attempt = 0; attempt < 3; attempt++) {
      final rng = Random(levelId * 31337 + attempt * 999983);
      final result = _attemptGeneration(config, rng);

      if (result.isSuccess) {
        final validationResult = _validator.validate(result.value);
        if (validationResult.isValid) {
          return Result.success(result.value);
        }
      }
    }

    // All attempts failed — return a guaranteed-solvable fallback.
    return Result.success(_generateFallbackLevel(config));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Core backward-generation (Tasks 9.1 – 9.3)
  // ──────────────────────────────────────────────────────────────────────────

  /// Single generation attempt implementing the backward algorithm.
  ///
  /// Steps:
  /// 1. Select unique random positions.
  /// 2. Shuffle to define solution order.
  /// 3. Assign directions respecting solution order.
  Result<LevelData, GenerationError> _attemptGeneration(
    LevelConfiguration config,
    Random random,
  ) {
    try {
      final positions = _selectUniquePositions(
        config.targetNodeCount,
        config.gridWidth,
        config.gridHeight,
        random,
      );

      if (positions.length < config.targetNodeCount) {
        return Result.error(
          GenerationError.noValidDirections('Grid too small for requested nodes'),
        );
      }

      final solutionPath = List<Point<int>>.from(positions)..shuffle(random);

      final nodes = _assignDirections(
        solutionPath,
        config.gridWidth,
        config.gridHeight,
        random,
      );

      if (nodes == null) {
        return Result.error(
          GenerationError.noValidDirections(
            'Could not assign valid directions to all nodes',
          ),
        );
      }

      return Result.success(LevelData(
        levelId: config.levelId,
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        nodes: nodes,
      ));
    } catch (e) {
      return Result.error(GenerationError.unexpected('Generation failed: $e'));
    }
  }

  /// Selects [count] unique random positions within [gridWidth] × [gridHeight].
  ///
  /// Uses a [Set] for O(1) membership checks. Expected O(n) time; O(n²) in
  /// worst case on a nearly-full grid.
  List<Point<int>> _selectUniquePositions(
    int count,
    int gridWidth,
    int gridHeight,
    Random random,
  ) {
    final positions = <Point<int>>[];
    final used = <String>{};

    int safety = 0;
    while (positions.length < count && safety++ < count * 100) {
      final x = random.nextInt(gridWidth);
      final y = random.nextInt(gridHeight);
      final key = '$x,$y';
      if (used.add(key)) {
        positions.add(Point(x, y));
      }
    }

    return positions;
  }

  /// Assigns directions to nodes respecting the backward-generation guarantee.
  ///
  /// For the node at index `i` in [solutionPath], only nodes at indices
  /// `i+1..N-1` are still on the board. The assigned direction must not
  /// ray-cast into any of those "future" positions.
  ///
  /// Returns null if any node has no valid direction (triggers a retry).
  ///
  /// Complexity: O(n²) where n = solutionPath.length (each node scans future nodes).
  List<NodeData>? _assignDirections(
    List<Point<int>> solutionPath,
    int gridWidth,
    int gridHeight,
    Random random,
  ) {
    final nodes = <NodeData>[];
    final palette = _getColorPalette();

    for (int i = 0; i < solutionPath.length; i++) {
      final position = solutionPath[i];

      // Nodes that are still on the board when the player taps node [i].
      final futureNodes = solutionPath.sublist(i + 1);

      final direction = _findValidDirection(
        position,
        futureNodes,
        gridWidth,
        gridHeight,
        random,
      );

      if (direction == null) return null; // Retry

      nodes.add(NodeData(
        id: i,
        x: position.x,
        y: position.y,
        dir: direction,
        color: palette[random.nextInt(palette.length)],
      ));
    }

    return nodes;
  }

  /// Finds a direction from [position] whose ray does not hit any [futureNodes].
  ///
  /// Shuffles directions for randomness (Requirement 7.3), then returns the
  /// first clear direction. Returns null only if all four directions are blocked
  /// (extremely rare on a grid with ≤70% density).
  Direction? _findValidDirection(
    Point<int> position,
    List<Point<int>> futureNodes,
    int gridWidth,
    int gridHeight,
    Random random,
  ) {
    // Early exit: no future nodes means all directions are valid.
    if (futureNodes.isEmpty) {
      final dirs = Direction.values.toList()..shuffle(random);
      return dirs.first;
    }

    // Build a O(1) lookup set for future positions.
    final futureSet = <String>{
      for (final p in futureNodes) '${p.x},${p.y}',
    };

    final shuffled = Direction.values.toList()..shuffle(random);
    for (final dir in shuffled) {
      if (!_directionHitsNodes(position, dir, futureSet, gridWidth, gridHeight)) {
        return dir;
      }
    }

    return null; // All 4 directions blocked
  }

  /// Ray-casts from [position] in [dir] until the grid edge.
  ///
  /// Returns `true` if the ray passes through any position in [futureSet],
  /// `false` if the ray clears the grid without hitting any future node.
  ///
  /// Complexity: O(max(gridWidth, gridHeight)) per call.
  bool _directionHitsNodes(
    Point<int> position,
    Direction dir,
    Set<String> futureSet,
    int gridWidth,
    int gridHeight,
  ) {
    int x = position.x;
    int y = position.y;

    while (true) {
      switch (dir) {
        case Direction.up:    y--; break;
        case Direction.down:  y++; break;
        case Direction.left:  x--; break;
        case Direction.right: x++; break;
      }

      // Ray left the grid — path is clear.
      if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return false;

      // Ray hit a future node — direction is blocked.
      if (futureSet.contains('$x,$y')) return true;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Fallback level generation (Task 10.1)
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates a simple, guaranteed-solvable fallback level.
  ///
  /// Layout: each node is placed in a unique column on the bottom row,
  /// pointing up. Since no two nodes share a row or column, nothing can
  /// ever block anything.
  ///
  /// Only used when the backward algorithm fails after all retries
  /// (should not occur under normal circumstances).
  LevelData _generateFallbackLevel(LevelConfiguration config) {
    final count = min(config.targetNodeCount, config.gridWidth);
    final palette = _getColorPalette();
    final nodes = <NodeData>[];

    for (int i = 0; i < count; i++) {
      nodes.add(NodeData(
        id: i,
        x: i,
        y: config.gridHeight - 1,
        dir: Direction.up,
        color: palette[i % palette.length],
      ));
    }

    return LevelData(
      levelId: config.levelId,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      nodes: nodes,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helper methods (Task 11)
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns the 6-colour palette used for node colouring (Requirement 7.4).
  List<Color> _getColorPalette() => const [
    Color(0xFF60EFFF),
    Color(0xFF00FF87),
    Color(0xFFFF5F6D),
    Color(0xFFFFC371),
    Color(0xFFA18CD1),
    Color(0xFF4FACFE),
  ];

  /// Calculates the grid size for a given [levelId] and [mode].
  ///
  /// Delegates to [LevelConfiguration._calculateGridSize] via a
  /// [LevelConfiguration.fromLevelId] call. Exposed as a static helper
  /// for callers that need the grid size without full configuration.
  ///
  /// - Easy:   4×4 → 6×6
  /// - Medium: 6×6 → 10×10
  /// - Hard:   10×10 → 20×20
  static int calculateGridSize(int levelId, DifficultyMode mode) {
    return LevelConfiguration.fromLevelId(levelId, mode: mode).gridWidth;
  }

  /// Calculates the target node count for a given [levelId] and [mode].
  ///
  /// Delegates to [LevelConfiguration.fromLevelId]. Exposed as a static
  /// helper for external callers (e.g. performance tests).
  static int calculateNodeCount(int levelId, DifficultyMode mode) {
    return LevelConfiguration.fromLevelId(levelId, mode: mode).targetNodeCount;
  }
}
