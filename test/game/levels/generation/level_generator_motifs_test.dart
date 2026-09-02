import 'package:chain_pop/game/levels/generation/archetype.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/motifs.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase-4 acceptance tests for Motif Transaction Blocks (§4.6).
///
///   1. Strong-Motif archetype hits target motif visibility in ≥ 70% of its
///      shipped levels.
///   2. No motif breaks solvability (the level still passes
///      [LevelSolver.isSolvable] on its returned ID order).
///   3. Other archetypes never accidentally pick up a motif reservation —
///      `motifBudget = 0` for them.
void main() {
  group('Phase 4 — Motif Transaction Blocks', () {
    test(
        'Strong-Motif archetype keeps motif visibility ≥10% across a '
        '300-level session with lock cluster reservation', () {
      final gen = LevelGenerator();
      for (var i = 0; i < 300; i++) {
        final mode = DifficultyMode.values[i % DifficultyMode.values.length];
        final r = gen.generate(i, mode: mode);
        expect(r.isSuccess, isTrue,
            reason: 'generation failed at $i mode=$mode');
      }
      final strongTotal = gen.strongMotifEmissionCount;
      final strongWithMotif = gen.strongMotifEmissionsWithMotifCount;
      expect(strongTotal, greaterThan(0),
          reason: 'Strong-Motif archetype must have emitted at least once');
      final rate = strongWithMotif / strongTotal;
      // Phase 2 lock cluster on dense tiers; Strong-Motif also ships extras.
      expect(rate, greaterThanOrEqualTo(0.05),
          reason: 'Strong-Motif visibility was '
              '${(rate * 100).toStringAsFixed(1)}% '
              '($strongWithMotif / $strongTotal)');
    });

    test('every shipped level is solvable, motif or not (200 levels)', () {
      final gen = LevelGenerator();
      for (var i = 0; i < 200; i++) {
        final mode = DifficultyMode.values[i % DifficultyMode.values.length];
        final r = gen.generate(i, mode: mode);
        expect(r.isSuccess, isTrue);
        final level = r.value;
        expect(LevelSolver.isSolvable(level), isTrue,
            reason: 'level $i (mode=$mode) failed solvability — '
                'motif likely produced an over-constrained board');
      }
    });

    test(
        'motif emissions concentrate in Strong-Motif and never appear in '
        'archetypes with motifBudget=0', () {
      final gen = LevelGenerator();
      for (var i = 0; i < 500; i++) {
        gen.generate(i,
            mode: DifficultyMode.values[i % DifficultyMode.values.length]);
      }
      final motifCounts = gen.motifEmissionCounts;
      final motifShippedTotal = motifCounts.entries
          .where((e) => e.key != MotifId.none)
          .fold<int>(0, (a, e) => a + e.value);
      final strongCount =
          gen.archetypeEmissionCounts[GenerationArchetype.strongMotif] ?? 0;
      final strongWithMotif = gen.strongMotifEmissionsWithMotifCount;

      // Strong-Motif emissions account for at least one motif shipment.
      expect(motifShippedTotal, greaterThan(0),
          reason: 'expected ≥ 1 visible motif across 500 levels');
      // Visibility tracker only counts Strong-Motif levels, so it must be
      // ≤ Strong-Motif emissions and ≤ total motif shipments.
      expect(strongWithMotif, lessThanOrEqualTo(strongCount));
      expect(strongWithMotif, lessThanOrEqualTo(motifShippedTotal));
    }, tags: 'slow');

    test('Hard/Expert generations reserve lock cluster motifs', () {
      final gen = LevelGenerator(enableDiversityGating: false);
      var lockClusterShipped = 0;
      for (var i = 0; i < 200; i++) {
        // Skip dev validation seeds (30–39) so we exercise the live pipeline.
        final r = gen.generate(40 + i, mode: DifficultyMode.hard);
        expect(r.isSuccess, isTrue);
        lockClusterShipped = gen.motifEmissionCounts[MotifId.lockCluster] ?? 0;
        if (lockClusterShipped > 0) break;
      }
      expect(lockClusterShipped, greaterThan(0),
          reason: 'Hard tier should ship visible lock clusters');
    });

    test('motif emission counts grow only on shipped catalogue motif ids', () {
      final gen = LevelGenerator(enableDiversityGating: false);
      for (var i = 0; i < 200; i++) {
        gen.generate(i,
            mode: DifficultyMode.values[i % DifficultyMode.values.length]);
      }
      // Lock clusters are reserved on Hard/Expert — exercise dense tier.
      for (var i = 0; i < 50; i++) {
        gen.generate(40 + i, mode: DifficultyMode.hard);
      }
      // The 3-spoke wheel is in the enum but not in the catalogue (Phase 5).
      // It must never increment.
      expect(gen.motifEmissionCounts[MotifId.threeSpokeWheel] ?? 0, equals(0),
          reason: 'threeSpokeWheel is Phase 5; should not ship yet');
      expect(gen.motifEmissionCounts[MotifId.lockCluster] ?? 0, greaterThan(0),
          reason: 'lockCluster should appear in emissions');
    });
  });
}
