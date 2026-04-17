import 'dart:math';
import 'difficulty_mode.dart';
import 'difficulty_parameters.dart';
import 'validation_result.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Supporting enums
// ═══════════════════════════════════════════════════════════════════════════

/// Determines the "flavour" of a level — grid shape, density, and direction
/// bias — without changing the core puzzle mechanic.
enum LevelArchetype {
  /// Balanced square grid, default density.
  standard,

  /// Smaller-than-normal square grid, high density (tight board).
  claustrophobic,

  /// Larger-than-normal square grid, sparse placement.
  openField,

  /// Rectangular (tall or wide) grid with axis-biased arrows.
  corridor,

  /// Square grid that strongly favours donut / ring masks; inward arrows.
  fortress,

  /// Square grid with organic blob / zigzag masks; uniform arrows.
  chaos,

  /// Larger grid, very low density (few nodes, lots of open space).
  sniper,
}

/// Controls how the backward generator weights direction selection.
enum DirectionBiasType {
  /// Equal probability for all four directions.
  uniform,

  /// Prefer left / right over up / down.
  horizontal,

  /// Prefer up / down over left / right.
  vertical,

  /// Prefer directions pointing toward grid centre (position-dependent).
  inward,

  /// Prefer directions pointing away from grid centre (position-dependent).
  outward,
}

// ═══════════════════════════════════════════════════════════════════════════
// Daily challenge tuning (see [LevelConfiguration.forDailyChallenge])
// ═══════════════════════════════════════════════════════════════════════════

/// Minimum fraction of the grid that must hold nodes (clamped by medium caps).
/// Kept moderate so generation still succeeds unlike the earlier ~0.78 floor.
const double kDailyChallengeMinFillRatio = 0.60;

/// First-roll chance to attempt an irregular [playCells] mask (blobs, zigzag, etc.).
const double kDailyChallengeIrregularProbability = 0.78;

/// Extra guaranteed mask attempts if the first roll misses or the mask is too small.
const int kDailyChallengeIrregularExtraTries = 10;

// ═══════════════════════════════════════════════════════════════════════════
// LevelConfiguration
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable configuration class that encapsulates all parameters for level
/// generation, including archetype-driven variety.
///
/// Example usage:
/// ```dart
/// final config = LevelConfiguration.fromLevelId(15);
/// final hardConfig = LevelConfiguration.fromLevelId(5, mode: DifficultyMode.hard);
/// ```
class LevelConfiguration {
  final int levelId;
  final int gridWidth;
  final int gridHeight;
  final int targetNodeCount;
  final DifficultyParameters difficulty;

  /// Archetype that flavours this level (grid shape, density, bias).
  final LevelArchetype archetype;

  /// How the backward generator should weight direction selection.
  final DirectionBiasType directionBias;

  /// Overrides archetype-based irregular-mask probability when non-null (dailies).
  final double? irregularMaskProbability;

  /// Additional irregular-mask attempts after the probabilistic roll ([LevelGenerator]).
  final int irregularLayoutExtraTries;

  /// Floor for scaled retry target counts; null = campaign default.
  final int? minimumTargetNodeCount;

  const LevelConfiguration({
    required this.levelId,
    required this.gridWidth,
    required this.gridHeight,
    required this.targetNodeCount,
    required this.difficulty,
    this.archetype = LevelArchetype.standard,
    this.directionBias = DirectionBiasType.uniform,
    this.irregularMaskProbability,
    this.irregularLayoutExtraTries = 0,
    this.minimumTargetNodeCount,
  });

  /// Factory constructor that derives configuration from level ID.
  ///
  /// If [mode] is not specified, automatically derives the difficulty mode
  /// from the level ID (0-9: easy, 10-29: medium, 30+: hard).
  factory LevelConfiguration.fromLevelId(int levelId, {DifficultyMode? mode}) {
    final difficulty = DifficultyParameters.fromLevelId(levelId, mode: mode);
    final archetype = _selectArchetype(levelId, difficulty.mode);
    final (gw, gh) =
        _calculateGridDimensions(levelId, difficulty.mode, archetype);
    final nodeCount =
        _calculateNodeCount(levelId, gw, gh, difficulty, archetype);
    final bias = _archetypeDirectionBias(archetype, levelId);

    return LevelConfiguration(
      levelId: levelId,
      gridWidth: gw,
      gridHeight: gh,
      targetNodeCount: nodeCount,
      difficulty: difficulty,
      archetype: archetype,
      directionBias: bias,
    );
  }

