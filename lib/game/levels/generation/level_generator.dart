import 'dart:math';
import 'package:flutter/material.dart';
import '../level.dart';
import '../level_solver.dart';
import 'difficulty_mode.dart';
import 'generation_error.dart';
import 'difficulty_parameters.dart';
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
/// 4. **Validate** — Run [LevelValidator] plus removal-wave bounds from
///    [DifficultyParameters.minChainLength] / [maxChainLength].
/// 5. **Fallback** — If all retries fail, return a guaranteed-solvable strip layout
///    (does not enforce wave bounds — last resort only).
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

  /// Effective inclusive bounds on [LevelSolver.countRemovalWaves] for a level
  /// with [nodeCount] nodes under [d].
  ///
  /// Hard mode tiers down the documented floor as boards grow: very small
  /// puzzles rarely reach five parallel-removal waves, yet we still want a
  /// stricter floor on huge layouts when random layouts tend to be deeper.
  static (int min, int max) removalWaveBounds(
    DifficultyParameters d,
    int nodeCount,
  ) {
    if (nodeCount <= 0) return (0, 0);
    var minW = d.minChainLength;
    final maxW = min(d.maxChainLength, nodeCount);
    if (d.mode == DifficultyMode.hard) {
      if (nodeCount <= 18) {
        minW = min(minW, 2);
      } else if (nodeCount <= 35) {
        minW = min(minW, 3);
      } else if (nodeCount <= 55) {
        minW = min(minW, 4);
      }
    }
    minW = min(minW, maxW);
    if (minW < 1) minW = 1;
    return (minW, maxW);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Generates a deterministic [LevelData] for the given [levelId].
  ///
  /// The level ID is used as the primary random seed so the same ID always
  /// produces the same puzzle.  Difficulty mode can be auto-derived or
  /// explicitly specified.
  ///
  /// Attempts generation up to 16 times (varying seed and scaled node count).
  /// On persistent failure returns a simple, guaranteed-solvable fallback level.
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

    // Primary attempts: vary both the seed AND the node count on later tries.
    // This explores structurally different configurations, not just different
    // random orderings of the same density.
    for (int attempt = 0; attempt < 16; attempt++) {
      final rng = Random(levelId * 31337 + attempt * 999983);

      // Gradually reduce node count in later retries (−15% per two attempts)
      // to give the direction-assigner more room when the grid is dense.
      final nodeCountScale = 1.0 - (attempt ~/ 2) * 0.15;
      final scaledConfig = attempt < 2
          ? config
          : LevelConfiguration(
              levelId: config.levelId,
              gridWidth: config.gridWidth,
              gridHeight: config.gridHeight,
              targetNodeCount:
                  (config.targetNodeCount * nodeCountScale).round().clamp(
                    config.difficulty.minNodes,
                    config.targetNodeCount,
                  ),
              difficulty: config.difficulty,
            );

      final result = _attemptGeneration(scaledConfig, rng);
      if (result.isSuccess) {
        final level = result.value;
        final validationResult = _validator.validate(level);
        if (!validationResult.isValid) continue;

        final waves = LevelSolver.countRemovalWaves(level);
        final (wMin, wMax) =
            removalWaveBounds(scaledConfig.difficulty, level.nodes.length);
        if (waves >= wMin && waves <= wMax) {
          return Result.success(level);
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

  /// Selects [count] unique positions spread across the grid using
  /// **stratified sampling**.
  ///
  /// The grid is divided into `ceil(sqrt(count))` × `ceil(sqrt(count))`
  /// sectors. One position is sampled from each sector before filling
  /// the remainder with pure random picks. This prevents clustering that
  /// often happens with pure uniform random placement.
  List<Point<int>> _selectUniquePositions(
    int count,
    int gridWidth,
    int gridHeight,
    Random random,
  ) {
    final positions = <Point<int>>[];
    final used = <String>{};

    // Phase 1 — stratified: pick one position per sector
    if (count > 1) {
      final sectors = sqrt(count.toDouble()).ceil();
      final sectorW = (gridWidth / sectors).ceil();
      final sectorH = (gridHeight / sectors).ceil();

      for (int sy = 0; sy < sectors && positions.length < count; sy++) {
        for (int sx = 0; sx < sectors && positions.length < count; sx++) {
          final xMin = sx * sectorW;
          final xMax = min(xMin + sectorW, gridWidth);
          final yMin = sy * sectorH;
          final yMax = min(yMin + sectorH, gridHeight);
          if (xMin >= gridWidth || yMin >= gridHeight) continue;

          for (int attempt = 0; attempt < 8; attempt++) {
            final x = xMin + random.nextInt(xMax - xMin);
            final y = yMin + random.nextInt(yMax - yMin);
            final key = '$x,$y';
            if (used.add(key)) {
              positions.add(Point(x, y));
              break;
            }
          }
        }
      }
    }

    // Phase 2 — fill remainder with pure random
    int safety = 0;
    while (positions.length < count && safety++ < count * 100) {
      final x = random.nextInt(gridWidth);
      final y = random.nextInt(gridHeight);
      final key = '$x,$y';
      if (used.add(key)) {
        positions.add(Point(x, y));
      }
    }

    // Shuffle so the stratified order doesn't bias the solution path
    positions.shuffle(random);
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

  /// Generates a guaranteed-solvable fallback level.
  ///
  /// Uses two groups of non-blocking nodes:
  ///  • **Group A** — placed at row 0, each in a unique column, pointing UP.
  ///    Their rays exit at y < 0 (off-grid) → never blocked.
  ///  • **Group B** — overflow nodes placed at row [gridHeight-1], unique
  ///    columns not used by Group A, pointing DOWN.
  ///    Their rays exit at y > gridHeight-1 → never blocked.
  ///  • **Group C** — any remaining placed at col 0, unique rows, pointing LEFT.
  ///
  /// All three groups are guaranteed immediately extractable by construction.
  LevelData _generateFallbackLevel(LevelConfiguration config) {
    final palette = _getColorPalette();
    final nodes = <NodeData>[];
    int id = 0;
    int needed = min(config.targetNodeCount, config.gridWidth * config.gridHeight);

    // Group A — row 0, unique columns, pointing UP
    for (int x = 0; x < config.gridWidth && id < needed; x++) {
      nodes.add(NodeData(
        id: id++, x: x, y: 0,
        dir: Direction.up,
        color: palette[(id - 1) % palette.length],
      ));
    }

    // Group B — row gridHeight-1, columns not used by A, pointing DOWN
    // (only reachable if needed > gridWidth)
    if (id < needed) {
      for (int x = 0; x < config.gridWidth && id < needed; x++) {
        // Skip columns already used by Group A (same col, different row — would
        // the UP node at row 0 col x block a DOWN node at row H-1 col x?
        // DOWN from (x, H-1): ray goes y > H-1 → off grid → not blocked. ✓
        // But UP from (x, 0): ray goes y < 0 → not blocked even with B present. ✓
        nodes.add(NodeData(
          id: id++, x: x, y: config.gridHeight - 1,
          dir: Direction.down,
          color: palette[(id - 1) % palette.length],
        ));
      }
    }

    // Group C — col 0, unique rows (excluding 0 and gridHeight-1), pointing LEFT
    if (id < needed) {
      for (int y = 1; y < config.gridHeight - 1 && id < needed; y++) {
        nodes.add(NodeData(
          id: id++, x: 0, y: y,
          dir: Direction.left,
          color: palette[(id - 1) % palette.length],
        ));
      }
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
  /// - Hard:   6×6 → 16×16 (see [LevelConfiguration._calculateGridSize])
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
