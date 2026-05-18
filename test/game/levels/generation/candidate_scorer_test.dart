import 'dart:math';

import 'package:chain_pop/game/levels/generation/candidate_scorer.dart';
import 'package:chain_pop/game/levels/generation/frontier_set.dart';
import 'package:chain_pop/game/levels/generation/sightline_table.dart';
import 'package:chain_pop/game/levels/grid_cell_key.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

Set<int> _fullRect(int w, int h) {
  final out = <int>{};
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out.add(gridCellKey(x, y));
    }
  }
  return out;
}

ConstructionState _stateForEmpty5x5({Set<int>? placed}) {
  final silhouette = _fullRect(5, 5);
  final frontier = FrontierSet(
    gridWidth: 5,
    gridHeight: 5,
    silhouette: silhouette,
  );
  final placedSet = placed ?? <int>{};
  for (final p in placedSet) {
    frontier.addPlaced(p);
  }
  return ConstructionState(
    gridWidth: 5,
    gridHeight: 5,
    silhouette: silhouette,
    placed: placedSet,
    frontier: frontier,
    sightlines: SightlineTable.forGrid(5, 5),
  );
}

void main() {
  group('CandidateScorer', () {
    test('mrvBonus increases as fewer directions are clear', () {
      const scorer = CandidateScorer();
      final state = _stateForEmpty5x5();
      final highMrv = Candidate(
        cellKey: gridCellKey(2, 2),
        cell: const Point(2, 2),
        direction: Direction.up,
        clearDirectionCount: 1,
      );
      final lowMrv = Candidate(
        cellKey: gridCellKey(2, 2),
        cell: const Point(2, 2),
        direction: Direction.up,
        clearDirectionCount: 4,
      );
      final fbHigh = scorer.featureBreakdown(highMrv, state);
      final fbLow = scorer.featureBreakdown(lowMrv, state);
      expect(fbHigh.mrvBonus, greaterThan(fbLow.mrvBonus));
    });

    test('unlockFanout counts only fresh frontier-eligible neighbours', () {
      const scorer = CandidateScorer();
      // Place node (1,1) so that placing (2,2) only unlocks fresh neighbours
      // not already in the frontier from prior placements.
      final state = _stateForEmpty5x5(placed: {gridCellKey(1, 1)});
      final c = Candidate(
        cellKey: gridCellKey(2, 2),
        cell: const Point(2, 2),
        direction: Direction.up,
        clearDirectionCount: 4,
      );
      final fb = scorer.featureBreakdown(c, state);
      // (1,1) is already placed — neighbours (1,2),(2,1),(0,1),(1,0) are
      // already in the frontier. (2,2)'s neighbours (3,2),(2,3) are NOT in
      // the frontier yet — they get unlocked.
      expect(fb.unlockFanout, greaterThan(0));
    });

    test('isolationPenalty fires when neighbours are mostly placed', () {
      const scorer = CandidateScorer();
      // Surround (2,2) with placed cells so its 8-neighbourhood is full.
      final placed = <int>{
        for (var dy = -1; dy <= 1; dy++)
          for (var dx = -1; dx <= 1; dx++)
            if (!(dx == 0 && dy == 0)) gridCellKey(2 + dx, 2 + dy),
      };
      final state = _stateForEmpty5x5(placed: placed);
      final c = Candidate(
        cellKey: gridCellKey(2, 2),
        cell: const Point(2, 2),
        direction: Direction.up,
        clearDirectionCount: 1,
      );
      final fb = scorer.featureBreakdown(c, state);
      expect(fb.isolationPenalty, greaterThan(0));
    });

    test('softmax pick is deterministic with a seeded RNG', () {
      const scorer = CandidateScorer(weights: ScorerWeights(temperature: 1.0));
      final state = _stateForEmpty5x5();
      final candidates = [
        Candidate(
          cellKey: gridCellKey(0, 0),
          cell: const Point(0, 0),
          direction: Direction.right,
          clearDirectionCount: 4,
        ),
        Candidate(
          cellKey: gridCellKey(4, 4),
          cell: const Point(4, 4),
          direction: Direction.left,
          clearDirectionCount: 4,
        ),
      ];
      final first = scorer.pick(candidates, state, Random(42));
      final second = scorer.pick(candidates, state, Random(42));
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.cellKey, equals(second!.cellKey));
    });

    test('pick returns null on empty candidate list', () {
      const scorer = CandidateScorer();
      final state = _stateForEmpty5x5();
      expect(scorer.pick(<Candidate>[], state, Random(1)), isNull);
    });
  });
}
