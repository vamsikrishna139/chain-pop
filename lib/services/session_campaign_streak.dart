import '../game/levels/generation/difficulty_mode.dart';

/// Completed **campaign** wins counted toward the between-level interstitial (not
/// tutorial / daily).
///
/// Increments only on a cleared level ([onWin]). [reset] clears the count after a
/// between-level interstitial is shown, or when the player returns to the main menu.
///
/// **Not** reset on fouls, level restart, game over, or time up — so imperfect
/// runs still accumulate completed wins toward the next ad.
abstract final class SessionCampaignStreak {
  SessionCampaignStreak._();

  /// Wins needed in a row before a between-level interstitial may show on the next transition.
  static int interstitialStreakThreshold(DifficultyMode mode) => switch (mode) {
        DifficultyMode.easy => 4,
        DifficultyMode.medium => 3,
        DifficultyMode.hard => 2,
      };

  static int _wins = 0;

  static int get wins => _wins;

  static void reset() => _wins = 0;

  static void onWin() => _wins++;
}
