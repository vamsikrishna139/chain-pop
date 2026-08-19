@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase B measurement harness (NOT a gate — always passes).
///
/// Prints the opening / FSR / viable-path distribution so we can observe the
/// opening-vs-FSR relationship at the current node count and compare before vs
/// after the opening-window compression lever. The actual >=90% in-band gate
/// lives in `difficulty_quality_audit_test.dart` (skipped until Phase B lands).
///
/// Run: flutter test test/game/levels/generation/opening_compression_measurement_test.dart
void main() {
  group('Phase B opening-compression measurement', () {
    test('Hard campaign L30-59 distribution', () {
      final gen = LevelGenerator();
      const startId = 30;
      const count = 30;
      final rows = <_Row>[];
      for (var id = startId; id < startId + count; id++) {
        final r = gen.generate(id, mode: DifficultyMode.hard);
        expect(r.isSuccess, isTrue, reason: 'Hard L$id should generate');
        rows.add(_measure('L$id', r.value, DifficultyProfile.hard));
      }
      _report('HARD CAMPAIGN (L30-59)', rows);
    });

    test('Daily challenge sample distribution', () {
      const dates = [
        '2026-06-13',
        '2026-06-14',
        '2026-06-15',
        '2026-06-16',
        '2026-06-17',
        '2026-06-18',
        '2026-06-19',
        '2026-06-20',
        '2026-06-21',
        '2026-06-22',
      ];
      final rows = <_Row>[];
      for (final dateStr in dates) {
        final level = LevelManager.getDailyChallenge(DateTime.parse(dateStr));
        rows.add(_measure(dateStr, level, DifficultyProfile.expert));
      }
      _report('DAILY CHALLENGE (sample)', rows);
    });
  });
}

class _Row {
  _Row(
    this.label,
    this.nodes,
    this.opening,
    this.openingWithoutPhaseGates,
    this.fsr,
    this.waveDepth,
    this.viablePaths,
    this.pathsCapped,
    this.fill,
    this.inBand,
  );
  final String label;
  final int nodes;
  final int opening;
  final int openingWithoutPhaseGates;
  final double fsr;
  final int waveDepth;
  final int viablePaths;
  final bool pathsCapped;
  final double fill;
  final bool inBand;
}

_Row _measure(String label, LevelData level, DifficultyProfile profile) {
  final m = LevelMetrics.compute(level, includeViablePath: true);
  final fill = m.nodeCount / (level.gridWidth * level.gridHeight);
  return _Row(
    label,
    m.nodeCount,
    m.firstLegalMoveCount,
    _openingWithoutPhaseGates(level),
    m.forcedSequenceRatio,
    m.waveDepth,
    m.viablePathCount,
    m.viablePathCountCapped,
    fill,
    profile.passes(m),
  );
}

int _openingWithoutPhaseGates(LevelData level) {
  final ungated = LevelData(
    levelId: level.levelId,
    gridWidth: level.gridWidth,
    gridHeight: level.gridHeight,
    playCells: level.playCells,
    nodes: [
      for (final n in level.nodes) n.copyWith(phaseGroup: 0),
    ],
  );
  return LevelMetrics.compute(ungated).firstLegalMoveCount;
}

void _report(String title, List<_Row> rows) {
  // ignore: avoid_print
  print('\n=== $title ===');
  for (final r in rows) {
    // ignore: avoid_print
    print('  ${r.label}: nodes=${r.nodes} opening=${r.opening} '
        'ungatedOpening=${r.openingWithoutPhaseGates} '
        'FSR=${(r.fsr * 100).toStringAsFixed(0)}% waves=${r.waveDepth} '
        'paths=${r.viablePaths}${r.pathsCapped ? '(capped)' : ''} '
        'inBand=${r.inBand}');
  }
  final n = rows.length;
  final inBand = rows.where((r) => r.inBand).length;
  final openings = rows.map((r) => r.opening).toList()..sort();
  final fsrs = rows.map((r) => r.fsr).toList()..sort();
  final openOver5 = rows.where((r) => r.opening > 5).length;
  final openUnder3 = rows.where((r) => r.opening < 3).length;
  final avgOpening = rows.fold<int>(0, (a, r) => a + r.opening) / n;
  final avgUngatedOpening =
      rows.fold<int>(0, (a, r) => a + r.openingWithoutPhaseGates) / n;
  final avgPhaseGateReduction = avgUngatedOpening - avgOpening;
  final avgFsr = rows.fold<double>(0, (a, r) => a + r.fsr) / n;
  final fsrOver90 = rows.where((r) => r.fsr > 0.90).length;
  final avgFill = rows.fold<double>(0, (a, r) => a + r.fill) / n;
  // ignore: avoid_print
  print('  AGG: inBand=$inBand/$n '
      'opening[min=${openings.first} med=${openings[n ~/ 2]} max=${openings.last} '
      'avg=${avgOpening.toStringAsFixed(1)}] over5=$openOver5 under3=$openUnder3 '
      'phaseGateOpeningReduction=${avgPhaseGateReduction.toStringAsFixed(1)} '
      'FSR[min=${(fsrs.first * 100).toStringAsFixed(0)}% '
      'max=${(fsrs.last * 100).toStringAsFixed(0)}% '
      'avg=${(avgFsr * 100).toStringAsFixed(0)}%] fsrOver90=$fsrOver90 '
      'avgFill=${(avgFill * 100).toStringAsFixed(0)}%');
}
