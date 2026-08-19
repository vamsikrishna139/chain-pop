import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/progression_profile.dart';
import 'package:chain_pop/game/levels/seeds/milestone_seeds.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';

void main() {
  test('Campaign Phase 0 regression guard', () {
    final gen = LevelGenerator(enableDiversityGating: false);

    for (int i = 1; i <= 1000; i++) {
      gen.resetCounters();
      final res = gen.generate(i, mode: DifficultyMode.hard);
      expect(res.isSuccess, isTrue, reason: 'Level $i must succeed');
      final level = res.value;

      final cores = level.nodes.where((n) => n.isCore).length;
      expect(cores, greaterThanOrEqualTo(3),
          reason: 'Level $i must have >= 3 cores');

      final budget = budgetFor(levelId: i, mode: DifficultyMode.hard);

      final locks = level.nodes.where((n) => n.kind == NodeKind.locked).length;
      final relays = level.nodes.where((n) => n.kind == NodeKind.relay).length;

      expect(locks, lessThanOrEqualTo(budget.lockCount),
          reason: 'Level $i lock count exceeded budget');
      expect(relays, lessThanOrEqualTo(budget.relayCount),
          reason: 'Level $i relay count exceeded budget');

      if (i >= 25 && i % 25 == 0) {
        if (i % 100 == 0) {
          expect(gen.seedEmissionCounts.containsKey(milestoneSniperSeed.id),
              isTrue,
              reason: 'Level $i should emit as sniper');
          expect(level.gridWidth, 10, reason: 'Sniper must be 10x10');
          expect(level.gridHeight, 10, reason: 'Sniper must be 10x10');
        } else if (i % 100 == 50) {
          expect(gen.seedEmissionCounts.containsKey(milestoneOverloadSeed.id),
              isTrue,
              reason: 'Level $i should emit as overload');
          expect(level.nodes.length, lessThanOrEqualTo(36));
        } else if (i % 100 == 75) {
          expect(
              gen.seedEmissionCounts.containsKey(ringMilestoneSeed.id), isTrue,
              reason: 'Level $i should emit as ring');
        } else if (i % 100 == 25) {
          expect(gen.seedEmissionCounts.containsKey(diamondMilestoneSeed.id),
              isTrue,
              reason: 'Level $i should emit as diamond');
        }
      }
    }
  }, tags: 'slow');

  test('Medium campaign variable core-count regression guard', () {
    final gen = LevelGenerator(enableDiversityGating: false);

    for (final i in [126, 149, 174, 251, 274, 299]) {
      gen.resetCounters();
      final res = gen.generate(i, mode: DifficultyMode.medium);
      expect(res.isSuccess, isTrue, reason: 'Medium level $i must succeed');
      final level = res.value;
      final budget = budgetFor(levelId: i, mode: DifficultyMode.medium);

      final cores = level.nodes.where((n) => n.isCore).length;
      expect(cores, equals(budget.coreCount),
          reason: 'Medium level $i core count mismatch');
    }
  });

  test('Hard sector 1/2 cascade reachability measurement', () {
    final gen = LevelGenerator(enableDiversityGating: false);
    const sampleIds = [1, 10, 24, 101, 124, 126, 149, 174, 201, 224];
    var reachableByDirectiveBudget = 0;

    for (final i in sampleIds) {
      final res = gen.generate(i, mode: DifficultyMode.hard);
      expect(res.isSuccess, isTrue, reason: 'Hard level $i must succeed');
      final level = res.value;
      final coreCompletionMove = _canonicalCoreCompletionMove(level);
      final directiveBudget = level.nodes.length ~/ 2;
      if (coreCompletionMove <= directiveBudget) {
        reachableByDirectiveBudget++;
      }
      // ignore: avoid_print
      print('Cascade L$i: coreWinMove=$coreCompletionMove '
          'budget=$directiveBudget nodes=${level.nodes.length}');
    }

    // Measurement only: this keeps the P3 cascade check visible without
    // hard-coding a threshold before the post-core-fix baseline is known.
    // ignore: avoid_print
    print('Cascade sample reachable by directive budget: '
        '$reachableByDirectiveBudget/${sampleIds.length}');
    expect(sampleIds, isNotEmpty);
  });

  test('daily challenges intentionally use sector 8 hard mechanic load', () {
    final budget = budgetFor(levelId: 10001, mode: DifficultyMode.hard);

    expect(budget.coreCount, equals(3));
    expect(budget.lockCount, equals(2));
    expect(budget.relayCount, equals(2));
    expect(budget.phaseGateCount, equals(2));
  });
}

int _canonicalCoreCompletionMove(LevelData level) {
  final waves = LevelSolver.nodeWaveIndices(level);
  final coreIds = {
    for (final n in level.nodes)
      if (n.isCore) n.id,
  };
  if (coreIds.isEmpty) return level.nodes.length;
  final lastCoreWave = coreIds
      .map((id) => waves[id] ?? level.nodes.length)
      .reduce((a, b) => a > b ? a : b);
  final earlierMoves = level.nodes.where((n) {
    final wave = waves[n.id] ?? level.nodes.length;
    return wave < lastCoreWave;
  }).length;
  final lastWaveCoreMoves = level.nodes.where((n) {
    final wave = waves[n.id] ?? level.nodes.length;
    return n.isCore && wave == lastCoreWave;
  }).length;
  return earlierMoves + lastWaveCoreMoves;
}
