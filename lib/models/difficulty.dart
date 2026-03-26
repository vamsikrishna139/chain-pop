import 'package:flutter/material.dart';
import '../game/levels/generation/difficulty_mode.dart';

/// Extension on [DifficultyMode] that adds UI metadata.
///
/// Centralises all difficulty-to-visual mappings so every screen
/// reads from one source of truth.
extension DifficultyExt on DifficultyMode {
  // ── Labels ───────────────────────────────────────────────────────────────

  /// Short display label, e.g. "EASY"
  String get label {
    switch (this) {
      case DifficultyMode.easy:   return 'EASY';
      case DifficultyMode.medium: return 'MEDIUM';
      case DifficultyMode.hard:   return 'HARD';
    }
  }

  /// Lowercase key used as Hive storage key segment.
  String get key {
    switch (this) {
      case DifficultyMode.easy:   return 'easy';
      case DifficultyMode.medium: return 'medium';
      case DifficultyMode.hard:   return 'hard';
    }
  }

  // ── Colors ───────────────────────────────────────────────────────────────

  /// Primary accent colour for this difficulty.
  Color get color {
    switch (this) {
      case DifficultyMode.easy:   return const Color(0xFF00F2FE); // cyan
      case DifficultyMode.medium: return const Color(0xFFFFC371); // amber
      case DifficultyMode.hard:   return const Color(0xFFFF5F6D); // crimson
    }
  }

  /// Dimmed version of the accent (30 % opacity) for backgrounds/borders.
  Color get dimColor => color.withOpacity(0.30);

  /// Very subtle tint used on the game board background.
  Color get boardTint => color.withOpacity(0.04);

  // ── Icons ────────────────────────────────────────────────────────────────

  /// Icon representing this difficulty level.
  IconData get icon {
    switch (this) {
      case DifficultyMode.easy:   return Icons.bolt_outlined;
      case DifficultyMode.medium: return Icons.local_fire_department_outlined;
      case DifficultyMode.hard:   return Icons.whatshot;
    }
  }

  // ── Star thresholds ───────────────────────────────────────────────────────

  /// Calculates 1–3 stars based on [jamCount].
  ///
  /// ⭐⭐⭐ = no jams at all (perfect run)
  /// ⭐⭐  = 1 or 2 jams
  /// ⭐   = 3+ jams or restarted at least once
  int starsForJams(int jamCount) {
    if (jamCount == 0) return 3;
    if (jamCount <= 2) return 2;
    return 1;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parses a stored string key back to a [DifficultyMode].
  static DifficultyMode fromKey(String key) {
    switch (key) {
      case 'medium': return DifficultyMode.medium;
      case 'hard':   return DifficultyMode.hard;
      default:       return DifficultyMode.easy;
    }
  }
}
