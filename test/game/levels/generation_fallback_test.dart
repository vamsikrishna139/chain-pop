// W2.5 — graceful generation failure (audit P2-5/6/7).
//
// Before: a failed generation hit `assert(false)` (crashing debug builds) and
// shipped a one-node board in release, with no test reaching either path and
// nothing reported. Layout validation was assert-only, so release never ran it.
// After: failures are reported through `LevelManager.onGenerationFallback` and
// the player gets a real board.
library;

import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/game/levels/level_solver.dart';
import 'package:flutter_test/flutter_test.dart';

/// A generator whose campaign path always fails, or always ships [bad].
class _BrokenGenerator extends LevelGenerator {
  _BrokenGenerator({this.bad});

  final LevelData? bad;

  @override
  Result<LevelData, GenerationError> generate(
    int levelId, {
    DifficultyMode? mode,
    Duration? timeBudget,
  }) =>
      bad != null
          ? Result.success(bad!)
          : Result.error(GenerationError.noValidDirections('forced'));
}

void main() {
  final reports = <(String, int, String)>[];

  setUp(() {
    reports.clear();
    LevelManager.onGenerationFallback = (k, id, r) => reports.add((k, id, r));
  });

  tearDown(() {
    LevelManager.onGenerationFallback = null;
    LevelManager.generator = LevelGenerator.neutral();
  });

  test('generateFromConfiguration reaches the exhausted error', () {
    // P2-7: no test used to drive this return.
    final r = LevelGenerator.neutral().generateFromConfiguration(
      LevelConfiguration.fromLevelId(10, mode: DifficultyMode.medium),
      primarySeed: 10,
      maxAttempts: 0,
    );
    expect(r.isSuccess, isFalse);
    expect(r.error.message, contains('Director exhausted 0 attempts'));
  });

  test('a failed campaign level ships a real board and is reported', () {
    LevelManager.generator = _BrokenGenerator();

    final level = LevelManager.getLevel(42, mode: DifficultyMode.hard);

    expect(level.levelId, 42);
    expect(level.nodes.length, greaterThan(1),
        reason: 'the fallback used to be a one-tap, one-node board');
    expect(LevelData.layoutValidationMessage(level), isNull);
    expect(LevelSolver.isSolvable(level), isTrue);
    expect(reports, hasLength(1));
    expect(reports.single.$1, 'campaign');
    expect(reports.single.$2, 42);
    expect(reports.single.$3, contains('forced'));
  });

  test('an invalid layout is caught in release-style flow, not shipped', () {
    // Two nodes on the same cell: exactly what the old assert-only check let
    // through in release.
    final bad = LevelData(
      levelId: 7,
      gridWidth: 4,
      gridHeight: 4,
      nodes: [
        NodeData(id: 0, x: 1, y: 1, dir: Direction.up),
        NodeData(id: 1, x: 1, y: 1, dir: Direction.left),
      ],
    );
    LevelManager.generator = _BrokenGenerator(bad: bad);

    final level = LevelManager.getLevel(7, mode: DifficultyMode.easy);

    expect(identical(level, bad), isFalse);
    expect(LevelData.layoutValidationMessage(level), isNull);
    expect(reports.single.$3, startsWith('invalid layout'));
  });

  for (final mode in DifficultyMode.values) {
    test('fallbackLevel is a valid, solvable ${mode.name} board', () {
      final level = LevelManager.fallbackLevel(901, mode: mode);
      expect(level.levelId, 901);
      expect(level.nodes.length, greaterThan(1));
      expect(LevelData.layoutValidationMessage(level), isNull);
      expect(LevelSolver.isSolvable(level), isTrue);
    });
  }

  test('a healthy Daily reports nothing', () {
    LevelManager.getDailyChallenge(DateTime(2026, 9, 1));
    expect(reports, isEmpty);
  });
}
