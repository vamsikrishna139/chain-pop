// Every campaign level must actually generate. This is the guard that P1 needed
// and did not have.
//
// T1.3 raised Medium sector 3+ from two cores to three. Cores are not just a
// win condition — `_markSpecialNodes` keeps relays out of **core rows**, because
// a relay rotates its whole row and can spin a core into a permanent face-off.
// Three cores therefore block three rows, and on a cramped board that can leave
// no legal relay position at all. The generator treated a mechanic-budget
// shortfall as a reason to discard the candidate and try again, so a board that
// could never seat its relay burned all forty attempts and returned
// `Result.error`.
//
// Exactly one level in 1..1500 hit it: **L427 Medium**, which generated fine
// before P1 and not at all after. One is enough — a campaign level that cannot
// be produced is strictly worse than any triviality this phase set out to fix,
// and nothing in the suite would have caught it, because the corpus tests all
// sample and the `report_*` harnesses only print failures.
//
// The fix is in `level_generator.dart`: at attempt exhaustion, ship a retained
// valid board (wave-band miss first, mechanic-short second) instead of erroring.
//
// ignore_for_file: avoid_print

@Tags(['slow'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('L427 Medium generates — the board T1.3 starved', () {
    final result = LevelGenerator.neutral()
        .generate(427, mode: DifficultyMode.medium, timeBudget: null);

    expect(result.isSuccess, isTrue,
        reason: 'L427 Medium is the level three cores starve of a relay; it '
            'must still ship, mechanic-short if need be');
    expect(LevelSolver.isSolvable(result.value), isTrue);
  });

  test('no campaign level fails to generate, in any mode', () {
    final broken = <String>[];
    final unsolvable = <String>[];

    for (final mode in DifficultyMode.values) {
      for (var id = 1; id <= 1500; id += 7) {
        final result = LevelGenerator.neutral()
            .generate(id, mode: mode, timeBudget: null);
        if (!result.isSuccess) {
          broken.add('L$id/${mode.name}: ${result.error}');
          continue;
        }
        if (!LevelSolver.isSolvable(result.value)) {
          unsolvable.add('L$id/${mode.name}');
        }
      }
    }

    expect(broken, isEmpty, reason: 'levels that will not generate');
    expect(unsolvable, isEmpty, reason: 'levels that generate but cannot be won');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
