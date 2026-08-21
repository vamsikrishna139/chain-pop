// T1.2 cost guard — the repick loop must stay negligible.
//
// `enrichLevel` runs once per *candidate* inside the generator's accept/reject
// loop, not once per emitted board, so anything added to it is multiplied
// across the whole K-loop. The plan's checks-and-balances table therefore puts
// two numbers on the choke point: `enrichLevel` p95 under 5 ms, and at most
// three repick rungs per selection. Both are asserted here.
//
// ignore_for_file: avoid_print

@Tags(['slow'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_parameters.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:chain_pop/game/levels/generation/level_enrichment.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_sample.dart';

void main() {
  test('enrichLevel p95 stays under 5ms and repicks stay bounded', () {
    final micros = <int>[];
    var maxRungs = 0;
    var escalations = 0;
    var floorMisses = 0;
    var selections = 0;

    for (final mode in DifficultyMode.values) {
      final gen = LevelGenerator.neutral();
      final tier = DifficultyProfile.tierFromMode(mode);

      for (final id in kReportSampleIds.take(40)) {
        final result = gen.generate(id, mode: mode, timeBudget: null);
        if (!result.isSuccess) continue;
        final level = result.value;

        // Re-enrich the shipped board: `enrichLevel` is idempotent on core
        // selection (pure function of geometry), so this times exactly the work
        // the generator does per candidate.
        final bare = LevelData(
          levelId: level.levelId,
          gridWidth: level.gridWidth,
          gridHeight: level.gridHeight,
          playCells: level.playCells,
          nodes: [
            for (final n in level.nodes)
              n.copyWith(isCore: false, kind: NodeKind.normal),
          ],
        );
        final config = LevelConfiguration(
          levelId: id,
          gridWidth: level.gridWidth,
          gridHeight: level.gridHeight,
          targetNodeCount: level.nodes.length,
          difficulty: DifficultyParameters.fromLevelId(id, mode: mode),
        );

        final records = <CoreSelectionRecord>[];
        CoreSelectionTelemetry.sink = records.add;
        final sw = Stopwatch()..start();
        enrichLevel(bare, config, tier);
        sw.stop();
        CoreSelectionTelemetry.sink = null;

        micros.add(sw.elapsedMicroseconds);
        for (final r in records) {
          selections++;
          if (r.repickRungs > maxRungs) maxRungs = r.repickRungs;
          if (r.escalated) escalations++;
          if (!r.floorMet) floorMisses++;
        }
      }
    }

    micros.sort();
    final p50 = micros[(micros.length * 0.50).floor()];
    final p95 = micros[(micros.length * 0.95).floor()];
    print('enrichLevel over ${micros.length} boards: '
        'p50=${p50 / 1000}ms p95=${p95 / 1000}ms max=${micros.last / 1000}ms');
    print('core selections=$selections maxRungs=$maxRungs '
        'escalations=$escalations floorMisses=$floorMisses');

    expect(p95, lessThan(5000), reason: 'enrichLevel p95 exceeded 5ms');
    expect(maxRungs, lessThanOrEqualTo(3),
        reason: 'the repick loop is contractually bounded at three rungs');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
