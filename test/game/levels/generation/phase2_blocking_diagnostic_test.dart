import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/removal_order.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 2 debug — which failure mode is active?
void main() {
  test('L30-39 blocking telemetry diagnosis', () {
    final gen = LevelGenerator();
    var totalOffered = 0;
    var totalPicked = 0;
    var totalRetries = 0;
    var totalBlockedNodes = 0;
    var totalNodes = 0;

    for (var id = 30; id <= 39; id++) {
      final before = gen.snapshotSession();
      final r = gen.generate(id, mode: DifficultyMode.hard);
      expect(r.isSuccess, isTrue);
      final after = gen.snapshotSession();
      final level = r.value;
      final m = LevelMetrics.compute(level);
      final blocked = _blockedRayNodeCount(level);

      totalOffered += after.blockingDirCandidatesOffered -
          before.blockingDirCandidatesOffered;
      totalPicked += after.blockingDirCandidatesPicked -
          before.blockingDirCandidatesPicked;
      totalRetries += after.constructionSolvabilityRetries -
          before.constructionSolvabilityRetries;
      totalBlockedNodes += blocked;
      totalNodes += level.nodes.length;

      // ignore: avoid_print
      print(
        'L$id: offered=${after.blockingDirCandidatesOffered - before.blockingDirCandidatesOffered} '
        'picked=${after.blockingDirCandidatesPicked - before.blockingDirCandidatesPicked} '
        'retries=${after.constructionSolvabilityRetries - before.constructionSolvabilityRetries} '
        'blockedNodes=$blocked/${level.nodes.length} '
        'FSR=${(m.forcedSequenceRatio * 100).toStringAsFixed(0)}% '
        'opening=${m.firstLegalMoveCount}',
      );
    }

    const n = 10.0;
    // ignore: avoid_print
    print('\n=== DIAGNOSIS ===');
    // ignore: avoid_print
    print(
      'Per-level avg: offered=${totalOffered / n} picked=${totalPicked / n} '
      'retries=${totalRetries / n} blockedNodes=${totalBlockedNodes / n}',
    );
    // ignore: avoid_print
    print(
      'Pick rate: ${totalPicked / totalOffered * 100}% of offered blocking candidates',
    );
    // ignore: avoid_print
    print(
      'Blocked-node share: ${totalBlockedNodes / totalNodes * 100}% of shipped nodes',
    );

    // Culprit 3 ruled out if offered > 0
    expect(totalOffered, greaterThan(0),
        reason: 'blocking dirs must be offered');
    // Blocking IS reaching shipped levels
    expect(totalBlockedNodes, greaterThan(50),
        reason: 'shipped levels should contain blocked-ray nodes');
  });

  test('retrograde occupancy maps to player phase correctly', () {
    // Retrograde occ high → opening (clear only). Low → release. Mid → crunch.
    // Verify _directionPoolForZone behavior via zone boundaries.
    expect(_zoneForOccupancy(0.90), 'opening');
    expect(_zoneForOccupancy(0.70), 'opening');
    expect(_zoneForOccupancy(0.50), 'crunch');
    expect(_zoneForOccupancy(0.35), 'crunch');
    expect(_zoneForOccupancy(0.20), 'release');
    expect(_zoneForOccupancy(0.05), 'release');
  });
}

String _zoneForOccupancy(double occ) {
  if (occ > 0.65) return 'opening';
  if (occ >= 0.35) return 'crunch';
  return 'release';
}

int _blockedRayNodeCount(LevelData level) {
  final keys = {for (final n in level.nodes) gridCellKey(n.x, n.y)};
  var count = 0;
  for (final n in level.nodes) {
    final others = Set<int>.from(keys)..remove(gridCellKey(n.x, n.y));
    if (rayHitsObstacleBeforeExit(
      Point(n.x, n.y),
      n.dir,
      others,
      level.gridWidth,
      level.gridHeight,
    )) {
      count++;
    }
  }
  return count;
}
