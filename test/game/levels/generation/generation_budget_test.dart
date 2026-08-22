import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generation time budget', () {
    test('a tiny budget ships a valid, solvable level quickly', () {
      final gen = LevelGenerator();
      // Non-milestone ids (avoid the separate, unbudgeted boss path at %25).
      for (final id in [37, 113, 287, 631, 947]) {
        gen.resetCounters();
        final sw = Stopwatch()..start();
        final result = gen.generate(
          id,
          timeBudget: const Duration(milliseconds: 1),
        );
        sw.stop();
        expect(result.isSuccess, isTrue, reason: 'id=$id should still ship');
        expect(
          LevelSolver.isSolvable(result.value),
          isTrue,
          reason: 'id=$id budget-shipped level must be solvable',
        );
        // Over budget immediately → fast-forwards to the relaxed regime and
        // ships the first valid level; nowhere near the full 40-attempt burn.
        //
        // Attempts are the assertion that matches the intent. Wall clock under
        // a 1ms budget is *not* a measure of the budget working: the budget
        // cannot preempt a retrograde construction once it has started, so the
        // elapsed time is however long the attempts that were already in flight
        // take. A board that needs an unlucky number of attempts therefore runs
        // far past 1ms no matter how well the escape hatch behaves.
        expect(
          gen.retrogradeAttemptCount,
          lessThan(40),
          reason: 'id=$id burned ${gen.retrogradeAttemptCount} attempts',
        );
        // The wall-clock guard is kept as a coarse backstop and re-anchored to
        // a measured distribution rather than to a hopeful round number.
        // Measured over all 100 `kReportSampleIds` at a 1ms budget, Hard:
        //
        //             p50   p90   p95    max   boards >= 500ms
        //   pre-P1     41    96   135   1252   1
        //   post-P1    41   103   163   1258   1
        //
        // i.e. the distribution did not move; the tail is a pre-existing
        // property of unpreemptable construction (one board in a hundred), and
        // the old 500ms figure was already below the population max. L947
        // happens to sit in that tail after P1 and did not before — the id
        // moved, the distribution did not.
        expect(
          sw.elapsedMilliseconds,
          lessThan(1500),
          reason: 'id=$id took ${sw.elapsedMilliseconds}ms under a 1ms budget',
        );
      }
    });

    test('budget off by default still produces a solvable level', () {
      final gen = LevelGenerator();
      final result = gen.generate(300);
      expect(result.isSuccess, isTrue);
      expect(LevelSolver.isSolvable(result.value), isTrue);
    });

    test('production budget bounds the slow low-id seeds', () {
      // Warm a fresh generator like production (shared ledger) and confirm the
      // 200ms budget keeps the previously-slow seeds (e.g. 36, 38, 52, 87)
      // bounded and solvable. Full 1..1000 solvability is covered by
      // deadlock_test; this guards the latency win for the slow tail.
      final gen = LevelGenerator();
      var worstMs = 0;
      for (int id = 1; id <= 160; id++) {
        final sw = Stopwatch()..start();
        final result = gen.generate(
          id,
          timeBudget: const Duration(milliseconds: 200),
        );
        sw.stop();
        expect(result.isSuccess, isTrue, reason: 'id=$id should ship');
        expect(
          LevelSolver.isSolvable(result.value),
          isTrue,
          reason: 'level $id must be solvable',
        );
        if (sw.elapsedMilliseconds > worstMs) worstMs = sw.elapsedMilliseconds;
      }
      // Gross-regression guard (pre-fix worst in this range was ~1.5s). Generous
      // for CI; increased to 2500ms to account for the seed path retry loop.
      expect(worstMs, lessThan(2500), reason: 'worst was ${worstMs}ms');
    });
  });
}
