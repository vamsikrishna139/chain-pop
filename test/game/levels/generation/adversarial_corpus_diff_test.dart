// T0.4§e — the before/after diff that closes P1's definition of done.
//
//   flutter test --tags report \
//     test/game/levels/generation/adversarial_corpus_diff_test.dart
//
// Measures the corpus as it stands today and compares it to an archived
// baseline directory — by default `genv1_pre_p1/`, the pre-P1 Gen V1 capture,
// which is the only honest "before" for P1's effect. Prints the per-quintile
// movement, `captureRate`, and the §e classification.
//
// **Asserts nothing**, by construction (§0.5): this is the evidence layer. The
// asserting file is `adversarial_corpus_guards_test.dart`, which compares
// against the *current* baseline and enforces invariance.
//
// Why this file exists at all: P1's published result was computed by hand from
// a baseline that turned out to have been captured mid-phase, and there was no
// committed harness to re-derive it from. There is now.
//
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'adversarial_corpus.dart';
import 'adversarial_corpus_report.dart';
import 'corpus_version.dart';

/// The archived capture to diff against. `genv1_pre_p1/` is pre-P1 Gen V1.
const String _kBeforeDir = 'docs/playtests/adversarial_baseline/genv1_pre_p1';

const List<String> _kBaselineFiles = [
  'medium_severity_baseline.csv',
  'medium_representative_baseline.csv',
  'hard_control_baseline.csv',
];

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

