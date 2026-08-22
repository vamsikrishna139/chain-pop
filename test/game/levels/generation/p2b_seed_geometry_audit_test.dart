// P2b T2.20 — do pinned seeds ship the shape they declare?
//
//   flutter test --tags report \
//     test/game/levels/generation/p2b_seed_geometry_audit_test.dart
//
// **Asserts nothing** — this is the audit, not the gate.
//
// A hand-authored seed pins a silhouette on purpose. But `choosePlanFromSeed`
// builds its mask through `_buildOrFallbackMask`, which returns `.mask` and
// DISCARDS the resolved id that `_resolveMask` computes. So when the declared
// shape fails its `minCells` floor, the plan keeps the seed's label while
// carrying the 64-cell rectangle fallback — a full-grid board that calls
// itself a diamond.
//
// This is not corrupt seed data. `diamond` spans p10=24 cells against a floor
// of 25 and `corridor` p10=16, so a low draw legitimately fails to build; the
// runtime then substitutes silently instead of reporting the substitution.
//
// The audit reports every campaign slot whose emitted board is a full grid
// while its analytics silhouette says otherwise.
//
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

void main() {
  test('P2b pinned-seed geometry audit', () {
    for (final mode in [DifficultyMode.hard, DifficultyMode.medium]) {
      final sink = InMemoryAnalyticsSink();
      final gen = LevelGenerator(analyticsSink: sink);
      var full = 0;
      var mismatched = 0;
      final byId = <SilhouetteId, int>{};
      for (var id = 1; id <= 300; id++) {
        final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
        if (!r.isSuccess || sink.events.isEmpty) continue;
        final sid = sink.events.last.silhouette;
        if (r.value.playCells != null) continue;
        full++;
        if (sid == SilhouetteId.rectangle) continue;
        mismatched++;
        byId[sid] = (byId[sid] ?? 0) + 1;
        print('  ${mode.name} L$id  declares ${sid.name}, ships a full '
            '${r.value.gridWidth}x${r.value.gridHeight} grid');
      }
      print('${mode.name.toUpperCase()} L1-300: $full full-grid boards, '
          '$mismatched of them mislabelled  $byId');
      print('');
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
