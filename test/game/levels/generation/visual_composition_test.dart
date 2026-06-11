import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/visual_composition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Visual Composition Checks', () {
    test('Easy tier always passes', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 9,
        gridHeight: 9,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.right),
          NodeData(id: 1, x: 8, y: 0, dir: Direction.left),
        ],
      );
      final result = evaluateVisualComposition(level, DifficultyTier.easy);
      expect(result.passes, isTrue);
    });

    test('Rejects wide corridor layouts when logical grid is symmetric', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 9,
        gridHeight: 9,
        nodes: [
          NodeData(id: 0, x: 1, y: 4, dir: Direction.right),
          NodeData(id: 1, x: 2, y: 4, dir: Direction.right),
          NodeData(id: 2, x: 3, y: 4, dir: Direction.right),
          NodeData(id: 3, x: 4, y: 4, dir: Direction.right),
          NodeData(id: 4, x: 5, y: 4, dir: Direction.right),
          NodeData(id: 5, x: 6, y: 4, dir: Direction.right),
        ],
      );
      // bboxWidth = 6, bboxHeight = 1. Aspect = 6.0 (exceeds 1.75)
      final result = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(result.passes, isFalse);
      expect(result.reason, VisualCompositionRejectReason.aspect);
    });

    test('Rejects corner blob layouts when blobVsGrid is < 0.50', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 10,
        gridHeight: 10,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.down),
          NodeData(id: 1, x: 1, y: 0, dir: Direction.down),
          NodeData(id: 2, x: 0, y: 1, dir: Direction.down),
          NodeData(id: 3, x: 1, y: 1, dir: Direction.down),
        ],
      );
      // bboxArea = 2 * 2 = 4. GridArea = 100. 4 / 100 = 0.04 (< 0.50)
      final result = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(result.passes, isFalse);
      expect(result.reason, VisualCompositionRejectReason.blobVsGrid);
    });

    test('Rejects sparse layout when bbox occupancy is < 0.35', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.down),
          NodeData(id: 1, x: 5, y: 5, dir: Direction.up),
        ],
      );
      // bboxArea = 36. nodes = 2. 2 / 36 = 0.055 (< 0.35)
      final result = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(result.passes, isFalse);
      expect(result.reason, VisualCompositionRejectReason.occupancy);
    });

    test('Rejects components count > 2', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 4,
        gridHeight: 4,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.down),
          NodeData(id: 1, x: 0, y: 1, dir: Direction.up),
          NodeData(id: 2, x: 2, y: 0, dir: Direction.left),
          NodeData(id: 3, x: 2, y: 1, dir: Direction.right),
          NodeData(id: 4, x: 3, y: 3, dir: Direction.up),
          NodeData(id: 5, x: 3, y: 2, dir: Direction.down),
        ],
      );
      // minX=0, maxX=3, minY=0, maxY=3. bboxArea=16. nodes=6. 6 / 16 = 0.375 (passes occupancy >= 0.35)
      // blobVsGrid = 16/16 = 1.0 (passes blobVsGrid >= 0.50)
      // Aspect = 4/4 = 1.0 (passes aspect)
      // 3 disconnected component pairs: (0,0)-(0,1), (2,0)-(2,1), (3,2)-(3,3)
      final result = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(result.passes, isFalse);
      expect(result.reason, VisualCompositionRejectReason.components);
    });

    test('Rejects singleton count > 2', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 4,
        gridHeight: 4,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.down),
          NodeData(id: 1, x: 2, y: 0, dir: Direction.up),
          NodeData(id: 2, x: 0, y: 2, dir: Direction.left),
          NodeData(id: 3, x: 2, y: 2, dir: Direction.right),
          NodeData(id: 4, x: 2, y: 3, dir: Direction.left),
          NodeData(id: 5, x: 3, y: 2, dir: Direction.up),
        ],
      );
      // Singletons: 0,0 and 2,0 and 0,2 (3 isolated singletons)
      // Total nodes: 6, bbox: 4x4 (area 16). Occupancy = 6/16 = 0.375 >= 0.35.
      // blobVsGrid = 16/16 = 1.0 >= 0.50.
      final result = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(result.passes, isFalse);
      expect(result.reason, VisualCompositionRejectReason.singleton);
    });

    test('Accepts valid visual compositions', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 4,
        gridHeight: 4,
        nodes: [
          NodeData(id: 0, x: 1, y: 1, dir: Direction.down),
          NodeData(id: 1, x: 1, y: 2, dir: Direction.up),
          NodeData(id: 2, x: 2, y: 1, dir: Direction.right),
          NodeData(id: 3, x: 2, y: 2, dir: Direction.left),
          NodeData(id: 4, x: 3, y: 2, dir: Direction.down),
          NodeData(id: 5, x: 3, y: 3, dir: Direction.up),
        ],
      );
      final result = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(result.passes, isTrue);
    });
  });
}
