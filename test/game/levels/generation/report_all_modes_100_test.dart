// Wide-sample board report across ALL three difficulty modes, over the same
// 100 random ids so the batches are directly comparable.
//   flutter test test/game/levels/generation/report_all_modes_100_test.dart
//
// Diagnostic only — asserts nothing. Also records which silhouette each
// emitted board used, via a recording SilhouetteSessionTracker.
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/silhouette_session_tracker.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:chain_pop/game/levels/level_directive.dart';
import 'package:chain_pop/game/world_registry.dart';
import 'package:chain_pop/screens/game/game_time_limit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'report_sample.dart';

/// Session tracker that also remembers every silhouette it was told about.
class _RecordingTracker extends SilhouetteSessionTracker {
  final List<SilhouetteId> seen = <SilhouetteId>[];

  @override
  void record(SilhouetteId silhouette) {
    seen.add(silhouette);
    super.record(silhouette);
  }
}

void _runMode({
  required String label,
  required DifficultyMode mode,
  required DifficultyProfile profile,
  required String csvPath,
}) {
  final ids = kReportSampleIds;
  print('\n===== $label — 100 random levels from L1..1500 '
      '(seed $kReportSampleSeed, budget ${kProdBudget.inMilliseconds}ms) =====');
  print('  canvas = fixed ${kCanvasSpan}x$kCanvasSpan = $kCanvasCells cells; '
      'screen = ${kBandW.toStringAsFixed(0)}x${kBandH.toStringAsFixed(0)}px '
      'playfield band on a ${kRefScreenW.toStringAsFixed(0)}x'
      '${kRefScreenH.toStringAsFixed(0)} phone\n');

  final tracker = _RecordingTracker();
  final gen = LevelGenerator(silhouetteSessionTracker: tracker);
  final failures = <int>[];
  final rows = <BoardRow>[];
  final shapes = <String, int>{};
  final sw = Stopwatch();

  for (final id in ids) {
    final before = tracker.seen.length;
    sw
      ..reset()
      ..start();
    final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
    sw.stop();
    if (!r.isSuccess) {
      failures.add(id);
      print('  L$id: GENERATION FAILED (${r.error})');
      continue;
    }
    final level = r.value;
    final shape = tracker.seen.length > before
        ? tracker.seen.last.name
        : (level.playCells == null ? 'rectangle(unrecorded)' : 'other');
    shapes[shape] = (shapes[shape] ?? 0) + 1;

    final world = worldForLevel(id);
    final row = measure(
      level,
      label: 'L$id',
      levelId: id,
      mode: mode,
      profile: profile,
      directive: directiveFor(levelId: id, mode: mode).label,
      timeLimitSec: computeGameTimeLimit(mode, level.nodes.length, id) ?? 0,
      genMs: sw.elapsedMilliseconds,
      sector: world.sector.mechanicBudgetTier,
      worldName: world.name,
    );
    rows.add(row);
    printRow(row);
  }

  printSummary('$label 100 random (L1–1500)', rows, failures);
  final shapeEntries = shapes.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  print('  silhouettes: '
      '${shapeEntries.map((e) => "${e.key}=${e.value}").join("  ")}');
  print('  generator: renegotiations=${gen.renegotiationCount} '
      'evaluatorRejections=${gen.evaluatorRejectionCount} '
      'diversityRejections=${gen.diversityRejectionCount}');
  printFitterSweep('$label 100', rows);
  writeCsv(csvPath, rows);
}

void main() {
  test('EASY — 100 random levels board report', () {
    _runMode(
      label: 'EASY',
      mode: DifficultyMode.easy,
      profile: DifficultyProfile.easy,
      csvPath: 'docs/playtests/report_easy_100.csv',
    );
  }, timeout: const Timeout(Duration(minutes: 45)));

  test('MEDIUM — 100 random levels board report', () {
    _runMode(
      label: 'MEDIUM',
      mode: DifficultyMode.medium,
      profile: DifficultyProfile.medium,
      csvPath: 'docs/playtests/report_medium_100.csv',
    );
  }, timeout: const Timeout(Duration(minutes: 45)));

  test('HARD — 100 random levels board report', () {
    _runMode(
      label: 'HARD',
      mode: DifficultyMode.hard,
      profile: DifficultyProfile.hard,
      csvPath: 'docs/playtests/report_hard_100.csv',
    );
  }, timeout: const Timeout(Duration(minutes: 45)));
}
