// Autoplay harness: actually *plays* the campaign through the real game class.
//
// Not a generation test — every other sweep in this suite asks whether a board
// can be built and whether a solver says it is clearable. This one drives
// `ChainPopGame` the way a player does: read what is extractable, tap one of
// them, let the game apply the consequences (relay row rotation, locks opening
// as their neighbours clear, core-win firing early), and repeat until the level
// is won or nothing can be tapped.
//
// That distinction matters because the tap-order-dependent failures live here
// and nowhere else. `LevelSolver.countRemovalWaves` clears every removable node
// in a wave simultaneously, so it cannot observe a board that a *particular*
// order of taps can strand — which is exactly what a relay does when it rotates
// a row out from under the player.
//
//   flutter test --tags report test/dev/autoplay_600_test.dart
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'dart:math';

import 'package:chain_pop/game/chain_pop_game.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

const int _kLevels = 600;

/// Play-throughs per level. The pick among equally-extractable nodes is random,
/// so one pass is one player's route through the board; a handful of passes
/// samples different routes and is what gives the relay soft-lock a chance to
/// show itself.
const int _kRoutesPerLevel = 3;

class _Outcome {
  _Outcome(this.won, this.taps, this.stranded);
  final bool won;
  final int taps;
  final int stranded;
}

/// One full play-through. Returns how it ended.
_Outcome _play(LevelData level, DifficultyMode mode, Random rng) {
  var won = false;
  final game = ChainPopGame(
    levelId: level.levelId,
    difficulty: mode,
    onWin: () => won = true,
  );
  game.levelData = level;
  game.activeNodes.addAll(level.nodes.map((n) => n.clone()));
  game.refreshExtractableIdsForTest();

  var taps = 0;
  // Every tap removes exactly one node, so the board bounds the loop; the +8
  // is slack for nothing in particular beyond making a runaway obvious.
  final cap = level.nodes.length + 8;
  while (!game.hasWon && taps < cap) {
    final candidates = [
      for (final n in game.activeNodes)
        if (game.canExtract(n)) n,
    ];
    if (candidates.isEmpty) break;
    game.registerExtraction(candidates[rng.nextInt(candidates.length)]);
    taps++;
  }
  // Both signals, deliberately: `hasWon` is the game's internal flag and
  // `onWin` is what the screen above it listens to. A win that sets one and
  // not the other is a bug the player would see as a level that never ends.
  return _Outcome(game.hasWon && won, taps, game.activeNodes.length);
}

void main() {
  test('autoplay the campaign, all three modes', () {
    final failures = <String>[];
    final gen = LevelGenerator();

    for (final mode in DifficultyMode.values) {
      final sw = Stopwatch()..start();
      var won = 0;
      var stuck = 0;
      var generationFailures = 0;
      var coreWins = 0;
      var totalTaps = 0;
      var worstTaps = 0;
      var worstId = 0;

      for (var id = 1; id <= _kLevels; id++) {
        final res = gen.generate(id, mode: mode);
        if (!res.isSuccess) {
          generationFailures++;
          failures.add('${mode.name} L$id: generation failed');
          continue;
        }
        final level = res.value;

        for (var route = 0; route < _kRoutesPerLevel; route++) {
          // Seeded per (level, route) so a failure is reproducible from the
          // line this harness prints, not just observable once.
          final out = _play(level, mode, Random(id * 1000 + route));
          if (out.won) {
            won++;
            if (out.stranded > 0) coreWins++;
            totalTaps += out.taps;
            if (out.taps > worstTaps) {
              worstTaps = out.taps;
              worstId = id;
            }
          } else {
            stuck++;
            failures.add('${mode.name} L$id route $route: STRANDED with '
                '${out.stranded}/${level.nodes.length} nodes left after '
                '${out.taps} taps');
          }
        }
      }
      sw.stop();

      const plays = _kLevels * _kRoutesPerLevel;
      print('\n=== ${mode.name.toUpperCase()} — $_kLevels levels x '
          '$_kRoutesPerLevel routes ===');
      print('  won            : $won/$plays');
      print('  stranded       : $stuck');
      print('  generation fail: $generationFailures');
      print('  core-wins      : $coreWins  (won with nodes still standing)');
      print('  taps           : avg ${won == 0 ? 0 : (totalTaps / won).toStringAsFixed(1)}, '
          'worst $worstTaps (L$worstId)');
      print('  wall clock     : ${sw.elapsed.inSeconds}s');
    }

    print('\n${failures.isEmpty ? "no failures" : "FAILURES (${failures.length}):"}');
    for (final f in failures.take(40)) {
      print('  $f');
    }

    // A level the player can tap into a dead end is the one outcome this
    // harness exists to catch, so it asserts rather than only reporting.
    expect(failures, isEmpty,
        reason: '${failures.length} play-throughs did not complete');
  }, timeout: const Timeout(Duration(minutes: 90)));
}
