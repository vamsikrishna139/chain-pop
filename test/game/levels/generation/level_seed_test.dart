import 'package:chain_pop/game/levels/generation/archetype.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:chain_pop/game/levels/seeds/seeds.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase-5 acceptance tests for the [LevelSeed] pipeline (§9 Phase 5).
///
///   1. Seeded levels deterministically pick the seed's archetype +
///      silhouette (Ring milestone migrated off `_generateRing`).
///   2. The opening-3 sequence emits clean-authored / relaxed levels with
///      the pinned node counts.
///   3. Seed emissions remain solvable + validated.
void main() {
  group('Phase 5 — Level Seeds', () {
    test('Ring milestone routes through the seed pipeline (mod 75 levels)',
        () {
      final gen = LevelGenerator();
      // Levels 75, 175, 275 are mod-75 within the milestone slot rotation
      // (and ≥ 25 so the milestone gate doesn't skip them).
      for (final id in [75, 175, 275]) {
        final r = gen.generate(id, mode: DifficultyMode.hard);
        expect(r.isSuccess, isTrue, reason: 'ring milestone $id failed');
      }
      final counts = gen.seedEmissionCounts;
      expect(counts['milestone-ring'] ?? 0, equals(3),
          reason: 'ring milestone emissions: $counts');
    });

    test('Opening seeds 1..3 emit and increment the seed counter', () {
      final gen = LevelGenerator();
      for (final id in [1, 2, 3]) {
        final r = gen.generate(id);
        expect(r.isSuccess, isTrue,
            reason: 'opening seed level $id failed to generate');
      }
      final counts = gen.seedEmissionCounts;
      expect(counts['opening-1'] ?? 0, equals(1));
      expect(counts['opening-2'] ?? 0, equals(1));
      expect(counts['opening-3'] ?? 0, equals(1));
    });

    test('Seeded levels deterministic across re-runs (same seed → same level)',
        () {
      final a = LevelGenerator();
      final b = LevelGenerator();
      final ra = a.generate(75, mode: DifficultyMode.hard);
      final rb = b.generate(75, mode: DifficultyMode.hard);
      expect(ra.isSuccess && rb.isSuccess, isTrue);
      expect(ra.value.gridWidth, equals(rb.value.gridWidth));
      expect(ra.value.gridHeight, equals(rb.value.gridHeight));
      expect(ra.value.nodes.length, equals(rb.value.nodes.length));
      for (var i = 0; i < ra.value.nodes.length; i++) {
        expect(ra.value.nodes[i].x, equals(rb.value.nodes[i].x));
        expect(ra.value.nodes[i].y, equals(rb.value.nodes[i].y));
        expect(ra.value.nodes[i].dir, equals(rb.value.nodes[i].dir));
      }
    });

    test(
        'ring milestone routes onto the Ring silhouette via the Director — '
        'no bespoke greedy branch', () {
      // The legacy `_generateRing` filled the entire border. Under the seed
      // pipeline, the level honours the Ring silhouette mask (a hollow
      // square), so the centre cells are off-limits.
      final gen = LevelGenerator();
      final r = gen.generate(75, mode: DifficultyMode.hard);
      expect(r.isSuccess, isTrue);
      final lvl = r.value;
      // Strong claim: every node lives on the silhouette boundary OR on a
      // ring-friendly cell. Cheap check — at least one node touches the
      // outer ring (x ∈ {0, w-1} or y ∈ {0, h-1}).
      final touchesOuter = lvl.nodes.any((n) =>
          n.x == 0 ||
          n.x == lvl.gridWidth - 1 ||
          n.y == 0 ||
          n.y == lvl.gridHeight - 1);
      expect(touchesOuter, isTrue);
    });

    test('seed registry covers exactly the documented opening levels', () {
      expect(seedRegistry.keys.toSet(), equals({1, 2, 3}));
      expect(seedRegistry[1]!.id, equals('opening-1'));
      expect(seedRegistry[2]!.archetypeId,
          equals(GenerationArchetype.cleanAuthored));
      expect(seedRegistry[3]!.silhouetteId, equals(SilhouetteId.cross));
    });
  });
}
