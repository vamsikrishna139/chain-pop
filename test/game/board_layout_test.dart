import 'package:chain_pop/game/board_layout.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OccupiedBounds', () {
    test('fromLevel with empty level falls back to full grid', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 9,
        gridHeight: 9,
        nodes: [],
      );
      final bounds = OccupiedBounds.fromLevel(level, pad: 1);
      expect(bounds.minX, 0);
      expect(bounds.maxX, 8);
      expect(bounds.minY, 0);
      expect(bounds.maxY, 8);
      expect(bounds.bboxWidth, 9);
      expect(bounds.bboxHeight, 9);
    });

    test('fromLevel traces bounds and respects padding', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 9,
        gridHeight: 9,
        nodes: [
          NodeData(id: 0, x: 2, y: 3, dir: Direction.up),
          NodeData(id: 1, x: 5, y: 6, dir: Direction.down),
        ],
      );
      final bounds = OccupiedBounds.fromLevel(level, pad: 1);
      // Raw minX=2, maxX=5, minY=3, maxY=6
      // Padded: minX=1, maxX=6, minY=2, maxY=7
      expect(bounds.minX, 1);
      expect(bounds.maxX, 6);
      expect(bounds.minY, 2);
      expect(bounds.maxY, 7);
      expect(bounds.bboxWidth, 6);
      expect(bounds.bboxHeight, 6);
    });

    test('fromLevel respects grid boundary clamps', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 9,
        gridHeight: 9,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 8, y: 8, dir: Direction.down),
        ],
      );
      final bounds = OccupiedBounds.fromLevel(level, pad: 1);
      expect(bounds.minX, 0);
      expect(bounds.maxX, 8);
      expect(bounds.minY, 0);
      expect(bounds.maxY, 8);
    });
  });

  group('BoardLayoutMetrics.fitCellSize', () {
    test('never exceeds band so grid fits (dense grid, narrow band)', () {
      const bandW = 300.0;
      const bandH = 500.0;
      const gw = 18;
      const gh = 18;
      final s = BoardLayoutMetrics.fitCellSize(
        bandW: bandW,
        bandH: bandH,
        gridWidth: gw,
        gridHeight: gh,
      );
      expect(s * gw, lessThanOrEqualTo(bandW + 1e-6));
      expect(s * gh, lessThanOrEqualTo(bandH + 1e-6));
    });

    test('uses minPreferred when it still fits', () {
      final s = BoardLayoutMetrics.fitCellSize(
        bandW: 400,
        bandH: 400,
        gridWidth: 10,
        gridHeight: 10,
      );
      expect(s, greaterThanOrEqualTo(26.0));
      expect(s * 10, lessThanOrEqualTo(400.0 + 1e-6));
    });

    test('compute embeds grid in usable band', () {
      final m = BoardLayoutMetrics.compute(
        screenW: 360,
        screenH: 700,
        topReserved: 100,
        bottomReserved: 70,
        gridWidth: 18,
        gridHeight: 18,
      );
      expect(m.cellSize * 18, lessThanOrEqualTo(m.usableW + 1e-6));
      expect(m.cellSize * 18, lessThanOrEqualTo(m.usableH + 1e-6));
    });
  });

  group('BoardLayoutMetrics.fitCellSizeForBounds', () {
    test('scales correctly according to target fill', () {
      final s = BoardLayoutMetrics.fitCellSizeForBounds(
        bandW: 500,
        bandH: 500,
        bboxWidth: 5,
        bboxHeight: 5,
        targetFill: 0.80,
      );
      // 500 * 0.80 = 400. 400 / 5 = 80
      expect(s, closeTo(80.0, 1e-6));
    });
  });

  group('LevelData.layoutValidationMessage', () {
    test('null when valid', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 2, y: 2, dir: Direction.down),
        ],
      );
      expect(LevelData.layoutValidationMessage(level), isNull);
    });

    test('detects duplicate cells', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 1, y: 1, dir: Direction.up),
          NodeData(id: 1, x: 1, y: 1, dir: Direction.down),
        ],
      );
      expect(LevelData.layoutValidationMessage(level), isNotNull);
    });

    test('detects out of bounds', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 3, y: 0, dir: Direction.up),
        ],
      );
      expect(LevelData.layoutValidationMessage(level), isNotNull);
    });
  });
}
