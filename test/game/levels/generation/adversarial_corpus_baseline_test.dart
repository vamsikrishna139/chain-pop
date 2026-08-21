// T0.4 — the baseline capture for the frozen adversarial corpus.
//
//   flutter test --tags report \
//     test/game/levels/generation/adversarial_corpus_baseline_test.dart
//
// Generates and measures all 300 frozen boards, computes the §d achievable-
// depth ceiling for each, and writes the three baseline CSVs. It **asserts
// nothing about quality**, by construction: this is the evidence layer (§0.5).
// The only asserting file in T0.4 is `adversarial_corpus_guards_test.dart`, and
// it asserts invariance, never quality.
//
// The corpus evaluates; it never tunes (T0.4§g). If a threshold in this file
// ever moves after someone has looked at which frozen ids failed, the
// instrument has become an optimiser and the result is void. The held-out
// sequence is:
//
//     freeze corpus -> T1.1-T1.4 -> evaluate frozen corpus
//                   -> the canary's kReportSampleIds (never seen by selection)
//                   -> one fresh draw -> final validation
//
// Re-running this test **after** P1 overwrites the committed baseline. That is
// intentional and is how the diff is produced — but the baseline must be
// committed to git first, or the before/after comparison is gone.
//
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/generation_version.dart';
import 'package:flutter_test/flutter_test.dart';

import 'adversarial_corpus.dart';
import 'adversarial_corpus_report.dart';
import 'corpus_version.dart';
import 'report_sample.dart';

const String _kOutDir = 'docs/playtests/adversarial_baseline';

