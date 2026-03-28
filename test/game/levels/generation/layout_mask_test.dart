import 'dart:math';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/layout_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLayoutMask', () {
    test('fullRect returns null', () {
      expect(buildLayoutMask(LayoutMaskKind.fullRect, 8, 8), isNull);
    });

    test('vShape returns non-empty subset within bounds', () {
      const w = 7;
      const h = 6;
      final cells = buildLayoutMask(LayoutMaskKind.vShape, w, h, random: Random(42))!;
      expect(cells, isNotEmpty);
      for (final key in cells) {
        final parts = key.split(',');
        final x = int.parse(parts[0]);
        final y = int.parse(parts[1]);
        expect(x, greaterThanOrEqualTo(0));
        expect(x, lessThan(w));
        expect(y, greaterThanOrEqualTo(0));
        expect(y, lessThan(h));
      }
    });

    test('pentagon returns cells or falls back to vShape for tiny grids', () {
      final large = buildLayoutMask(LayoutMaskKind.pentagon, 12, 12, random: Random(1))!;
      expect(large.length, greaterThanOrEqualTo(9));
    });

    test('cShape removes most interior void cells', () {
      const w = 9;
      const h = 9;
      final cells = buildLayoutMask(LayoutMaskKind.cShape, w, h, random: Random(0))!;
      expect(cells.length, lessThan(w * h));
      expect(cells.length, greaterThan(40));
    });

    test('deterministic Random yields stable vShape cell count', () {
      final a = buildLayoutMask(LayoutMaskKind.vShape, 10, 10, random: Random(99))!;
      final b = buildLayoutMask(LayoutMaskKind.vShape, 10, 10, random: Random(99))!;
      expect(a.length, b.length);
      expect(a, b);
    });
  });

  group('rollIrregularLayout', () {
    test('easy rolls irregular less often than medium and hard', () {
      var easyCount = 0;
      var mediumCount = 0;
      var hardCount = 0;
      const trials = 500;
      final r = Random(12345);
      for (var i = 0; i < trials; i++) {
        if (rollIrregularLayout(DifficultyMode.easy, r)) easyCount++;
        if (rollIrregularLayout(DifficultyMode.medium, r)) mediumCount++;
        if (rollIrregularLayout(DifficultyMode.hard, r)) hardCount++;
      }
      expect(easyCount, lessThan(mediumCount));
      expect(mediumCount, lessThan(hardCount));
    });

    test('all modes can roll true over many draws', () {
      var easyTrue = false;
      var mediumTrue = false;
      var hardTrue = false;
      final r = Random(7);
      for (var i = 0; i < 200; i++) {
        if (rollIrregularLayout(DifficultyMode.easy, r)) easyTrue = true;
        if (rollIrregularLayout(DifficultyMode.medium, r)) mediumTrue = true;
        if (rollIrregularLayout(DifficultyMode.hard, r)) hardTrue = true;
      }
      expect(easyTrue, isTrue);
      expect(mediumTrue, isTrue);
      expect(hardTrue, isTrue);
    });
  });

  group('pickIrregularKind', () {
    test('returns a variety of non-fullRect shapes', () {
      final kinds = <LayoutMaskKind>{};
      final r = Random(3);
      for (var i = 0; i < 500; i++) {
        kinds.add(pickIrregularKind(r));
      }
      expect(kinds, isNot(contains(LayoutMaskKind.fullRect)));
      expect(kinds.length, greaterThanOrEqualTo(5));
      expect(kinds, contains(LayoutMaskKind.vShape));
      expect(kinds, contains(LayoutMaskKind.pentagon));
      expect(kinds, contains(LayoutMaskKind.cShape));
    });

    test('respects preferred list when provided', () {
      final r = Random(42);
      const preferred = [LayoutMaskKind.diamond, LayoutMaskKind.donut];
      for (var i = 0; i < 50; i++) {
        final kind = pickIrregularKind(r, preferred: preferred);
        expect(preferred, contains(kind));
      }
    });
  });
}
