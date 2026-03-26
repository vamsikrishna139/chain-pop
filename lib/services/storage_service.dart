import 'package:hive/hive.dart';

class StorageService {
  static const String _boxName = 'chain_pop_storage';
  static const String _levelKey = 'highest_unlocked_level';

  static late Box _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Gets the highest unlocked level (1-indexed). Defaults to 1.
  static int get highestUnlockedLevel {
    return _box.get(_levelKey, defaultValue: 1);
  }

  /// Sets the highest unlocked level.
  static Future<void> unlockLevel(int level) async {
    final current = highestUnlockedLevel;
    if (level > current) {
      await _box.put(_levelKey, level);
    }
  }

  /// Clears progress for testing.
  static Future<void> clearProgress() async {
    await _box.put(_levelKey, 1);
  }
}
