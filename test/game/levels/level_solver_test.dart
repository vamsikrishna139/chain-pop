import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LevelSolver.canRemove', () {
    test('returns true when ray exits grid with no blockers (all directions)', () {
      const gw = 5;
      const gh = 5;
      final level = LevelData(levelId: 1, gridWidth: gw, gridHeight: gh, nodes: []);

      expect(
        LevelSolver.canRemove(
          NodeData(id: 0, x: 2, y: 0, dir: Direction.up),
          [NodeData(id: 0, x: 2, y: 0, dir: Direction.up)],
          level,
        ),
        isTrue,
      );
      expect(
        LevelSolver.canRemove(
          NodeData(id: 0, x: 2, y: 4, dir: Direction.down),
          [NodeData(id: 0, x: 2, y: 4, dir: Direction.down)],
          level,
        ),
        isTrue,
      );
      expect(
        LevelSolver.canRemove(
          NodeData(id: 0, x: 0, y: 2, dir: Direction.left),
          [NodeData(id: 0, x: 0, y: 2, dir: Direction.left)],
          level,
        ),
        isTrue,
      );
      expect(
        LevelSolver.canRemove(
          NodeData(id: 0, x: 4, y: 2, dir: Direction.right),
          [NodeData(id: 0, x: 4, y: 2, dir: Direction.right)],
          level,
        ),
        isTrue,
      );
    });

    test('returns false when another node blocks the ray', () {
      final level = LevelData(levelId: 1, gridWidth: 5, gridHeight: 5, nodes: []);
      final a = NodeData(id: 0, x: 2, y: 3, dir: Direction.up);
      final b = NodeData(id: 1, x: 2, y: 1, dir: Direction.down);
      expect(LevelSolver.canRemove(a, [a, b], level), isFalse);
    });

    test('ignores self when checking blockers', () {
      final level = LevelData(levelId: 1, gridWidth: 5, gridHeight: 5, nodes: []);
      final n = NodeData(id: 0, x: 2, y: 2, dir: Direction.right);
      expect(LevelSolver.canRemove(n, [n], level), isTrue);
    });

    test('playCells does not clip ray — void outside play area still blocks', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 5,
        gridHeight: 5,
        playCells: {'2,2', '2,3'},
        nodes: [],
      );
      final mover = NodeData(id: 0, x: 2, y: 2, dir: Direction.right);
      final blocker = NodeData(id: 1, x: 4, y: 2, dir: Direction.left);
      expect(LevelSolver.canRemove(mover, [mover, blocker], level), isFalse);
    });
  });

  group('LevelSolver.canRemoveWithPositions', () {
    test('matches canRemove when others set excludes self', () {
      final level = LevelData(levelId: 1, gridWidth: 6, gridHeight: 6, nodes: []);
      final a = NodeData(id: 0, x: 1, y: 1, dir: Direction.right);
      final b = NodeData(id: 1, x: 3, y: 1, dir: Direction.left);
      final c = NodeData(id: 2, x: 5, y: 5, dir: Direction.down);
      final all = [a, b, c];

      for (final focus in all) {
        final others = <String>{
          for (final o in all)
            if (o.id != focus.id) '${o.x},${o.y}',
        };
        expect(
          LevelSolver.canRemoveWithPositions(focus, others, level),
          LevelSolver.canRemove(focus, all, level),
          reason: 'node ${focus.id}',
        );
      }
    });
  });

  group('LevelSolver.countRemovalWaves / isSolvable', () {
    test('single node pointing to edge clears in one wave', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 4,
        gridHeight: 4,
        nodes: [
          NodeData(id: 0, x: 1, y: 3, dir: Direction.up, color: const Color(0xFF4FACFE)),
        ],
      );
      expect(LevelSolver.countRemovalWaves(level), 1);
      expect(LevelSolver.isSolvable(level), isTrue);
    });

    test('returns -1 / not solvable for mutual block', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [
          NodeData(id: 0, x: 1, y: 2, dir: Direction.up),
          NodeData(id: 1, x: 1, y: 1, dir: Direction.down),
        ],
      );
      expect(LevelSolver.countRemovalWaves(level), -1);
      expect(LevelSolver.isSolvable(level), isFalse);
    });

    test('parallel removable nodes share one wave', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 5, y: 5, dir: Direction.down),
        ],
      );
      expect(LevelSolver.countRemovalWaves(level), 1);
    });

    test('staggered clears take multiple waves', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [
          NodeData(id: 0, x: 2, y: 2, dir: Direction.right),
          NodeData(id: 1, x: 4, y: 2, dir: Direction.right),
        ],
      );
      expect(LevelSolver.countRemovalWaves(level), 2);
    });
  });

  group('LevelSolver.getHint', () {
    test('returns first extractable node in list order', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [],
      );
      final blocked = NodeData(id: 0, x: 2, y: 2, dir: Direction.down);
      final free = NodeData(id: 1, x: 0, y: 0, dir: Direction.up);
      final wall = NodeData(id: 2, x: 2, y: 3, dir: Direction.left);
      final active = [blocked, free, wall];
      final hint = LevelSolver.getHint(active, level);
      expect(hint?.id, 1);
    });

    test('returns null when nothing is extractable', () {
      final level = LevelData(
        levelId: 1,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [],
      );
      final a = NodeData(id: 0, x: 1, y: 2, dir: Direction.up);
      final b = NodeData(id: 1, x: 1, y: 1, dir: Direction.down);
      expect(LevelSolver.getHint([a, b], level), isNull);
    });

    test('returns null for empty active list', () {
      final level = LevelData(levelId: 1, gridWidth: 3, gridHeight: 3, nodes: []);
      expect(LevelSolver.getHint([], level), isNull);
    });
  });
}
