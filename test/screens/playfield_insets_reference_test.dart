// Derives the **real** playfield-band insets the running app applies, by
// pumping a real [GameScreen] at the two reference device sizes and reading
// back what [GamePlayfieldInsetController.syncFromHud] handed to the engine.
//
// This exists because the board report harness (board_report_utils.dart) used
// to assume the [ChainPopGame] constructor defaults (140/92), which are only
// placeholders until the first post-frame HUD measurement lands. The numbers
// printed here are the source of truth for `kRefTopReserved*` /
// `kRefBottomReserved*` in that harness; the test asserts they stay in sync so
// the corpus cannot silently drift away from the shipped layout again.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/services/ads/no_op_ad_service.dart';
import 'package:chain_pop/services/game_audio.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../game/levels/generation/board_report_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir =
        await Directory.systemTemp.createTemp('chain_pop_insets_ref_');
    Hive.init(tempDir.path);
    await StorageService.init();
  });

  // (logical w, logical h, dpr, safeTop, safeBottom, label, expected consts)
  final devices =
      <(double, double, double, double, double, String, double, double)>[
    (
      390,
      844,
      3.0,
      47,
      34,
      'iPhone 14 (390x844)',
      kRefTopReserved,
      kRefBottomReserved
    ),
    (
      430,
      932,
      3.0,
      59,
      34,
      'iPhone 15 Pro Max (430x932)',
      kRefTopReservedLarge,
      kRefBottomReservedLarge
    ),
  ];

  for (final (w, h, dpr, safeTop, safeBottom, label, expTop, expBottom)
      in devices) {
    testWidgets('reference insets — $label', (tester) async {
      tester.view.physicalSize = Size(w * dpr, h * dpr);
      tester.view.devicePixelRatio = dpr;
      tester.view.padding = FakeViewPadding(
        top: safeTop * dpr,
        bottom: safeBottom * dpr,
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            level: 120,
            difficulty: DifficultyMode.hard,
            adService: NoOpAdService(),
            audioHandleFactory: SilentGameAudioHandle.new,
          ),
        ),
      );
      // Let the level generate and the post-frame HUD measurement land.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      final state = tester.state<GameScreenState>(find.byType(GameScreen));
      final engine = state.engine;
      final top = engine.topReserved;
      final bottom = engine.bottomReserved;
      final bandW = w - 2 * kRefMargin;
      final bandH = h - top - bottom - kRefMargin;

      print('  $label: safeTop=$safeTop safeBottom=$safeBottom '
          '=> topReserved=${top.toStringAsFixed(1)} '
          'bottomReserved=${bottom.toStringAsFixed(1)} '
          '=> band ${bandW.toStringAsFixed(1)}x${bandH.toStringAsFixed(1)}');

      expect(top, greaterThan(0));
      expect(bottom, greaterThan(0));
      // Guard: the harness constants must track the shipped layout. If this
      // fails, the HUD changed — update board_report_utils.dart to the printed
      // values and re-baseline the corpus.
      expect(top, closeTo(expTop, 1.0),
          reason: 'kRefTopReserved for $label is stale');
      expect(bottom, closeTo(expBottom, 1.0),
          reason: 'kRefBottomReserved for $label is stale');
    });
  }
}
