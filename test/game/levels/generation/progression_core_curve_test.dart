// T1.3 — Medium's core-count curve, enumerated rather than spot-checked.
//
// `coreCount: 2` used to appear at two sites in `progression_profile.dart`: an
// explicit `sector == 3` branch and the default `MechanicBudget` that covers
// sectors 4 and up — i.e. most of the campaign. A duplicated literal like that
// is only ever half-updated, and half-updating it here produces a nonsensical
// curve (sector 3 gets three cores, sector 4 onward keeps two) that a spot
// check on one level id sails straight past. So this test enumerates every
// sector the rule covers.
//
// See docs/IMPLEMENTATION_PLAN_V2.md §T1.3.

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/progression_profile.dart';
import 'package:chain_pop/game/world_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every level id in 1..1500 that lands in [sector], so the assertions run
/// against the real `worldForLevel` mapping rather than a hand-picked id that
/// might not even be in the sector it is named for.
List<int> _idsInSector(int sector) => [
      for (var id = 1; id <= 1500; id++)
        if (worldForLevel(id).sector.mechanicBudgetTier == sector) id,
    ];

void main() {
  group('Medium core curve', () {
    // sector 1 -> 0 cores (pure on-ramp)
    // sector 2 -> 1 core  (introduce)
    // sector 3+ -> 3 cores (established)
    const expected = {1: 0, 2: 1, 3: 3, 4: 3, 5: 3, 6: 3, 7: 3, 8: 3};

    for (final entry in expected.entries) {
      test('sector ${entry.key} ships ${entry.value} cores on every level', () {
        final ids = _idsInSector(entry.key);
        expect(ids, isNotEmpty,
            reason: 'sector ${entry.key} has no levels in 1..1500');
        for (final id in ids) {
          expect(
            budgetFor(levelId: id, mode: DifficultyMode.medium).coreCount,
            equals(entry.value),
            reason: 'L$id (sector ${entry.key}) core count',
          );
        }
      });
    }

    test('the curve is monotone and never regresses across the campaign', () {
      var previous = 0;
      for (var sector = 1; sector <= 8; sector++) {
        final ids = _idsInSector(sector);
        if (ids.isEmpty) continue;
        final cores =
            budgetFor(levelId: ids.first, mode: DifficultyMode.medium)
                .coreCount;
        expect(cores, greaterThanOrEqualTo(previous),
            reason: 'sector $sector drops below sector ${sector - 1}');
        previous = cores;
      }
    });
  });

  group('the other modes are unchanged by T1.3', () {
    test('Hard ships three cores in every sector', () {
      for (var sector = 1; sector <= 8; sector++) {
        for (final id in _idsInSector(sector).take(5)) {
          expect(budgetFor(levelId: id, mode: DifficultyMode.hard).coreCount,
              equals(3),
              reason: 'L$id (sector $sector)');
        }
      }
    });

    test('daily challenges keep the sector-8 Hard load', () {
      expect(budgetFor(levelId: 10001, mode: DifficultyMode.hard).coreCount,
          equals(3));
    });
  });
}
