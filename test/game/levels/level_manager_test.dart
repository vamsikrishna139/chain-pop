import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Structural and solvability invariants for [LevelManager.getLevel].
/// Playthrough correctness is covered in [regression_test.dart].
void main() {
  void assertLevelInvariants(int levelId, DifficultyMode mode) {
    final level = LevelManager.getLevel(levelId, mode: mode);

    expect(level.levelId, levelId);
    expect(level.gridWidth, inInclusiveRange(3, 20));
    expect(level.gridHeight, inInclusiveRange(3, 20));
    expect(level.nodes, isNotEmpty);

    final occupied = <String>{};
    for (final n in level.nodes) {
      expect(n.x, inInclusiveRange(0, level.gridWidth - 1));
      expect(n.y, inInclusiveRange(0, level.gridHeight - 1));
      final key = '${n.x},${n.y}';
      expect(occupied, isNot(contains(key)),
          reason: 'duplicate cell $key on $mode level $levelId');
      occupied.add(key);
    }

    final play = level.playCells;
    if (play != null && play.isNotEmpty) {
      for (final n in level.nodes) {
        expect(play, contains('${n.x},${n.y}'),
            reason: 'node outside playCells on $mode level $levelId');
      }
    }

    expect(
      LevelSolver.isSolvable(level),
      isTrue,
      reason: '$mode level $levelId should be solvable',
    );
    expect(
      LevelSolver.countRemovalWaves(level),
      greaterThanOrEqualTo(1),
      reason: '$mode level $levelId should need at least one removal wave',
    );
  }

  group('LevelManager.getLevel', () {
    test('satisfies invariants for levels 1–20 × all modes', () {
      for (final mode in DifficultyMode.values) {
        for (var id = 1; id <= 20; id++) {
          assertLevelInvariants(id, mode);
        }
      }
    });

    test('milestone-style ids (25, 50) still produce valid levels', () {
      for (final mode in DifficultyMode.values) {
        assertLevelInvariants(25, mode);
        assertLevelInvariants(50, mode);
      }
    });
  });

  group('LevelManager.getDailyChallenge', () {
    test('same date yields identical layout and solvable board', () {
      final day = DateTime(2026, 6, 15);
      final a = LevelManager.getDailyChallenge(day);
      final b = LevelManager.getDailyChallenge(day);
      expect(a.levelId, 20260615);
      expect(b.levelId, 20260615);
      expect(a.gridWidth, b.gridWidth);
      expect(a.gridHeight, b.gridHeight);
      expect(a.nodes.length, b.nodes.length);

      String sig(LevelData l) {
        final parts = l.nodes
            .map((n) => '${n.x},${n.y},${n.dir.name}')
            .toList()
          ..sort();
        return parts.join('|');
      }

      expect(sig(a), sig(b));
      expect(LevelSolver.isSolvable(a), isTrue);
    });

    test('distinct calendar days produce distinct layouts (not fallback strip)', () {
      final d1 = LevelManager.getDailyChallenge(DateTime(2026, 4, 1));
      final d2 = LevelManager.getDailyChallenge(DateTime(2026, 4, 2));
      String sig(LevelData l) {
        final parts = l.nodes
            .map((n) => '${n.x},${n.y},${n.dir.name}')
            .toList()
          ..sort();
        return '${l.nodes.length}|${parts.join('|')}';
      }

      expect(sig(d1), isNot(sig(d2)));
      expect(LevelSolver.isSolvable(d1), isTrue);
      expect(LevelSolver.isSolvable(d2), isTrue);
    });
  });
}
