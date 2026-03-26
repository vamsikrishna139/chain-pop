/// End-to-end integration tests for the level generation pipeline.
///
/// Tests the complete flow: level ID → configuration → generation → validation → LevelData
import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/game/levels/level_solver.dart';

void main() {
  final generator = LevelGenerator();
  final validator = LevelValidator();

  // ─── Full pipeline flow ────────────────────────────────────────────────────
  group('Integration — End-to-end generation pipeline', () {
    test('Level ID → LevelData is solvable and valid', () {
      for (final id in [1, 10, 30, 100]) {
        final result = generator.generate(id);
        expect(result.isSuccess, isTrue, reason: 'Level $id failed');

        final validation = validator.validate(result.value);
        expect(validation.isValid, isTrue,
            reason: 'Level $id validator rejected: ${validation.message}');

        expect(LevelSolver.isSolvable(result.value), isTrue,
            reason: 'Level $id not solvable by solver');
      }
    });

    test('Invalid config (negative level ID) returns error result', () {
      final result = generator.generate(-1);
      expect(result.isError, isTrue);
      expect(result.error.type, equals('invalid_configuration'));
    });

    test('LevelManager.getLevel always returns valid LevelData', () {
      for (final id in [1, 5, 15, 50, 200]) {
        final level = LevelManager.getLevel(id);
        expect(level.nodes, isNotEmpty);
        expect(LevelSolver.isSolvable(level), isTrue,
            reason: 'LevelManager level $id not solvable');
      }
    });

    test('LevelManager supports explicit difficulty modes', () {
      for (final mode in DifficultyMode.values) {
        final level = LevelManager.getLevel(5, mode: mode);
        expect(LevelSolver.isSolvable(level), isTrue,
            reason: 'mode=$mode not solvable');
      }
    });
  });

  // ─── Retry logic ──────────────────────────────────────────────────────────
  group('Integration — Retry & fallback', () {
    test('Fallback level is always solvable when returned', () {
      // Levels 500-520 exercise extreme configurations; ensure they're always valid.
      for (int id = 500; id <= 520; id++) {
        final level = LevelManager.getLevel(id);
        expect(LevelSolver.isSolvable(level), isTrue,
            reason: 'Fallback for level $id not solvable');
      }
    });
  });

  // ─── Validator compatibility ────────────────────────────────────────────────
  group('Integration — LevelValidator compatibility', () {
    test('Validator accepts all generated levels', () {
      for (int id = 1; id <= 50; id++) {
        final result = generator.generate(id);
        if (result.isSuccess) {
          final v = validator.validate(result.value);
          expect(v.isValid, isTrue, reason: 'Validator rejected level $id: ${v.message}');
        }
      }
    });
  });
}
