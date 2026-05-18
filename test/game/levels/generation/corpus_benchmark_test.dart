import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/archetype.dart';
import 'package:chain_pop/game/levels/generation/director.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus_benchmark_utils.dart';

/// Corpus-scale Hard-mode smoke + diversity diagnostics for CI logs (Phase A).
///
/// **Hard milestones** mirror [LevelGenerator] (`_getMilestoneType`): after
/// [levelId] ≥ `25`, `levelId % 100 == 0` activates the sparse sniper capsule
/// and `levelId % 100 == 50` activates the max-density pass. Levels `25` and
/// `75 mod 100` are handled by seeded diamonds/rings elsewhere.
///
/// For each emission we observe [InMemoryAnalyticsSink]. When a milestone
/// still shares the Director telemetry path **and** emits analytics, deltas
/// line up exactly with non-milestone cadence. Levels that unexpectedly skip
/// an emission are surfaced through [zeroDeltaLevels] diagnostics.
///
/// Rolling **Hamming** summaries operate on emitted `fingerprint.bits` alone
/// with a deque matching [DiversityLedger]'s §4.5 window size (`20`).
void main() {
  group('Corpus benchmark — Hard-mode diversity smoke', () {
    test('N=100 + local metrics + Hamming rolling summary', () {
      _runSequentialCorpusHard(levels: 100, expectArchipelago: false);
    });

    test('N=500 + histogram invariants', () {
      _runSequentialCorpusHard(levels: 500, expectArchipelago: true);
    });
  });

  group('Milestone telemetry seed annotations', () {
    test('milestone:maxDensity on synthetic max-density IDs', () {
      final sink = InMemoryAnalyticsSink();
      LevelGenerator(analyticsSink: sink)
          .generate(150, mode: DifficultyMode.hard);
      expect(sink.events, hasLength(1));
      expect(sink.events.single.seedId, 'milestone:maxDensity');
    });

    test('milestone:sparseSniper every hundred on Hard', () {
      final sink = InMemoryAnalyticsSink();
      LevelGenerator(analyticsSink: sink)
          .generate(300, mode: DifficultyMode.hard);
      expect(sink.events, hasLength(1));
      expect(sink.events.single.seedId, 'milestone:sparseSniper');
    });
  });
}