  /// Convenience factory with explicit difficulty mode.
  factory LevelConfiguration.withMode(int levelId, DifficultyMode mode) {
    return LevelConfiguration.fromLevelId(levelId, mode: mode);
  }

  /// Daily puzzle: starts from [fromLevelId] (medium) for grid, archetype, and
  /// chain bounds, then enforces [kDailyChallengeMinFillRatio] and biased
  /// irregular silhouettes without replacing the whole generator.
  factory LevelConfiguration.forDailyChallenge(int dayKey) {
    final base = LevelConfiguration.fromLevelId(dayKey, mode: DifficultyMode.medium);
    final area = base.gridWidth * base.gridHeight;
    final cap = min(base.difficulty.maxNodes, area - 1);
    final minByFill = max(
      base.difficulty.minNodes,
      (area * kDailyChallengeMinFillRatio).ceil(),
    ).clamp(base.difficulty.minNodes, cap);
    final target = max(base.targetNodeCount, minByFill).clamp(
      base.difficulty.minNodes,
      cap,
    );

    return LevelConfiguration(
      levelId: dayKey,
      gridWidth: base.gridWidth,
      gridHeight: base.gridHeight,
      targetNodeCount: target,
      difficulty: base.difficulty,
      archetype: base.archetype,
      directionBias: base.directionBias,
      irregularMaskProbability: kDailyChallengeIrregularProbability,
      irregularLayoutExtraTries: kDailyChallengeIrregularExtraTries,
      minimumTargetNodeCount: minByFill,
    );
  }

