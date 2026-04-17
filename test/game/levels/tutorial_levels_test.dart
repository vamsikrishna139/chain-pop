import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:chain_pop/game/levels/tutorial_levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tutorialLevels has length 5 and each layout is valid and solvable', () {
    expect(tutorialLevels, hasLength(5));
    for (final level in tutorialLevels) {
      expect(LevelData.layoutValidationMessage(level), isNull);
      expect(LevelSolver.isSolvable(level), isTrue,
          reason: 'levelId ${level.levelId}');
    }
  });

  test('first tutorial level is solvable', () {
    expect(LevelSolver.isSolvable(tutorialLevels.first), isTrue);
  });
}
