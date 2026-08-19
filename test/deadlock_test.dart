import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
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
    // The full 1..1000 sweep costs ~6 minutes — it was the single largest item
    // in the default `flutter test` run. It is split in two so the invariant
    // still guards every commit without owning the feedback loop:
    //
    //   * the sampled test below runs by default (~35s, every 10th level plus
    //     the milestone slots, which take the separate seeded path);
    //   * the exhaustive sweep is tagged `slow` for CI and pre-release.
    //
    // If the sampled test ever goes red, run the full sweep to get the
    // complete list of failing ids:
    //     flutter test test/deadlock_test.dart --tags slow
    test('Every 10th level + milestone slots are solvable (sampled)', () {
      final List<int> failedLevels = [];

      final ids = <int>{
        for (int id = 1; id <= 1000; id += 10) id,
        // Milestone slots bypass procedural generation for pinned seeds, so
        // sampling on a stride of 10 alone would under-cover them.
        for (int id = 25; id <= 1000; id += 25) id,
      }.toList()
        ..sort();

      for (final id in ids) {
        final level = LevelManager.getLevel(id);
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

    test('Every level from 1 to 1000 is solvable (no deadlocks)', () {
      final List<int> failedLevels = [];

      for (int id = 1; id <= 1000; id++) {
        final level = LevelManager.getLevel(id);
        if (!LevelSolver.isSolvable(level)) {
          failedLevels.add(id);
        }
      }

      expect(
        failedLevels,
        isEmpty,
        reason: 'Deadlock detected in levels: $failedLevels',
      );
    }, tags: 'slow');

    // Secondary check: the fallback path itself must be solvable.
    // We force it by requesting an absurdly large node count that forces
    // repeated failures until the safe fallback kicks in.
    test('Safe fallback level is always solvable', () {
      // Levels with very high IDs hit the max node count on a small grid,
      // which exercises the fallback path.
      for (int id = 500; id <= 520; id++) {
        final level = LevelManager.getLevel(id);
        expect(
          LevelSolver.isSolvable(level),
          isTrue,
          reason: 'Fallback level $id is not solvable',
        );
      }
    });
  });
}
