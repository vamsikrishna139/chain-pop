import 'dart:async';

/// Owns gameplay timers for [GameScreen] so lifecycle stays centralized.
final class GameScreenTimerCoordinator {
  Timer? countdownTimer;
  Timer? autoAdvanceDelayTimer;
  Timer? autoAdvanceTimer;
  Timer? ghostHintTimer;
  Timer? easyHudTimer;
  Timer? tutorialExitTimer;
  Timer? goalIntroTimer;

  void cancelWinAdvanceTimers() {
    autoAdvanceDelayTimer?.cancel();
    autoAdvanceDelayTimer = null;
    autoAdvanceTimer?.cancel();
    autoAdvanceTimer = null;
  }

  void cancelGameplayTimers() {
    countdownTimer?.cancel();
    countdownTimer = null;
    ghostHintTimer?.cancel();
    ghostHintTimer = null;
    easyHudTimer?.cancel();
    easyHudTimer = null;
    tutorialExitTimer?.cancel();
    tutorialExitTimer = null;
    goalIntroTimer?.cancel();
    goalIntroTimer = null;
  }

  void disposeAll() {
    cancelWinAdvanceTimers();
    cancelGameplayTimers();
  }
}
