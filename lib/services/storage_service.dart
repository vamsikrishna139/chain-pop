import 'package:flutter/foundation.dart';

import '../game/levels/generation/difficulty_mode.dart';
import '../models/game_settings.dart';
import 'storage/chain_pop_persistence.dart';
import 'storage/hive_chain_pop_persistence.dart';
import 'storage/storage_locator.dart';

/// Thin facade over [ChainPopPersistence] (`StorageLocator.instance`).
///
/// **Scope:** device-local, unencrypted game state only.
///
/// Legacy key layout unchanged — see [HiveChainPopPersistence].
class StorageService {
  StorageService._();

  static ChainPopPersistence get _p => StorageLocator.instance;

  /// Mirrors [HiveChainPopPersistence.campaignInterstitialMinLifetimeClears].
  static const int campaignInterstitialMinLifetimeClears =
      HiveChainPopPersistence.campaignInterstitialMinLifetimeClears;

  /// Mirrors [HiveChainPopPersistence.campaignInterstitialMinGameplaySeconds].
  static const int campaignInterstitialMinGameplaySeconds =
      HiveChainPopPersistence.campaignInterstitialMinGameplaySeconds;

  static Future<void> init() async {
    final persistence = HiveChainPopPersistence();
    await persistence.open();
    StorageLocator.install(persistence);
  }

  /// Replaces persistence for deterministic tests (`FakeChainPopPersistence`, etc.).
  @visibleForTesting
  static void installForTesting(ChainPopPersistence persistence) {
    StorageLocator.install(persistence);
  }

  @visibleForTesting
  static void uninstallForTesting() => StorageLocator.uninstall();

  @visibleForTesting
  static int get debugSchemaMarkerOrZero => _p.schemaVersionRead;

  static bool get hintRewardAdCoachSeen =>
      StorageLocator.instance.hintRewardAdCoachSeen;

  static Future<void> setHintRewardAdCoachSeen() =>
      StorageLocator.instance.setHintRewardAdCoachSeen();

  static DifficultyMode get selectedDifficulty =>
      StorageLocator.instance.selectedDifficulty;

  static Future<void> setSelectedDifficulty(DifficultyMode mode) =>
      StorageLocator.instance.setSelectedDifficulty(mode);

  static GameSettings get gameSettings => StorageLocator.instance.gameSettings;

  static Future<void> saveGameSettings(GameSettings settings) =>
      StorageLocator.instance.saveGameSettings(settings);

  static int highestUnlocked(DifficultyMode mode) =>
      StorageLocator.instance.highestUnlocked(mode);

  static Future<void> unlockLevel(DifficultyMode mode, int level) =>
      StorageLocator.instance.unlockLevel(mode, level);

  static int stars(DifficultyMode mode, int levelId) =>
      StorageLocator.instance.stars(mode, levelId);

  static Future<void> saveStars(
    DifficultyMode mode,
    int levelId,
    int newStars,
  ) =>
      StorageLocator.instance.saveStars(mode, levelId, newStars);

  static int totalStarsInRange(
    DifficultyMode mode,
    int fromLevel,
    int toLevel,
  ) =>
      StorageLocator.instance.totalStarsInRange(mode, fromLevel, toLevel);

  static int dailyStarsForDayKey(int dayKey) =>
      StorageLocator.instance.dailyStarsForDayKey(dayKey);

  static Future<void> saveDailyStars(int dayKey, int newStars) =>
      StorageLocator.instance.saveDailyStars(dayKey, newStars);

  static bool isDailyUnlockedViaAd(int dayKey) =>
      StorageLocator.instance.isDailyUnlockedViaAd(dayKey);

  static Future<void> markDailyUnlockedViaAd(int dayKey) =>
      StorageLocator.instance.markDailyUnlockedViaAd(dayKey);

  static bool get tutorialCompleted =>
      StorageLocator.instance.tutorialCompleted;

  static Future<void> setTutorialCompleted(bool value) =>
      StorageLocator.instance.setTutorialCompleted(value);

  static int get lifetimeCampaignClears =>
      StorageLocator.instance.lifetimeCampaignClears;

  static int get lifetimeGameplaySeconds =>
      StorageLocator.instance.lifetimeGameplaySeconds;

  static bool get campaignInterstitialLifetimeGateSatisfied =>
      StorageLocator.instance.campaignInterstitialLifetimeGateSatisfied;

  static Future<void> incrementLifetimeCampaignClears() =>
      StorageLocator.instance.incrementLifetimeCampaignClears();

  static Future<void> accumulateLifetimeGameplaySeconds(int delta) =>
      StorageLocator.instance.accumulateLifetimeGameplaySeconds(delta);

  @visibleForTesting
  static Future<void> seedLifetimeEngagementGateForTests() =>
      StorageLocator.instance.seedLifetimeEngagementGateForTests();

  @Deprecated('Use highestUnlocked(DifficultyMode) instead')
  static int get highestUnlockedLevel =>
      StorageLocator.instance.highestUnlocked(
        StorageLocator.instance.selectedDifficulty,
      );

  @Deprecated('Use unlockLevel(DifficultyMode, int) instead')
  static Future<void> unlockLevelLegacy(int level) =>
      unlockLevel(selectedDifficulty, level);

  static Future<void> clearProgress() => StorageLocator.instance.clearProgress();

  static Future<void> clearProgressForMode(DifficultyMode mode) =>
      StorageLocator.instance.clearProgressForMode(mode);

  /// Re-runs idempotent schema migration (after tests delete `_chain_pop_storage_schema`).
  @visibleForTesting
  static Future<void> debugReconcileStorageSchemaMarker() async {
    final impl = StorageLocator.instance;
    if (impl is HiveChainPopPersistence) {
      await impl.reconcileSchemaMarker();
    }
  }
}
