import 'package:chain_pop/game/levels/generation/frontier_set.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:flutter_test/flutter_test.dart';

Set<int> _fullRect(int w, int h) {
  final out = <int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.add(gridCellKey(x, y));
    }
  }
  return out;
}

void main() {
  group('FrontierSet', () {
    test('initial frontier on a full rectangle is the outer ring', () {
      final fs = FrontierSet(
        gridWidth: 4,
        gridHeight: 4,
        silhouette: _fullRect(4, 4),
      );
      // 4x4 → outer ring of 12 cells.
      expect(fs.length, equals(12));
      // Interior cells (1,1)..(2,2) are NOT in the frontier yet.
      for (var y = 1; y <= 2; y++) {
        for (var x = 1; x <= 2; x++) {
          expect(fs.contains(gridCellKey(x, y)), isFalse,
              reason: 'interior ($x,$y) should not start in frontier');
        }
      }
    });

    test('addPlaced expands the frontier with cardinal neighbours', () {
      final fs = FrontierSet(
        gridWidth: 5,
        gridHeight: 5,
        silhouette: _fullRect(5, 5),
      );
      final centre = gridCellKey(2, 2);
      expect(fs.contains(centre), isFalse);
      fs.addPlaced(centre);
      // The four cardinal neighbours are now in the frontier.
      expect(fs.contains(gridCellKey(1, 2)), isTrue);
      expect(fs.contains(gridCellKey(3, 2)), isTrue);
      expect(fs.contains(gridCellKey(2, 1)), isTrue);
      expect(fs.contains(gridCellKey(2, 3)), isTrue);
      // The placed cell itself is removed from the frontier.
      expect(fs.contains(centre), isFalse);
      expect(fs.isPlaced(centre), isTrue);
    });

    test('removePlaced restores frontier state symmetrically', () {
      final fs = FrontierSet(
        gridWidth: 5,
        gridHeight: 5,
        silhouette: _fullRect(5, 5),
      );
      final before = fs.cells.toSet();
      final cell = gridCellKey(2, 2);
      fs.addPlaced(cell);
      fs.removePlaced(cell);
      final after = fs.cells.toSet();
      expect(after, equals(before),
          reason: 'remove must be the inverse of add for an interior cell');
      expect(fs.isPlaced(cell), isFalse);
    });

    test('placing/removing multiple cells leaves consistent state', () {
      final fs = FrontierSet(
        gridWidth: 6,
        gridHeight: 6,
        silhouette: _fullRect(6, 6),
      );
      final before = fs.cells.toSet();

      final cells = [
        gridCellKey(2, 2),
        gridCellKey(3, 3),
        gridCellKey(4, 2),
      ];
      for (final c in cells) {
        fs.addPlaced(c);
      }
      // Now roll them all back in reverse.
      for (final c in cells.reversed) {
        fs.removePlaced(c);
      }
      expect(fs.cells.toSet(), equals(before),
          reason: 'sequence of adds/removes must round-trip');
      for (final c in cells) {
        expect(fs.isPlaced(c), isFalse);
      }
    });

    test('boundary cells stay in the frontier after rollback', () {
      final fs = FrontierSet(
        gridWidth: 5,
        gridHeight: 5,
        silhouette: _fullRect(5, 5),
      );
      final corner = gridCellKey(0, 0);
      expect(fs.contains(corner), isTrue);
      fs.addPlaced(corner);
      expect(fs.contains(corner), isFalse);
      fs.removePlaced(corner);
      expect(fs.contains(corner), isTrue,
          reason: 'corner is on the boundary → re-enters frontier');
    });

    test('non-silhouette cells never join the frontier', () {
      // Donut-like silhouette: 4x4 with the centre hole removed.
      final silhouette = _fullRect(4, 4)
        ..removeAll([
          gridCellKey(1, 1),
          gridCellKey(2, 1),
          gridCellKey(1, 2),
          gridCellKey(2, 2),
        ]);
      final fs = FrontierSet(
        gridWidth: 4,
        gridHeight: 4,
        silhouette: silhouette,
      );
      fs.addPlaced(gridCellKey(0, 1));
      // (1,1) is in the hole; must not be added by addPlaced of (0,1).
      expect(fs.contains(gridCellKey(1, 1)), isFalse);
    });
  });
}
