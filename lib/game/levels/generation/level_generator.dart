import 'dart:math';
import 'package:flutter/material.dart';
import '../level.dart';
import '../level_solver.dart';
import 'difficulty_mode.dart';
import 'generation_error.dart';
import 'difficulty_parameters.dart';
import 'layout_mask.dart';
import 'level_configuration.dart';
import 'level_validator.dart';
import 'result.dart';

/// Milestone types triggered at specific level multiples.
enum _MilestoneType {
  oneDirection,
  maxDensity,
  ring,
  sparseSniper,
}

/// Generates deterministic, deadlock-free puzzle levels using the **backward
/// generation algorithm**.
///
/// ## Algorithm Overview
///
/// The backward generation algorithm guarantees solvability by construction:
///
/// 1. **Play region** — Optionally picks an irregular subset of cells
///    ([LevelData.playCells]) based on archetype and difficulty. Nodes are
///    placed only inside that region. **Rays** for blocking still run in a
///    straight line across the **full** bounding grid until the edge.
/// 2. **Select positions** — Pick N unique random positions in the play region.
/// 3. **Define solution order** — Shuffle positions to create a removal sequence.
/// 4. **Assign directions** — For each node at index `i`, only nodes at indices
///    `i+1..N-1` are still on the board. Assign a direction whose ray does
///    **not** pass through any of those "future" nodes. Direction selection is
///    weighted by the config's [DirectionBiasType].
/// 5. **Validate** — Run [LevelValidator] plus removal-wave bounds.
/// 6. **Fallback** — If all retries fail, return a guaranteed-solvable strip.
class LevelGenerator {
  final LevelValidator _validator;

  LevelGenerator({LevelValidator? validator})
      : _validator = validator ?? LevelValidator();

  /// Effective inclusive bounds on [LevelSolver.countRemovalWaves].
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

  // ────────────────────────────────────────────────────────────────────────
  // Public API
  // ────────────────────────────────────────────────────────────────────────

  /// Generates a deterministic [LevelData] for the given [levelId].
  ///
  /// Checks for milestone levels first, then falls back to the normal
  /// backward-generation loop with archetype-driven shape/bias selection.
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

    // ── Milestone levels (every 25th, Medium/Hard only) ───────────────
    final milestone = _getMilestoneType(config);
    if (milestone != null) {
      final rng = Random(levelId * 31337);
      final result = _generateMilestone(milestone, config, rng);
      if (result.isSuccess) {
        final level = result.value;
        final validationResult = _validator.validate(level);
        if (validationResult.isValid) return result;
      }
      // If milestone generation failed, fall through to normal generation.
    }

    // ── Normal generation with retries ────────────────────────────────
    for (int attempt = 0; attempt < 16; attempt++) {
      final rng = Random(levelId * 31337 + attempt * 999983);

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
              archetype: config.archetype,
              directionBias: config.directionBias,
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

    return Result.success(_generateFallbackLevel(config));
  }

  // ────────────────────────────────────────────────────────────────────────
  // Core backward-generation
  // ────────────────────────────────────────────────────────────────────────

