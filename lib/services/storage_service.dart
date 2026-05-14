import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../game/levels/generation/difficulty_mode.dart';
import '../models/difficulty.dart';
import '../models/game_settings.dart';
import '../utils/safe_hive_values.dart';

/// Persistent storage for all game progress using Hive.
///
/// **Scope:** device-local, unencrypted game state only. Do not store secrets,
/// tokens, or PII here — treat the box as untrusted input on read (see
/// [coerceHiveBool] / [coerceHiveInt]).
///
/// Keys layout:
/// ```
/// _chain_pop_storage_schema    → int migration marker (see [_schemaVersion])
/// selected_difficulty          → 'easy' | 'medium' | 'hard'
/// unlocked_easy                → highest unlocked level (easy)
/// unlocked_medium              → highest unlocked level (medium)
/// unlocked_hard                → highest unlocked level (hard)
/// stars_easy_<levelId>         → 0-3
/// stars_medium_<levelId>       → 0-3
/// stars_hard_<levelId>         → 0-3
/// daily_stars_<YYYYMMDD>       → 0-3 (best result that local calendar day)
/// daily_ad_unlock_<YYYYMMDD>   → true after rewarded ad (older / off-window days)
/// tutorial_completed           → true after finishing the 5-step onboarding track
/// lifetime_campaign_level_clears → count of cleared campaign wins (lifetime)
/// lifetime_gameplay_seconds    → non-tutorial gameplay time from [GameScreen] disposes
/// ```
class StorageService {
  static const String _boxName = 'chain_pop_storage';
  static const String _schemaKey = '_chain_pop_storage_schema';
  static const int _schemaVersion = 1;

  static const String _difficultyKey = 'selected_difficulty';
  static const String _unlockedPrefix = 'unlocked_';
  static const String _starsPrefix = 'stars_';
  static const String _dailyStarsPrefix = 'daily_stars_';
  static const String _dailyAdUnlockPrefix = 'daily_ad_unlock_';
  static const String _tutorialCompletedKey = 'tutorial_completed';

  /// At least one of [#lifetimeCampaignClears] / [#lifetimeGameplaySeconds] must
  /// reach these before between-level campaign interstitials engage (first-player protection).
  static const int campaignInterstitialMinLifetimeClears = 5;

  /// ~10 minutes; pairs with clears gate under OR semantics.
  static const int campaignInterstitialMinGameplaySeconds = 600;

  static const String _lifetimeCampaignClearsKey = 'lifetime_campaign_level_clears';
  static const String _lifetimeGameplaySecondsKey = 'lifetime_gameplay_seconds';
  static const String _settingsSoundKey = 'settings_sound';
  static const String _settingsHapticsKey = 'settings_haptics';
  static const String _settingsColorblindKey = 'settings_colorblind';

  static late Box<dynamic> _box;

  static Future<void> init() async {
    _box = await Hive.openBox<dynamic>(_boxName);
    await _ensureSchemaAndMigrate();
  }

  /// Reserved for forward-compatible one-time transforms when [_schemaVersion]
  /// bumps (key renames, value normalizations). Keep migrations idempotent.
  static Future<void> _ensureSchemaAndMigrate() async {
    final stored = coerceHiveInt(
      _box.get(_schemaKey),
      fallback: 0,
      min: 0,
      max: 999,
    );
    if (stored >= _schemaVersion) return;

    // Example: if (stored < 1) { await _migrateToV1(); }
    await _box.put(_schemaKey, _schemaVersion);
  }

  // ── Difficulty preference ─────────────────────────────────────────────────

  /// Returns the player's globally selected difficulty. Defaults to easy.
  static DifficultyMode get selectedDifficulty {
    final raw = _box.get(_difficultyKey, defaultValue: 'easy');
    if (raw is! String) return DifficultyMode.easy;
    return DifficultyExt.fromKey(raw);
  }

  /// Persists the player's difficulty selection.
  static Future<void> setSelectedDifficulty(DifficultyMode mode) async {
    await _box.put(_difficultyKey, mode.key);
  }

  // ── Gameplay / accessibility preferences ─────────────────────────────────

