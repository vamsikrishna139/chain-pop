import 'package:hive/hive.dart';

import '../../game/levels/generation/difficulty_mode.dart';
import '../../models/difficulty.dart';
import '../../models/game_settings.dart';
import '../../utils/safe_hive_values.dart';
import 'chain_pop_persistence.dart';

/// Hive implementation of [ChainPopPersistence].
final class HiveChainPopPersistence implements ChainPopPersistence {
  HiveChainPopPersistence();

  static const String boxName = 'chain_pop_storage';
  static const String _schemaKey = '_chain_pop_storage_schema';

  /// At least one of lifetime clears / gameplay seconds must reach these before
  /// between-level campaign interstitials engage (first-player protection).
  static const int campaignInterstitialMinLifetimeClears = 5;

  /// ~10 minutes; pairs with clears gate under OR semantics.
  static const int campaignInterstitialMinGameplaySeconds = 600;

  static const int _schemaVersion = 2;

  static const String _difficultyKey = 'selected_difficulty';
  static const String _unlockedPrefix = 'unlocked_';
  static const String _starsPrefix = 'stars_';
  static const String _dailyStarsPrefix = 'daily_stars_';
  static const String _dailyAdUnlockPrefix = 'daily_ad_unlock_';
  static const String _tutorialCompletedKey = 'tutorial_completed';

  static const String _lifetimeCampaignClearsKey =
      'lifetime_campaign_level_clears';
  static const String _lifetimeGameplaySecondsKey =
      'lifetime_gameplay_seconds';
  static const String _settingsSoundKey = 'settings_sound';
  static const String _settingsHapticsKey = 'settings_haptics';
  static const String _settingsColorblindKey = 'settings_colorblind';

  static const String _hintRewardCoachSeenKey = 'hint_reward_coach_seen';

  late Box<dynamic> _box;

  Box<dynamic> get boxForTests => _box;

  @override
  Future<void> open() async {
    _box = await Hive.openBox<dynamic>(boxName);
    await _ensureSchemaAndMigrate();
  }

  @override
  int get schemaVersionRead => coerceHiveInt(
        _box.get(_schemaKey),
        fallback: 0,
        min: 0,
        max: 999,
      );

  /// Reserved for forward-compatible one-time transforms when [_schemaVersion]
  /// bumps (key renames, value normalizations). Keep migrations idempotent.
  Future<void> _ensureSchemaAndMigrate() async {
    final stored = schemaVersionRead;
    if (stored >= _schemaVersion) return;

    if (stored < 2) {
      await _migrateToV2(fromVersion: stored);
    }

    await _box.put(_schemaKey, _schemaVersion);
  }

  /// Generation-gap migrations — keep idempotent for reruns / corrupted markers.
  Future<void> _migrateToV2({required int fromVersion}) async {
    if (fromVersion < 1) {
      // Reserved for legacy installs predating explicit schema versioning.
    }
  }

  @override
  bool get hintRewardAdCoachSeen => coerceHiveBool(
        _box.get(_hintRewardCoachSeenKey),
        fallback: false,
      );

  @override
  Future<void> setHintRewardAdCoachSeen() async {
    await _box.put(_hintRewardCoachSeenKey, true);
  }

  @override
  DifficultyMode get selectedDifficulty {
    final raw = _box.get(_difficultyKey, defaultValue: 'easy');
    if (raw is! String) return DifficultyMode.easy;
    return DifficultyExt.fromKey(raw);
  }

  @override
  Future<void> setSelectedDifficulty(DifficultyMode mode) async {
    await _box.put(_difficultyKey, mode.key);
  }

  @override
  GameSettings get gameSettings => GameSettings(
        soundEnabled: coerceHiveBool(
          _box.get(_settingsSoundKey),
          fallback: true,
        ),
        hapticsEnabled: coerceHiveBool(
          _box.get(_settingsHapticsKey),
          fallback: true,
        ),
        colorblindFriendly: coerceHiveBool(
          _box.get(_settingsColorblindKey),
          fallback: false,
        ),
      );

  @override
  Future<void> saveGameSettings(GameSettings settings) async {
    await _box.put(_settingsSoundKey, settings.soundEnabled);
    await _box.put(_settingsHapticsKey, settings.hapticsEnabled);
    await _box.put(_settingsColorblindKey, settings.colorblindFriendly);
  }

  @override
  int highestUnlocked(DifficultyMode mode) {
    return coerceHiveInt(
      _box.get('$_unlockedPrefix${mode.key}'),
      fallback: 1,
      min: 1,
      max: 1 << 20,
    );
  }

