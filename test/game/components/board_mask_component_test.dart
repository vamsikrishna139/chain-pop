import 'dart:ui';

import 'package:chain_pop/game/components/board_mask_component.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardMaskComponent', () {
    test('size matches grid times cellSize', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 6,
        gridHeight: 5,
        nodes: [],
      );
      const cell = 32.0;
      final comp = BoardMaskComponent(levelData: level, cellSize: cell);
      expect(comp.size.x, 6 * cell);
      expect(comp.size.y, 5 * cell);
    });

    test('render is a no-op when playCells is null', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 4,
        gridHeight: 4,
        nodes: [],
      );
      final comp = BoardMaskComponent(levelData: level, cellSize: 20);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(() => comp.render(canvas), returnsNormally);
    });

    test('render draws when playCells is non-empty', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        playCells: {'1,1'},
        nodes: [NodeData(id: 0, x: 1, y: 1, dir: Direction.up)],
      );
      final comp = BoardMaskComponent(levelData: level, cellSize: 10);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(() => comp.render(canvas), returnsNormally);
    });
  });
}