  /// Validates that configuration parameters are within acceptable ranges.
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
    final minFloor = minimumTargetNodeCount;
    if (minFloor != null) {
      if (minFloor > gridWidth * gridHeight) {
        return ValidationResult.error(
          'minimumTargetNodeCount exceeds grid capacity',
        );
      }
      if (targetNodeCount < minFloor) {
        return ValidationResult.error(
          'targetNodeCount below minimumTargetNodeCount',
        );
      }
    }
    final irp = irregularMaskProbability;
    if (irp != null && (irp < 0 || irp > 1)) {
      return ValidationResult.error('irregularMaskProbability must be 0–1');
    }
    if (irregularLayoutExtraTries < 0 || irregularLayoutExtraTries > 24) {
      return ValidationResult.error('irregularLayoutExtraTries out of range');
    }
    return ValidationResult.success();
  }

  // ── Archetype selection ────────────────────────────────────────────────

  /// Deterministic archetype assignment per level.  Early levels in each mode
  /// always get [LevelArchetype.standard] to preserve the learning curve.
  static LevelArchetype _selectArchetype(int levelId, DifficultyMode mode) {
    switch (mode) {
      case DifficultyMode.easy:
        if (levelId < 15) return LevelArchetype.standard;
      case DifficultyMode.medium:
        if (levelId < 12) return LevelArchetype.standard;
      case DifficultyMode.hard:
        if (levelId < 32) return LevelArchetype.standard;
    }

    final pool = switch (mode) {
      DifficultyMode.easy => const [
          LevelArchetype.standard,
          LevelArchetype.standard,
          LevelArchetype.standard,
          LevelArchetype.openField,
          LevelArchetype.corridor,
        ],
      DifficultyMode.medium => const [
          LevelArchetype.standard,
          LevelArchetype.standard,
          LevelArchetype.claustrophobic,
          LevelArchetype.openField,
          LevelArchetype.corridor,
          LevelArchetype.fortress,
          LevelArchetype.sniper,
        ],
      DifficultyMode.hard => const [
          LevelArchetype.standard,
          LevelArchetype.claustrophobic,
          LevelArchetype.openField,
          LevelArchetype.corridor,
          LevelArchetype.fortress,
          LevelArchetype.chaos,
          LevelArchetype.sniper,
        ],
    };

    final rng = Random(levelId * 31337 + 777);
    return pool[rng.nextInt(pool.length)];
  }

  // ── Grid dimensions ────────────────────────────────────────────────────

  /// Returns `(width, height)` for the bounding grid.  Most archetypes use a
  /// square grid; [LevelArchetype.corridor] produces a rectangular one.
  static (int, int) _calculateGridDimensions(
    int levelId,
    DifficultyMode mode,
    LevelArchetype archetype,
  ) {
    final base = _baseGridSize(levelId, mode);

    switch (archetype) {
      case LevelArchetype.standard:
      case LevelArchetype.chaos:
        return (base, base);
      case LevelArchetype.claustrophobic:
        final s = max(3, base - 1);
        return (s, s);
      case LevelArchetype.openField:
      case LevelArchetype.sniper:
        final s = min(20, base + 2);
        return (s, s);
      case LevelArchetype.corridor:
        final longAxis = min(20, (base * 1.45).round());
        final shortAxis = max(3, (base * 0.65).round());
        return levelId.isEven
            ? (shortAxis, longAxis)
            : (longAxis, shortAxis);
      case LevelArchetype.fortress:
        final s = max(5, base);
        return (s, s);
    }
  }

  /// Logarithmic grid growth, capped per mode.
  static int _baseGridSize(int levelId, DifficultyMode mode) {
    final logLevel = levelId >= 0 ? log(levelId + 1) / ln2 : 0.0;
    switch (mode) {
      case DifficultyMode.easy:
        return (4 + logLevel * 0.55).floor().clamp(4, 8);
      case DifficultyMode.medium:
        return (6 + logLevel * 0.7).floor().clamp(6, 12);
      case DifficultyMode.hard:
        return (6 + logLevel * 1.15).floor().clamp(6, 18);
    }
  }

  // ── Node count ─────────────────────────────────────────────────────────

  /// Target node count, modulated by archetype density and sinusoidal
  /// variation.
  static int _calculateNodeCount(
    int levelId,
    int gridWidth,
    int gridHeight,
    DifficultyParameters difficulty,
    LevelArchetype archetype,
  ) {
    final area = gridWidth * gridHeight;

    final logLevel = levelId >= 0 ? log(levelId + 1) / ln2 : 0.0;
    final growthRate = switch (difficulty.mode) {
      DifficultyMode.easy => 1.5,
      DifficultyMode.medium => 2.5,
      DifficultyMode.hard => 3.5,
    };
    final effectiveMaxNodes = min(
      difficulty.maxNodes + (logLevel * growthRate).floor(),
      difficulty.maxNodes * 3,
    );

    final baseCount = difficulty.minNodes + (levelId * 0.5).floor();
    final densityMod = _archetypeDensityModifier(archetype);
    final maxPossible =
        (area * difficulty.densityFactor * densityMod).floor();
    final clamped = baseCount.clamp(
      difficulty.minNodes,
      min(effectiveMaxNodes, maxPossible),
    );

    final m = 1.0 +
        sin(levelId * 0.157) * 0.10 +
        sin(levelId * 0.067) * 0.07 +
        sin(levelId * 0.031) * 0.04;

    return (clamped * m).round().clamp(difficulty.minNodes, area);
  }

  // ── Archetype helpers ──────────────────────────────────────────────────

  /// Density multiplier per archetype (applied on top of the mode's
  /// base density factor).
  static double _archetypeDensityModifier(LevelArchetype archetype) {
    return switch (archetype) {
      LevelArchetype.standard => 1.0,
      LevelArchetype.claustrophobic => 1.35,
      LevelArchetype.openField => 0.65,
      LevelArchetype.corridor => 0.85,
      LevelArchetype.fortress => 0.90,
      LevelArchetype.chaos => 1.10,
      LevelArchetype.sniper => 0.45,
    };
  }

  /// Direction bias that matches the archetype's intended feel.
  static DirectionBiasType _archetypeDirectionBias(
    LevelArchetype archetype,
    int levelId,
  ) {
    return switch (archetype) {
      LevelArchetype.standard => DirectionBiasType.uniform,
      LevelArchetype.claustrophobic => DirectionBiasType.uniform,
      LevelArchetype.openField => DirectionBiasType.uniform,
      LevelArchetype.corridor => levelId.isEven
          ? DirectionBiasType.vertical
          : DirectionBiasType.horizontal,
      LevelArchetype.fortress => DirectionBiasType.inward,
      LevelArchetype.chaos => DirectionBiasType.uniform,
      LevelArchetype.sniper => DirectionBiasType.uniform,
    };
  }
}
