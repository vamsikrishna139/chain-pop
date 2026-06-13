import 'package:chain_pop/game/levels/generation/level_validator.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:chain_pop/game/levels/tutorial_levels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tutorialLevels matches tutorialStepCount and all layouts are valid',
      () {
    expect(tutorialLevels, hasLength(tutorialStepCount));
    for (final level in tutorialLevels) {
      expect(LevelData.layoutValidationMessage(level), isNull,
          reason: 'levelId ${level.levelId}');
    }
  });

  test('movement steps (0–4) are clear-all solvable', () {
    for (final level in tutorialLevels.take(5)) {
      expect(LevelSolver.isSolvable(level), isTrue,
          reason: 'levelId ${level.levelId}');
    }
  });

  test('final movement recap has at least 6 arrows', () {
    expect(tutorialLevels[4].nodes.length, greaterThanOrEqualTo(6));
  });

  test('cores step: three free cores, demo pair stays stuck for the finale',
      () {
    final level = tutorialLevels[5];
    final cores = level.nodes.where((n) => n.isCore).toList();
    final others = level.nodes.where((n) => !n.isCore).toList();
    expect(cores, hasLength(3));
    for (final core in cores) {
      expect(LevelSolver.canRemove(core, level.nodes, level), isTrue,
          reason: 'every core must be extractable from the start');
    }
    for (final node in others) {
      expect(LevelSolver.canRemove(node, level.nodes, level), isFalse,
          reason: 'the face-off pair must stay stuck until the finale');
    }
  });

  test('relay step: pair is deadlocked until the relay rotates the row', () {
    final level = tutorialLevels[6];
    final relay =
        level.nodes.singleWhere((n) => n.kind == NodeKind.relay);
    expect(LevelSolver.canRemove(relay, level.nodes, level), isTrue);
    for (final node in level.nodes.where((n) => n.id != relay.id)) {
      expect(LevelSolver.canRemove(node, level.nodes, level), isFalse,
          reason: 'only the relay may open the board');
    }
    // The relay-aware validator certifies the post-rotation solution path.
    expect(LevelValidator().validate(level).isValid, isTrue);
  });

  test('locked step: padlock opens after its neighbors clear', () {
    final level = tutorialLevels[7];
    final locked =
        level.nodes.singleWhere((n) => n.kind == NodeKind.locked);
    expect(LevelSolver.canRemove(locked, level.nodes, level), isFalse,
        reason: 'locked while neighbors are occupied');
    expect(LevelSolver.isSolvable(level), isTrue);
    expect(LevelValidator().validate(level).isValid, isTrue);
  });
}
