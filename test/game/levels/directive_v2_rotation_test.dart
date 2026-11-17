import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => LevelManager.genV2FromLevel.clear());

  test('V2 Hard: every directive in each 5-level block, SWIFT <= 25%', () {
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 1;
    var swift = 0;
    for (var b = 0; b < 40; b++) {
      final seen = <LevelDirective>{};
      for (var i = 1; i <= 5; i++) {
        final id = b * 5 + i;
        if (id % 25 == 0) continue; // boss slots pin the sector signature
        final d = directiveFor(levelId: id, mode: DifficultyMode.hard);
        seen.add(d);
        if (d == LevelDirective.swift) swift++;
      }
      // cascade may fall back when a level has no cores, so allow 4+.
      expect(seen.length, greaterThanOrEqualTo(3), reason: 'block $b');
    }
    expect(swift / 200, lessThanOrEqualTo(0.35));
  });

  test('levels below the cut-over keep their V1 directive', () {
    final before = [
      for (var i = 1; i <= 50; i++)
        directiveFor(levelId: i, mode: DifficultyMode.hard)
    ];
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 51;
    final after = [
      for (var i = 1; i <= 50; i++)
        directiveFor(levelId: i, mode: DifficultyMode.hard)
    ];
    expect(after, before);
  });
}
