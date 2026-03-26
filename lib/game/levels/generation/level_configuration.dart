import 'dart:math';
import 'difficulty_mode.dart';
import 'difficulty_parameters.dart';
import 'validation_result.dart';

/// Immutable configuration class that encapsulates all parameters for level generation.
///
/// This class defines the grid dimensions, target node count, and difficulty parameters
/// for generating a puzzle level. It provides factory constructors for deriving
/// configurations from level IDs with automatic or explicit difficulty mode selection.
///
/// Example usage:
/// ```dart
/// // Auto-derive difficulty from level ID
/// final config = LevelConfiguration.fromLevelId(15);
///
/// // Explicit difficulty mode
/// final hardConfig = LevelConfiguration.fromLevelId(5, mode: DifficultyMode.hard);
/// ```
class LevelConfiguration {
  /// Unique identifier for this level
  final int levelId;
  
  /// Width of the grid in cells
  final int gridWidth;
  
  /// Height of the grid in cells
  final int gridHeight;
  
  /// Target number of nodes to place in the level
  final int targetNodeCount;
  
  /// Difficulty parameters controlling level complexity
  final DifficultyParameters difficulty;
  
  const LevelConfiguration({
    required this.levelId,
    required this.gridWidth,
    required this.gridHeight,
    required this.targetNodeCount,
    required this.difficulty,
  });
  
  /// Factory constructor that derives configuration from level ID.
  ///
  /// If [mode] is not specified, automatically derives the difficulty mode
  /// from the level ID (0-9: easy, 10-29: medium, 30+: hard).
  ///
  /// Example:
  /// ```dart
  /// // Auto-derive mode (level 5 will be easy)
  /// final config1 = LevelConfiguration.fromLevelId(5);
  ///
  /// // Explicit hard mode for level 5
  /// final config2 = LevelConfiguration.fromLevelId(5, mode: DifficultyMode.hard);
  /// ```
  factory LevelConfiguration.fromLevelId(int levelId, {DifficultyMode? mode}) {
    // Get difficulty parameters (auto-derived or explicit mode)
    final difficulty = DifficultyParameters.fromLevelId(levelId, mode: mode);
    
    // Calculate grid size based on difficulty mode
    final gridSize = _calculateGridSize(levelId, difficulty.mode);
    
    // Calculate node count within difficulty constraints
    final nodeCount = _calculateNodeCount(levelId, gridSize, difficulty);
    
    return LevelConfiguration(
      levelId: levelId,
      gridWidth: gridSize,
      gridHeight: gridSize,
      targetNodeCount: nodeCount,
      difficulty: difficulty,
    );
  }
  
  /// Factory constructor with explicit difficulty mode.
  ///
  /// Convenience method for creating a configuration with a specific difficulty mode.
  ///
  /// Example:
  /// ```dart
  /// final config = LevelConfiguration.withMode(10, DifficultyMode.easy);
  /// ```
  factory LevelConfiguration.withMode(int levelId, DifficultyMode mode) {
    return LevelConfiguration.fromLevelId(levelId, mode: mode);
  }
  
  /// Validates that configuration parameters are within acceptable ranges.
  ///
  /// Checks:
  /// - Level ID is non-negative
  /// - Grid dimensions are at least 3x3
  /// - Grid dimensions do not exceed 20x20
  /// - Node count is at least 3
  /// - Node count does not exceed grid capacity
  /// - Node count does not exceed 400
  ///
  /// Returns a [ValidationResult] indicating success or failure with error message.
  ValidationResult validate() {
    if (levelId < 0) {
      return ValidationResult.error('Level ID must be non-negative');
    }
    if (gridWidth < 3 || gridHeight < 3) {
      return ValidationResult.error('Grid dimensions must be at least 3x3');
    }
    if (gridWidth > 20 || gridHeight > 20) {
      return ValidationResult.error('Grid dimensions must not exceed 20x20');
    }
    if (targetNodeCount < 3) {
      return ValidationResult.error('Must have at least 3 nodes');
    }
    if (targetNodeCount > gridWidth * gridHeight) {
      return ValidationResult.error('Node count exceeds grid capacity');
    }
    if (targetNodeCount > 400) {
      return ValidationResult.error('Node count must not exceed 400');
    }
    return ValidationResult.success();
  }
  
  /// Calculates grid size based on level ID and difficulty mode.
  ///
  /// Grid size progression:
  /// - Easy: 4x4 to 6x6
  /// - Medium: 6x6 to 10x10
  /// - Hard: 10x10 to 20x20
  static int _calculateGridSize(int levelId, DifficultyMode mode) {
    switch (mode) {
      case DifficultyMode.easy:
        // 4x4 to 6x6
        return (4 + (levelId / 10).floor()).clamp(4, 6);
      case DifficultyMode.medium:
        // 6x6 to 10x10
        return (6 + (levelId / 8).floor()).clamp(6, 10);
      case DifficultyMode.hard:
        // 10x10 to 20x20
        return (10 + (levelId / 5).floor()).clamp(10, 20);
    }
  }
  
  /// Calculates node count based on level ID, grid size, and difficulty parameters.
  ///
  /// The calculation:
  /// 1. Starts with a base count from level progression
  /// 2. Applies density factor to respect grid capacity
  /// 3. Clamps to difficulty min/max constraints
  static int _calculateNodeCount(
    int levelId,
    int gridSize,
    DifficultyParameters difficulty,
  ) {
    // Base count from level progression
    final baseCount = (difficulty.minNodes + (levelId * 0.5).floor());
    
    // Apply density factor
    final maxPossible = (gridSize * gridSize * difficulty.densityFactor).floor();
    
    // Clamp to difficulty constraints
    return baseCount.clamp(
      difficulty.minNodes,
      min(difficulty.maxNodes, maxPossible),
    );
  }
}
