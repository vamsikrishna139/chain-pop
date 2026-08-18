// **Experiment B** — grid-aspect sweep. Go/no-go gate for P5.
//
// Regenerates the *same* 100 campaign ids under forced grid dimensions, so the
// only variable is board aspect. The plan predicts that taller grids lengthen
// vertical rays, block more nodes at the start, and therefore **narrow** the
// opening — the key uncertainty behind the whole portrait-composition idea.
//
// Diagnostic only; asserts nothing about quality. Run it directly:
//   flutter test test/game/levels/generation/experiment_b_grid_aspect_test.dart
// ignore_for_file: avoid_print

import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'report_sample.dart';

/// Grid shapes under test. Width stays ≤ 8; 7 is the tap-compliant maximum on
/// a 390 pt phone, and 8×8 is today's dominant shape (the control).
const List<(int, int)> kAspects = [
  (8, 8), // control — what ships
  (7, 7),
  (7, 9),
  (7, 10),
  (7, 11),
];

class _Agg {
  final List<double> opening = [];
  final List<double> fsr = [];
  final List<double> cud = [];
  final List<double> waves = [];
  final List<double> bf = [];
  final List<double> nodes = [];
  final List<double> genMs = [];
  final List<double> cover = [];
  final List<double> cell = [];
  final List<double> gridOcc = [];
  int inBand = 0;
  int openingInBand = 0;
  int failures = 0;
  int total = 0;
}

double _q(List<double> v, double f) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  return s[((s.length - 1) * f).round()];
}

String _c(double v, [int d = 1]) => v.toStringAsFixed(d).padLeft(8);

void main() {
  test('EXPERIMENT B — forced grid aspect over the same 100 ids', () {
    final ids = kReportSampleIds;
    print('\n===== EXPERIMENT B — grid-aspect sweep '
        '(${ids.length} ids, budget ${kProdBudget.inMilliseconds}ms, '
        'Hard band) =====');
    print('  Milestone seeds are disabled so every id takes the Director path '
        'and the forced grid is the only variable.\n');

    final results = <String, _Agg>{};

    for (final (gw, gh) in kAspects) {
      final label = '${gw}x$gh';
      final agg = _Agg();
      final gen = LevelGenerator();
      final sw = Stopwatch();

      for (final id in ids) {
        final base = LevelConfiguration.fromLevelId(
          id,
          mode: DifficultyMode.hard,
        );
        final config = LevelConfiguration(
          levelId: base.levelId,
          gridWidth: gw,
          gridHeight: gh,
          targetNodeCount: base.targetNodeCount,
          difficulty: base.difficulty,
          archetype: base.archetype,
          directionBias: base.directionBias,
          irregularMaskProbability: base.irregularMaskProbability,
          irregularLayoutExtraTries: base.irregularLayoutExtraTries,
          minimumTargetNodeCount: base.minimumTargetNodeCount,
        );
        if (!config.validate().isValid) {
          agg.failures++;
          agg.total++;
          continue;
        }

        sw
          ..reset()
          ..start();
        final r = gen.generateFromConfiguration(
          config,
          primarySeed: id,
          applyMilestones: false,
          targetTier: DifficultyTier.hard,
          timeBudget: kProdBudget,
        );
        sw.stop();
        agg.total++;
        if (!r.isSuccess) {
          agg.failures++;
          continue;
        }

        final level = r.value;
        final m = LevelMetrics.compute(level);
        agg.opening.add(m.firstLegalMoveCount.toDouble());
        agg.fsr.add(m.forcedSequenceRatio * 100);
        agg.cud.add(m.criticalUnlockDepth.toDouble());
        agg.waves.add(m.waveDepth.toDouble());
        agg.bf.add(m.averageBranchingFactor);
        agg.nodes.add(m.nodeCount.toDouble());
        agg.genMs.add(sw.elapsedMilliseconds.toDouble());
        if (DifficultyProfile.hard.passes(m)) agg.inBand++;
        if (DifficultyProfile.hardExpertOpeningBand
            .contains(m.firstLegalMoveCount)) {
          agg.openingInBand++;
        }

        // Layout consequences on the reference device.
        var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
        for (final n in level.nodes) {
          minX = min(minX, n.x);
          maxX = max(maxX, n.x);
          minY = min(minY, n.y);
          maxY = max(maxY, n.y);
        }
        final bw = min(gw, maxX - minX + 3);
        final bh = min(gh, maxY - minY + 3);
        final cell = fitCellPx(
          device: ReferenceDevice.iphone390,
          variant: FitterVariant.perAxis,
          bboxWidth: bw,
          bboxHeight: bh,
          gridWidth: gw,
          gridHeight: gh,
        );
        agg.cell.add(cell);
        agg.cover.add(100 *
            (gw * gh * cell * cell) /
            ReferenceDevice.iphone390.bandArea);
        agg.gridOcc.add(100 * m.nodeCount / (gw * gh));
      }
      results[label] = agg;
      print('  $label done (${agg.total - agg.failures} ok, '
          '${agg.failures} failed)');
    }

    print('\n  ${"grid".padRight(8)}${"nodes".padLeft(8)}${"open p50".padLeft(9)}'
        '${"open max".padLeft(9)}${"openOK".padLeft(8)}${"FSR p50".padLeft(9)}'
        '${"CUD p50".padLeft(9)}${"waves".padLeft(8)}${"BF p50".padLeft(8)}'
        '${"inBand".padLeft(8)}${"gen p95".padLeft(9)}'
        '${"cell".padLeft(8)}${"cover".padLeft(8)}${"gridOcc".padLeft(9)}'
        '${"fail".padLeft(6)}');
    for (final (gw, gh) in kAspects) {
      final label = '${gw}x$gh';
      final a = results[label]!;
      final n = a.total - a.failures;
      print('  ${label.padRight(8)}'
          '${_c(_q(a.nodes, 0.5), 0)}'
          '${_c(_q(a.opening, 0.5), 0).padLeft(9)}'
          '${_c(_q(a.opening, 1.0), 0).padLeft(9)}'
          '${"${a.openingInBand}/$n".padLeft(8)}'
          '${_c(_q(a.fsr, 0.5), 0).padLeft(9)}'
          '${_c(_q(a.cud, 0.5), 0).padLeft(9)}'
          '${_c(_q(a.waves, 0.5), 0)}'
          '${_c(_q(a.bf, 0.5))}'
          '${"${a.inBand}/$n".padLeft(8)}'
          '${_c(_q(a.genMs, 0.95), 0).padLeft(9)}'
          '${_c(_q(a.cell, 0.5))}'
          '${_c(_q(a.cover, 0.5), 0)}'
          '${_c(_q(a.gridOcc, 0.5), 0).padLeft(9)}'
          '${a.failures.toString().padLeft(6)}');
    }
    print('\n  openOK = openings inside the honest [3,11] band.');
    print('  cover/cell measured on 390x844 under the shipped per-axis fitter.');
    print('');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
