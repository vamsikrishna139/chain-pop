import 'dart:math';
import 'package:flutter/material.dart';
import '../level.dart';
import 'difficulty_mode.dart';
import 'generation_error.dart';
import 'level_configuration.dart';
import 'level_validator.dart';
import 'result.dart';

/// Core generation class implementing the backward generation algorithm.
///
/// The LevelGenerator produces deterministic, solvable puzzle levels using a
/// backward generation approach. It constructs levels by first defining a valid
/// solution path, then assigning node directions that respect this solution order.
///
/// Example usage:
/// ```dart
/// final generator = LevelGenerator();
///
/// // Auto-derive difficulty from level ID
/// final result = generator.generate(15);
///
/// // Explicit difficulty mode
/// final hardResult = generator.generate(5, mode: DifficultyMode.hard);
///
/// if (result.isSuccess) {
///   final level = result.value;
///   print('Generated level with ${level.nodes.length} nodes');
/// } else {
///   print('Generation failed: ${result.error}');
/// }
/// ```
class LevelGenerator {
  final Random _random;
  final LevelValidator _validator;

  /// Creates a new LevelGenerator with optional dependencies.
  ///
  /// [random] - Random number generator for non-deterministic operations.
  ///            Defaults to a new Random() instance.
  /// [validator] - Level validator for verifying generated levels.
  ///               Defaults to a new LevelValidator() instance.
  LevelGenerator({
    Random? random,
    LevelValidator? validator,
  })  : _random = random ?? Random(),
        _validator = validator ?? LevelValidator();

  /// Generates a deterministic level from a level identifier.
  ///
  /// The level ID is used as a seed for random generation, ensuring that
  /// the same ID always produces the same level. The difficulty mode can be
  /// explicitly specified or auto-derived from the level ID.
  ///
  /// Parameters:
  /// - [levelId] - Unique identifier for the level (used as random seed)
  /// - [mode] - Optional difficulty mode (easy/medium/hard). If not specified,
  ///            mode is auto-derived: 0-9=easy, 10-29=medium, 30+=hard
  ///
  /// Returns a [Result] containing either:
  /// - Success: A valid, solvable [LevelData]
  /// - Error: A [GenerationError] describing what went wrong
  ///
  /// The generator attempts generation up to 3 times. If all attempts fail,
  /// it returns a simple fallback level that is guaranteed to be solvable.
  ///
  /// Example:
  /// ```dart
  /// // Auto-derive difficulty (level 15 will be medium)
  /// final result1 = generator.generate(15);
  ///
  /// // Force easy mode for level 50
  /// final result2 = generator.generate(50, mode: DifficultyMode.easy);
  /// ```
  Result<LevelData, GenerationError> generate(
    int levelId, {
    DifficultyMode? mode,
  }) {
    // Create configuration from level ID with optional mode
    final config = LevelConfiguration.fromLevelId(levelId, mode: mode);

    // Validate configuration
    final validationResult = config.validate();
    if (!validationResult.isValid) {
      return Result.error(
        GenerationError.invalidConfiguration(validationResult.message),
      );
    }

    // Seed random generator for deterministic generation
    final seededRandom = Random(levelId);

    // Attempt generation with retries (3 attempts)
    for (int attempt = 0; attempt < 3; attempt++) {
      final result = _attemptGeneration(config, seededRandom);

      if (result.isSuccess) {
        final level = result.value;
        final validation = _validator.validate(level);

        if (validation.isValid) {
          return Result.success(level);
        }
      }
    }

    // Fallback to simple level after max retries
    return Result.success(_generateFallbackLevel(config));
  }

  /// Single generation attempt using backward algorithm.
  ///
  /// This method implements the core backward generation algorithm:
  /// 1. Select unique random positions for all nodes
  /// 2. Shuffle positions to create a random solution path order
  /// 3. Assign valid directions to each node in solution order
  ///
  /// Returns a [Result] containing either a generated [LevelData] or a
  /// [GenerationError] if the attempt failed.
  Result<LevelData, GenerationError> _attemptGeneration(
    LevelConfiguration config,
    Random random,
  ) {
    try {
      // Step 1: Select unique random positions
      final positions = _selectUniquePositions(
        config.targetNodeCount,
        config.gridWidth,
        config.gridHeight,
        random,
      );

      // Step 2: Shuffle to create solution path order
      final solutionPath = List<Point<int>>.from(positions)..shuffle(random);

      // Step 3: Assign directions respecting solution order
      final nodes = _assignDirections(
        solutionPath,
        config.gridWidth,
        config.gridHeight,
        random,
      );

      if (nodes == null) {
        return Result.error(
          GenerationError.noValidDirections('Could not assign valid directions'),
        );
      }

      return Result.success(LevelData(
        levelId: config.levelId,
        gridWidth: config.gridWidth,
        gridHeight: config.gridHeight,
        nodes: nodes,
      ));
    } catch (e) {
      return Result.error(
        GenerationError.unexpected('Generation failed: $e'),
      );
    }
  }

