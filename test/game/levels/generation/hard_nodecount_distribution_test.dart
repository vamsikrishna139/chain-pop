// Diagnostic harness: prints a human-readable report, not production code.
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Why is every Hard level ~25 nodes? `_pickTargetNodeCount` computes
/// `mask.length * fillRatio` (fillRatio 0.32-0.44) and then clamps it up to
/// `lo = max(profile.nodeCount.min, minNodes) = 25`. On the board sizes Hard
/// actually uses, that density target lands *below* 25, so the floor wins and
/// the density formula never gets to express anything.
void main() {
  test('Hard node-count distribution', () {
    final gen = LevelGenerator(enableDiversityGating: false);
    final counts = <int, int>{};
    final grids = <String, int>{};

    for (var i = 1; i <= 200; i++) {
      final r = gen.generate(i,
          mode: DifficultyMode.hard,
          timeBudget: const Duration(milliseconds: 200));
      if (!r.isSuccess) continue;
      final lvl = r.value;
      counts.update(lvl.nodes.length, (v) => v + 1, ifAbsent: () => 1);
      final area = lvl.gridWidth * lvl.gridHeight;
      grids.update(
          '${lvl.gridWidth}x${lvl.gridHeight} (area $area)', (v) => v + 1,
          ifAbsent: () => 1);
    }

    print('\n=== HARD NODE COUNTS (levels 1-200) ===');
    for (final k in counts.keys.toList()..sort()) {
      print('  $k nodes: ${counts[k]}');
    }
    print('\ngrids: $grids');
    print('\nFor the density target to beat the floor of 25 you need');
    print('mask.length > 25/0.44 = 57 cells at the luckiest fillRatio,');
    print('and > 25/0.32 = 78 cells to beat it reliably.');

    expect(counts, isNotEmpty);
  });
}
