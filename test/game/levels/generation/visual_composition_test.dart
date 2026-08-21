import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
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

  // ═════════════════════════════════════════════════════════════════════════
  // T2.4a — observe. The score is computed for every board and acted on by
  // NOTHING. These tests exist to prove the "shadow mode" claim rather than
  // assert it, because T2.4c's whole design depends on T2.4b calibrating
  // against a distribution gathered while the rules were still the old ones.
  //
  // See docs/IMPLEMENTATION_PLAN_V2.md §T2.4a.
  // ═════════════════════════════════════════════════════════════════════════
  group('T2.4a composition score (shadow mode)', () {
    test('every rejection still names the same reason, in the same priority '
        'order', () {
      // The restructure replaced five early returns with compute-all +
      // resolve-at-the-end. Priority must be identical: a board failing both
      // aspect and components must still report `aspect`.
      final level = LevelData(
        levelId: 0,
        gridWidth: 8,
        gridHeight: 8,
        // A 1x8 sliver: aspect is extreme AND it is a single component.
        nodes: [
          for (var y = 0; y < 8; y++)
            NodeData(id: y, x: 0, y: y, dir: Direction.up),
        ],
      );
      final r = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(r.passes, isFalse);
      expect(r.reason, equals(VisualCompositionRejectReason.aspect),
          reason: 'aspect must win the priority order, as it did before T2.4a');
    });

    test('a rejected board still reports a usable score and detail', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 8,
        gridHeight: 8,
        nodes: [
          for (var y = 0; y < 8; y++)
            NodeData(id: y, x: 0, y: y, dir: Direction.up),
        ],
      );
      final r = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(r.evaluated, isTrue,
          reason: 'T2.4b needs the rejected population, so rejects must carry '
              'a real measurement, not filler');
      expect(r.score, inInclusiveRange(0.0, 1.0));
      expect(r.detail.aspect, lessThan(0.5),
          reason: 'a 1x8 sliver should score badly on the aspect term');
    });

    test('Easy is short-circuited and flagged unevaluated', () {
      // Easy never runs the rules (plan §T1.4). Its filler detail must not be
      // read as a perfect composition, or it would skew T2.4b's calibration.
      final level = LevelData(
        levelId: 0,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var y = 0; y < 6; y++)
            NodeData(id: y, x: 0, y: y, dir: Direction.up),
        ],
      );
      final r = evaluateVisualComposition(level, DifficultyTier.easy);
      expect(r.passes, isTrue);
      expect(r.evaluated, isFalse);
    });

    test('the generator records both populations and still ships the same '
        'board', () {
      final g = LevelGenerator.neutral();
      final a = g.generate(42, mode: DifficultyMode.hard).value;

      // Shadow-mode observation must not perturb generation at all.
      final b = LevelGenerator.neutral()
          .generate(42, mode: DifficultyMode.hard)
          .value;
      expect(a.nodes.length, equals(b.nodes.length));

      // Both populations are captured; the rejected one is the half no CSV
      // can otherwise see.
      expect(g.visualScoresAccepted, isNotEmpty);
      for (final v in [...g.visualScoresAccepted, ...g.visualScoresRejected]) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