  /// Single generation attempt with archetype-aware shape and bias.
  Result<LevelData, GenerationError> _attemptGeneration(
    LevelConfiguration config,
    Random random,
  ) {
    try {
      Set<String>? playCells;

      final irregProb = _irregularProbability(config);
      if (random.nextDouble() < irregProb) {
        final shapes = _preferredShapes(config.archetype);
        final kind = pickIrregularKind(random, preferred: shapes);
        final mask = buildLayoutMask(
          kind,
          config.gridWidth,
          config.gridHeight,
          random: random,
        );
        if (mask != null &&
            mask.length >= config.targetNodeCount &&
            mask.length >= config.difficulty.minNodes) {
          playCells = mask;
        }
      }

      final positions = _selectUniquePositions(
        config.targetNodeCount,
        config.gridWidth,
        config.gridHeight,
        random,
        playCells,
      );

      if (positions.length < config.targetNodeCount) {
        return Result.error(
          GenerationError.noValidDirections(
              'Grid too small for requested nodes'),
        );
      }

      final solutionPath = List<Point<int>>.from(positions)..shuffle(random);

      final nodes = _assignDirections(
        solutionPath,
        config.gridWidth,
        config.gridHeight,
        random,
        config.directionBias,
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
        playCells: playCells,
        nodes: nodes,
      ));
    } catch (e) {
      return Result.error(GenerationError.unexpected('Generation failed: $e'));
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Archetype-aware shape selection
  // ────────────────────────────────────────────────────────────────────────

  /// Probability of rolling an irregular layout based on archetype + mode.
  static double _irregularProbability(LevelConfiguration config) {
    return switch (config.archetype) {
      LevelArchetype.fortress => 0.92,
      LevelArchetype.chaos => 0.95,
      LevelArchetype.claustrophobic => 0.60,
      LevelArchetype.corridor => 0.06,
      LevelArchetype.sniper => 0.06,
      LevelArchetype.openField => 0.08,
      LevelArchetype.standard => switch (config.difficulty.mode) {
          DifficultyMode.easy => 0.12,
          DifficultyMode.medium => 0.22,
          DifficultyMode.hard => 0.58,
        },
    };
  }

  /// Subset of mask shapes favoured by each archetype, or null for all.
  static List<LayoutMaskKind>? _preferredShapes(LevelArchetype archetype) {
    return switch (archetype) {
      LevelArchetype.claustrophobic => const [
          LayoutMaskKind.diamond,
          LayoutMaskKind.cross,
        ],
      LevelArchetype.fortress => const [
          LayoutMaskKind.donut,
          LayoutMaskKind.cShape,
        ],
      LevelArchetype.chaos => const [
          LayoutMaskKind.randomBlob,
          LayoutMaskKind.zigzag,
        ],
      _ => null,
    };
  }

  // ────────────────────────────────────────────────────────────────────────
  // Position selection (stratified sampling)
  // ────────────────────────────────────────────────────────────────────────

  List<Point<int>> _selectUniquePositions(
    int count,
    int gridWidth,
    int gridHeight,
    Random random,
    Set<String>? allowedCells,
  ) {
    final positions = <Point<int>>[];
    final used = <String>{};

    if (allowedCells != null && allowedCells.isNotEmpty) {
      final pool = allowedCells
          .map((k) {
            final parts = k.split(',');
            return Point(int.parse(parts[0]), int.parse(parts[1]));
          })
          .toList()
        ..shuffle(random);
      if (pool.length < count) return positions;
      for (var i = 0; i < count; i++) {
        positions.add(pool[i]);
      }
      return positions;
    }

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

    int safety = 0;
    while (positions.length < count && safety++ < count * 100) {
      final x = random.nextInt(gridWidth);
      final y = random.nextInt(gridHeight);
      final key = '$x,$y';
      if (used.add(key)) {
        positions.add(Point(x, y));
      }
    }

    positions.shuffle(random);
    return positions;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Direction assignment (backward guarantee + bias)
  // ────────────────────────────────────────────────────────────────────────

  List<NodeData>? _assignDirections(
    List<Point<int>> solutionPath,
    int gridWidth,
    int gridHeight,
    Random random,
    DirectionBiasType bias,
  ) {
    final nodes = <NodeData>[];
    final palette = _getColorPalette();

    for (int i = 0; i < solutionPath.length; i++) {
      final position = solutionPath[i];
      final futureNodes = solutionPath.sublist(i + 1);

      final direction = _findValidDirection(
        position,
        futureNodes,
        gridWidth,
        gridHeight,
        random,
        bias,
      );

      if (direction == null) return null;

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

  /// Finds a direction whose ray does not hit any [futureNodes], using
  /// weighted ordering from [bias].
  Direction? _findValidDirection(
    Point<int> position,
    List<Point<int>> futureNodes,
    int gridWidth,
    int gridHeight,
    Random random,
    DirectionBiasType bias,
  ) {
    final ordered = _biasedDirectionOrder(
      random,
      bias,
      position,
      gridWidth,
      gridHeight,
    );

    if (futureNodes.isEmpty) return ordered.first;

    final futureSet = <String>{
      for (final p in futureNodes) '${p.x},${p.y}',
    };

    for (final dir in ordered) {
      if (!_directionHitsNodes(position, dir, futureSet, gridWidth, gridHeight)) {
        return dir;
      }
    }

    return null;
  }

  /// Returns the four directions in a weighted-random order.
  List<Direction> _biasedDirectionOrder(
    Random random,
    DirectionBiasType bias,
    Point<int> position,
    int gridWidth,
    int gridHeight,
  ) {
    switch (bias) {
      case DirectionBiasType.uniform:
        return Direction.values.toList()..shuffle(random);

      case DirectionBiasType.horizontal:
        return _weightedShuffle(random, {
          Direction.left: 2.0,
          Direction.right: 2.0,
          Direction.up: 1.0,
          Direction.down: 1.0,
        });

      case DirectionBiasType.vertical:
        return _weightedShuffle(random, {
          Direction.up: 2.0,
          Direction.down: 2.0,
          Direction.left: 1.0,
          Direction.right: 1.0,
        });

      case DirectionBiasType.inward:
        final cx = gridWidth / 2.0;
        final cy = gridHeight / 2.0;
        return _weightedShuffle(random, {
          Direction.left: position.x > cx ? 2.0 : 0.5,
          Direction.right: position.x < cx ? 2.0 : 0.5,
          Direction.up: position.y > cy ? 2.0 : 0.5,
          Direction.down: position.y < cy ? 2.0 : 0.5,
        });

      case DirectionBiasType.outward:
        final cx = gridWidth / 2.0;
        final cy = gridHeight / 2.0;
        return _weightedShuffle(random, {
          Direction.left: position.x < cx ? 2.0 : 0.5,
          Direction.right: position.x > cx ? 2.0 : 0.5,
          Direction.up: position.y < cy ? 2.0 : 0.5,
          Direction.down: position.y > cy ? 2.0 : 0.5,
        });
    }
  }

  /// Weighted random ordering: picks directions one at a time with
  /// probability proportional to weight.
  List<Direction> _weightedShuffle(
    Random random,
    Map<Direction, double> weights,
  ) {
    final result = <Direction>[];
    final pool = Map<Direction, double>.from(weights);
    while (pool.isNotEmpty) {
      final total = pool.values.fold(0.0, (a, b) => a + b);
      var r = random.nextDouble() * total;
      Direction? picked;
      for (final entry in pool.entries) {
        r -= entry.value;
        if (r <= 0) {
          picked = entry.key;
          break;
        }
      }
      picked ??= pool.keys.last;
      result.add(picked);
      pool.remove(picked);
    }
    return result;
  }

  /// Ray-cast: returns true if the ray hits any future node before exiting.
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
        case Direction.up:
          y--;
          break;
        case Direction.down:
          y++;
          break;
        case Direction.left:
          x--;
          break;
        case Direction.right:
          x++;
          break;
      }
      if (x < 0 || x >= gridWidth || y < 0 || y >= gridHeight) return false;
      if (futureSet.contains('$x,$y')) return true;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Milestone levels (Item 10)
  // ────────────────────────────────────────────────────────────────────────

  /// Returns the milestone type for this level, or null for normal levels.
  /// Milestones fire every 25th level for Medium/Hard only.
  static _MilestoneType? _getMilestoneType(LevelConfiguration config) {
    if (config.difficulty.mode == DifficultyMode.easy) return null;
    final id = config.levelId;
    if (id < 25) return null;

    final mod = id % 100;
    if (mod == 0) return _MilestoneType.sparseSniper;
    if (mod == 50) return _MilestoneType.maxDensity;
    if (mod == 75) return _MilestoneType.ring;
    if (mod == 25) return _MilestoneType.oneDirection;
    return null;
  }

  Result<LevelData, GenerationError> _generateMilestone(
    _MilestoneType type,
    LevelConfiguration config,
    Random random,
  ) {
    switch (type) {
      case _MilestoneType.oneDirection:
        return _generateOneDirection(config, random);
      case _MilestoneType.maxDensity:
        return _generateMaxDensity(config, random);
      case _MilestoneType.ring:
        return _generateRing(config, random);
      case _MilestoneType.sparseSniper:
        return _generateSparseSniper(config, random);
    }
  }

  /// All arrows point the same direction.  Solution order is sorted so the
  /// backward algorithm guarantee holds trivially.
  Result<LevelData, GenerationError> _generateOneDirection(
    LevelConfiguration config,
    Random random,
  ) {
    final dir = Direction.values[random.nextInt(4)];

    final positions = _selectUniquePositions(
      config.targetNodeCount,
      config.gridWidth,
      config.gridHeight,
      random,
      null,
    );
    if (positions.length < config.targetNodeCount) {
      return Result.error(
        GenerationError.noValidDirections('Not enough positions'),
      );
    }

    // Sort so that nodes "downstream" of the chosen direction are removed
    // first, guaranteeing that each node's ray never hits a future node.
    positions.sort((a, b) {
      int cmp;
      switch (dir) {
        case Direction.right:
          cmp = b.x.compareTo(a.x);
        case Direction.left:
          cmp = a.x.compareTo(b.x);
        case Direction.down:
          cmp = b.y.compareTo(a.y);
        case Direction.up:
          cmp = a.y.compareTo(b.y);
      }
      if (cmp != 0) return cmp;
      return a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x);
    });

    final palette = _getColorPalette();
    final nodes = <NodeData>[];
    for (int i = 0; i < positions.length; i++) {
      nodes.add(NodeData(
        id: i,
        x: positions[i].x,
        y: positions[i].y,
        dir: dir,
        color: palette[random.nextInt(palette.length)],
      ));
    }

    return Result.success(LevelData(
      levelId: config.levelId,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      nodes: nodes,
    ));
  }

  /// Nearly maximum density — fills as many cells as the grid allows.
  Result<LevelData, GenerationError> _generateMaxDensity(
    LevelConfiguration config,
    Random random,
  ) {
    final maxCount = min(config.gridWidth * config.gridHeight,
        max(config.targetNodeCount, 40));
    final denseConfig = LevelConfiguration(
      levelId: config.levelId,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      targetNodeCount: maxCount,
      difficulty: config.difficulty,
      archetype: config.archetype,
      directionBias: DirectionBiasType.uniform,
    );
    return _attemptGeneration(denseConfig, random);
  }

  /// Nodes placed only on the border of the grid.
  Result<LevelData, GenerationError> _generateRing(
    LevelConfiguration config,
    Random random,
  ) {
    final border = <Point<int>>[];
    for (int x = 0; x < config.gridWidth; x++) {
      border.add(Point(x, 0));
      if (config.gridHeight > 1) {
        border.add(Point(x, config.gridHeight - 1));
      }
    }
    for (int y = 1; y < config.gridHeight - 1; y++) {
      border.add(Point(0, y));
      if (config.gridWidth > 1) {
        border.add(Point(config.gridWidth - 1, y));
      }
    }
    border.shuffle(random);

    final count = min(config.targetNodeCount, border.length);
    final positions = border.sublist(0, count);

    final solutionPath = List<Point<int>>.from(positions)..shuffle(random);
    final nodes = _assignDirections(
      solutionPath,
      config.gridWidth,
      config.gridHeight,
      random,
      DirectionBiasType.outward,
    );

    if (nodes == null) {
      return Result.error(
        GenerationError.noValidDirections('Ring generation failed'),
      );
    }

    return Result.success(LevelData(
      levelId: config.levelId,
      gridWidth: config.gridWidth,
      gridHeight: config.gridHeight,
      nodes: nodes,
    ));
  }

  /// Very few nodes on a large grid — a "sniper" challenge.
  Result<LevelData, GenerationError> _generateSparseSniper(
    LevelConfiguration config,
    Random random,
  ) {
    final sparseCount = max(
      config.difficulty.minNodes,
      (config.targetNodeCount * 0.45).round(),
    );
    final w = min(20, config.gridWidth + 2);
    final h = min(20, config.gridHeight + 2);
    final sparseConfig = LevelConfiguration(
      levelId: config.levelId,
      gridWidth: w,
      gridHeight: h,
      targetNodeCount: sparseCount,
      difficulty: config.difficulty,
      archetype: config.archetype,
      directionBias: DirectionBiasType.uniform,
    );
    return _attemptGeneration(sparseConfig, random);
  }

  // ────────────────────────────────────────────────────────────────────────
  // Fallback level generation
  // ────────────────────────────────────────────────────────────────────────

  LevelData _generateFallbackLevel(LevelConfiguration config) {
    final palette = _getColorPalette();
    final nodes = <NodeData>[];
    int id = 0;
    int needed =
        min(config.targetNodeCount, config.gridWidth * config.gridHeight);

    for (int x = 0; x < config.gridWidth && id < needed; x++) {
      nodes.add(NodeData(
        id: id++,
        x: x,
        y: 0,
        dir: Direction.up,
        color: palette[(id - 1) % palette.length],
      ));
    }

    if (id < needed) {
      for (int x = 0; x < config.gridWidth && id < needed; x++) {
        nodes.add(NodeData(
          id: id++,
          x: x,
          y: config.gridHeight - 1,
          dir: Direction.down,
          color: palette[(id - 1) % palette.length],
        ));
      }
    }

    if (id < needed) {
      for (int y = 1; y < config.gridHeight - 1 && id < needed; y++) {
        nodes.add(NodeData(
          id: id++,
          x: 0,
          y: y,
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

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  List<Color> _getColorPalette() => const [
        Color(0xFF60EFFF),
        Color(0xFF00FF87),
        Color(0xFFFF5F6D),
        Color(0xFFFFC371),
        Color(0xFFA18CD1),
        Color(0xFF4FACFE),
      ];

  /// Returns the grid width for a given [levelId] and [mode].
  static int calculateGridSize(int levelId, DifficultyMode mode) {
    return LevelConfiguration.fromLevelId(levelId, mode: mode).gridWidth;
  }

  /// Returns the target node count for a given [levelId] and [mode].
  static int calculateNodeCount(int levelId, DifficultyMode mode) {
    return LevelConfiguration.fromLevelId(levelId, mode: mode).targetNodeCount;
  }
}