void main() {
  test('T0.4 — capture the adversarial corpus baseline', () {
    printCorpusVersionBanner('T0.4 ADVERSARIAL BASELINE');
    print('  adversarialCorpusVersion : $kAdversarialCorpusVersion');
    print('  frozen at generationVersion: '
        '$kAdversarialCorpusGenerationVersion (now $kGenerationVersion)');
    print('  pool seed $kAdversarialPoolSeed, '
        'canary seed $kReportSampleSeed (held out)');
    print('  timeBudget: null — determinism contract (T0.0a)');
    print('  boards: ${kAdversarialCorpus.length}');

    final rows = measureCorpus(
      kAdversarialCorpus,
      onProgress: (done, total) {
        if (done % 50 == 0) print('    measured $done/$total');
      },
    );

    final severity =
        rows.where((r) => r.entry.view == CorpusView.mediumSeverity).toList();
    final representative = rows
        .where((r) => r.entry.view == CorpusView.mediumRepresentative)
        .toList();
    final hard =
        rows.where((r) => r.entry.view == CorpusView.hardControl).toList();

    // ── Order-independence, proven rather than assumed ─────────────────────
    //
    // The selection sweep visited these ids in ascending order inside a
    // 600-board Medium pool; this sweep visits them in corpus order, mixed with
    // Hard boards. `freezeNodes` was recorded there and is re-measured here. If
    // they agree, the board really is a function of
    // `(levelId, mode, generationVersion)` and the T0.4§b freeze key is
    // well-defined.
    //
    // The first version of this run used a single shared `LevelGenerator` and
    // this check would have failed: the diversity ledger and the silhouette
    // tracker are session state (T0.0a), so a reused instance makes the board a
    // function of the whole preceding sequence. L1411 came out at 17 nodes in
    // one order and 18 in the other. `measureEntry` now builds a fresh
    // `LevelGenerator.neutral()` per board.
    //
    // Node count is the right quantity to check — with one correction that P1
    // forced. The paragraph above used to end "`budget.coreCount` is consumed
    // only post-generation, so it is invariant across all of P1". That is true
    // of `budget.coreCount` and false of the *board*: enrichment runs inside
    // the generator's accept/reject loop, so changing which nodes are cores
    // changes lock and relay placement and can change which candidate survives
    // validation. See `kP1GeometryMovers` for the full argument and the 42
    // boards it moved.
    //
    // Those boards are named rather than tolerated. Drift on anything else is
    // still a failure, which is the only reason this check is still worth
    // running.
    final drift = <String>[];
    for (final r in rows) {
      if (r.entry.freezeNodes == 0) continue;
      if (kP1GeometryMovers.contains(r.entry.key)) continue;
      if (r.entry.freezeNodes != r.nodes) {
        drift.add('${r.entry.key}: freeze ${r.entry.freezeNodes} '
            'nodes vs measured ${r.nodes}');
      }
    }
    print('\n===== ORDER INDEPENDENCE (freeze vs baseline node counts) =====');
    print('  checked ${rows.where((r) => r.entry.freezeNodes > 0).length} '
        'severity boards, ${drift.length} disagreed');
    for (final d in drift.take(20)) {
      print('    $d');
    }

    printViewSummary('MEDIUM SEVERITY', severity);
    printQuintileTable(severity);
    printViewSummary('MEDIUM REPRESENTATIVE', representative);
    printViewSummary('HARD CONTROL', hard);

    // ── T0.4's optional telemetry, and the input to T1.2's design ──────────
    print('\n===== CORE-SELECTION PATH (which hatch shipped the cores) =====');
    printCorePathDistribution('severity      ', severity);
    printCorePathDistribution('representative', representative);
    printCorePathDistribution('hard control  ', hard);

    print('\n===== REALISED COMPOSITION (for the README) =====');
    printComposition('severity      ', severity);
    printComposition('representative', representative);
    printComposition('hard control  ', hard);

    // ── The number T1.2 is designed against ────────────────────────────────
    //
    // Boards whose ceiling is itself below the mode floor cannot be fixed by
    // any core selection. T1.2's bounded repick will burn all its attempts and
    // ship the best it saw, silently. If this set is large, T1.2 as specified
    // cannot deliver its stated invariant and the remedy has to move upstream
    // into candidate rejection. Known *before* T1.2 is written, not after.
    print('\n===== GEOMETRICALLY UNFIXABLE (ceiling < mode floor) =====');
    for (final entry in <String, List<AdversarialRow>>{
      'severity': severity,
      'representative': representative,
      'hard': hard,
    }.entries) {
      final u = entry.value.where((r) => r.geometricallyUnfixable).toList();
      print('  ${entry.key.padRight(15)} ${u.length}/${entry.value.length}');
      for (final r in u.take(20)) {
        print('     L${r.levelId} ${r.mode.name} S${r.board.sector} '
            'cores=${r.board.cores} nodes=${r.nodes} '
            'taps=${r.tapsToWin} ceiling=${r.ceiling.ceilingTapDepth}');
      }
    }

    // Boards where the selector left the most depth on the table — the work
    // order T1.1/T1.2 are aimed at.
    print('\n===== LARGEST SELECTOR HEADROOM (severity view) =====');
    final byHeadroom = List<AdversarialRow>.from(severity)
      ..sort((a, b) => b.ceiling.headroom.compareTo(a.ceiling.headroom));
    for (final r in byHeadroom.take(20)) {
      print('  L${r.levelId} Q${r.entry.quintile} S${r.board.sector} '
          'cores=${r.board.cores} nodes=${r.nodes} '
          'taps=${r.tapsToWin} ceiling=${r.ceiling.ceilingTapDepth} '
          'capture=${r.captureRate.toStringAsFixed(2)}');
    }

    // Boards too large for the 62-bit closure mask would have had their ceiling
    // silently reported as the actual depth, quietly turning every one of them
    // into a perfect capture. Max observed node count is 27, so this is a
    // tripwire, not a live concern — but a silently wrong baseline is exactly
    // the failure this whole phase exists to prevent.
    final inexact = rows.where((r) => !r.ceiling.exhaustive).toList();
    print('\n  non-exhaustive ceilings: ${inexact.length} '
        '(must be 0; >62 nodes)');

    print('\n===== CSVs =====');
    writeAdversarialCsv(
        '$_kOutDir/medium_severity_baseline.csv', severity);
    writeAdversarialCsv(
        '$_kOutDir/medium_representative_baseline.csv', representative);
    writeAdversarialCsv('$_kOutDir/hard_control_baseline.csv', hard);

    // The only expectations here are that the instrument itself ran — never
    // that a board is good. Quality gates live in core_triviality_test.dart.
    expect(rows, hasLength(kAdversarialCorpus.length));
    expect(kAdversarialCorpusGenerationVersion, equals(kGenerationVersion),
        reason: 'the corpus was frozen against a different generationVersion; '
            'the frozen ids no longer mean the boards they were selected for');
    expect(drift, isEmpty,
        reason: 'generation is not a pure function of '
            '(levelId, mode, generationVersion) — session state leaked in');
    expect(inexact, isEmpty,
        reason: 'ceiling search was skipped on ${inexact.length} boards; '
            'the baseline would overstate captureRate for them');
  }, timeout: const Timeout(Duration(minutes: 45)));
}
