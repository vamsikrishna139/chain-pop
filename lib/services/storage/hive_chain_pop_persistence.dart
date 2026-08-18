import 'package:hive/hive.dart';

import '../../game/levels/generation/difficulty_mode.dart';
import '../../models/difficulty.dart';
import '../../models/game_settings.dart';
import '../../utils/safe_hive_values.dart';
import '../achievements/achievement_counters.dart';
import 'chain_pop_storage.dart';

/// Hive implementation of [ChainPopStorage] / [ChainPopPersistence].
final class HiveChainPopPersistence implements ChainPopStorage {
  HiveChainPopPersistence();

  static const String boxName = 'chain_pop_storage';
  static const String _schemaKey = '_chain_pop_storage_schema';

  /// At least one of lifetime clears / gameplay seconds must reach these before
  /// between-level campaign interstitials engage (first-player protection).
  static const int campaignInterstitialMinLifetimeClears = 5;

  /// ~10 minutes; pairs with clears gate under OR semantics.
  static const int campaignInterstitialMinGameplaySeconds = 600;

  static const int _schemaVersion = 3;

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
  static const String _settingsAimRayKey = 'settings_aim_ray';
  static const String _settingsAmbientMotionKey = 'settings_ambient_motion';

  static const String _hintRewardCoachSeenKey = 'hint_reward_coach_seen';

  static const String _achievementUnlockedKey = 'ach_unlocked_ids';
  static const String _achievementCursorKey = 'ach_sync_cursor';

  /// Ceiling for achievement counters. Generous enough for the 150,000-node
  /// tier with headroom, small enough that a corrupt value cannot overflow.
  static const int _achievementCounterMax = 1 << 30;

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

    if (stored < 3) {
      await _migrateToV3();
    }

    await _box.put(_schemaKey, _schemaVersion);
  }

  /// Generation-gap migrations — keep idempotent for reruns / corrupted markers.
  Future<void> _migrateToV2({required int fromVersion}) async {
    if (fromVersion < 1) {
      // Reserved for legacy installs predating explicit schema versioning.
    }
  }

  /// Seeds the achievement aggregates introduced with the Play Games catalog.
  ///
  /// Only counters that can be honestly reconstructed from existing keys are
  /// seeded. Star totals and Daily completions are both fully recoverable —
  /// the per-level and per-day records already exist. Everything else
  /// (nodes cleared, per-mechanic tallies, streak history) has no historical
  /// record, so it legitimately starts at zero for existing players.
  ///
  /// Idempotent: re-running recomputes the same values from the same source
  /// keys rather than accumulating.
  Future<void> _migrateToV3() async {
    var stars = 0;
    var dailies = 0;
    for (final key in _box.keys) {
      final k = key.toString();
      if (k.startsWith(_starsPrefix)) {
        stars += coerceHiveInt(_box.get(key), fallback: 0, min: 0, max: 3);
      } else if (k.startsWith(_dailyStarsPrefix)) {
        if (coerceHiveInt(_box.get(key), fallback: 0, min: 0, max: 3) > 0) {
          dailies++;
        }
      }
    }
    await _box.put(AchievementCounter.totalStars.storageKey, stars);
    await _box.put(AchievementCounter.dailyCompleted.storageKey, dailies);
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
        showAimRay: coerceHiveBool(
          _box.get(_settingsAimRayKey),
          fallback: true,
        ),
        ambientMotion: coerceHiveBool(
          _box.get(_settingsAmbientMotionKey),
          fallback: true,
        ),
      );

  @override
  Future<void> saveGameSettings(GameSettings settings) async {
    await _box.put(_settingsSoundKey, settings.soundEnabled);
    await _box.put(_settingsHapticsKey, settings.hapticsEnabled);
    await _box.put(_settingsColorblindKey, settings.colorblindFriendly);
    await _box.put(_settingsAimRayKey, settings.showAimRay);
    await _box.put(_settingsAmbientMotionKey, settings.ambientMotion);
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
      // Keep the cross-mode aggregate in step with the per-level records; only
      // the improvement is added, so re-clearing a level never double-counts.
      await bumpAchievementCounter(
        AchievementCounter.totalStars,
        capped - current,
      );
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
      // A day counts once, on the transition from unplayed to played —
      // improving a day's score later must not inflate the completion tally.
      if (current == 0) {
        await bumpAchievementCounter(AchievementCounter.dailyCompleted, 1);
      }
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

  // ── Achievements ──────────────────────────────────────────────────────────

  @override
  int achievementCounter(AchievementCounter counter) => coerceHiveInt(
        _box.get(counter.storageKey),
        fallback: 0,
        min: 0,
        max: _achievementCounterMax,
      );

  @override
  Future<void> setAchievementCounter(
    AchievementCounter counter,
    int value,
  ) async {
    await _box.put(
      counter.storageKey,
      coerceHiveInt(value, fallback: 0, min: 0, max: _achievementCounterMax),
    );
  }

  @override
  Future<void> bumpAchievementCounter(
    AchievementCounter counter,
    int delta,
  ) async {
    if (delta <= 0) return;
    await setAchievementCounter(counter, achievementCounter(counter) + delta);
  }

  @override
  Future<void> raiseAchievementCounter(
    AchievementCounter counter,
    int value,
  ) async {
    if (value <= achievementCounter(counter)) return;
    await setAchievementCounter(counter, value);
  }

  @override
  Future<void> orAchievementCounter(
    AchievementCounter counter,
    int bits,
  ) async {
    if (bits == 0) return;
    final merged = achievementCounter(counter) | bits;
    await setAchievementCounter(counter, merged);
  }

  @override
  Set<String> get unlockedAchievementIds {
    final raw = _box.get(_achievementUnlockedKey);
    if (raw is! List) return const <String>{};
    return raw.whereType<String>().toSet();
  }

  @override
  Future<void> markAchievementUnlocked(String id) async {
    final current = unlockedAchievementIds;
    if (current.contains(id)) return;
    await _box.put(_achievementUnlockedKey, <String>[...current, id]);
  }

  @override
  Map<String, int> get achievementSyncCursor {
    final raw = _box.get(_achievementCursorKey);
    if (raw is! Map) return const <String, int>{};
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (k is String) {
        out[k] = coerceHiveInt(
          v,
          fallback: 0,
          min: 0,
          max: _achievementCounterMax,
        );
      }
    });
    return out;
  }

  @override
  Future<void> setAchievementSyncCursor(String id, int steps) async {
    final next = Map<String, int>.from(achievementSyncCursor);
    final safe = coerceHiveInt(
      steps,
      fallback: 0,
      min: 0,
      max: _achievementCounterMax,
    );
    if (next[id] == safe) return;
    next[id] = safe;
    await _box.put(_achievementCursorKey, next);
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
