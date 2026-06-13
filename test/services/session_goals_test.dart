import 'package:chain_pop/services/session_goals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lands the rotating session goal on a specific kind for deterministic tests.
  void forceGoal(SessionGoalKind kind) {
    for (var i = 0; i <= SessionGoalKind.values.length; i++) {
      if (SessionGoals.active == kind) return;
      SessionGoals.resetSession();
    }
    fail('could not force goal $kind');
  }

  setUp(SessionGoals.resetSession);

  group('SessionGoals progress', () {
    test('Win 3 levels completes on the third win', () {
      forceGoal(SessionGoalKind.winThree);
      expect(SessionGoals.recordWin(surge: false), isFalse);
      expect(SessionGoals.recordWin(surge: false), isFalse);
      expect(SessionGoals.progress, 2);
      expect(SessionGoals.recordWin(surge: false), isTrue);
      expect(SessionGoals.isComplete, isTrue);
      // Fires completion only once.
      expect(SessionGoals.recordWin(surge: false), isFalse);
    });

    test('Reach a ×6 combo completes when the streak hits 6', () {
      forceGoal(SessionGoalKind.comboSix);
      expect(SessionGoals.recordStreak(3), isFalse);
      expect(SessionGoals.recordStreak(5), isFalse);
      expect(SessionGoals.progress, 5);
      expect(SessionGoals.recordStreak(6), isTrue);
      expect(SessionGoals.isComplete, isTrue);
    });

    test('combo goal ignores wins; win goal ignores streaks', () {
      forceGoal(SessionGoalKind.comboSix);
      expect(SessionGoals.recordWin(surge: false), isFalse);
      expect(SessionGoals.progress, 0);

      forceGoal(SessionGoalKind.winThree);
      expect(SessionGoals.recordStreak(9), isFalse);
      expect(SessionGoals.progress, 0);
    });

    test('Clear a SURGE completes only on a surge win', () {
      forceGoal(SessionGoalKind.clearSurge);
      expect(SessionGoals.recordWin(surge: false), isFalse);
      expect(SessionGoals.progress, 0);
      expect(SessionGoals.recordWin(surge: true), isTrue);
      expect(SessionGoals.isComplete, isTrue);
    });

    test('resetSession clears progress and rotates the goal', () {
      final first = SessionGoals.active;
      SessionGoals.recordWin(surge: true);
      SessionGoals.resetSession();
      expect(SessionGoals.progress, 0);
      expect(SessionGoals.isComplete, isFalse);
      // Rotation advances so sessions vary.
      final second = SessionGoals.active;
      expect(second, isNot(first));
    });
  });

  group('SessionGoals — core/flawless/nodes goals', () {
    test('Restore 5 reactors accumulates cores across wins', () {
      forceGoal(SessionGoalKind.restoreCores);
      expect(SessionGoals.recordCoresRestored(3), isFalse);
      expect(SessionGoals.progress, 3);
      // A 0-core (non-core) win never advances it.
      expect(SessionGoals.recordCoresRestored(0), isFalse);
      expect(SessionGoals.progress, 3);
      expect(SessionGoals.recordCoresRestored(3), isTrue);
      expect(SessionGoals.isComplete, isTrue);
    });

    test('Clear 120 nodes accumulates node counts', () {
      forceGoal(SessionGoalKind.clearNodes);
      expect(SessionGoals.recordNodesCleared(70), isFalse);
      expect(SessionGoals.recordNodesCleared(49), isFalse);
      expect(SessionGoals.progress, 119);
      expect(SessionGoals.recordNodesCleared(1), isTrue);
    });

    test('Win 2 levels jam-free completes on the second flawless win', () {
      forceGoal(SessionGoalKind.flawlessClear);
      expect(SessionGoals.recordFlawlessWin(), isFalse);
      expect(SessionGoals.recordFlawlessWin(), isTrue);
      expect(SessionGoals.isComplete, isTrue);
    });

    test('each goal ignores the other signal types', () {
      forceGoal(SessionGoalKind.restoreCores);
      expect(SessionGoals.recordNodesCleared(200), isFalse);
      expect(SessionGoals.recordFlawlessWin(), isFalse);
      expect(SessionGoals.recordWin(surge: true), isFalse);
      expect(SessionGoals.progress, 0);
    });
  });

  group('SessionGoals.seedRotation', () {
    test('seeds the opening goal by day and is idempotent', () {
      SessionGoals.debugReset();
      // dayKey % 6 == 3 → restoreCores.
      SessionGoals.seedRotation(3);
      expect(SessionGoals.active, SessionGoalKind.restoreCores);
      // A second seed in the same run is ignored.
      SessionGoals.seedRotation(0);
      expect(SessionGoals.active, SessionGoalKind.restoreCores);
    });

    test('does nothing once a goal is already active', () {
      SessionGoals.debugReset();
      final opening = SessionGoals.active; // forces _active (index 0).
      SessionGoals.seedRotation(3);
      expect(SessionGoals.active, opening);
    });
  });

  group('DefaultSessionGoalsController', () {
    test('exposes active goal, clamped progress, and target', () {
      forceGoal(SessionGoalKind.winThree);
      const c = defaultSessionGoalsController;
      expect(c.activeGoal, SessionGoalKind.winThree);
      expect(c.target, 3);
      c.recordWin(surge: false);
      expect(c.progress, 1);
      // Over-target progress is clamped for display.
      c.recordWin(surge: false);
      c.recordWin(surge: false);
      c.recordWin(surge: false);
      expect(c.progress, 3);
      expect(c.isComplete, isTrue);
    });
  });
}
