// Gate: every milestone slot ships as its own hand-authored landmark.
//
// Every 25th level pins a seed so the player gets a recognisable board at the
// slot they have been climbing towards. When the seeded path exhausted its
// attempts it fell through to the ordinary procedural pipeline — the level
// still generated and still played, so no existing test noticed, and 16 of the
// 40 Hard slots (plus 8 Medium) shipped with no landmark at all.
//
// This is the gate for that. It is deliberately about *identity*, not quality:
// the level being playable is other tests' job, and this one only asks whether
// the milestone is the milestone.
//
// What the assertions can and cannot see: enrichment rebuilds `LevelData`
// without `silhouetteId`, so the shipped board does not carry its own shape
// label and cannot simply be asked. Two things stand in for it —
//
//   * `seedEmissionCounts` is incremented only on the seeded path's ship line,
//     so a non-zero count for the expected id proves *that* board came from
//     *that* seed's plan, and `Director.choosePlanFromSeed` pins the plan's
//     silhouette to the seed's;
//   * `playCells` survives enrichment untouched, so a seed whose silhouette
//     carves cells out of the grid must not ship a full rectangle.
//
// Together they catch the regression that motivated the test (a silently
// procedural milestone) and a seeded plan renegotiating its way onto the
// rectangle fallback. They would not catch a ring shipped as a diamond; the
// pin in `GenerationPlan.pinnedSilhouette` is what rules that out.

import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:chain_pop/game/levels/seeds/seed_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Milestone cadence: every 25th level from 25 to 1000.
const int _kFirstSlot = 25;
const int _kLastSlot = 1000;
const int _kSlotStride = 25;

void main() {
  group('milestone slots ship their own seed', () {
    for (final mode in [DifficultyMode.medium, DifficultyMode.hard]) {
      test(mode.name, () {
        final lost = <String>[];
        final rectangular = <String>[];

        for (var slot = _kFirstSlot; slot <= _kLastSlot; slot += _kSlotStride) {
          final config = LevelConfiguration.fromLevelId(slot, mode: mode);
          final seed = milestoneSeedFor(config);
          // Showcase levels and the sub-25 run own their slots outright.
          if (seed == null) continue;

          // Fresh generator per level: the seed counters are cumulative, and a
          // shared diversity ledger would let earlier slots steer later ones.
          final gen = LevelGenerator.neutral();
          final res = gen.generate(slot, mode: mode);

          expect(res.isSuccess, isTrue,
              reason: 'slot $slot (${mode.name}) must generate at all');

          if ((gen.seedEmissionCounts[seed.id] ?? 0) == 0) {
            lost.add('$slot -> ${seed.id} '
                '(${gen.seedFallthroughCounts[seed.id] ?? 0} fallthrough, '
                '${gen.seedAttemptCounts[seed.id] ?? 0} attempts, '
                '${gen.seedMechanicShortfallCounts[seed.id] ?? 0} shortfalls, '
                '${gen.seedConstructionFailureCounts[seed.id] ?? 0} '
                'construction failures)');
            continue;
          }

          // Whether the seed's silhouette can be rendered at all on this
          // level's grid. `Director._buildOrFallbackMask` asks exactly this
          // and falls back to the full rectangle when the answer is null, so
          // a null here means the rectangle is forced and there is no shape
          // decision left for the seeded path to get wrong.
          //
          // On Hard this is currently null for every diamond slot: the mode's
          // `minNodes` floor (25) is higher than the diamond carves out of an
          // 8x8, so Hard diamonds have always shipped as rectangles — before
          // this gate existed and before the fallthrough fix, which only
          // changed whether they shipped as *diamond seeds*. Raising them to a
          // real diamond means moving Hard's node floor, which is load-bearing
          // elsewhere (evaluator FSR rule, perf budget, seed byte-stability)
          // and is not this test's call to make.
          //
          // Deliberately expressed as the live mask query rather than as a
          // hard-coded "skip Hard": if the floor is ever retuned, this gate
          // starts enforcing those slots on its own.
          final renderable = buildSilhouetteMask(
                id: seed.silhouetteId,
                gridWidth: config.gridWidth,
                gridHeight: config.gridHeight,
                random: Random(slot),
                minCells: config.difficulty.minNodes,
                varied: false,
              ) !=
              null;

          if (seed.silhouetteId != SilhouetteId.rectangle && renderable) {
            final level = res.value;
            final full = level.gridWidth * level.gridHeight;
            // A null `playCells` is the "whole grid is playable" encoding, so
            // it fails this check for the same reason a full set does.
            final cells = level.playCells;
            if (cells == null || cells.length == full) {
              rectangular.add('$slot -> ${seed.id} '
                  '(${seed.silhouetteId.name} shipped as a full '
                  '${level.gridWidth}x${level.gridHeight} rectangle)');
            }
          }
        }

        expect(lost, isEmpty,
            reason: 'milestone slots that lost their landmark and shipped as '
                'ordinary procedural boards:\n  ${lost.join('\n  ')}');
        expect(rectangular, isEmpty,
            reason: 'milestone slots whose silhouette collapsed to the '
                'rectangle fallback:\n  ${rectangular.join('\n  ')}');
      });
    }
  });
}
