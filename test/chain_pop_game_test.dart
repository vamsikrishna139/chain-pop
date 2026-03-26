import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/chain_pop_game.dart';

void main() {
  group('Chain Pop Mechanics Logic Tests', () {
    test('Level 2 Mechanic Checks', () {
      final game = ChainPopGame(levelId: 2, onWin: () {});
      // Manually trigger board setup ignoring flame components loading constraints
      final nodes = [
        NodeData(id: 1, x: 2, y: 2, dir: Direction.left),
        NodeData(id: 2, x: 1, y: 2, dir: Direction.up),
        NodeData(id: 3, x: 2, y: 1, dir: Direction.right),
      ];
      
      game.activeNodes.addAll(nodes);

      expect(game.canExtract(nodes[0]), isFalse, reason: 'Node 1 is blocked by Node 2');
      expect(game.canExtract(nodes[1]), isTrue, reason: 'Node 2 is free');
      expect(game.canExtract(nodes[2]), isTrue, reason: 'Node 3 is free');
      
      // Simulate popping Node 2
      game.registerExtraction(nodes[1]);
      
      // Node 1 should now be free
      expect(game.canExtract(nodes[0]), isTrue, reason: 'Node 1 should be freed after Node 2 pops');
    });

    test('Level 3 Mechanics Checks', () {
      final game = ChainPopGame(levelId: 3, onWin: () {});
      final nodes = [
        NodeData(id: 1, x: 2, y: 1, dir: Direction.down),
        NodeData(id: 2, x: 2, y: 2, dir: Direction.right),
        NodeData(id: 3, x: 1, y: 2, dir: Direction.right),
        NodeData(id: 4, x: 3, y: 2, dir: Direction.down),
        NodeData(id: 5, x: 2, y: 3, dir: Direction.left),
      ];

      game.activeNodes.addAll(nodes);

      expect(game.canExtract(nodes[0]), isFalse, reason: 'Node 1 blocked by Node 2 and Node 5');
      expect(game.canExtract(nodes[1]), isFalse, reason: 'Node 2 blocked by Node 4');
      expect(game.canExtract(nodes[2]), isFalse, reason: 'Node 3 blocked by Node 2');
      expect(game.canExtract(nodes[3]), isTrue,  reason: 'Node 4 is free');
      expect(game.canExtract(nodes[4]), isTrue,  reason: 'Node 5 is free');

      // Pop Node 4 Sequence
      game.registerExtraction(nodes[3]);
      expect(game.canExtract(nodes[1]), isTrue, reason: 'Node 2 should now be free');

      // Pop Node 2 Sequence
      game.registerExtraction(nodes[1]);
      expect(game.canExtract(nodes[0]), isFalse, reason: 'Node 1 is still blocked by Node 5');
      expect(game.canExtract(nodes[2]), isTrue, reason: 'Node 3 is now free');

      // Pop Node 5 Sequence
      game.registerExtraction(nodes[4]);
      expect(game.canExtract(nodes[0]), isTrue, reason: 'Node 1 is completely free');
    });
  });
}
