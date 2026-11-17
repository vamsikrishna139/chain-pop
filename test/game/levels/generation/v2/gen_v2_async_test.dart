// Gen V2 campaign boards off the UI thread: LevelManager.getLevelAsync, plus
// the reset path that must restore the V2 cut-over without a restart.
import 'dart:io';
import 'dart:isolate';

import 'package:chain_pop/game/levels/generation/generation.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/services/storage/local_progress_reset.dart';
import 'package:chain_pop/services/storage/storage_locator.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'board_fingerprint.dart';

/// The Gen V2 Hard board for [id], built directly from the generator.
LevelData _v2Reference(int id) => LevelGenerator.neutral()
    .generate(
      id,
      mode: DifficultyMode.hard,
      workBudget: LevelManager.genV2WorkBudget,
      generationVersion: 2,
    )
    .value;

void main() {
  tearDown(() {
    LevelManager.genV2FromLevel.clear();
    LevelManager.clearServedLevels();
    LevelManager.onGenerationFallback = null;
  });

  group('getLevelAsync', () {
    test('builds the same V2 board as getLevel', () async {
      LevelManager.genV2FromLevel[DifficultyMode.hard] = 1;
      for (final id in [1, 37, 400, 950]) {
        LevelManager.clearServedLevels();
        final viaAsync =
            await LevelManager.getLevelAsync(id, mode: DifficultyMode.hard);
        LevelManager.clearServedLevels();
        final viaSync = LevelManager.getLevel(id, mode: DifficultyMode.hard);
        expect(boardFingerprint(viaAsync), boardFingerprint(viaSync),
            reason: 'Hard L$id differs between async and sync');
        expect(boardFingerprint(viaAsync), boardFingerprint(_v2Reference(id)),
            reason: 'Hard L$id should be the V2 board');
      }
    });

    test('serves from the cache, shared with getLevel', () async {
      LevelManager.genV2FromLevel[DifficultyMode.hard] = 1;
      final first =
          await LevelManager.getLevelAsync(12, mode: DifficultyMode.hard);
      final again =
          await LevelManager.getLevelAsync(12, mode: DifficultyMode.hard);
      final sync = LevelManager.getLevel(12, mode: DifficultyMode.hard);
      expect(identical(first, again), isTrue);
      expect(identical(first, sync), isTrue);
    });

    test('a level getLevel already served is not regenerated', () async {
      LevelManager.genV2FromLevel[DifficultyMode.hard] = 1;
      final sync = LevelManager.getLevel(5, mode: DifficultyMode.hard);
      final viaAsync =
          await LevelManager.getLevelAsync(5, mode: DifficultyMode.hard);
      expect(identical(sync, viaAsync), isTrue);
    });

    test('below the cut-over it serves the V1 board in place', () async {
      LevelManager.genV2FromLevel[DifficultyMode.hard] = 10;
      final v1 = await LevelManager.getLevelAsync(9, mode: DifficultyMode.hard);
      expect(boardFingerprint(v1), isNot(boardFingerprint(_v2Reference(9))));
      expect(identical(v1, LevelManager.getLevel(9, mode: DifficultyMode.hard)),
          isTrue);
    });

    test('a fallback is reported on the calling isolate and not cached',
        () async {
      // Level ids must be non-negative, so V2 generation fails for -1.
      LevelManager.genV2FromLevel[DifficultyMode.hard] = -1;
      final caller = Isolate.current.hashCode;
      final reports = <(String, int, int)>[];
      LevelManager.onGenerationFallback = (kind, id, reason) =>
          reports.add((kind, id, Isolate.current.hashCode));

      final level =
          await LevelManager.getLevelAsync(-1, mode: DifficultyMode.hard);
      expect(level.levelId, -1);
      expect(level.nodes, isNotEmpty, reason: 'a playable fallback board');
      expect(reports, [('campaign', -1, caller)]);

      // Not cached: the next visit tries (and here reports) again.
      await LevelManager.getLevelAsync(-1, mode: DifficultyMode.hard);
      expect(reports, hasLength(2));
    });
  });

  group('prefetchLevel', () {
    test('caches the same board getLevel builds; a later open joins it',
        () async {
      LevelManager.genV2FromLevel[DifficultyMode.hard] = 1;
      expect(LevelManager.cachedLevel(21, mode: DifficultyMode.hard), isNull);

      LevelManager.prefetchLevel(21, mode: DifficultyMode.hard);
      // Opening the level while the prefetch runs waits for that same build.
      final opened =
          await LevelManager.getLevelAsync(21, mode: DifficultyMode.hard);
      final cached = LevelManager.cachedLevel(21, mode: DifficultyMode.hard);
      expect(identical(opened, cached), isTrue);
      expect(boardFingerprint(opened), boardFingerprint(_v2Reference(21)));
    });

    test('two concurrent opens share one build', () async {
      LevelManager.genV2FromLevel[DifficultyMode.hard] = 1;
      final a = LevelManager.getLevelAsync(33, mode: DifficultyMode.hard);
      final b = LevelManager.getLevelAsync(33, mode: DifficultyMode.hard);
      expect(identical(await a, await b), isTrue);
    });

    test('never prefetches V1 boards (shared diversity ledger)', () async {
      LevelManager.genV2FromLevel[DifficultyMode.hard] = 50;
      final ledgerBefore =
          LevelManager.generator.diversityLedger.serialize().toString();
      LevelManager.prefetchLevel(10, mode: DifficultyMode.hard);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(LevelManager.cachedLevel(10, mode: DifficultyMode.hard), isNull);
      expect(LevelManager.generator.diversityLedger.serialize().toString(),
          ledgerBefore);
    });
  });

  group('resetLocalProgress', () {
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('chain_pop_reset_v2_');
      Hive.init(dir.path);
      await StorageService.init();
    });

    test('restores V2 from level 1 in every mode, with no restart', () async {
      // An existing player who updated at Hard 50: V2 from L51.
      for (final mode in DifficultyMode.values) {
        LevelManager.genV2FromLevel[mode] = 51;
        await StorageService.saveGenV2FromLevel(mode, 51);
      }
      expect(LevelManager.generationVersionFor(1, DifficultyMode.hard), 1);
      final v2L1 = boardFingerprint(_v2Reference(1));
      final before = LevelManager.getLevel(1, mode: DifficultyMode.hard);
      expect(boardFingerprint(before), isNot(v2L1));

      await resetLocalProgress();

      for (final mode in DifficultyMode.values) {
        expect(LevelManager.genV2FromLevel[mode], 1, reason: mode.name);
        expect(StorageLocator.instance.genV2FromLevel(mode), 1,
            reason: '${mode.name} stored cut-over');
      }
      final after = LevelManager.getLevel(1, mode: DifficultyMode.hard);
      expect(boardFingerprint(after), v2L1,
          reason: 'Hard L1 is V2 right after reset');
    });
  });
}
