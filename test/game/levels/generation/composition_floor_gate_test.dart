// The composition regression guard, as an ASSERTION.
//
// Until T2.10a this gate existed only as a number written in
// `IMPLEMENTATION_PLAN_V2.md` and checked by eye against a `report`-tagged
// sweep that asserts nothing (plan §0.5). It could not go red on its own; the
// Medium breach after T2.6/T2.7 was found by hand, and could as easily have
// been missed. A gate nothing enforces is documentation.
//
// **Window.** L301-800, deliberately not L1-300. The old Medium floor of 0.63
// was the shipped p10 of L1-300, and T2.10a's control showed it was never met
// on later windows even on the *pre-P2b* tree (0.6097 / 0.6246 there vs 0.6530
// on L1-300). Gating on the window a threshold was overfit to is how the
// overfit survives. Generation is sequential because the diversity ledger is
// session state.
//
// **Tagged `slow`, and that is a real cost.** It generates 800 levels per mode.
// The default suite cannot carry it, which means it gates nothing on an
// ordinary `flutter test` — the same weakness that let the relay soft-lock
// reach a corpus. It is therefore a **pre-freeze checklist item**, not a
// background safety net:
//
//     flutter test --tags slow test/game/levels/generation/composition_floor_gate_test.dart
library;

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/difficulty_profile.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/visual_composition.dart';
import 'package:flutter_test/flutter_test.dart';

import 'board_report_utils.dart';

const int _kWindowStart = 301;
const int _kWindowEnd = 800;

void main() {
  test('shipped composition p10 holds its re-derived floor', () {
    for (final e in [
      (DifficultyMode.medium, DifficultyTier.medium),
      (DifficultyMode.hard, DifficultyTier.hard),
    ]) {
      final floor = kCompositionFloor[e.$2]!;
      final gen = LevelGenerator();
      final scores = <double>[];
      for (var id = 1; id <= _kWindowEnd; id++) {
        final r = gen.generate(id, mode: e.$1, timeBudget: kProdBudget);
        if (!r.isSuccess || id < _kWindowStart) continue;
        scores.add(evaluateVisualComposition(r.value, e.$2).score);
      }
      scores.sort();
      final p10 = scores[((scores.length - 1) * 0.10).round()];
      expect(p10, greaterThanOrEqualTo(floor),
          reason: '${e.$1.name} shipped composition p10 is '
              '${p10.toStringAsFixed(4)}, below its floor of $floor '
              '(n=${scores.length}, L$_kWindowStart-$_kWindowEnd). '
              'Re-derive only with the T2.10a method: fresh corpus, bootstrap '
              'lower tail, held-out validation — never by nudging the constant '
              'to whatever the current tree happens to produce.');
    }
  }, tags: 'slow');
}
