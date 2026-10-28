// P2b — where candidate variety is lost, measured rather than argued.
//
//   flutter test --tags report \
//     test/game/levels/generation/p2_selection_funnel_report_test.dart
//
// **Asserts nothing**, by construction (plan §0.5). Companion to
// `p2_variety_report_test.dart`: that file measures the *boards*, this one
// measures the *machinery that chooses between them*.
//
// It exists because P2's bundle moved every per-board measure it aimed at
// (Hard topology classes 22 -> 38) and moved no sequence measure at all
// (same-silhouette run 6 -> 6, rolling min-Hamming median 3.00 -> 3.00). Board
// measures are set by mask geometry; sequence measures are set by *selection*.
// So the question is whether selection runs — and the answer is that it very
// nearly never does. See `docs/P2B_PLAN.md`.
//
// Three views, each answering one question:
//
//   1. THE FUNNEL — of the K-loop's iterations, how many candidates survive to
//      the diversity ledger, how many the ledger calls novel, and how many are
//      left for the comparator to actually rank. T2.5 adds the per-stage
//      MORTALITY table: every iteration entered exits through exactly one
//      gate, so the row that dominates is the one starving the funnel.
//      Medium and Easy are run as controls — if they are healthy, the cause is
//      Hard-specific density rather than the loop's shape.
//   2. FINGERPRINT ENTROPY — per-bit, which of the ledger's 26 fingerprint bits
//      carry information on Hard. A novelty threshold is only meaningful
//      against the entropy actually available.
//   3. CONCRETE OUTLINES — how many genuinely different mask outlines each
//      silhouette id renders as. `silhouetteVisualFamily` collapses 8 ids into
//      4 families, and the P2 DoD's "lattice share" is measured on that label;
//      this view is what the label hides.
//
// ignore_for_file: avoid_print

@Tags(['corpus', 'report'])
library;

import 'dart:math' as math;

import 'package:chain_pop/game/levels/analytics/generation_analytics.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'corpus_benchmark_utils.dart';

/// Levels in the funnel sweep. 300 is enough for the funnel histograms; the
/// entropy and outline views use the 500-level sequential run so they match
/// `p2_variety_report_test.dart`'s population exactly.
const int kFunnelLevels = 300;
const int kSequenceLevels = 500;

