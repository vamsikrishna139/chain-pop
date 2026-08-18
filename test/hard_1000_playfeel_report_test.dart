// Diagnostic harness #2: what the Hard campaign actually *feels* like to play.
// Measures effective level length (core-win fires early), decision density,
// and how much of each board is a free-tap mop-up.
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/metrics.dart';
import 'package:chain_pop/screens/game/game_time_limit.dart';

void main() {
  test('HARD 1000 — play-feel report', () {
    final gen = LevelGenerator();

    final tapsToWin = <double>[];
    final boardFracAtWin = <double>[];
    final freeAtStartFrac = <double>[];
    final noDecisionFrac = <double>[];
    final realDecisionSteps = <int>[];
    final bucket = <int, List<double>>{};
    var coreWinLevels = 0;
    var levels = 0;

    // Sample every 3rd level up to 600. The sector-7/8 tail is excluded here
    // only because those levels take 4-40s each to generate (see the latency
    // finding); structure is already flat well before then.
    for (var i = 1; i <= 600; i += 3) {
      final res = gen.generate(i,
          mode: DifficultyMode.hard,
          timeBudget: const Duration(milliseconds: 200));
      if (!res.isSuccess) continue;
      final lv = res.value;
      levels++;
      final n = lv.nodes.length;

      final cores = lv.nodes.where((c) => c.isCore).map((c) => c.id).toSet();
      if (cores.isNotEmpty) coreWinLevels++;

      // Effective length: play greedily but always take a core the moment it
      // is legal (an optimal core-rush). Everything after the last core is
      // auto-popped by the cascade finale, so it costs the player no taps.
      final remaining = lv.nodes.map((x) => x.clone()).toList();
      final pos = <int>{for (final x in remaining) _key(x)};
      var taps = 0;
      var coresLeft = cores.length;
      var wideSteps = 0;
      var steps = 0;
      var decisionSteps = 0;
      var firstWave = 0;

      while (coresLeft > 0 && remaining.isNotEmpty) {
        final legal = <NodeData>[];
        for (final x in remaining) {
          pos.remove(_key(x));
          final ok = LevelSolver.canRemoveWithPositions(x, pos, lv);
          pos.add(_key(x));
          if (ok) legal.add(x);
        }
        if (legal.isEmpty) break;
        if (steps == 0) firstWave = legal.length;
        steps++;
        if (legal.length >= 8) wideSteps++;
        if (legal.length >= 2) decisionSteps++;

        // prefer a core if legal, else the node that unlocks the most
        NodeData pick = legal.firstWhere((x) => cores.contains(x.id),
            orElse: () => legal.first);
        if (cores.contains(pick.id)) coresLeft--;
        taps++;
        pos.remove(_key(pick));
        remaining.removeWhere((x) => x.id == pick.id);
      }

      tapsToWin.add(taps.toDouble());
      boardFracAtWin.add(taps / n);
      freeAtStartFrac.add(firstWave / n);
      noDecisionFrac.add(steps == 0 ? 0 : wideSteps / steps);
      realDecisionSteps.add(decisionSteps);

      final b = (i - 1) ~/ 100;
      bucket.putIfAbsent(b, () => []).add(taps / n);
    }

    double avg(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

    print('\n#### PLAY-FEEL over $levels HARD levels');
    print('core-win levels: $coreWinLevels / $levels');
    print('avg taps to trigger the win: ${avg(tapsToWin).toStringAsFixed(1)}');
    print('avg fraction of the board the player actually pops: '
        '${(avg(boardFracAtWin) * 100).toStringAsFixed(1)}%  '
        '(the rest is the auto cascade)');
    print('avg fraction of the board legal on turn 1: '
        '${(avg(freeAtStartFrac) * 100).toStringAsFixed(1)}%');
    print('avg fraction of turns with >=8 legal moves (no real decision): '
        '${(avg(noDecisionFrac) * 100).toStringAsFixed(1)}%');

    print('\nboard-fraction-popped by 100-level bucket:');
    for (var b = 0; b < 10; b++) {
      final v = bucket[b];
      if (v == null) continue;
      print('  ${(b * 100 + 1).toString().padLeft(4)}-${(b + 1) * 100}: '
          '${(avg(v) * 100).toStringAsFixed(1)}%');
    }

    // Can a level be lost by playing badly (other than the clock)?
    print('\nfail-state check: relay-free Chain Pop is monotone, so no tap order '
        'can strand the board. The only loss condition is the countdown.');
    final gen2 = LevelGenerator();
    var timePressure = <double>[];
    for (var i = 1; i <= 600; i += 17) {
      final res = gen2.generate(i, mode: DifficultyMode.hard);
      if (!res.isSuccess) continue;
      final lv = res.value;
      final limit =
          computeGameTimeLimit(DifficultyMode.hard, lv.nodes.length, i) ?? 0;
      timePressure.add(limit / lv.nodes.length);
    }
    print('avg seconds of countdown per node: '
        '${avg(timePressure).toStringAsFixed(2)}s  '
        '(SWIFT 3-star needs half of that)');

    // How similar are consecutive levels' opening positions?
    final gen3 = LevelGenerator();
    var same = 0, tot = 0;
    String? prev;
    for (var i = 1; i <= 200; i++) {
      final res = gen3.generate(i, mode: DifficultyMode.hard);
      if (!res.isSuccess) continue;
      final m = LevelMetrics.compute(res.value);
      final sig = '${res.value.nodes.length}|${m.waveDepth}|${m.waveZeroWidth}|'
          '${m.forcedSequenceRatio.toStringAsFixed(1)}';
      if (prev == sig) same++;
      if (prev != null) tot++;
      prev = sig;
    }
    print('consecutive levels with an identical coarse difficulty signature '
        '(nodes|waves|opening|FSR): $same / $tot');
  });
}

int _key(NodeData n) => (n.y << 16) | n.x;
