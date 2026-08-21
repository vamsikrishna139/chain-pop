// P1 final validation — the fresh draw.
//
// T0.4§g's held-out sequence ends with a population that no part of P1 has ever
// seen: not the frozen corpus (which selection was run against, once), and not
// `kReportSampleIds` (which the canary gates on and which was therefore in front
// of the implementer the whole time). If the fix only works on boards someone
// looked at, it is a fit, not a fix.
//
//     freeze corpus -> T1.1-T1.3 -> evaluate frozen corpus
//                   -> canary's kReportSampleIds
//                   -> ONE FRESH DRAW  <- this file
//
// "One" is meant literally. The seed below is fixed and must not be re-rolled:
// re-drawing until a draw passes is the same error as tuning against the corpus,
// just with extra steps. If this fails, P1 failed.
//
// ignore_for_file: avoid_print

@Tags(['slow'])
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'adversarial_corpus.dart';
import 'board_report_utils.dart';
import 'report_sample.dart';

/// Fixed, drawn once, disjoint from every population P1 was developed against.
const int kFreshDrawSeed = 20260820;

/// Over-drawn so that removing the held-out ids still leaves a full 100.
///
/// `sampleLevelIds` fills a set from one `Random(seed)` stream, so raising the
/// draw size *extends* the same sequence rather than re-rolling it: the first
/// 220 ids are bit-identical at 280. Sizing it to land on 100 after the
/// exclusions is bookkeeping, not a re-draw.
final List<int> kFreshDrawIds = () {
  final corpusIds = {for (final e in kAdversarialCorpus) e.levelId};
  final seen = {...corpusIds, ...kReportSampleIds};
  return [
    for (final id in sampleLevelIds(
      count: 300,
      minId: 1,
      maxId: 1500,
      seed: kFreshDrawSeed,
    ))
      if (!seen.contains(id)) id,
  ].take(100).toList();
}();

({int min, int p50, double shareAtMost6}) _profile(
  String label,
  DifficultyMode mode,
  DifficultyProfile profile,
) {
  final failures = <int>[];
  final rows = runCampaignBatch(
    levelIds: kFreshDrawIds,
    mode: mode,
    profile: profile,
    failures: failures,
    timeBudget: null,
  );
  expect(failures, isEmpty, reason: '$label: generation failed for $failures');
  expect(rows, hasLength(kFreshDrawIds.length));

  final taps = [for (final r in rows) r.tapsToWin]..sort();
  final share = rows.where((r) => r.tapsToWin <= 6).length / rows.length;
  final p50 = taps[(taps.length - 1) ~/ 2];
  print('$label (n=${taps.length}): min=${taps.first} p50=$p50 '
      'max=${taps.last} share(<=6)=${(share * 100).toStringAsFixed(1)}%');
  return (min: taps.first, p50: p50, shareAtMost6: share);
}

void main() {
  test('the fresh draw is genuinely held out', () {
    expect(kFreshDrawIds, hasLength(100));
    final corpusIds = {for (final e in kAdversarialCorpus) e.levelId};
    for (final id in kFreshDrawIds) {
      expect(corpusIds.contains(id), isFalse, reason: 'L$id is in the corpus');
      expect(kReportSampleIds.contains(id), isFalse,
          reason: 'L$id is in the canary sample');
    }
  });

  test('P1 gates hold on boards nobody looked at', () {
    final easy =
        _profile('EASY  ', DifficultyMode.easy, DifficultyProfile.easy);
    final medium =
        _profile('MEDIUM', DifficultyMode.medium, DifficultyProfile.medium);
    final hard =
        _profile('HARD  ', DifficultyMode.hard, DifficultyProfile.hard);

    expect(medium.shareAtMost6, lessThan(0.05));
    expect(medium.min, greaterThanOrEqualTo(6));

    expect(easy.shareAtMost6, equals(0.0));
    expect(easy.p50, greaterThanOrEqualTo(9));

    expect(hard.p50, closeTo(10, 1));
    expect(hard.min, greaterThanOrEqualTo(6));
  }, timeout: const Timeout(Duration(minutes: 30)));
}
