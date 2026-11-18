// Gen V2 gate G7 (docs/GEN_V2_PLAN.md): who gets V2, and the served cache
// never mixes versions.
import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    LevelManager.genV2FromLevel.clear();
    LevelManager.genV2UntilLevel.clear();
    LevelManager.genV2DailyFromKey = LevelManager.kGenV2DailyFromKeyDefault;
    LevelManager.clearServedLevels();
  });

  group('resolveGenV2FromLevel', () {
    test('fresh install gets V2 from level 1', () {
      expect(
          LevelManager.resolveGenV2FromLevel(
              stored: null, highestUnlocked: 1, hasProgress: false),
          1);
    });

    test('existing player keeps V1 on every unlocked level', () {
      expect(
          LevelManager.resolveGenV2FromLevel(
              stored: null, highestUnlocked: 40, hasProgress: true),
          41);
      // Stars on level 1 only: level 1 was seen, so it stays V1.
      expect(
          LevelManager.resolveGenV2FromLevel(
              stored: null, highestUnlocked: 1, hasProgress: true),
          2);
    });

    test('a stored cut-over is never recomputed', () {
      expect(
          LevelManager.resolveGenV2FromLevel(
              stored: 12, highestUnlocked: 90, hasProgress: true),
          12);
    });
  });

  group('rollback switch (GEN_V2_ENABLED=false)', () {
    test('release builds ship with V2 on', () {
      expect(LevelManager.kGenV2Enabled, isTrue);
    });

    test('V2 on and nothing stored: no upper bound', () {
      expect(
          LevelManager.resolveGenV2UntilLevel(
              enabled: true, stored: null, from: 1, highestUnlocked: 30),
          isNull);
    });

    test('V2 off freezes V2 at the frontier the player reached', () {
      // Fresh-install V2 player at L30: L1-30 keep V2, L31+ go back to V1.
      expect(
          LevelManager.resolveGenV2UntilLevel(
              enabled: false, stored: null, from: 1, highestUnlocked: 30),
          30);
      // Upgraded player (V2 from L41) who has not reached L41 yet: no V2.
      expect(
          LevelManager.resolveGenV2UntilLevel(
              enabled: false, stored: null, from: 41, highestUnlocked: 40),
          40);
    });

    test('a stored bound wins, even after V2 is turned back on', () {
      expect(
          LevelManager.resolveGenV2UntilLevel(
              enabled: true, stored: 30, from: 1, highestUnlocked: 80),
          30);
      expect(
          LevelManager.resolveGenV2UntilLevel(
              enabled: false, stored: 0, from: 1, highestUnlocked: 80),
          0);
    });

    test('generationVersionFor honours the bound', () {
      LevelManager.genV2FromLevel[DifficultyMode.hard] = 10;
      LevelManager.genV2UntilLevel[DifficultyMode.hard] = 20;
      expect(LevelManager.generationVersionFor(9, DifficultyMode.hard), 1);
      expect(LevelManager.generationVersionFor(10, DifficultyMode.hard), 2);
      expect(LevelManager.generationVersionFor(20, DifficultyMode.hard), 2);
      expect(LevelManager.generationVersionFor(21, DifficultyMode.hard), 1);
      // An empty range (until < from) is V1 everywhere.
      LevelManager.genV2UntilLevel[DifficultyMode.hard] = 9;
      expect(LevelManager.generationVersionFor(10, DifficultyMode.hard), 1);
    });
  });

  test('no cut-over set means V1 everywhere', () {
    expect(LevelManager.generationVersionFor(1, DifficultyMode.hard), 1);
    expect(LevelManager.generationVersionFor(999, DifficultyMode.hard), 1);
  });

  test('V1 below the cut-over, V2 at and above it, per mode', () {
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 10;
    expect(LevelManager.generationVersionFor(9, DifficultyMode.hard), 1);
    expect(LevelManager.generationVersionFor(10, DifficultyMode.hard), 2);
    expect(LevelManager.generationVersionFor(10, DifficultyMode.medium), 1);
  });

  test('getLevel serves V1 below the cut-over and V2 above it', () {
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 10;
    final v1 = LevelManager.getLevel(9, mode: DifficultyMode.hard);
    final v2 = LevelManager.getLevel(10, mode: DifficultyMode.hard);
    expect(v1.gridWidth, 8, reason: 'V1 Hard is 8 wide');
    expect(v2.gridWidth, 7, reason: 'V2 Hard is a 7-wide portrait frame');
    expect(v2.gridHeight, greaterThanOrEqualTo(9));
    expect(v2.nodes.length, greaterThanOrEqualTo(28));
  });

  test('served cache never mixes versions', () {
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 10;
    final asV2 = LevelManager.getLevel(10, mode: DifficultyMode.hard);
    expect(asV2.gridWidth, 7);
    // Same level, same session, cut-over moved: must regenerate as V1.
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 11;
    final asV1 = LevelManager.getLevel(10, mode: DifficultyMode.hard);
    expect(asV1.gridWidth, 8);
    // And back: the V2 board is served from cache, unchanged.
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 10;
    expect(identical(LevelManager.getLevel(10, mode: DifficultyMode.hard), asV2),
        isTrue);
  });

  test('a V2 board does not depend on what was played before it', () {
    LevelManager.genV2FromLevel[DifficultyMode.hard] = 1;
    final first = LevelManager.getLevel(12, mode: DifficultyMode.hard);
    // Play other levels (grows the shared ledger), drop the session cache as
    // an app restart would, and ask again.
    for (var id = 1; id <= 6; id++) {
      LevelManager.getLevel(id, mode: DifficultyMode.hard);
      LevelManager.getLevel(id, mode: DifficultyMode.easy);
    }
    LevelManager.clearServedLevels();
    final again = LevelManager.getLevel(12, mode: DifficultyMode.hard);
    expect([for (final n in again.nodes) '${n.x},${n.y},${n.dir},${n.kind}'],
        [for (final n in first.nodes) '${n.x},${n.y},${n.dir},${n.kind}']);
    expect(again.playCells, first.playCells);
  });

  test('Daily: past dates keep V1, dates from the cut-over get V2', () {
    LevelManager.genV2DailyFromKey = 20261201;
    expect(LevelManager.dailyGenerationVersionFor(20261130), 1);
    expect(LevelManager.dailyGenerationVersionFor(20261201), 2);
    LevelManager.genV2DailyFromKey = null;
    expect(LevelManager.dailyGenerationVersionFor(20300101), 1);
  });

  test('Daily V2 board is deterministic and dense', () {
    LevelManager.genV2DailyFromKey = 20261201;
    final a = LevelManager.getDailyChallenge(DateTime(2026, 12, 3));
    final b = LevelManager.getDailyChallenge(DateTime(2026, 12, 3));
    expect(a.nodes.length, b.nodes.length);
    expect([for (final n in a.nodes) '${n.x},${n.y},${n.dir}'],
        [for (final n in b.nodes) '${n.x},${n.y},${n.dir}']);
    expect(a.gridWidth, 7);
  });
}
