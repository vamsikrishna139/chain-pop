// P2b T2.16 — why Daily fell out of band, measured at expert tier over 30
// dates instead of the audit gate's 10. Asserts nothing.

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily expert-band diagnosis', () {
    const e = DifficultyProfile.expert;
    var ok = 0;
    const n = 30;
    final fails = <String, int>{};
    for (var i = 0; i < n; i++) {
      final d = DateTime.parse('2026-06-13').add(Duration(days: i));
      final lvl = LevelManager.getDailyChallenge(d);
      final m = LevelMetrics.compute(lvl);
      final why = <String>[];
      if (m.nodeCount < e.nodeCount.min || m.nodeCount > e.nodeCount.max)
        why.add('nodes');
      if (m.averageBranchingFactor < e.averageBranchingFactor.min ||
          m.averageBranchingFactor > e.averageBranchingFactor.max)
        why.add('BF');
      if (m.criticalUnlockDepth < e.criticalUnlockDepth.min ||
          m.criticalUnlockDepth > e.criticalUnlockDepth.max) why.add('CUD');
      if (m.forcedSequenceRatio < e.forcedSequenceRatio.min ||
          m.forcedSequenceRatio > e.forcedSequenceRatio.max) why.add('FSR');
      final passes = e.passes(m);
      if (passes) {
        ok++;
      } else {
        for (final w in why) {
          fails[w] = (fails[w] ?? 0) + 1;
        }
        // ignore: avoid_print
        print(
            '  ${d.toIso8601String().substring(0, 10)}  nodes=${m.nodeCount} BF=${m.averageBranchingFactor.toStringAsFixed(2)} CUD=${m.criticalUnlockDepth} FSR=${(m.forcedSequenceRatio * 100).toStringAsFixed(0)}%  fails=${why.isEmpty ? "(arc/other)" : why.join(",")}');
      }
    }
    // ignore: avoid_print
    print(
        'Daily in-band over $n dates: ${(100 * ok / n).toStringAsFixed(1)}% ($ok/$n)');
    // ignore: avoid_print
    print('failure criteria tally: $fails');
    // ignore: avoid_print
    print(
        'expert bands: nodes=${e.nodeCount.min}-${e.nodeCount.max} BF=${e.averageBranchingFactor.min}-${e.averageBranchingFactor.max} CUD=${e.criticalUnlockDepth.min}-${e.criticalUnlockDepth.max} FSR=${e.forcedSequenceRatio.min}-${e.forcedSequenceRatio.max}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
