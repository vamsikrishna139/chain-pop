import 'package:chain_pop/game/world_registry.dart';
import 'package:chain_pop/theme/app_colors.dart';
import 'package:chain_pop/theme/world_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorldTheme', () {
    test('forLevel resolves the campaign world accent', () {
      expect(WorldTheme.forLevel(1).accent, worldForLevel(1).accent);
      expect(WorldTheme.forLevel(30).accent, worldForLevel(30).accent);
      expect(WorldTheme.forLevel(60).accent, worldForLevel(60).accent);
      expect(WorldTheme.forLevel(90).accent, worldForLevel(90).accent);
    });

    test('different world accents produce different background tints', () {
      final tints = kWorlds
          .map((w) => WorldTheme.fromAccent(w.accent).backgroundTint)
          .toSet();
      expect(tints.length, kWorlds.length,
          reason: 'each world should be visually distinct in-play');
    });

    test('backgroundTint stays close to the base background', () {
      for (final w in kWorlds) {
        final tint = WorldTheme.fromAccent(w.accent).backgroundTint;
        // 5% lerp: never a loud background, always a dark stage.
        expect(
          (tint.computeLuminance() - AppColors.background.computeLuminance())
              .abs(),
          lessThan(0.05),
        );
      }
    });

    test('tileFill is lighter than the background so silhouettes read', () {
      for (final w in kWorlds) {
        final theme = WorldTheme.fromAccent(w.accent);
        expect(
          theme.tileFill.computeLuminance(),
          greaterThan(theme.backgroundTint.computeLuminance()),
        );
      }
    });

    test('overlay colors are translucent', () {
      final theme = WorldTheme.fromAccent(const Color(0xFF00E5FF));
      expect(theme.silhouetteGlow.a, lessThan(0.5));
      expect(theme.restoredFill.a, lessThan(0.5));
      expect(theme.restoredTrace.a, lessThan(0.5));
      expect(theme.tileBorder.a, lessThan(0.5));
    });
  });
}
