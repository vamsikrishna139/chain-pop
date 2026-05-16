import '../../game/levels/generation/difficulty_mode.dart';
import '../storage_service.dart';

/// Persistence facade for campaign / daily progression used by [GameScreen].
///
/// Tests may inject a fake; production defaults to Hive-backed storage.
abstract interface class ChainPopProgressStore {
  Future<void> saveStars(DifficultyMode mode, int levelId, int newStars);

  Future<void> unlockLevel(DifficultyMode mode, int level);

  Future<void> incrementLifetimeCampaignClears();

  Future<void> accumulateLifetimeGameplaySeconds(int secs);

  Future<void> saveDailyStars(int dayKey, int earned);

  Future<void> setTutorialCompleted(bool value);
}

/// Default implementation delegating to [StorageService].
final class HiveChainPopProgressStore implements ChainPopProgressStore {
  const HiveChainPopProgressStore();

  @override
  Future<void> accumulateLifetimeGameplaySeconds(int secs) =>
      StorageService.accumulateLifetimeGameplaySeconds(secs);

  @override
  Future<void> incrementLifetimeCampaignClears() =>
      StorageService.incrementLifetimeCampaignClears();

  @override
  Future<void> saveDailyStars(int dayKey, int earned) =>
      StorageService.saveDailyStars(dayKey, earned);

  @override
  Future<void> saveStars(DifficultyMode mode, int levelId, int newStars) =>
      StorageService.saveStars(mode, levelId, newStars);

  @override
  Future<void> setTutorialCompleted(bool value) =>
      StorageService.setTutorialCompleted(value);

  @override
  Future<void> unlockLevel(DifficultyMode mode, int level) =>
      StorageService.unlockLevel(mode, level);
}

/// Default Hive-backed store for menu/game navigation (tests may inject fakes).
const HiveChainPopProgressStore defaultHiveChainPopProgressStore =
    HiveChainPopProgressStore();
