import 'package:chain_pop/game/levels/generation/core_metrics.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoreMetrics', () {
    test('F1 pathology: shallow wide board diverges on tap fraction', () {
      // Create a shallow wide board (the F1 pathology).
      // We want many nodes (e.g. 10), but the cores are blocked by only a few.
      // E.g. Cores at y=1, Blockers at y=0, all facing UP.
      // Tapping the blockers clears the way for the cores.
      // Other nodes on the board are completely disconnected from the cores.
      
      final nodes = <NodeData>[
        // The core sequence (depth 2)
        NodeData(id: 0, x: 0, y: 0, dir: Direction.up, isCore: false),
        NodeData(id: 1, x: 0, y: 1, dir: Direction.up, isCore: true),
        
        // A long irrelevant chain (depth 4)
        NodeData(id: 2, x: 1, y: 0, dir: Direction.up, isCore: false),
        NodeData(id: 3, x: 1, y: 1, dir: Direction.up, isCore: false),
        NodeData(id: 4, x: 1, y: 2, dir: Direction.up, isCore: false),
        NodeData(id: 5, x: 1, y: 3, dir: Direction.up, isCore: false),
        
        // More irrelevant parallel noise (all depth 1)
        NodeData(id: 6, x: 2, y: 0, dir: Direction.up, isCore: false),
        NodeData(id: 7, x: 3, y: 0, dir: Direction.up, isCore: false),
        NodeData(id: 8, x: 4, y: 0, dir: Direction.up, isCore: false),
        NodeData(id: 9, x: 5, y: 0, dir: Direction.up, isCore: false),
      ];
      
      final level = LevelData(
        levelId: 1,
        gridWidth: 6,
        gridHeight: 4,
        nodes: nodes,
      );

      final metrics = CoreMetrics.compute(level);
      
      expect(metrics.totalNodes, 10);
      expect(metrics.coreTapDepth, 2); // only node 0 and 1
      expect(metrics.coreTapFraction, 0.2); // 2/10
      expect(metrics.coreIsolation, 0.8); // 8/10
      expect(metrics.coreCriticalDepth, 2);
      
      final waveProfile = computeWavePeelingProfile(level);
      final waveDepth = waveProfile.length;
      expect(waveDepth, 4); // because of the length-4 chain
      
      final coreWaveRatio = metrics.coreCriticalDepth / waveDepth;
      expect(coreWaveRatio, 0.5); // 2 / 4 = 0.5
      
      // The divergence F1 warns about:
      // coreWaveRatio is 0.5, which the legacy engine considers "good",
      // but coreTapFraction is 0.2, showing 80% of the board is irrelevant filler.
    });

    test('deep core dependency: large tap fraction', () {
      // A sequential snake of 5 nodes. Core is at the very end.
      final nodes = <NodeData>[
        NodeData(id: 0, x: 0, y: 0, dir: Direction.left, isCore: false), // unblocked
        NodeData(id: 1, x: 1, y: 0, dir: Direction.left, isCore: false), // blocked by 0
        NodeData(id: 2, x: 2, y: 0, dir: Direction.left, isCore: false), // blocked by 1 (and 0)
        NodeData(id: 3, x: 3, y: 0, dir: Direction.left, isCore: false), // blocked by 2 (and 1, 0)
        NodeData(id: 4, x: 4, y: 0, dir: Direction.left, isCore: true),  // blocked by 3 (and 2, 1, 0)
      ];
      
      final level = LevelData(
        levelId: 2,
        gridWidth: 5,
        gridHeight: 1,
        nodes: nodes,
      );

      final metrics = CoreMetrics.compute(level);
      
      // The core is blocked by all 4 nodes in front of it.
      expect(metrics.coreTapDepth, 5);
      expect(metrics.coreTapFraction, 1.0);
      expect(metrics.coreIsolation, 0.0);
      expect(metrics.coreCriticalDepth, 5);
    });
    test('maxSingleTapCascade counts nodes waiting on exactly one node', () {
      // Node 0 sits at the centre. Nodes 1 and 2 point at it from two
      // different axes with nothing beyond it on their rays, so each has the
      // singleton prerequisite set {0}: removing 0 alone unlocks both.
      //
      // Nodes 3 and 4 sit further out on the same two lines, so their rays
      // pass through 1 and 2 as well — two-element prerequisite sets, which
      // must NOT count towards a single-tap unlock.
      final nodes = <NodeData>[
        NodeData(id: 0, x: 2, y: 2, dir: Direction.right, isCore: true),
        NodeData(id: 1, x: 2, y: 1, dir: Direction.down, isCore: false),
        NodeData(id: 2, x: 1, y: 2, dir: Direction.right, isCore: false),
        NodeData(id: 3, x: 2, y: 0, dir: Direction.down, isCore: false),
        NodeData(id: 4, x: 0, y: 2, dir: Direction.right, isCore: false),
      ];

      final level = LevelData(
        levelId: 3,
        gridWidth: 5,
        gridHeight: 5,
        nodes: nodes,
      );

      final metrics = CoreMetrics.compute(level);

      expect(metrics.maxSingleTapCascade, 2);
      // Node 0 faces right into empty cells, so the core closure is the core
      // alone — the rest of the board is filler by this measure.
      expect(metrics.coreTapDepth, 1);
      expect(metrics.coreTapFraction, 0.2);
      expect(metrics.coreCriticalDepth, 1);
    });

    test('a board with no cores reports a zero closure', () {
      final level = LevelData(
        levelId: 4,
        gridWidth: 2,
        gridHeight: 1,
        nodes: <NodeData>[
          NodeData(id: 0, x: 0, y: 0, dir: Direction.left, isCore: false),
          NodeData(id: 1, x: 1, y: 0, dir: Direction.left, isCore: false),
        ],
      );

      final metrics = CoreMetrics.compute(level);

      expect(metrics.totalNodes, 2);
      expect(metrics.coreTapDepth, 0);
      expect(metrics.coreTapFraction, 0.0);
      expect(metrics.coreIsolation, 1.0);
      expect(metrics.coreCriticalDepth, 0);
    });

    test('an empty board is the empty metric, not a divide by zero', () {
      final level = LevelData(
        levelId: 5,
        gridWidth: 1,
        gridHeight: 1,
        nodes: const <NodeData>[],
      );

      expect(CoreMetrics.compute(level), isA<CoreMetrics>());
      expect(CoreMetrics.compute(level).coreTapFraction, 0.0);
      expect(CoreMetrics.compute(level).totalNodes, 0);
    });

    test('coreCriticalDepth agrees with the shared prerequisite relation', () {
      // Whole-board critical depth is an upper bound on the core-restricted
      // one, and they coincide when the deepest node IS a core. This is the
      // property that guarantees CoreMetrics and computeCriticalUnlockDepth
      // never drift apart on what "prerequisite" means.
      final nodes = <NodeData>[
        NodeData(id: 0, x: 0, y: 0, dir: Direction.left, isCore: false),
        NodeData(id: 1, x: 1, y: 0, dir: Direction.left, isCore: false),
        NodeData(id: 2, x: 2, y: 0, dir: Direction.left, isCore: true),
      ];
      final level = LevelData(
        levelId: 6,
        gridWidth: 3,
        gridHeight: 1,
        nodes: nodes,
      );

      expect(
        CoreMetrics.compute(level).coreCriticalDepth,
        computeCriticalUnlockDepth(level),
      );
    });

  });
}
