// **Experiment C** — FSR vs node count, to derive an honest cap curve.
// **Experiment D** — pre- vs post-enrichment metric drift.
//
// Both are diagnostics; neither asserts a quality band. Run directly:
//   flutter test test/game/levels/generation/experiment_cd_test.dart
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'report_sample.dart';

double _q(List<double> v, double f) {
  if (v.isEmpty) return 0;
  final s = List<double>.from(v)..sort();
  return s[((s.length - 1) * f).round()];
}

String _p(double v, [int d = 1]) => v.toStringAsFixed(d).padLeft(8);

LevelConfiguration _forced(int id, int gw, int gh) {
  final base = LevelConfiguration.fromLevelId(id, mode: DifficultyMode.hard);
  return LevelConfiguration(
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
}

/// Strips everything `enrichLevel` adds, recovering the board exactly as the
/// Phase-2 evaluator saw it. Enrichment is the **only** source of
/// `NodeKind.locked` / `NodeKind.relay` / `phaseGroup` (the retrograde
/// constructor never sets them) and it only ever `copyWith`s those fields, so
/// positions, directions and ids are untouched.
LevelData _deEnrich(LevelData level) => LevelData(
      levelId: level.levelId,
      gridWidth: level.gridWidth,
      gridHeight: level.gridHeight,
      playCells: level.playCells,
      nodes: [
        for (final n in level.nodes)
          n.copyWith(kind: NodeKind.normal, phaseGroup: 0),
      ],
      portalPairs: level.portalPairs,
    );

void main() {
  test('EXPERIMENT C — FSR vs node count', () {
    // The Hard node target is `mask.length × (0.32..0.44)` clamped to
    // `[25, min(42, mask)]`, so **grid area is the only lever a test has** to
    // move node count: the count is pinned at the clamp floor on today's 8×8
    // boards and rises with area until it hits the profile max of 42.
    //
    // Confound, stated up front: a larger grid also lengthens rays. This
    // measures FSR-at-node-count as the generator can actually reach it, not
    // FSR-at-node-count with geometry held constant — the latter is not
    // reachable without an app-side node-count lever, which is itself P7.
    const grids = [(8, 8), (9, 9), (10, 10), (11, 11), (12, 12)];
    final ids = kReportSampleIds.take(40).toList();

    print('\n===== EXPERIMENT C — FSR vs node count '
        '(${ids.length} ids per grid, Hard band, '
        '${kProdBudget.inMilliseconds}ms) =====');

    final byNodeCount = <int, List<double>>{};

    print('\n  ${"grid".padRight(8)}${"n".padLeft(5)}${"nodes p50".padLeft(10)}'
        '${"nodes max".padLeft(10)}${"FSR p50".padLeft(9)}'
        '${"FSR p75".padLeft(9)}${"FSR max".padLeft(9)}'
        '${"cap@p50".padLeft(9)}${"overCap".padLeft(9)}');
    for (final (gw, gh) in grids) {
      final gen = LevelGenerator();
      final nodes = <double>[];
      final fsr = <double>[];
      var overCap = 0;
      for (final id in ids) {
        final config = _forced(id, gw, gh);
        if (!config.validate().isValid) continue;
        final r = gen.generateFromConfiguration(
          config,
          primarySeed: id,
          applyMilestones: false,
          targetTier: DifficultyTier.hard,
          timeBudget: kProdBudget,
        );
        if (!r.isSuccess) continue;
        final m = LevelMetrics.compute(r.value);
        nodes.add(m.nodeCount.toDouble());
        fsr.add(m.forcedSequenceRatio);
        byNodeCount
            .putIfAbsent(m.nodeCount, () => <double>[])
            .add(m.forcedSequenceRatio);
        if (m.forcedSequenceRatio >
            DifficultyProfile.fsrCapForNodeCount(m.nodeCount)) {
          overCap++;
        }
      }
      final medNodes = _q(nodes, 0.5).round();
      print('  ${"${gw}x$gh".padRight(8)}${nodes.length.toString().padLeft(5)}'
          '${_p(_q(nodes, 0.5), 0).padLeft(10)}'
          '${_p(_q(nodes, 1.0), 0).padLeft(10)}'
          '${_p(_q(fsr, 0.5) * 100, 0).padLeft(9)}'
          '${_p(_q(fsr, 0.75) * 100, 0).padLeft(9)}'
          '${_p(_q(fsr, 1.0) * 100, 0).padLeft(9)}'
          '${_p(DifficultyProfile.fsrCapForNodeCount(medNodes) * 100, 0).padLeft(9)}'
          '${"$overCap/${nodes.length}".padLeft(9)}');
    }

    print('\n  --- measured FSR by node count vs the shipped cap curve ---');
    print('  ${"nodes".padRight(7)}${"n".padLeft(5)}${"FSR p50".padLeft(9)}'
        '${"FSR p75".padLeft(9)}${"FSR p95".padLeft(9)}'
        '${"shipped cap".padLeft(12)}${"verdict".padLeft(12)}');
    final counts = byNodeCount.keys.toList()..sort();
    for (final c in counts) {
      final v = byNodeCount[c]!;
      if (v.length < 3) continue;
      final cap = DifficultyProfile.fsrCapForNodeCount(c);
      final p75 = _q(v, 0.75);
      final verdict = cap >= 1.0
          ? 'uncapped'
          : p75 <= cap
              ? 'ok'
              : 'CAP BITES';
      print('  ${c.toString().padRight(7)}${v.length.toString().padLeft(5)}'
          '${_p(_q(v, 0.5) * 100, 0).padLeft(9)}'
          '${_p(p75 * 100, 0).padLeft(9)}'
          '${_p(_q(v, 0.95) * 100, 0).padLeft(9)}'
          '${_p(cap * 100, 0).padLeft(12)}'
          '${verdict.padLeft(12)}');
    }
    print('\n  An honest cap must sit at or above the p75 of the measured FSR '
        'at each node count, or it rejects the generator\'s own output.\n');
  }, timeout: const Timeout(Duration(minutes: 60)));

  test('EXPERIMENT D — pre- vs post-enrichment metric drift', () {
    // The bands are enforced on the **pre-enrichment** board; enrichment then
    // adds locks and phase gates, and the solver honours both. Locks and phase
    // gates only ever *add* constraints, so the predicted sign is: opening
    // narrows, FSR rises, waves deepen. This measures the size.
    final ids = kReportSampleIds;
    print('\n===== EXPERIMENT D — enrichment drift (${ids.length} Hard ids) '
        '=====');

    final gen = LevelGenerator();
    final dOpening = <double>[];
    final dFsr = <double>[];
    final dWaves = <double>[];
    final dCud = <double>[];
    final dBf = <double>[];
    var stillInBand = 0;
    var wasInBand = 0;
    var n = 0;

    for (final id in ids) {
      final r =
          gen.generate(id, mode: DifficultyMode.hard, timeBudget: kProdBudget);
      if (!r.isSuccess) continue;
      final shipped = r.value;
      final post = LevelMetrics.compute(shipped);
      final pre = LevelMetrics.compute(_deEnrich(shipped));
      n++;
      dOpening
          .add((post.firstLegalMoveCount - pre.firstLegalMoveCount).toDouble());
      dFsr.add((post.forcedSequenceRatio - pre.forcedSequenceRatio) * 100);
      dWaves.add((post.waveDepth - pre.waveDepth).toDouble());
      dCud.add((post.criticalUnlockDepth - pre.criticalUnlockDepth).toDouble());
      dBf.add(post.averageBranchingFactor - pre.averageBranchingFactor);
      if (DifficultyProfile.hard.passes(pre)) wasInBand++;
      if (DifficultyProfile.hard.passes(post)) stillInBand++;
    }

    print('\n  n=$n   (post − pre; negative = enrichment tightened it)');
    print('  ${"metric".padRight(10)}${"min".padLeft(8)}${"p25".padLeft(8)}'
        '${"p50".padLeft(8)}${"p75".padLeft(8)}${"max".padLeft(8)}'
        '${"mean".padLeft(8)}');
    void row(String name, List<double> v) {
      final mean = v.isEmpty ? 0.0 : v.reduce((a, b) => a + b) / v.length;
      print('  ${name.padRight(10)}${_p(_q(v, 0))}${_p(_q(v, 0.25))}'
          '${_p(_q(v, 0.5))}${_p(_q(v, 0.75))}${_p(_q(v, 1.0))}'
          '${_p(mean, 2)}');
    }

    row('opening', dOpening);
    row('FSR pts', dFsr);
    row('waves', dWaves);
    row('CUD', dCud);
    row('BF', dBf);

    print('\n  in-band on the board the evaluator judged (pre): '
        '$wasInBand/$n');
    print('  in-band on the board the player receives (post):  '
        '$stillInBand/$n');
    print('  drift cost: ${wasInBand - stillInBand} boards judged in-band '
        'that ship out-of-band.\n');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
