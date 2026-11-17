// P2: micro-twist levels carry their preset mechanics. Fast (4 boards).
import 'package:chain_pop/game/levels/generation/core_metrics.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/visual_composition.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('twist levels', () {
    for (final id in [17, 42]) {
      final l = LevelGenerator.neutral()
          .generate(id,
              mode: DifficultyMode.hard,
              workBudget: LevelManager.genV2WorkBudget,
              generationVersion: 2)
          .value;
      expect(l.lockCount, greaterThanOrEqualTo(1), reason: 'L$id lock finale');
    }
  });

  // P3 (V2c) lock variance rides the sawtooth: relief 0, climax 3.
  test('lock variance by world position', () {
    LevelData gen(int id) => LevelGenerator.neutral()
        .generate(id,
            mode: DifficultyMode.hard,
            workBudget: LevelManager.genV2WorkBudget,
            generationVersion: 2)
        .value;
    expect(gen(2).lockCount, 0, reason: 'L2 relief');
    expect(gen(22).lockCount, greaterThanOrEqualTo(2), reason: 'L22 climax');
  });

  // D3 via core placement: V2 cores cover at least half the board on a
  // representative level (soft target, so only checked where reachable).
  test('V2 core depth target', () {
    final l = LevelGenerator.neutral()
        .generate(5,
            mode: DifficultyMode.hard,
            workBudget: LevelManager.genV2WorkBudget,
            generationVersion: 2)
        .value;
    expect(CoreMetrics.compute(l).coreTapFraction, greaterThanOrEqualTo(0.5));
  });

  // S1 v2: the diagonal staircase on Hard L2 (two big triangular voids, no big
  // rectangle) is re-rolled; ordinary levels stay under the void limit.
  test('no large connected void on early V2 levels', () {
    for (final id in [2, 3, 6]) {
      final l = LevelGenerator.neutral()
          .generate(id,
              mode: DifficultyMode.hard,
              workBudget: LevelManager.genV2WorkBudget,
              generationVersion: 2)
          .value;
      expect(genV2LargestVoidRegionFraction(l),
          lessThanOrEqualTo(kGenV2MaxVoidRegionFraction),
          reason: 'L$id');
    }
  });
}
