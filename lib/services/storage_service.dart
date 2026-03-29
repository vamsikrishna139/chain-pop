import 'package:hive/hive.dart';
import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../models/game_settings.dart';

/// Persistent storage for all game progress using Hive.
///
/// Keys layout:
/// ```
/// selected_difficulty          → 'easy' | 'medium' | 'hard'
/// unlocked_easy                → highest unlocked level (easy)
/// unlocked_medium              → highest unlocked level (medium)
/// unlocked_hard                → highest unlocked level (hard)
/// stars_easy_<levelId>         → 0-3
/// stars_medium_<levelId>       → 0-3
/// stars_hard_<levelId>         → 0-3
/// ```
class StorageService {
  static const String _boxName = 'chain_pop_storage';
  static const String _difficultyKey = 'selected_difficulty';
  static const String _unlockedPrefix = 'unlocked_';
  static const String _starsPrefix = 'stars_';
  static const String _settingsSoundKey = 'settings_sound';
  static const String _settingsHapticsKey = 'settings_haptics';
  static const String _settingsColorblindKey = 'settings_colorblind';

  static late Box _box;

  static Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  // ── Difficulty preference ─────────────────────────────────────────────────

  /// Returns the player's globally selected difficulty. Defaults to easy.
  static DifficultyMode get selectedDifficulty {
    final key = _box.get(_difficultyKey, defaultValue: 'easy') as String;
    return DifficultyExt.fromKey(key);
  }

  /// Persists the player's difficulty selection.
  static Future<void> setSelectedDifficulty(DifficultyMode mode) async {
    await _box.put(_difficultyKey, mode.key);
  }

  // ── Gameplay / accessibility preferences ─────────────────────────────────

  static GameSettings get gameSettings => GameSettings(
        soundEnabled: _box.get(_settingsSoundKey, defaultValue: true) as bool,
        hapticsEnabled: _box.get(_settingsHapticsKey, defaultValue: true) as bool,
        colorblindFriendly:
            _box.get(_settingsColorblindKey, defaultValue: false) as bool,
      );

  static Future<void> saveGameSettings(GameSettings settings) async {
    await _box.put(_settingsSoundKey, settings.soundEnabled);
    await _box.put(_settingsHapticsKey, settings.hapticsEnabled);
    await _box.put(_settingsColorblindKey, settings.colorblindFriendly);
  }

  // ── Level unlock tracking (per difficulty) ────────────────────────────────

  /// Highest unlocked level for [mode]. Defaults to 1.
  static int highestUnlocked(DifficultyMode mode) {
    return _box.get('$_unlockedPrefix${mode.key}', defaultValue: 1) as int;
  }

  /// Unlocks [level] for [mode] if it is higher than the current maximum.
  static Future<void> unlockLevel(DifficultyMode mode, int level) async {
    final current = highestUnlocked(mode);
    if (level > current) {
      await _box.put('$_unlockedPrefix${mode.key}', level);
    }
  }

  // ── Star ratings (per difficulty, per level) ──────────────────────────────

  /// Returns stars earned (0–3) for [levelId] on [mode].
  static int stars(DifficultyMode mode, int levelId) {
    return _box.get('$_starsPrefix${mode.key}_$levelId', defaultValue: 0) as int;
  }

  /// Records [newStars] for [levelId] on [mode], only updating if higher.
  static Future<void> saveStars(
    DifficultyMode mode,
    int levelId,
    int newStars,
  ) async {
    final current = stars(mode, levelId);
    if (newStars > current) {
      await _box.put('$_starsPrefix${mode.key}_$levelId', newStars);
    }
  }

  // ── Legacy compat (used by old code paths) ────────────────────────────────

  /// @deprecated Use [highestUnlocked] with an explicit [mode].
  static int get highestUnlockedLevel => highestUnlocked(selectedDifficulty);

  /// @deprecated Use [unlockLevel] with an explicit [mode].
  static Future<void> unlockLevelLegacy(int level) =>
      unlockLevel(selectedDifficulty, level);

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Clears all progress (useful for testing / debug).
  static Future<void> clearProgress() async {
    await _box.clear();
  }

  /// Clears progress only for [mode].
  static Future<void> clearProgressForMode(DifficultyMode mode) async {
    await _box.delete('$_unlockedPrefix${mode.key}');
    for (final key in _box.keys.toList()) {
      if (key.toString().startsWith('$_starsPrefix${mode.key}_')) {
        await _box.delete(key);
      }
    }
  }
}