  /// Selects unique random positions on the grid.
  ///
  /// Generates [count] random unique positions within the grid bounds.
  /// Uses a Set for O(1) lookup to efficiently track used positions.
  ///
  /// Parameters:
  /// - [count] - Number of unique positions to generate
  /// - [gridWidth] - Width of the grid
  /// - [gridHeight] - Height of the grid
  /// - [random] - Random number generator for position selection
  ///
  /// Returns a list of [count] unique Point<int> positions.
  ///
  /// Complexity: O(n) expected time where n = count
  /// Worst case: O(n²) if grid is nearly full
  List<Point<int>> _selectUniquePositions(
    int count,
    int gridWidth,
    int gridHeight,
    Random random,
  ) {
    final positions = <Point<int>>[];
    final Set<String> used = {};

    while (positions.length < count) {
      final x = random.nextInt(gridWidth);
      final y = random.nextInt(gridHeight);
      final key = '$x,$y';

      if (!used.contains(key)) {
        positions.add(Point(x, y));
        used.add(key);
      }
    }

    return positions;
  }

  /// Assigns directions to nodes respecting solution path order.
  ///
  /// TODO: Implement in task 9.1
  /// This is a stub implementation that assigns placeholder directions.
  ///
  /// Returns null if no valid assignment exists.
  List<NodeData>? _assignDirections(
    List<Point<int>> solutionPath,
    int gridWidth,
    int gridHeight,
    Random random,
  ) {
    // Stub: Assign all nodes pointing up for now
    final nodes = <NodeData>[];
    final palette = _getColorPalette();

    for (int i = 0; i < solutionPath.length; i++) {
      final position = solutionPath[i];
      nodes.add(NodeData(
        id: i,
        x: position.x,
        y: position.y,
        dir: Direction.up,
        color: palette[random.nextInt(palette.length)],
      ));
    }

    return nodes;
  }

  /// Finds a valid direction that doesn't hit future nodes.
  ///
  /// TODO: Implement in task 9.2
  /// This is a stub implementation.
  Direction? _findValidDirection(
    Point<int> position,
    List<Point<int>> futureNodes,
    int gridWidth,
    int gridHeight,
    Random random,
  ) {
    // Stub: Always return up for now
    return Direction.up;
  }

  /// Checks if a direction from a position hits any of the given nodes.
  ///
  /// TODO: Implement in task 9.3
  /// This is a stub implementation.
  bool _directionHitsNodes(
    Point<int> position,
    Direction direction,
    List<Point<int>> nodes,
    int gridWidth,
    int gridHeight,
  ) {
    // Stub: Always return false (no collision) for now
    return false;
  }

  /// Generates a simple fallback level when generation fails.
  ///
  /// TODO: Implement in task 10.1
  /// This is a stub implementation that creates a minimal valid level.
  LevelData _generateFallbackLevel(LevelConfiguration config) {
    // Stub: Create a simple diagonal pattern
    final nodes = <NodeData>[];
    final count = min(
      config.targetNodeCount,
      min(config.gridWidth, config.gridHeight),
    );

    for (int i = 0; i < count; i++) {
      nodes.add(NodeData(
        id: i,
        x: i,
        y: i,
        dir: Direction.up,
        color: const Color(0xFF4FACFE),
      ));
    }

    return LevelData(
      levelId: config.levelId,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      nodes: nodes,
    );
  }

  /// Returns the color palette for node colors.
  ///
  /// TODO: Implement in task 11.1
  /// This is a stub implementation.
  List<Color> _getColorPalette() {
    // Stub: Return basic palette
    return const [
      Color(0xFF60EFFF),
      Color(0xFF00FF87),
      Color(0xFFFF5F6D),
      Color(0xFFFFC371),
      Color(0xFFA18CD1),
      Color(0xFF4FACFE),
    ];
  }
}
