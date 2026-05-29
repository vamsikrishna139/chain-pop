import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/removal_order.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed seed so random level picks are reproducible across runs.
const _kSnapshotSeed = 424242;

/// Prints gameplay-relevant metrics for manual inspection:
/// `flutter test test/game/levels/generation/dense_strategy_snapshot_test.dart`
void main() {
  test('prints dense strategy gameplay snapshot', () {
    final gen = LevelGenerator();

    // ignore: avoid_print
    print('\n=== Dense Strategy — gameplay metrics snapshot ===\n');

    _printSequentialBatch(
      gen,
      label: 'Hard campaign (L30–39)',
      mode: DifficultyMode.hard,
      profile: DifficultyProfile.hard,
      startId: 30,
      count: 10,
    );

    _printSequentialBatch(
      gen,
      label: 'Hard campaign (L47–49)',
      mode: DifficultyMode.hard,
      profile: DifficultyProfile.hard,
      startId: 47,
      count: 3,
    );

    _printBatch(
      gen,
      label: 'Hard (20 random, L30–500)',
      mode: DifficultyMode.hard,
      profile: DifficultyProfile.hard,
      levelIds: _sampleLevelIds(
        count: 20,
        minId: 30,
        maxId: 500,
        seed: _kSnapshotSeed,
      ),
    );

    _printBatch(
      gen,
      label: 'Easy (10 random, L1–99)',
      mode: DifficultyMode.easy,
      profile: DifficultyProfile.easy,
      levelIds: _sampleLevelIds(
        count: 10,
        minId: 1,
        maxId: 99,
        seed: _kSnapshotSeed + 1,
      ),
    );

    _printBatch(
      gen,
      label: 'Medium (10 random, L10–200)',
      mode: DifficultyMode.medium,
      profile: DifficultyProfile.medium,
      levelIds: _sampleLevelIds(
        count: 10,
        minId: 10,
        maxId: 200,
        seed: _kSnapshotSeed + 2,
      ),
    );

    _printDailies();
  });
}

List<int> _sampleLevelIds({
  required int count,
  required int minId,
  required int maxId,
  required int seed,
}) {
  final rng = Random(seed);
  final ids = <int>{};
  final span = maxId - minId + 1;
  assert(count <= span, 'count must not exceed id span');
  while (ids.length < count) {
    ids.add(minId + rng.nextInt(span));
  }
  return ids.toList()..sort();
}

void _printSequentialBatch(
  LevelGenerator gen, {
  required String label,
  required DifficultyMode mode,
  required DifficultyProfile profile,
  required int startId,
  required int count,
}) {
  _printBatch(
    gen,
    label: label,
    mode: mode,
    profile: profile,
    levelIds: List.generate(count, (i) => startId + i),
  );
}

