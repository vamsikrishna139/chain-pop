// P3 evidence: Daily generation latency for the known-pathological date keys.
// Diagnostic only — the shipped gate lives in report_daily_10_test.dart.
//
//   flutter test test/game/levels/generation/daily_budget_probe_test.dart
// ignore_for_file: avoid_print

import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('worst-case daily keys', () {
    for (final key in [20260905, 20260819]) {
      for (final budget in <Duration>[
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 400),
      ]) {
        final gen = LevelGenerator();
        final sw = Stopwatch()..start();
        final r = gen.generateDailyChallenge(key, timeBudget: budget);
        sw.stop();
        print('  key=$key budget=${budget.inMilliseconds} '
            'elapsed=${sw.elapsedMilliseconds}ms ok=${r.isSuccess} '
            'nodes=${r.isSuccess ? r.value.nodes.length : -1} '
            'rejections=${gen.evaluatorRejectionCount} '
            'reneg=${gen.renegotiationCount} '
            'retroAttempts=${gen.retrogradeAttemptCount}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
