import 'dart:math' as math;

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

  test('phase step: gated arrows have clear rays but wait for the phase', () {
    final level = tutorialLevels[8];
    final gated = level.nodes.where((n) => n.phaseGroup > 0).toList();
    final open = level.nodes.where((n) => n.phaseGroup == 0).toList();
    expect(gated, hasLength(2));
    expect(open, hasLength(2));

    // The lesson must be the phase, never a blocked ray: each gated arrow is
    // unremovable now, yet removable the moment only its own phase remains.
    for (final node in gated) {
      expect(LevelSolver.canRemove(node, level.nodes, level), isFalse,
          reason: 'node ${node.id} must wait for phase 0 to clear');
      expect(LevelSolver.canRemove(node, gated, level), isTrue,
          reason: 'node ${node.id} ray must already be clear');
    }
    for (final node in open) {
      expect(LevelSolver.canRemove(node, level.nodes, level), isTrue,
          reason: 'node ${node.id} opens the board');
    }
    expect(LevelValidator().validate(level).isValid, isTrue);
  });

  test('graduation step: carries every arrow type', () {
    final level = tutorialLevels[9];
    expect(level.nodes.where((n) => n.kind == NodeKind.relay), hasLength(1));
    expect(level.nodes.where((n) => n.kind == NodeKind.locked), hasLength(1));
    expect(level.nodes.where((n) => n.phaseGroup > 0).length,
        greaterThanOrEqualTo(1));
    expect(level.nodes.where((n) => n.isCore).length, greaterThanOrEqualTo(2));
    // A plain arrow with no special property, so all five types are present.
    expect(
      level.nodes.where((n) =>
          n.kind == NodeKind.normal && !n.isCore && n.phaseGroup == 0),
      isNotEmpty,
    );
    expect(LevelValidator().validate(level).isValid, isTrue,
        reason: 'ID order must solve the board end to end');
  });

  test('graduation step: cores are gated behind act one', () {
    final level = tutorialLevels[9];
    for (final core in level.nodes.where((n) => n.isCore)) {
      expect(core.phaseGroup, greaterThan(0),
          reason: 'a phase-0 core could win the level before act one is '
              'taught, skipping the relay and padlock entirely');
      expect(LevelSolver.canRemove(core, level.nodes, level), isFalse);
    }
  });

  test('graduation step: the relay is the only way to free node 2', () {
    final level = tutorialLevels[9];
    final relay = level.nodes.singleWhere((n) => n.kind == NodeKind.relay);
    final blocked = level.nodes.singleWhere((n) => n.id == 2);
    expect(LevelSolver.canRemove(blocked, level.nodes, level), isFalse);

    // Removing every other act-one arrow must still leave node 2 stuck: only
    // the relay's row rotation can turn it toward an open edge.
    final withoutPeers = level.nodes
        .where((n) => n.id == blocked.id || n.id == relay.id || n.phaseGroup > 0)
        .toList();
    expect(LevelSolver.canRemove(blocked, withoutPeers, level), isFalse,
        reason: 'node 2 must depend on the rotation, not on tap order');
  });

  test('graduation step: finale still has something to sweep', () {
    final level = tutorialLevels[9];
    final lastCoreId =
        level.nodes.where((n) => n.isCore).map((n) => n.id).reduce(math.max);
    expect(level.nodes.any((n) => n.id > lastCoreId), isTrue,
        reason: 'at least one arrow must outlive the last core so the cascade '
            'finale plays on the final tutorial board');
  });
}