void _runSequentialCorpusHard({
  required int levels,
  required bool expectArchipelago,
}) {
  final sink = InMemoryAnalyticsSink();
  final maskAttempts = <SilhouetteId>[];
  final gen = LevelGenerator(
    analyticsSink: sink,
    director: Director(
      onMaskRectangleFallback: (attempted, resolved) {
        maskAttempts.add(attempted);
        expect(resolved, SilhouetteId.rectangle,
            reason: 'rectangle fallback is the authorised full-mask shape');
      },
    ),
  );

  final zeroDeltaLevels = <int>[];
  for (var levelId = 0; levelId < levels; levelId++) {
    final before = sink.events.length;
    final r =
        gen.generate(levelId, mode: DifficultyMode.hard); // deterministic id
    expect(r.isSuccess, isTrue, reason: 'level $levelId must ship');

    // Milestone bookkeeping: correlate planned ids vs analytics cadence.
    final after = sink.events.length;
    if (after == before) {
      zeroDeltaLevels.add(levelId);
      expect(
        matchesHardSyntheticMilestoneId(levelId),
        isFalse,
        reason:
            '$levelId had no telemetry despite successful generate — regressions?',
      );
    }
  }

  expect(sink.events.length, equals(levels),
      reason: 'exactly one analytics emission per shipped level');

  if (maskAttempts.isNotEmpty) {
    // ignore: avoid_print
    print(
        'Director mask rectangle fallback attempts (${maskAttempts.length}): '
        '${silhouetteTallyPretty(maskAttempts)}');
  } else {
    // ignore: avoid_print
    print('Director mask fallback audit: none (buildSilhouetteMask clean).');
  }

  if (zeroDeltaLevels.isNotEmpty) {
    // ignore: avoid_print
    print('Levels with telemetry delta 0 (unexpected unless generator skips analytics): '
        '$zeroDeltaLevels');
  }

  final ids = silhouetteIdHistogram(sink.events);
  final macros = silhouetteMacroHistogram(sink.events);
  expect(macros[SilhouetteVisualFamily.geometricLattice],
      greaterThanOrEqualTo(10),
      reason: 'geometric lattice should dominate large portions of corpus');
  if (expectArchipelago) {
    expect(macros[SilhouetteVisualFamily.archipelago], greaterThan(0));
    expect(macros[SilhouetteVisualFamily.corridor], greaterThan(0));
    expect(macros[SilhouetteVisualFamily.organic], greaterThan(0));
  }

  // ignore: avoid_print
  print('Silhouette histogram (counts): ${_pretty(ids)}');

  // Archetype distribution — mirrors Phase-6 QA expectations.
  final arch = <GenerationArchetype, int>{};
  for (final e in sink.events) {
    arch[e.archetype] = (arch[e.archetype] ?? 0) + 1;
  }
  // ignore: avoid_print
  print('Archetype histogram: ${_prettyArchetypes(arch)}');

  // Streak summaries for silhouette primitives + coarse macro buckets.
  final silStreak =
      streakDistribution(sink.events.map((e) => e.silhouette).toList());
  final macroStreak = streakDistribution(macroSequence(sink.events));
  // ignore: avoid_print
  print('Silhouette streaks max=${silStreak['max']} hist=${silStreak['histogram']}');
  // ignore: avoid_print
  print('Macro streaks max=${macroStreak['max']} hist=${macroStreak['histogram']}');

  final macroSeq = macroSequence(sink.events);
  const windowsToSummarize = <int>[5, 10, 20];
  for (final w in windowsToSummarize) {
    final stats = macroBucketWindowStats(macroSequence: macroSeq, window: w);
    // ignore: avoid_print
    print(
        'Macro sliding W=$w: minDistinct=${stats.minDistinct} '
        'maxDistinct=${stats.maxDistinct} avg=${stats.avgDistinct.toStringAsFixed(2)} '
        'pureLatticeWindows=${stats.latticeOnlyWindows}');

    expect(stats.avgDistinct,
        greaterThan(1.0),
        reason: 'Hard corpus should roam multiple macro visuals by W=$w'); // heuristic
    if (levels >= 200) {
      expect(stats.latticeOnlyWindows, lessThan(macroSeq.length - w),
          reason: 'expect some temporal mixing beyond pure lattice streaks');
    }
  }

  final bits =
      sink.events.map((e) => e.fingerprint.bits).toList(growable: false);
  final hamm = rollingMinHammingDistances(fingerprintBits: bits);

  // Raw XOR distances trail the live §4.5 gate because the ledger applies
  // silhouette-family tightening (threshold 5 plus margin 3 for recent matches).
  // ignore: avoid_print
  print(
      'Rolling min-Hamming XOR (window=$kDiversityFingerprintWindowSize prior emissions): '
      'median=${hamm.median.toStringAsFixed(2)} '
      'p90=${hamm.p90.toStringAsFixed(2)} '
      '(samples=${hamm.minDistances.length}; '
      'ledger reference thresholds: base=5 tightened=8)');
  expect(
    hamm.median,
    greaterThanOrEqualTo(2),
    reason: 'keep a nonzero XOR spread versus the deque (empirical smoke)',
  );
  expect(
    hamm.p90,
    greaterThanOrEqualTo(5),
    reason:
        'bulk of tail should brush the XOR distance implied by silhouette bits alone',
  );
}

String _pretty(Map<SilhouetteId, int> ids) =>
    {for (final e in ids.entries) e.key.name: e.value}.toString();

String _prettyArchetypes(Map<GenerationArchetype, int> m) =>
    {for (final e in m.entries) e.key.name: e.value}.toString();

String silhouetteTallyPretty(List<SilhouetteId> silhouettes) {
  final tally = <SilhouetteId, int>{};
  for (final s in silhouettes) {
    tally[s] = (tally[s] ?? 0) + 1;
  }
  return {for (final e in tally.entries) e.key.name: e.value}.toString();
}

/*
 * ─── Playtest gate (manual QA) ─────────────────────────────────────────────
 *
 * ☑ Snapshot a grid/screenshot collage for milestones (ids ending in `:50`
 *   densification and `:00` sparse sniper) versus typical Hard boards.
 *
 * ☑ Run five fresh player playtests noting perceived rhythm + silhouette
 *   readability (organic vs lattice stretches).
 *
 * ☑ Confirm CI rolling Hamming / macro-window prints stay bounded after
 *   tuning Director weights — watch for creeping `pureLatticeWindows`.
 */
