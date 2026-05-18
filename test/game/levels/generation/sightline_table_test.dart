import 'package:chain_pop/game/levels/generation/sightline_table.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SightlineTable', () {
    test('empty board: every direction is clear from every cell', () {
      final t = SightlineTable.forGrid(5, 5);
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          for (final dir in Direction.values) {
            expect(t.hasClearRay(x, y, dir, <int>{}), isTrue,
                reason: 'cell ($x,$y) dir $dir should be clear on empty board');
          }
          expect(t.clearDirectionCount(x, y, <int>{}), equals(4));
        }
      }
    });

    test('blocker between source and edge blocks the ray', () {
      final t = SightlineTable.forGrid(5, 5);
      final occupied = <int>{gridCellKey(3, 2)};
      // (1, 2) shooting right is blocked by (3, 2).
      expect(t.hasClearRay(1, 2, Direction.right, occupied), isFalse);
      // (1, 2) shooting left is clear (exits the grid).
      expect(t.hasClearRay(1, 2, Direction.left, occupied), isTrue);
      // (1, 2) shooting up/down are clear.
      expect(t.hasClearRay(1, 2, Direction.up, occupied), isTrue);
      expect(t.hasClearRay(1, 2, Direction.down, occupied), isTrue);
    });

    test('blocker beyond edge does not affect rays', () {
      final t = SightlineTable.forGrid(4, 4);
      // (1, 1) shooting up exits at row -1; nothing in the precomputed ray.
      expect(t.hasClearRay(1, 1, Direction.up, <int>{gridCellKey(1, 0)}),
          isFalse);
      // Removing the blocker → clear.
      expect(t.hasClearRay(1, 1, Direction.up, <int>{}), isTrue);
    });

    test('clearDirectionCount tracks added blockers', () {
      final t = SightlineTable.forGrid(5, 5);
      final occupied = <int>{
        gridCellKey(2, 0), // up blocker for (2,2)
        gridCellKey(2, 4), // down blocker for (2,2)
      };
      expect(t.clearDirectionCount(2, 2, occupied), equals(2));
      occupied.add(gridCellKey(0, 2)); // left blocker
      expect(t.clearDirectionCount(2, 2, occupied), equals(1));
      occupied.add(gridCellKey(4, 2)); // right blocker → fully boxed in
      expect(t.clearDirectionCount(2, 2, occupied), equals(0));
    });
  });
}
