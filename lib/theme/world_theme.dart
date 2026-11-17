import 'package:flutter/material.dart';
import '../game/world_registry.dart';
import 'app_colors.dart';

/// Per-world playfield palette derived from a single accent color.
///
/// Every color comes from one formula (lerp against [AppColors] roles), so the
/// four campaign worlds — plus the daily/tutorial fallback — stay visually
/// consistent without hand-tuned per-world literals.
class WorldTheme {
  final Color accent;

  /// Opaque canvas color painted by `ChainPopGame.backgroundColor()`.
  final Color backgroundTint;

  /// Fill for playable-cell tiles (silhouette rendering).
  final Color tileFill;

  /// 1px border around playable-cell tiles.
  final Color tileBorder;

  /// Soft glow stroked around the silhouette boundary.
  final Color silhouetteGlow;

  /// Opaque "tray" painted as one continuous rounded body under every
  /// playable cell, so an irregular mask reads as a single deliberate shape
  /// rather than scattered tiles. Sits between [backgroundTint] and
  /// [tileFill] in brightness.
  final Color trayFill;

  /// Thin crisp rim traced around the tray's outer edge.
  final Color trayRim;

  /// Faint marker drawn at the centre of in-frame void cells. Rays still
  /// travel through voids, so a hint of the grid there is honest, and it
  /// stops large holes from reading as dead screen.
  final Color voidMarker;

  /// Fill for "restored" cells left behind by extracted nodes.
  final Color restoredFill;

  /// Trace line connecting adjacent restored cells.
  final Color restoredTrace;

  const WorldTheme._({
    required this.accent,
    required this.backgroundTint,
    required this.tileFill,
    required this.tileBorder,
    required this.silhouetteGlow,
    required this.trayFill,
    required this.trayRim,
    required this.voidMarker,
    required this.restoredFill,
    required this.restoredTrace,
  });

  factory WorldTheme.fromAccent(Color accent) {
    Color lift(Color base, double towardWhite, double towardAccent) {
      final lifted = Color.lerp(base, Colors.white, towardWhite)!;
      return Color.lerp(lifted, accent, towardAccent)!;
    }

    return WorldTheme._(
      accent: accent,
      backgroundTint: lift(AppColors.background, 0.0, 0.05),
      tileFill: lift(AppColors.surface, 0.18, 0.14),
      tileBorder: Colors.white.withValues(alpha: 0.15),
      silhouetteGlow: accent.withValues(alpha: 0.38),
      trayFill: lift(AppColors.surface, 0.07, 0.10),
      trayRim: accent.withValues(alpha: 0.35),
      voidMarker: Colors.white.withValues(alpha: 0.10),
      restoredFill: accent.withValues(alpha: 0.10),
      restoredTrace: accent.withValues(alpha: 0.16),
    );
  }

  /// Resolves the campaign world accent for [levelId]. Daily challenge and
  /// tutorial screens pass their own accent via [WorldTheme.fromAccent].
  factory WorldTheme.forLevel(int levelId) =>
      WorldTheme.fromAccent(worldForLevel(levelId).accent);
}
