import 'achievement_tracker.dart';

/// Service location for the achievement tracker, mirroring [StorageLocator]
/// and [AdsLocator].
///
/// Unlike those two this one self-installs a default rather than throwing.
/// Achievement tracking is strictly additive to gameplay — a missing tracker
/// should never be able to take down a level win — so callers get a working
/// local-only tracker even if bootstrap never ran.
abstract final class AchievementsLocator {
  AchievementsLocator._();

  static AchievementTracker? _instance;

  static AchievementTracker get instance =>
      _instance ??= AchievementTracker();

  static void install(AchievementTracker tracker) {
    _instance = tracker;
  }

  /// Clears the holder. Tests that install a fake should call this in teardown.
  static void uninstall() => _instance = null;
}
