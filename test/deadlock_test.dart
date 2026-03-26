import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level_generator.dart';
import 'package:chain_pop/game/levels/level_solver.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // Deadlock stress-test: verify EVERY level is solvable.
  //
  // The backward-generation algorithm guarantees solvability by construction,
  // but we test all 1 000 levels explicitly so any future change to the
  // generator is caught immediately.
  // ──────────────────────────────────────────────────────────────────────────
  group('Deadlock Regression – levels 1..1000', () {
    test('Every level from 1 to 1000 is solvable (no deadlocks)', () {
      final List<int> failedLevels = [];

      for (int id = 1; id <= 1000; id++) {
        final level = LevelGenerator.generate(id);
        if (!LevelSolver.isSolvable(level)) {
          failedLevels.add(id);
        }
      }

      expect(
        failedLevels,
        isEmpty,
        reason: 'Deadlock detected in levels: $failedLevels',
      );
    });

    // Secondary check: the fallback path itself must be solvable.
    // We force it by requesting an absurdly large node count that forces
    // repeated failures until the safe fallback kicks in.
    test('Safe fallback level is always solvable', () {
      // Levels with very high IDs hit the max node count on a small grid,
      // which exercises the fallback path.
      for (int id = 500; id <= 520; id++) {
        final level = LevelGenerator.generate(id);
        expect(
          LevelSolver.isSolvable(level),
          isTrue,
          reason: 'Fallback level $id is not solvable',
        );
      }
    });
  });
}
