import '../../game/levels/generation/difficulty_mode.dart';
import '../../models/game_settings.dart';
import '../achievements/achievement_counters.dart';

/// Low-level persistence boundary for Hive-backed gameplay state.
///
/// Prefer the synonym [ChainPopStorage] in new code; [StorageService] remains the
/// static façade (production tests use a temporary box via [HiveChainPopPersistence]).
abstract interface class ChainPopPersistence {
  Future<void> open();

  int get schemaVersionRead;

  // ── Coach / onboarding flags ───────────────────────────────────────────────

  bool get hintRewardAdCoachSeen;

  Future<void> setHintRewardAdCoachSeen();

  // ── Difficulty preference ─────────────────────────────────────────────────

  DifficultyMode get selectedDifficulty;

  Future<void> setSelectedDifficulty(DifficultyMode mode);

  // ── Preferences ───────────────────────────────────────────────────────────

  GameSettings get gameSettings;

  Future<void> saveGameSettings(GameSettings settings);

  // ── Level unlock ──────────────────────────────────────────────────────────

  int highestUnlocked(DifficultyMode mode);

  Future<void> unlockLevel(DifficultyMode mode, int level);

  // ── Stars ─────────────────────────────────────────────────────────────────

  int stars(DifficultyMode mode, int levelId);

  Future<void> saveStars(
    DifficultyMode mode,
    int levelId,
    int newStars,
  );

  int totalStarsInRange(
    DifficultyMode mode,
    int fromLevel,
    int toLevel,
  );

  // ── Daily challenge ───────────────────────────────────────────────────────

  int dailyStarsForDayKey(int dayKey);

  Future<void> saveDailyStars(int dayKey, int newStars);

  bool isDailyUnlockedViaAd(int dayKey);

  Future<void> markDailyUnlockedViaAd(int dayKey);

  // ── Tutorial ──────────────────────────────────────────────────────────────

  bool get tutorialCompleted;

  Future<void> setTutorialCompleted(bool value);

  // ── Premium / Subscription ────────────────────────────────────────────────

  bool get cachedPremium;

  Future<void> setCachedPremium(bool value);

  // ── Lifetime engagement ───────────────────────────────────────────────────

  int get lifetimeCampaignClears;

  int get lifetimeGameplaySeconds;

  bool get campaignInterstitialLifetimeGateSatisfied;

  Future<void> incrementLifetimeCampaignClears();

  Future<void> accumulateLifetimeGameplaySeconds(int delta);

  Future<void> seedLifetimeEngagementGateForTests();

  // ── Achievements (schema v3) ──────────────────────────────────────────────

  /// Reads one aggregate counter. Missing keys read as 0.
  int achievementCounter(AchievementCounter counter);

  /// Overwrites a counter. Prefer [bumpAchievementCounter] for sums and
  /// [raiseAchievementCounter] for high-water marks.
  Future<void> setAchievementCounter(AchievementCounter counter, int value);

  /// Adds [delta] (no-op when `delta <= 0`).
  Future<void> bumpAchievementCounter(AchievementCounter counter, int delta);

  /// Raises to [value] only if it exceeds the stored value — a monotonic
  /// high-water mark for "best ever" counters.
  Future<void> raiseAchievementCounter(AchievementCounter counter, int value);

  /// ORs [bits] into a bitmask counter.
  Future<void> orAchievementCounter(AchievementCounter counter, int bits);

  /// Locally recorded unlocks. Unlocks are permanent — an achievement stays
  /// unlocked even if the counter behind it could no longer satisfy the rule.
  Set<String> get unlockedAchievementIds;

  Future<void> markAchievementUnlocked(String id);

  /// Last step value successfully pushed to Play Games, per achievement id.
  /// Drives the sync queue: an entry whose desired steps equal its cursor is
  /// already in sync and is not re-sent.
  Map<String, int> get achievementSyncCursor;

  Future<void> setAchievementSyncCursor(String id, int steps);

  // ── Reset ─────────────────────────────────────────────────────────────────

  Future<void> clearProgress();

  Future<void> clearProgressForMode(DifficultyMode mode);
}