  static GameSettings get gameSettings => GameSettings(
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

  static Future<void> saveGameSettings(GameSettings settings) async {
    await _box.put(_settingsSoundKey, settings.soundEnabled);
    await _box.put(_settingsHapticsKey, settings.hapticsEnabled);
    await _box.put(_settingsColorblindKey, settings.colorblindFriendly);
  }

  // ── Level unlock tracking (per difficulty) ────────────────────────────────

  /// Highest unlocked level for [mode]. Defaults to 1.
  static int highestUnlocked(DifficultyMode mode) {
    return coerceHiveInt(
      _box.get('$_unlockedPrefix${mode.key}'),
      fallback: 1,
      min: 1,
      max: 1 << 20,
    );
  }

  /// Unlocks [level] for [mode] if it is higher than the current maximum.
  static Future<void> unlockLevel(DifficultyMode mode, int level) async {
    final sanitized = coerceHiveInt(level, fallback: 1, min: 1, max: 1 << 20);
    final current = highestUnlocked(mode);
    if (sanitized > current) {
      await _box.put('$_unlockedPrefix${mode.key}', sanitized);
    }
  }

  // ── Star ratings (per difficulty, per level) ──────────────────────────────

  /// Returns stars earned (0–3) for [levelId] on [mode].
  static int stars(DifficultyMode mode, int levelId) {
    return coerceHiveInt(
      _box.get('$_starsPrefix${mode.key}_$levelId'),
      fallback: 0,
      min: 0,
      max: 3,
    );
  }

  /// Records [newStars] for [levelId] on [mode], only updating if higher.
  static Future<void> saveStars(
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

  /// Sum of stars for levels \[fromLevel, toLevel] inclusive (for UI bands).
  static int totalStarsInRange(
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

  // ── Daily challenge (local calendar [dayKey] = YYYYMMDD) ───────────────────

  /// Best stars (0–3) saved for the daily puzzle on [dayKey].
  static int dailyStarsForDayKey(int dayKey) {
    return coerceHiveInt(
      _box.get('$_dailyStarsPrefix$dayKey'),
      fallback: 0,
      min: 0,
      max: 3,
    );
  }

  /// Stores [newStars] for [dayKey] only when higher than the saved value.
  static Future<void> saveDailyStars(int dayKey, int newStars) async {
    final capped = coerceHiveInt(newStars, fallback: 0, min: 0, max: 3);
    final current = dailyStarsForDayKey(dayKey);
    if (capped > current) {
      await _box.put('$_dailyStarsPrefix$dayKey', capped);
    }
  }

  /// Rewarded-ad unlock for playing a daily outside the free calendar window.
  static bool isDailyUnlockedViaAd(int dayKey) {
    return coerceHiveBool(
      _box.get('$_dailyAdUnlockPrefix$dayKey'),
      fallback: false,
    );
  }

  static Future<void> markDailyUnlockedViaAd(int dayKey) async {
    await _box.put('$_dailyAdUnlockPrefix$dayKey', true);
  }

  // ── Onboarding tutorial ───────────────────────────────────────────────────

  /// Whether the player finished the fixed 5-level tutorial track.
  static bool get tutorialCompleted => coerceHiveBool(
        _box.get(_tutorialCompletedKey),
        fallback: false,
      );

  static Future<void> setTutorialCompleted(bool value) async {
    await _box.put(_tutorialCompletedKey, value);
  }

  // ── Monetization lifetime engagement signals (device-local aggregates) ────

  /// Cleared campaign levels (tutorial / daily excluded), monotonic lifetime count.
  static int get lifetimeCampaignClears => coerceHiveInt(
        _box.get(_lifetimeCampaignClearsKey),
        fallback: 0,
        min: 0,
        max: 1 << 28,
      );

  /// Seconds of non-tutorial [GameScreen] time accumulated from screen disposals.
  static int get lifetimeGameplaySeconds => coerceHiveInt(
        _box.get(_lifetimeGameplaySecondsKey),
        fallback: 0,
        min: 0,
        max: 1 << 30,
      );

  /// OR gate: qualifies the player for between-level campaign interstitials beyond streak rules.
  static bool get campaignInterstitialLifetimeGateSatisfied =>
      lifetimeCampaignClears >= campaignInterstitialMinLifetimeClears ||
      lifetimeGameplaySeconds >= campaignInterstitialMinGameplaySeconds;

  /// Called once per cleared campaign win (mirror [StorageService.unlockLevel] intent).
  static Future<void> incrementLifetimeCampaignClears() async {
    final next =
        coerceHiveInt(lifetimeCampaignClears + 1, fallback: 0, min: 0, max: 1 << 28);
    await _box.put(_lifetimeCampaignClearsKey, next);
  }

  /// Accumulates guarded seconds when a gameplay screen is disposed (non-tutorial only).
  static Future<void> accumulateLifetimeGameplaySeconds(int delta) async {
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

  /// Bypasses onboarding protection for deterministic interstitial regressions only.
  @visibleForTesting
  static Future<void> seedLifetimeEngagementGateForTests() async {
    await _box.put(_lifetimeCampaignClearsKey, campaignInterstitialMinLifetimeClears);
  }

  // ── Legacy compat (used by old code paths) ────────────────────────────────

  /// @deprecated Use [highestUnlocked] with an explicit [mode].
  static int get highestUnlockedLevel => highestUnlocked(selectedDifficulty);

  /// @deprecated Use [unlockLevel] with an explicit [mode].
  static Future<void> unlockLevelLegacy(int level) =>
      unlockLevel(selectedDifficulty, level);

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Clears all progress (useful for testing / debug).
  ///
  /// Includes [tutorialCompleted] and all other Hive keys in this box.
  static Future<void> clearProgress() async {
    await _box.clear();
    await _box.put(_schemaKey, _schemaVersion);
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
