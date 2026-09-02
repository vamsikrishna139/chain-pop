// EXPECTED RED until P1 lands. Documents F1 — "Medium collapses into a
// two-tap board, Easy is mechanically inert".
// See docs/IMPLEMENTATION_PLAN_V2.md §T0.3.
//
// This is the **gate** file for P1, and the only one. The three
// `report_*_100_test.dart` harnesses are the *evidence* layer: they print and
// write CSVs and assert nothing, by construction (§0.5). Every P1 tap-depth
// assertion, for all three modes, lives here.
//
// Expected status when committed:
//
//   | case   | measured today               | verdict            |
//   |--------|------------------------------|--------------------|
//   | Medium | 66% of boards win in ≤6 taps | RED — this is F1   |
//   | Easy   | 0 cores anywhere             | RED — no core arc  |
//   | Hard   | min 6, p50 10                | GREEN from day one |
//
// **Baseline calibration, 2026-08-19.** The plan quoted "44% ≤6 taps" for
// Medium and "p50 11" for Hard. Neither reproduces. Measured over
// `kReportSampleIds`, agreeing exactly between a fresh unbudgeted run and the
// committed T0.2 CSVs in `docs/playtests/`, the real Gen V1 figures are
// Medium 66% / min 2 and Hard p50 10 / min 6. The 44% is not recoverable under
// any encoding of "taps" (coreTapDepth raw → 86%, core-boards-only → 82.5%,
// waveDepth → 92%, CUD → 98%), so it is treated the same way §P2 treats the
// non-reproducible topology "14": discarded as a baseline. The Hard guard is
// therefore centred on the measured 10, not the quoted 11 — centring on 11
// would have permitted an upward drift to 12 while flagging a benign 9.
//
// The Hard case is a **regression guard, not a formality**: Hard shares
// `_markCoreNodes` with Medium, so T1.1/T1.2 can over-correct it. It must be
// green before P1 and stay green after.
//
// Determinism: this batch runs with `timeBudget: null`. The T0.0a closure audit
// scopes the contract to the unbudgeted path — under a wall-clock budget the
// generator's control flow depends on elapsed time, which would make these
// statistics machine-dependent and this gate a flake.
//
// ignore_for_file: avoid_print

