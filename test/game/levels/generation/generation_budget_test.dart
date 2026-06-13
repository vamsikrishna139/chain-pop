import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generation time budget', () {
    test('a tiny budget ships a valid, solvable level quickly', () {
      final gen = LevelGenerator();
      // Non-milestone ids (avoid the separate, unbudgeted boss path at %25).
      for (final id in [37, 113, 287, 631, 947]) {
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
        expect(
          sw.elapsedMilliseconds,
          lessThan(500),
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
      // for CI; the real win is the eliminated >1s tail.
      expect(worstMs, lessThan(900), reason: 'worst was ${worstMs}ms');
    });
  });
}
