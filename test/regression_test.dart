import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/chain_pop_game.dart';

void main() {
  group('Regression Tests - Levels 1 to 5 Playthroughs', () {
    
    // Helper function to simulate a playthrough of a sequence of node IDs.
    void playLevelSequence(int levelId, List<int> sequenceToPop) {
      bool winTriggered = false;
      final game = ChainPopGame(levelId: levelId, onWin: () {
        winTriggered = true;
      });
      
      // Manually set up nodes without Flame's async onLoad() cycle
      final levelData = LevelManager.getLevel(levelId)!;
      for (var node in levelData.nodes) {
        game.activeNodes.add(node.clone());
      }
      
      int index = 0;
      for (int id in sequenceToPop) {
        // Find the node by id
        final node = game.activeNodes.firstWhere((n) => n.id == id);
        
        // Assert we CAN extract it
        expect(game.canExtract(node), isTrue, 
          reason: 'Level $levelId: Failed to extract node $id at step $index. Expected it to be free.');
        
        // Extract it
        game.registerExtraction(node);
        index++;
      }
      
      // Simulate Flame removing all nodes and firing checkWinCondition
      expect(game.activeNodes.isEmpty, isTrue, 
        reason: 'Level $levelId: Board should be empty after sequence.');
      game.checkWinCondition();
    }

    test('Level 1 Playthrough', () {
      playLevelSequence(1, [1, 2]);
    });

    test('Level 2 Playthrough', () {
      // 1 blocked by 2. 2 and 3 are free.
      playLevelSequence(2, [2, 3, 1]);
    });

    test('Level 3 Playthrough', () {
      // Node 4 is free. Popping 4 frees 2. Popping 2 frees 1 and 3. Node 5 is free initially.
      playLevelSequence(3, [5, 4, 2, 1, 3]);
    });

    test('Level 4 Playthrough', () {
      playLevelSequence(4, [4, 3, 1, 2, 5]);
    });

    test('Level 5 Playthrough', () {
      playLevelSequence(5, [5, 4, 3, 2, 1]);
    });

  });
}