@Tags(['slow'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'report_sample.dart';

/// The taps-to-win population for one mode, plus the aggregates the gates read.
class _TapProfile {
  _TapProfile(this.label, this.rows);

  final String label;
  final List<BoardRow> rows;

  List<int> get taps => [for (final r in rows) r.tapsToWin];

  /// Nearest-rank percentile — the same convention `printSummary` uses in
  /// `board_report_utils.dart`, so a canary number can be read straight off a
  /// corpus CSV summary.
  int _q(double f) {
    final s = taps..sort();
    return s[((s.length - 1) * f).round()];
  }

  int get minTaps => _q(0);
  int get p50Taps => _q(0.5);
  int get p95Taps => _q(0.95);

  /// Share of boards won in at most [n] taps.
  double shareAtMost(int n) =>
      rows.where((r) => r.tapsToWin <= n).length / rows.length;

  /// Boards that reached the win through the core condition at all.
  int get coreWinBoards => rows.where((r) => r.cores > 0).length;

  void report() {
    final t = taps;
    print('\n===== TAPS TO WIN — $label (n=${t.length}) =====');
    print('  min=$minTaps  p50=$p50Taps  p95=$p95Taps  max=${_q(1)}');
    print('  share(<=6 taps) = ${(shareAtMost(6) * 100).toStringAsFixed(1)}%'
        '   share(<=9 taps) = ${(shareAtMost(9) * 100).toStringAsFixed(1)}%');
    print('  core-win boards = $coreWinBoards / ${rows.length}'
        '  (the rest are clear-all wins, taps == nodeCount)');
    final hist = <int, int>{};
    for (final v in t) {
      hist[(v ~/ 3) * 3] = (hist[(v ~/ 3) * 3] ?? 0) + 1;
    }
    final keys = hist.keys.toList()..sort();
    for (final k in keys) {
      print('    ${k.toString().padLeft(3)}-${(k + 2).toString().padLeft(3)} '
          '${"#" * hist[k]!} ${hist[k]}');
    }
    final worst = rows.where((r) => r.tapsToWin <= 6).toList()
      ..sort((a, b) => a.tapsToWin.compareTo(b.tapsToWin));
    if (worst.isNotEmpty) {
      print('  trivial boards (<=6 taps), shallowest first:');
      for (final r in worst.take(15)) {
        print('    ${r.label.padRight(7)} S${r.sector} '
            'taps=${r.tapsToWin.toString().padLeft(2)} '
            'nodes=${r.nodes.toString().padLeft(2)} '
            'cores=${r.cores} '
            'tapFrac=${r.core.coreTapFraction.toStringAsFixed(2)} '
            'coreCrit=${r.core.coreCriticalDepth} '
            'waves=${r.metrics.waveDepth}');
      }
    }
  }
}

_TapProfile _profileFor({
  required String label,
  required DifficultyMode mode,
  required DifficultyProfile profile,
}) {
  final failures = <int>[];
  final rows = runCampaignBatch(
    levelIds: kReportSampleIds,
    mode: mode,
    profile: profile,
    failures: failures,
    timeBudget: null,
  );
  // A generation failure would silently shrink the population and flatter the
  // statistics, so it fails the gate rather than being averaged away.
  expect(failures, isEmpty,
      reason: '$label: generation failed for ids $failures');
  expect(rows, hasLength(kReportSampleIds.length));
  final p = _TapProfile(label, rows);
  p.report();
  return p;
}

void main() {
  late _TapProfile easy;
  late _TapProfile medium;
  late _TapProfile hard;

  setUpAll(() {
    easy = _profileFor(
      label: 'EASY',
      mode: DifficultyMode.easy,
      profile: DifficultyProfile.easy,
    );
    medium = _profileFor(
      label: 'MEDIUM',
      mode: DifficultyMode.medium,
      profile: DifficultyProfile.medium,
    );
    hard = _profileFor(
      label: 'HARD',
      mode: DifficultyMode.hard,
      profile: DifficultyProfile.hard,
    );
  });

  group('core triviality', () {
    // EXPECTED RED until T1.1–T1.3. Measured today: 66% of Medium boards are
    // won in six taps or fewer and the shallowest is 2. That is F1.
    test('Medium boards are not trivially short', () {
      expect(medium.shareAtMost(6), lessThan(0.05),
          reason: 'F1: Medium collapses into trivial boards');
      expect(medium.minTaps, greaterThanOrEqualTo(6),
          reason: 'F1: no Medium board may be a two-tap board');
    });

    // EXPECTED RED until T1.4. Easy ships zero cores, so every Easy board is a
    // clear-all win today and this case passes for the wrong reason. It is
    // committed red-ready: it is the guard that T1.4's single core does not
    // recreate F1 in miniature, which is Easy's ONLY quality gate (§T1.4).
    test('Easy teaches without collapsing', () {
      expect(easy.shareAtMost(6), equals(0.0),
          reason: 'Easy must never contain a trivial board');
      expect(easy.p50Taps, greaterThanOrEqualTo(9),
          reason: 'Easy must stay long enough to teach');
    });

    // GREEN from day one — a regression guard against over-correction. Hard
    // measures healthy today and shares the code path P1 edits. Centred on the
    // measured baseline of 10 (see the calibration note above), so the window
    // is a symmetric [9, 11].
    test('Hard stays where it already is', () {
      expect(hard.p50Taps, closeTo(10, 1), reason: 'P1 must not move Hard');
      expect(hard.minTaps, greaterThanOrEqualTo(6),
          reason: 'Hard has no trivial boards today and must not gain any');
    });
  });
}
