// The pentagon mask used dart:ui's Path, which throws on a worker isolate
// ("UI actions are only available on root isolate"). Gen V2 boards are built
// on a worker isolate, so every level that drew a pentagon silently fell back
// to generating on the UI thread. These tests pin the pure-Dart replacement
// to Path's answers and prove the mask (and a whole V2 sweep) builds off the
// root isolate.
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/layout_mask.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pentagon exactly as `_pentagonCells` builds it, from the same draws.
List<(double, double)> _pentagon(
    int w, int h, double wobble, double apex, double midY, double baseIn) {
  final x0 = w * (0.08 + wobble);
  final x1 = w * (0.92 - wobble);
  final yTop = h * (0.18 + wobble * 0.5);
  final yMid = h * midY;
  final yBot = h * (0.92 - wobble * 0.5);
  return [
    (w * apex, yTop),
    (x1, yMid),
    (w * (1 - baseIn), yBot),
    (w * baseIn, yBot),
    (x0, yMid),
  ];
}

Set<String> _withPath(List<(double, double)> poly, int w, int h) {
  final path = Path()..moveTo(poly.first.$1, poly.first.$2);
  for (final (x, y) in poly.skip(1)) {
    path.lineTo(x, y);
  }
  path.close();
  return {
    for (var y = 0; y < h; y++)
      for (var x = 0; x < w; x++)
        if (path.contains(Offset(x + 0.5, y + 0.5))) '$x,$y',
  };
}

Set<String> _withPolygon(List<(double, double)> poly, int w, int h) => {
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
          if (polygonContainsPoint(poly, x + 0.5, y + 0.5)) '$x,$y',
    };

void main() {
  // MASK_N=2000 for a deeper sweep (~400k shapes).
  final jittered = int.tryParse(Platform.environment['MASK_N'] ?? '') ?? 150;

  test('polygonContainsPoint rasterises the pentagon exactly like Path', () {
    var cases = 0;
    final mismatches = <String>[];
    for (var w = 3; w <= 16; w++) {
      for (var h = 3; h <= 16; h++) {
        // Un-jittered shape across the whole wobble range, including the
        // `random == null` default (wobble 0.04).
        for (var k = 0; k <= 40; k++) {
          final wobble = k / 40 * 0.08;
          final poly = _pentagon(w, h, wobble, 0.5, 0.42, 0.22);
          cases++;
          if (!setEquals(_withPath(poly, w, h), _withPolygon(poly, w, h))) {
            mismatches.add('${w}x$h wobble=$wobble');
          }
        }
        // Jittered shapes, drawn from the same ranges as the generator.
        final r = Random(w * 1000 + h);
        for (var k = 0; k < jittered; k++) {
          final poly = _pentagon(
            w,
            h,
            r.nextDouble() * 0.08,
            0.34 + r.nextDouble() * 0.32,
            0.32 + r.nextDouble() * 0.22,
            0.10 + r.nextDouble() * 0.14,
          );
          cases++;
          if (!setEquals(_withPath(poly, w, h), _withPolygon(poly, w, h))) {
            mismatches.add('${w}x$h jittered #$k');
          }
        }
      }
    }
    expect(mismatches, isEmpty, reason: '$cases shapes compared');
  });

  test('the pentagon mask builds on a worker isolate', () async {
    final cells = await Isolate.run(() => buildLayoutMask(
        LayoutMaskKind.pentagon, 7, 10,
        random: Random(3), jitter: Random(4)));
    expect(cells, isNotNull);
    expect(cells!.length, greaterThanOrEqualTo(9));
    expect(
        cells,
        buildLayoutMask(LayoutMaskKind.pentagon, 7, 10,
            random: Random(3), jitter: Random(4)));
  });

  test('Gen V2 Hard L1-30 generates on a worker isolate', () async {
    final failures = await Isolate.run(() {
      final out = <String>[];
      for (var id = 1; id <= 30; id++) {
        try {
          LevelGenerator.neutral().generate(id,
              mode: DifficultyMode.hard,
              workBudget: LevelManager.genV2WorkBudget,
              generationVersion: 2);
        } catch (e) {
          out.add('L$id: $e');
        }
      }
      return out;
    });
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

bool setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
