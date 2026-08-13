/// Tunables for [GameScreen] timing, lives, and win overlay behavior.
///
/// Centralizes magic numbers so gameplay pacing and tests stay aligned.
abstract final class GameScreenConstants {
  GameScreenConstants._();

  static const int maxLives = 3;
  static const int winAutoAdvanceSeconds = 5;
  static const int winAutoAdvanceDelayMs = 700;

  /// Fast clears under this elapsed time use the lightweight [QuickWinBanner]
  /// flow-preserving transition instead of the full win panel.
  static const int quickWinMaxClearMs = 20000;
  static const int sessionGoalIntroMs = 4000;

  /// How long the [QuickWinBanner] shows before auto-advancing.
  static const int quickWinBannerMs = 1500;
  static const int ghostHintDelaySeconds = 4;

  /// Tutorial steps 0–1 coach the very first taps: pulse the single legal node
  /// sooner (and repeatedly) so a brand-new player never stalls.
  static const int tutorialCoachHintDelaySeconds = 2;
  static const int winStarAnimationMs = 450;
  static const int winStarStaggerBaseMs = 200;
  static const int winStarStaggerStepMs = 150;

  /// Confetti burst on level clear ([WinCelebrationOverlay]).
  static const Duration winConfettiDuration = Duration(milliseconds: 2900);
  static const int winConfettiParticleCount = 88;
  /// Gravity scale multiplied by min(screen width, height) px/s².
  static const double winConfettiGravity = 1.05;
}
