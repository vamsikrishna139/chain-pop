/// Regression tests ensuring LevelSolver backward-compatibility with the
/// new LevelGenerator.
import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/level_solver.dart';

void main() {
  final generator = LevelGenerator();

  group('Solver Compatibility — isSolvable', () {
    test('LevelSolver.isSolvable returns true for all generated levels (1-100)', () {
      final failed = <int>[];
      for (int id = 1; id <= 100; id++) {
        final result = generator.generate(id);
        if (result.isSuccess && !LevelSolver.isSolvable(result.value)) {
          failed.add(id);
        }
      }
      expect(failed, isEmpty, reason: 'Solver found unsolvable levels: $failed');
    });
  });

  group('Solver Compatibility — getHint', () {
    test('LevelSolver.getHint finds a valid move for every generated level', () {
      for (final id in [1, 5, 10, 30, 100]) {
        final result = generator.generate(id);
        expect(result.isSuccess, isTrue);

        final level = result.value;
        final active = level.nodes.map((n) => n.clone()).toList();
        final hint = LevelSolver.getHint(
          active,
          level.gridWidth,
          level.gridHeight,
        );

        expect(hint, isNotNull, reason: 'No hint available for level $id');
        // Verify the hint node is actually extractable
        expect(
          LevelSolver.canRemove(hint!, active),
          isTrue,
          reason: 'Hint node ${hint.id} is not extractable in level $id',
        );
      }
    });

    test('Hint remains valid after each extraction step', () {
      final result = generator.generate(42);
      expect(result.isSuccess, isTrue);

      final level = result.value;
      final active = level.nodes.map((n) => n.clone()).toList();
      int steps = 0;

      while (active.isNotEmpty) {
        final hint = LevelSolver.getHint(
          active,
          level.gridWidth,
          level.gridHeight,
        );
        expect(hint, isNotNull, reason: 'Solver stuck at step $steps');
        active.removeWhere((n) => n.id == hint!.id);
        steps++;
      }

      expect(steps, equals(result.value.nodes.length));
    });
  });

  group('Removal-wave band', () {
    test('Levels 1–100 sit within min/max removal waves for auto-derived mode', () {
      for (var id = 1; id <= 100; id++) {
        final result = generator.generate(id);
        expect(result.isSuccess, isTrue, reason: 'Level $id');
        final level = result.value;
        final config = LevelConfiguration.fromLevelId(id);
        final waves = LevelSolver.countRemovalWaves(level);
        final (wMin, wMax) = LevelGenerator.removalWaveBounds(
          config.difficulty,
          level.nodes.length,
        );
        expect(
          waves,
          inInclusiveRange(wMin, wMax),
          reason: 'Level $id waves=$waves expected [$wMin, $wMax]',
        );
      }
    });
  });
}
