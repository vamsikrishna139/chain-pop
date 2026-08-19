// T0.4§c — the three machine-checked guards on the frozen adversarial corpus.
//
//   flutter test --tags slow \
//     test/game/levels/generation/adversarial_corpus_guards_test.dart
//
// This is the **only asserting file** in T0.4, and everything it asserts is an
// *invariance*, never a quality bar. Quality gates live in
// `core_triviality_test.dart`; the corpus evaluates and never tunes (§g).
//
// GREEN at baseline, and green is the boring case. The guards exist for the day
// P1 lands, where they answer a question no headline statistic can:
//
//   | what P1 did                                  | headline | guards |
//   |----------------------------------------------|----------|--------|
//   | deeper cores on the same boards              | p50 up   | green  |
//   | inflated node counts                         | p50 up   | RED    |
//   | moved geometry, so the boards aren't the same| p50 up   | RED    |
//
// All three produce the same improved number. Only these guards separate them.
//
// **Why node-count equality is exact, not a tolerance.** `budget.coreCount` is
// consumed only in `level_enrichment.dart`, post-generation, and `directiveFor`
// is read only by star grading and the UI — never by the generator. So across
// all of P1 (T1.1 band, T1.2 floor, T1.3 count 2->3, T1.4 Easy core) node count
// and geometry must be **bit-identical**. A "<=10% median increase" guardrail
// would be far too loose; the assertion is equality, and any delta means P1
// leaked into geometry.
//
// **One intended side effect, pre-recorded so it is not mistaken for a
// regression.** T1.4 moves Easy sector 3+ from `coreCount: 0` to `1`, which
// stops `directiveFor` falling back from `cascade` to `swift`
// (`level_directive.dart`). Star goals change on those levels. That is correct,
// and no guard here watches `directive`.
//
// ignore_for_file: avoid_print

@Tags(['slow'])
library;

import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/generation_version.dart';
import 'package:flutter_test/flutter_test.dart';

import 'adversarial_corpus.dart';
import 'adversarial_corpus_report.dart';
import 'report_sample.dart';

const String _kOutDir = 'docs/playtests/adversarial_baseline';

const Map<CorpusView, String> _kBaselineFiles = {
  CorpusView.mediumSeverity: '$_kOutDir/medium_severity_baseline.csv',
  CorpusView.mediumRepresentative:
      '$_kOutDir/medium_representative_baseline.csv',
  CorpusView.hardControl: '$_kOutDir/hard_control_baseline.csv',
};

