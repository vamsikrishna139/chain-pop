import '../../game/levels/generation/difficulty_mode.dart';
import '../../models/game_settings.dart';

/// Injectable persistence boundary for Hive-backed gameplay state ([StorageService]
/// facade in production tests against a temporary box via [HiveChainPopPersistence]).
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

  // ── Lifetime engagement ───────────────────────────────────────────────────

  int get lifetimeCampaignClears;

  int get lifetimeGameplaySeconds;

  bool get campaignInterstitialLifetimeGateSatisfied;

  Future<void> incrementLifetimeCampaignClears();

  Future<void> accumulateLifetimeGameplaySeconds(int delta);

  Future<void> seedLifetimeEngagementGateForTests();

  // ── Reset ─────────────────────────────────────────────────────────────────

  Future<void> clearProgress();

  Future<void> clearProgressForMode(DifficultyMode mode);
}
