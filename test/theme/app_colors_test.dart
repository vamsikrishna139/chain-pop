import 'package:chain_pop/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors', () {
    test('node palettes have six slots (generation colorSlot range)', () {
      expect(AppColors.nodePalette, hasLength(6));
      expect(AppColors.nodePaletteColorblind, hasLength(6));
    });

    test('matchNodePaletteIndex returns exact index for palette colors', () {
      for (var i = 0; i < AppColors.nodePalette.length; i++) {
        expect(AppColors.matchNodePaletteIndex(AppColors.nodePalette[i]), i);
      }
    });

    test('matchNodePaletteIndex picks nearest for off-palette colors', () {
      // Midway between slot 0 and 1 in RGB — should resolve to one of them.
      const between = Color(0xFF30F7C3);
      final idx = AppColors.matchNodePaletteIndex(between);
      expect(idx, inInclusiveRange(0, AppColors.nodePalette.length - 1));
      final chosen = AppColors.nodePalette[idx];
      final dr = between.r - chosen.r;
      final dg = between.g - chosen.g;
      final db = between.b - chosen.b;
      final dist = dr * dr + dg * dg + db * db;
      for (final p in AppColors.nodePalette) {
        final d = (between.r - p.r) * (between.r - p.r) +
            (between.g - p.g) * (between.g - p.g) +
            (between.b - p.b) * (between.b - p.b);
        expect(dist, lessThanOrEqualTo(d + 1e-9));
      }
    });

    test('nodeDefault matches a palette entry', () {
      final idx = AppColors.matchNodePaletteIndex(AppColors.nodeDefault);
      expect(AppColors.nodePalette[idx], AppColors.nodeDefault);
    });
  });
}