void main() {
  group('corpus structure — no generation required', () {
    test('300 boards in three views of 100', () {
      expect(kAdversarialCorpus, hasLength(300));
      for (final v in CorpusView.values) {
        expect(corpusView(v), hasLength(100), reason: '${v.name} view');
      }
    });

    test('all five quintiles populated at n=20', () {
      for (var q = 1; q <= 5; q++) {
        expect(corpusQuintile(q), hasLength(20), reason: 'Q$q');
      }
      expect(kQuintileBoundsAtFreeze, hasLength(5));
      for (final b in kQuintileBoundsAtFreeze) {
        expect(b.poolCount, equals(kAdversarialPoolSize ~/ 5));
      }
      // Rank-based cuts, so quintiles are non-decreasing but may share a
      // boundary value where the pool is tied. Strict separation would be the
      // wrong assertion — it would fail on a healthy corpus.
      for (var i = 1; i < kQuintileBoundsAtFreeze.length; i++) {
        expect(kQuintileBoundsAtFreeze[i].minTaps,
            greaterThanOrEqualTo(kQuintileBoundsAtFreeze[i - 1].minTaps));
      }
    });

    test('severity view keeps the boards the earlier sketch would have cut', () {
      // `docs/playtests/T0_EXIT_GATE.md` proposed restricting Medium to "boards
      // with cores, sectors 3+". T0.3 found the shallowest boards are
      // overwhelmingly sector 2, single-core, and Medium sector 2 keeps
      // `coreCount: 1` after T1.3 — so that filter would have removed exactly
      // the population P1 has to fix. This asserts the filter is absent.
      final severity = corpusView(CorpusView.mediumSeverity);
      final lowSector = severity.where((e) => e.levelId <= 300).length;
      expect(lowSector, greaterThan(0),
          reason: 'no early-sector boards — a sector filter crept in');
      // Q1 is where the pathology lives; it must not be twenty clones.
      final q1Ids = corpusQuintile(1).map((e) => e.levelId).toSet();
      expect(q1Ids, hasLength(20));
    });

    test('the four id sets are mutually disjoint', () {
      // The canary's `kReportSampleIds` were excluded from every draw, so they
      // remain a genuine held-out set for T0.4§g's final validation. If the
      // corpus and the canary shared ids, "validate on data selection never
      // saw" would be false and the anti-overfit sequence would be broken.
      final sets = <String, Set<int>>{
        for (final v in CorpusView.values)
          v.name: corpusView(v).map((e) => e.levelId).toSet(),
        'canary': kReportSampleIds.toSet(),
      };
      for (final a in sets.keys) {
        for (final b in sets.keys) {
          if (a == b) continue;
          expect(sets[a]!.intersection(sets[b]!), isEmpty,
              reason: '$a overlaps $b');
        }
      }
    });

    test('frozen against the running generationVersion', () {
      // Freezing is keyed on `(levelId, mode, generationVersion)`. A bump
      // re-rolls content, so the frozen ids would silently mean different
      // boards and every comparison against the baseline would be nonsense.
      // Fixing this means re-freezing the corpus deliberately, not editing the
      // constant.
      expect(kAdversarialCorpusGenerationVersion, equals(kGenerationVersion),
          reason: 'corpus frozen at v$kAdversarialCorpusGenerationVersion but '
              'the generator is at v$kGenerationVersion — re-freeze, do not '
              'edit the constant');
    });

    test('a baseline exists for every view', () {
      for (final entry in _kBaselineFiles.entries) {
        expect(File(entry.value).existsSync(), isTrue,
            reason: 'missing baseline for ${entry.key.name}: ${entry.value}\n'
                'Run: flutter test --tags report '
                'test/game/levels/generation/'
                'adversarial_corpus_baseline_test.dart');
      }
    });
  });

  group('the three guards', () {
    late Map<String, BaselineRecord> baseline;
    late List<AdversarialRow> current;

    setUpAll(() {
      baseline = <String, BaselineRecord>{};
      for (final path in _kBaselineFiles.values) {
        baseline.addAll(readBaseline(path));
      }
      current = measureCorpus(kAdversarialCorpus);
    });

    test('every frozen board is still present in the baseline', () {
      // A shrunk corpus passes a hash comparison by having nothing to compare,
      // so population size is checked before anything else.
      expect(baseline, hasLength(kAdversarialCorpus.length));
      for (final e in kAdversarialCorpus) {
        expect(baseline.containsKey(e.key), isTrue,
            reason: 'no baseline row for ${e.key}');
      }
    });

    test('guard 1 — geometry identity', () {
      // Node positions, directions, mask, portals. `isCore` is explicitly
      // exempt: the contract is "P1 changed core selection, not puzzle
      // geometry". `kind` and `phaseGroup` are exempt too — lock and relay
      // placement legitimately follow the core set (`_markSpecialNodes` filters
      // on `!n.isCore` and on core rows), so hashing them here would turn an
      // intended consequence of P1 into a red guard.
      final moved = <String>[];
      for (final r in current) {
        final b = baseline[r.entry.key]!;
        if (r.geometryHash != b.geometryHash) {
          moved.add('${r.entry.key}: ${b.geometryHash} -> ${r.geometryHash}');
        }
      }
      expect(moved, isEmpty,
          reason: 'geometry moved on ${moved.length} boards — P1 is specified '
              'to change core selection only:\n${moved.take(10).join("\n")}');
    });

    test('guard 2 — solution-structure identity', () {
      // Wave indices on the mechanic-stripped board. See `solutionHashOf` for
      // why the strip is necessary: `_canRemoveWithSet` short-circuits on
      // locked nodes and phase groups, and lock placement follows the cores, so
      // wave indices on the *enriched* board are not core-independent and this
      // guard would fire on a correct P1.
      final moved = <String>[];
      for (final r in current) {
        final b = baseline[r.entry.key]!;
        if (r.solutionHash != b.solutionHash) {
          moved.add('${r.entry.key}: ${b.solutionHash} -> ${r.solutionHash}');
        }
      }
      expect(moved, isEmpty,
          reason: 'the removal structure of ${moved.length} puzzles changed:\n'
              '${moved.take(10).join("\n")}');
    });

    test('guard 3 — node-count equality, exact', () {
      // The likeliest false positive P1 can produce: node counts inflate, so
      // `coreTapDepth` rises while the cores stay last-popped. F1 intact,
      // hidden behind a better headline number. Equality kills it outright.
      final moved = <String>[];
      for (final r in current) {
        final b = baseline[r.entry.key]!;
        if (r.nodes != b.nodes) {
          moved.add('${r.entry.key}: ${b.nodes} -> ${r.nodes} nodes');
        }
      }
      expect(moved, isEmpty,
          reason: 'node counts moved on ${moved.length} boards. '
              '`budget.coreCount` is consumed only post-generation, so this is '
              'impossible unless something upstream now reads it — find that '
              'before trusting any other number:\n${moved.take(10).join("\n")}');
    });

    test('the achievable-depth ceiling is a geometric invariant', () {
      // The ceiling is computed from `computeRayPrerequisites`, which reads
      // only positions and directions. If it moves while guards 1-3 are green,
      // the ceiling computation itself has changed and every `captureRate` in
      // the baseline is on a different scale from every one after it — a
      // silently incomparable diff.
      final moved = <String>[];
      for (final r in current) {
        final b = baseline[r.entry.key]!;
        if (r.ceiling.ceilingTapDepth != b.ceilingTapDepth) {
          moved.add('${r.entry.key}: ${b.ceilingTapDepth} -> '
              '${r.ceiling.ceilingTapDepth}');
        }
      }
      expect(moved, isEmpty,
          reason: 'ceilings moved on ${moved.length} boards; captureRate is no '
              'longer comparable across the diff:\n${moved.take(10).join("\n")}');
    });
  });

  group('post-P1 classification (T0.4§e)', () {
    // The classifier is exercised here on synthetic records so it is known
    // correct before P1 produces the real ones. Nothing below generates a
    // board; these are unit tests of a decision tree.
    BaselineRecord base({
      int taps = 4,
      int nodes = 18,
      int ceiling = 12,
      String geom = 'G',
      String sol = 'S',
      String coreSet = 'C',
    }) =>
        BaselineRecord(
          levelId: 1,
          mode: DifficultyMode.medium,
          view: 'mediumSeverity',
          quintile: 1,
          severityRank: 1,
          tapsToWin: taps,
          nodes: nodes,
          cores: 2,
          ceilingTapDepth: ceiling,
          captureRate: taps / ceiling,
          geometryHash: geom,
          solutionHash: sol,
          coreSetHash: coreSet,
          contentIdentity: '1/medium/v1/neutral',
        );

    BoardOutcome classify({
      required BaselineRecord b,
      int taps = 10,
      int nodes = 18,
      String geom = 'G',
      String sol = 'S',
      String coreSet = 'C2',
      int ceiling = 12,
      double capture = 0.83,
    }) =>
        classifyBoard(
          baseline: b,
          currentTapsToWin: taps,
          currentNodes: nodes,
          currentGeometryHash: geom,
          currentSolutionHash: sol,
          currentCoreSetHash: coreSet,
          currentCeilingTapDepth: ceiling,
          currentCaptureRate: capture,
          mode: DifficultyMode.medium,
        );

    test('a geometry change invalidates the board, whatever the taps did', () {
      expect(classify(b: base(), geom: 'G2'), BoardOutcome.violation);
    });

    test('a node-count change invalidates the board', () {
      expect(classify(b: base(), nodes: 19), BoardOutcome.violation);
    });

    test('a solution-structure change invalidates the board', () {
      expect(classify(b: base(), sol: 'S2'), BoardOutcome.violation);
    });

    test('violation wins even when the board now looks fixed', () {
      // The impostor this whole file exists for: inflate nodes, watch
      // `tapsToWin` rise, declare victory. The tree checks invariants first.
      expect(classify(b: base(), taps: 14, nodes: 22), BoardOutcome.violation);
    });

    test('at floor with moved cores is FIXED', () {
      expect(classify(b: base(), taps: 6, coreSet: 'C2'), BoardOutcome.fixed);
    });

    test('at floor with the same cores is INCIDENTAL', () {
      expect(classify(b: base(), taps: 6, coreSet: 'C'),
          BoardOutcome.incidental);
    });

    test('below floor on a board that cannot reach it is UNFIXABLE', () {
      expect(
        classify(b: base(ceiling: 4), taps: 4, ceiling: 4, capture: 1.0),
        BoardOutcome.unfixable,
      );
    });

    test('below floor at >=90% capture is SELECTOR-OPTIMAL, BOARD-LIMITED', () {
      // Ceiling 7 clears the floor of 6, so the board was not the hard limit —
      // but the selector took 5 of the 7 available... at 0.95 it is judged to
      // have done its job.
      expect(
        classify(b: base(), taps: 5, ceiling: 7, capture: 0.95),
        BoardOutcome.selectorOptimalBoardLimited,
      );
    });

    test('below floor with depth left on the table is SELECTOR-FAILED', () {
      expect(
        classify(b: base(), taps: 4, ceiling: 14, capture: 0.29),
        BoardOutcome.selectorFailed,
      );
    });

    test('the board-limited threshold is exactly 0.90, inclusive', () {
      expect(
        classify(b: base(), taps: 5, ceiling: 7, capture: 0.90),
        BoardOutcome.selectorOptimalBoardLimited,
      );
      expect(
        classify(b: base(), taps: 5, ceiling: 7, capture: 0.899),
        BoardOutcome.selectorFailed,
      );
    });
  });
}
