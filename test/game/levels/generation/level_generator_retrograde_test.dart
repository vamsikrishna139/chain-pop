import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/level_validator.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase-1 acceptance tests retained as Phase-3+ regression sensors.
///
/// The plan's Phase-1 acceptance was "fallback hit rate drops to <5% across
/// 10k random generations". 10k is too slow for CI; we run 1k spread across
/// modes / level-IDs. The bar still applies in Phase 3 (where the monotone
/// fallback was deleted outright; the counter must therefore stay at 0).
void main() {
  group('LevelGenerator retrograde path (carried into Phase 3+)', () {
    test('produces valid + solvable levels for easy/medium/hard', () {
      final gen = LevelGenerator();
      final validator = LevelValidator();
      for (final mode in DifficultyMode.values) {
        for (final id in const [0, 5, 12, 25, 50, 100, 250, 750]) {
          final result = gen.generate(id, mode: mode);
          expect(result.isSuccess, isTrue, reason: 'mode=$mode id=$id');
          final level = result.value;
          expect(validator.validate(level).isValid, isTrue,
              reason: 'validator failed for mode=$mode id=$id');
          expect(LevelSolver.isSolvable(level), isTrue,
              reason: 'level not solvable for mode=$mode id=$id');
        }
      }
    });

    test(
        'identical output for the same level ID when diversity gating is '
        'disabled (per-level determinism contract)', () {
      final a = LevelGenerator(enableDiversityGating: false);
      final b = LevelGenerator(enableDiversityGating: false);
      for (final id in const [3, 17, 42, 137, 999]) {
        final ra = a.generate(id);
        final rb = b.generate(id);
        expect(ra.isSuccess, isTrue);
        expect(rb.isSuccess, isTrue);
        expect(ra.value.nodes.length, equals(rb.value.nodes.length));
        for (var i = 0; i < ra.value.nodes.length; i++) {
          final na = ra.value.nodes[i];
          final nb = rb.value.nodes[i];
          expect(na.x, equals(nb.x));
          expect(na.y, equals(nb.y));
          expect(na.dir, equals(nb.dir));
        }
      }
    });

    test('monotone fallback counter stays at 0 across 1000 generations '
        '(retired in Phase 3)', () {
      final gen = LevelGenerator();
      const samples = 1000;
      for (var i = 0; i < samples; i++) {
        final mode = DifficultyMode.values[i % DifficultyMode.values.length];
        gen.generate(i, mode: mode);
      }
      expect(gen.monotoneFallbackHitCount, equals(0),
          reason: 'monotone fallback was retired in Phase 3; any non-zero '
              'value means a fallback we forgot to delete re-appeared.');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('retrograde path is the primary route for every emission', () {
      final gen = LevelGenerator();
      for (var i = 0; i < 200; i++) {
        gen.generate(i);
      }
      // Director-driven retrograde should account for at least one attempt
      // per emission; milestones (`_generateMaxDensity` etc.) call back
      // into `_attemptGeneration`, so the counter can be slightly higher
      // than 200 — but never lower.
      expect(gen.retrogradeAttemptCount, greaterThanOrEqualTo(200));
      expect(gen.retrogradeSuccessCount, greaterThan(0));
      expect(gen.legacyAttemptCount, lessThan(gen.retrogradeAttemptCount));
    });
  });
}
