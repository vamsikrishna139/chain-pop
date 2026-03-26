import 'level.dart';
import 'level_generator.dart';

class LevelManager {
  static LevelData getLevel(int levelId) {
    // We always use the generator now to ensure consistency and solvability
    return LevelGenerator.generate(levelId);
  }
}
