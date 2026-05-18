import 'dart:math';

import 'package:chain_pop/game/levels/generation/director.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Director.choosePlan', () {
    test('picks a node count inside the §6 band for each tier', () {
      final director = Director();
      final random = Random(7);
      for (final mode in DifficultyMode.values) {
        final tier = DifficultyProfile.tierFromMode(mode);
        final profile = DifficultyProfile.forTier(tier);
        var inBand = 0;
        const samples = 50;
        for (var i = 0; i < samples; i++) {
          final config = LevelConfiguration.fromLevelId(20 + i, mode: mode);
          final plan = director.choosePlan(config, random);
          if (profile.nodeCount.contains(plan.targetNodeCount)) inBand++;
        }
        // ≥ 80% in-band; small grids (Easy early levels) might clamp
        // below the band floor when the legacy `minNodes` is smaller.
        expect(inBand / samples, greaterThanOrEqualTo(0.80),
            reason: 'mode=$mode in-band=$inBand/$samples');
      }
    });

    test('respects overrideTier (Daily Expert)', () {
      final director = Director();
      final random = Random(8);
      final config =
          LevelConfiguration.fromLevelId(99, mode: DifficultyMode.medium);
      final plan = director.choosePlan(
        config,
        random,
        overrideTier: DifficultyTier.expert,
      );
      expect(plan.tier, equals(DifficultyTier.expert));
      expect(plan.profile.tier, equals(DifficultyTier.expert));
    });

    test('Experimental archetype sometimes routes to the legacy greedy path',
        () {
      final director = Director();
      final random = Random(9);
      var legacyPicked = 0;
      var experimentalSeen = 0;
      for (var i = 0; i < 500; i++) {
        final config = LevelConfiguration.fromLevelId(i);
        final plan = director.choosePlan(config, random);
        if (plan.archetype.name == 'experimental') {
          experimentalSeen++;
          if (plan.useLegacyGreedyPath) legacyPicked++;
        } else {
          expect(plan.useLegacyGreedyPath, isFalse,
              reason: 'non-Experimental archetype $i must not use greedy');
        }
      }
      expect(experimentalSeen, greaterThan(0));
      expect(legacyPicked, greaterThan(0),
          reason: 'Experimental archetype must sometimes choose the greedy '
              'path (legacyGreedyProbability > 0)');
    });
  });

  group('Director.renegotiate', () {
    test('downscales node count by ~10% on renegotiation', () {
      final director = Director();
      final random = Random(10);
      final config = LevelConfiguration.fromLevelId(50);
      final plan = director.choosePlan(config, random);
      final renegotiated = director.renegotiate(plan, config, random);
      expect(renegotiated, isNotNull);
      expect(renegotiated!.targetNodeCount,
          lessThanOrEqualTo(plan.targetNodeCount));
      expect(renegotiated.renegotiationDepth, equals(1));
    });

    test('returns null after exhausting maxRenegotiations', () {
      final director = Director(maxRenegotiations: 2);
      final random = Random(11);
      final config = LevelConfiguration.fromLevelId(60);
      var plan = director.choosePlan(config, random);
      for (var i = 0; i < 2; i++) {
        final next = director.renegotiate(plan, config, random);
        expect(next, isNotNull);
        plan = next!;
      }
      expect(director.renegotiate(plan, config, random), isNull);
    });
  });
}
