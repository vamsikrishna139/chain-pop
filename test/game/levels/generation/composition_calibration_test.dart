// T2.4b — composition-score calibration.
//
// Analysis only. Asserts NOTHING (plan §0.5: gates never live in a report
// harness). Its job is to answer one question with data:
//
//   what score does a board the CURRENT validator already accepts earn?
//
// Only against that baseline is a p10 floor meaningful. T2.4a made the score
// observable; this establishes the distribution; T2.4c is the first stage
// allowed to act on it.
//
//   flutter test test/game/levels/generation/composition_calibration_test.dart
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'dart:io';
import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/visual_composition.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

/// 300 levels per mode, as §T2.4b requires ("300+ levels/mode").
const int kCalibrationSampleSize = 300;

/// Disjoint from `kReportSampleSeed` so the calibration population is not the
/// same 100 ids the T0.3 canary already reports on.
const int kCalibrationSeed = 20260821;

List<int> _calibrationIds() {
  final rng = Random(kCalibrationSeed);
  final ids = <int>{};
  while (ids.length < kCalibrationSampleSize) {
    ids.add(1 + rng.nextInt(1500));
  }
  return ids.toList()..sort();
}

List<double> _percentiles(List<double> xs) {
  final s = [...xs]..sort();
  double p(double q) => s.isEmpty ? 0 : s[(q * (s.length - 1)).round()];
  return [p(0.0), p(0.10), p(0.25), p(0.50), p(0.75), p(0.90), p(1.0)];
}

String _fmtRow(String label, int n, List<double> p) =>
    '  ${label.padRight(30)} n=${n.toString().padLeft(6)}  '
    'min=${p[0].toStringAsFixed(4)}  p10=${p[1].toStringAsFixed(4)}  '
    'p25=${p[2].toStringAsFixed(4)}  p50=${p[3].toStringAsFixed(4)}  '
    'p75=${p[4].toStringAsFixed(4)}  p90=${p[5].toStringAsFixed(4)}  '
    'max=${p[6].toStringAsFixed(4)}';

void main() {
  test('T2.4b — composition score calibration', () {
    final ids = _calibrationIds();
    final buf = StringBuffer();
    void emit(String line) {
      print(line);
      buf.writeln(line);
    }

    emit('# T2.4b — Composition score calibration');
    emit('');
    emit('- sample: $kCalibrationSampleSize ids per mode, seed '
        '$kCalibrationSeed, drawn from L1..1500');
    emit('- budget: ${kProdBudget.inMilliseconds}ms (production path)');
    emit('- score: unweighted mean of the five 0..1 rule sub-scores (T2.4a)');
    emit('- Easy is excluded: `evaluateVisualComposition` short-circuits for '
        'the easy tier, so it has no composition measurement at all.');
    emit('');

    for (final mode in [DifficultyMode.medium, DifficultyMode.hard]) {
      // One generator for the whole sweep, deliberately: a warm diversity
      // ledger is what production actually runs, and the rejected population
      // only exists on the generator instance.
      final gen = LevelGenerator();
      final tier = DifficultyProfile.tierFromMode(mode);

      final shipped = <double>[];
      final shippedDetail = <String, List<double>>{
        'aspect': [],
        'blobVsGrid': [],
        'occupancy': [],
        'singleton': [],
        'components': [],
      };
      var failures = 0;

      for (final id in ids) {
        final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
        if (!r.isSuccess) {
          failures++;
          continue;
        }
        final v = evaluateVisualComposition(r.value, tier);
        if (!v.evaluated) continue;
        shipped.add(v.score);
        shippedDetail['aspect']!.add(v.detail.aspect);
        shippedDetail['blobVsGrid']!.add(v.detail.blobVsGrid);
        shippedDetail['occupancy']!.add(v.detail.occupancy);
        shippedDetail['singleton']!.add(v.detail.singleton);
        shippedDetail['components']!.add(v.detail.components);
      }

      final accepted = gen.visualScoresAccepted;
      final rejected = gen.visualScoresRejected;
      final snap = gen.snapshotSession();

      emit('## ${mode.name.toUpperCase()}');
      emit('');
      emit('```');
      emit(_fmtRow(
          'SHIPPED (known-good)', shipped.length, _percentiles(shipped)));
      emit(_fmtRow('candidates ACCEPTED by rules', accepted.length,
          _percentiles(accepted)));
      emit(_fmtRow('candidates REJECTED by rules', rejected.length,
          _percentiles(rejected)));
      emit('');
      for (final e in shippedDetail.entries) {
        emit(_fmtRow(
            '  shipped.${e.key}', e.value.length, _percentiles(e.value)));
      }
      emit('');
      emit('  reject reasons: '
          'components=${snap.rejectComponentsCount} '
          'singleton=${snap.rejectSingletonCount} '
          'occupancy=${snap.rejectOccupancyCount} '
          'blobVsGrid=${snap.rejectBlobVsGridCount} '
          'aspect=${snap.rejectAspectCount}');
      emit('  generation failures: $failures');
      emit('```');
      emit('');

      // Separation: how well would a p10 floor discriminate?
      if (rejected.isNotEmpty && shipped.isNotEmpty) {
        final shipP = _percentiles(shipped);
        final floor = shipP[1]; // p10 of the known-good population
        final rejBelow = rejected.where((s) => s < floor).length;
        final accBelow = accepted.where((s) => s < floor).length;
        emit('  A floor at SHIPPED p10 = ${floor.toStringAsFixed(4)} would sit '
            'below ${(100 * rejBelow / rejected.length).toStringAsFixed(1)}% '
            'of currently-rejected candidates and '
            '${(100 * accBelow / max(1, accepted.length)).toStringAsFixed(1)}% '
            'of currently-accepted ones.');
        emit('');
      }
    }

    final out = File('docs/playtests/composition_calibration.md');
    out.writeAsStringSync(buf.toString());
    print('\nWROTE ${out.path}');
  }, timeout: const Timeout(Duration(minutes: 45)));
}
