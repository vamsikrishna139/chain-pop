// T2.9a — is the CUD floor safe to relax? Measured, one variable at a time.
//
//   flutter test --tags report \
//     test/game/levels/generation/p2b_cud_isolation_report_test.dart
//
// **Asserts nothing** (plan §0.5). T2.5's mortality table put the CUD floor at
// 22.3% of Hard K-loop iterations — the second-largest killer after
// composition `components`, which is closed by T2.4c's evidence. That makes
// CUD the next candidate, and "large" is not "safe to relax".
//
// Three variants differing by exactly one integer:
//
//   A  relaxation 0   baseline, the shipped floor
//   B  relaxation 1   mildly relaxed
//   C  relaxation 99  effectively disabled
//
// Every other lever is untouched. This is the T2.8 discipline: a change with an
// obvious story still gets measured alone, because three of them have now been
// wrong.
//
// Reported per variant:
//   * funnel     — rankable/level, exit paths, no-choice share
//   * quality    — composition p10 (the T2.4b gate), shipped-CUD distribution
//   * cost       — generation p95
//
// ignore_for_file: avoid_print

@Tags(['corpus', 'report'])
library;

import 'dart:math' as math;

import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

const int kLevels = 300;

void main() {
  test('T2.9a CUD isolation', () {
    for (final relax in [0, 1, 99]) {
      final label = relax == 0
          ? 'A  relaxation 0  (baseline, shipped floor)'
          : relax == 1
              ? 'B  relaxation 1  (mildly relaxed)'
              : 'C  relaxation 99 (floor effectively disabled)';
      print('\n═══ VARIANT $label ═══');
      LevelGenerator.cudFloorRelaxation = relax;
      for (final mode in [DifficultyMode.hard, DifficultyMode.medium]) {
        _sweep(mode);
      }
    }
    // Never leave the knob set — every later test in the same process would
    // silently run a different generator.
    LevelGenerator.cudFloorRelaxation = 0;
  }, timeout: const Timeout(Duration(minutes: 60)));
}

void _sweep(DifficultyMode mode) {
  final sink = InMemoryAnalyticsSink();
  final gen = LevelGenerator(analyticsSink: sink);
  final paths = <String, int>{};
  final rankableHist = <int, int>{};
  final durations = <int>[];
  var totalRankable = 0, totalCand = 0, totalNovel = 0, n = 0;
  var cudRejects = 0, iters = 0;

  for (var id = 1; id <= kLevels; id++) {
    gen.resetCounters();
    final sw = Stopwatch()..start();
    final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
    sw.stop();
    if (!r.isSuccess) continue;
    n++;
    durations.add(sw.elapsedMicroseconds);
    final a = gen.acceptedNovelCandidateCount;
    rankableHist[a] = (rankableHist[a] ?? 0) + 1;
    totalRankable += a;
    totalCand += gen.candidateCount;
    totalNovel += gen.novelCandidateCount;
    cudRejects += gen.cudFloorRejects;
    iters += gen.kloopIterations;
    gen.fallbackReasonCounts.forEach((k, v) => paths[k] = (paths[k] ?? 0) + v);
  }

  final d = math.max(1, n);
  final shippedCud =
      sink.events.map((e) => e.metrics.criticalUnlockDepth).toList()..sort();
  durations.sort();

  final noChoice = (rankableHist[0] ?? 0) + (rankableHist[1] ?? 0);
  print('  ${mode.name.toUpperCase()} (n=$n)');
  print('    rankable/level     ${(totalRankable / d).toStringAsFixed(2)}   '
      'novel/level ${(totalNovel / d).toStringAsFixed(2)}   '
      'candidates/level ${(totalCand / d).toStringAsFixed(2)}');
  print('    no-choice levels   $noChoice/$n = '
      '${(100 * noChoice / d).toStringAsFixed(1)}%');
  print('    exit paths         $paths');
  print('    CUD floor rejects  $cudRejects of $iters iterations = '
      '${(100 * cudRejects / math.max(1, iters)).toStringAsFixed(1)}%');
  print('    shipped CUD        min=${_at(shippedCud, 0.0)} '
      'p10=${_at(shippedCud, 0.10)} p50=${_at(shippedCud, 0.50)} '
      'p90=${_at(shippedCud, 0.90)} max=${_at(shippedCud, 1.0)}');
  // NOT the T2.4b composition gate, and deliberately not reported as one:
  // `_visualScoresAccepted` is capped at `_kVisualScoreSampleCap` and is never
  // cleared by `resetCounters`, so it holds the first N accepted boards — an
  // early-level sample, not the corpus. It reads identically across all three
  // variants for that reason. The real gate lives in the composition
  // calibration sweep and is run separately.
  print(
      '    gen p50/p95        ${_ms(durations, 0.50)} / ${_ms(durations, 0.95)}'
      '   (budget 260 ms)');
}

String _at(List<int> v, double p) =>
    v.isEmpty ? '-' : v[((v.length - 1) * p).round()].toString();

String _ms(List<int> v, double p) => v.isEmpty
    ? '-'
    : '${(v[((v.length - 1) * p).round()] / 1000).toStringAsFixed(0)} ms';
