// T2.10a — recalibrate the composition regression guard against the *new*
// selection regime.
//
//   flutter test --tags report \
//     test/game/levels/generation/p2b_composition_recalibration_test.dart
//
// **Asserts nothing** (plan §0.5). This is the observe half of an
// observe→calibrate→act split, the same discipline as T2.4a/b/c and T2.6/T2.7.
//
// WHY THE OLD FLOOR MUST BE RE-DERIVED, NOT NUDGED.
//
// The T2.4b floors (Medium >= 0.63, Hard >= 0.65) are the *shipped p10* of a
// population in which ~95% of levels exited through the `non-novel` fallback —
// the one path that selects purely on composition. P2b deliberately dismantled
// that regime: Medium now ships 174 of 300 through the ranked in-band path.
//
// So the old constant no longer answers "is composition quality acceptable?".
// It answers "does the new selector reproduce the lower tail of the old
// fallback-dominated population?" — a different question, and not one worth
// gating on. The guard is a *regression floor*, not an optimisation target,
// and a regression floor has to describe the engine that actually ships.
//
// HOW THIS AVOIDS MOVING THE GOALPOSTS.
//
// Three rules, all of which the discovery work broke and this run does not:
//
//  1. **Fresh corpus.** The gap was discovered on L1-300. Calibration uses a
//     disjoint later window, and a second disjoint window is held out for
//     validation. Deriving a threshold on the sample that motivated it is how
//     old-threshold overfitting becomes new-threshold overfitting.
//  2. **Robust lower tail, not a single p10.** A lone p10 off one 300-board
//     draw is corpus noise as much as signal. Bootstrap gives an interval, and
//     the floor is set below its lower bound with a stated margin.
//  3. **Validated unseen.** The chosen floor is then checked against the
//     held-out window it was not derived from.
//
// Sequential generation throughout: the diversity ledger is session state, so
// a board depends on every board before it. Sampling a later window of one
// continuous run is what the player actually meets.
//
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'dart:math' as math;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/visual_composition.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';
import 'corpus_benchmark_utils.dart';

/// Disjoint windows of one sequential campaign run.
const int kDiscoveryEnd = 300; // the sample the gap was found on — excluded
const int kCalibStart = 301, kCalibEnd = 800;
const int kValidStart = 801, kValidEnd = 1300;

/// Bootstrap resamples for the lower-tail interval.
const int kBootstrap = 2000;

void main() {
  test('T2.10a composition recalibration', () {
    printCorpusVersionBanner('T2.10a COMPOSITION RECALIBRATION');
    for (final e in [
      (DifficultyMode.medium, DifficultyTier.medium, 0.63),
      (DifficultyMode.hard, DifficultyTier.hard, 0.65),
    ]) {
      _recalibrate(e.$1, e.$2, e.$3);
    }
  }, timeout: const Timeout(Duration(minutes: 90)));
}

void _recalibrate(DifficultyMode mode, DifficultyTier tier, double oldFloor) {
  final gen = LevelGenerator();
  final discovery = <double>[];
  final calib = <double>[];
  final valid = <double>[];

  for (var id = 1; id <= kValidEnd; id++) {
    final r = gen.generate(id, mode: mode, timeBudget: kProdBudget);
    if (!r.isSuccess) continue;
    final score = evaluateVisualComposition(r.value, tier).score;
    if (id <= kDiscoveryEnd) {
      discovery.add(score);
    } else if (id >= kCalibStart && id <= kCalibEnd) {
      calib.add(score);
    } else if (id >= kValidStart && id <= kValidEnd) {
      valid.add(score);
    }
  }

  print('\n═══ ${mode.name.toUpperCase()} — old floor $oldFloor ═══');
  _describe(
      'discovery  L1-$kDiscoveryEnd  (EXCLUDED from derivation)', discovery);
  _describe('CALIBRATION L$kCalibStart-$kCalibEnd', calib);
  _describe('validation L$kValidStart-$kValidEnd (held out)', valid);

  // Bootstrap the calibration window's p10.
  final rng = math.Random(20260822);
  final p10s = <double>[];
  for (var b = 0; b < kBootstrap; b++) {
    final sample = List<double>.generate(
        calib.length, (_) => calib[rng.nextInt(calib.length)])
      ..sort();
    p10s.add(_at(sample, 0.10));
  }
  p10s.sort();
  final lo = _at(p10s, 0.025), hi = _at(p10s, 0.975);
  print('  bootstrap p10 95% CI on the calibration window: '
      '[${lo.toStringAsFixed(4)}, ${hi.toStringAsFixed(4)}]  '
      '(n=$kBootstrap resamples)');

  // The floor sits below the interval's lower bound, not at a point estimate.
  // 0.01 is one fifth of `kCompositionRankBand` — smaller than the granularity
  // at which two boards read as differently composed, so the margin cannot
  // hide a real regression, and large enough to absorb corpus-to-corpus noise
  // of the size the CI shows.
  const margin = 0.01;
  final proposed = ((lo - margin) * 1000).floor() / 1000;
  print('  PROPOSED FLOOR = ${proposed.toStringAsFixed(4)}  '
      '(CI lower ${lo.toStringAsFixed(4)} - margin $margin, floored to 3dp)');

  for (final e in [
    ('calibration', calib),
    ('validation (UNSEEN)', valid),
    ('discovery', discovery),
  ]) {
    final below = e.$2.where((s) => s < proposed).length;
    final oldBelow = e.$2.where((s) => s < oldFloor).length;
    final sorted = [...e.$2]..sort();
    print(
        '  vs ${e.$1.padRight(20)} p10=${_at(sorted, 0.10).toStringAsFixed(4)}  '
        'clears proposed: ${_at(sorted, 0.10) >= proposed ? "YES" : "NO"}   '
        'below proposed $below/${e.$2.length}   '
        'below old $oldFloor: $oldBelow/${e.$2.length}');
  }
}

void _describe(String label, List<double> v) {
  if (v.isEmpty) {
    print('  ${label.padRight(46)} (empty)');
    return;
  }
  final s = [...v]..sort();
  print('  ${label.padRight(46)} n=${s.length.toString().padLeft(4)}  '
      'min=${_f(s, 0.0)} p05=${_f(s, .05)} p10=${_f(s, .10)} '
      'p15=${_f(s, .15)} p25=${_f(s, .25)} p50=${_f(s, .50)} '
      'p75=${_f(s, .75)} p90=${_f(s, .90)}');
}

String _f(List<double> s, double p) => _at(s, p).toStringAsFixed(4);
double _at(List<double> s, double p) => s[((s.length - 1) * p).round()];
