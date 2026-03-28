import 'package:flutter/material.dart';

/// Single source of truth for every color literal in Chain Pop.
///
/// Named after *role*, not hue, so the palette can evolve without renaming
/// dozens of call-sites.
abstract final class AppColors {
  // ── Backgrounds ──────────────────────────────────────────────────────────

  static const background = Color(0xFF0F0F13);
  static const surface = Color(0xFF14141C);
  static const surfaceDialog = Color(0xFF1A1A22);

  // ── Node palette ─────────────────────────────────────────────────────────

  static const nodeDefault = Color(0xFF4FACFE);

  static const nodePalette = <Color>[
    Color(0xFF60EFFF),
    Color(0xFF00FF87),
    Color(0xFFFF5F6D),
    Color(0xFFFFC371),
    Color(0xFFA18CD1),
    Color(0xFF4FACFE),
  ];

  // ── Difficulty accents ───────────────────────────────────────────────────

  static const accentEasy = Color(0xFF00F2FE);
  static const accentMedium = Color(0xFFFFC371);
  static const accentHard = Color(0xFFFF5F6D);

  // ── Semantic ─────────────────────────────────────────────────────────────

  static const starGold = Color(0xFFFFC371);
  static const timerWarning = Color(0xFFFF5F6D);
  static const timerCaution = Color(0xFFFFC371);

  // ── Guide overlay ────────────────────────────────────────────────────────

  static const guideLineAlpha = 0.14;
}