  @override
  Future<void> unlockLevel(DifficultyMode mode, int level) async {
    final sanitized =
        coerceHiveInt(level, fallback: 1, min: 1, max: 1 << 20);
    final current = highestUnlocked(mode);
    if (sanitized > current) {
      await _box.put('$_unlockedPrefix${mode.key}', sanitized);
    }
  }

  @override
  int stars(DifficultyMode mode, int levelId) {
    return coerceHiveInt(
      _box.get('$_starsPrefix${mode.key}_$levelId'),
      fallback: 0,
      min: 0,
      max: 3,
    );
  }

  @override
  Future<void> saveStars(
    DifficultyMode mode,
    int levelId,
    int newStars,
  ) async {
    final capped = coerceHiveInt(newStars, fallback: 0, min: 0, max: 3);
    final current = stars(mode, levelId);
    if (capped > current) {
      await _box.put('$_starsPrefix${mode.key}_$levelId', capped);
    }
  }

  @override
  int totalStarsInRange(
    DifficultyMode mode,
    int fromLevel,
    int toLevel,
  ) {
    if (toLevel < fromLevel || fromLevel < 1) return 0;
    var sum = 0;
    for (var i = fromLevel; i <= toLevel; i++) {
      sum += stars(mode, i);
    }
    return sum;
  }

  @override
  int dailyStarsForDayKey(int dayKey) {
    return coerceHiveInt(
      _box.get('$_dailyStarsPrefix$dayKey'),
      fallback: 0,
      min: 0,
      max: 3,
    );
  }

  @override
  Future<void> saveDailyStars(int dayKey, int newStars) async {
    final capped = coerceHiveInt(newStars, fallback: 0, min: 0, max: 3);
    final current = dailyStarsForDayKey(dayKey);
    if (capped > current) {
      await _box.put('$_dailyStarsPrefix$dayKey', capped);
    }
  }

  @override
  bool isDailyUnlockedViaAd(int dayKey) {
    return coerceHiveBool(
      _box.get('$_dailyAdUnlockPrefix$dayKey'),
      fallback: false,
    );
  }

  @override
  Future<void> markDailyUnlockedViaAd(int dayKey) async {
    await _box.put('$_dailyAdUnlockPrefix$dayKey', true);
  }

  @override
  bool get tutorialCompleted => coerceHiveBool(
        _box.get(_tutorialCompletedKey),
        fallback: false,
      );

  @override
  Future<void> setTutorialCompleted(bool value) async {
    await _box.put(_tutorialCompletedKey, value);
  }

  @override
  int get lifetimeCampaignClears => coerceHiveInt(
        _box.get(_lifetimeCampaignClearsKey),
        fallback: 0,
        min: 0,
        max: 1 << 28,
      );

  @override
  int get lifetimeGameplaySeconds => coerceHiveInt(
        _box.get(_lifetimeGameplaySecondsKey),
        fallback: 0,
        min: 0,
        max: 1 << 30,
      );

  @override
  bool get campaignInterstitialLifetimeGateSatisfied =>
      lifetimeCampaignClears >= campaignInterstitialMinLifetimeClears ||
      lifetimeGameplaySeconds >= campaignInterstitialMinGameplaySeconds;

  @override
  Future<void> incrementLifetimeCampaignClears() async {
    final next = coerceHiveInt(
      lifetimeCampaignClears + 1,
      fallback: 0,
      min: 0,
      max: 1 << 28,
    );
    await _box.put(_lifetimeCampaignClearsKey, next);
  }

  @override
  Future<void> accumulateLifetimeGameplaySeconds(int delta) async {
    if (delta <= 0) return;
    final safe = coerceHiveInt(delta, fallback: 0, min: 0, max: 8 * 3600);
    final sum = coerceHiveInt(
      lifetimeGameplaySeconds + safe,
      fallback: 0,
      min: 0,
      max: 1 << 30,
    );
    await _box.put(_lifetimeGameplaySecondsKey, sum);
  }

  /// Re-applies `_ensureSchemaAndMigrate()` (tests that delete `_chain_pop_storage_schema`).
  Future<void> reconcileSchemaMarker() => _ensureSchemaAndMigrate();

  /// Bypasses onboarding protection for deterministic interstitial regressions only.
  @override
  Future<void> seedLifetimeEngagementGateForTests() async {
    await _box.put(
      _lifetimeCampaignClearsKey,
      campaignInterstitialMinLifetimeClears,
    );
  }

  @override
  Future<void> clearProgress() async {
    await _box.clear();
    await _box.put(_schemaKey, _schemaVersion);
  }

  @override
  Future<void> clearProgressForMode(DifficultyMode mode) async {
    await _box.delete('$_unlockedPrefix${mode.key}');
    for (final key in _box.keys.toList()) {
      if (key.toString().startsWith('$_starsPrefix${mode.key}_')) {
        await _box.delete(key);
      }
    }
  }
}
