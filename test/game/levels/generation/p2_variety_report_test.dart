// P2 — the variety instrument the P2 definition of done is scored against.
//
//   flutter test --tags report \
//     test/game/levels/generation/p2_variety_report_test.dart
//
// Every F4 number in the P2 DoD in one place, measured the same way before and
// after the T2.1+T2.2+T2.3+T2.4c bundle:
//
//   * distinct `topologyClass` per mode (target Hard >= 30, from 23)
//   * geometric-lattice share on Hard          (target < 50%, from 68%)
//   * longest same-silhouette run              (target <= 3, from 6)
//   * worst 5-level window: distinct families  (target >= 2)
//   * rolling min-Hamming median               (target >= 5, from 3.00)
//   * shipped mask -> rectangle fallback rate  (target < 0.5%, from 8%)
//   * Hard L45-56 full-rect boards             (the visible symptom; target 0)
//   * Hard generation p95                      (must not get worse)
//
// **Asserts nothing**, by construction (plan §0.5): this is the evidence layer.
// The pre-bundle reading is archived in docs/playtests/p2_variety_pre_bundle.md
// so the after-run is a controlled comparison on the same machine, not a
// comparison against a number someone published on a different tree.
//
// Two populations, deliberately:
//   * the **sequential campaign run** (L1..N in order, one generator) is the
//     only way to see streaks, windows and the rolling Hamming median at all —
//     they are properties of the emission *sequence*, and the diversity ledger
//     only carries state along it.
//   * the **300-id/mode sample** is the calibrated topology-class population
//     (`docs/playtests/topology_class_calibration.md`, seed 7), reused verbatim
//     so the 23/25/40 baseline stays comparable.
//
// ignore_for_file: avoid_print

@Tags(['corpus', 'report'])
library;

import 'dart:math' as math;

import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/director.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'corpus_benchmark_utils.dart';

/// Levels in the sequential campaign run. 500 is the size F4's original
/// benchmark used, and streak / window measures need the sequence to be long
/// enough that a 6-run is not a small-sample artefact.
const int kSequentialLevels = 500;

/// The topology-class sample, pinned to T0.2's calibration draw.
const int kTopologySampleSize = 300;
const int kTopologySampleSeed = 7;

void main() {
  test('P2 variety report', () {
    printCorpusVersionBanner('P2 VARIETY REPORT');
    print('topologyDefinitionVersion: $kTopologyDefinitionVersion');
    print('sequential run: Hard L0..${kSequentialLevels - 1}, prod budget');
    print('topology sample: $kTopologySampleSize ids/mode, '
        'seed $kTopologySampleSeed, ids 1..1500, prod budget');
    print('');

    _sequentialHardReport();
    print('');
    _topologyClassReport();
    print('');
    _fullRectSymptomReport();
  }, timeout: const Timeout(Duration(minutes: 30)));
}

// ═══════════════════════════════════════════════════════════════════════════
// Sequence-dependent measures: lattice share, streaks, windows, Hamming,
// fallback rate, latency.
// ═══════════════════════════════════════════════════════════════════════════