void main() {
  test('P2b selection funnel report', () {
    printCorpusVersionBanner('P2b SELECTION FUNNEL');
    _funnel(DifficultyMode.hard);
    print('');
    _funnel(DifficultyMode.medium);
    print('');
    _funnel(DifficultyMode.easy);
    print('');
    final bits = _entropyAndOutlines();
    print('');
    _novelty(bits);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. The funnel.
// ═══════════════════════════════════════════════════════════════════════════

void _funnel(DifficultyMode mode) {
  final gen = LevelGenerator();
  final cand = <int, int>{};
  final rankable = <int, int>{};
  final paths = <String, int>{};
  var totalCand = 0, totalNovel = 0, totalRankable = 0, totalRej = 0, n = 0;
  // T2.5 — per-stage mortality. Every iteration entered leaves through exactly
  // one of these, or reaches the ledger.
  var iters = 0,
      budgetBreaks = 0,
      construction = 0,
      fsr = 0,
      cud = 0,
      oob = 0,
      hrAspect = 0,
      hrComponents = 0;

  for (var id = 1; id <= kFunnelLevels; id++) {
    gen.resetCounters();
    final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
    if (!r.isSuccess) continue;
    n++;
    final c = gen.candidateCount;
    final a = gen.acceptedNovelCandidateCount;
    cand[c] = (cand[c] ?? 0) + 1;
    rankable[a] = (rankable[a] ?? 0) + 1;
    totalCand += c;
    totalNovel += gen.novelCandidateCount;
    totalRankable += a;
    totalRej += gen.evaluatorRejectionCount;
    iters += gen.kloopIterations;
    budgetBreaks += gen.kloopBudgetBreaks;
    construction += gen.constructionFailures;
    fsr += gen.fsrCapRejects;
    cud += gen.cudFloorRejects;
    oob += gen.outOfBandNoted;
    hrAspect += gen.hardRejectAspect;
    hrComponents += gen.hardRejectComponents;
    gen.fallbackReasonCounts.forEach((k, v) => paths[k] = (paths[k] ?? 0) + v);
  }

  final label = mode.name.toUpperCase();
  print('--- THE FUNNEL ($label L1-$kFunnelLevels, prod budget, n=$n) ---');
  print('candidates reaching the ledger, per level : ${_hist(cand)}');
  print('RANKABLE candidates (in-band + novel)     : ${_hist(rankable)}');
  print('exit path taken                           : $paths');
  print('totals: candidates=$totalCand  novel=$totalNovel  '
      'rankable=$totalRankable  evaluatorRejections=$totalRej');
  final d = math.max(1, n);
  print('per level: candidates=${(totalCand / d).toStringAsFixed(2)}  '
      'novel=${(totalNovel / d).toStringAsFixed(2)}  '
      'rankable=${(totalRankable / d).toStringAsFixed(2)}');
  final noChoice = (rankable[0] ?? 0) + (rankable[1] ?? 0);
  print('LEVELS WHERE RANKING HAD NO CHOICE (<=1 rankable): '
      '$noChoice/$n = ${(100 * noChoice / d).toStringAsFixed(1)}%');
  print('  ^ every diversity mechanism in the generator — ledger novelty, the');
  print('    silhouette streak penalty and diversity boost, T2.4c composition');
  print(
      '    ranking, the tempo/CUD/topology comparator — chooses among these.');

  // T2.5 — the mortality table. This is the view that says WHICH gate to
  // touch, and it is the reason `_evaluatorRejectionCount` was split: that
  // counter also fires on the `!inBand` branch when the candidate then goes on
  // to reach the ledger, so it never named a stage.
  print('  K-loop mortality, $label — where the $iters iterations went:');
  final rows = <String, int>{
    'construction failed (build/solve/renegotiate)': construction,
    'FSR cap reject': fsr,
    'composition HARD reject — aspect': hrAspect,
    'composition HARD reject — components': hrComponents,
    'CUD floor reject (out-of-band only)': cud,
    'REACHED THE LEDGER': totalCand,
  };
  final mi = math.max(1, iters);
  for (final e in rows.entries) {
    print('    ${e.key.padRight(46)} ${e.value.toString().padLeft(5)}  '
        '${(100 * e.value / mi).toStringAsFixed(1)}%');
  }
  final accounted = rows.values.reduce((a, b) => a + b);
  print(
      '    ${'—— accounted for'.padRight(46)} ${accounted.toString().padLeft(5)}'
      '${accounted == iters ? '  (conserved)' : '  MISMATCH vs $iters'}');
  print('    iterations never entered (latency budget)      '
      '${budgetBreaks.toString().padLeft(5)}');
  print('    of the ledger-reaching, out-of-band            '
      '${oob.toString().padLeft(5)}   (an observation, not an exit)');
  print('    per level: iterations=${(iters / d).toStringAsFixed(2)}  '
      'reached ledger=${(totalCand / d).toStringAsFixed(2)}');
}

// ═══════════════════════════════════════════════════════════════════════════
// 2 + 3. Fingerprint entropy and concrete outlines, on one sequential run.
// ═══════════════════════════════════════════════════════════════════════════

/// Bit labels for the §4.5 fingerprint layout (`diversity_ledger.dart`).
const Map<int, String> _kBitLabels = {
  0: 'sil0',
  1: 'sil1',
  2: 'sil2',
  3: 'wave0',
  4: 'wave1',
  5: 'bf0',
  6: 'bf1',
  7: 'motif0',
  8: 'motif1',
  9: 'motif2',
  10: 'dirN',
  11: 'dirE',
  12: 'dirS',
  13: 'dirW',
  23: 'fam0',
  24: 'fam1',
  25: 'fam2',
};

List<int> _entropyAndOutlines() {
  final sink = InMemoryAnalyticsSink();
  final gen = LevelGenerator(analyticsSink: sink);
  final outlines = <SilhouetteId, Set<String>>{};

  for (var id = 1; id <= kSequenceLevels; id++) {
    final r =
        gen.generate(id, mode: DifficultyMode.hard, timeBudget: kProdBudget);
    if (!r.isSuccess) continue;
    final ev = sink.events.last;
    final cells = r.value.playCells;
    final sig = (cells == null || cells.isEmpty)
        ? 'rect${r.value.gridWidth}x${r.value.gridHeight}'
        : '${cells.length}@${r.value.gridWidth}x${r.value.gridHeight}';
    (outlines[ev.silhouette] ??= <String>{}).add(sig);
  }

  final bits = sink.events.map((e) => e.fingerprint.bits).toList();
  print('--- FINGERPRINT BIT ENTROPY (Hard, n=${bits.length}) ---');
  var dead = 0;
  var entropy = 0.0;
  final groups = <String, double>{};
  for (var b = 0; b <= 25; b++) {
    final ones = bits.where((x) => (x >> b) & 1 == 1).length;
    final p = ones / math.max(1, bits.length);
    final label = _kBitLabels[b] ?? 'dens${b - 14}';
    final h =
        (p <= 0 || p >= 1) ? 0.0 : -(p * _log2(p) + (1 - p) * _log2(1 - p));
    if (p <= 0 || p >= 1) dead++;
    entropy += h;
    final group = label.replaceAll(RegExp(r'[0-9]+$'), '');
    groups[group] = (groups[group] ?? 0) + h;
    print('  bit ${b.toString().padLeft(2)} ${label.padRight(7)} '
        'p(1)=${p.toStringAsFixed(3)}  h=${h.toStringAsFixed(3)}'
        '${(p <= 0 || p >= 1) ? '   DEAD' : ''}');
  }
  print('  DEAD bits: $dead/26   effective entropy: '
      '${entropy.toStringAsFixed(2)} of 26 bits');
  final g = groups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  print('  by field: ${g.map((e) => '${e.key}='
      '${e.value.toStringAsFixed(2)}b').join('  ')}');

  print('\n--- CONCRETE OUTLINES PER SILHOUETTE ID ---');
  print(
      '  (cells@grid signatures — what the player actually sees, against the');
  print('   4-family label the "lattice share" DoD item is measured on)');
  final ids = outlines.keys.toList()
    ..sort((a, b) => outlines[b]!.length.compareTo(outlines[a]!.length));
  for (final id in ids) {
    print('  ${id.name.padRight(13)} '
        '${outlines[id]!.length.toString().padLeft(3)} distinct outlines   '
        '[${silhouetteVisualFamily(id).name}]');
  }
  print('  TOTAL distinct outlines: '
      '${outlines.values.fold<int>(0, (a, b) => a + b.length)}');
  return bits;
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. What the novelty gate is actually being asked for.
// ═══════════════════════════════════════════════════════════════════════════

void _novelty(List<int> bits) {
  final hamm = rollingMinHammingDistances(fingerprintBits: bits);
  final sorted = [...hamm.minDistances]..sort();
  print('--- NOVELTY GATE vs ACHIEVABLE DISTANCE ---');
  print('rolling nearest-neighbour Hamming over a 20-wide window:');
  print('  min=${sorted.isEmpty ? 0 : sorted.first}  '
      'p25=${_pct(sorted, 0.25)}  median=${hamm.median.toStringAsFixed(2)}  '
      'p75=${_pct(sorted, 0.75)}  p90=${hamm.p90.toStringAsFixed(2)}  '
      'max=${sorted.isEmpty ? 0 : sorted.last}');
  final below5 = sorted.where((d) => d < 5).length;
  final below8 = sorted.where((d) => d < 8).length;
  final t2 = math.max(1, sorted.length);
  final t = t2;
  print('ledger thresholds: base=5, same-visual-family=8');
  print('  share under base 5 : ${(100 * below5 / t).toStringAsFixed(1)}%');
  print('  share under 8      : ${(100 * below8 / t).toStringAsFixed(1)}%');
  // T2.7 — the admission CDF the new threshold is chosen from. Printed so the
  // constant is derived from the distribution rather than picked as a round
  // number, the same observe-then-calibrate split T2.4a/b used.
  print('T2.7 admission CDF — share of levels a threshold would call NOVEL:');
  for (var t = 2; t <= 9; t++) {
    final admitted = sorted.where((d) => d >= t).length;
    print(
        '  threshold $t : ${(100 * admitted / t2).toStringAsFixed(1)}% admitted');
  }
  // What a silhouette-only difference actually costs, which is the floor the
  // plan pinned: novelty must still reject a board differing only in
  // silhouette id from a window entry.
  final silDistances = <int>[];
  for (final a in SilhouetteId.values) {
    for (final b in SilhouetteId.values) {
      if (a.index >= b.index) continue;
      final d = _pop((a.index ^ b.index)) +
          _pop(silhouetteVisualFamily(a).index ^
              silhouetteVisualFamily(b).index);
      silDistances.add(d);
    }
  }
  silDistances.sort();
  print('silhouette-id-only pair distances (sil bits + family bits): '
      'min=${silDistances.first} max=${silDistances.last}');
  print('  ^ a threshold at or below max makes a pure silhouette swap read as');
  print('    novel, which is the floor the plan pinned a fixture test on.');
  print('  ^ a candidate must clear the threshold against EVERY one of the 20');
  print('    entries in the window, so these shares are a lower bound on how');
  print('    often novelty is unreachable.');
}

// ═══════════════════════════════════════════════════════════════════════════

int _pop(int x) {
  var c = 0;
  var v = x;
  while (v != 0) {
    c += v & 1;
    v >>= 1;
  }
  return c;
}

double _log2(double x) => x <= 0 ? 0 : math.log(x) / math.ln2;

String _pct(List<int> sorted, double p) =>
    sorted.isEmpty ? '0' : sorted[((sorted.length - 1) * p).round()].toString();

String _hist(Map<int, int> m) {
  final keys = m.keys.toList()..sort();
  return keys.map((k) => '$k:${m[k]}').join(' ');
}
