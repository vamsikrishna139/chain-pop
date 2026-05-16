import '../game/levels/generation/difficulty_mode.dart';

/// Completed **campaign** wins counted toward the between-level interstitial (not
/// tutorial / daily).
///
/// Increments only on a cleared level ([onWin]). [reset] clears the count after a
/// between-level interstitial is shown, or when the player returns to the main menu.
///
/// **Not** reset on fouls, level restart, game over, or time up — so imperfect
/// runs still accumulate completed wins toward the next ad.
///
/// **Isolates / tests:** `_wins` lives in isolate-static memory ([wins]). The default
/// Flutter test runner is single-isolate sequential; parallel VM shards are separate
/// processes. For deterministic unit tests inject [CampaignStreakTracker] rather than
/// depending on streak side effects from other suites in the same isolate.
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

/// Injectable façade so [GameScreen] tests can observe streak side-effects without globals.
abstract interface class CampaignStreakTracker {
  void onCampaignWin();

  void resetSession();
}

final class DefaultCampaignStreakTracker implements CampaignStreakTracker {
  const DefaultCampaignStreakTracker();

  @override
  void onCampaignWin() => SessionCampaignStreak.onWin();

  @override
  void resetSession() => SessionCampaignStreak.reset();
}

/// Default tracker wired to [SessionCampaignStreak] static counters.
const CampaignStreakTracker defaultCampaignStreakTracker =
    DefaultCampaignStreakTracker();
