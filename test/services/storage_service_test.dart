import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('chain_pop_storage_test_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  setUp(() async {
    await StorageService.clearProgress();
  });

  group('StorageService', () {
    test('selectedDifficulty defaults to easy', () {
      expect(StorageService.selectedDifficulty, DifficultyMode.easy);
    });

    test('setSelectedDifficulty persists', () async {
      await StorageService.setSelectedDifficulty(DifficultyMode.hard);
      expect(StorageService.selectedDifficulty, DifficultyMode.hard);
      await StorageService.setSelectedDifficulty(DifficultyMode.medium);
      expect(StorageService.selectedDifficulty, DifficultyMode.medium);
    });

    test('highestUnlocked defaults to 1 and unlockLevel raises cap', () async {
      expect(StorageService.highestUnlocked(DifficultyMode.easy), 1);
      await StorageService.unlockLevel(DifficultyMode.easy, 5);
      expect(StorageService.highestUnlocked(DifficultyMode.easy), 5);
      await StorageService.unlockLevel(DifficultyMode.easy, 3);
      expect(StorageService.highestUnlocked(DifficultyMode.easy), 5);
      await StorageService.unlockLevel(DifficultyMode.easy, 8);
      expect(StorageService.highestUnlocked(DifficultyMode.easy), 8);
    });

    test('stars only increase when higher', () async {
      expect(StorageService.stars(DifficultyMode.medium, 1), 0);
      await StorageService.saveStars(DifficultyMode.medium, 1, 2);
      expect(StorageService.stars(DifficultyMode.medium, 1), 2);
      await StorageService.saveStars(DifficultyMode.medium, 1, 1);
      expect(StorageService.stars(DifficultyMode.medium, 1), 2);
      await StorageService.saveStars(DifficultyMode.medium, 1, 3);
      expect(StorageService.stars(DifficultyMode.medium, 1), 3);
    });

    test('per-mode isolation for unlock and stars', () async {
      await StorageService.unlockLevel(DifficultyMode.hard, 10);
      await StorageService.saveStars(DifficultyMode.hard, 2, 3);
      expect(StorageService.highestUnlocked(DifficultyMode.easy), 1);
      expect(StorageService.stars(DifficultyMode.easy, 2), 0);
      expect(StorageService.highestUnlocked(DifficultyMode.hard), 10);
      expect(StorageService.stars(DifficultyMode.hard, 2), 3);
    });

    test('clearProgressForMode leaves other modes intact', () async {
      await StorageService.setSelectedDifficulty(DifficultyMode.hard);
      await StorageService.unlockLevel(DifficultyMode.easy, 4);
      await StorageService.unlockLevel(DifficultyMode.medium, 7);
      await StorageService.clearProgressForMode(DifficultyMode.easy);
      expect(StorageService.highestUnlocked(DifficultyMode.easy), 1);
      expect(StorageService.highestUnlocked(DifficultyMode.medium), 7);
      expect(StorageService.selectedDifficulty, DifficultyMode.hard);
    });

    test('highestUnlockedLevel follows selected difficulty', () async {
      await StorageService.setSelectedDifficulty(DifficultyMode.medium);
      await StorageService.unlockLevel(DifficultyMode.medium, 12);
      expect(StorageService.highestUnlockedLevel, 12);
    });
  });
}
