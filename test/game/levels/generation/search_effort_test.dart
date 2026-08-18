import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/search_effort.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeSearchEffort', () {
    test('empty board has zero effort and is solved', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 4,
        gridHeight: 4,
        nodes: const [],
      );

      final result = computeSearchEffort(level);

      expect(result.solved, isTrue);
      expect(result.searchEffortScore, equals(0));
    });

    test('trivial parallel opening requires low effort', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < 3; i++)
            NodeData(id: i, x: i, y: 0, dir: Direction.up),
        ],
      );

      final result = computeSearchEffort(level);

      expect(result.solved, isTrue);
      expect(result.searchEffortScore, lessThan(10));
      expect(LevelSolver.isSolvable(level), isTrue);
    });

    test('LevelMetrics.compute populates searchEffortScore', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < 4; i++)
            NodeData(id: i, x: i, y: 1, dir: Direction.right),
        ],
      );

      final metrics = LevelMetrics.compute(level);
      final effort = computeSearchEffort(level);

      expect(metrics.searchEffortScore, equals(effort.searchEffortScore));
      expect(metrics.searchEffortScore, greaterThan(0));
    });
  });
}
