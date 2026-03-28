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
    test('easy never rolls irregular', () {
      final r = Random(12345);
      for (var i = 0; i < 50; i++) {
        expect(rollIrregularLayout(DifficultyMode.easy, r), isFalse);
      }
    });

    test('medium/hard can roll true or false over many draws', () {
      var mediumTrue = false;
      var hardTrue = false;
      final r = Random(7);
      for (var i = 0; i < 200; i++) {
        if (rollIrregularLayout(DifficultyMode.medium, r)) mediumTrue = true;
        if (rollIrregularLayout(DifficultyMode.hard, r)) hardTrue = true;
      }
      expect(mediumTrue, isTrue);
      expect(hardTrue, isTrue);
    });
  });

  group('pickIrregularKind', () {
    test('returns one of vShape, pentagon, cShape', () {
      final kinds = <LayoutMaskKind>{};
      final r = Random(3);
      for (var i = 0; i < 300; i++) {
        kinds.add(pickIrregularKind(r));
      }
      expect(kinds, contains(LayoutMaskKind.vShape));
      expect(kinds, contains(LayoutMaskKind.pentagon));
      expect(kinds, contains(LayoutMaskKind.cShape));
    });
  });
}
