import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

LevelData _trivialThreeNodeLine() {
  // 5x1 board, three nodes all shooting left → straightforward chain.
  //   id 0 at (0,0) shoots left  (already at the edge)
  //   id 1 at (1,0) shoots left  (clear once id 0 is gone)
  //   id 2 at (2,0) shoots left  (clear once 0+1 are gone)
  return LevelData(
    levelId: 0,
    gridWidth: 5,
    gridHeight: 1,
    nodes: [
      NodeData(id: 0, x: 0, y: 0, dir: Direction.left),
      NodeData(id: 1, x: 1, y: 0, dir: Direction.left),
      NodeData(id: 2, x: 2, y: 0, dir: Direction.left),
    ],
  );
}

void main() {
  group('tempoProfile', () {
    test('empty level → empty profile', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 4,
        gridHeight: 4,
        nodes: const [],
      );
      expect(computeTempoProfile(level), isEmpty);
    });

    test('three-node line: forced sequence with one legal move per step', () {
      final tempo = computeTempoProfile(_trivialThreeNodeLine());
      // Each step only the leftmost remaining node is removable.
      expect(tempo, equals([1, 1, 1]));
    });

    test('two parallel chains: first step has two legal moves', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 5,
        gridHeight: 3,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.left),
          NodeData(id: 1, x: 0, y: 2, dir: Direction.left),
          NodeData(id: 2, x: 1, y: 0, dir: Direction.left),
          NodeData(id: 3, x: 1, y: 2, dir: Direction.left),
        ],
      );
      final tempo = computeTempoProfile(level);
      expect(tempo.first, equals(2),
          reason: 'two top-row chains both have a free leftmost node');
    });
  });

  group('criticalUnlockDepth', () {
    test('forced three-node line → depth 3', () {
      expect(computeCriticalUnlockDepth(_trivialThreeNodeLine()), equals(3));
    });

    test('independent nodes have depth 1', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 4, y: 0, dir: Direction.up),
        ],
      );
      expect(computeCriticalUnlockDepth(level), equals(1));
    });
  });

  group('viablePathCount', () {
    test('forced line has exactly one viable sequence', () {
      final r = computeViablePathCount(_trivialThreeNodeLine());
      expect(r.$1, equals(1));
      expect(r.$2, isFalse);
    });

    test('two independent nodes → 2 orderings', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 5,
        gridHeight: 5,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 4, y: 4, dir: Direction.down),
        ],
      );
      final r = computeViablePathCount(level);
      expect(r.$1, equals(2));
      expect(r.$2, isFalse);
    });

    test('hitting the branch cap reports capped=true', () {
      // Three independent nodes → 3! = 6 orderings; cap at 2 → capped.
      final level = LevelData(
        levelId: 0,
        gridWidth: 7,
        gridHeight: 7,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 6, y: 0, dir: Direction.up),
          NodeData(id: 2, x: 0, y: 6, dir: Direction.down),
        ],
      );
      final r = computeViablePathCount(level, branchCap: 2);
      expect(r.$1, equals(2));
      expect(r.$2, isTrue);
    });
  });

  group('LevelMetrics.compute', () {
    test('derived numbers match the underlying tempo', () {
      final level = _trivialThreeNodeLine();
      final m = LevelMetrics.compute(level);
      expect(m.nodeCount, equals(3));
      expect(m.firstLegalMoveCount, equals(1));
      expect(m.averageBranchingFactor, closeTo(1.0, 1e-9));
      expect(m.forcedSequenceRatio, closeTo(1.0, 1e-9));
      expect(m.frontierVariance, closeTo(0.0, 1e-9));
      expect(m.tempoProfile, equals([1, 1, 1]));
      expect(m.viablePathCount, equals(-1),
          reason: 'viable path opt-in; default off');
    });

    test('bailOutOnTime can cap viable-path search early', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 7,
        gridHeight: 7,
        nodes: [
          NodeData(id: 0, x: 0, y: 0, dir: Direction.up),
          NodeData(id: 1, x: 6, y: 0, dir: Direction.up),
          NodeData(id: 2, x: 0, y: 6, dir: Direction.down),
        ],
      );
      final fast = computeViablePathCount(
        level,
        branchCap: 64,
        expansionCap: 6000,
        bailOutOnTime: true,
        maxMicroseconds: 0,
      );
      expect(fast.$2, isTrue);
    });
  });
}
