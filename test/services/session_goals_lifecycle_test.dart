import 'package:chain_pop/services/session_goals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void forceGoal(SessionGoalKind kind) {
    for (var i = 0; i <= SessionGoalKind.values.length; i++) {
      if (SessionGoals.active == kind) return;
      SessionGoals.resetSession();
    }
    fail('could not force goal $kind');
  }

  setUp(SessionGoals.resetSession);

  group('skipIfUnachievable', () {
    test('rotates a fresh Restore-cores goal off a coreless board', () {
      forceGoal(SessionGoalKind.restoreCores);
      SessionGoals.skipIfUnachievable(boardHasCores: false);
      expect(SessionGoals.active, isNot(SessionGoalKind.restoreCores));
    });

    test('keeps Restore-cores when the board has cores', () {
      forceGoal(SessionGoalKind.restoreCores);
      SessionGoals.skipIfUnachievable(boardHasCores: true);
      expect(SessionGoals.active, SessionGoalKind.restoreCores);
    });

    test('keeps Restore-cores once the player has made progress', () {
      forceGoal(SessionGoalKind.restoreCores);
      SessionGoals.recordCoresRestored(2);
      SessionGoals.skipIfUnachievable(boardHasCores: false);
      expect(SessionGoals.active, SessionGoalKind.restoreCores);
      expect(SessionGoals.progress, 2);
    });

    test('leaves other goals alone', () {
      forceGoal(SessionGoalKind.winThree);
      SessionGoals.skipIfUnachievable(boardHasCores: false);
      expect(SessionGoals.active, SessionGoalKind.winThree);
    });
  });

  group('onReturnToMenu', () {
    test('keeps an unfinished goal and its progress', () {
      forceGoal(SessionGoalKind.winThree);
      SessionGoals.recordWin(surge: false);
      SessionGoals.onReturnToMenu();
      expect(SessionGoals.active, SessionGoalKind.winThree);
      expect(SessionGoals.progress, 1);
    });

    test('rotates a completed goal', () {
      forceGoal(SessionGoalKind.clearSurge);
      expect(SessionGoals.recordWin(surge: true), isTrue);
      SessionGoals.onReturnToMenu();
      expect(SessionGoals.isComplete, isFalse);
      expect(SessionGoals.active, isNot(SessionGoalKind.clearSurge));
    });
  });
}
