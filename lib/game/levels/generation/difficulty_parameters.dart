import 'difficulty_mode.dart';

/// Immutable parameters that define difficulty characteristics for level generation
class DifficultyParameters {
  /// The difficulty mode
  final DifficultyMode mode;
  
  /// Target minimum **removal waves** — rounds of “extract all currently free
  /// nodes” ([LevelSolver.countRemovalWaves]) before the board is empty.
  /// [LevelGenerator.removalWaveBounds] may lower this for Hard/Medium on
  /// smaller layouts so generation does not always fall back.
  final int minChainLength;

  /// Target maximum removal waves (clamped to node count in [removalWaveBounds]).
  final int maxChainLength;
  
  /// Density factor (0.0-1.0) controlling how full the grid should be
  final double densityFactor;
  
  /// Minimum number of nodes for this difficulty
  final int minNodes;
  
  /// Maximum number of nodes for this difficulty
  final int maxNodes;
  
  const DifficultyParameters({
    required this.mode,
    required this.minChainLength,
    required this.maxChainLength,
    required this.densityFactor,
    required this.minNodes,
    required this.maxNodes,
  });
  
  /// Creates difficulty parameters from a level ID
  /// 
  /// If [mode] is not specified, derives the mode from the level ID:
  /// - Levels 0-9: Easy
  /// - Levels 10-29: Medium
  /// - Levels 30+: Hard
  factory DifficultyParameters.fromLevelId(int levelId, {DifficultyMode? mode}) {
    // If mode not specified, derive from level ID
    final effectiveMode = mode ?? _deriveModeFromLevel(levelId);
    
    switch (effectiveMode) {
      case DifficultyMode.easy:
        return const DifficultyParameters(
          mode: DifficultyMode.easy,
          minChainLength: 2,
          maxChainLength: 4,
          densityFactor: 0.25,
          minNodes: 4,
          maxNodes: 12,
        );
      case DifficultyMode.medium:
        return const DifficultyParameters(
          mode: DifficultyMode.medium,
          minChainLength: 2,
          maxChainLength: 8,
          densityFactor: 0.45,
          minNodes: 10,
          maxNodes: 30,
        );
      case DifficultyMode.hard:
        return const DifficultyParameters(
          mode: DifficultyMode.hard,
          minChainLength: 5,
          maxChainLength: 12,
          densityFactor: 0.40,
          minNodes: 5,
          maxNodes: 60,
        );
    }
  }
  
  /// Derives difficulty mode from level ID
  /// - Levels 0-9: Easy
  /// - Levels 10-29: Medium
  /// - Levels 30+: Hard
  static DifficultyMode _deriveModeFromLevel(int levelId) {
    if (levelId < 10) return DifficultyMode.easy;
    if (levelId < 30) return DifficultyMode.medium;
    return DifficultyMode.hard;
  }
}
