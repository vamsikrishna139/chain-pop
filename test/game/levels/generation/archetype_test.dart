import 'dart:math';

import 'package:chain_pop/game/levels/generation/archetype.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GenerationArchetypeSpec.distribution', () {
    test('weights sum to 1.0', () {
      final total = GenerationArchetypeSpec.distribution.values
          .fold<double>(0, (a, b) => a + b);
      expect(total, closeTo(1.0, 1e-9));
    });

    test('sample matches the §5 distribution within ±3% over 5000 draws', () {
      final counts = <GenerationArchetype, int>{
        for (final a in GenerationArchetype.values) a: 0,
      };
      final random = Random(123);
      const n = 5000;
      for (var i = 0; i < n; i++) {
        final a = GenerationArchetypeSpec.sample(random, DifficultyMode.medium);
        counts[a] = counts[a]! + 1;
      }
      GenerationArchetypeSpec.distribution.forEach((arch, expectedShare) {
        final observed = counts[arch]! / n;
        expect((observed - expectedShare).abs(), lessThan(0.03),
            reason:
                'archetype=$arch observed=${observed.toStringAsFixed(3)} '
                'expected=$expectedShare');
      });
    });
  });

  group('forArchetype', () {
    test('Experimental sets a non-zero legacy-greedy probability', () {
      final spec =
          GenerationArchetypeSpec.forArchetype(GenerationArchetype.experimental);
      expect(spec.legacyGreedyProbability, greaterThan(0));
    });

    test('non-Experimental archetypes never use the legacy greedy path', () {
      for (final a in GenerationArchetype.values) {
        if (a == GenerationArchetype.experimental) continue;
        final spec = GenerationArchetypeSpec.forArchetype(a);
        expect(spec.legacyGreedyProbability, equals(0));
      }
    });

    test('every archetype has a non-empty preferredSilhouettes list', () {
      for (final a in GenerationArchetype.values) {
        final spec = GenerationArchetypeSpec.forArchetype(a);
        expect(spec.preferredSilhouettes, isNotEmpty,
            reason: 'archetype=$a has no preferred silhouettes');
      }
    });
  });
}
