// Diagnostic harness for the milestone-seed path. Asserts nothing — it exists
// to answer one question with numbers instead of inference:
//
//   when a milestone slot does not ship as its own silhouette, where does the
//   seeded path actually stop?
//
// Every 25th level pins a hand-authored silhouette so the player gets a
// recognisable landmark. When that path exhausts its attempts it falls through
// to the ordinary procedural pipeline: the level still generates, the player
// still gets a playable board, and nothing anywhere says the landmark is gone.
// `LevelGenerator` counted only the seeded attempts that *shipped*, so the
// failures were invisible; the counters this harness prints are the other half.
//
// Read the columns as a funnel — attempts split into construction failures
// (the Director could not build the pinned silhouette), validation failures
// (it built, but the enriched board was invalid), mechanic shortfalls (it built
// and validated, but could not seat its full lock/relay budget), and, at the
// end, either an emission or a fallthrough.
//
//   flutter test test/game/levels/generation/milestone_seed_audit_test.dart
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Milestone cadence: every 25th level from 25 to 1000.
const int _kFirstSlot = 25;
const int _kLastSlot = 1000;
const int _kSlotStride = 25;

String _kindFor(int slot) => switch (slot % 100) {
      0 => 'sniper',
      50 => 'overload',
      25 => 'diamond',
      _ => 'ring',
    };

void main() {
  test('milestone seed funnel, all slots x {medium, hard}', () {
    for (final mode in [DifficultyMode.medium, DifficultyMode.hard]) {
      print('\n=== MILESTONE SEED AUDIT — ${mode.name} ===');
      print('slot  kind      ms      att  cons  val  short  result');

      var lostSlots = 0;
      var totalMs = 0;
      var worstMs = 0;
      var worstSlot = 0;

      for (var slot = _kFirstSlot; slot <= _kLastSlot; slot += _kSlotStride) {
        // A fresh generator per level: the counters are cumulative, and a
        // shared diversity ledger would also let earlier slots steer later
        // ones. `neutral()` declares both.
        final gen = LevelGenerator.neutral();

        final sw = Stopwatch()..start();
        final res = gen.generate(slot, mode: mode);
        sw.stop();

        // The seed id is whatever the path actually touched, whether it
        // emitted or gave up — so read it from either side of the funnel.
        final seedIds = <String>{
          ...gen.seedAttemptCounts.keys,
          ...gen.seedEmissionCounts.keys,
        };
        final id = seedIds.isEmpty ? '-' : seedIds.join('+');

        int sum(Map<String, int> m) => m.values.fold<int>(0, (a, b) => a + b);

        final attempts = sum(gen.seedAttemptCounts);
        final construction = sum(gen.seedConstructionFailureCounts);
        final validation = sum(gen.seedValidationFailureCounts);
        final shortfall = sum(gen.seedMechanicShortfallCounts);
        final fallthrough = sum(gen.seedFallthroughCounts);
        final emitted = sum(gen.seedEmissionCounts);

        final String result;
        if (!res.isSuccess) {
          result = 'GENERATION FAILED';
        } else if (emitted > 0) {
          result = 'emitted $id';
        } else if (fallthrough > 0) {
          result = 'LOST -> procedural (seed $id)';
        } else {
          result = 'no seed for this slot';
        }
        if (fallthrough > 0) lostSlots++;

        final ms = sw.elapsedMilliseconds;
        totalMs += ms;
        if (ms > worstMs) {
          worstMs = ms;
          worstSlot = slot;
        }

        print('${slot.toString().padLeft(4)}  '
            '${_kindFor(slot).padRight(9)} '
            '${ms.toString().padLeft(6)}  '
            '${attempts.toString().padLeft(3)}  '
            '${construction.toString().padLeft(4)}  '
            '${validation.toString().padLeft(3)}  '
            '${shortfall.toString().padLeft(5)}  '
            '$result');
      }

      const slots = ((_kLastSlot - _kFirstSlot) ~/ _kSlotStride) + 1;
      print('\n${mode.name}: $lostSlots/$slots slots lost the landmark; '
          'total ${totalMs}ms, worst slot $worstSlot at ${worstMs}ms');
    }
  });
}