void main() {
  test('T0.4§e — before/after diff and classification', () {
    printCorpusVersionBanner('T0.4§e CORPUS DIFF');
    print('  before: $_kBeforeDir');
    print('  after : the working tree\n');

    final before = <String, BaselineRecord>{};
    for (final f in _kBaselineFiles) {
      before.addAll(readBaseline('$_kBeforeDir/$f'));
    }
    final rows = measureCorpus(kAdversarialCorpus);

    void viewSummary(String label, bool Function(AdversarialRow) where) {
      final rs = rows.where(where).toList();
      if (rs.isEmpty) return;
      final beforeTaps = <int>[for (final r in rs) before[r.entry.key]!.tapsToWin]
        ..sort();
      final afterTaps = <int>[for (final r in rs) r.tapsToWin]..sort();
      final beforeCapture = <double>[
        for (final r in rs) before[r.entry.key]!.captureRate
      ]..sort();
      final afterCapture = <double>[for (final r in rs) r.captureRate]..sort();
      int shortBefore = 0, shortAfter = 0;
      for (final r in rs) {
        if (before[r.entry.key]!.tapsToWin <= 6) shortBefore++;
        if (r.tapsToWin <= 6) shortAfter++;
      }
      String p(List<int> v, double f) => '${percentileInt(v, f)}';
      print('== $label  (n=${rs.length})');
      print('   tapsToWin  min ${beforeTaps.first} -> ${afterTaps.first}   '
          'p25 ${p(beforeTaps, 0.25)} -> ${p(afterTaps, 0.25)}   '
          'p50 ${p(beforeTaps, 0.50)} -> ${p(afterTaps, 0.50)}   '
          'p75 ${p(beforeTaps, 0.75)} -> ${p(afterTaps, 0.75)}');
      print('   <=6 taps   ${_pct(shortBefore / rs.length)} -> '
          '${_pct(shortAfter / rs.length)}');
      print('   captureRate p50 '
          '${percentileDouble(beforeCapture, 0.50).toStringAsFixed(2)} -> '
          '${percentileDouble(afterCapture, 0.50).toStringAsFixed(2)}');
    }

    viewSummary('MEDIUM SEVERITY',
        (r) => r.entry.view == CorpusView.mediumSeverity);
    viewSummary('MEDIUM REPRESENTATIVE',
        (r) => r.entry.view == CorpusView.mediumRepresentative);
    viewSummary('HARD CONTROL', (r) => r.entry.view == CorpusView.hardControl);

    print('\n===== PER-QUINTILE (severity view) =====');
    print('  Q   n   p50 taps        <=6 taps          captureRate p50');
    for (var q = 1; q <= 5; q++) {
      final rs = rows
          .where((r) =>
              r.entry.view == CorpusView.mediumSeverity && r.entry.quintile == q)
          .toList();
      if (rs.isEmpty) continue;
      final bt = <int>[for (final r in rs) before[r.entry.key]!.tapsToWin]..sort();
      final at = <int>[for (final r in rs) r.tapsToWin]..sort();
      final bc = <double>[for (final r in rs) before[r.entry.key]!.captureRate]
        ..sort();
      final ac = <double>[for (final r in rs) r.captureRate]..sort();
      final sb = rs.where((r) => before[r.entry.key]!.tapsToWin <= 6).length;
      final sa = rs.where((r) => r.tapsToWin <= 6).length;
      final taps =
          '${percentileInt(bt, 0.5)} -> ${percentileInt(at, 0.5)}'.padRight(16);
      final short =
          '${_pct(sb / rs.length)} -> ${_pct(sa / rs.length)}'.padRight(18);
      final capture = '${percentileDouble(bc, 0.5).toStringAsFixed(2)} -> '
          '${percentileDouble(ac, 0.5).toStringAsFixed(2)}';
      print('  Q$q  ${rs.length}   $taps  $short  $capture');
    }

    // ── §e classification ───────────────────────────────────────────────────
    //
    // `classifyBoard` calls any geometry, solution or node-count movement a
    // VIOLATION, which is right when the comparison is a guard. Here the
    // comparison spans P1 itself, and P1 legitimately moved 61 boards
    // (`kP1GeometryMovers` — see the argument there). Those boards are exempted
    // **by name**, by handing the classifier the current hashes for them, so
    // the audited decision tree is reused rather than relaxed. Any board
    // outside that list that moves still classifies as a VIOLATION.
    final counts = <BoardOutcome, int>{};
    final notable = <BoardOutcome, List<String>>{};
    for (final r in rows) {
      final b = before[r.entry.key]!;
      final exempt = kP1GeometryMovers.contains(r.entry.key);
      final outcome = classifyBoard(
        baseline: exempt
            ? BaselineRecord(
                levelId: b.levelId,
                mode: b.mode,
                view: b.view,
                quintile: b.quintile,
                severityRank: b.severityRank,
                tapsToWin: b.tapsToWin,
                nodes: r.nodes,
                cores: b.cores,
                ceilingTapDepth: b.ceilingTapDepth,
                captureRate: b.captureRate,
                geometryHash: r.geometryHash,
                solutionHash: r.solutionHash,
                coreSetHash: b.coreSetHash,
                contentIdentity: b.contentIdentity,
              )
            : b,
        currentTapsToWin: r.tapsToWin,
        currentNodes: r.nodes,
        currentGeometryHash: r.geometryHash,
        currentSolutionHash: r.solutionHash,
        currentCoreSetHash: r.coreSetHash,
        currentCeilingTapDepth: r.ceiling.ceilingTapDepth,
        currentCaptureRate: r.captureRate,
        mode: r.mode,
      );
      counts[outcome] = (counts[outcome] ?? 0) + 1;
      if (outcome != BoardOutcome.fixed) {
        (notable[outcome] ??= []).add(r.entry.key);
      }
    }

    print('\n===== §e CLASSIFICATION (${rows.length} boards) =====');
    for (final o in BoardOutcome.values) {
      print('  ${o.name.padRight(28)} ${counts[o] ?? 0}');
    }
    for (final entry in notable.entries) {
      if (entry.value.isEmpty) continue;
      print('  ${entry.key.name}: ${entry.value.take(30).join(', ')}'
          '${entry.value.length > 30 ? ' …' : ''}');
    }

    // Coreless boards classify as INCIDENTAL by construction — the win is
    // clear-all, so there is no core set to move. Counted separately so the
    // INCIDENTAL total is readable.
    final coreless = rows.where((r) => r.board.cores == 0).length;
    print('  (of which coreless boards, where INCIDENTAL is definitional: '
        '$coreless)');
  });
}
