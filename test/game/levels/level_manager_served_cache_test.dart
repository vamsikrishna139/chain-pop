import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(LevelManager.clearServedLevels);
  tearDown(LevelManager.clearServedLevels);

  test('re-entering a level serves the same board', () {
    final first = LevelManager.getLevel(37, mode: DifficultyMode.medium);
    // Another level in between would move the diversity ledger.
    LevelManager.getLevel(38, mode: DifficultyMode.medium);
    final again = LevelManager.getLevel(37, mode: DifficultyMode.medium);
    expect(identical(again, first), isTrue);
  });

  test('modes do not share boards', () {
    final easy = LevelManager.getLevel(12, mode: DifficultyMode.easy);
    final hard = LevelManager.getLevel(12, mode: DifficultyMode.hard);
    expect(identical(easy, hard), isFalse);
  });

  test('the cache is bounded', () {
    final first = LevelManager.getLevel(1, mode: DifficultyMode.easy);
    for (var i = 2; i <= LevelManager.servedCacheCapacity + 1; i++) {
      LevelManager.getLevel(i, mode: DifficultyMode.easy);
    }
    // Level 1 was evicted, so it is generated afresh.
    final regenerated = LevelManager.getLevel(1, mode: DifficultyMode.easy);
    expect(identical(regenerated, first), isFalse);
  });
}
