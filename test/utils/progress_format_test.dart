import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:chain_pop/utils/progress_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('ProgressFormat — pure formatters', () {
    test('level adds thousands separators', () {
      expect(ProgressFormat.level(0), '0');
      expect(ProgressFormat.level(1), '1');
      expect(ProgressFormat.level(18), '18');
      expect(ProgressFormat.level(1000), '1,000');
      expect(ProgressFormat.level(1018), '1,018');
      expect(ProgressFormat.level(1234567), '1,234,567');
    });

    test('starsCompact shortens large totals', () {
      expect(ProgressFormat.starsCompact(0), '0');
      expect(ProgressFormat.starsCompact(39), '39');
      expect(ProgressFormat.starsCompact(999), '999');
      expect(ProgressFormat.starsCompact(1200), '1.2k');
      expect(ProgressFormat.starsCompact(2847), '2.8k');
    });

    test('stretchWindow aligns to 20-level pages', () {
      expect(ProgressFormat.stretchWindow(1), (start: 1, end: 20));
      expect(ProgressFormat.stretchWindow(20), (start: 1, end: 20));
      expect(ProgressFormat.stretchWindow(21), (start: 21, end: 40));
      expect(ProgressFormat.stretchWindow(1000), (start: 981, end: 1000));
      expect(ProgressFormat.stretchWindow(1018), (start: 1001, end: 1020));
    });

    test('avgStarsPerClearedStage', () {
      expect(ProgressFormat.avgStarsPerClearedStage(0, 0), isNull);
      expect(ProgressFormat.avgStarsPerClearedStage(54, 18), closeTo(3.0, 0.001));
      expect(ProgressFormat.avgStarsPerClearedStage(36, 18), closeTo(2.0, 0.001));
    });
  });

  group('ProgressFormat.stretchStars', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() async {
      final tempDir = await Directory.systemTemp.createTemp('progress_fmt_');
      Hive.init(tempDir.path);
      await StorageService.init();
    });

    setUp(() async {
      await StorageService.clearProgress();
    });

    test('counts only stars from stretch start through frontier', () async {
      await StorageService.unlockLevel(DifficultyMode.easy, 25);
      for (var i = 1; i <= 25; i++) {
        await StorageService.saveStars(DifficultyMode.easy, i, 3);
      }
      final s = ProgressFormat.stretchStars(DifficultyMode.easy, 25);
      // Window 21–40, frontier 25 → levels 21–25 → 5 levels → cap 15
      expect(s.cap, 15);
      expect(s.earned, 15);
    });
  });
}
