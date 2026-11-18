// W2.7 — what flipping `PortalRollout.enabled` would do, measured before
// anyone flips it. Same populations both ways: Medium and Hard L601–1000
// (portals are budgeted from sector 6) and the 365 Dailies of 2027.
//
//   flutter test test/game/levels/generation/portal_rollout_report_test.dart \
//     --plain-name "rollout hard on"
// Each writes docs/playtests/portal_rollout/<name>.md.
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'dart:io';

import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/generation/progression_profile.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

class _Tally {
  _Tally(this.name);
  final String name;
  int n = 0, ok = 0, unsolvable = 0, withPortals = 0, relayAndPortal = 0;
  int retrograde = 0, failures = 0, exhausted = 0;
  final ms = <int>[];
  final unsolvableIds = <String>[];

  void add(String id, Result<LevelData, GenerationError> r, int elapsedMs) {
    n++;
    ms.add(elapsedMs);
    if (!r.isSuccess) return;
    ok++;
    final l = r.value;
    if (!LevelSolver.isSolvable(l)) {
      unsolvable++;
      unsolvableIds.add(id);
    }
    if (l.portalPairs.isNotEmpty) {
      withPortals++;
      if (l.relayCount > 0) relayAndPortal++;
    }
  }

  String report() {
    final s = [...ms]..sort();
    int q(double p) => s[((s.length - 1) * p).round()];
    final total = ms.fold<int>(0, (a, b) => a + b);
    return '## $name\n\n'
        '- generated: $ok / $n; unsolvable: $unsolvable'
        '${unsolvableIds.isEmpty ? '' : ' (${unsolvableIds.take(10).join(', ')})'}\n'
        '- boards with portals: $withPortals; with portal + relay: '
        '$relayAndPortal\n'
        '- retrograde attempts: $retrograde; construction failures: '
        '$failures; attempts exhausted: $exhausted\n'
        '- gen ms: p50 ${q(.5)}  p90 ${q(.9)}  p99 ${q(.99)}  max ${q(1)}  '
        'total ${(total / 1000).toStringAsFixed(1)} s\n';
  }
}

void _write(_Tally t) {
  final f = File('docs/playtests/portal_rollout/${t.name}.md');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(t.report());
  print(t.report());
}

void _campaign(DifficultyMode mode, bool on) {
  PortalRollout.enabled = on;
  addTearDown(() => PortalRollout.enabled = false);
  final t = _Tally('${mode.name}_L601-1000_${on ? 'on' : 'off'}');
  final gen = LevelGenerator.neutral();
  for (var id = 601; id <= 1000; id++) {
    final sw = Stopwatch()..start();
    final r = gen.generate(id, mode: mode);
    t.add('L$id', r, sw.elapsedMilliseconds);
  }
  t
    ..retrograde = gen.retrogradeAttemptCount
    ..failures = gen.constructionFailures
    ..exhausted = gen.snapshotSession().maxAttemptsExhaustedCount;
  _write(t);
}

void _daily(bool on) {
  PortalRollout.enabled = on;
  addTearDown(() => PortalRollout.enabled = false);
  final t = _Tally('daily_2027_${on ? 'on' : 'off'}');
  var day = DateTime(2027, 1, 1);
  while (day.year == 2027) {
    final key = day.year * 10000 + day.month * 100 + day.day;
    final gen = LevelGenerator.neutral();
    final sw = Stopwatch()..start();
    final r = gen.generateDailyChallenge(key,
        workBudget: LevelManager.dailyWorkBudget);
    t.add('$key', r, sw.elapsedMilliseconds);
    t
      ..retrograde += gen.retrogradeAttemptCount
      ..failures += gen.constructionFailures
      ..exhausted += gen.snapshotSession().maxAttemptsExhaustedCount;
    day = day.add(const Duration(days: 1));
  }
  _write(t);
}

void main() {
  const t = Timeout(Duration(minutes: 60));
  for (final on in [false, true]) {
    final tag = on ? 'on' : 'off';
    test('rollout medium $tag', () => _campaign(DifficultyMode.medium, on),
        timeout: t);
    test('rollout hard $tag', () => _campaign(DifficultyMode.hard, on),
        timeout: t);
    test('rollout daily $tag', () => _daily(on), timeout: t);
  }
}
