// Dev helper (not an assertion test): prints solved tap orders for manual
// on-device play. Driven by --dart-define=SOLVE_SPEC="mode:id,mode:id,…".
import 'package:flutter_test/flutter_test.dart';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/game/levels/level_solver.dart';

const _spec = String.fromEnvironment('SOLVE_SPEC');

void main() {
  test('dump solve orders', () {
    for (final item in _spec.split(',').where((s) => s.trim().isNotEmpty)) {
      final parts = item.split(':');
      final mode = parts[0];
      final id = int.parse(parts[1]);

      final LevelData level;
      if (mode == 'daily') {
        final y = id ~/ 10000, m = (id ~/ 100) % 100, d = id % 100;
        level = LevelManager.getDailyChallenge(DateTime(y, m, d));
      } else {
        final dm = switch (mode) {
          'easy' => DifficultyMode.easy,
          'medium' => DifficultyMode.medium,
          'hard' => DifficultyMode.hard,
          _ => throw ArgumentError('bad mode $mode'),
        };
        level = LevelManager.getLevel(id, mode: dm);
      }

      final active = [...level.nodes];
      final order = <String>[];
      var guard = 0;
      while (active.isNotEmpty && guard++ < 5000) {
        final hint = LevelSolver.getHint(active, level);
        if (hint == null) break;
        order.add('${hint.x},${hint.y}');
        active.removeWhere((n) => n.id == hint.id);
      }
      // ignore: avoid_print
      print('SOLVE|$mode|$id|grid=${level.gridWidth}x${level.gridHeight}'
          '|nodes=${level.nodes.length}|cores=${level.coreCount}'
          '|relays=${level.relayCount}|locks=${level.lockCount}'
          '|unsolved=${active.length}|order=${order.join(' ')}');
    }
  });
}
