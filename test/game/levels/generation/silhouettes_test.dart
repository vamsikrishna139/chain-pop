import 'dart:math';

import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSilhouetteMask', () {
    test('rectangle always returns the full board', () {
      final mask = buildSilhouetteMask(
        id: SilhouetteId.rectangle,
        gridWidth: 6,
        gridHeight: 5,
        random: Random(0),
      );
      expect(mask, isNotNull);
      expect(mask!.length, equals(30));
    });

    test('archipelago produces three disjoint clusters on a wide grid', () {
      final mask = buildSilhouetteMask(
        id: SilhouetteId.archipelago,
        gridWidth: 12,
        gridHeight: 4,
        random: Random(1),
      );
      expect(mask, isNotNull);
      expect(mask!.length, greaterThan(0));
      // At least some cells per third of the grid (proves the clusters are
      // not all bunched together).
      var leftThird = 0, midThird = 0, rightThird = 0;
      for (final k in mask) {
        final x = k & 0xffff;
        if (x < 4) {
          leftThird++;
        } else if (x < 8) {
          midThird++;
        } else {
          rightThird++;
        }
      }
      expect(leftThird, greaterThan(0));
      expect(midThird, greaterThan(0));
      expect(rightThird, greaterThan(0));
    });

    test('corridor occupies a thin band of the grid', () {
      final mask = buildSilhouetteMask(
        id: SilhouetteId.corridor,
        gridWidth: 9,
        gridHeight: 9,
        random: Random(2),
      );
      expect(mask, isNotNull);
      // Less than the full grid.
      expect(mask!.length, lessThan(81));
      // More than just a single row/column.
      expect(mask.length, greaterThanOrEqualTo(9));
    });

    test('respects minCells — returns null when the silhouette is too small',
        () {
      // 4x4 organic blob asked for at least 100 cells is impossible.
      final mask = buildSilhouetteMask(
        id: SilhouetteId.organicBlob,
        gridWidth: 4,
        gridHeight: 4,
        random: Random(3),
        minCells: 100,
      );
      expect(mask, isNull);
    });
  });

  group('silhouetteToPlayCells', () {
    test('returns null when the mask covers the whole grid', () {
      final mask = <int>{
        for (var y = 0; y < 4; y++)
          for (var x = 0; x < 4; x++) gridCellKey(x, y),
      };
      expect(
          silhouetteToPlayCells(mask, gridWidth: 4, gridHeight: 4), isNull);
    });

    test('round-trips a partial mask back to string form', () {
      final mask = <int>{
        gridCellKey(0, 0),
        gridCellKey(1, 2),
        gridCellKey(3, 1),
      };
      final cells =
          silhouetteToPlayCells(mask, gridWidth: 4, gridHeight: 4);
      expect(cells, isNotNull);
      expect(cells, containsAll(['0,0', '1,2', '3,1']));
      expect(cells!.length, equals(3));
    });
  });
}
