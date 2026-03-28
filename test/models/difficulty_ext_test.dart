import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
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

    test('starsForJams matches jam thresholds', () {
      expect(DifficultyMode.easy.starsForJams(0), 3);
      expect(DifficultyMode.medium.starsForJams(1), 2);
      expect(DifficultyMode.hard.starsForJams(2), 2);
      expect(DifficultyMode.easy.starsForJams(3), 1);
      expect(DifficultyMode.hard.starsForJams(100), 1);
    });

    test('dimColor and boardTint are derived from color', () {
      expect(DifficultyMode.medium.dimColor.opacity, closeTo(0.30, 0.01));
      expect(DifficultyMode.hard.boardTint.opacity, closeTo(0.04, 0.01));
    });
  });
}
