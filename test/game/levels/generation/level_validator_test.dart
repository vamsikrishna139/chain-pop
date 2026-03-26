import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/generation/level_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LevelValidator', () {
    late LevelValidator validator;

    setUp(() {
      validator = LevelValidator();
    });

    group('validate', () {
      test('passes for valid solvable level with simple diagonal pattern', () {
        // Create a simple solvable level: 3 nodes in diagonal, all pointing up
        final level = LevelData(
          levelId: 1,
          gridWidth: 5,
          gridHeight: 5,
          nodes: [
            NodeData(id: 0, x: 0, y: 2, dir: Direction.up),
            NodeData(id: 1, x: 1, y: 1, dir: Direction.up),
            NodeData(id: 2, x: 2, y: 0, dir: Direction.up),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isTrue);
        expect(result.message, isEmpty);
      });

      test('passes for valid level with nodes pointing in different directions',
          () {
        // Create a level where nodes point in various directions
        // Node 0 at (0,0) points right (clear path, no nodes to the right in row 0)
        // Node 1 at (1,1) points down (clear path, no nodes below in column 1)
        // Node 2 at (2,2) points left (clear path, no nodes to the left in row 2)
        final level = LevelData(
          levelId: 2,
          gridWidth: 5,
          gridHeight: 5,
          nodes: [
            NodeData(id: 0, x: 0, y: 0, dir: Direction.right),
            NodeData(id: 1, x: 1, y: 1, dir: Direction.down),
            NodeData(id: 2, x: 2, y: 2, dir: Direction.left),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isTrue);
      });

      test('fails when node cannot be removed due to blocking node above', () {
        // Node 0 at (1,2) points up, but node 1 at (1,1) blocks it
        final level = LevelData(
          levelId: 3,
          gridWidth: 5,
          gridHeight: 5,
          nodes: [
            NodeData(id: 0, x: 1, y: 2, dir: Direction.up),
            NodeData(id: 1, x: 1, y: 1, dir: Direction.down),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isFalse);
        expect(result.message, contains('Node 0'));
        expect(result.message, contains('cannot be removed'));
      });

      test('fails when node cannot be removed due to blocking node below', () {
        // Node 0 at (1,1) points down, but node 1 at (1,2) blocks it
        final level = LevelData(
          levelId: 4,
          gridWidth: 5,
          gridHeight: 5,
          nodes: [
            NodeData(id: 0, x: 1, y: 1, dir: Direction.down),
            NodeData(id: 1, x: 1, y: 2, dir: Direction.up),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isFalse);
        expect(result.message, contains('Node 0'));
      });

      test('fails when node cannot be removed due to blocking node to the left',
          () {
        // Node 0 at (2,1) points left, but node 1 at (1,1) blocks it
        final level = LevelData(
          levelId: 5,
          gridWidth: 5,
          gridHeight: 5,
          nodes: [
            NodeData(id: 0, x: 2, y: 1, dir: Direction.left),
            NodeData(id: 1, x: 1, y: 1, dir: Direction.right),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isFalse);
        expect(result.message, contains('Node 0'));
      });

      test(
          'fails when node cannot be removed due to blocking node to the right',
          () {
        // Node 0 at (1,1) points right, but node 1 at (2,1) blocks it
        final level = LevelData(
          levelId: 6,
          gridWidth: 5,
          gridHeight: 5,
          nodes: [
            NodeData(id: 0, x: 1, y: 1, dir: Direction.right),
            NodeData(id: 1, x: 2, y: 1, dir: Direction.left),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isFalse);
        expect(result.message, contains('Node 0'));
      });

      test('passes when blocking node is removed before blocked node', () {
        // Node 0 at (1,1) points up (blocks node 1)
        // Node 1 at (1,2) points up (can be removed after node 0)
        final level = LevelData(
          levelId: 7,
          gridWidth: 5,
          gridHeight: 5,
          nodes: [
            NodeData(id: 0, x: 1, y: 1, dir: Direction.left),
            NodeData(id: 1, x: 1, y: 2, dir: Direction.up),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isTrue);
      });

      test('validates complex level with multiple nodes', () {
        // Create a more complex solvable level
        final level = LevelData(
          levelId: 8,
          gridWidth: 6,
          gridHeight: 6,
          nodes: [
            NodeData(id: 0, x: 0, y: 0, dir: Direction.right),
            NodeData(id: 1, x: 1, y: 1, dir: Direction.down),
            NodeData(id: 2, x: 2, y: 2, dir: Direction.left),
            NodeData(id: 3, x: 3, y: 3, dir: Direction.up),
            NodeData(id: 4, x: 4, y: 4, dir: Direction.right),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isTrue);
      });

      test('handles single node level', () {
        final level = LevelData(
          levelId: 9,
          gridWidth: 3,
          gridHeight: 3,
          nodes: [
            NodeData(id: 0, x: 1, y: 1, dir: Direction.up),
          ],
        );

        final result = validator.validate(level);

        expect(result.isValid, isTrue);
      });

      test('handles empty level', () {
        final level = LevelData(
          levelId: 10,
          gridWidth: 3,
          gridHeight: 3,
          nodes: [],
        );

        final result = validator.validate(level);

        expect(result.isValid, isTrue);
      });
    });

    group('_canRemoveNode', () {
      test('detects blocking node above (Direction.up)', () {
        final nodeToRemove = NodeData(id: 0, x: 2, y: 3, dir: Direction.up);
        final blockingNode = NodeData(id: 1, x: 2, y: 1, dir: Direction.down);
        final allNodes = [nodeToRemove, blockingNode];

        // Use reflection or create a test that indirectly tests this
        // Since _canRemoveNode is private, we test through validate
        final level = LevelData(
          levelId: 11,
          gridWidth: 5,
          gridHeight: 5,
          nodes: allNodes,
        );

        final result = validator.validate(level);
        expect(result.isValid, isFalse);
      });

      test('detects blocking node below (Direction.down)', () {
        final nodeToRemove = NodeData(id: 0, x: 2, y: 1, dir: Direction.down);
        final blockingNode = NodeData(id: 1, x: 2, y: 3, dir: Direction.up);
        final allNodes = [nodeToRemove, blockingNode];

        final level = LevelData(
          levelId: 12,
          gridWidth: 5,
          gridHeight: 5,
          nodes: allNodes,
        );

        final result = validator.validate(level);
        expect(result.isValid, isFalse);
      });

      test('detects blocking node to the left (Direction.left)', () {
        final nodeToRemove = NodeData(id: 0, x: 3, y: 2, dir: Direction.left);
        final blockingNode = NodeData(id: 1, x: 1, y: 2, dir: Direction.right);
        final allNodes = [nodeToRemove, blockingNode];

        final level = LevelData(
          levelId: 13,
          gridWidth: 5,
          gridHeight: 5,
          nodes: allNodes,
        );

        final result = validator.validate(level);
        expect(result.isValid, isFalse);
      });

      test('detects blocking node to the right (Direction.right)', () {
        final nodeToRemove =
            NodeData(id: 0, x: 1, y: 2, dir: Direction.right);
        final blockingNode = NodeData(id: 1, x: 3, y: 2, dir: Direction.left);
        final allNodes = [nodeToRemove, blockingNode];

        final level = LevelData(
          levelId: 14,
          gridWidth: 5,
          gridHeight: 5,
          nodes: allNodes,
        );

        final result = validator.validate(level);
        expect(result.isValid, isFalse);
      });

      test('allows removal when no blocking nodes in direction', () {
        final nodeToRemove = NodeData(id: 0, x: 2, y: 2, dir: Direction.up);
        final otherNode = NodeData(id: 1, x: 3, y: 3, dir: Direction.down);
        final allNodes = [nodeToRemove, otherNode];

        final level = LevelData(
          levelId: 15,
          gridWidth: 5,
          gridHeight: 5,
          nodes: allNodes,
        );

        final result = validator.validate(level);
        expect(result.isValid, isTrue);
      });

      test('ignores nodes in different rows/columns', () {
        final nodeToRemove = NodeData(id: 0, x: 2, y: 2, dir: Direction.up);
        final otherNode1 = NodeData(id: 1, x: 1, y: 1, dir: Direction.down);
        final otherNode2 = NodeData(id: 2, x: 3, y: 3, dir: Direction.left);
        final allNodes = [nodeToRemove, otherNode1, otherNode2];

        final level = LevelData(
          levelId: 16,
          gridWidth: 5,
          gridHeight: 5,
          nodes: allNodes,
        );

        final result = validator.validate(level);
        expect(result.isValid, isTrue);
      });
    });
  });
}
