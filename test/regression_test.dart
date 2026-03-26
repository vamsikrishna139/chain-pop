import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level_generator.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:chain_pop/game/levels/level.dart';

void main() {
  // The old regression tests hard-coded specific node IDs, but levels are now
  // procedurally generated with a seeded RNG.  Instead of testing exact node
  // sequences, we verify the full solution path by:
  //   1. Generating the level.
  //   2. Simulating the known-good path: remove nodes in ascending ID order
  //      (that is the solution order the generator encodes by construction).
  //   3. Asserting every step is valid and the board empties completely.

  group('Regression Tests - Levels 1 to 5 Playthroughs', () {
    void simulateSolutionPath(int levelId) {
      final level = LevelGenerator.generate(levelId);
      final activeNodes = level.nodes.map((n) => n.clone()).toList();

      // Solution path = node IDs in ascending order (0, 1, 2, ...)
      final solutionOrder = List<NodeData>.from(activeNodes)
        ..sort((a, b) => a.id.compareTo(b.id));

      for (int step = 0; step < solutionOrder.length; step++) {
        final target = solutionOrder[step];
        // Find the live instance in activeNodes
        final liveNode = activeNodes.firstWhere((n) => n.id == target.id);

        expect(
          LevelSolver.canRemove(liveNode, activeNodes),
          isTrue,
          reason: 'Level $levelId: node ${liveNode.id} blocked at step $step',
        );

        activeNodes.removeWhere((n) => n.id == liveNode.id);
      }

      expect(
        activeNodes,
        isEmpty,
        reason: 'Level $levelId: board not empty after solution path',
      );
    }

    test('Level 1 Playthrough', () => simulateSolutionPath(1));
    test('Level 2 Playthrough', () => simulateSolutionPath(2));
    test('Level 3 Playthrough', () => simulateSolutionPath(3));
    test('Level 4 Playthrough', () => simulateSolutionPath(4));
    test('Level 5 Playthrough', () => simulateSolutionPath(5));
  });
}
