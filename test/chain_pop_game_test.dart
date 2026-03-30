import 'package:chain_pop/game/chain_pop_game.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/services/game_sfx.dart';
import 'package:chain_pop/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChainPopGame callbacks and win', () {
    test('registerExtraction invokes onNodeRemoved with counts', () {
      var lastRemoved = -1;
      var lastTotal = -1;
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
        onNodeRemoved: (removed, total) {
          lastRemoved = removed;
          lastTotal = total;
        },
      );
      final nodes = [
        NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
        NodeData(id: 1, x: 4, y: 4, dir: Direction.down),
      ];
      game.levelData = LevelData(
        levelId: 1,
        gridWidth: 5,
        gridHeight: 5,
        nodes: nodes.map((n) => n.clone()).toList(),
      );
      game.activeNodes.addAll(nodes.map((n) => n.clone()));

      game.registerExtraction(nodes[0]);
      expect(lastTotal, 2);
      expect(lastRemoved, 1);
    });

    test('axis guides turn off after a valid extraction', () {
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
      );
      final n = NodeData(id: 0, x: 0, y: 0, dir: Direction.up);
      game.levelData = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [n.clone()],
      );
      game.activeNodes.add(n.clone());

      game.toggleAxisGuides();
      expect(game.axisGuidesVisible, isTrue);
      game.registerExtraction(n);
      expect(game.axisGuidesVisible, isFalse);
    });

    test('checkWinCondition calls onWin once when board clears', () {
      var wins = 0;
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () => wins++,
      );
      final n = NodeData(id: 0, x: 0, y: 0, dir: Direction.up);
      game.levelData = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [n.clone()],
      );
      game.activeNodes.add(n.clone());

      game.registerExtraction(n);
      expect(game.activeNodes, isEmpty);
      game.checkWinCondition();
      expect(wins, 1);
      game.checkWinCondition();
      expect(wins, 1);
      expect(game.hasWon, isTrue);
    });
  });

  group('Chain Pop Mechanics Logic Tests', () {
    test('Level 2 Mechanic Checks', () {
      final game = ChainPopGame(levelId: 2, difficulty: DifficultyMode.easy, onWin: () {});
      // Manually trigger board setup ignoring flame components loading constraints
      final nodes = [
        NodeData(id: 1, x: 2, y: 2, dir: Direction.left),
        NodeData(id: 2, x: 1, y: 2, dir: Direction.up),
        NodeData(id: 3, x: 2, y: 1, dir: Direction.right),
      ];

      game.levelData = LevelData(
        levelId: 2,
        gridWidth: 6,
        gridHeight: 6,
        nodes: nodes.map((n) => n.clone()).toList(),
      );
      game.activeNodes.addAll(nodes);

      expect(game.canExtract(nodes[0]), isFalse, reason: 'Node 1 is blocked by Node 2');
      expect(game.canExtract(nodes[1]), isTrue, reason: 'Node 2 is free');
      expect(game.canExtract(nodes[2]), isTrue, reason: 'Node 3 is free');
      
      // Simulate popping Node 2
      game.registerExtraction(nodes[1]);
      
      // Node 1 should now be free
      expect(game.canExtract(nodes[0]), isTrue, reason: 'Node 1 should be freed after Node 2 pops');
    });

    test('undo restores last removal and updates onNodeRemoved', () {
      var lastRemoved = -1;
      var lastTotal = -1;
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
        onNodeRemoved: (removed, total) {
          lastRemoved = removed;
          lastTotal = total;
        },
      );
      final n0 = NodeData(id: 0, x: 0, y: 0, dir: Direction.up);
      final n1 = NodeData(id: 1, x: 4, y: 4, dir: Direction.down);
      game.levelData = LevelData(
        levelId: 1,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [n0.clone(), n1.clone()],
      );
      game.activeNodes.addAll([n0.clone(), n1.clone()]);

      expect(game.canUndo, isFalse);
      game.registerExtraction(n0);
      expect(game.canUndo, isTrue);
      expect(lastRemoved, 1);
      expect(lastTotal, 2);

      expect(game.undo(), isTrue);
      expect(game.activeNodes, hasLength(2));
      expect(lastRemoved, 0);
      expect(game.canUndo, isFalse);
    });

    test('undo returns false when stack is empty', () {
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
      );
      game.levelData = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [NodeData(id: 0, x: 0, y: 0, dir: Direction.up)],
      );
      game.activeNodes.add(game.levelData.nodes.first.clone());
      expect(game.undo(), isFalse);
    });

    test('undo returns false after win', () {
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
      );
      final n = NodeData(id: 0, x: 0, y: 0, dir: Direction.up);
      game.levelData = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [n.clone()],
      );
      game.activeNodes.add(n.clone());
      game.registerExtraction(n);
      game.checkWinCondition();
      expect(game.hasWon, isTrue);
      expect(game.undo(), isFalse);
    });

    test('playSfx does not call onSfx when sound is disabled', () {
      var calls = 0;
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
      );
      game.onSfx = (sfx, {double playbackRate = 1.0}) {
        calls++;
      };
      game.soundEnabled = false;
      game.playSfx(GameSfx.uiTap);
      expect(calls, 0);
      game.soundEnabled = true;
      game.playSfx(GameSfx.uiTap);
      expect(calls, 1);
    });

    test('reportJam resets popPlaybackRate baseline', () {
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
      );
      final n0 = NodeData(id: 0, x: 0, y: 0, dir: Direction.up);
      final n1 = NodeData(id: 1, x: 2, y: 0, dir: Direction.up);
      game.levelData = LevelData(
        levelId: 1,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [n0.clone(), n1.clone()],
      );
      game.activeNodes.addAll([n0.clone(), n1.clone()]);

      expect(game.popPlaybackRate, closeTo(0.94, 1e-9));
      game.registerExtraction(n0);
      expect(game.popPlaybackRate, 1.0);
      game.reportJam();
      expect(game.popPlaybackRate, closeTo(0.94, 1e-9));
    });

    test('effectiveNodeColor maps colorSlot when colorblind palette is on', () {
      final game = ChainPopGame(
        levelId: 1,
        difficulty: DifficultyMode.easy,
        onWin: () {},
      );
      const slot = 2;
      final c = AppColors.nodePalette[slot];
      final n = NodeData(
        id: 0,
        x: 0,
        y: 0,
        dir: Direction.up,
        color: c,
        colorSlot: slot,
      );
      game.colorblindPalette = false;
      expect(game.effectiveNodeColor(n), c);
      game.colorblindPalette = true;
      expect(game.effectiveNodeColor(n), AppColors.nodePaletteColorblind[slot]);
    });

    test('Level 3 Mechanics Checks', () {
      final game = ChainPopGame(levelId: 3, difficulty: DifficultyMode.easy, onWin: () {});
      final nodes = [
        NodeData(id: 1, x: 2, y: 1, dir: Direction.down),
        NodeData(id: 2, x: 2, y: 2, dir: Direction.right),
        NodeData(id: 3, x: 1, y: 2, dir: Direction.right),
        NodeData(id: 4, x: 3, y: 2, dir: Direction.down),
        NodeData(id: 5, x: 2, y: 3, dir: Direction.left),
      ];

      game.levelData = LevelData(
        levelId: 3,
        gridWidth: 6,
        gridHeight: 6,
        nodes: nodes.map((n) => n.clone()).toList(),
      );
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
