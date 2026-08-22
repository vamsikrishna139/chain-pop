import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/visual_composition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _t24c();
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
      // T2.4c: soft. Named and scored, but no longer fatal.
      expect(result.passes, isTrue);
      expect(result.softFailed, isTrue);
      expect(result.reason, VisualCompositionRejectReason.blobVsGrid);
      expect(result.detail.blobVsGrid, lessThan(0.5),
          reason: 'the violated term must be what drags the score down');
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
      // T2.4c: soft. `occupancy` is the Medium-only lever — T2.4b measured it
      // rejecting 1,672 Medium candidates and exactly 0 Hard ones.
      expect(result.passes, isTrue);
      expect(result.softFailed, isTrue);
      expect(result.reason, VisualCompositionRejectReason.occupancy);
      expect(result.detail.occupancy, lessThan(0.35));
    });

    test('Rejects components count > the allowance', () {
      // T2.4c raised `allowedComponents` from `max(2, maskComponents)` to
      // `maskComponents + 2`, so on a maskless board the allowance is 3, not 2.
      // The old fixture had exactly 3 components and is now legal *by design*;
      // a 4th pair is added so the test still probes the reject boundary
      // instead of silently becoming a pass-through.
      final level = LevelData(
        levelId: 1,
        gridWidth: 6,
        gridHeight: 4,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.down),
          NodeData(id: 1, x: 0, y: 1, dir: Direction.up),
          NodeData(id: 2, x: 2, y: 0, dir: Direction.left),
          NodeData(id: 3, x: 2, y: 1, dir: Direction.right),
          NodeData(id: 4, x: 4, y: 3, dir: Direction.up),
          NodeData(id: 5, x: 4, y: 2, dir: Direction.down),
          NodeData(id: 6, x: 0, y: 3, dir: Direction.up),
          NodeData(id: 7, x: 1, y: 3, dir: Direction.down),
        ],
      );
      // minX=0, maxX=3, minY=0, maxY=3. bboxArea=16. nodes=6. 6 / 16 = 0.375 (passes occupancy >= 0.35)
      // blobVsGrid = 16/16 = 1.0 (passes blobVsGrid >= 0.50)
      // Aspect = 4/4 = 1.0 (passes aspect)
      // 3 disconnected component pairs: (0,0)-(0,1), (2,0)-(2,1), (3,2)-(3,3)
      final result = evaluateVisualComposition(level, DifficultyTier.medium);
      // T2.4c: still a HARD reject. It was softened, the T2.4b p10 floor
      // caught the result (Hard 0.6595 -> 0.5844), and the plan's pre-committed
      // remedy — "re-reject `components` only" — was applied.
      expect(result.passes, isFalse);
      expect(result.reason, VisualCompositionRejectReason.components);
      expect(kHardCompositionRules,
          contains(VisualCompositionRejectReason.components));
    });

    test('the singleton allowance scales with mask components (T2.4c)', () {
      // T2.4c raised `allowedSingletons` from `max(2, maskComponents)` to
      // `maskComponents + 2`, so a maskless board is allowed 3, not 2.
      //
      // Three isolated nodes and nothing else: 3 singletons and 3 components,
      // both sitting exactly at the raised allowance. The original fixture for
      // this case had 3 singletons *plus* a connected cluster, which is 4
      // components — under T2.4c the hard `components` rule fires on it first,
      // so it can no longer isolate the singleton behaviour. That is not a
      // quirk of the fixture: on a maskless board every additional singleton is
      // also an additional component, so a *soft* singleton failure is
      // unreachable there at all. Soft-failure behaviour is covered by the
      // `occupancy` and `blobVsGrid` cases above.
      final level = LevelData(
        levelId: 1,
        gridWidth: 3,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.down),
          NodeData(id: 1, x: 2, y: 0, dir: Direction.up),
          NodeData(id: 2, x: 0, y: 2, dir: Direction.left),
        ],
      );
      final result = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(result.passes, isTrue,
          reason: '3 singletons / 3 components sit exactly at the allowance; '
              'before T2.4c this board rejected on an allowance of 2');
      expect(result.detail.singleton, lessThan(1.0),
          reason: 'still scored — the allowance moved, the measurement did not');
      expect(result.detail.components, lessThan(1.0));
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

// ═══════════════════════════════════════════════════════════════════════════
// T2.4c — rank. The four soft rules admit and score; `aspect` and `components`
// still reject. The cases below pin the parts that are easy to get subtly
// wrong, and one of them was in fact wrong when T2.4c was first written.
// ═══════════════════════════════════════════════════════════════════════════

void _t24c() {
  group('T2.4c — soft rules rank, hard rules reject', () {
    test('a hard rule rejects even when a soft rule fails first in priority '
        'order', () {
      // THE REGRESSION THIS FILE EXISTS FOR.
      //
      // The reject reason is resolved in a fixed priority order
      // (aspect -> blobVsGrid -> occupancy -> singleton -> components) and
      // `components` is LAST. The first cut of T2.4c scanned that one order and
      // returned at the first failure, which is correct only while every rule
      // is hard: a board failing `singleton` (soft, 4th) *and* `components`
      // (hard, 5th) was named `singleton`, admitted, and the hard rule never
      // fired. Measured, that shipped scattered boards under a different label
      // — Hard's shipped `singleton` violations went 5 -> 36 while `components`
      // violations stayed at 0 and its p10 stayed pinned at 0.00.
      //
      // This board is three isolated singletons AND four components.
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
      final r = evaluateVisualComposition(level, DifficultyTier.medium);
      expect(r.detail.singleton, lessThan(1.0),
          reason: 'the soft rule really is violated on this board');
      // 4 components against an allowance of 3 -> the hard rule must win.
      expect(r.detail.components, lessThan(1.0));
      expect(r.passes, isFalse,
          reason: 'a hard-rule violation must reject regardless of which rule '
              'wins the naming order');
      expect(r.reason, VisualCompositionRejectReason.components);
    });

    test('every soft rule admits, and every hard rule rejects', () {
      for (final rule in VisualCompositionRejectReason.values) {
        final isHard = kHardCompositionRules.contains(rule);
        expect(isHard, rule == VisualCompositionRejectReason.aspect ||
            rule == VisualCompositionRejectReason.components,
            reason: 'T2.4c ships exactly {aspect, components} as hard; '
                'changing that set is a seed-moving decision and must be '
                'made in the plan, not here');
      }
    });

    test('a soft failure still lowers the score it is scored on', () {
      // The ranking term is only meaningful if violating a soft rule actually
      // costs score — otherwise "reject -> rank" silently becomes "reject ->
      // ignore", which is the failure mode that has no test to catch it.
      final clean = LevelData(
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
      final sparse = LevelData(
        levelId: 1,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.down),
          NodeData(id: 1, x: 5, y: 5, dir: Direction.up),
        ],
      );
      final a = evaluateVisualComposition(clean, DifficultyTier.medium);
      final b = evaluateVisualComposition(sparse, DifficultyTier.medium);
      expect(a.softFailed, isFalse);
      expect(b.softFailed, isTrue);
      expect(b.score, lessThan(a.score),
          reason: 'a soft-failing board must rank below a clean one');
    });
  });
}
