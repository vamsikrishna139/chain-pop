import '../../game/levels/level_manager.dart';
import '../../game/levels/generation/difficulty_mode.dart';
import 'storage_locator.dart';

/// Wipes local game progress: the game database (stars, unlocks, difficulty,
/// game settings) and the level-diversity history. The cached ad-free flag
/// survives (see `clearProgress`).
///
/// Shared by "Reset Game Data" and "Delete my data" so the two can't drift.
///
/// After a wipe the player has no progress anywhere, which is exactly the
/// fresh-install case the Gen V2 cut-over resolves to level 1. `clearProgress`
/// also erased the stored cut-over, so without this the in-memory map kept the
/// old per-mode cut-over (e.g. Hard from L51) and served V1 boards for L1–50
/// until the next restart, when bootstrap would re-resolve it to 1. Clearing
/// the map instead would be worse: an empty map means V1 everywhere.
Future<void> resetLocalProgress() async {
  final storage = StorageLocator.instance;
  await storage.clearProgress();
  for (final mode in DifficultyMode.values) {
    LevelManager.genV2FromLevel[mode] = 1;
    await storage.saveGenV2FromLevel(mode, 1);
  }
  LevelManager.generator.diversityLedger.clear();
  LevelManager.clearServedLevels();
}
