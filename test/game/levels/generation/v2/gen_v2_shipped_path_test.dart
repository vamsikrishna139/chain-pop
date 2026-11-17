// The boards the app ships (LevelManager.getLevel) must equal the boards the
// V2 gates measure (a fresh neutral generator per level).
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_fingerprint.dart';

void main() {
  test('shipped V2 board == harness board', () {
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 1;
    addTearDown(() => LevelManager.genV2FromLevel.clear());
    final diffs = <int>[];
    for (final id in [1, 2, 3, 5, 8, 13, 17, 22]) {
      final shipped = LevelManager.getLevel(id, mode: DifficultyMode.hard);
      final harness = LevelGenerator.neutral()
          .generate(id,
              mode: DifficultyMode.hard,
              workBudget: LevelManager.genV2WorkBudget,
              generationVersion: 2)
          .value;
      if (boardFingerprint(shipped) != boardFingerprint(harness)) diffs.add(id);
    }
    expect(diffs, isEmpty, reason: 'levels whose shipped board differs');
  });
}
