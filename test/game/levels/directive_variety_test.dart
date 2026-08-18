// Diagnostic harness: prints a human-readable report, not production code.
// ignore_for_file: avoid_print

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/game/world_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('directives vary within a sector and escalate across sectors', () {
    final perSector = <int, Map<String, int>>{};
    var longestRun = 0;
    var runLen = 0;
    LevelDirective? prev;

    for (var i = 1; i <= 1000; i++) {
      final d = directiveFor(levelId: i, mode: DifficultyMode.hard);
      final s = worldForLevel(i).sector.mechanicBudgetTier;
      (perSector[s] ??= {}).update(d.label, (v) => v + 1, ifAbsent: () => 1);

      if (d == prev) {
        runLen++;
      } else {
        runLen = 1;
        prev = d;
      }
      if (runLen > longestRun) longestRun = runLen;
    }

    print('\n=== DIRECTIVE DISTRIBUTION (Hard) ===');
    for (final s in perSector.keys.toList()..sort()) {
      print('sector $s: ${perSector[s]}');
    }
    print('longest identical-directive run: $longestRun levels');

    // A player should never chase the same three-star goal for dozens of
    // levels straight — that is the monotony this rotation exists to fix.
    expect(longestRun, lessThanOrEqualTo(4),
        reason: 'directives must rotate, not sit on one goal for a whole '
            'sector');

    // Every sector must offer at least two distinct goals.
    for (final entry in perSector.entries) {
      expect(entry.value.length, greaterThanOrEqualTo(2),
          reason: 'sector ${entry.key} offers only one directive');
    }

    // Boss levels pin their sector's signature directive, so every boss inside
    // one sector tests the same thing — the world's finale is consistent.
    final bossBySector = <int, Set<String>>{};
    for (var b = 25; b <= 1000; b += 25) {
      final s = worldForLevel(b).sector.mechanicBudgetTier;
      (bossBySector[s] ??= {})
          .add(directiveFor(levelId: b, mode: DifficultyMode.hard).label);
    }
    for (final entry in bossBySector.entries) {
      expect(entry.value.length, 1,
          reason: 'sector ${entry.key} bosses must share one signature '
              'directive, got ${entry.value}');
    }

    // The late campaign must still be dominated by the strict goals.
    final s8 = perSector[8]!;
    expect(s8['FLAWLESS'], isNotNull,
        reason: 'sector 8 must still test FLAWLESS');
  });
}
