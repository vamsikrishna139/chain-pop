import 'dart:ui';

import 'package:chain_pop/game/components/board_mask_component.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/theme/world_theme.dart';
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

    test('renders tiles for the full grid when playCells is null', () {
      // Rectangular boards get the same tile chassis as silhouettes.
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

    test('renders playable-cell tiles when playCells is non-empty', () {
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

    test('accepts an explicit WorldTheme', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 2,
        gridHeight: 2,
        nodes: [],
      );
      final theme = WorldTheme.fromAccent(const Color(0xFFFFB020));
      final comp = BoardMaskComponent(
        levelData: level,
        cellSize: 16,
        theme: theme,
      );
      expect(comp.theme.accent, const Color(0xFFFFB020));
      final recorder = PictureRecorder();
      expect(() => comp.render(Canvas(recorder)), returnsNormally);
    });
  });
}
