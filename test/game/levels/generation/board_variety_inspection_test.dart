@Tags(['report'])
library;

import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Visual + statistical inspection of generated board shapes.
///
/// Generates 100 levels (50 Hard, 25 Easy, 25 Medium) at random level IDs in
/// 1..1000, renders each board as ASCII so the silhouette is eyeballable, then
/// reports how much the *shape* actually varies and how often it repeats.
///
/// This is a print-only diagnostic (no hard asserts beyond "everything
/// generates"); run with:
///   flutter test test/game/levels/generation/board_variety_inspection_test.dart
void main() {
  test('inspect 100 random boards across modes (50% Hard)', () {
    final gen = LevelGenerator();
    final pick = Random(20260612); // fixed so the run is reproducible

    // 50 Hard + 25 Easy + 25 Medium, interleaved in generation order.
    final plan = <DifficultyMode>[
      ...List.filled(50, DifficultyMode.hard),
      ...List.filled(25, DifficultyMode.easy),
      ...List.filled(25, DifficultyMode.medium),
    ]..shuffle(pick);

    final rows = <_Row>[];
    for (final mode in plan) {
      final id = 1 + pick.nextInt(1000);
      final res = gen.generate(id, mode: mode);
      expect(res.isSuccess, isTrue, reason: 'gen failed mode=$mode id=$id');
      rows.add(_Row(mode, id, res.value));
    }

    // ── Render every board ───────────────────────────────────────────────
    final b = StringBuffer();
    b.writeln(
        '\n================ 100 BOARDS (in generation order) ================');
    b.writeln(
        'legend: ^v<> = node facing · core=O locked=L relay=R · "·"=empty cell · " "=void\n');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      b.writeln(
          '#${(i + 1).toString().padLeft(3)}  ${r.mode.name.toUpperCase().padRight(6)}'
          ' id=${r.id.toString().padLeft(4)}  ${r.level.gridWidth}x${r.level.gridHeight}'
          '  nodes=${r.level.nodes.length}  sig=${r.sig.hashCode.toRadixString(16)}');
      b.writeln(_render(r.level));
    }

    // ── Analysis ─────────────────────────────────────────────────────────
    b.writeln('\n================ ANALYSIS ================');
    for (final mode in DifficultyMode.values) {
      final group = rows.where((r) => r.mode == mode).toList();
      if (group.isEmpty) continue;
      final sigs = group.map((r) => r.sig).toList();
      final distinct = sigs.toSet().length;
      final counts = <String, int>{};
      for (final s in sigs) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
      final repeated = counts.values.where((c) => c > 1).length;
      final maxDup = counts.values.fold<int>(0, max);
      b.writeln('${mode.name.toUpperCase()}: ${group.length} boards, '
          '$distinct distinct shapes '
          '(${(distinct / group.length * 100).toStringAsFixed(0)}% unique), '
          '$repeated shapes appear >1×, most-repeated shape = $maxDup×');
    }

    // Overall back-to-back and windowed repetition across the whole 100-run.
    final allSigs = rows.map((r) => r.sig).toList();
    var backToBack = 0;
    var maxRun = 1, run = 1;
    for (var i = 1; i < allSigs.length; i++) {
      if (allSigs[i] == allSigs[i - 1]) {
        backToBack++;
        run++;
        maxRun = max(maxRun, run);
      } else {
        run = 1;
      }
    }
    b.writeln('\nOVERALL (100 boards in order):');
    b.writeln('  distinct shapes: ${allSigs.toSet().length}/100');
    b.writeln(
        '  back-to-back identical shapes: $backToBack (max consecutive run: $maxRun)');
    // Sliding window of 5: how varied does any short streak of play feel?
    var minW = 5;
    for (var i = 0; i + 5 <= allSigs.length; i++) {
      final w = allSigs.sublist(i, i + 5).toSet().length;
      minW = min(minW, w);
    }
    b.writeln('  worst 5-level window distinctness: $minW/5');

    // ignore: avoid_print
    print(b.toString());
  });
}

class _Row {
  final DifficultyMode mode;
  final int id;
  final LevelData level;
  late final String sig = _shapeSignature(level);
  _Row(this.mode, this.id, this.level);
}

/// Silhouette signature: the playable-cell set normalised to its bounding box,
/// so two boards with the same *shape* (ignoring position/size offset) match.
String _shapeSignature(LevelData lvl) {
  final cells = <Point<int>>[];
  if (lvl.playCells == null) {
    for (var y = 0; y < lvl.gridHeight; y++) {
      for (var x = 0; x < lvl.gridWidth; x++) {
        cells.add(Point(x, y));
      }
    }
  } else {
    for (final c in lvl.playCells!) {
      final p = c.split(',');
      cells.add(Point(int.parse(p[0]), int.parse(p[1])));
    }
  }
  final minX = cells.map((p) => p.x).reduce(min);
  final minY = cells.map((p) => p.y).reduce(min);
  final norm = cells.map((p) => '${p.x - minX},${p.y - minY}').toList()..sort();
  return norm.join(';');
}

String _render(LevelData lvl) {
  final play = lvl.playCells;
  bool playable(int x, int y) => play == null || play.contains('$x,$y');
  final byCell = <String, NodeData>{
    for (final n in lvl.nodes) '${n.x},${n.y}': n
  };

  final sb = StringBuffer();
  for (var y = 0; y < lvl.gridHeight; y++) {
    sb.write('    ');
    for (var x = 0; x < lvl.gridWidth; x++) {
      if (!playable(x, y)) {
        sb.write(' ');
        continue;
      }
      final n = byCell['$x,$y'];
      if (n == null) {
        sb.write('·');
        continue;
      }
      if (n.isCore) {
        sb.write('O');
      } else if (n.kind == NodeKind.locked) {
        sb.write('L');
      } else if (n.kind == NodeKind.relay) {
        sb.write('R');
      } else {
        sb.write(switch (n.dir) {
          Direction.up => '^',
          Direction.down => 'v',
          Direction.left => '<',
          Direction.right => '>',
        });
      }
    }
    sb.writeln();
  }
  return sb.toString().trimRight();
}
