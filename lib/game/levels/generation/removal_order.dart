import 'dart:math';

import '../grid_cell_key.dart';
import '../level.dart';

/// True iff stepping from [pos] along [dir] hits a cell in [obstacleKeys]
/// before leaving the [gridWidth]×[gridHeight] bounds.
bool rayHitsObstacleBeforeExit(
  Point<int> pos,
  Direction dir,
  Set<int> obstacleKeys,
  int gridWidth,
  int gridHeight,
) {
  var x = pos.x;
  var y = pos.y;
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
    if (obstacleKeys.contains(gridCellKey(x, y))) return true;
  }
}

/// Simulates one extraction turn: can this cell shoot off the board without
/// crossing any [obstacleKeys] in a straight cardinal line?
bool isExtractableAgainst(
  Point<int> pos,
  Set<int> obstacleKeys,
  int gridWidth,
  int gridHeight,
) {
  for (final d in Direction.values) {
    if (!rayHitsObstacleBeforeExit(
      pos,
      d,
      obstacleKeys,
      gridWidth,
      gridHeight,
    )) {
      return true;
    }
  }
  return false;
}

/// Picks a random valid elimination sequence using **randomized greedy**
/// forward simulation: at each step, remove an extractable node among those
/// remaining (shuffled). This matches valid player tap sequences from [LevelSolver].
///
/// When this returns non-null, the backward direction pass in [LevelGenerator]
/// can always assign arrows (every step has at least one unobstructed ray) in
/// some cardinal direction — the same property used in mixed-initiative /
/// solution-first PCG (constraint satisfaction with example playthrough).
///
/// Returns **null only after exhaustion** — every one of [maxAttempts]
/// independent greedy trials failed to clear all [positions]. Callers must not
/// invent a fake elimination order (e.g. a mere shuffle); they should
/// renegotiate density/shape instead.
List<Point<int>>? tryGreedyEliminationOrder(
  List<Point<int>> positions,
  int gridWidth,
  int gridHeight,
  Random random, {
  int maxAttempts = 96,
}) {
  if (positions.isEmpty) return [];
  if (positions.length == 1) return [positions.first];

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final rem = positions.toList()..shuffle(random);
    final order = <Point<int>>[];
    final keys = {for (final p in rem) gridCellKey(p.x, p.y)};

    while (rem.isNotEmpty) {
      final candidates = rem.toList()..shuffle(random);
      Point<int>? pick;
      for (final c in candidates) {
        final others = Set<int>.from(keys)..remove(gridCellKey(c.x, c.y));
        if (isExtractableAgainst(c, others, gridWidth, gridHeight)) {
          pick = c;
          break;
        }
      }
      if (pick == null) break;

      order.add(pick);
      rem.remove(pick);
      keys.remove(gridCellKey(pick.x, pick.y));
    }

    if (order.length == positions.length) return order;
  }

  return null;
}
