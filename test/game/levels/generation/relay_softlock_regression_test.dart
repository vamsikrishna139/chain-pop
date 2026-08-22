// The soft-lock guard that runs in the DEFAULT suite.
//
// `test/dev/autoplay_600_test.dart` is the harness that actually catches
// tap-order soft-locks — it drives `ChainPopGame` the way a player does — but
// it is `@Tags(['report'])` and 5,400 play-throughs long, so it does not run
// on an ordinary `flutter test`. That is how a reachable soft-lock survived
// long enough to ship into a corpus.
//
// This is the bounded version: same engine, same random-route method, a prefix
// of the campaign. It runs in the default suite so the invariant is defended
// on every change rather than only when someone remembers to sweep.
//
// **What it caught, and must keep catching.** `enrichLevel` used to assign
// phase groups *after* placing relays, so `_relayIsSoftlockSafe` proved its
// worst case against a board with every node in phase group 0 — not the board
// that shipped. Phase gates strictly tighten legal tap order. Measured on the
// board this found (`hard L592`, whose relay is poppable on tap 1, so the
// proof's worst case is the full board):
//
//   worst case, phase groups stripped — what the proof saw : SOLVABLE
//   worst case as shipped             — what the player got: UNSOLVABLE
//
// Moving phase-gate assignment above the relay block fixed it. If it ever
// moves back, or any other board-shaping step is added after the relay proof,
// this test is what says so.
library;

import 'dart:math';

import 'package:chain_pop/game/chain_pop_game.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

/// Full campaign length, and that is not negotiable down: the boards this
/// defect stranded were medium L501 and hard L592. A 150-level prefix runs
/// four times faster and passes on the broken tree — verified — so it would
/// have guarded nothing.
const int _kLevels = 600;
const int _kRoutes = 3;

void main() {
  test('no campaign board can be tapped into a dead end', () {
    final failures = <String>[];

    // Sequential, one generator per mode: the diversity ledger is session
    // state, so a board depends on every board before it. Generating a level
    // in isolation produces a different board and would not reproduce.
    for (final mode in [DifficultyMode.medium, DifficultyMode.hard]) {
      final gen = LevelGenerator();
      for (var id = 1; id <= _kLevels; id++) {
        final res = gen.generate(id, mode: mode);
        if (!res.isSuccess) continue;
        final level = res.value;

        for (var route = 0; route < _kRoutes; route++) {
          var won = false;
          final game = ChainPopGame(
            levelId: level.levelId,
            difficulty: mode,
            onWin: () => won = true,
          );
          game.levelData = level;
          game.activeNodes.addAll(level.nodes.map((n) => n.clone()));
          game.refreshExtractableIdsForTest();

          // Seeded per (level, route) so any failure is reproducible from the
          // line this prints, not merely observable once.
          final rng = Random(id * 1000 + route);
          var taps = 0;
          while (!game.hasWon && taps < level.nodes.length + 8) {
            final candidates = [
              for (final n in game.activeNodes)
                if (game.canExtract(n)) n,
            ];
            if (candidates.isEmpty) break;
            game.registerExtraction(candidates[rng.nextInt(candidates.length)]);
            taps++;
          }
          if (!(game.hasWon && won)) {
            final relays =
                level.nodes.where((n) => n.kind == NodeKind.relay).length;
            failures.add('${mode.name} L$id route $route: STRANDED with '
                '${game.activeNodes.length}/${level.nodes.length} nodes after '
                '$taps taps (relays=$relays, '
                'phaseGroups=${level.nodes.map((n) => n.phaseGroup).toSet().length})');
          }
        }
      }
    }

    expect(failures, isEmpty,
        reason: '${failures.length} play-throughs reached a dead end:\n'
            '${failures.join('\n')}');
  });
}
