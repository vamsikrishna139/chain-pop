import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/progression_profile.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LevelResult run(int id, DifficultyMode mode,
          {int jams = 0, int undos = 0, int secs = 1, int moves = 10}) =>
      LevelResult(
        levelId: id,
        jamCount: jams,
        elapsedSeconds: secs,
        undosUsed: undos,
        movesTaken: moves,
        totalNodes: 10,
        mode: mode,
      );

  test('a directive met with 2+ jams no longer earns 3 stars', () {
    // Find an Easy level whose directive is SWIFT or UNAIDED (jam-agnostic).
    final id = List.generate(200, (i) => i + 1).firstWhere((i) {
      final d = directiveFor(levelId: i, mode: DifficultyMode.easy);
      return d == LevelDirective.unaided;
    });
    expect(run(id, DifficultyMode.easy, jams: 0).earnedStars, 3);
    expect(run(id, DifficultyMode.easy, jams: 1).earnedStars, 3);
    expect(run(id, DifficultyMode.easy, jams: 2).earnedStars, 1);
    expect(run(id, DifficultyMode.easy, jams: 5).earnedStars, 1);
  });

  test('coreless CASCADE fallback rotates instead of always SWIFT', () {
    final fallbacks = <LevelDirective>{};
    for (var i = 1; i <= 120; i++) {
      final d = directiveFor(levelId: i, mode: DifficultyMode.easy);
      expect(d, isNot(LevelDirective.cascade),
          reason: 'Easy has no cores, so CASCADE is unwinnable (L$i)');
      fallbacks.add(d);
    }
    expect(fallbacks, containsAll([
      LevelDirective.swift,
      LevelDirective.unaided,
      LevelDirective.integrity,
    ]));
  });

  test('no campaign board budgets more than one relay', () {
    for (final mode in DifficultyMode.values) {
      for (final id in [1, 251, 501, 751, 900, 1000, 20261112]) {
        expect(budgetFor(levelId: id, mode: mode).relayCount,
            lessThanOrEqualTo(1),
            reason: '$mode L$id');
      }
    }
  });
}
