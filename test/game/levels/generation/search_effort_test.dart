import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/generation/search_effort.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeSearchEffort', () {
    test('empty board has zero effort and is solved', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 4,
        gridHeight: 4,
        nodes: const [],
      );

      final result = computeSearchEffort(level);

      expect(result.solved, isTrue);
      expect(result.searchEffortScore, equals(0));
    });

    test('trivial parallel opening requires low effort', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < 3; i++)
            NodeData(id: i, x: i, y: 0, dir: Direction.up),
        ],
      );

      final result = computeSearchEffort(level);

      expect(result.solved, isTrue);
      expect(result.searchEffortScore, lessThan(10));
      expect(LevelSolver.isSolvable(level), isTrue);
    });

    test('LevelMetrics.compute populates searchEffortScore', () {
      final level = LevelData(
        levelId: 0,
        gridWidth: 6,
        gridHeight: 6,
        nodes: [
          for (var i = 0; i < 4; i++)
            NodeData(id: i, x: i, y: 1, dir: Direction.right),
        ],
      );

      final metrics = LevelMetrics.compute(level);
      final effort = computeSearchEffort(level);

      expect(metrics.searchEffortScore, equals(effort.searchEffortScore));
      expect(metrics.searchEffortScore, greaterThan(0));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // T2.0 — the search must be bounded.
  //
  // computeSearchEffort is a full backtracking search whose `maxTieDepth` does
  // NOT bound it: _dfsTieBreak recurses through _solveState, which re-enters
  // tie-breaking at depth 0, so the counter resets on every commit. Before the
  // caps, campaign L777 Hard spent 6.2 s PER CALL here — 74.4 s of a 74.6 s
  // generation, 99.8% of the total, while the retrograde constructor (long
  // assumed to be the culprit) accounted for 0.1 s.
  //
  // See docs/IMPLEMENTATION_PLAN_V2.md §T2.0.
  // ═════════════════════════════════════════════════════════════════════════
  group('T2.0 search-effort bounding', () {
    test('a known-pathological board is measured in bounded time', () {
      // L777 Hard is the measured worst case. The board itself is fine — it
      // was only ever unaffordable to *measure*.
      final level = LevelGenerator.neutral()
          .generate(777, mode: DifficultyMode.hard)
          .value;

      final sw = Stopwatch()..start();
      final result = computeSearchEffort(level);
      final elapsedMs = sw.elapsedMilliseconds;

      // Pre-T2.0 this single call took ~6200 ms. The cap is 20 ms of search
      // plus the O(depth) unwind; 500 ms is a generous ceiling that still
      // fails loudly if the bound is ever removed.
      expect(elapsedMs, lessThan(500),
          reason: 'computeSearchEffort took ${elapsedMs}ms — the T2.0 cap is '
              'not bounding the search');
      expect(result.expansionCount, greaterThan(0));
    });

    test('caps are honoured and reported', () {
      final level = LevelGenerator.neutral()
          .generate(777, mode: DifficultyMode.hard)
          .value;

      // A deliberately tiny expansion budget must trip the cap, report it,
      // and refuse to claim the board was solved.
      final capped = computeSearchEffort(level, expansionCap: 5);
      expect(capped.capped, isTrue);
      expect(capped.expansionCount, lessThanOrEqualTo(6));
      expect(capped.solved, isFalse,
          reason: 'a capped search must not report solved — it ran out of '
              'budget, it did not prove anything');
    });

    test('boards that finish inside the budget are unaffected by the caps', () {
      // The contract that makes T2.0 board-neutral: anything completing within
      // the caps returns exactly what it always did.
      final level = LevelGenerator.neutral()
          .generate(717, mode: DifficultyMode.hard)
          .value;

      final generous = computeSearchEffort(level,
          expansionCap: 1 << 30, maxMicroseconds: 1 << 30);
      final shipped = computeSearchEffort(level);

      expect(generous.capped, isFalse,
          reason: 'pick a board that genuinely completes, or this proves '
              'nothing');
      expect(shipped.capped, isFalse);
      expect(shipped.expansionCount, equals(generous.expansionCount));
      expect(shipped.backtrackCount, equals(generous.backtrackCount));
      expect(shipped.solved, equals(generous.solved));
    });
  });
}
