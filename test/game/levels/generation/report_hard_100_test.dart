// Wide-sample board report: 100 random Hard levels drawn from L1–L1500.
// Diagnostic only — run it directly:
//   flutter test test/game/levels/generation/report_hard_100_test.dart
// ignore_for_file: avoid_print

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'report_sample.dart';

void main() {
  test('HARD — 100 random levels (L1–1500) board report', () {
    final ids = kReportSampleIds;
    print('\n===== HARD — 100 random levels from L1..1500 '
        '(seed $kReportSampleSeed, budget ${kProdBudget.inMilliseconds}ms) =====');
    print('  canvas = fixed ${kCanvasSpan}x$kCanvasSpan = $kCanvasCells cells; '
        'screen = ${kBandW.toStringAsFixed(0)}x${kBandH.toStringAsFixed(0)}px '
        'playfield band on a ${kRefScreenW.toStringAsFixed(0)}x'
        '${kRefScreenH.toStringAsFixed(0)} phone\n');

    final failures = <int>[];
    final rows = runCampaignBatch(
      levelIds: ids,
      mode: DifficultyMode.hard,
      profile: DifficultyProfile.hard,
      failures: failures,
    );
    printSummary('HARD 100 random (L1–1500)', rows, failures);
    printFitterSweep('HARD 100', rows);
    writeCsv('docs/playtests/report_hard_100.csv', rows);
  }, timeout: const Timeout(Duration(minutes: 45)));
}
