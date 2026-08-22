// Diagnostic harness: prints a human-readable report, not production code.
// ignore_for_file: avoid_print

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Milestone slots take a separate, unbudgeted generation path, so a heavy
/// pinned seed there is paid directly in level-load time by the player.
///
/// Tagged `slow`: this costs ~90s, and irreducibly so — the runtime *is* the
/// measurement. 40 slots against a baseline whose worst is ~2.2s cannot be
/// made cheap without measuring something else. It stays a real gate; it just
/// belongs in CI rather than in the local edit loop. Run with:
///     flutter test --tags slow
void main() {
  test('milestone slots load fast enough to not stall the player', () {
    final gen = LevelGenerator();

    print('\n=== MILESTONE LOAD LATENCY (Hard) ===');
    print('slot  kind      ms');

    var worst = 0;
    var worstSlot = 0;

    for (var m = 25; m <= 1000; m += 25) {
      final sw = Stopwatch()..start();
      final res = gen.generate(
        m,
        mode: DifficultyMode.hard,
        timeBudget: const Duration(milliseconds: 200),
      );
      sw.stop();
      expect(res.isSuccess, isTrue, reason: 'slot $m must generate');

      final mod = m % 100;
      final kind = switch (mod) {
        0 => 'sniper',
        50 => 'overload',
        25 => 'diamond',
        _ => 'ring',
      };
      if (sw.elapsedMilliseconds > worst) {
        worst = sw.elapsedMilliseconds;
        worstSlot = m;
      }
      if (mod == 50 || mod == 0) {
        print('${m.toString().padLeft(4)}  ${kind.padRight(9)} '
            '${sw.elapsedMilliseconds}');
      }
    }

    print('\nworst: slot $worstSlot at ${worst}ms');

    // A level that takes seconds to appear reads as the game hanging, and
    // milestone slots are exactly the levels a player is most excited to reach.
    //
    // The ceiling is 3s against a measured baseline whose worst slot is ~2.2s
    // (725). That 2.2s is already a pre-existing smell worth attacking, but the
    // guard exists to catch the *large* regressions: pinning a node count on
    // the overload seed pushed single slots to 66s and 181s, because the
    // generator's time budget does not bound the seeded Director path.
    expect(worst, lessThan(3000),
        reason: 'slot $worstSlot took ${worst}ms to generate');
  }, tags: 'slow');
}
