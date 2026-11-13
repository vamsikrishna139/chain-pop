import '../../game/levels/level_manager.dart';
import 'storage_locator.dart';

/// Wipes local game progress: the game database (stars, unlocks, difficulty,
/// game settings) and the level-diversity history. The cached ad-free flag
/// survives (see `clearProgress`).
///
/// Shared by "Reset Game Data" and "Delete my data" so the two can't drift.
Future<void> resetLocalProgress() async {
  await StorageLocator.instance.clearProgress();
  LevelManager.generator.diversityLedger.clear();
  LevelManager.clearServedLevels();
}