void _sequentialHardReport() {
  final sink = InMemoryAnalyticsSink();
  // Every rectangle substitution the Director makes, whether or not the board
  // that used it is the one that ships. The DoD's "shipped mask fallback" is
  // the narrower number below (`playCells == null` on an emitted board); this
  // one is the attempt-level pressure behind it.
  final fallbackAttempts = <SilhouetteId>[];
  final gen = LevelGenerator(
    analyticsSink: sink,
    director: Director(
      onMaskRectangleFallback: (attempted, _) =>
          fallbackAttempts.add(attempted),
    ),
  );

  final genMs = <int>[];
  // Two different things, conflated in the first draft of this file and worth
  // keeping apart: `playCells == null` means the Director *chose* the
  // rectangle silhouette (legitimate variety), whereas a non-null mask that
  // covers the whole grid is a silhouette that was asked for and could not be
  // built — the actual fallback the DoD's "8% -> < 0.5%" is about.
  var shippedRectSilhouette = 0;
  var shippedRectFallback = 0;
  final sw = Stopwatch();
  for (var id = 0; id < kSequentialLevels; id++) {
    sw
      ..reset()
      ..start();
    final r =
        gen.generate(id, mode: DifficultyMode.hard, timeBudget: kProdBudget);
    sw.stop();
    if (!r.isSuccess) {
      print('  L$id: GENERATION FAILED (${r.error})');
      continue;
    }
    genMs.add(sw.elapsedMilliseconds);
    final cells = r.value.playCells;
    final area = r.value.gridWidth * r.value.gridHeight;
    if (cells == null || cells.isEmpty) {
      shippedRectSilhouette++;
    } else if (cells.length == area) {
      shippedRectFallback++;
    }
  }

  final events = sink.events;
  print('--- sequential Hard, n=${events.length} ---');

  final macros = silhouetteMacroHistogram(events);
  final total = math.max(1, events.length);
  final lattice = macros[SilhouetteVisualFamily.geometricLattice] ?? 0;
  print('lattice share: ${_pct(lattice / total)} '
      '(DoD < 50%, from 68%)');
  for (final f in SilhouetteVisualFamily.values) {
    print('  ${f.name.padRight(17)} ${(macros[f] ?? 0).toString().padLeft(4)}  '
        '${_pct((macros[f] ?? 0) / total)}');
  }
  print('silhouette ids: ${_tally(silhouetteIdHistogram(events))}');

  final silStreak =
      streakDistribution(events.map((e) => e.silhouette).toList());
  final macroStreak = streakDistribution(macroSequence(events));
  print('longest same-silhouette run: ${silStreak['max']} '
      '(DoD <= 3, from 6)  hist=${silStreak['histogram']}');
  print('longest same-family run:     ${macroStreak['max']}  '
      'hist=${macroStreak['histogram']}');

  final w5 =
      macroBucketWindowStats(macroSequence: macroSequence(events), window: 5);
  print('worst 5-level window families: ${w5.minDistinct} '
      '(DoD >= 2)  avg=${w5.avgDistinct.toStringAsFixed(2)} '
      'pureLattice=${w5.latticeOnlyWindows}');
  for (final w in const [10, 20]) {
    final s =
        macroBucketWindowStats(macroSequence: macroSequence(events), window: w);
    print('  W=$w min=${s.minDistinct} max=${s.maxDistinct} '
        'avg=${s.avgDistinct.toStringAsFixed(2)} '
        'pureLattice=${s.latticeOnlyWindows}');
  }

  final bits = events.map((e) => e.fingerprint.bits).toList(growable: false);
  final hamm = rollingMinHammingDistances(fingerprintBits: bits);
  final hammSorted = [...hamm.minDistances]..sort();
  print('rolling min-Hamming median: ${hamm.median.toStringAsFixed(2)} '
      '(DoD >= 5, from 3.00)  p90=${hamm.p90.toStringAsFixed(2)} '
      'min=${hammSorted.isEmpty ? 0 : hammSorted.first}');

  final n = math.max(1, genMs.length);
  print('shipped mask FALLBACK (asked for a shape, got the grid): '
      '$shippedRectFallback/${genMs.length} = '
      '${_pct(shippedRectFallback / n)}  (DoD < 0.5%, from 8%)');
  print('shipped rectangle SILHOUETTE (chosen, not a failure): '
      '$shippedRectSilhouette/${genMs.length} = '
      '${_pct(shippedRectSilhouette / n)}');
  print('director rectangle substitutions (attempt-level): '
      '${fallbackAttempts.length}  ${_tally(_countBy(fallbackAttempts))}');

  genMs.sort();
  print('gen latency ms: p50=${_pctlInt(genMs, 0.50)} '
      'p75=${_pctlInt(genMs, 0.75)} p95=${_pctlInt(genMs, 0.95)} '
      'p100=${genMs.isEmpty ? 0 : genMs.last}  (DoD p95 <= 260)');
}

// ═══════════════════════════════════════════════════════════════════════════
// Topology classes, on T0.2's calibrated sample.
// ═══════════════════════════════════════════════════════════════════════════

