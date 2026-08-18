// Diagnostic harness: prints a human-readable report, not production code.
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';

import 'package:chain_pop/game/levels/generation/metrics.dart';


void main() {
  test('Detailed Analysis of 1000 Levels - Medium & Hard', () {
    print('\n======================================================');
    print('   CHAIN-POP 1000 LEVEL GENERATION DEEP ANALYSIS');
    print('======================================================');

    for (final mode in [DifficultyMode.medium, DifficultyMode.hard]) {
      final gen = LevelGenerator();
      int totalNodes = 0;
      int totalWaves = 0;
      double totalFSR = 0;
      double totalBranching = 0;
      int totalFirstLegal = 0;
      int totalCUD = 0;
      int successCount = 0;

      Map<String, int> shapeCounts = {};
      Map<int, int> nodeDistribution = {};
      Map<int, int> waveDistribution = {};
      Map<int, int> fsrBuckets = {}; // 0-20%, 20-40%, 40-60%, 60-80%, 80-100%

      // Sample breakdown for level buckets (e.g. Early 1-50, Mid 51-200, Late 201-1000)
      Map<String, List<int>> bucketNodes = {
        '1-50': [],
        '51-200': [],
        '201-500': [],
        '501-1000': [],
      };
      Map<String, List<int>> bucketWaves = {
        '1-50': [],
        '51-200': [],
        '201-500': [],
        '501-1000': [],
      };

      for (var i = 1; i <= 1000; i++) {
        final res = gen.generate(i, mode: mode);
        if (res.isSuccess) {
          successCount++;
          final level = res.value;
          final metrics = LevelMetrics.compute(level);

          final nodeCount = level.nodes.length;
          totalNodes += nodeCount;
          totalWaves += metrics.waveDepth;
          totalFSR += metrics.forcedSequenceRatio;
          totalBranching += metrics.averageBranchingFactor;
          totalFirstLegal += metrics.firstLegalMoveCount;
          totalCUD += metrics.criticalUnlockDepth;

          nodeDistribution[nodeCount] = (nodeDistribution[nodeCount] ?? 0) + 1;
          waveDistribution[metrics.waveDepth] = (waveDistribution[metrics.waveDepth] ?? 0) + 1;

          final fsrBucket = (metrics.forcedSequenceRatio * 5).floor().clamp(0, 4);
          fsrBuckets[fsrBucket] = (fsrBuckets[fsrBucket] ?? 0) + 1;

          final shapeKey = '${level.gridWidth}x${level.gridHeight}';
          shapeCounts[shapeKey] = (shapeCounts[shapeKey] ?? 0) + 1;

          final bucketKey = i <= 50 ? '1-50' : (i <= 200 ? '51-200' : (i <= 500 ? '201-500' : '501-1000'));
          bucketNodes[bucketKey]!.add(nodeCount);
          bucketWaves[bucketKey]!.add(metrics.waveDepth);
        }
      }

      final snapshot = gen.snapshotSession();
      print('\n------------------------------------------------------');
      print('   DIFFICULTY MODE: ${mode.name.toUpperCase()} (1,000 Levels Generated)');
      print('------------------------------------------------------');
      print('Success Rate: $successCount / 1000 (${(successCount / 10).toStringAsFixed(1)}%)');
      print('Average Node Count: ${(totalNodes / successCount).toStringAsFixed(2)} nodes');
      print('Average Removal Waves (Depth): ${(totalWaves / successCount).toStringAsFixed(2)} waves');
      print('Average Forced Sequence Ratio (FSR): ${(totalFSR / successCount).toStringAsFixed(3)}');
      print('Average Branching Factor: ${(totalBranching / successCount).toStringAsFixed(2)} choices/step');
      print('Average First Legal Moves (Opening Taps): ${(totalFirstLegal / successCount).toStringAsFixed(2)}');
      print('Average Critical Unlock Depth (CUD): ${(totalCUD / successCount).toStringAsFixed(2)} steps');

      print('\n[Grid Canvas Dimensions]');
      shapeCounts.forEach((k, v) => print('  $k grid: $v levels (${(v / 10).toStringAsFixed(1)}%)'));

      print('\n[Progression Across Campaign Buckets (Avg Nodes | Avg Waves)]');
      bucketNodes.forEach((bKey, nodeList) {
        final avgN = nodeList.isEmpty ? 0.0 : nodeList.reduce((a, b) => a + b) / nodeList.length;
        final waveList = bucketWaves[bKey]!;
        final avgW = waveList.isEmpty ? 0.0 : waveList.reduce((a, b) => a + b) / waveList.length;
        print('  Levels $bKey: Avg Nodes = ${avgN.toStringAsFixed(1)} | Avg Waves = ${avgW.toStringAsFixed(1)}');
      });

      print('\n[Node Count Histogram]');
      final sortedNodes = nodeDistribution.keys.toList()..sort();
      print('  Range: ${sortedNodes.first} to ${sortedNodes.last} nodes');
      for (final n in sortedNodes) {
        if (nodeDistribution[n]! > 15) {
          print('    $n nodes: ${nodeDistribution[n]} levels (${(nodeDistribution[n]! / 10).toStringAsFixed(1)}%)');
        }
      }

      print('\n[Removal Waves Histogram (Solve Depth)]');
      final sortedWaves = waveDistribution.keys.toList()..sort();
      print('  Range: ${sortedWaves.first} to ${sortedWaves.last} waves');
      for (final w in sortedWaves) {
        print('    $w waves: ${waveDistribution[w]} levels (${(waveDistribution[w]! / 10).toStringAsFixed(1)}%)');
      }

      print('\n[Forced Sequence Ratio (FSR) Linearity Profile]');
      print('  0.00 - 0.20 (Highly Branching / Easy): ${fsrBuckets[0] ?? 0} levels');
      print('  0.20 - 0.40 (Flexible / Choice Heavy): ${fsrBuckets[1] ?? 0} levels');
      print('  0.40 - 0.60 (Balanced Funneling):       ${fsrBuckets[2] ?? 0} levels');
      print('  0.60 - 0.80 (Tight Linear Sequence):    ${fsrBuckets[3] ?? 0} levels');
      print('  0.80 - 1.00 (Single-Path Bottleneck):   ${fsrBuckets[4] ?? 0} levels');

      print('\n[Director Archetype Emissions]');
      snapshot.archetypeEmissions.forEach((k, v) {
        print('  ${k.name}: $v levels (${(v / 10).toStringAsFixed(1)}%)');
      });

      print('\n[Generator Diagnostics & Quality Gates]');
      print('  Evaluator Rejections (Band Misses): ${snapshot.evaluatorRejections}');
      print('  Diversity Rejections (Duplicates):   ${snapshot.diversityRejections}');
      print('  Renegotiations (Downscaling/Swaps): ${snapshot.renegotiations}');
    }
  });
}
