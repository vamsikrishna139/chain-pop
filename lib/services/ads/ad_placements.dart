/// Logical placement identifiers for analytics and ad loading.
abstract final class AdPlacements {
  AdPlacements._();

  /// Rewarded: revive after running out of lives (hard campaign only).
  static const continueAfterLives = 'continue_after_lives';

  /// Rewarded: undo after free undos exhausted (cooldown gated in UI).
  static const undo = 'undo';

  /// Rewarded: hint after free hints exhausted (cooldown gated in UI).
  static const hint = 'hint';

  /// Interstitial between levels when campaign win streak is high enough.
  static const betweenLevelsStreak = 'between_levels_streak';

  /// Rewarded: play a daily challenge for a day before today (one-time unlock per day).
  static const dailyUnlockPast = 'daily_unlock_past';

  /// Banner: bottom of [DailyChallengeCalendarScreen].
  static const dailyChallengeCalendarBanner = 'daily_challenge_calendar_banner';

  /// Banner: bottom of [GamePauseOverlay] while paused (campaign + daily; not tutorial).
  static const gamePauseBanner = 'game_pause_banner';
}
