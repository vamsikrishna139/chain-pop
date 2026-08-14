/// Persisted aggregate counters behind the achievement catalog.
///
/// Kept as one enum rather than twenty storage members so adding a counter is a
/// one-line change. [storageKey] is written to Hive — **never rename a key**,
/// and never reuse one for a different meaning.
///
/// Bitmask counters ([silhouetteFamilyMask], [directiveThreeStarMask],
/// [flagsMask]) are OR-accumulated; the rest are monotonic sums or maxima.
enum AchievementCounter {
  /// Nodes on boards that were won. See `AchievementStats.nodesCleared`.
  nodesCleared('ach_nodes_cleared'),

  /// Stars summed across all three difficulty tracks. Maintained as a running
  /// aggregate because `totalStarsInRange` is per-mode and scanning three modes
  /// over a thousand levels on every win is a full box scan.
  totalStars('ach_total_stars'),

  coresExtracted('ach_cores_extracted'),
  locksOpened('ach_locks_opened'),
  relaysCleared('ach_relays_cleared'),
  phaseGatesCleared('ach_phase_gates_cleared'),
  portalsTraversed('ach_portals_traversed'),

  dailyCompleted('ach_daily_completed'),
  dailyArchived('ach_daily_archived'),

  /// Current run of consecutive days with a completed level.
  currentPlayStreakDays('ach_streak_current'),

  /// Best run ever. Achievements read this one, so breaking a streak never
  /// revokes a badge.
  bestPlayStreakDays('ach_streak_best'),

  /// `dayKey` of the last day a level was completed. Guards the streak against
  /// double-counting a day and against a device clock moving backwards.
  lastPlayDayKey('ach_streak_last_day'),

  /// Current and best runs of consecutive jam-free wins. Persisted because
  /// `SessionCampaignStreak` is session-scoped and resets on relaunch.
  currentJamFreeRun('ach_jamfree_current'),
  bestJamFreeRun('ach_jamfree_best'),

  /// Best count of 3-starred Guardians inside any single sector, any mode.
  bestSectorGuardians('ach_sector_guardians_best'),

  /// One bit per `SilhouetteVisualFamily`.
  silhouetteFamilyMask('ach_silhouette_families'),

  /// One bit per `LevelDirective` that has been 3-starred.
  directiveThreeStarMask('ach_directives_three_star'),

  /// One bit per `AchievementFlag`.
  flagsMask('ach_flags');

  const AchievementCounter(this.storageKey);

  /// Hive key. Persisted — do not rename.
  final String storageKey;
}
