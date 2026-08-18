// Diagnostic harness: prints a human-readable report, not production code.
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';

/// A milestone only *feels* like a milestone if it reads differently from the
/// levels either side of it. This measures each milestone slot against its
/// immediate neighbours so a regression that quietly makes "Overload" the same
/// size as level 149 is visible.
void main() {
  test('milestone slots read differently from their neighbours', () {
    final gen = LevelGenerator(enableDiversityGating: false);

    int nodesOf(int id) {
      final r = gen.generate(id, mode: DifficultyMode.hard);
      return r.isSuccess ? r.value.nodes.length : -1;
    }

    String gridOf(int id) {
      final r = gen.generate(id, mode: DifficultyMode.hard);
      return r.isSuccess ? '${r.value.gridWidth}x${r.value.gridHeight}' : '?';
    }

    print('\n=== MILESTONE TEXTURE (Hard) ===');
    print('slot  kind      grid    nodes | neighbours (n-1, n+1)');

    final overloadNodes = <int>[];
    final sniperNodes = <int>[];
    final plainNodes = <int>[];

    for (var m = 25; m <= 1000; m += 25) {
      final mod = m % 100;
      final kind = switch (mod) {
        0 => 'sniper',
        50 => 'overload',
        25 => 'diamond',
        _ => 'ring',
      };
      final n = nodesOf(m);
      final before = nodesOf(m - 1);
      final after = m < 1000 ? nodesOf(m + 1) : -1;
      plainNodes.addAll([before, if (after > 0) after]);
      if (kind == 'overload') overloadNodes.add(n);
      if (kind == 'sniper') sniperNodes.add(n);

      if (m % 100 == 0 || m % 100 == 50) {
        print('${m.toString().padLeft(4)}  ${kind.padRight(9)} '
            '${gridOf(m).padRight(6)} ${n.toString().padLeft(5)} | '
            '$before, $after');
      }
    }

    double avg(List<int> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

    print('\navg nodes — overload: ${avg(overloadNodes).toStringAsFixed(1)}, '
        'sniper: ${avg(sniperNodes).toStringAsFixed(1)}, '
        'ordinary neighbours: ${avg(plainNodes).toStringAsFixed(1)}');

    // The sniper milestone is defined by its 10x10 board; that must hold.
    for (var m = 100; m <= 1000; m += 100) {
      expect(gridOf(m), '10x10', reason: 'sniper slot $m must be 10x10');
    }

    // NOT asserted: that "Overload" is denser than an ordinary level. It is
    // not — it currently ships the same ~25 nodes, so the milestone is a label
    // with no gameplay behind it. Pinning a node count on the seed is the fix,
    // but it first needs a latency bound inside the Director; see the KNOWN GAP
    // note on `milestoneOverloadSeed` and `milestone_latency_test.dart`.
    // This harness exists to make that gap visible and to show it closing.
  });
}
