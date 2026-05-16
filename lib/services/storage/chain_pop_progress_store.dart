import '../../game/levels/generation/difficulty_mode.dart';
import 'chain_pop_storage.dart';
import 'storage_locator.dart';

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

/// Default implementation delegating to [ChainPopStorage] (via [StorageLocator]).
final class HiveChainPopProgressStore implements ChainPopProgressStore {
  HiveChainPopProgressStore([this._override]);

  final ChainPopStorage? _override;

  ChainPopStorage get _backend => _override ?? StorageLocator.instance;

  @override
  Future<void> accumulateLifetimeGameplaySeconds(int secs) =>
      _backend.accumulateLifetimeGameplaySeconds(secs);

  @override
  Future<void> incrementLifetimeCampaignClears() =>
      _backend.incrementLifetimeCampaignClears();

  @override
  Future<void> saveDailyStars(int dayKey, int earned) =>
      _backend.saveDailyStars(dayKey, earned);

  @override
  Future<void> saveStars(DifficultyMode mode, int levelId, int newStars) =>
      _backend.saveStars(mode, levelId, newStars);

  @override
  Future<void> setTutorialCompleted(bool value) =>
      _backend.setTutorialCompleted(value);

  @override
  Future<void> unlockLevel(DifficultyMode mode, int level) =>
      _backend.unlockLevel(mode, level);
}

/// Default Hive-backed store for menu/game navigation (tests may inject fakes).
final HiveChainPopProgressStore defaultHiveChainPopProgressStore =
    HiveChainPopProgressStore();
