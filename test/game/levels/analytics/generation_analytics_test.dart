import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/archetype.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase-6 acceptance tests (§9 Phase 6).
///
///   1. Default sink is no-op — generator does not crash without analytics.
///   2. Injected [InMemoryAnalyticsSink] receives one event per successful
///      `generate()` call.
///   3. Each event carries archetype, silhouette, metrics, and fingerprint.
///   4. `snapshotSession` mirrors the live counters and is forwarded to
///      sinks via `analyticsSink.snapshot(...)` only when the host explicitly
///      asks for it (per the lightweight-by-design scope).
///   5. `InMemoryAnalyticsSink.archetypeInBandRate` produces a per-archetype
///      QA breakdown — the artifact the plan calls out.
void main() {
  group('Phase 6 — Generation analytics', () {
    test('default sink is no-op and does not affect generation', () {
      final gen = LevelGenerator();
      for (var i = 0; i < 20; i++) {
        final r = gen.generate(i,
            mode: DifficultyMode.values[i % DifficultyMode.values.length]);
        expect(r.isSuccess, isTrue);
      }
      // Reaching here means no exceptions and the snapshot helper works.
      final snap = gen.snapshotSession();
      expect(snap.totalEmissions, equals(20));
    });

    test('in-memory sink receives one event per successful emission', () {
      final sink = InMemoryAnalyticsSink();
      final gen = LevelGenerator(analyticsSink: sink);
      for (var i = 0; i < 30; i++) {
        final r = gen.generate(i,
            mode: DifficultyMode.values[i % DifficultyMode.values.length]);
        expect(r.isSuccess, isTrue);
      }
      expect(sink.events.length, equals(30));
      for (final e in sink.events) {
        expect(e.archetype, isA<GenerationArchetype>());
        expect(e.silhouette, isNotNull);
        expect(e.metrics.nodeCount, greaterThan(0));
        expect(e.fingerprint.bits, isA<int>());
      }
    });

    test('per-archetype in-band rate report (QA breakdown)', () {
      final sink = InMemoryAnalyticsSink();
      final gen = LevelGenerator(analyticsSink: sink);
      for (var i = 0; i < 200; i++) {
        gen.generate(i,
            mode: DifficultyMode.values[i % DifficultyMode.values.length]);
      }
      final rates = sink.archetypeInBandRate();
      expect(rates, isNotEmpty);
      for (final entry in rates.entries) {
        expect(entry.value, inInclusiveRange(0.0, 1.0),
            reason: 'archetype=${entry.key} rate=${entry.value}');
      }
    });

    test('session snapshot mirrors live counters', () {
      final gen = LevelGenerator();
      for (var i = 0; i < 50; i++) {
        gen.generate(i,
            mode: DifficultyMode.values[i % DifficultyMode.values.length]);
      }
      final snap = gen.snapshotSession();
      expect(snap.totalEmissions, equals(50));
      expect(snap.retrogradeAttempts,
          greaterThanOrEqualTo(gen.retrogradeAttemptCount));
      // strongMotifVisibilityRate is null only when no Strong-Motif level
      // has shipped yet; with 50 emissions that's extremely unlikely.
      if (snap.strongMotifEmissions > 0) {
        expect(snap.strongMotifVisibilityRate, isNotNull);
        expect(snap.strongMotifVisibilityRate!,
            inInclusiveRange(0.0, 1.0));
      }
    });

    test('seeded levels carry their seedId in the event', () {
      final sink = InMemoryAnalyticsSink();
      final gen = LevelGenerator(analyticsSink: sink);
      // Levels 1, 2, 3 are pinned to the opening seeds.
      gen.generate(1);
      gen.generate(2);
      gen.generate(3);
      final ids = sink.events
          .where((e) => e.seedId != null)
          .map((e) => e.seedId)
          .toList();
      expect(ids, containsAll(['opening-1', 'opening-2', 'opening-3']));
    });

    test('event.toMap is JSON-friendly', () {
      final sink = InMemoryAnalyticsSink();
      final gen = LevelGenerator(analyticsSink: sink);
      gen.generate(10);
      expect(sink.events, isNotEmpty);
      final map = sink.events.first.toMap();
      expect(map['levelId'], isA<int>());
      expect(map['archetype'], isA<String>());
      expect(map['silhouette'], isA<String>());
      expect(map['inBand'], isA<bool>());
    });
  });
}
