import 'package:chain_pop/game/components/node_component.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NodeComponent makeNode(Direction dir) => NodeComponent(
        data: NodeData(id: 0, x: 1, y: 1, dir: dir),
        cellSize: 40,
      );

  group('NodeComponent relay rotation animation', () {
    test('clockwise rotation starts the arrow spun a quarter-turn back', () {
      final node = makeNode(Direction.up);
      node.animateRotationTo(
        NodeData(id: 0, x: 1, y: 1, dir: Direction.right),
        clockwise: true,
      );
      // Data updates immediately; the visual spin offset eases back to 0.
      expect(node.data.dir, Direction.right);
      expect(node.arrowSpin, lessThan(0));
    });

    test('counter-clockwise rotation spins the opposite way', () {
      final node = makeNode(Direction.up);
      node.animateRotationTo(
        NodeData(id: 0, x: 1, y: 1, dir: Direction.left),
        clockwise: false,
      );
      expect(node.arrowSpin, greaterThan(0));
    });
  });

  group('NodeComponent blocker flash', () {
    test('flashAsBlocker arms the warning pulse', () {
      final node = makeNode(Direction.left);
      expect(node.isFlashingBlocker, isFalse);
      node.flashAsBlocker();
      expect(node.isFlashingBlocker, isTrue);
    });
  });
}
