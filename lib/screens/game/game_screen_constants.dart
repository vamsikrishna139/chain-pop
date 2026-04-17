/// Tunables for [GameScreen] timing, lives, and win overlay behavior.
///
/// Centralizes magic numbers so gameplay pacing and tests stay aligned.
abstract final class GameScreenConstants {
  GameScreenConstants._();

  static const int maxLives = 3;
  static const int winAutoAdvanceSeconds = 5;
  static const int winAutoAdvanceDelayMs = 700;
  static const int ghostHintDelaySeconds = 4;
  static const int winStarAnimationMs = 450;
  static const int winStarStaggerBaseMs = 200;
  static const int winStarStaggerStepMs = 150;
}
