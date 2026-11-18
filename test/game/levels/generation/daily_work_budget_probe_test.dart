// W2.2 calibration: how much construction work an unbounded Daily spends, and
// what that costs in wall time, across a year of date keys. Diagnostic only.
//
//   flutter test test/game/levels/generation/daily_work_budget_probe_test.dart
// ignore_for_file: avoid_print

@Tags(['report'])
library;

import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:flutter_test/flutter_test.dart';

int _pct(List<int> sorted, double p) =>
    sorted[((sorted.length - 1) * p).round()];

void main() {
  test('daily work units across 2027', () {
    final work = <int>[];
    final ms = <int>[];
    final rows = <String>[];
    var day = DateTime(2027, 1, 1);
    while (day.year == 2027) {
      final key = day.year * 10000 + day.month * 100 + day.day;
      final gen = LevelGenerator.neutral();
      final sw = Stopwatch()..start();
      final r = gen.generateDailyChallenge(key);
      sw.stop();
      final units = gen.kloopIterations + gen.renegotiationCount;
      work.add(units);
      ms.add(sw.elapsedMilliseconds);
      rows.add('$key,$units,${sw.elapsedMilliseconds},${r.isSuccess}');
      day = day.add(const Duration(days: 1));
    }
    final ws = [...work]..sort();
    final mss = [...ms]..sort();
    print('n=${ws.length}');
    for (final p in [0.5, 0.75, 0.9, 0.95, 0.99, 1.0]) {
      print('p$p work=${_pct(ws, p)} ms=${_pct(mss, p)}');
    }
    final totalMs = ms.fold<int>(0, (a, b) => a + b);
    final totalWork = work.fold<int>(0, (a, b) => a + b);
    print('ms/unit=${(totalMs / totalWork).toStringAsFixed(2)}');
    final worst = List.generate(rows.length, (i) => i)
      ..sort((a, b) => ms[b].compareTo(ms[a]));
    print('worst: ${worst.take(10).map((i) => rows[i]).join('  ')}');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
