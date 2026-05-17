import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase-2 acceptance tests for the Quality Evaluator.
///
/// The plan's stated acceptance criteria for Phase 2 are:
///   1. ≥ 90% of emitted levels fall inside their tier's bands
///   2. no Hard level has BF < 2 (the softened-band reviewer rule)
///   3. no level with nodeCount > 28 has FSR > 40%
///
/// **Sequencing note (plan §7 + §9):** until Phase 3 ships, `targetNodeCount`
/// is chosen by the legacy `LevelConfiguration` (Medium ≈ 50 nodes, Hard ≈ 90
/// nodes). §6's bands assume the Director chooses 14–22 / 20–30 nodes
/// instead, so criterion 1 is structurally Phase-3 work. This file asserts
/// criteria 2 and 3 strictly today, smokes that the evaluator is being
/// invoked, and records the current in-band rate as a baseline. The Phase-3
/// test suite will raise the rate-1 bar back to ≥ 0.90 once node counts come
/// from the Director.
void main() {
  group('Evaluator wired into retrograde path', () {
    test('rule 2 — no Hard level has BF < 2 (200 samples)', () {
      final gen = LevelGenerator();
      const samples = 200;
      for (var i = 0; i < samples; i++) {
        final r = gen.generate(30 + i, mode: DifficultyMode.hard);
        expect(r.isSuccess, isTrue);
        final m = LevelMetrics.compute(r.value);
        expect(m.averageBranchingFactor, greaterThanOrEqualTo(2.0),
            reason:
                'Hard generation $i produced BF=${m.averageBranchingFactor}');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
        'rule 3 — no level with nodeCount > 28 has FSR > 40% (covers '
        'Hard + dailies across 400 samples)', () {
      final gen = LevelGenerator();
      const samples = 400;
      for (var i = 0; i < samples; i++) {
        final mode =
            DifficultyMode.values[i % DifficultyMode.values.length];
        final r = gen.generate(i, mode: mode);
        expect(r.isSuccess, isTrue);
        final m = LevelMetrics.compute(r.value);
        if (m.nodeCount > DifficultyProfile.fsrCapNodeThreshold) {
          expect(
              m.forcedSequenceRatio,
              lessThanOrEqualTo(
                  DifficultyProfile.fsrCapValue + 1e-9),
              reason: 'sample $i mode=$mode nodes=${m.nodeCount} '
                  'FSR=${m.forcedSequenceRatio.toStringAsFixed(3)}');
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('rule 1 baseline — evaluator runs and prefers in-band attempts', () {
      // Phase 3 will tighten this. For Phase 2 we verify the evaluator is
      // wired up (in-band counter advances) and capture the current rate.
      final gen = LevelGenerator();
      const samples = 300;
      var inBand = 0;
      for (var i = 0; i < samples; i++) {
        final mode =
            DifficultyMode.values[i % DifficultyMode.values.length];
        final r = gen.generate(i, mode: mode);
        expect(r.isSuccess, isTrue);
        final profile = DifficultyProfile.forTier(
            DifficultyProfile.tierFromMode(mode));
        if (profile.passes(LevelMetrics.compute(r.value))) inBand++;
      }
      expect(gen.retrogradeInBandSuccessCount, greaterThan(0),
          reason: 'evaluator must accept at least some in-band attempts');
      expect(gen.evaluatorRejectionCount, greaterThan(0),
          reason: 'evaluator must reject at least some out-of-band attempts');
      // Baseline: with the legacy `LevelConfiguration` choosing node counts,
      // Easy levels are roughly in-band (≈45%) while Medium/Hard are far over
      // §6 node-count limits. A non-zero rate proves the evaluator is doing
      // something today; Phase 3 raises this back to ≥ 90%.
      expect(inBand, greaterThan(0));
      // ignore: avoid_print
      print('Phase-2 baseline in-band rate: '
          '${(inBand * 100 / samples).toStringAsFixed(1)}%');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('evaluator path still keeps monotone fallback < 5%', () {
      final gen = LevelGenerator();
      const samples = 600;
      for (var i = 0; i < samples; i++) {
        final mode =
            DifficultyMode.values[i % DifficultyMode.values.length];
        gen.generate(i, mode: mode);
      }
      final rate = gen.monotoneFallbackHitCount / samples;
      expect(rate, lessThan(0.05),
          reason: 'monotone fallback rate=${(rate * 100).toStringAsFixed(2)}%');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('every emitted level remains solvable (smoke check)', () {
      final gen = LevelGenerator();
      for (var i = 0; i < 50; i++) {
        final r = gen.generate(i);
        expect(r.isSuccess, isTrue);
        expect(LevelData.layoutValidationMessage(r.value), isNull);
      }
    });

    test('daily challenge targets the Expert band', () {
      final gen = LevelGenerator();
      final before = gen.retrogradeAttemptCount;
      final r = gen.generateDailyChallenge(20260517);
      expect(r.isSuccess, isTrue);
      expect(gen.retrogradeAttemptCount, greaterThan(before),
          reason: 'daily challenge must route through the evaluator');
    });
  });
}
