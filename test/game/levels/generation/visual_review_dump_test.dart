// ignore_for_file: avoid_print
@Tags(['report'])
library;
import 'dart:convert';
import 'dart:io';
import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

void main() {
  test('dump the visual review set', () {
    final out = <Map<String, dynamic>>[];
    for (final e in [
      (DifficultyMode.hard, 30, 80),
      (DifficultyMode.medium, 30, 80),
    ]) {
      final mode = e.$1;
      final sink = InMemoryAnalyticsSink();
      final gen = LevelGenerator(analyticsSink: sink);
      for (var id = 1; id <= e.$3; id++) {
        // T2.17: the shipped app bounds generation, so the human visual gate
        // must review bounded boards. On this window the emitted set happens
        // to be identical either way (generation finishes inside 200ms for
        // most ids), but relying on that is relying on a coincidence.
        final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
        if (!r.isSuccess || id < e.$2) continue;
        final l = r.value;
        final ev = sink.events.last;
        final m = LevelMetrics.compute(l);
        out.add({
          'mode': mode.name,
          'id': id,
          'w': l.gridWidth,
          'h': l.gridHeight,
          'silhouette': ev.silhouette.name,
          'family': silhouetteVisualFamily(ev.silhouette).name,
          'archetype': ev.archetype.name,
          'inBand': ev.inBand,
          'novel': ev.novelFingerprint,
          'nodes': l.nodes.length,
          'cores': l.nodes.where((n) => n.isCore).length,
          'locks': l.nodes.where((n) => n.kind == NodeKind.locked).length,
          'relays': l.nodes.where((n) => n.kind == NodeKind.relay).length,
          'waves': m.waveDepth,
          'opening': m.firstLegalMoveCount,
          'cud': m.criticalUnlockDepth,
          'playCells': l.playCells?.toList(),
          'nodesData': [
            for (final n in l.nodes)
              {
                'x': n.x, 'y': n.y, 'd': n.dir.name,
                'k': n.kind.name, 'c': n.isCore ? 1 : 0,
              }
          ],
        });
      }
    }
    final f = File(Platform.environment['REVIEW_DUMP_PATH'] ??
        'build/review_boards.json');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(out));
    print('wrote ${out.length} boards to ${f.path}');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
