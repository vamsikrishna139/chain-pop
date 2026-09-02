import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/models/difficulty.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DifficultyExt', () {
    test('label and key are consistent per mode', () {
      expect(DifficultyMode.easy.label, 'EASY');
      expect(DifficultyMode.easy.key, 'easy');
      expect(DifficultyMode.medium.label, 'MEDIUM');
      expect(DifficultyMode.medium.key, 'medium');
      expect(DifficultyMode.hard.label, 'HARD');
      expect(DifficultyMode.hard.key, 'hard');
    });

    test('fromKey maps storage strings', () {
      expect(DifficultyExt.fromKey('easy'), DifficultyMode.easy);
      expect(DifficultyExt.fromKey('medium'), DifficultyMode.medium);
      expect(DifficultyExt.fromKey('hard'), DifficultyMode.hard);
      expect(DifficultyExt.fromKey('unknown'), DifficultyMode.easy);
      expect(DifficultyExt.fromKey(''), DifficultyMode.easy);
    });

    test('starsFor checks directives and jams', () {
      // Level 501 is sector 5 (Integrity: jamCount <= 1)
      const integrityMet = LevelResult(
          levelId: 501,
          jamCount: 1,
          elapsedSeconds: 10,
          undosUsed: 0,
          movesTaken: 5,
          totalNodes: 10,
          mode: DifficultyMode.medium);
      const integrityFailedOneStar = LevelResult(
          levelId: 501,
          jamCount: 2,
          elapsedSeconds: 10,
          undosUsed: 0,
          movesTaken: 10,
          totalNodes: 10,
          mode: DifficultyMode.medium);

      expect(integrityMet.earnedStars, 3);
      expect(integrityFailedOneStar.earnedStars, 1);

      // Level 500 is sector 4 (Unaided: undosUsed == 0)
      const unaidedMet = LevelResult(
          levelId: 500,
          jamCount: 1,
          elapsedSeconds: 20,
          undosUsed: 0,
          movesTaken: 10,
          totalNodes: 10,
          mode: DifficultyMode.medium);
      const unaidedFailedButTwoStars = LevelResult(
          levelId: 500,
          jamCount: 0,
          elapsedSeconds: 100,
          undosUsed: 1,
          movesTaken: 10,
          totalNodes: 10,
          mode: DifficultyMode.medium);

      expect(unaidedMet.earnedStars, 3);
      expect(unaidedFailedButTwoStars.earnedStars, 2);
    });

    test('dimColor and boardTint are derived from color', () {
      expect(DifficultyMode.medium.dimColor.a, closeTo(0.30, 0.01));
      expect(DifficultyMode.hard.boardTint.a, closeTo(0.04, 0.01));
    });
  });
}