void _printBatch(
  LevelGenerator gen, {
  required String label,
  required DifficultyMode mode,
  required DifficultyProfile profile,
  required List<int> levelIds,
}) {
  // ignore: avoid_print
  print('--- $label ---');
  if (levelIds.length > 1 && levelIds.last - levelIds.first + 1 != levelIds.length) {
    // ignore: avoid_print
    print('  levels: ${levelIds.join(", ")}');
  }

  var nodes = 0, cud = 0, waves = 0, flm = 0, inBand = 0;
  var fillSum = 0.0, fsrSum = 0.0, bfSum = 0.0;
  var tempoMinSum = 0, tempoMaxSum = 0;
  final viable = <int>[];

  var offeredSum = 0, pickedSum = 0, retrySum = 0, blockedNodesSum = 0;
  var crunchPickSum = 0, releasePickSum = 0;
  var winRetry0 = 0, winRetry1 = 0, winRetry2 = 0;
  var chainDepthMaxSum = 0, maxHubSum = 0, pathsCappedCount = 0;
  var fanoutSum = 0.0;

  for (final id in levelIds) {
    final before = gen.snapshotSession();
    final r = gen.generate(id, mode: mode);
    expect(r.isSuccess, isTrue, reason: 'L$id ($mode) should generate');
    final after = gen.snapshotSession();
    final offered = after.blockingDirCandidatesOffered -
        before.blockingDirCandidatesOffered;
    final picked =
        after.blockingDirCandidatesPicked - before.blockingDirCandidatesPicked;
    final retries = after.constructionSolvabilityRetries -
        before.constructionSolvabilityRetries;
    final crunchPick = after.crunchZoneBlockingPicked -
        before.crunchZoneBlockingPicked;
    final releasePick = after.releaseZoneFallbackPicked -
        before.releaseZoneFallbackPicked;
    final winRetry = gen.lastWinningBlockingRetryIndex;

    final level = r.value;
    final m = LevelMetrics.compute(level, includeViablePath: true);
    final area = level.gridWidth * level.gridHeight;
    final fill = level.nodes.length / area;
    final passes = profile.passes(m);
    final tempo = m.tempoProfile;
    final tempoMin = tempo.isEmpty ? 0 : tempo.reduce(min);
    final tempoMax = tempo.isEmpty ? 0 : tempo.reduce(max);
    final blockedNodes = _countBlockedRayNodes(level);
    final topo = LevelTopologyMetrics.compute(level);
    final pathsCapped = m.viablePathCountCapped;

    nodes += m.nodeCount;
    fillSum += fill;
    cud += m.criticalUnlockDepth;
    fsrSum += m.forcedSequenceRatio;
    waves += m.waveDepth;
    flm += m.firstLegalMoveCount;
    bfSum += m.averageBranchingFactor;
    tempoMinSum += tempoMin;
    tempoMaxSum += tempoMax;
    offeredSum += offered;
    pickedSum += picked;
    retrySum += retries;
    blockedNodesSum += blockedNodes;
    crunchPickSum += crunchPick;
    releasePickSum += releasePick;
    if (winRetry == 0) winRetry0++;
    if (winRetry == 1) winRetry1++;
    if (winRetry == 2) winRetry2++;
    chainDepthMaxSum += topo.chainDepthMax;
    maxHubSum += topo.maxHubInDegree;
    fanoutSum += topo.avgUnlockFanout;
    if (pathsCapped) pathsCappedCount++;
    if (passes) inBand++;
    if (m.viablePathCount >= 0) viable.add(m.viablePathCount);

    // ignore: avoid_print
    print(
      '  L$id: ${level.gridWidth}x${level.gridHeight} '
      'nodes=${m.nodeCount} fill=${(fill * 100).toStringAsFixed(0)}% '
      'CUD=${m.criticalUnlockDepth} FSR=${(m.forcedSequenceRatio * 100).toStringAsFixed(0)}% '
      'waves=${m.waveDepth} opening=${m.firstLegalMoveCount} '
      'BF=${m.averageBranchingFactor.toStringAsFixed(1)} '
      'tempoMin=$tempoMin tempoMax=$tempoMax '
      'paths=${m.viablePathCount} inBand=$passes '
      'blkOffered=$offered blkPicked=$picked solvRetries=$retries blockedNodes=$blockedNodes '
      'crunchPick=$crunchPick releasePick=$releasePick winRetry=$winRetry '
      'chainDepthMax=${topo.chainDepthMax} maxHub=${topo.maxHubInDegree} '
      'avgFanout=${topo.avgUnlockFanout.toStringAsFixed(1)} pathsCapped=$pathsCapped '
      'wavesProfile=${m.wavePeelingProfile}',
    );
  }

  final n = levelIds.length.toDouble();
  // ignore: avoid_print
  print(
    '  AVG: nodes=${(nodes / n).toStringAsFixed(0)} fill=${(fillSum / n * 100).toStringAsFixed(0)}% '
    'CUD=${(cud / n).toStringAsFixed(1)} FSR=${(fsrSum / n * 100).toStringAsFixed(0)}% '
    'waves=${(waves / n).toStringAsFixed(1)} opening=${(flm / n).toStringAsFixed(1)} '
    'BF=${(bfSum / n).toStringAsFixed(1)} '
    'tempoMin=${(tempoMinSum / n).toStringAsFixed(1)} tempoMax=${(tempoMaxSum / n).toStringAsFixed(1)} '
    'inBand=$inBand/${levelIds.length} '
    'paths=${viable.isEmpty ? "n/a" : "${viable.reduce((a, b) => a + b) ~/ viable.length} avg"} '
    'blkOffered=${(offeredSum / n).toStringAsFixed(0)} blkPicked=${(pickedSum / n).toStringAsFixed(1)} '
    'solvRetries=${(retrySum / n).toStringAsFixed(1)} blockedNodes=${(blockedNodesSum / n).toStringAsFixed(1)} '
    'crunchPick=${(crunchPickSum / n).toStringAsFixed(1)} releasePick=${(releasePickSum / n).toStringAsFixed(1)} '
    'winRetry=0:$winRetry0 1:$winRetry1 2:$winRetry2 '
    'chainDepthMax=${(chainDepthMaxSum / n).toStringAsFixed(1)} '
    'maxHub=${(maxHubSum / n).toStringAsFixed(1)} '
    'avgFanout=${(fanoutSum / n).toStringAsFixed(1)} '
    'pathsCapped=$pathsCappedCount/${levelIds.length}\n',
  );
}

/// Nodes whose assigned direction hits another node before exiting the grid.
int _countBlockedRayNodes(LevelData level) {
  final keys = {
    for (final n in level.nodes) gridCellKey(n.x, n.y),
  };
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

void _printDailies() {
  // ignore: avoid_print
  print('--- Daily challenges (sample week) ---');
  const keys = [
    20260515,
    20260516,
    20260517,
    20260518,
    20260519,
    20260520,
    20260521,
  ];
  for (final key in keys) {
    final s = key.toString();
    final date = DateTime(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );
    final level = LevelManager.getDailyChallenge(date);
    final m = LevelMetrics.compute(level, includeViablePath: true);
    final fill = level.nodes.length / (level.gridWidth * level.gridHeight);
    final passes = DifficultyProfile.expert.passes(m);
    // ignore: avoid_print
    print(
      '  $key: ${level.gridWidth}x${level.gridHeight} '
      'nodes=${m.nodeCount} fill=${(fill * 100).toStringAsFixed(0)}% '
      'CUD=${m.criticalUnlockDepth} FSR=${(m.forcedSequenceRatio * 100).toStringAsFixed(0)}% '
      'waves=${m.waveDepth} opening=${m.firstLegalMoveCount} '
      'BF=${m.averageBranchingFactor.toStringAsFixed(1)} inBand=$passes '
      'wavesProfile=${m.wavePeelingProfile}',
    );
  }
}
