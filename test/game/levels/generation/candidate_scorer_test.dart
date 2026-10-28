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
      final scorer = CandidateScorer();
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
      final scorer = CandidateScorer();
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
      final scorer = CandidateScorer();
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
      final scorer =
          CandidateScorer(weights: const ScorerWeights(temperature: 1.0));
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
      final scorer = CandidateScorer();
      final state = _stateForEmpty5x5();
      expect(scorer.pick(<Candidate>[], state, Random(1)), isNull);
    });

    test('ray intercept bonus beats row/col cross-block in crunch zone', () {
      final scorer = CandidateScorer(
        weights: const ScorerWeights(
          unlockFanout: 0,
          mrvBonus: 0,
          isolationPenalty: 0,
        ),
      );
      // Row-aligned but ray-clear: (2,0) blocks down from (2,2) only via row,
      // not via ray in direction right.
      final placed = <int>{gridCellKey(2, 0), gridCellKey(0, 2)};
      final state = _stateForEmpty5x5(placed: placed);
      final clearCandidate = Candidate(
        cellKey: gridCellKey(2, 2),
        cell: const Point(2, 2),
        direction: Direction.right,
        clearDirectionCount: 2,
        isBlockingRay: false,
      );
      final blockingCandidate = Candidate(
        cellKey: gridCellKey(2, 2),
        cell: const Point(2, 2),
        direction: Direction.up,
        clearDirectionCount: 2,
        isBlockingRay: true,
      );

      expect(
        crossBlockCountAt(2, 2, [
          const Point(2, 0),
          const Point(0, 2),
        ]),
        equals(2),
      );
      expect(
        rayInterceptCount(
          const Point(2, 2),
          Direction.up,
          [const Point(2, 0), const Point(0, 2)],
          5,
          5,
        ),
        equals(1),
      );

      double scoreAt(double occ, Candidate c) => scorer.score(
            c,
            ConstructionState(
              gridWidth: state.gridWidth,
              gridHeight: state.gridHeight,
              silhouette: state.silhouette,
              placed: state.placed,
              frontier: state.frontier,
              sightlines: state.sightlines,
              occupancyRatio: occ,
            ),
          );

      expect(scoreAt(0.50, clearCandidate), equals(0.0));
      expect(
        scoreAt(0.50, blockingCandidate),
        greaterThan(scoreAt(0.50, clearCandidate)),
      );
      expect(scoreAt(0.70, blockingCandidate), lessThan(0.0));
    });

    test('crunch pre-filter biases toward blocking rays', () {
      final scorer = CandidateScorer(
        weights: const ScorerWeights(
          unlockFanout: 0,
          mrvBonus: 0,
          isolationPenalty: 0,
          temperature: 0.01,
        ),
        crunchBlockingProbability: 1.0,
      );
      final state = ConstructionState(
        gridWidth: 5,
        gridHeight: 5,
        silhouette: _fullRect(5, 5),
        placed: {gridCellKey(2, 2)},
        frontier: FrontierSet(
          gridWidth: 5,
          gridHeight: 5,
          silhouette: _fullRect(5, 5),
        )..addPlaced(gridCellKey(2, 2)),
        sightlines: SightlineTable.forGrid(5, 5),
        occupancyRatio: 0.50,
      );
      final candidates = [
        Candidate(
          cellKey: gridCellKey(1, 2),
          cell: const Point(1, 2),
          direction: Direction.up,
          clearDirectionCount: 1,
          isBlockingRay: false,
        ),
        Candidate(
          cellKey: gridCellKey(3, 2),
          cell: const Point(3, 2),
          direction: Direction.left,
          clearDirectionCount: 1,
          isBlockingRay: true,
        ),
      ];
      final picked = scorer.pick(candidates, state, Random(0));
      expect(picked?.isBlockingRay, isTrue);
      expect(scorer.blockingDirCandidatesPicked, equals(1));
    });
  });
}
