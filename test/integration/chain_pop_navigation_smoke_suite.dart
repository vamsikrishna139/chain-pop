// Shared ChainPop smoke: menu → level select → Easy level 1 [GameScreen].
//
// Caller must supply [beforeAll] (e.g. [bootstrapChainPop] from `main.dart`).
// Requires a plugin-capable embedding (`integration_test/` with `-d`); menus use
// real [GameAudioController] — not runnable under headless VM tests.

import 'package:chain_pop/main.dart';
import 'package:chain_pop/models/game_settings.dart';
import 'package:chain_pop/screens/game_screen.dart';
import 'package:chain_pop/screens/level_select_screen.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpFrames(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void registerChainPopNavigationSmoke({
  required Future<void> Function() beforeAll,
}) {
  setUpAll(() async => beforeAll());

  setUp(() async {
    await StorageService.clearProgress();
    await StorageService.saveGameSettings(
      const GameSettings(soundEnabled: false, hapticsEnabled: false),
    );
  });

  testWidgets('main menu → Play → level select → Easy level 1 game', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ChainPopApp());

    await _pumpFrames(tester, frames: 45);

    expect(find.text('Difficulty'), findsOneWidget);
    final play = find.text('Play');
    expect(play, findsOneWidget);
    await tester.ensureVisible(play.first);
    await tester.tap(play);
    await _pumpFrames(tester, frames: 45);

    expect(find.byType(LevelSelectScreen), findsOneWidget);

    await tester.tap(find.text('1\u201320'));
    await _pumpFrames(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(LevelSelectScreen),
        matching: find.text('1'),
      ).first,
    );
    await _pumpFrames(tester);

    final level1Card = find.descendant(
      of: find.byType(LevelSelectScreen),
      matching: find.bySemanticsLabel(RegExp(r'Level 1,')),
    );
    expect(level1Card, findsWidgets);
    await tester.ensureVisible(level1Card.first);
    await tester.tap(level1Card.first);
    await _pumpFrames(tester);

    expect(find.byType(GameScreen), findsOneWidget);
  });
}