void _topologyClassReport() {
  print('--- topology classes ($kTopologySampleSize ids/mode) ---');
  final ids = sampleLevelIds(
    count: kTopologySampleSize,
    minId: 1,
    maxId: 1500,
    seed: kTopologySampleSeed,
  );
  for (final mode in DifficultyMode.values) {
    final classes = <String, int>{};
    var fullRect = 0;
    var n = 0;
    final scores = <double>[];
    // T2.4c control: which soft rule, if any, the SHIPPED board violates.
    // Before T2.4c every one of these would have been a rejection, so this is
    // the exact population the p10 floor is protecting.
    final shippedViolations = <String, int>{};
    final perRule = <String, List<double>>{};
    final gen = LevelGenerator();
    for (final id in ids) {
      final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
      if (!r.isSuccess) continue;
      n++;
      final level = r.value;
      final row = measure(
        level,
        label: 'L$id',
        levelId: id,
        mode: mode,
        profile:
            DifficultyProfile.forTier(DifficultyProfile.tierFromMode(mode)),
        directive: '',
        timeLimitSec: 0,
        genMs: 0,
        sector: 0,
        worldName: '',
      );
      classes[row.topologyClass] = (classes[row.topologyClass] ?? 0) + 1;
      if (row.visual.evaluated) {
        scores.add(row.visual.score);
        final why = row.visual.reason?.name ?? 'clean';
        shippedViolations[why] = (shippedViolations[why] ?? 0) + 1;
        final d = row.visual.detail;
        (perRule['aspect'] ??= []).add(d.aspect);
        (perRule['blobVsGrid'] ??= []).add(d.blobVsGrid);
        (perRule['occupancy'] ??= []).add(d.occupancy);
        (perRule['singleton'] ??= []).add(d.singleton);
        (perRule['components'] ??= []).add(d.components);
      }
      final cells = level.playCells;
      final area = level.gridWidth * level.gridHeight;
      if (cells == null || cells.isEmpty || cells.length == area) fullRect++;
    }
    scores.sort();
    print('${mode.name.padRight(7)} n=$n  distinct topologyClass='
        '${classes.length}  fullRect=${_pct(fullRect / math.max(1, n))}  '
        'shipped composition p10='
        '${scores.isEmpty ? 'n/a' : _pctl(scores, 0.10).toStringAsFixed(4)}');
    final top = classes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('  top classes: '
        '${top.take(6).map((e) => '${e.key}x${e.value}').join(' ')}');
    if (shippedViolations.isNotEmpty) {
      final v = shippedViolations.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      print('  shipped rule violations: '
          '${v.map((e) => '${e.key}=${e.value}').join(' ')}');
      final terms = perRule.entries.map((e) {
        final xs = [...e.value]..sort();
        return '${e.key} p10=${_pctl(xs, 0.10).toStringAsFixed(2)} '
            'p50=${_pctl(xs, 0.50).toStringAsFixed(2)}';
      }).join('  ');
      print('  per-term: $terms');
    }
  }
  print('(Gen V1 calibrated baseline: Easy 40 / Medium 25 / Hard 23; '
      'DoD Hard >= 30)');
  print('(composition p10 here is the 100-id-style read; the T2.4b GATE is the '
      '300-id seed-20260821 sample in composition_calibration_test)');
}

// ═══════════════════════════════════════════════════════════════════════════
// The visible symptom: Hard L45-56 shipping five full-rect boards.
// ═══════════════════════════════════════════════════════════════════════════

void _fullRectSymptomReport() {
  print('--- Hard L45-56 (the visible symptom) ---');
  final gen = LevelGenerator();
  var fullRect = 0;
  final line = StringBuffer();
  for (var id = 45; id <= 56; id++) {
    final r =
        gen.generate(id, mode: DifficultyMode.hard, timeBudget: kProdBudget);
    if (!r.isSuccess) {
      line.write('L$id=FAIL ');
      continue;
    }
    final cells = r.value.playCells;
    final area = r.value.gridWidth * r.value.gridHeight;
    final isRect = cells == null || cells.isEmpty || cells.length == area;
    if (isRect) fullRect++;
    line.write('L$id=${isRect ? 'RECT' : '${cells.length}c'} ');
  }
  print(line.toString().trim());
  print('full-rect boards in L45-56: $fullRect  (DoD: not five; was 5)');
}

// ═══════════════════════════════════════════════════════════════════════════

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

double _pctl(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  final i = ((sorted.length - 1) * p).round();
  return sorted[i];
}

int _pctlInt(List<int> sorted, double p) {
  if (sorted.isEmpty) return 0;
  return sorted[((sorted.length - 1) * p).round()];
}

Map<T, int> _countBy<T>(Iterable<T> xs) {
  final m = <T, int>{};
  for (final x in xs) {
    m[x] = (m[x] ?? 0) + 1;
  }
  return m;
}

String _tally<T>(Map<T, int> m) {
  final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return e
      .map((x) => '${x.key.toString().split('.').last}=${x.value}')
      .join(' ');
}
