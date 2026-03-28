import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NodeData', () {
    test('clone is equal but not identical', () {
      final a = NodeData(
        id: 3,
        x: 2,
        y: 1,
        dir: Direction.left,
        color: const Color(0xFFABCDEF),
      );
      final b = a.clone();
      expect(identical(a, b), isFalse);
      expect(b.id, a.id);
      expect(b.x, a.x);
      expect(b.y, a.y);
      expect(b.dir, a.dir);
      expect(b.color, a.color);
    });

    test('toString contains id and coordinates', () {
      final n = NodeData(id: 7, x: 4, y: 5, dir: Direction.down);
      expect(n.toString(), contains('7'));
      expect(n.toString(), contains('4,5'));
    });
  });

  group('LevelData', () {
    test('holds playCells and nodes', () {
      final level = LevelData(
        levelId: 42,
        gridWidth: 5,
        gridHeight: 4,
        playCells: {'0,0', '1,1'},
        nodes: [NodeData(id: 0, x: 0, y: 0, dir: Direction.right)],
      );
      expect(level.levelId, 42);
      expect(level.gridWidth, 5);
      expect(level.gridHeight, 4);
      expect(level.playCells, contains('0,0'));
      expect(level.nodes, hasLength(1));
    });
  });

  group('Direction', () {
    test('has four values', () {
      expect(Direction.values, hasLength(4));
    });
  });
}
