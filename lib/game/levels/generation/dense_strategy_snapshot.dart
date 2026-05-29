// ignore_for_file: avoid_print

import 'difficulty_mode.dart';
import 'difficulty_profile.dart';
import 'level_generator.dart';
import 'metrics.dart';

/// Prints gameplay-relevant metrics for manual Dense Strategy comparison.
void runDenseStrategySnapshot() {
  final gen = LevelGenerator();

  print('=== Dense Strategy — gameplay metrics snapshot ===\n');

  _sampleHardCampaign(gen, count: 20, startId: 30);
  _sampleHardCampaign(gen, count: 5, startId: 47);
  _sampleDailies(gen, dayKeys: const [
    20260515,
    20260516,
    20260517,
    20260518,
    20260519,
    20260520,
    20260521,
  ]);
}

void _sampleHardCampaign(
  LevelGenerator gen, {
  required int count,
  required int startId,
}) {
  print('--- Hard campaign (levels $startId–${startId + count - 1}) ---');
  var totalNodes = 0;
  var totalFill = 0.0;
  var cudSum = 0;
  var fsrSum = 0.0;
  var waveSum = 0;
  var flmSum = 0;
  var inBand = 0;
  final viablePaths = <int>[];
  var chainDepthMaxSum = 0;
  var maxHubSum = 0;
  var fanoutSum = 0.0;
  var pathsCappedCount = 0;

  for (var i = 0; i < count; i++) {
    final id = startId + i;
    final r = gen.generate(id, mode: DifficultyMode.hard);
    if (r.isError) {
      print('  level $id: FAILED ${r.error}');
      continue;
    }
    final level = r.value;
    final m = LevelMetrics.compute(level, includeViablePath: true);
    final area = level.gridWidth * level.gridHeight;
    final fill = level.nodes.length / area;
    final profile = DifficultyProfile.hard;
    final passes = profile.passes(m);
    final topo = LevelTopologyMetrics.compute(level);

    totalNodes += m.nodeCount;
    totalFill += fill;
    cudSum += m.criticalUnlockDepth;
    fsrSum += m.forcedSequenceRatio;
    waveSum += m.waveDepth;
    flmSum += m.firstLegalMoveCount;
    if (passes) inBand++;
    if (m.viablePathCount >= 0) viablePaths.add(m.viablePathCount);
    chainDepthMaxSum += topo.chainDepthMax;
    maxHubSum += topo.maxHubInDegree;
    fanoutSum += topo.avgUnlockFanout;
    if (m.viablePathCountCapped) pathsCappedCount++;

    print(
      '  L$id: ${level.gridWidth}x${level.gridHeight} '
      'nodes=${m.nodeCount} fill=${(fill * 100).toStringAsFixed(0)}% '
      'CUD=${m.criticalUnlockDepth} FSR=${(m.forcedSequenceRatio * 100).toStringAsFixed(0)}% '
      'waves=${m.waveDepth} openingMoves=${m.firstLegalMoveCount} '
      'BF=${m.averageBranchingFactor.toStringAsFixed(1)} '
      'viablePaths=${m.viablePathCount >= 0 ? m.viablePathCount : "?"} '
      'inBand=${passes ? "yes" : "no"} '
      'tempo=${m.tempoProfile} '
      'chainDepthMax=${topo.chainDepthMax} maxHub=${topo.maxHubInDegree} '
      'avgFanout=${topo.avgUnlockFanout.toStringAsFixed(1)} '
      'pathsCapped=${m.viablePathCountCapped}',
    );
  }

  final n = count.toDouble();
  print(
    '\n  Averages: nodes=${(totalNodes / n).toStringAsFixed(1)} '
    'fill=${(totalFill / n * 100).toStringAsFixed(0)}% '
    'CUD=${(cudSum / n).toStringAsFixed(1)} '
    'FSR=${(fsrSum / n * 100).toStringAsFixed(0)}% '
    'waves=${(waveSum / n).toStringAsFixed(1)} '
    'openingMoves=${(flmSum / n).toStringAsFixed(1)} '
    'evaluatorInBand=${inBand}/$count '
    'chainDepthMax=${(chainDepthMaxSum / n).toStringAsFixed(1)} '
    'maxHub=${(maxHubSum / n).toStringAsFixed(1)} '
    'avgFanout=${(fanoutSum / n).toStringAsFixed(1)} '
    'pathsCapped=$pathsCappedCount/$count',
  );
  if (viablePaths.isNotEmpty) {
    viablePaths.sort();
    print(
      '  Viable paths: min=${viablePaths.first} median=${viablePaths[viablePaths.length ~/ 2]} max=${viablePaths.last}',
    );
  }
  final snap = gen.snapshotSession();
  print(
    '  Construction telemetry: blockingOffered=${snap.blockingDirCandidatesOffered} '
    'blockingPicked=${snap.blockingDirCandidatesPicked} '
    'crunchPick=${snap.crunchZoneBlockingPicked} releasePick=${snap.releaseZoneFallbackPicked} '
    'solvabilityRetries=${snap.constructionSolvabilityRetries} '
    'winRetry=0:${snap.winningBlockingRetryIndex0} 1:${snap.winningBlockingRetryIndex1} 2:${snap.winningBlockingRetryIndex2} '
    'maxAttemptsExhausted=${snap.maxAttemptsExhaustedCount}',
  );
  print('');
}

void _sampleDailies(
  LevelGenerator gen, {
  required List<int> dayKeys,
}) {
  print('--- Daily challenges ---');
  for (final key in dayKeys) {
    final r = gen.generateDailyChallenge(key);
    if (r.isError) {
      print('  $key: FAILED ${r.error}');
      continue;
    }
    final level = r.value;
    final m = LevelMetrics.compute(level, includeViablePath: true);
    final area = level.gridWidth * level.gridHeight;
    final fill = level.nodes.length / area;
    final profile = DifficultyProfile.expert;
    final passes = profile.passes(m);
    print(
      '  $key: ${level.gridWidth}x${level.gridHeight} '
      'nodes=${m.nodeCount} fill=${(fill * 100).toStringAsFixed(0)}% '
      'CUD=${m.criticalUnlockDepth} FSR=${(m.forcedSequenceRatio * 100).toStringAsFixed(0)}% '
      'waves=${m.waveDepth} openingMoves=${m.firstLegalMoveCount} '
      'inBand=${passes ? "yes" : "no"}',
    );
  }
  print('');
}
